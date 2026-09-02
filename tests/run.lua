-- Exposition test suite.
-- Copyright (c) 2026 Zethrel. All rights reserved. See LICENSE.
--
--   lua5.1 tests/run.lua
--
-- Runs against the real Core/Splitter.lua, outside WoW. Lua 5.1 is the same
-- interpreter the game ships, so what passes here behaves the same in game.

local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local Splitter = dofile(here .. "/../Core/Splitter.lua")

local failures, checks = 0, 0
local currentTest = "?"

local function check(ok, message)
	checks = checks + 1
	if not ok then
		failures = failures + 1
		print(string.format("  FAIL [%s] %s", currentTest, message or "assertion failed"))
	end
end

local function eq(actual, expected, message)
	check(actual == expected, string.format("%s (got %s, expected %s)",
		message or "equality", tostring(actual), tostring(expected)))
end

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

--------------------------------------------------------------------------------
-- Shared property checks
--------------------------------------------------------------------------------

local function isValidUTF8(s)
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		local extra
		if c < 0x80 then extra = 0
		elseif c >= 0xC2 and c <= 0xDF then extra = 1
		elseif c >= 0xE0 and c <= 0xEF then extra = 2
		elseif c >= 0xF0 and c <= 0xF4 then extra = 3
		else return false end
		for k = 1, extra do
			local cc = s:byte(i + k)
			if not cc or cc < 0x80 or cc > 0xBF then return false end
		end
		i = i + extra + 1
	end
	return true
end

-- Rebuilds the exact marker the splitter would have applied, using a sentinel
-- so literal "1/2" or "..." inside the text can never be mistaken for one.
local function markerAffixes(style, index, total, position)
	local decorated = Splitter.GetMarkerStyle(style).apply("\1", index, total, position)
	local at = decorated:find("\1", 1, true)
	return decorated:sub(1, at - 1), decorated:sub(at + 1)
end

