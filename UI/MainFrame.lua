-- Exposition - UI/MainFrame.lua
--
-- The composer window: type on the left, watch exactly what will hit chat on
-- the right of the cut, then send.
--
-- Deliberately built from plain frames and a handful of long lived templates
-- (UIPanelButtonTemplate, UICheckButtonTemplate, InputBoxTemplate,
-- UIPanelCloseButton, BackdropTemplate) rather than the options/dropdown
-- templates, which Blizzard has rewritten repeatedly.

local _, ns = ...

local UI = {}
ns.UI = UI

local PAD = 16
local CONTROLS_HEIGHT = 216
local PREVIEW_HEIGHT = 120
local ROW_HEIGHT = 22

-- Smallest window that still leaves the composer a usable amount of room:
-- title + composer + counter + preview + controls + trim.
local MIN_WIDTH, MIN_HEIGHT = 560, 560

local Splitter = ns.Splitter

--------------------------------------------------------------------------------
-- Small builders
--------------------------------------------------------------------------------

local function ShowTooltip(owner, title, body)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(title, 1, 0.82, 0)
	if body then
		for line in tostring(body):gmatch("[^\n]+") do
			GameTooltip:AddLine(line, 1, 1, 1, true)
		end
	end
	GameTooltip:Show()
end

local function AddTooltip(widget, title, body)
	widget:SetScript("OnEnter", function(self) ShowTooltip(self, title, body) end)
	widget:SetScript("OnLeave", GameTooltip_Hide or function() GameTooltip:Hide() end)
end

-- A sunken panel used for the composer and the preview.
local function CreateBox(parent)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	box:SetBackdropColor(0, 0, 0, 0.6)
	box:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
	return box
end

local function CreateLabel(parent, text, fontObject)
	local label = parent:CreateFontString(nil, "ARTWORK", fontObject or "GameFontNormalSmall")
	label:SetText(text)
	return label
end

local function CreateButton(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, ROW_HEIGHT)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

-- A push button that stays down while it is the active choice.
local function SetToggled(button, on)
	if on then
		button:SetButtonState("PUSHED", true)
		button:GetFontString():SetTextColor(1, 0.82, 0)
	else
		button:SetButtonState("NORMAL")
		button:GetFontString():SetTextColor(1, 1, 1)
	end
end

local function CreateCheckBox(parent, text, tooltip, get, set)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	local label = CreateLabel(parent, text, "GameFontHighlightSmall")
	label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	check.label = label
	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		UI:Refresh()
	end)
	check.Sync = function(self) self:SetChecked(get() and true or false) end
	AddTooltip(check, text, tooltip)
	check.width = 26 + label:GetStringWidth()
	return check
end

-- Adds a slim bar on the right edge of a box showing where you are in a
-- scrolling region. Cheaper and less fragile than a full scrollbar template.
local function AttachScrollIndicator(box, scroll)
	local track = box:CreateTexture(nil, "ARTWORK")
	track:SetColorTexture(1, 1, 1, 0.06)
	track:SetPoint("TOPRIGHT", box, "TOPRIGHT", -5, -5)
	track:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -5, 5)
	track:SetWidth(4)

	local thumb = box:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(0.54, 0.78, 1, 0.5)
	thumb:SetWidth(4)
	thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, 0)

	local function Update()
		local range = scroll:GetVerticalScrollRange() or 0
		local height = track:GetHeight()
		if range <= 0.5 then
			track:Hide()
			thumb:Hide()
			return
		end
		track:Show()
		thumb:Show()
		local visible = scroll:GetHeight()
		local content = visible + range
		local thumbHeight = math.max(16, height * (visible / content))
		local progress = scroll:GetVerticalScroll() / range
		thumb:SetHeight(thumbHeight)
		thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -progress * (height - thumbHeight))
	end

	scroll:HookScript("OnVerticalScroll", Update)
	scroll:HookScript("OnScrollRangeChanged", Update)
	scroll:HookScript("OnSizeChanged", Update)
	box.UpdateScrollIndicator = Update
	return Update
end

local function CreateScrollArea(parent)
	local box = CreateBox(parent)
	local scroll = CreateFrame("ScrollFrame", nil, box)
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -7)
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -13, 7)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local target = self:GetVerticalScroll() - delta * 30
		self:SetVerticalScroll(math.max(0, math.min(range, target)))
	end)
	AttachScrollIndicator(box, scroll)
	return box, scroll
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

