-- Exposition - Core/Splitter.lua
--
-- The chunking engine. Pure Lua: it touches no WoW API so it can be unit
-- tested outside the game (see tests/). Everything is byte oriented because
-- SendChatMessage limits messages by bytes, not by characters.

local _, ns = ...
ns = ns or {}

local Splitter = {}
ns.Splitter = Splitter

-- Blizzard truncates anything past this, silently.
Splitter.MAX_MESSAGE_BYTES = 255

local strbyte, strsub, strfind, strlen = string.byte, string.sub, string.find, string.len
local floor, max, min = math.floor, math.max, math.min

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local SPACE, TAB, LF, CR = 32, 9, 10, 13

local function isSpaceByte(b)
	return b == SPACE or b == TAB or b == LF or b == CR
end

-- Walks `e` backwards until s:sub(1, e) no longer ends inside a multi byte
-- UTF-8 sequence. Continuation bytes are 0x80..0xBF (128..191).
local function utf8SafeEnd(s, e)
	while e > 0 do
		local nextByte = strbyte(s, e + 1)
		if not nextByte or nextByte < 128 or nextByte >= 192 then
			return e
		end
		e = e - 1
	end
	return e
end

local function digits(n)
	return strlen(tostring(n))
end

local function trimRight(s)
	local trimmed = s:gsub("%s+$", "")
	return trimmed
end

--------------------------------------------------------------------------------
-- Marker styles
--
-- Each style knows two things:
--   reserve(total)  - worst case bytes a marker can add for a post of `total`
--                     messages, so the splitter can shrink its budget up front.
--   apply(...)      - decorate one finished chunk.
--------------------------------------------------------------------------------

local MarkerStyles = {}
Splitter.MarkerStyles = MarkerStyles

MarkerStyles.none = {
	reserve = function() return 0 end,
	apply = function(piece) return piece end,
}

local function affix(piece, marker, position)
	if position == "suffix" then
		return piece .. " " .. marker
	end
	return marker .. " " .. piece
end

MarkerStyles.count = {
	-- "12/25 "
	reserve = function(total) return total < 2 and 0 or digits(total) * 2 + 2 end,
	apply = function(piece, index, total, position)
		if total < 2 then return piece end
		return affix(piece, index .. "/" .. total, position)
	end,
}

MarkerStyles.bracket = {
	-- "[12/25] "
	reserve = function(total) return total < 2 and 0 or digits(total) * 2 + 4 end,
	apply = function(piece, index, total, position)
		if total < 2 then return piece end
		return affix(piece, "[" .. index .. "/" .. total .. "]", position)
	end,
}

MarkerStyles.paren = {
	-- "(12/25) "
	reserve = function(total) return total < 2 and 0 or digits(total) * 2 + 4 end,
	apply = function(piece, index, total, position)
		if total < 2 then return piece end
		return affix(piece, "(" .. index .. "/" .. total .. ")", position)
	end,
}

MarkerStyles.ellipsis = {
	-- "...text..." - a middle chunk pays for both ends.
	reserve = function(total) return total < 2 and 0 or 6 end,
	apply = function(piece, index, total)
		if total < 2 then return piece end
		if index > 1 then piece = "..." .. piece end
		if index < total then piece = piece .. "..." end
		return piece
	end,
}

MarkerStyles.raid = {
	-- "{rt1} " - only eight icons exist, so fall back to plain numbering.
	reserve = function(total)
		if total < 2 then return 0 end
		if total > 8 then return MarkerStyles.count.reserve(total) end
		return 7
	end,
	apply = function(piece, index, total, position)
		if total < 2 then return piece end
		if total > 8 then return MarkerStyles.count.apply(piece, index, total, position) end
		return affix(piece, "{rt" .. index .. "}", position)
	end,
}

function Splitter.GetMarkerStyle(key)
	return MarkerStyles[key or "none"] or MarkerStyles.none
end

--------------------------------------------------------------------------------
-- Sentence detection
--------------------------------------------------------------------------------

-- Words that end in a full stop without ending a sentence.
local ABBREVIATIONS = {
	mr = true, mrs = true, ms = true, dr = true, st = true, prof = true,
	sgt = true, capt = true, lt = true, gen = true, sr = true, jr = true,
	etc = true, vs = true, approx = true, no = true, fig = true, inc = true,
}

local function isAbbreviation(s, terminatorStart)
	local word = strsub(s, 1, terminatorStart - 1):match("([%a]+)$")
	if not word then return false end
	-- A lone letter is almost always an initial: "A. Smith".
	if strlen(word) == 1 then return true end
	return ABBREVIATIONS[word:lower()] or false
end

-- Index of the last byte of a sentence ending at or after `minEnd`, or nil.
local function lastSentenceEnd(s, minEnd)
	local best, init = nil, 1
	while true do
		local a, b = strfind(s, "[%.%!%?]+['\"%)%]]*", init)
		if not a then break end
		init = b + 1
		local following = strbyte(s, b + 1)
		if (following == nil or isSpaceByte(following))
			and b >= minEnd
			and not isAbbreviation(s, a)
		then
			best = b
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Text normalisation
--------------------------------------------------------------------------------

