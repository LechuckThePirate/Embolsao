-- Click bindings: which modifier key, held while left-clicking an item, does
-- what (show a merged stack's real stacks, split, the item actions menu), the
-- tooltip hints and click helpers built on them, and the Bindings window where
-- they are configured. Split out of UI.lua (see the file-size and Lua 5.1 limits
-- notes there); loads BEFORE it and exports what the item buttons need on
-- Embolsao.Bindings. It reaches the UI table only at run time (Embolsao.UI).
local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

local Bindings = {}
Embolsao.Bindings = Bindings

-- Callback StackSplitFrame invokes as button:SplitStack(amount) once the
-- player confirms a split quantity in its popup. Shared -- acts only on the
-- button/bagID/slot it's given.
local function SplitItemStack(button, split)
    C_Container.SplitContainerItem(button:GetBagID(), button:GetID(), split)
end

--------------------------------------------------------------------------
-- Click bindings: which modifier key, held while left-clicking an item,
-- triggers which action. Configurable in the "Bindings" window (main menu),
-- stored account-wide in Embolsao.db.bindings as { [actionID] = combo }.
--
-- A combo is "NONE" (unbound) or the held modifiers in the fixed order
-- ALT, CTRL, SHIFT joined by "-" ("CTRL", "ALT-SHIFT"...). A plain click
-- can't be bound: it's pick up/place, and right-click is use/deposit.
-- Defaults reproduce how the addon behaved before this was configurable
-- (Ctrl = stacks, Shift = split), plus the new Alt = item actions menu.
--------------------------------------------------------------------------

local BINDING_ACTIONS = {
    { id = "STACKS", default = "CTRL", labelKey = "BINDING_STACKS" },
    { id = "SPLIT", default = "SHIFT", labelKey = "BINDING_SPLIT" },
    { id = "MENU", default = "ALT", labelKey = "BINDING_MENU" },
}

local BINDING_CHOICES = {
    "NONE", "SHIFT", "CTRL", "ALT", "CTRL-SHIFT", "ALT-CTRL", "ALT-SHIFT", "ALT-CTRL-SHIFT",
}

local BINDING_KEY_LABEL_KEYS = { ALT = "KEY_ALT", CTRL = "KEY_CTRL", SHIFT = "KEY_SHIFT" }

-- The modifiers held right now, as a combo ("" when none).
local function CurrentModifierCombo()
    local parts = {}
    if IsAltKeyDown() then table.insert(parts, "ALT") end
    if IsControlKeyDown() then table.insert(parts, "CTRL") end
    if IsShiftKeyDown() then table.insert(parts, "SHIFT") end
    return table.concat(parts, "-")
end

local function GetBinding(actionID)
    local saved = Embolsao.db.bindings and Embolsao.db.bindings[actionID]
    if saved then
        for _, choice in ipairs(BINDING_CHOICES) do
            if choice == saved then return saved end
        end
    end
    for _, action in ipairs(BINDING_ACTIONS) do
        if action.id == actionID then return action.default end
    end
    return "NONE"
end

-- Two actions can't share a combo: taking one that's in use hands the other
-- action whatever this one had (so a swap, or "unbound" if it had nothing).
local function SetBinding(actionID, combo)
    local previous = GetBinding(actionID)
    if combo ~= "NONE" then
        for _, other in ipairs(BINDING_ACTIONS) do
            if other.id ~= actionID and GetBinding(other.id) == combo then
                Embolsao.db.bindings[other.id] = previous
            end
        end
    end
    Embolsao.db.bindings[actionID] = combo
end

local function ResetBindings()
    wipe(Embolsao.db.bindings)
end

-- "Ctrl + Shift", or "Unbound".
local function BindingText(combo)
    if combo == "NONE" then return L.BINDING_UNBOUND end
    local parts = {}
    for key in combo:gmatch("[^-]+") do
        table.insert(parts, L[BINDING_KEY_LABEL_KEYS[key]])
    end
    return table.concat(parts, " + ")
end

-- Which action, if any, the modifiers held at this moment are bound to.
local function ActionForCurrentClick()
    local combo = CurrentModifierCombo()
    if combo == "" then return nil end
    for _, action in ipairs(BINDING_ACTIONS) do
        if GetBinding(action.id) == combo then return action.id end
    end
    return nil
end

-- Whether an action means anything for this particular item button: stacks
-- only for a merged entry made of several real stacks, split only for a
-- stack of more than one. Used to show just the relevant hints on a tooltip.
local function BindingApplies(actionID, btn)
    if not btn.itemID then return false end
    if actionID == "STACKS" then
        return btn.locations ~= nil and #btn.locations > 1
    elseif actionID == "SPLIT" then
        -- A Gearset tab's Equipped/Unavailable rows (UI.lua) have no real
        -- bag slot behind them -- GetBagID() comes back nil there, which
        -- C_Container.GetContainerItemInfo rejects outright ("bad argument
        -- #1") instead of just returning no info the way an empty/invalid
        -- real slot would.
        local bagID = btn:GetBagID()
        if not bagID then return false end
        local info = C_Container.GetContainerItemInfo(bagID, btn:GetID())
        return info ~= nil and (info.stackCount or 1) > 1 and not info.isLocked
    end
    return true
end

-- Adds the applicable bindings to the item tooltip currently being built: the
-- key in gold, the action in grey -- and when the player is holding exactly
-- that combo right now, the line lights up (see the MODIFIER_STATE_CHANGED
-- refresh at the bottom of the file), so it's clear what the click will do.
local function AddBindingHints(btn)
    local held = CurrentModifierCombo()
    local addedAny = false
    for _, action in ipairs(BINDING_ACTIONS) do
        local combo = GetBinding(action.id)
        if combo ~= "NONE" and BindingApplies(action.id, btn) then
            if not addedAny then
                GameTooltip:AddLine(" ")
                addedAny = true
            end
            local active = held == combo
            local keyText = BindingText(combo) .. " + " .. L.CLICK
            if active then
                GameTooltip:AddDoubleLine(keyText, L[action.labelKey], 0.3, 1, 0.3, 1, 1, 1)
            else
                GameTooltip:AddDoubleLine(keyText, L[action.labelKey], 1, 0.82, 0, 0.65, 0.65, 0.65)
            end
        end
    end
end

-- Opens Blizzard's own StackSplitFrame for the real stack under this button.
local function StartSplit(btn)
    local info = C_Container.GetContainerItemInfo(btn:GetBagID(), btn:GetID())
    local itemCount = info and info.stackCount
    if itemCount and itemCount > 1 and not info.isLocked then
        btn.SplitStack = SplitItemStack
        Embolsao:OpenStackSplitFrame(itemCount, btn, "BOTTOMRIGHT", "TOPRIGHT")
    end
end

-- The Bindings window: one dropdown per action, plus a short reminder of the
-- fixed controls that can't be rebound.
local bindingsFrame

local function RefreshBindingsFrame()
    if not bindingsFrame then return end
    for _, row in ipairs(bindingsFrame.rows) do
        row.dropdown:GenerateMenu()
    end
end

local function ShowBindingsFrame()
    if not bindingsFrame then
        bindingsFrame = CreateFrame("Frame", "EmbolsaoBindingsFrame", UIParent, "BackdropTemplate")
        bindingsFrame:SetSize(400, 400)
        bindingsFrame:SetPoint("CENTER")
        bindingsFrame:SetFrameStrata("DIALOG")
        bindingsFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        bindingsFrame:SetBackdropColor(0, 0, 0, 0.9)
        bindingsFrame:SetMovable(true)
        bindingsFrame:EnableMouse(true)
        bindingsFrame:RegisterForDrag("LeftButton")
        bindingsFrame:SetScript("OnDragStart", bindingsFrame.StartMoving)
        bindingsFrame:SetScript("OnDragStop", bindingsFrame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "EmbolsaoBindingsFrame")

        local close = CreateFrame("Button", nil, bindingsFrame, "UIPanelCloseButtonDefaultAnchors")
        close:SetPoint("TOPRIGHT", -2, -2)

        bindingsFrame.title = bindingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        bindingsFrame.title:SetPoint("TOP", 0, -16)
        bindingsFrame.title:SetText(L.BINDINGS)

        bindingsFrame.hint = bindingsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        bindingsFrame.hint:SetPoint("TOP", 0, -46)
        bindingsFrame.hint:SetWidth(350)
        bindingsFrame.hint:SetJustifyH("CENTER")
        bindingsFrame.hint:SetText(L.BINDINGS_HINT)

        bindingsFrame.rows = {}
        for index, action in ipairs(BINDING_ACTIONS) do
            local label = bindingsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            label:SetPoint("TOPLEFT", 24, -96 - (index - 1) * 58)
            label:SetText(L[action.labelKey])

            local dropdown = CreateFrame("DropdownButton", nil, bindingsFrame, "WowStyle1DropdownTemplate")
            dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
            dropdown:SetWidth(220)
            dropdown:SetupMenu(function(_, rootDescription)
                local function IsSelected(choice)
                    return GetBinding(action.id) == choice
                end
                local function SetSelected(choice)
                    SetBinding(action.id, choice)
                    -- The swap rule may have changed another action's binding.
                    RefreshBindingsFrame()
                end
                for _, choice in ipairs(BINDING_CHOICES) do
                    rootDescription:CreateRadio(BindingText(choice), IsSelected, SetSelected, choice)
                end
            end)

            bindingsFrame.rows[index] = { dropdown = dropdown }
        end

        bindingsFrame.fixed = bindingsFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        bindingsFrame.fixed:SetPoint("TOPLEFT", 24, -96 - #BINDING_ACTIONS * 58 - 8)
        bindingsFrame.fixed:SetWidth(352)
        bindingsFrame.fixed:SetJustifyH("LEFT")
        bindingsFrame.fixed:SetSpacing(3)
        bindingsFrame.fixed:SetText(L.BINDINGS_FIXED_TEXT)

        local resetButton = CreateFrame("Button", nil, bindingsFrame, "UIPanelButtonTemplate")
        resetButton:SetSize(150, 22)
        resetButton:SetPoint("BOTTOMLEFT", 16, 16)
        resetButton:SetText(L.BINDINGS_RESET)
        resetButton:SetScript("OnClick", function()
            ResetBindings()
            RefreshBindingsFrame()
        end)

        local closeButton = CreateFrame("Button", nil, bindingsFrame, "UIPanelButtonTemplate")
        closeButton:SetSize(100, 22)
        closeButton:SetPoint("BOTTOMRIGHT", -16, 16)
        closeButton:SetText(CLOSE)
        closeButton:SetScript("OnClick", function() bindingsFrame:Hide() end)
    end

    RefreshBindingsFrame()
    bindingsFrame:Show()
end


Bindings.CurrentModifierCombo = CurrentModifierCombo
Bindings.ActionForCurrentClick = ActionForCurrentClick
Bindings.BindingApplies = BindingApplies
Bindings.AddBindingHints = AddBindingHints
Bindings.StartSplit = StartSplit
Bindings.ShowBindingsFrame = ShowBindingsFrame
