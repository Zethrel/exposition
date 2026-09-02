-- Exposition - Core/Config.lua
-- Copyright (c) 2026 Zethrel. All rights reserved. See LICENSE.
--
-- Saved settings, defaults, and the tables that describe the choices offered
-- in the UI.

local ADDON, ns = ...

ns.ADDON_NAME = ADDON

-- Chat throttling on the server side is unforgiving, and a disconnect halfway
-- through a post is worse than a slow post. Nothing is ever sent faster.
ns.MIN_DELAY = 0.75
ns.MAX_DELAY = 120

ns.DEFAULTS = {
	channel = "SAY",
	whisperTarget = "",
	channelTarget = "",
	delay = 15,
	marker = "none",
	markerPosition = "prefix",
	preferSentence = true,
	respectNewlines = true,
	confirmAbove = 8,
	keepTextAfterSending = true,
	draft = "",
	point = nil,
	width = 640,
	height = 660,
}

ns.CHANNELS = {
	{ key = "SAY",           label = "Say" },
	{ key = "EMOTE",         label = "Emote" },
	{ key = "YELL",          label = "Yell" },
	{ key = "PARTY",         label = "Party" },
	{ key = "RAID",          label = "Raid" },
	{ key = "INSTANCE_CHAT", label = "Instance" },
	{ key = "GUILD",         label = "Guild" },
	{ key = "OFFICER",       label = "Officer" },
	{ key = "WHISPER",       label = "Whisper", needs = "player" },
	{ key = "CHANNEL",       label = "Channel", needs = "channel" },
}

ns.MARKERS = {
	{
		key = "none", label = "None",
		tip = "No marker. Cleanest for immersive roleplay, but readers have to\nwork out the order themselves if messages arrive out of sequence.",
	},
	{
		key = "count", label = "1/5",
		tip = "Plain numbering: |cffffffff1/5|r\nCheap (four extra characters) and unambiguous.",
	},
	{
		key = "bracket", label = "[1/5]",
		tip = "Bracketed numbering: |cffffffff[1/5]|r\nStands apart from the prose a little more clearly.",
	},
	{
		key = "paren", label = "(1/5)",
		tip = "Parenthesised numbering: |cffffffff(1/5)|r\nReads as an aside rather than a label.",
	},
	{
		key = "ellipsis", label = "...",
		tip = "Trailing and leading ellipses: |cffffffffthe door...|r / |cffffffff...swings open|r\nNo numbers at all, just a hint that the thought continues.",
	},
	{
		key = "raid", label = "{rt1}",
		tip = "Raid target icons: |cffffffff{rt1} {rt2} {rt3}|r\n\n|cffff8080Careful:|r these are the same icons used for marking\ntargets, and many roleplayers read them as out-of-character\nchatter. Only the first eight are available; past that\nExposition falls back to plain numbering.",
	},
}

function ns.GetChannelInfo(key)
	for _, info in ipairs(ns.CHANNELS) do
		if info.key == key then return info end
	end
	return ns.CHANNELS[1]
end

function ns.Print(...)
	local text = table.concat({ ... }, " ")
	DEFAULT_CHAT_FRAME:AddMessage("|cff8ac6ffExposition|r: " .. text)
end

--- Copies missing defaults into the saved table without clobbering choices.
local function applyDefaults(db, defaults)
	for key, value in pairs(defaults) do
		if db[key] == nil then db[key] = value end
	end
	return db
end

function ns.LoadDB()
	ExpositionDB = applyDefaults(ExpositionDB or {}, ns.DEFAULTS)
	local db = ExpositionDB
	db.delay = math.max(0, math.min(ns.MAX_DELAY, tonumber(db.delay) or ns.DEFAULTS.delay))
	if not ns.Splitter.MarkerStyles[db.marker] then db.marker = "none" end
	ns.db = db
	return db
end

--- Options in the shape Splitter.Split expects.
function ns.SplitOptions()
	local db = ns.db
	return {
		limit = ns.Splitter.MAX_MESSAGE_BYTES,
		marker = db.marker,
		markerPosition = db.markerPosition,
		preferSentence = db.preferSentence,
		respectNewlines = db.respectNewlines,
	}
end

--- "1m 15s", "45s", "instant"
function ns.FormatDuration(seconds)
	seconds = math.floor((seconds or 0) + 0.5)
	if seconds <= 0 then return "instantly" end
	if seconds < 60 then return seconds .. "s" end
	local minutes = math.floor(seconds / 60)
	local rest = seconds % 60
	if rest == 0 then return minutes .. "m" end
	return minutes .. "m " .. rest .. "s"
end
