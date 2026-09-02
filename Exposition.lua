-- Exposition - Exposition.lua
--
-- Entry point: saved variables, slash commands, and the addon compartment
-- button.

local ADDON, ns = ...

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
	if event ~= "ADDON_LOADED" or name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")
	ns.LoadDB()
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function Usage()
	ns.Print("commands:")
	ns.Print("  |cffffd100/expo|r - open or close the composer")
	ns.Print("  |cffffd100/expo stop|r - cancel a post that is still sending")
	ns.Print("  |cffffd100/expo delay <seconds>|r - set the gap between messages")
	ns.Print("  |cffffd100/expo marker <none, count, bracket, paren, ellipsis, raid>|r")
end

SLASH_EXPOSITION1 = "/exposition"
SLASH_EXPOSITION2 = "/expo"
SlashCmdList["EXPOSITION"] = function(input)
	local command, argument = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

	if command == "" then
		ns.UI:Toggle()
	elseif command == "stop" then
		if ns.Sender:IsRunning() then
			ns.Sender:Stop("Stopped.")
		else
			ns.Print("nothing is being sent.")
		end
	elseif command == "delay" then
		local seconds = tonumber(argument)
		if not seconds then
			ns.Print("delay is currently " .. ns.db.delay .. "s.")
		else
			ns.db.delay = math.max(0, math.min(ns.MAX_DELAY, seconds))
			ns.Print("delay set to " .. ns.db.delay .. "s.")
			if ns.UI.frame then ns.UI:SyncWidgets(); ns.UI:Refresh() end
		end
	elseif command == "marker" then
		if ns.Splitter.MarkerStyles[argument] then
			ns.db.marker = argument
			ns.Print("marker style set to " .. argument .. ".")
			if ns.UI.frame then ns.UI:SyncWidgets(); ns.UI:Refresh() end
		else
			ns.Print("marker is currently " .. ns.db.marker .. ".")
		end
	else
		Usage()
	end
end

--------------------------------------------------------------------------------
-- Addon compartment (the menu on the minimap clock in modern clients)
--------------------------------------------------------------------------------

function Exposition_OnAddonCompartmentClick()
	ns.UI:Toggle()
end

function Exposition_OnAddonCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:AddLine("Exposition", 1, 0.82, 0)
	GameTooltip:AddLine("Write a long post, send it in readable pieces.", 1, 1, 1, true)
	GameTooltip:AddLine("/expo", 0.54, 0.78, 1)
	GameTooltip:Show()
end

function Exposition_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