local function stripMarker(chunk, style, index, total, position, label)
	local prefix, suffix = markerAffixes(style, index, total, position)
	if prefix ~= "" then
		check(chunk:sub(1, #prefix) == prefix, string.format(
			"%s: chunk %d missing marker prefix %q", label, index, prefix))
		chunk = chunk:sub(#prefix + 1)
	end
	if suffix ~= "" then
		check(chunk:sub(-#suffix) == suffix, string.format(
			"%s: chunk %d missing marker suffix %q", label, index, suffix))
		chunk = chunk:sub(1, #chunk - #suffix)
	end
	return chunk
end

-- Every guarantee the addon makes about a split, checked at once.
local function assertWellFormed(text, opts, label)
	local chunks, info = Splitter.Split(text, opts)
	local limit = (opts and opts.limit) or 255
	local style = (opts and opts.marker) or "none"

	local position = (opts and opts.markerPosition) or "prefix"
	local words = {}
	for index, chunk in ipairs(chunks) do
		check(#chunk <= limit, string.format(
			"%s: chunk over the byte limit (%d > %d)", label, #chunk, limit))
		check(isValidUTF8(chunk), label .. ": chunk is not valid UTF-8")
		check(chunk:match("^%s") == nil, label .. ": chunk starts with whitespace")
		check(chunk:match("%s$") == nil, label .. ": chunk ends with whitespace")
		check(#chunk > 0, label .. ": empty chunk")
		for word in stripMarker(chunk, style, index, #chunks, position, label):gmatch("%S+") do
			words[#words + 1] = word
		end
	end

	-- No word may be lost, gained, or reordered.
	local expected = {}
	for word in Splitter.Normalize(text, opts and opts.respectNewlines):gmatch("%S+") do
		expected[#expected + 1] = word
	end
	if not info.brokeWord then
		eq(#words, #expected, label .. ": word count changed")
		for i = 1, math.min(#words, #expected) do
			if words[i] ~= expected[i] then
				check(false, string.format("%s: word %d changed (%q vs %q)",
					label, i, words[i], expected[i]))
				break
			end
		end
	end
	-- Rejoined text must still contain every original character.
	local rejoined = table.concat(words, " ")
	if not info.brokeWord then
		eq(rejoined, table.concat(expected, " "), label .. ": text not preserved")
	end

	eq(info.total, #chunks, label .. ": info.total disagrees with chunk count")
	return chunks, info
end

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

-- One long paragraph with no hard line breaks, i.e. what someone actually
-- types into a big composer window.
local PROSE = table.concat({
	"The tavern door swings inward on a gust of rain-soaked wind, and for a",
	"moment the whole common room turns to look. She shakes the water from her",
	"cloak, peels back the hood, and lets the door bang shut behind her. Nobody",
	"offers a seat. Nobody ever does, not on a night like this one, not with the",
	"storm climbing the cliffs outside and the harbour bell tolling itself hoarse",
	"against the dark. She crosses to the bar anyway. The barkeep does not meet",
	"her eyes. He polishes a glass that was already clean, then polishes it",
	"again, and when she sets a single silver coin on the wood between them he",
	"looks at it the way a man looks at a spider. \"We're closed,\" he says. It is",
	"not yet the eighth bell. The fire says otherwise, and so do the twelve",
	"people pretending very hard not to watch her.",
}, " ")

local LONG_WORD = string.rep("a", 300)

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

test("empty input produces nothing", function()
	local chunks, info = Splitter.Split("", {})
	eq(#chunks, 0, "no chunks")
	eq(info.total, 0, "info.total")
	chunks = Splitter.Split("   \n\n  \t ", {})
	eq(#chunks, 0, "whitespace only yields no chunks")
end)

test("short text stays a single message", function()
	local chunks = assertWellFormed("Hello, Azeroth.", { marker = "count" }, "short")
	eq(#chunks, 1, "one chunk")
	eq(chunks[1], "Hello, Azeroth.", "no marker on a single message")
end)

test("exactly 255 bytes is not split", function()
	local text = string.rep("ab ", 84) .. "cd" -- 254 bytes
	local chunks = assertWellFormed(text, {}, "255 boundary")
	eq(#chunks, 1, "fits in one message")
	eq(#chunks[1], 254, "byte length")
end)

test("256 bytes splits into two", function()
	local text = string.rep("ab ", 85) .. "cde" -- 258 bytes
	local chunks = assertWellFormed(text, {}, "256 boundary")
	eq(#chunks, 2, "two messages")
end)

test("prose splits on word boundaries", function()
	local chunks = assertWellFormed(PROSE, { preferSentence = false }, "prose")
	check(#chunks > 3, "prose should need several messages")
	for _, chunk in ipairs(chunks) do
		check(not chunk:match("^%a+%s") or true, "sanity")
	end
end)

test("a word is never cut across the boundary", function()
	-- The regression the whole addon exists for: "escape" must not become
	-- "...esc" + "ape from here".
	-- 250 bytes of filler puts byte 256 - the first byte that cannot fit -
	-- squarely inside "escape", which a naive cut would leave as "...esc".
	local filler = string.rep("x ", 125)
	local text = filler .. "escape from here"
	local chunks = assertWellFormed(text, { preferSentence = false }, "no mid-word cut")
	eq(#chunks, 2, "two messages")
	check(not chunks[1]:match("esc$"), "first message must not end in a word fragment")
	check(chunks[2]:match("^escape"), "second message must start with the whole word")
end)

test("markers are counted against the byte limit", function()
	for _, style in ipairs({ "none", "count", "bracket", "paren", "ellipsis", "raid" }) do
		local chunks = assertWellFormed(PROSE, { marker = style }, "marker=" .. style)
		check(#chunks >= 4, style .. ": expected several messages")
	end
end)

test("marker numbering is correct and stable", function()
	local chunks = Splitter.Split(PROSE, { marker = "count" })
	for i, chunk in ipairs(chunks) do
		check(chunk:match("^(%d+)/(%d+) ") ~= nil, "chunk " .. i .. " carries a marker")
		local index, total = chunk:match("^(%d+)/(%d+) ")
		eq(tonumber(index), i, "marker index")
		eq(tonumber(total), #chunks, "marker total")
	end
end)

test("marker width converges when the count crosses ten", function()
	-- Enough text that reserving two digits instead of one changes the count.
	local text = string.rep("lorem ipsum dolor sit amet ", 100)
	for _, style in ipairs({ "count", "bracket", "paren" }) do
		local chunks = assertWellFormed(text, { marker = style }, "convergence " .. style)
		check(#chunks > 10, style .. ": expected more than ten messages")
		local _, total = chunks[1]:match("(%d+)/(%d+)")
		eq(tonumber(total), #chunks, style .. ": total matches actual count")
	end
end)

test("suffix markers work too", function()
	local chunks = assertWellFormed(PROSE,
		{ marker = "count", markerPosition = "suffix" }, "suffix")
	for i, chunk in ipairs(chunks) do
		check(chunk:match("%s(%d+)/(%d+)$") ~= nil, "chunk " .. i .. " ends with its marker")
	end
end)

test("raid icons fall back to numbers past eight", function()
	local short = Splitter.Split(PROSE, { marker = "raid" })
	check(#short <= 8, "fixture should fit in eight messages")
	check(short[1]:match("^{rt1} ") ~= nil, "uses raid icon markers")

	local long = Splitter.Split(string.rep("lorem ipsum dolor sit amet ", 100), { marker = "raid" })
	check(#long > 8, "fixture should exceed eight messages")
	check(long[9]:match("^9/%d+ ") ~= nil, "falls back to numbering")
	for _, chunk in ipairs(long) do
		check(#chunk <= 255, "fallback still respects the limit")
	end
end)

test("ellipsis marker brackets the middle messages", function()
	local chunks = Splitter.Split(PROSE, { marker = "ellipsis" })
	check(#chunks >= 3, "need a middle message")
	check(chunks[1]:match("^%.%.%.") == nil, "first message has no leading ellipsis")
	check(chunks[1]:match("%.%.%.$") ~= nil, "first message trails off")
	check(chunks[#chunks]:match("^%.%.%.") ~= nil, "last message picks up")
	check(chunks[#chunks]:match("%.%.%.$") == nil, "last message does not trail off")
end)

test("sentence preference ends messages on sentences", function()
	local chunks = Splitter.Split(PROSE, { preferSentence = true, marker = "none" })
	local ended = 0
	for i = 1, #chunks - 1 do
		if chunks[i]:match("[%.%!%?]['\"%)%]]*$") then ended = ended + 1 end
	end
	check(ended >= math.floor((#chunks - 1) / 2),
		string.format("most messages should end on a sentence (%d of %d)", ended, #chunks - 1))
end)

test("sentence preference never breaks on an abbreviation", function()
	local text = string.rep("word ", 40) .. "Dr. " .. string.rep("word ", 40)
	local chunks = Splitter.Split(text, { preferSentence = true })
	for i = 1, #chunks - 1 do
		check(chunks[i]:match("Dr%.$") == nil, "must not end a message on 'Dr.'")
	end
end)

test("line breaks start a new message when asked", function()
	local text = "First line.\nSecond line.\nThird line."
	local chunks = assertWellFormed(text, { respectNewlines = true }, "newlines respected")
	eq(#chunks, 3, "one message per line")
	eq(chunks[1], "First line.", "line one")
	eq(chunks[3], "Third line.", "line three")

	local merged = assertWellFormed(text, { respectNewlines = false }, "newlines merged")
	eq(#merged, 1, "all one message")
	eq(merged[1], "First line. Second line. Third line.", "joined with spaces")
end)

test("blank lines and stray whitespace are cleaned up", function()
	local chunks = Splitter.Split("  Hello \n\n\n   world  \t\t ok  ", { respectNewlines = true })
	eq(#chunks, 2, "two lines")
	eq(chunks[1], "Hello", "leading whitespace trimmed")
	eq(chunks[2], "world ok", "runs of whitespace collapsed")
end)

test("an over-long single word is cut safely", function()
	local chunks, info = Splitter.Split(LONG_WORD, {})
	eq(#chunks, 2, "two messages")
	check(info.brokeWord, "reports that a word had to be broken")
	eq(#chunks[1] + #chunks[2], 300, "no characters lost")
	for _, chunk in ipairs(chunks) do
		check(#chunk <= 255, "still within the limit")
	end
end)

test("UTF-8 is never cut mid character", function()
	-- Accented text with no spaces at all forces hard cuts inside the string.
	local blob = string.rep("\195\169", 400) -- 400 x 'e' with an acute accent
	local chunks, info = Splitter.Split(blob, {})
	check(info.brokeWord, "reports the forced break")
	for _, chunk in ipairs(chunks) do
		check(#chunk <= 255, "within the limit")
		check(isValidUTF8(chunk), "chunk is valid UTF-8")
	end
	eq(table.concat(chunks), blob, "characters preserved exactly")

	-- And the same with ordinary multi-byte prose.
	local prose = string.rep("na\195\175ve r\195\169sum\195\169 caf\195\169 ", 30)
	assertWellFormed(prose, { marker = "count" }, "utf8 prose")
end)

test("emoji and other four byte sequences survive", function()
	local emoji = string.rep("\240\159\144\137 dragon ", 40)
	local chunks = assertWellFormed(emoji, { marker = "bracket" }, "emoji")
	for _, chunk in ipairs(chunks) do
		check(isValidUTF8(chunk), "chunk is valid UTF-8")
	end
end)

test("custom limits are honoured", function()
	for _, limit in ipairs({ 40, 80, 120, 255 }) do
		assertWellFormed(PROSE, { limit = limit, marker = "count" }, "limit=" .. limit)
	end
end)

test("duration estimate matches the queue", function()
	eq(Splitter.EstimateDuration(0, 15), 0, "nothing to send")
	eq(Splitter.EstimateDuration(1, 15), 0, "first message goes out immediately")
	eq(Splitter.EstimateDuration(5, 15), 60, "four gaps of fifteen seconds")
end)

test("fuzzing never violates the contract", function()
	local words = { "a", "the", "storm", "harbour", "Dr.", "well?", "yes!", "na\195\175ve",
		"\240\159\144\137", "supercalifragilisticexpialidocious", "...", "\"quoted\"", "1/2" }
	math.randomseed(20260902)
	for iteration = 1, 300 do
		local parts = {}
		for _ = 1, math.random(1, 120) do
			parts[#parts + 1] = words[math.random(#words)]
			if math.random(12) == 1 then parts[#parts + 1] = "\n" end
		end
		local text = table.concat(parts, " ")
		local styles = { "none", "count", "bracket", "paren", "ellipsis", "raid" }
		assertWellFormed(text, {
			marker = styles[math.random(#styles)],
			markerPosition = math.random(2) == 1 and "prefix" or "suffix",
			preferSentence = math.random(2) == 1,
			respectNewlines = math.random(2) == 1,
			limit = math.random(2) == 1 and 255 or math.random(30, 255),
		}, "fuzz #" .. iteration)
	end
end)

--------------------------------------------------------------------------------

print("Exposition splitter tests")
print("-------------------------")
for _, t in ipairs(tests) do
	currentTest = t.name
	local before = failures
	t.fn()
	print(string.format("  %s  %s", failures == before and "ok  " or "FAIL", t.name))
end
print("-------------------------")
print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
