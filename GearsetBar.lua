local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

-- The floating gearset bar: one button per Gearset tab, draggable anywhere
-- on screen, shown while Preferences' "Show gearset bar" is on and at least
-- one Gearset exists. Closing it with its own X turns that preference off
-- (so the two never disagree). A button toggles its set: equip it, take it
-- off if it's the one worn, or -- when a DIFFERENT set is worn -- take that
-- one off first and then equip this one.
Embolsao.GearsetBar = {}
local Bar = Embolsao.GearsetBar

local BUTTON_SIZE = 34
local BUTTON_GAP = 8
local PADDING = 10
local CLOSE_SIZE = 18
local GLOW_THICKNESS = 2
local GLOW_OUTSET = 3
-- Longest a swap can take end to end (Unequip's read-back + the pause + the
-- Equip's stow and read-back) -- clicks in the meantime are ignored, since
-- a second swap started on top of a half-done first one would fight it.
local BUSY_SECONDS = 3

local frame
local buttons = {}
local busy = false
local refreshPending = false

-- Bags-domain Gearset tabs in the player's own tab order.
local function GetGearsets()
    local filters = Embolsao:GetFilters("bags")
    local gearsets = {}
    for _, tabData in ipairs(filters:GetAllTabs()) do
        if tabData.tabType == "gearset" then
            local tab = filters:GetCustomTab(tabData.id)
            if tab then
                table.insert(gearsets, tab)
            end
        end
    end
    return gearsets
end

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    Embolsao.db.gearsetBarPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function OnButtonClick(button)
    local tab = button.tab
    if not tab or busy then return end
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT or "You can't do that in combat.", 1, 0.2, 0.2)
        return
    end

    local Gearset = Embolsao.Gearset
    if Gearset:IsEquipped(tab) then
        busy = true
        Gearset:Unequip(tab)
    elseif Gearset:CanToggle(tab) then
        busy = true
        local other
        for _, candidate in ipairs(GetGearsets()) do
            if candidate ~= tab and Gearset:IsEquipped(candidate) then
                other = candidate
                break
            end
        end
        if other then
            -- The other set comes off first (which also puts back whatever
            -- IT had replaced), then a beat for that to settle, then this one.
            Gearset:Unequip(other, function()
                C_Timer.After(0.5, function() Gearset:Equip(tab) end)
            end)
        else
            Gearset:Equip(tab)
        end
    else
        return -- nothing of the set is available: nothing to do
    end

    C_Timer.After(BUSY_SECONDS, function() busy = false end)
end

