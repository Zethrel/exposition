-- Exposition integration tests.
-- Copyright (c) 2026 Zethrel. All rights reserved. See LICENSE.
--
--   lua5.1 tests/integration.lua
--
-- Loads the real addon files against a stubbed WoW client and drives the
-- window the way a player would: type, preview, send, wait, stop.

local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local root = here .. "/.."
local stub = dofile(here .. "/wow_stub.lua")

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
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

-- Fresh client, fresh saved variables, window open.
local function fresh()
	stub.Install()
	_G.ExpositionDB = nil
	local ns = stub.LoadAddon(root)
	_G.SlashCmdList["EXPOSITION"]("")
	return ns
end

local function compose(ns, text)
	ns.UI.editBox:SetText(text)
	stub.Advance(0.2) -- let the debounced preview refresh run
end

local PROSE = table.concat({
	"The tavern door swings inward on a gust of rain-soaked wind, and for a",
	"moment the whole common room turns to look. She shakes the water from her",
	"cloak, peels back the hood, and lets the door bang shut behind her. Nobody",
	"offers a seat. Nobody ever does, not on a night like this one, not with the",
	"storm climbing the cliffs outside and the harbour bell tolling itself",
	"hoarse against the dark. She crosses to the bar anyway. The barkeep does",
	"not meet her eyes. He polishes a glass that was already clean, then",
	"polishes it again, and when she sets a single silver coin on the wood",
	"between them he looks at it the way a man looks at a spider. It is not yet",
	"the eighth bell, whatever he says, and the fire behind her says so too.",
}, " ")

--------------------------------------------------------------------------------

test("the addon loads and seeds its settings", function()
	stub.Install()
	_G.ExpositionDB = nil
	local ns = stub.LoadAddon(root)
	check(ns.db ~= nil, "saved variables initialised")
	eq(ns.db.delay, 15, "default delay")
	eq(ns.db.channel, "SAY", "default channel")
	eq(ns.db.marker, "none", "default marker")
	check(_G.SlashCmdList["EXPOSITION"] ~= nil, "slash command registered")
end)

test("existing settings survive an upgrade", function()
	stub.Install()
	_G.ExpositionDB = { delay = 22, marker = "bracket" }
	local ns = stub.LoadAddon(root)
	eq(ns.db.delay, 22, "kept the player's delay")
	eq(ns.db.marker, "bracket", "kept the player's marker")
	eq(ns.db.channel, "SAY", "filled in the missing default")
end)

test("a nonsense marker in saved variables is repaired", function()
	stub.Install()
	_G.ExpositionDB = { marker = "wingdings" }
	local ns = stub.LoadAddon(root)
	eq(ns.db.marker, "none", "fell back to no marker")
end)

test("the window opens and closes", function()
	local ns = fresh()
	check(ns.UI.frame ~= nil, "frame built")
	check(ns.UI.frame:IsShown(), "frame shown")
	_G.SlashCmdList["EXPOSITION"]("")
	check(not ns.UI.frame:IsShown(), "frame hidden again")
end)