function UI:Create()
	if self.frame then return self.frame end
	local db = ns.db

	local frame = CreateFrame("Frame", "ExpositionFrame", UIParent, "BackdropTemplate")
	self.frame = frame
	frame:SetSize(math.max(MIN_WIDTH, db.width or 640), math.max(MIN_HEIGHT, db.height or 660))
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:SetClampedToScreen(true)
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
	elseif frame.SetMinResize then
		frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
	end
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		UI:SavePlacement()
	end)
	frame:Hide()

	if db.point then
		frame:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
	else
		frame:SetPoint("CENTER")
	end

	tinsert(UISpecialFrames, "ExpositionFrame")

	local title = CreateLabel(frame, "Exposition", "GameFontNormalLarge")
	title:SetPoint("TOP", frame, "TOP", 0, -14)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		UI:SavePlacement()
		UI:Relayout()
	end)

	self:BuildControls(frame)
	self:BuildPreview(frame)
	self:BuildComposer(frame)

	frame:SetScript("OnSizeChanged", function() UI:Relayout() end)
	frame:SetScript("OnShow", function()
		UI:SyncWidgets()
		UI:Refresh()
	end)

	self:SyncWidgets()
	self:Relayout()
	return frame
end

function UI:SavePlacement()
	local frame = self.frame
	local point, _, relativePoint, x, y = frame:GetPoint()
	ns.db.point = { point, "UIParent", relativePoint, x, y }
	ns.db.width, ns.db.height = math.floor(frame:GetWidth()), math.floor(frame:GetHeight())
end

--------------------------------------------------------------------------------
-- Controls (bottom block)
--------------------------------------------------------------------------------