local function CreateButton()
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    -- Trim the icon's built-in border so square icons sit cleanly.
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Green outline while this set is the one worn: four thin strips on the
    -- OVERLAY layer, same approach as the tab button's indicator.
    button.glow = {}
    local function Edge(...)
        local edge = button:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(0.1, 1, 0.2, 1)
        edge:Hide()
        table.insert(button.glow, edge)
        return edge
    end
    -- Outside the icon, like the tab buttons in the bags window (the bar's
    -- padding leaves room for it).
    local o = GLOW_OUTSET
    local top, bottom, left, right = Edge(), Edge(), Edge(), Edge()
    top:SetPoint("TOPLEFT", -o, o); top:SetPoint("TOPRIGHT", o, o); top:SetHeight(GLOW_THICKNESS)
    bottom:SetPoint("BOTTOMLEFT", -o, -o); bottom:SetPoint("BOTTOMRIGHT", o, -o); bottom:SetHeight(GLOW_THICKNESS)
    left:SetPoint("TOPLEFT", -o, o); left:SetPoint("BOTTOMLEFT", -o, -o); left:SetWidth(GLOW_THICKNESS)
    right:SetPoint("TOPRIGHT", o, o); right:SetPoint("BOTTOMRIGHT", o, -o); right:SetWidth(GLOW_THICKNESS)

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.2)

    button:RegisterForClicks("LeftButtonUp")
    -- Dragging any button moves the whole bar, so it can be grabbed anywhere.
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() frame:StartMoving() end)
    button:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)
    button:SetScript("OnClick", OnButtonClick)
    button:SetScript("OnEnter", function(self)
        local tab = self.tab
        if not tab then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(tab.name)
        if Embolsao.Gearset:IsEquipped(tab) then
            GameTooltip:AddLine(L.GEARSET_BAR_CLICK_UNEQUIP, 1, 1, 1)
        elseif Embolsao.Gearset:CanToggle(tab) then
            GameTooltip:AddLine(L.GEARSET_BAR_CLICK_EQUIP, 1, 1, 1)
        else
            GameTooltip:AddLine(L.GEARSET_BAR_NOTHING_AVAILABLE, 1, 0.3, 0.3)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    return button
end

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "EmbolsaoGearsetBar", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.75)

    local pos = Embolsao.db.gearsetBarPosition
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end

    -- Closing it from here turns the preference off, so the checkbox in
    -- Preferences always says what's on screen.
    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
    frame.closeButton:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    frame.closeButton:SetPoint("RIGHT", -3, 0)
    frame.closeButton:SetScript("OnClick", function()
        Embolsao.db.showGearsetBar = false
        Bar:Refresh()
        if Embolsao.UI.SyncGearsetBarCheck then
            Embolsao.UI:SyncGearsetBarCheck()
        end
    end)
    frame.closeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.GEARSET_BAR_CLOSE_HINT)
        GameTooltip:Show()
    end)
    frame.closeButton:SetScript("OnLeave", GameTooltip_Hide)

    return frame
end

function Bar:Refresh()
    if not Embolsao.db then return end

    local gearsets = GetGearsets()
    if Embolsao.db.showGearsetBar == false or #gearsets == 0 then
        if frame then frame:Hide() end
        return
    end

    EnsureFrame()
    local Gearset = Embolsao.Gearset

    for index, tab in ipairs(gearsets) do
        local button = buttons[index]
        if not button then
            button = CreateButton()
            buttons[index] = button
        end
        button:ClearAllPoints()
        button:SetPoint("LEFT", frame, "LEFT",
            PADDING + (index - 1) * (BUTTON_SIZE + BUTTON_GAP), 0)
        button.tab = tab
        button.icon:SetTexture(tab.icon or "Interface\\Icons\\INV_Misc_Bag_10")

        local equipped = Gearset:IsEquipped(tab)
        for _, edge in ipairs(button.glow) do
            edge:SetShown(equipped)
        end
        -- Nothing of the set to equip (and it isn't worn): dimmed, like the
        -- Unavailable rows in the tab itself.
        local available = equipped or Gearset:CanToggle(tab)
        button.icon:SetDesaturated(not available)
        button.icon:SetAlpha(available and 1 or 0.5)
        button:Show()
    end
    for index = #gearsets + 1, #buttons do
        buttons[index].tab = nil
        buttons[index]:Hide()
    end

    frame:SetSize(PADDING * 2 + #gearsets * BUTTON_SIZE + (#gearsets - 1) * BUTTON_GAP
        + 6 + CLOSE_SIZE, PADDING * 2 + BUTTON_SIZE)
    frame:Show()
end

-- Refresh triggers fire in bursts (every bag update, every tab rebuild) --
-- coalesce them into one pass.
function Bar:RefreshSoon()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.2, function()
        refreshPending = false
        Bar:Refresh()
    end)
end

-- Tabs created/edited/deleted rebuild through UI:BuildTabs; anything that can
-- change what's available or worn refreshes through UI:Refresh.
if Embolsao.UI then
    if Embolsao.UI.BuildTabs then hooksecurefunc(Embolsao.UI, "BuildTabs", function() Bar:RefreshSoon() end) end
    if Embolsao.UI.Refresh then hooksecurefunc(Embolsao.UI, "Refresh", function() Bar:RefreshSoon() end) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function() Bar:RefreshSoon() end)
