-- The Preferences window: its checkboxes, the default-tab and opacity controls,
-- and the tab manager (reorder / hide / edit / delete). Split out of UI.lua (see
-- the file-size and Lua 5.1 limits notes there); loads after it, since its entry
-- point hangs off the UI table (UI.ShowPreferencesFrame).
local ADDON_NAME, Embolsao = ...
local L = Embolsao.L
local UI = Embolsao.UI

local prefsFrame

local function BuildDefaultTabMenu(dropdown, rootDescription)
    local function IsSelected(tabID)
        return Embolsao.db.defaultTab == tabID
    end
    local function SetSelected(tabID)
        Embolsao.db.defaultTab = tabID
    end

    rootDescription:CreateRadio(L.LAST_SELECTED, IsSelected, SetSelected, "LAST")
    for _, tab in ipairs(Embolsao.Filters:GetAllTabs()) do
        rootDescription:CreateRadio(tab.name, IsSelected, SetSelected, tab.id)
    end
end

local function CreatePreferenceCheckbox(parent, labelText, dbKey, anchorY, onChange)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 24, anchorY)
    check:SetChecked(Embolsao.db[dbKey])
    check:SetScript("OnClick", function(self)
        Embolsao.db[dbKey] = self:GetChecked() and true or false
        if onChange then onChange() end
    end)

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(labelText)

    return check
end

local TAB_MANAGER_ROW_HEIGHT = 26

-- One row per tab (built-in + custom, hidden ones included -- this is the
-- one place you can bring a hidden tab back). Up/down reuse the exact
-- arrow-button templates the scrollbar itself is built from, since a plain
-- Unicode arrow glyph turned out invisible earlier (default UI fonts don't
-- cover it) -- these are real textured buttons, not a font glyph.
-- Which pane's set of tabs the list below is managing. Only the bags' unless
-- Preferences -> "Separate tabs for Bank and Bags" is on, in which case the
-- dropdown next to the "Manage tabs" label picks bags or bank.
local function GetTabManagerDomain()
    if not Embolsao.db.separateBankTabs then return "bags" end
    return prefsFrame and prefsFrame.tabManagerDomain or "bags"
end