function UI:BuildControls(frame)
	local db = ns.db

	local controls = CreateFrame("Frame", nil, frame)
	controls:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 14)
	controls:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 14)
	controls:SetHeight(CONTROLS_HEIGHT)
	self.controls = controls

	-- Fixed row offsets from the top of the block. Resizing the window only
	-- grows the composer, so these never need to move.
	local ROW_HEADER, ROW_CHANNEL_1, ROW_CHANNEL_2 = -2, -26, -52
	local ROW_MARKER_LABEL, ROW_MARKER = -82, -98
	local ROW_DELAY, ROW_TOGGLES = -130, -158
	local GAP, CHANNEL_WIDTH, MARKER_WIDTH, PER_ROW = 6, 92, 74, 5

	local function place(widget, x, y)
		widget:SetPoint("TOPLEFT", controls, "TOPLEFT", x, y)
	end

	-- Header row: section label on the left, whisper/channel target on the
	-- right, where nothing else competes for the space at any window width.
	local sendToLabel = CreateLabel(controls, "SEND TO")
	place(sendToLabel, 0, ROW_HEADER - 3)
	sendToLabel:SetTextColor(0.9, 0.75, 0.3)

	local target = CreateFrame("EditBox", nil, controls, "InputBoxTemplate")
	target:SetAutoFocus(false)
	target:SetSize(170, 20)
	target:SetPoint("TOPRIGHT", controls, "TOPRIGHT", 0, ROW_HEADER)
	target:SetScript("OnTextChanged", function(self)
		local channel = ns.db.channel
		if channel == "WHISPER" then
			ns.db.whisperTarget = self:GetText()
		elseif channel == "CHANNEL" then
			ns.db.channelTarget = self:GetText()
		end
	end)
	target:SetScript("OnEscapePressed", target.ClearFocus)
	target:SetScript("OnEnterPressed", target.ClearFocus)
	self.targetBox = target

	local targetLabel = CreateLabel(controls, "", "GameFontHighlightSmall")
	targetLabel:SetPoint("RIGHT", target, "LEFT", -8, 0)
	self.targetLabel = targetLabel

	-- Channels: two rows of push buttons instead of a dropdown. One click
	-- instead of two, and no dependency on the menu API of the week.
	self.channelButtons = {}
	for index, info in ipairs(ns.CHANNELS) do
		local button = CreateButton(controls, info.label, CHANNEL_WIDTH, function()
			ns.db.channel = info.key
			UI:SyncWidgets()
			UI:Refresh()
		end)
		local row = math.floor((index - 1) / PER_ROW)
		local column = (index - 1) % PER_ROW
		place(button, column * (CHANNEL_WIDTH + GAP),
			row == 0 and ROW_CHANNEL_1 or ROW_CHANNEL_2)
		self.channelButtons[info.key] = button
	end

	-- Markers: each button is labelled with the marker it produces.
	local markerLabel = CreateLabel(controls, "MESSAGE MARKER")
	place(markerLabel, 0, ROW_MARKER_LABEL)
	markerLabel:SetTextColor(0.9, 0.75, 0.3)

	self.markerButtons = {}
	for index, info in ipairs(ns.MARKERS) do
		local button = CreateButton(controls, info.label, MARKER_WIDTH, function()
			ns.db.marker = info.key
			UI:SyncWidgets()
			UI:Refresh()
		end)
		place(button, (index - 1) * (MARKER_WIDTH + GAP), ROW_MARKER)
		AddTooltip(button, "Marker: " .. info.label, info.tip)
		self.markerButtons[info.key] = button
	end

	-- Delay
	local waitLabel = CreateLabel(controls, "Wait", "GameFontHighlightSmall")
	place(waitLabel, 2, ROW_DELAY - 4)

	local delayBox = CreateFrame("EditBox", nil, controls, "InputBoxTemplate")
	delayBox:SetAutoFocus(false)
	delayBox:SetSize(38, 20)
	delayBox:SetMaxLetters(5)
	delayBox:SetJustifyH("CENTER")
	delayBox:SetPoint("LEFT", waitLabel, "RIGHT", 12, 0)
	delayBox:SetScript("OnEscapePressed", delayBox.ClearFocus)
	delayBox:SetScript("OnEnterPressed", delayBox.ClearFocus)
	delayBox:SetScript("OnEditFocusLost", function(self) UI:CommitDelay(self:GetText()) end)
	self.delayBox = delayBox

	local minus = CreateButton(controls, "-", 20, function() UI:NudgeDelay(-1) end)
	minus:SetHeight(20)
	minus:SetPoint("LEFT", delayBox, "RIGHT", 6, 0)
	local plus = CreateButton(controls, "+", 20, function() UI:NudgeDelay(1) end)
	plus:SetHeight(20)
	plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)

	local secondsLabel = CreateLabel(controls, "seconds between messages", "GameFontHighlightSmall")
	secondsLabel:SetPoint("LEFT", plus, "RIGHT", 8, 0)

	local delayHint = CreateLabel(controls, "", "GameFontDisableSmall")
	delayHint:SetPoint("LEFT", secondsLabel, "RIGHT", 8, 0)
	self.delayHint = delayHint

	local delayTip = "How long Exposition waits before sending the next message.\n\n"
		.. "A full 255 character message is roughly 45 words. At a typical adult\n"
		.. "reading speed of 238-250 words per minute that is about 12 seconds,\n"
		.. "and longer for many readers. 15-16 seconds leaves a little room.\n\n"
		.. "Exposition never sends faster than one message every "
		.. ns.MIN_DELAY .. "s, because\nthe server throttles rapid chat and can disconnect you."
	AddTooltip(delayBox, "Delay between messages", delayTip)
	AddTooltip(minus, "Delay between messages", delayTip)
	AddTooltip(plus, "Delay between messages", delayTip)

	-- Toggles
	local sentences = CreateCheckBox(controls, "End on sentences",
		"Prefer to break where a sentence ends, so each message reads as a\n"
		.. "complete thought instead of stopping mid-clause.\n\n"
		.. "Only applies when a sentence ends reasonably close to the limit;\n"
		.. "otherwise Exposition still breaks between words.",
		function() return ns.db.preferSentence end,
		function(value) ns.db.preferSentence = value end)
	place(sentences, -4, ROW_TOGGLES)

	local newlines = CreateCheckBox(controls, "Keep line breaks",
		"Start a new message wherever you pressed Enter.\n\n"
		.. "Chat cannot carry line breaks, so the alternative is to fold your\n"
		.. "paragraphs together into one continuous block of text.",
		function() return ns.db.respectNewlines end,
		function(value) ns.db.respectNewlines = value end)
	newlines:SetPoint("LEFT", sentences, "LEFT", sentences.width + 20, 0)

	local keepText = CreateCheckBox(controls, "Keep text after sending",
		"Leave the composer contents alone once a post has gone out,\n"
		.. "instead of clearing it.",
		function() return ns.db.keepTextAfterSending end,
		function(value) ns.db.keepTextAfterSending = value end)
	keepText:SetPoint("LEFT", newlines, "LEFT", newlines.width + 20, 0)

	self.checkBoxes = { sentences, newlines, keepText }

	-- Send / Stop
	local send = CreateButton(controls, "Send", 110, function() UI:DoSend() end)
	send:SetHeight(24)
	send:SetPoint("BOTTOMRIGHT", controls, "BOTTOMRIGHT", 0, 0)
	self.sendButton = send

	local stop = CreateButton(controls, "Stop", 80, function()
		ns.Sender:Stop("Stopped.")
	end)
	stop:SetHeight(24)
	stop:SetPoint("RIGHT", send, "LEFT", -6, 0)
	self.stopButton = stop
	AddTooltip(stop, "Stop", "Cancel the rest of the post. Messages already sent stay sent.")

	local status = CreateLabel(controls, "", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", controls, "BOTTOMLEFT", 2, 6)
	status:SetPoint("RIGHT", stop, "LEFT", -10, 0)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)
	self.statusLabel = status