-- Chat messages cannot contain newlines, so they either become hard breaks
-- between messages or plain spaces.
function Splitter.Normalize(text, respectNewlines)
	text = text or ""
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	if not respectNewlines then
		text = text:gsub("\n", " ")
	end
	text = text:gsub("[ \t]+", " ")
	text = text:gsub(" *\n *", "\n")
	text = text:gsub("\n\n+", "\n")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return text
end

--------------------------------------------------------------------------------
-- The greedy packer
--------------------------------------------------------------------------------

-- Fills `out` with pieces of `s`, each at most `budget` bytes, never cutting a
-- word in half unless a single word is longer than the whole budget.
local function packParagraph(s, budget, out, preferSentence, sentenceWindow, stats)
	local pos, n = 1, strlen(s)

	while pos <= n do
		while pos <= n and isSpaceByte(strbyte(s, pos)) do
			pos = pos + 1
		end
		if pos > n then break end

		if n - pos + 1 <= budget then
			out[#out + 1] = trimRight(strsub(s, pos, n))
			return
		end

		-- Scan back from the first byte we may not keep, looking for the last
		-- space that still fits. Landing exactly on pos + budget is fine: it
		-- means the chunk is exactly `budget` bytes and the space is dropped.
		local cut, foundSpace
		local j = pos + budget
		while j > pos do
			if isSpaceByte(strbyte(s, j)) then
				foundSpace = j
				break
			end
			j = j - 1
		end

		if foundSpace then
			cut = foundSpace - 1
		else
			-- One unbroken word longer than a whole message. Nothing to do but
			-- cut it, at least without slicing a UTF-8 sequence in half.
			cut = utf8SafeEnd(s, pos + budget - 1)
			if cut < pos then cut = pos + budget - 1 end
			stats.brokeWord = true
		end

		local piece = strsub(s, pos, cut)

		if preferSentence and foundSpace then
			local minEnd = floor(budget * (1 - sentenceWindow))
			local sentence = lastSentenceEnd(piece, minEnd)
			if sentence then
				piece = strsub(piece, 1, sentence)
				cut = pos + sentence - 1
			end
		end

		piece = trimRight(piece)
		if piece == "" then
			-- Defensive: never loop forever on pathological input.
			pos = cut + 1
		else
			out[#out + 1] = piece
			pos = cut + 1
		end
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local DEFAULT_OPTIONS = {
	limit = 255,
	marker = "none",
	markerPosition = "prefix",
	preferSentence = true,
	respectNewlines = true,
	sentenceWindow = 0.35,
}

Splitter.DEFAULT_OPTIONS = DEFAULT_OPTIONS

local function option(opts, key)
	local value = opts and opts[key]
	if value == nil then return DEFAULT_OPTIONS[key] end
	return value
end

local function packAll(text, budget, preferSentence, sentenceWindow, stats)
	local out = {}
	if text == "" then return out end
	local from = 1
	while true do
		local nl = strfind(text, "\n", from, true)
		local paragraph = strsub(text, from, nl and nl - 1 or nil)
		if paragraph ~= "" then
			packParagraph(paragraph, budget, out, preferSentence, sentenceWindow, stats)
		end
		if not nl then break end
		from = nl + 1
	end
	return out
end

--- Splits `text` into ready to send chat messages.
-- @return chunks (array of strings), info table
function Splitter.Split(text, opts)
	local limit = option(opts, "limit")
	local markerKey = option(opts, "marker")
	local position = option(opts, "markerPosition")
	local preferSentence = option(opts, "preferSentence")
	local respectNewlines = option(opts, "respectNewlines")
	local sentenceWindow = option(opts, "sentenceWindow")

	local style = Splitter.GetMarkerStyle(markerKey)
	local normalized = Splitter.Normalize(text, respectNewlines)
	local stats = { brokeWord = false }

	if normalized == "" then
		return {}, { total = 0, bytes = 0, longest = 0, brokeWord = false, budget = limit }
	end

	-- Markers cost bytes, and their width depends on how many messages there
	-- are, which depends on the marker width. Iterate until it settles; the
	-- reserve only ever grows, so this converges in two or three passes.
	local total, chunks, budget = 1, nil, limit
	for _ = 1, 8 do
		local reserve = style.reserve(total)
		budget = max(limit - reserve, 16)
		stats.brokeWord = false
		chunks = packAll(normalized, budget, preferSentence, sentenceWindow, stats)
		if #chunks <= total then break end
		total = #chunks
	end

	local count = #chunks
	local longest = 0
	for i = 1, count do
		chunks[i] = style.apply(chunks[i], i, count, position)
		longest = max(longest, strlen(chunks[i]))
	end

	return chunks, {
		total = count,
		bytes = strlen(normalized),
		longest = longest,
		brokeWord = stats.brokeWord,
		budget = budget,
	}
end

--- Seconds a post will take to send, first message going out immediately.
function Splitter.EstimateDuration(count, delay)
	if not count or count < 2 then return 0 end
	return (count - 1) * (delay or 0)
end

return Splitter
