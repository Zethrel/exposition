-- Exposition - Core/Sender.lua
-- Copyright (c) 2026 Zethrel. All rights reserved. See LICENSE.
--
-- Owns the outgoing queue: one chat message now, the rest on a timer.

local _, ns = ...

local Sender = {}
ns.Sender = Sender

Sender.running = false
Sender.queue = nil
Sender.index = 0
Sender.token = 0

local MAX_RETRIES = 2

--------------------------------------------------------------------------------
-- Turning Blizzard's error strings into something matchable
--------------------------------------------------------------------------------

local function toPattern(format)
	if not format then return nil end
	local pattern = format:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	pattern = pattern:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
	return "^" .. pattern .. "$"
end

local THROTTLED = ERR_CHAT_THROTTLED
local PLAYER_NOT_FOUND = toPattern(ERR_CHAT_PLAYER_NOT_FOUND_S)

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

--- Checks a destination before anything is sent, so a bad target costs one
--- error line instead of ten failed messages.
-- @return resolvedTarget, errorMessage
function Sender:Validate(chatType, target)
	if chatType == "WHISPER" then
		target = (target or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if target == "" then
			return nil, "Enter a name to whisper."
		end
		return target
	elseif chatType == "CHANNEL" then
		target = (target or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if target == "" then
			return nil, "Enter a channel name or number."
		end
		local id = tonumber(target)
		if not id then
			id = GetChannelName(target)
		elseif select(2, GetChannelName(id)) == nil then
			id = 0
		end
		if not id or id == 0 then
			return nil, string.format("You are not in channel %q.", target)
		end
		return id
	elseif chatType == "PARTY" or chatType == "RAID" then
		if not IsInGroup() then
			return nil, "You are not in a group."
		end
		if chatType == "RAID" and not IsInRaid() then
			return nil, "You are not in a raid."
		end
	elseif chatType == "INSTANCE_CHAT" then
		if not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
			return nil, "You are not in an instance group."
		end
	elseif chatType == "GUILD" or chatType == "OFFICER" then
		if not IsInGuild() then
			return nil, "You are not in a guild."
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Queue
--------------------------------------------------------------------------------

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, _, message)
	if not Sender.running then return end
	if THROTTLED and message == THROTTLED then
		Sender:OnThrottled()
	elseif PLAYER_NOT_FOUND and Sender.chatType == "WHISPER" and message:match(PLAYER_NOT_FOUND) then
		Sender:Stop("No such player. Nothing further was sent.")
	end
end)

function Sender:IsRunning()
	return self.running
end

function Sender:Remaining()
	if not self.running then return 0 end
	return #self.queue - self.index
end

--- Starts sending `chunks`. The first message goes out immediately.
-- @param options table: chatType, target, delay, onProgress, onFinish
function Sender:Start(chunks, options)
	if self.running then
		return false, "Already sending. Stop the current post first."
	end
	if not chunks or #chunks == 0 then
		return false, "Nothing to send."
	end

	self.queue = chunks
	self.index = 0
	self.retryIndex, self.retryCount = nil, 0
	self.chatType = options.chatType
	self.target = options.target
	self.delay = math.max(ns.MIN_DELAY, tonumber(options.delay) or ns.DEFAULTS.delay)
	self.extraDelay = 0
	self.onProgress = options.onProgress
	self.onFinish = options.onFinish
	self.token = self.token + 1
	self.running = true

	watcher:RegisterEvent("CHAT_MSG_SYSTEM")
	self:Step()
	return true
end

function Sender:Step()
	if not self.running then return end

	self.index = self.index + 1
	if self.index > #self.queue then
		self:Finish("done")
		return
	end

	local message = self.queue[self.index]
	local ok, err = pcall(SendChatMessage, message, self.chatType, nil, self.target)
	if not ok then
		self:Stop("Could not send: " .. tostring(err))
		return
	end
	self.lastSendTime = GetTime()

	if self.onProgress then
		self.onProgress(self.index, #self.queue, message)
	end

	if self.index < #self.queue then
		self:ScheduleNext()
	else
		self:Finish("done")
	end
end

function Sender:ScheduleNext()
	local token = self.token
	local wait = self.delay + (self.extraDelay or 0)
	self.extraDelay = 0
	self.nextSendTime = GetTime() + wait
	C_Timer.After(wait, function()
		if self.running and self.token == token then
			self:Step()
		end
	end)
end

--- The server refused the last message. It was not delivered, so back up and
--- try it again after a longer pause.
function Sender:OnThrottled()
	local failed = self.index
	if self.retryIndex == failed then
		self.retryCount = self.retryCount + 1
	else
		self.retryIndex, self.retryCount = failed, 1
	end
	if self.retryCount > MAX_RETRIES then
		self:Stop("The server is throttling chat. Increase the delay and try again.")
		return
	end
	self.index = failed - 1
	self.extraDelay = 6
	self.token = self.token + 1
	ns.Print("|cffffd100Throttled by the server.|r Retrying message "
		.. (self.index + 1) .. " in a few seconds.")
	self:ScheduleNext()
end

--- Ends the queue and tells the UI. Called for both a completed post and an
--- early stop, so there is exactly one teardown path.
function Sender:Finish(reason)
	local onFinish = self.onFinish
	local total = self.queue and #self.queue or 0
	local sent = math.max(math.min(self.index, total), 0)

	self.running = false
	self.token = self.token + 1
	self.queue = nil
	self.index = 0
	self.onProgress = nil
	self.onFinish = nil
	self.nextSendTime = nil
	watcher:UnregisterEvent("CHAT_MSG_SYSTEM")

	if onFinish then onFinish(reason, sent, total) end
end

--- Stops early. `message`, when given, is shown to the player.
function Sender:Stop(message)
	if not self.running then return end
	self:Finish(message or "stopped")
	if message then ns.Print(message) end
end