end

--------------------------------------------------------------------------------
-- Preview and composer
--------------------------------------------------------------------------------

function UI:BuildPreview(frame)
	local box, scroll = CreateScrollArea(frame)
	box:SetPoint("BOTTOMLEFT", self.controls, "TOPLEFT", 0, 10)
	box:SetPoint("BOTTOMRIGHT", self.controls, "TOPRIGHT", 0, 10)
	box:SetHeight(PREVIEW_HEIGHT)
	self.previewBox = box
	self.previewScroll = scroll

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT")
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetSpacing(2)
	self.previewContent = content
	self.previewText = text

	local heading = CreateLabel(frame, "", "GameFontNormalSmall")
	heading:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 2, 4)
	heading:SetJustifyH("LEFT")
	self.counterLabel = heading
end

function UI:BuildComposer(frame)
	local box, scroll = CreateScrollArea(frame)
	box:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -40)
	box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -40)
	box:SetPoint("BOTTOM", self.counterLabel, "TOP", 0, 4)
	self.composerBox = box
	self.composerScroll = scroll

	local editBox = CreateFrame("EditBox", nil, scroll)
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject("ChatFontNormal")
	editBox:SetMaxLetters(0)
	editBox:SetTextInsets(2, 2, 2, 2)
	editBox:SetHeight(80)
	editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
	editBox:SetScript("OnTextChanged", function(self)
		ns.db.draft = self:GetText()
		scroll:UpdateScrollChildRect()
		UI:QueueRefresh()
	end)
	editBox:SetScript("OnCursorChanged", function(_, _, y, _, cursorHeight)
		local top = -y
		local bottom = top + cursorHeight
		local offset = scroll:GetVerticalScroll()
		local visible = scroll:GetHeight()
		if top < offset then
			scroll:SetVerticalScroll(math.max(0, top))
		elseif bottom > offset + visible then
			local range = scroll:GetVerticalScrollRange() or 0
			scroll:SetVerticalScroll(math.min(range, bottom - visible))
		end
	end)
	scroll:SetScrollChild(editBox)
	self.editBox = editBox

	-- Clicking anywhere in the panel starts typing.
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() editBox:SetFocus() end)

	local hint = CreateLabel(box, "Type or paste your post here.", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -9)
	self.placeholder = hint
end

function UI:Relayout()
	if not self.frame then return end
	local width = self.composerScroll:GetWidth()
	self.editBox:SetWidth(width)
	self.previewText:SetWidth(self.previewScroll:GetWidth())
	self.previewContent:SetWidth(self.previewScroll:GetWidth())
	self.composerScroll:UpdateScrollChildRect()
	if self.composerBox.UpdateScrollIndicator then self.composerBox.UpdateScrollIndicator() end
	if self.previewBox.UpdateScrollIndicator then self.previewBox.UpdateScrollIndicator() end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function UI:SyncWidgets()
	local db = ns.db
	if not self.frame then return end

	for key, button in pairs(self.channelButtons) do
		SetToggled(button, key == db.channel)
	end
	for key, button in pairs(self.markerButtons) do
		SetToggled(button, key == db.marker)
	end
	for _, check in ipairs(self.checkBoxes) do
		check:Sync()
	end

	local info = ns.GetChannelInfo(db.channel)
	if info.needs == "player" then
		self.targetLabel:SetText("Whisper to")
		self.targetBox:SetText(db.whisperTarget or "")
		self.targetLabel:Show()
		self.targetBox:Show()
	elseif info.needs == "channel" then
		self.targetLabel:SetText("Channel name or number")
		self.targetBox:SetText(db.channelTarget or "")
		self.targetLabel:Show()
		self.targetBox:Show()
	else
		self.targetLabel:Hide()
		self.targetBox:Hide()
	end

	self.delayBox:SetText(tostring(db.delay))
	self:UpdateDelayHint()
	self:UpdateSendState()
