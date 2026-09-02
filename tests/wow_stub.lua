-- A small stand-in for the pieces of the WoW client Exposition touches, so the
-- Copyright (c) 2026 Zethrel. All rights reserved. See LICENSE.
-- addon can be loaded and driven outside the game.
--
-- Widget methods are whitelisted rather than blindly accepted: calling a method
-- that does not exist on a real WoW widget raises an error here, which is what
-- makes this useful for catching typos.

local stub = {}

local WIDGET_METHODS = {
	-- Region
	SetPoint = true, SetAllPoints = true, ClearAllPoints = true, GetPoint = true,
	SetSize = true, SetWidth = true, SetHeight = true, GetWidth = true, GetHeight = true,
	Show = true, Hide = true, IsShown = true, IsVisible = true, SetShown = true,
	SetAlpha = true, GetAlpha = true, SetParent = true, GetParent = true, GetName = true,
	-- Frame
	SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true,
	SetClampedToScreen = true, SetToplevel = true, SetFrameStrata = true, SetFrameLevel = true,
	SetMovable = true, SetResizable = true, SetResizeBounds = true, SetUserPlaced = true,
	EnableMouse = true, EnableMouseWheel = true, EnableKeyboard = true,
	RegisterForDrag = true, StartMoving = true, StopMovingOrSizing = true, StartSizing = true,
	SetScript = true, GetScript = true, HookScript = true,
	RegisterEvent = true, UnregisterEvent = true, UnregisterAllEvents = true,
	CreateFontString = true, CreateTexture = true, SetHitRectInsets = true,
	-- ScrollFrame
	SetScrollChild = true, GetScrollChild = true, UpdateScrollChildRect = true,
	SetVerticalScroll = true, GetVerticalScroll = true, GetVerticalScrollRange = true,
	SetHorizontalScroll = true, GetHorizontalScroll = true,
	-- FontString
	SetText = true, GetText = true, SetTextColor = true, SetJustifyH = true,
	SetJustifyV = true, SetSpacing = true, GetStringWidth = true, GetStringHeight = true,
	SetWordWrap = true, SetFontObject = true, SetFormattedText = true,
	-- Texture
	SetColorTexture = true, SetTexture = true, SetTexCoord = true, SetVertexColor = true,
	SetDrawLayer = true, SetBlendMode = true,
	-- Button
	SetNormalTexture = true, SetHighlightTexture = true, SetPushedTexture = true,
	SetDisabledTexture = true, GetFontString = true, SetButtonState = true,
	Enable = true, Disable = true, IsEnabled = true, RegisterForClicks = true,
	SetNormalFontObject = true, Click = true,
	-- CheckButton
	SetChecked = true, GetChecked = true,
	-- EditBox
	SetMultiLine = true, SetAutoFocus = true, SetMaxLetters = true, SetMaxBytes = true,
	SetTextInsets = true, SetFocus = true, ClearFocus = true, HasFocus = true,
	SetNumeric = true, HighlightText = true, SetCursorPosition = true, Insert = true,
	GetNumLetters = true, SetSecureText = true,
}

local widgetMeta

local function fireScript(widget, name, ...)
	local handler = widget.__scripts[name]
	if handler then return handler(widget, ...) end
end

local widgetAPI = {}

function widgetAPI:SetScript(name, handler) self.__scripts[name] = handler end
function widgetAPI:GetScript(name) return self.__scripts[name] end
function widgetAPI:HookScript(name, handler)
	local existing = self.__scripts[name]
	if not existing then
		self.__scripts[name] = handler
	else
		self.__scripts[name] = function(...) existing(...) return handler(...) end
	end
end

function widgetAPI:Show()
	self.__shown = true
	fireScript(self, "OnShow")
end
function widgetAPI:Hide()
	self.__shown = false
	fireScript(self, "OnHide")
end
function widgetAPI:IsShown() return self.__shown and true or false end
function widgetAPI:IsVisible() return self.__shown and true or false end
function widgetAPI:SetShown(value) if value then self:Show() else self:Hide() end end