-- Shows the bags/bank picker next to "Manage tabs" only while the panes have
-- separate tabs (and falls back to the bags' list when they stop having them).
local function UpdateTabManagerDomainControl()
    if not prefsFrame or not prefsFrame.tabManagerDomainDropdown then return end
    local separate = Embolsao.db.separateBankTabs and true or false
    if not separate then
        prefsFrame.tabManagerDomain = "bags"
    end
    prefsFrame.tabManagerDomainDropdown:SetShown(separate)
    prefsFrame.tabManagerDomainDropdown:GenerateMenu()
end

local function RefreshTabManagerList()
    local content = prefsFrame.tabListContent
    prefsFrame.tabRows = prefsFrame.tabRows or {}

    local filters = Embolsao:GetFilters(GetTabManagerDomain())
    local tabs = filters:GetAllTabs()
    for i, tabData in ipairs(tabs) do
        local row = prefsFrame.tabRows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetSize(1, TAB_MANAGER_ROW_HEIGHT)

            row.upButton = CreateFrame("Button", nil, row, "UIPanelScrollUpButtonTemplate")
            row.upButton:SetPoint("LEFT", 0, 0)
            row.downButton = CreateFrame("Button", nil, row, "UIPanelScrollDownButtonTemplate")
            row.downButton:SetPoint("LEFT", row.upButton, "RIGHT", 2, 0)

            row.visibleCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.visibleCheck:SetSize(22, 22)
            row.visibleCheck:SetPoint("LEFT", row.downButton, "RIGHT", 4, 0)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", row.visibleCheck, "RIGHT", 4, 0)

            row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)

            prefsFrame.tabRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * TAB_MANAGER_ROW_HEIGHT)
        row:SetPoint("RIGHT")
        row.icon:SetTexture(tabData.icon)
        row.name:SetText(tabData.name)
        local isAll = tabData.id == "ALL"

        row.visibleCheck:SetChecked(not tabData.hidden)
        row.visibleCheck:SetScript("OnClick", function(self)
            filters:SetTabHidden(tabData.id, not self:GetChecked())
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerList()
        end)
        row.visibleCheck:SetEnabled(not isAll) -- "All" is always visible, no exceptions
        row.upButton:SetScript("OnClick", function()
            filters:MoveTab(tabData.id, -1)
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerList()
        end)
        row.upButton:SetEnabled(i > 1 and not isAll)
        row.downButton:SetScript("OnClick", function()
            filters:MoveTab(tabData.id, 1)
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerList()
        end)
        row.downButton:SetEnabled(i < #tabs and not isAll)
        row:Show()
    end

    for i = #tabs + 1, #prefsFrame.tabRows do
        prefsFrame.tabRows[i]:Hide()
    end

    content:SetHeight(math.max(#tabs, 1) * TAB_MANAGER_ROW_HEIGHT)
end

-- The preferences window has outgrown a fixed-size dialog, so its controls
-- live in a scroll frame, and the window can be resized vertically (a grip
-- in the bottom-right corner) for screens without room for all of it. Width
-- stays fixed; the height is remembered between sessions.
local PREFS_WIDTH = 320
local PREFS_DEFAULT_HEIGHT = 760
local PREFS_MIN_HEIGHT = 300
local PREFS_TOP_INSET = 44 -- room for the title above the scrolling area
local PREFS_BOTTOM_INSET = 52 -- room for the Close button below it
local PREFS_SCROLLBAR_WIDTH = 28
local PREFS_CONTENT_HEIGHT = 700
local PREFS_TAB_LIST_HEIGHT = 200

local function GetPrefsMaxHeight()
    return math.max(PREFS_MIN_HEIGHT, UIParent:GetHeight() - 40)
end

local function ClampPrefsHeight(height)
    return math.min(math.max(height, PREFS_MIN_HEIGHT), GetPrefsMaxHeight())
end

local function ShowPreferencesFrame()
    if not prefsFrame then
        prefsFrame = CreateFrame("Frame", "EmbolsaoPreferencesFrame", UIParent, "BackdropTemplate")
        prefsFrame:SetSize(PREFS_WIDTH, ClampPrefsHeight(Embolsao.db.prefsFrameHeight or PREFS_DEFAULT_HEIGHT))
        prefsFrame:SetPoint("CENTER")
        prefsFrame:SetFrameStrata("DIALOG")
        prefsFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        prefsFrame:SetBackdropColor(0, 0, 0, 0.9)
        prefsFrame:SetMovable(true)
        prefsFrame:EnableMouse(true)
        prefsFrame:RegisterForDrag("LeftButton")
        prefsFrame:SetScript("OnDragStart", prefsFrame.StartMoving)
        prefsFrame:SetScript("OnDragStop", prefsFrame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "EmbolsaoPreferencesFrame")

        -- Vertical resizing only: the width bounds are pinned to one value.
        -- SetResizeBounds is the current API; older clients only have the
        -- Min/Max pair.
        prefsFrame:SetResizable(true)
        if prefsFrame.SetResizeBounds then
            prefsFrame:SetResizeBounds(PREFS_WIDTH, PREFS_MIN_HEIGHT, PREFS_WIDTH, GetPrefsMaxHeight())
        else
            prefsFrame:SetMinResize(PREFS_WIDTH, PREFS_MIN_HEIGHT)
            prefsFrame:SetMaxResize(PREFS_WIDTH, GetPrefsMaxHeight())
        end

        local close = CreateFrame("Button", nil, prefsFrame, "UIPanelCloseButtonDefaultAnchors")
        close:SetPoint("TOPRIGHT", -2, -2)

        prefsFrame.title = prefsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        prefsFrame.title:SetPoint("TOP", 0, -16)
        prefsFrame.title:SetText(L.PREFERENCES)

        -- Everything between the title and the Close button scrolls. The
        -- scroll frame leaves room on its right for the scrollbar the
        -- template draws just outside it; controls inside are positioned
        -- from the content frame's own top-left, as they were from the
        -- window's before.
        local scrollFrame = CreateFrame("ScrollFrame", nil, prefsFrame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 0, -PREFS_TOP_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -PREFS_SCROLLBAR_WIDTH, PREFS_BOTTOM_INSET)
        prefsFrame.scrollFrame = scrollFrame

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(PREFS_WIDTH - PREFS_SCROLLBAR_WIDTH, PREFS_CONTENT_HEIGHT)
        scrollFrame:SetScrollChild(content)
        prefsFrame.content = content

        prefsFrame.tabLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.tabLabel:SetPoint("TOPLEFT", 24, -8)
        prefsFrame.tabLabel:SetText(L.DEFAULT_TAB)

        -- Text automatically reflects whichever radio is selected -- no need
        -- to set it ourselves, Blizzard_Menu does that once the menu opens.
        prefsFrame.tabDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
        prefsFrame.tabDropdown:SetPoint("TOPLEFT", prefsFrame.tabLabel, "BOTTOMLEFT", 0, -6)
        prefsFrame.tabDropdown:SetWidth(220)
        prefsFrame.tabDropdown:SetupMenu(BuildDefaultTabMenu)

        prefsFrame.consolidateCheck = CreatePreferenceCheckbox(
            content, L.CONSOLIDATE_STACKS, "consolidateStacks", -78,
            function()
                Embolsao:ScanBags()
                Embolsao:ScanBank()
                UI:Refresh()
            end
        )

        prefsFrame.rememberPosCheck = CreatePreferenceCheckbox(
            content, L.REMEMBER_POSITION, "rememberPosition", -108
        )

        -- (Grouping by category / subcategory is per tab now: the sort menu and
        -- each tab's editor have it. The global values only seed tabs that
        -- haven't chosen.)
        prefsFrame.syncCategoryVisibilityCheck = CreatePreferenceCheckbox(
            content, L.SYNC_CATEGORY_VISIBILITY, "syncCategoryVisibility", -138,
            function() UI:Refresh() end
        )

        prefsFrame.minimapButtonCheck = CreatePreferenceCheckbox(
            content, L.MINIMAP_ENABLE_BUTTON, "showMinimapButton", -168,
            function() Embolsao.Minimap:SetShown(Embolsao.db.showMinimapButton) end
        )

        prefsFrame.mergeBankStorageCheck = CreatePreferenceCheckbox(
            content, L.MERGE_BANK_STORAGE, "mergeBankStorage", -198,
            function() UI:RefreshBankAvailability() end
        )

        -- Off: the bank pane shares the bags' tabs, as it used to. On (the
        -- default): it has its own, kept apart. Switching rebuilds both panes'
        -- tab bars, and the tab manager below follows (it only offers the
        -- bags/bank choice while this is on).
        prefsFrame.separateBankTabsCheck = CreatePreferenceCheckbox(
            content, L.SEPARATE_BANK_TABS, "separateBankTabs", -228,
            function()
                UI:BuildTabs()
                UI:Refresh()
                UpdateTabManagerDomainControl()
                RefreshTabManagerList()
            end
        )

        -- (Whether the Recent and Junk groups show is per tab now: each tab's editor
        -- has it. The global values only seed tabs that haven't chosen.)

        prefsFrame.autoSellJunkCheck = CreatePreferenceCheckbox(
            content, L.AUTO_SELL_JUNK, "autoSellJunk", -258
        )

        prefsFrame.closeOnCombatCheck = CreatePreferenceCheckbox(
            content, L.CLOSE_ON_COMBAT, "closeOnCombat", -288,
            function() UI:RefreshSecureToggle() end
        )

        -- Off: nothing is remembered at the bank, the button goes, and what was
        -- already saved is dropped.
        prefsFrame.offlineBankCheck = CreatePreferenceCheckbox(
            content, L.OFFLINE_BANK_PREF, "offlineBank", -318,
            function() UI:RefreshOfflineBank() end
        )

        -- How see-through the window gets while moving (the slider under it is
        -- only live while the option is on). Built by hand -- a bar and the
        -- stock thumb -- rather than from one of the slider templates, whose
        -- names differ between the clients.
        local function UpdateFadeSliderState()
            local on = Embolsao.db.fadeWhileMoving ~= false
            prefsFrame.fadeSlider:EnableMouse(on)
            prefsFrame.fadeSlider:SetAlpha(on and 1 or 0.4)
            prefsFrame.fadeSliderLabel:SetAlpha(on and 1 or 0.4)
        end

        prefsFrame.fadeWhileMovingCheck = CreatePreferenceCheckbox(
            content, L.FADE_WHILE_MOVING, "fadeWhileMoving", -348,
            function() UpdateFadeSliderState() end
        )

        prefsFrame.fadeSliderLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        prefsFrame.fadeSliderLabel:SetPoint("TOPLEFT", 52, -378)

        local fadeSlider = CreateFrame("Slider", nil, content)
        prefsFrame.fadeSlider = fadeSlider
        fadeSlider:SetOrientation("HORIZONTAL")
        fadeSlider:SetSize(200, 16)
        fadeSlider:SetPoint("TOPLEFT", 52, -394)
        fadeSlider:SetMinMaxValues(0.1, 0.9)
        fadeSlider:SetValueStep(0.05)
        if fadeSlider.SetObeyStepOnDrag then fadeSlider:SetObeyStepOnDrag(true) end
        local bar = fadeSlider:CreateTexture(nil, "BACKGROUND")
        bar:SetPoint("LEFT", 0, 0)
        bar:SetPoint("RIGHT", 0, 0)
        bar:SetHeight(4)
        bar:SetColorTexture(1, 1, 1, 0.25)
        fadeSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        fadeSlider:GetThumbTexture():SetSize(20, 20)
        fadeSlider:SetValue(Embolsao.db.fadeAlpha or 0.3)
        prefsFrame.fadeSliderLabel:SetText(string.format(L.FADE_OPACITY, math.floor((Embolsao.db.fadeAlpha or 0.3) * 100 + 0.5)))
        fadeSlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value * 20 + 0.5) / 20 -- to the step: 5% at a time
            Embolsao.db.fadeAlpha = value
            prefsFrame.fadeSliderLabel:SetText(string.format(L.FADE_OPACITY, math.floor(value * 100 + 0.5)))
        end)
        UpdateFadeSliderState()

        -- Not a plain Embolsao.db key -- it controls WHICH store Embolsao.db
        -- itself reads from (see Core.lua), so it needs its own get/set
        -- straight to EmbolsaoCharDB instead of going through CreatePreferenceCheckbox.
        prefsFrame.charSpecificCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        prefsFrame.charSpecificCheck:SetSize(24, 24)
        prefsFrame.charSpecificCheck:SetPoint("TOPLEFT", 24, -418)
        prefsFrame.charSpecificCheck:SetScript("OnClick", function(self)
            Embolsao:SetUseCharacterSpecificData(self:GetChecked())
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerList()
        end)

        prefsFrame.charSpecificLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.charSpecificLabel:SetPoint("LEFT", prefsFrame.charSpecificCheck, "RIGHT", 4, 0)
        prefsFrame.charSpecificLabel:SetText(L.CHARACTER_SPECIFIC_CUSTOMIZATION)

        prefsFrame.manageTabsLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.manageTabsLabel:SetPoint("TOPLEFT", 24, -452)
        prefsFrame.manageTabsLabel:SetText(L.MANAGE_TABS)

        -- Bags | Bank: which pane's tabs the list below manages. Only shown
        -- while the two panes have separate sets of tabs.
        prefsFrame.tabManagerDomain = "bags"
        prefsFrame.tabManagerDomainDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
        prefsFrame.tabManagerDomainDropdown:SetPoint("LEFT", prefsFrame.manageTabsLabel, "RIGHT", 12, 0)
        prefsFrame.tabManagerDomainDropdown:SetWidth(110)
        prefsFrame.tabManagerDomainDropdown:SetupMenu(function(_, rootDescription)
            local function IsSelected(domain) return prefsFrame.tabManagerDomain == domain end
            local function SetSelected(domain)
                prefsFrame.tabManagerDomain = domain
                RefreshTabManagerList()
            end
            rootDescription:CreateRadio(L.PANE_BAGS, IsSelected, SetSelected, "bags")
            rootDescription:CreateRadio(L.PANE_BANK, IsSelected, SetSelected, "bank")
        end)

        -- Fixed height now: it sits inside a scrolling area, so "fill down to
        -- the window's bottom edge" no longer means anything. It still scrolls
        -- on its own when there are more tabs than fit.
        prefsFrame.tabListScrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
        prefsFrame.tabListScrollFrame:SetPoint("TOPLEFT", prefsFrame.manageTabsLabel, "BOTTOMLEFT", 0, -8)
        prefsFrame.tabListScrollFrame:SetSize(PREFS_WIDTH - PREFS_SCROLLBAR_WIDTH - 24 - 36, PREFS_TAB_LIST_HEIGHT)

        prefsFrame.tabListContent = CreateFrame("Frame", nil, prefsFrame.tabListScrollFrame)
        prefsFrame.tabListContent:SetPoint("TOPLEFT")
        prefsFrame.tabListContent:SetSize(1, 1)
        prefsFrame.tabListScrollFrame:SetScrollChild(prefsFrame.tabListContent)

        local closeButton = CreateFrame("Button", nil, prefsFrame, "UIPanelButtonTemplate")
        closeButton:SetSize(100, 22)
        closeButton:SetPoint("BOTTOM", 0, 16)
        closeButton:SetText(CLOSE)
        closeButton:SetScript("OnClick", function() prefsFrame:Hide() end)

        -- Resize grip, bottom-right. StartSizing("BOTTOM") = vertical only.
        local grip = CreateFrame("Button", nil, prefsFrame)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", -4, 4)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetScript("OnMouseDown", function()
            prefsFrame:StartSizing("BOTTOM")
        end)
        grip:SetScript("OnMouseUp", function()
            prefsFrame:StopMovingOrSizing()
            Embolsao.db.prefsFrameHeight = math.floor(prefsFrame:GetHeight() + 0.5)
        end)
    end

    prefsFrame.charSpecificCheck:SetChecked(EmbolsaoCharDB.useCharacterSpecific)
    UpdateTabManagerDomainControl()
    RefreshTabManagerList()
    prefsFrame:Show()
end


UI.ShowPreferencesFrame = ShowPreferencesFrame