end

function UI:UpdateDelayHint()
	local db = ns.db
	if db.delay < ns.MIN_DELAY then
		self.delayHint:SetText("(floor: " .. ns.MIN_DELAY .. "s)")
	else
		self.delayHint:SetText("")
	end
end

function UI:CommitDelay(value)
	local number = tonumber((value or ""):match("[%d%.]+") or "")
	if not number then
		self.delayBox:SetText(tostring(ns.db.delay))
		return
	end
	ns.db.delay = math.max(0, math.min(ns.MAX_DELAY, number))
	self.delayBox:SetText(tostring(ns.db.delay))
	self:UpdateDelayHint()
	self:Refresh()
end

function UI:NudgeDelay(step)
	self:CommitDelay(tostring((tonumber(ns.db.delay) or 0) + step))
end

function UI:EffectiveDelay()
	return math.max(ns.MIN_DELAY, tonumber(ns.db.delay) or 0)
end

function UI:GetTarget()
	local info = ns.GetChannelInfo(ns.db.channel)
	if info.needs == "player" then return ns.db.whisperTarget end
	if info.needs == "channel" then return ns.db.channelTarget end
	return nil
end

function UI:SetStatus(text, kind)
	if not self.statusLabel then return end
	self.statusLabel:SetText(text or "")
	self.statusKind = kind
	if kind == "error" then
		self.statusLabel:SetTextColor(1, 0.45, 0.45)
	elseif kind == "active" then
		self.statusLabel:SetTextColor(0.54, 0.78, 1)
	else
		self.statusLabel:SetTextColor(0.7, 0.7, 0.7)
	end
end

function UI:UpdateSendState()
	local running = ns.Sender:IsRunning()
	if running then
		self.sendButton:Disable()
		self.stopButton:Enable()
	else
		self.stopButton:Disable()
		if self.chunks and #self.chunks > 0 then
			self.sendButton:Enable()
		else
			self.sendButton:Disable()
		end
	end
end

--------------------------------------------------------------------------------
-- Live preview
--------------------------------------------------------------------------------

function UI:QueueRefresh()
	if self.refreshQueued then return end
	self.refreshQueued = true
	C_Timer.After(0.1, function()
		self.refreshQueued = false
		self:Refresh()
	end)
end

-- Pipes are escape characters to a FontString; show the player's text as typed.
local function escapePipes(text)
	local escaped = text:gsub("|", "||")
	return escaped
end