function widgetAPI:SetText(text)
	self.__text = text ~= nil and tostring(text) or ""
	fireScript(self, "OnTextChanged", false)
end
function widgetAPI:GetText() return self.__text or "" end

function widgetAPI:SetSize(w, h) self.__width, self.__height = w, h end
function widgetAPI:SetWidth(w) self.__width = w end
function widgetAPI:SetHeight(h) self.__height = h end
function widgetAPI:GetWidth() return self.__width or 100 end
function widgetAPI:GetHeight() return self.__height or 20 end
function widgetAPI:GetName() return self.__name end
function widgetAPI:GetParent() return self.__parent end

function widgetAPI:SetPoint(point, relativeTo, relativePoint, x, y)
	self.__point = { point, relativeTo, relativePoint, x, y }
end
function widgetAPI:GetPoint()
	local p = self.__point or { "CENTER", nil, "CENTER", 0, 0 }
	return p[1], p[2], p[3] or "CENTER", p[4] or 0, p[5] or 0
end

function widgetAPI:GetStringWidth() return math.max(10, #(self.__text or "") * 6) end
function widgetAPI:GetStringHeight() return math.max(10, math.ceil(#(self.__text or "") / 60) * 12) end

function widgetAPI:GetVerticalScrollRange() return self.__scrollRange or 0 end
function widgetAPI:GetVerticalScroll() return self.__scroll or 0 end
function widgetAPI:SetVerticalScroll(value)
	self.__scroll = value
	fireScript(self, "OnVerticalScroll", value)
end
function widgetAPI:UpdateScrollChildRect()
	local child = self.__scrollChild
	self.__scrollRange = child and math.max(0, child:GetHeight() - self:GetHeight()) or 0
end
function widgetAPI:SetScrollChild(child) self.__scrollChild = child end
function widgetAPI:GetScrollChild() return self.__scrollChild end

function widgetAPI:SetChecked(value) self.__checked = value and true or false end
function widgetAPI:GetChecked() return self.__checked and true or false end

function widgetAPI:Enable() self.__enabled = true end
function widgetAPI:Disable() self.__enabled = false end
function widgetAPI:IsEnabled() return self.__enabled ~= false end
function widgetAPI:Click() fireScript(self, "OnClick", "LeftButton") end

function widgetAPI:GetFontString()
	if not self.__fontString then self.__fontString = stub.CreateWidget("FontString", nil, self) end
	return self.__fontString
end

function widgetAPI:CreateFontString(name, layer, template)
	return stub.CreateWidget("FontString", name, self)
end
function widgetAPI:CreateTexture(name, layer)
	return stub.CreateWidget("Texture", name, self)
end

function widgetAPI:RegisterEvent(event)
	stub.listeners[event] = stub.listeners[event] or {}
	stub.listeners[event][self] = true
end
function widgetAPI:UnregisterEvent(event)
	if stub.listeners[event] then stub.listeners[event][self] = nil end
end
function widgetAPI:UnregisterAllEvents()
	for _, set in pairs(stub.listeners) do set[self] = nil end
end

widgetMeta = {
	__index = function(widget, key)
		local method = widgetAPI[key]
		if method then return method end
		if WIDGET_METHODS[key] then
			local noop = function() end
			rawset(widget, key, noop)
			return noop
		end
		return nil
	end,
}

function stub.CreateWidget(kind, name, parent)
	local widget = setmetatable({
		__kind = kind, __name = name, __parent = parent,
		__scripts = {}, __shown = kind ~= "Frame" and kind ~= "Button" or false,
	}, widgetMeta)
	if kind == "FontString" or kind == "Texture" then widget.__shown = true end
	if name then _G[name] = widget end
	return widget
end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

function stub.Install()
	stub.listeners = {}
	stub.clock = 1000
	stub.timers = {}
	stub.sent = {}
	stub.printed = {}
	stub.popups = {}

	_G.UIParent = stub.CreateWidget("Frame", "UIParent")
	_G.UISpecialFrames = {}
	_G.StaticPopupDialogs = {}
	_G.tinsert = table.insert
	_G.tremove = table.remove
	_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

	_G.CreateFrame = function(kind, name, parent, template)
		local widget = stub.CreateWidget(kind, name, parent or _G.UIParent)
		widget.__template = template
		if kind == "Frame" or kind == "Button" or kind == "CheckButton"
			or kind == "EditBox" or kind == "ScrollFrame" then
			widget.__shown = true
		end
		return widget
	end

	_G.GetTime = function() return stub.clock end
	_G.C_Timer = {
		After = function(delay, callback)
			table.insert(stub.timers, { at = stub.clock + delay, callback = callback })
		end,
	}

	_G.C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }

	_G.SendChatMessage = function(message, chatType, language, target)
		assert(type(message) == "string", "message must be a string")
		assert(#message <= 255, "message exceeds 255 bytes: " .. #message)
		table.insert(stub.sent, { message = message, chatType = chatType, target = target })
	end

	_G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, text) table.insert(stub.printed, text) end,
	}

	_G.GameTooltip = stub.CreateWidget("Frame", "GameTooltip")
	_G.GameTooltip.SetOwner = function() end
	_G.GameTooltip.AddLine = function() end
	_G.GameTooltip.Show = function() end
	_G.GameTooltip.Hide = function() end

	_G.StaticPopup_Show = function(which, arg1, arg2, data)
		table.insert(stub.popups, { which = which, arg1 = arg1, arg2 = arg2, data = data })
		return { data = data }
	end

	_G.SlashCmdList = {}
	_G.YES, _G.NO = "Yes", "No"
	_G.ERR_CHAT_THROTTLED = "You have used too many chat and channel commands. Please wait a moment before trying again."
	_G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
	_G.LE_PARTY_CATEGORY_INSTANCE = 2

	stub.inGroup, stub.inRaid, stub.inGuild, stub.channels = false, false, false, {}
	_G.IsInGroup = function() return stub.inGroup end
	_G.IsInRaid = function() return stub.inRaid end
	_G.IsInGuild = function() return stub.inGuild end
	_G.GetChannelName = function(nameOrId)
		if type(nameOrId) == "number" then
			local name = stub.channels[nameOrId]
			if name then return nameOrId, name end
			return 0
		end
		for id, name in pairs(stub.channels) do
			if name:lower() == tostring(nameOrId):lower() then return id, name end
		end
		return 0
	end

	return stub
end

--- Fires an event at every frame registered for it.
function stub.FireEvent(event, ...)
	local set = stub.listeners[event]
	if not set then return end
	for widget in pairs(set) do
		local handler = widget.__scripts.OnEvent
		if handler then handler(widget, event, ...) end
	end
end

--- Advances the fake clock, running any timers that come due.
function stub.Advance(seconds)
	local target = stub.clock + seconds
	while true do
		local nextIndex, nextAt
		for index, timer in ipairs(stub.timers) do
			if timer.at <= target and (not nextAt or timer.at < nextAt) then
				nextIndex, nextAt = index, timer.at
			end
		end
		if not nextIndex then break end
		local timer = table.remove(stub.timers, nextIndex)
		stub.clock = timer.at
		timer.callback()
	end
	stub.clock = target
end

--- Loads the addon exactly as the client would, in TOC order.
function stub.LoadAddon(root)
	local ns = {}
	local files = {
		"Core/Splitter.lua", "Core/Config.lua", "Core/Sender.lua",
		"UI/MainFrame.lua", "Exposition.lua",
	}
	for _, file in ipairs(files) do
		local chunk = assert(loadfile(root .. "/" .. file))
		chunk("Exposition", ns)
	end
	stub.FireEvent("ADDON_LOADED", "Exposition")
	return ns
end

return stub