test("typing updates the preview and the counter", function()
	local ns = fresh()
	compose(ns, PROSE)
	check(#ns.UI.chunks >= 3, "prose split into several messages")
	check(ns.UI.previewText:GetText():find("1/", 1, true) ~= nil, "preview numbers the messages")
	check(ns.UI.counterLabel:GetText():find("message") ~= nil, "counter mentions messages")
	check(ns.UI.counterLabel:GetText():find("to send") ~= nil, "counter estimates the time")
	check(ns.UI.sendButton:IsEnabled(), "send is available")
end)

test("an empty composer cannot be sent", function()
	local ns = fresh()
	compose(ns, "")
	eq(#ns.UI.chunks, 0, "nothing to send")
	check(not ns.UI.sendButton:IsEnabled(), "send is disabled")
	ns.UI:DoSend()
	eq(#stub.sent, 0, "nothing went out")
end)

test("a post goes out one message at a time", function()
	local ns = fresh()
	ns.db.delay = 15
	compose(ns, PROSE)
	local expected = {}
	for index, chunk in ipairs(ns.UI.chunks) do expected[index] = chunk end

	ns.UI:DoSend()
	eq(#stub.sent, 1, "first message is immediate")
	eq(stub.sent[1].message, expected[1], "first message matches the preview")
	eq(stub.sent[1].chatType, "SAY", "sent to the right channel")
	check(ns.Sender:IsRunning(), "queue is running")
	check(not ns.UI.sendButton:IsEnabled(), "send is locked while sending")
	check(ns.UI.stopButton:IsEnabled(), "stop is available")

	stub.Advance(14)
	eq(#stub.sent, 1, "nothing extra before the delay elapses")

	stub.Advance(2)
	eq(#stub.sent, 2, "second message after the delay")

	stub.Advance(15 * #expected)
	eq(#stub.sent, #expected, "everything was sent")
	for index, chunk in ipairs(expected) do
		eq(stub.sent[index].message, chunk, "message " .. index .. " in order")
	end
	check(not ns.Sender:IsRunning(), "queue finished")
	check(ns.UI.statusLabel:GetText():find("Sent") ~= nil, "status reports completion")
end)

test("the composer is cleared only when asked", function()
	local ns = fresh()
	ns.db.keepTextAfterSending = true
	compose(ns, "A short line.")
	ns.UI:DoSend()
	stub.Advance(60)
	eq(ns.UI.editBox:GetText(), "A short line.", "text kept")

	ns.db.keepTextAfterSending = false
	compose(ns, "Another short line.")
	ns.UI:DoSend()
	stub.Advance(60)
	eq(ns.UI.editBox:GetText(), "", "text cleared")
end)

test("stopping leaves the rest unsent", function()
	local ns = fresh()
	compose(ns, PROSE)
	ns.UI:DoSend()
	stub.Advance(16)
	eq(#stub.sent, 2, "two out so far")

	ns.UI.stopButton:Click()
	check(not ns.Sender:IsRunning(), "queue stopped")
	stub.Advance(120)
	eq(#stub.sent, 2, "no further messages")
	check(ns.UI.statusLabel:GetText():find("Stopped") ~= nil, "status reports the stop")
end)

test("a long post asks for confirmation first", function()
	local ns = fresh()
	compose(ns, string.rep("lorem ipsum dolor sit amet ", 120))
	check(#ns.UI.chunks > ns.db.confirmAbove, "enough messages to warrant a prompt")

	ns.UI:DoSend()
	eq(#stub.sent, 0, "nothing sent before confirming")
	eq(#stub.popups, 1, "a confirmation was raised")
	check(stub.popups[1].arg1:find("messages over about") ~= nil, "prompt states the cost")

	-- Accepting the popup is what actually starts the post.
	local dialog = _G.StaticPopupDialogs["EXPOSITION_CONFIRM_SEND"]
	dialog.OnAccept(nil, stub.popups[1].data)
	eq(#stub.sent, 1, "sending began after confirmation")
	ns.Sender:Stop()
end)

test("a whisper needs a name", function()
	local ns = fresh()
	ns.db.channel = "WHISPER"
	ns.db.whisperTarget = ""
	compose(ns, "Psst.")
	ns.UI:DoSend()
	eq(#stub.sent, 0, "nothing sent")
	check(ns.UI.statusLabel:GetText():find("name") ~= nil, "told the player why")

	ns.db.whisperTarget = "Zethrel"
	ns.UI:DoSend()
	eq(#stub.sent, 1, "sent once a name is set")
	eq(stub.sent[1].target, "Zethrel", "addressed correctly")
end)

test("group and guild channels are checked before sending", function()
	local ns = fresh()
	compose(ns, "Hello.")
	for _, case in ipairs({
		{ channel = "PARTY", needle = "group" },
		{ channel = "RAID", needle = "group" },
		{ channel = "GUILD", needle = "guild" },
		{ channel = "INSTANCE_CHAT", needle = "instance" },
	}) do
		ns.db.channel = case.channel
		ns.UI:DoSend()
		check(ns.UI.statusLabel:GetText():lower():find(case.needle) ~= nil,
			case.channel .. ": explained the problem")
	end
	eq(#stub.sent, 0, "nothing was sent to a channel we are not in")

	stub.inGroup, stub.inRaid = true, true
	ns.db.channel = "RAID"
	ns.UI:DoSend()
	eq(#stub.sent, 1, "raid chat works once in a raid")
end)

test("a numbered channel is resolved by name", function()
	local ns = fresh()
	stub.channels = { [4] = "LookingForGroup" }
	ns.db.channel = "CHANNEL"
	ns.db.channelTarget = "LookingForGroup"
	compose(ns, "Hello.")
	ns.UI:DoSend()
	eq(#stub.sent, 1, "sent")
	eq(stub.sent[1].target, 4, "resolved to the channel index")

	ns.db.channelTarget = "NotJoined"
	ns.UI:DoSend()
	eq(#stub.sent, 1, "nothing sent to a channel we have not joined")
	check(ns.UI.statusLabel:GetText():find("not in channel") ~= nil, "explained the problem")
end)

test("markers reach chat exactly as previewed", function()
	local ns = fresh()
	ns.db.marker = "count"
	compose(ns, PROSE)
	local previewed = ns.UI.chunks
	check(previewed[1]:match("^1/%d+ ") ~= nil, "preview carries the marker")
	ns.UI:DoSend()
	stub.Advance(15 * #previewed + 5)
	eq(#stub.sent, #previewed, "all sent")
	for index, chunk in ipairs(previewed) do
		eq(stub.sent[index].message, chunk, "message " .. index .. " unchanged on the way out")
	end
end)

test("a throttle warning makes the message retry rather than vanish", function()
	local ns = fresh()
	ns.db.delay = 2
	compose(ns, PROSE)
	ns.UI:DoSend()
	eq(#stub.sent, 1, "first message out")

	stub.FireEvent("CHAT_MSG_SYSTEM", _G.ERR_CHAT_THROTTLED)
	check(ns.Sender:IsRunning(), "still running")
	stub.Advance(10)
	eq(stub.sent[2].message, stub.sent[1].message, "the throttled message was sent again")
	ns.Sender:Stop()
end)

test("a missing whisper target aborts the rest of the post", function()
	local ns = fresh()
	ns.db.channel = "WHISPER"
	ns.db.whisperTarget = "Ghost"
	compose(ns, PROSE)
	ns.UI:DoSend()
	eq(#stub.sent, 1, "first message attempted")

	stub.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Ghost' is currently playing.")
	check(not ns.Sender:IsRunning(), "queue aborted")
	stub.Advance(120)
	eq(#stub.sent, 1, "nothing further was sent into the void")
end)

test("the delay floor is enforced", function()
	local ns = fresh()
	ns.db.delay = 0
	compose(ns, PROSE)
	ns.UI:DoSend()
	eq(#stub.sent, 1, "first message out")
	stub.Advance(0.5)
	eq(#stub.sent, 1, "still waiting out the minimum gap")
	stub.Advance(0.5)
	eq(#stub.sent, 2, "second message after the floor")
	ns.Sender:Stop()
end)

test("slash commands drive the same state as the window", function()
	local ns = fresh()
	_G.SlashCmdList["EXPOSITION"]("delay 20")
	eq(ns.db.delay, 20, "delay set")
	eq(ns.UI.delayBox:GetText(), "20", "window follows")

	_G.SlashCmdList["EXPOSITION"]("marker bracket")
	eq(ns.db.marker, "bracket", "marker set")

	_G.SlashCmdList["EXPOSITION"]("delay 9999")
	eq(ns.db.delay, ns.MAX_DELAY, "delay clamped")

	compose(ns, PROSE)
	ns.UI:DoSend()
	check(ns.Sender:IsRunning(), "sending")
	_G.SlashCmdList["EXPOSITION"]("stop")
	check(not ns.Sender:IsRunning(), "stopped from chat")

	_G.SlashCmdList["EXPOSITION"]("nonsense")
	check(#stub.printed > 0, "unknown commands print usage")
end)

test("the delay box rejects junk and clamps", function()
	local ns = fresh()
	ns.UI:CommitDelay("abc")
	eq(ns.db.delay, 15, "unchanged by junk")
	ns.UI:CommitDelay("16")
	eq(ns.db.delay, 16, "accepted a number")
	ns.UI:CommitDelay("-5")
	eq(ns.db.delay, 5, "reads the number out of odd input")
	ns.UI:NudgeDelay(1)
	eq(ns.db.delay, 6, "stepper works")
end)

test("settings and window placement are remembered", function()
	local ns = fresh()
	ns.db.marker = "paren"
	ns.db.delay = 18
	ns.UI:SavePlacement()
	check(ns.db.point ~= nil, "placement stored")
	local saved = _G.ExpositionDB

	-- Simulate a reload: same saved table, fresh client.
	stub.Install()
	_G.ExpositionDB = saved
	local reloaded = stub.LoadAddon(root)
	_G.SlashCmdList["EXPOSITION"]("")
	eq(reloaded.db.marker, "paren", "marker remembered")
	eq(reloaded.db.delay, 18, "delay remembered")
	eq(reloaded.UI.markerButtons.paren:IsEnabled(), true, "marker buttons rebuilt")
end)

test("a draft survives closing the window", function()
	local ns = fresh()
	compose(ns, "Half-written thought.")
	_G.SlashCmdList["EXPOSITION"]("") -- close
	local saved = _G.ExpositionDB
	eq(saved.draft, "Half-written thought.", "draft stored")

	stub.Install()
	_G.ExpositionDB = saved
	local reloaded = stub.LoadAddon(root)
	_G.SlashCmdList["EXPOSITION"]("")
	eq(reloaded.UI.editBox:GetText(), "Half-written thought.", "draft restored")
end)

test("two posts cannot overlap", function()
	local ns = fresh()
	compose(ns, PROSE)
	ns.UI:DoSend()
	local sentSoFar = #stub.sent
	ns.UI:DoSend()
	eq(#stub.sent, sentSoFar, "the second attempt sent nothing")
	check(ns.UI.statusLabel:GetText():find("Already") ~= nil, "explained why")
	ns.Sender:Stop()
end)

test("every channel button changes where the post goes", function()
	local ns = fresh()
	stub.inGroup, stub.inRaid, stub.inGuild = true, true, true
	compose(ns, "Testing.")
	for _, info in ipairs(ns.CHANNELS) do
		if not info.needs then
			ns.UI.channelButtons[info.key]:Click()
			eq(ns.db.channel, info.key, "button selected " .. info.key)
			ns.UI:DoSend()
			eq(stub.sent[#stub.sent].chatType, info.key, "sent to " .. info.key)
			stub.Advance(60)
		end
	end
end)

test("stale errors clear as you type, confirmations do not", function()
	local ns = fresh()
	ns.db.channel = "WHISPER"
	ns.db.whisperTarget = ""
	compose(ns, "Psst.")
	ns.UI:DoSend()
	check(ns.UI.statusLabel:GetText() ~= "", "an error is shown")
	compose(ns, "Psst, over here.")
	eq(ns.UI.statusLabel:GetText(), "", "the stale error cleared once the text changed")

	ns.db.channel = "SAY"
	ns.UI:DoSend()
	stub.Advance(60)
	check(ns.UI.statusLabel:GetText():find("Sent") ~= nil, "confirmation shown")
	compose(ns, "Something else.")
	check(ns.UI.statusLabel:GetText():find("Sent") ~= nil, "confirmation survives editing")
end)

test("player text cannot inject colour codes into the preview", function()
	local ns = fresh()
	compose(ns, "|cffff0000red|r and |Hitem:1|h[thing]|h")
	local preview = ns.UI.previewText:GetText()
	check(preview:find("||cffff0000", 1, true) ~= nil, "pipes escaped for display")
	eq(ns.UI.chunks[1], "|cffff0000red|r and |Hitem:1|h[thing]|h", "the message itself is untouched")
end)

test("a tiny saved window size is corrected on load", function()
	stub.Install()
	_G.ExpositionDB = { width = 120, height = 90 }
	local ns = stub.LoadAddon(root)
	_G.SlashCmdList["EXPOSITION"]("")
	check(ns.UI.frame:GetWidth() >= 560, "width raised to the minimum")
	check(ns.UI.frame:GetHeight() >= 560, "height raised to the minimum")
end)

--------------------------------------------------------------------------------

print("Exposition integration tests")
print("----------------------------")
for _, t in ipairs(tests) do
	currentTest = t.name
	local before = failures
	local ok, err = pcall(t.fn)
	if not ok then
		failures = failures + 1
		print(string.format("  ERROR [%s] %s", t.name, tostring(err)))
	end
	print(string.format("  %s  %s", failures == before and "ok  " or "FAIL", t.name))
end
print("----------------------------")
print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