function UI:Refresh()
	if not self.frame then return end

	local text = self.editBox:GetText() or ""
	local chunks, info = Splitter.Split(text, ns.SplitOptions())
	self.chunks, self.splitInfo = chunks, info

	self.placeholder:SetShown(text == "")

	-- Counter line
	if #chunks == 0 then
		self.counterLabel:SetText("|cff909090Nothing to send yet.|r")
	else
		local duration = Splitter.EstimateDuration(#chunks, self:EffectiveDelay())
		local parts = string.format(
			"|cffffffff%d|r characters  |cff909090>|r  |cffffd100%d|r message%s",
			info.bytes, #chunks, #chunks == 1 and "" or "s")
		if #chunks > 1 then
			parts = parts .. string.format("  |cff909090>|r  about |cffffffff%s|r to send",
				ns.FormatDuration(duration))
		end
		if info.brokeWord then
			parts = parts .. "   |cffff8080A word longer than a whole message had to be cut.|r"
		end
		self.counterLabel:SetText(parts)
	end

	-- Preview body
	local lines = {}
	for index, chunk in ipairs(chunks) do
		local overLimit = #chunk > Splitter.MAX_MESSAGE_BYTES
		lines[#lines + 1] = string.format("|cff8ac6ff%d/%d|r  |cff%s%d chars|r",
			index, #chunks, overLimit and "ff5555" or "707070", #chunk)
		lines[#lines + 1] = "|cffe8e8e8" .. escapePipes(chunk) .. "|r"
		lines[#lines + 1] = " "
	end
	local previousScroll = self.previewScroll:GetVerticalScroll() or 0
	self.previewText:SetText(table.concat(lines, "\n"))
	self.previewContent:SetHeight(math.max(1, self.previewText:GetStringHeight() + 4))
	self.previewScroll:UpdateScrollChildRect()
	self.previewScroll:SetVerticalScroll(
		math.min(previousScroll, self.previewScroll:GetVerticalScrollRange() or 0))
	if self.previewBox.UpdateScrollIndicator then self.previewBox.UpdateScrollIndicator() end

	self:UpdateSendState()
	-- An error about the last attempt is stale once the text changes; a
	-- "sent" confirmation is worth leaving on screen.
	if self.statusKind == "error" and not ns.Sender:IsRunning() then
		self:SetStatus("")
	end
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["EXPOSITION_CONFIRM_SEND"] = {
	text = "Exposition\n\nThis will send %s to %s.\n\nContinue?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, data)
		if data then ns.UI:Dispatch(data.chunks, data.chatType, data.target) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function UI:DoSend()
	if ns.Sender:IsRunning() then
		self:SetStatus("Already sending.", "error")
		return
	end

	local chunks = self.chunks
	if not chunks or #chunks == 0 then
		self:SetStatus("Nothing to send.", "error")
		return
	end

	local info = ns.GetChannelInfo(ns.db.channel)
	local target, err = ns.Sender:Validate(info.key, self:GetTarget())
	if err then
		self:SetStatus(err, "error")
		return
	end

	if #chunks > (ns.db.confirmAbove or 8) then
		local summary = string.format("%d messages over about %s",
			#chunks, ns.FormatDuration(Splitter.EstimateDuration(#chunks, self:EffectiveDelay())))
		local where = info.label
		if target then where = where .. " (" .. tostring(target) .. ")" end
		StaticPopup_Show("EXPOSITION_CONFIRM_SEND", summary, where,
			{ chunks = chunks, chatType = info.key, target = target })
		return
	end

	self:Dispatch(chunks, info.key, target)
end

function UI:Dispatch(chunks, chatType, target)
	local total = #chunks
	local ok, err = ns.Sender:Start(chunks, {
		chatType = chatType,
		target = target,
		delay = self:EffectiveDelay(),
		onProgress = function(index)
			UI:SetStatus(string.format("Sending %d of %d...", index, total), "active")
			UI:UpdateSendState()
		end,
		onFinish = function(reason, sent)
			UI:StopCountdown()
			if reason == "done" then
				UI:SetStatus(string.format("Sent %d message%s.", sent, sent == 1 and "" or "s"))
				if not ns.db.keepTextAfterSending then
					UI.editBox:SetText("")
				end
			else
				UI:SetStatus(string.format("Stopped after %d of %d.", sent, total), "error")
			end
			UI:UpdateSendState()
		end,
	})
	if not ok then
		self:SetStatus(err or "Could not start.", "error")
		return
	end
	self:StartCountdown(total)
	self:UpdateSendState()
end

-- Shows the wait between messages ticking down, so a long delay does not look
-- like the addon has stalled.
function UI:StartCountdown(total)
	local frame = self.frame
	frame:SetScript("OnUpdate", function(_, elapsed)
		UI.countdownElapsed = (UI.countdownElapsed or 0) + elapsed
		if UI.countdownElapsed < 0.2 then return end
		UI.countdownElapsed = 0
		local sender = ns.Sender
		if not sender:IsRunning() then
			UI:StopCountdown()
			return
		end
		local remaining = (sender.nextSendTime or 0) - GetTime()
		if remaining > 0 then
			UI:SetStatus(string.format("Sending %d of %d - next in %ds",
				sender.index, total, math.ceil(remaining)), "active")
		end
	end)
end

function UI:StopCountdown()
	if self.frame then self.frame:SetScript("OnUpdate", nil) end
	self.countdownElapsed = 0
end

--------------------------------------------------------------------------------

function UI:Toggle()
	local frame = self:Create()
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		if ns.db.draft and ns.db.draft ~= "" and (self.editBox:GetText() or "") == "" then
			self.editBox:SetText(ns.db.draft)
		end
		self.editBox:SetFocus()
	end
end

function UI:Show()
	local frame = self:Create()
	if not frame:IsShown() then self:Toggle() end
end
