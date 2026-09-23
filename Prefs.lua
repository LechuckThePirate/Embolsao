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

local function CreatePreferenceCheckbox(parent, labelText, dbKey, anchorX, anchorY, onChange)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", anchorX, anchorY)
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

-- Bags and Bank each get their own always-visible panel side by side (no
-- picker to switch between them) -- when Preferences -> "Separate tabs for
-- Bank and Bags" is off, Embolsao:GetFilters("bank") already falls back to
-- the same shared set "bags" uses (Filters.lua), so the two panels just
-- naturally show identical lists rather than needing special-casing here.

-- One row per tab (built-in + custom, hidden ones included -- this is the
-- one place you can bring a hidden tab back). Up/down reuse the exact
-- arrow-button templates the scrollbar itself is built from, since a plain
-- Unicode arrow glyph turned out invisible earlier (default UI fonts don't
-- cover it) -- these are real textured buttons, not a font glyph.
local function RefreshTabManagerPanel(panel)
    local content = panel.listContent
    local filters = Embolsao:GetFilters(panel.domain)
    local tabs = filters:GetAllTabs()
    for i, tabData in ipairs(tabs) do
        local row = panel.rows[i]
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

            row.deleteButton = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
            row.deleteButton:SetSize(18, 18)
            row.deleteButton:SetPoint("RIGHT", 0, 0)

            panel.rows[i] = row
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
            RefreshTabManagerPanel(panel)
        end)
        row.visibleCheck:SetEnabled(not isAll) -- "All" is always visible, no exceptions
        row.upButton:SetScript("OnClick", function()
            filters:MoveTab(tabData.id, -1)
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerPanel(panel)
        end)
        row.upButton:SetEnabled(i > 1 and not isAll)
        row.downButton:SetScript("OnClick", function()
            filters:MoveTab(tabData.id, 1)
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerPanel(panel)
        end)
        row.downButton:SetEnabled(i < #tabs and not isAll)
        row.deleteButton:SetShown(not tabData.isBuiltIn)
        row.deleteButton:SetScript("OnClick", function()
            StaticPopup_Show("EMBOLSAO_DELETE_TAB", tabData.name, nil, { tabID = tabData.id, domain = panel.domain })
        end)
        row:Show()
    end

    for i = #tabs + 1, #panel.rows do
        panel.rows[i]:Hide()
    end

    content:SetHeight(math.max(#tabs, 1) * TAB_MANAGER_ROW_HEIGHT)
end

local function RefreshTabManagerList()
    if prefsFrame.bagsPanel then RefreshTabManagerPanel(prefsFrame.bagsPanel) end
    if prefsFrame.bankPanel then RefreshTabManagerPanel(prefsFrame.bankPanel) end
end

local PREFS_TAB_PANEL_WIDTH = 272

-- One self-contained Manage Tabs zone (label + bordered/backgrounded scroll
-- area) for a single domain ("bags" or "bank") -- built twice, side by
-- side, instead of one shared list behind a picker.
local function BuildTabManagerPanel(parent, domain, labelText, x, y)
    local panel = { domain = domain, rows = {} }

    panel.label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    panel.label:SetPoint("TOPLEFT", x, y)
    panel.label:SetText(labelText)

    -- A backdrop behind the scroll frame -- same subtle panel style as the
    -- item window's own tab strip / footer (UI.lua) -- so this reads as its
    -- own bordered zone instead of blending into the window's plain
    -- background.
    panel.backdrop = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel.backdrop:SetPoint("TOPLEFT", panel.label, "BOTTOMLEFT", -6, -8)
    panel.backdrop:SetSize(PREFS_TAB_PANEL_WIDTH, PREFS_TAB_LIST_HEIGHT + 12)
    panel.backdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel.backdrop:SetBackdropColor(1, 1, 1, 0.06)
    panel.backdrop:SetBackdropBorderColor(1, 1, 1, 0.3)

    panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel.backdrop, "UIPanelScrollFrameTemplate")
    panel.scrollFrame:SetPoint("TOPLEFT", 8, -6)
    panel.scrollFrame:SetSize(PREFS_TAB_PANEL_WIDTH - 8 - 36, PREFS_TAB_LIST_HEIGHT)

    panel.listContent = CreateFrame("Frame", nil, panel.scrollFrame)
    panel.listContent:SetPoint("TOPLEFT")
    panel.listContent:SetSize(1, 1)
    panel.scrollFrame:SetScrollChild(panel.listContent)

    return panel
end

local function FormatLastPlayed(savedAt)
    local days = math.floor((time() - (savedAt or time())) / 86400)
    if days <= 0 then return L.TIME_TODAY end
    return string.format(L.TIME_DAYS_AGO, days)
end

local function RefreshCharSpecificState()
    prefsFrame.charSpecificCheck:SetChecked(EmbolsaoCharDB.useCharacterSpecific)
    UI:BuildTabs()
    UI:Refresh()
    RefreshTabManagerList()
end

StaticPopupDialogs["EMBOLSAO_COPY_PREFERENCES"] = {
    text = L.COPY_PREFERENCES_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        if Embolsao:CopyPreferencesFromCharacter(data.charKey) then
            RefreshCharSpecificState()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["EMBOLSAO_RESET_TO_SHARED"] = {
    text = L.RESET_TO_SHARED_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        Embolsao:ResetCharacterToShared()
        RefreshCharSpecificState()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["EMBOLSAO_RESET_TO_DEFAULT_TABS"] = {
    text = L.RESET_TO_DEFAULT_TABS_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        Embolsao:ResetCharacterToDefault()
        RefreshCharSpecificState()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- The preferences window has outgrown a fixed-size dialog, so its controls
-- live in a scroll frame, and the window can be resized vertically (a grip
-- in the bottom-right corner) for screens without room for all of it. Width
-- stays fixed; the height is remembered between sessions.
-- Two columns (PREFS_COLUMN1_X / PREFS_COLUMN2_X below) instead of one long
-- list -- wider and much shorter than the single-column layout this
-- replaced, which had grown tall enough to need constant scrolling every
-- time a new preference was added.
local PREFS_WIDTH = 620
local PREFS_DEFAULT_HEIGHT = 686
local PREFS_MIN_HEIGHT = 300
local PREFS_TOP_INSET = 44 -- room for the title above the scrolling area
local PREFS_BOTTOM_INSET = 52 -- room for the Close button below it
local PREFS_SCROLLBAR_WIDTH = 28
local PREFS_CONTENT_HEIGHT = 590
local PREFS_TAB_LIST_HEIGHT = 130
local PREFS_COLUMN1_X = 24
local PREFS_COLUMN2_X = 320

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

        --------------------------------------------------------------------
        -- Two columns of checkboxes, five rows, left and right filled at
        -- the same Y so they read as an actual grid.
        --------------------------------------------------------------------
        prefsFrame.consolidateCheck = CreatePreferenceCheckbox(
            content, L.CONSOLIDATE_STACKS, "consolidateStacks", PREFS_COLUMN1_X, -78,
            function()
                Embolsao:ScanBags()
                Embolsao:ScanBank()
                UI:Refresh()
            end
        )

        prefsFrame.rememberPosCheck = CreatePreferenceCheckbox(
            content, L.REMEMBER_POSITION, "rememberPosition", PREFS_COLUMN1_X, -108
        )

        -- (Grouping by category / subcategory is per tab now: the sort menu and
        -- each tab's editor have it. The global values only seed tabs that
        -- haven't chosen.)
        prefsFrame.syncCategoryVisibilityCheck = CreatePreferenceCheckbox(
            content, L.SYNC_CATEGORY_VISIBILITY, "syncCategoryVisibility", PREFS_COLUMN1_X, -138,
            function() UI:Refresh() end
        )

        prefsFrame.minimapButtonCheck = CreatePreferenceCheckbox(
            content, L.MINIMAP_ENABLE_BUTTON, "showMinimapButton", PREFS_COLUMN1_X, -168,
            function() Embolsao.Minimap:SetShown(Embolsao.db.showMinimapButton) end
        )

        prefsFrame.mergeBankStorageCheck = CreatePreferenceCheckbox(
            content, L.MERGE_BANK_STORAGE, "mergeBankStorage", PREFS_COLUMN1_X, -198,
            function() UI:RefreshBankAvailability() end
        )

        -- Off: the bank pane shares the bags' tabs, as it used to (and the
        -- Bank panel below just mirrors the Bags one). On (the default): it
        -- has its own, kept apart.
        prefsFrame.separateBankTabsCheck = CreatePreferenceCheckbox(
            content, L.SEPARATE_BANK_TABS, "separateBankTabs", PREFS_COLUMN2_X, -78,
            function()
                UI:BuildTabs()
                UI:Refresh()
                RefreshTabManagerList()
            end
        )

        -- (Whether the Recent and Junk groups show is per tab now: each tab's editor
        -- has it. The global values only seed tabs that haven't chosen.)

        prefsFrame.autoSellJunkCheck = CreatePreferenceCheckbox(
            content, L.AUTO_SELL_JUNK, "autoSellJunk", PREFS_COLUMN2_X, -108
        )

        prefsFrame.closeOnCombatCheck = CreatePreferenceCheckbox(
            content, L.CLOSE_ON_COMBAT, "closeOnCombat", PREFS_COLUMN2_X, -138,
            function() UI:RefreshSecureToggle() end
        )

        -- Off: nothing is remembered at the bank, the button goes, and what was
        -- already saved is dropped.
        prefsFrame.offlineBankCheck = CreatePreferenceCheckbox(
            content, L.OFFLINE_BANK_PREF, "offlineBank", PREFS_COLUMN2_X, -168,
            function() UI:RefreshOfflineBank() end
        )

        -- Not a plain Embolsao.db key -- it controls WHICH store Embolsao.db
        -- itself reads from (see Core.lua), so it needs its own get/set
        -- straight to EmbolsaoCharDB instead of going through CreatePreferenceCheckbox.
        -- Pulled out of the checkbox grid and up next to Default Tab
        -- (same height) -- important enough, and affecting every other
        -- preference below it, to read as separate rather than just one
        -- more checkbox in the list.
        prefsFrame.charSpecificCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        prefsFrame.charSpecificCheck:SetSize(24, 24)
        prefsFrame.charSpecificCheck:SetPoint("TOPLEFT", PREFS_COLUMN2_X, -8)
        prefsFrame.charSpecificCheck:SetScript("OnClick", function(self)
            Embolsao:SetUseCharacterSpecificData(self:GetChecked())
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerList()
        end)

        prefsFrame.charSpecificLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.charSpecificLabel:SetPoint("LEFT", prefsFrame.charSpecificCheck, "RIGHT", 4, 0)
        prefsFrame.charSpecificLabel:SetText(L.CHARACTER_SPECIFIC_CUSTOMIZATION)

        --------------------------------------------------------------------
        -- Sliders, side by side: background opacity (always live) on the
        -- left, fade-while-moving (checkbox + its own slider) on the right.
        --------------------------------------------------------------------
        prefsFrame.bgOpacityLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.bgOpacityLabel:SetPoint("TOPLEFT", PREFS_COLUMN1_X, -228)

        local bgOpacitySlider = CreateFrame("Slider", nil, content)
        prefsFrame.bgOpacitySlider = bgOpacitySlider
        bgOpacitySlider:SetOrientation("HORIZONTAL")
        bgOpacitySlider:SetSize(240, 16)
        bgOpacitySlider:SetPoint("TOPLEFT", PREFS_COLUMN1_X + 4, -252)
        bgOpacitySlider:SetMinMaxValues(0.1, 1.0)
        bgOpacitySlider:SetValueStep(0.05)
        if bgOpacitySlider.SetObeyStepOnDrag then bgOpacitySlider:SetObeyStepOnDrag(true) end
        local bgBar = bgOpacitySlider:CreateTexture(nil, "BACKGROUND")
        bgBar:SetPoint("LEFT", 0, 0)
        bgBar:SetPoint("RIGHT", 0, 0)
        bgBar:SetHeight(4)
        bgBar:SetColorTexture(1, 1, 1, 0.25)
        bgOpacitySlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        bgOpacitySlider:GetThumbTexture():SetSize(20, 20)
        bgOpacitySlider:SetValue(Embolsao.db.backgroundOpacity or 1)
        prefsFrame.bgOpacityLabel:SetText(string.format(L.BACKGROUND_OPACITY, math.floor((Embolsao.db.backgroundOpacity or 1) * 100 + 0.5)))
        bgOpacitySlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value * 20 + 0.5) / 20 -- to the step: 5% at a time
            Embolsao.db.backgroundOpacity = value
            prefsFrame.bgOpacityLabel:SetText(string.format(L.BACKGROUND_OPACITY, math.floor(value * 100 + 0.5)))
            UI:RefreshBackgroundOpacity()
        end)

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
            content, L.FADE_WHILE_MOVING, "fadeWhileMoving", PREFS_COLUMN2_X, -228,
            function() UpdateFadeSliderState() end
        )

        prefsFrame.fadeSliderLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        prefsFrame.fadeSliderLabel:SetPoint("TOPLEFT", PREFS_COLUMN2_X + 28, -256)

        local fadeSlider = CreateFrame("Slider", nil, content)
        prefsFrame.fadeSlider = fadeSlider
        fadeSlider:SetOrientation("HORIZONTAL")
        fadeSlider:SetSize(240, 16)
        fadeSlider:SetPoint("TOPLEFT", PREFS_COLUMN2_X + 28, -272)
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

        --------------------------------------------------------------------
        -- Cross-character preference copy/reset: this character's own
        -- customization only, never touches any other character's data or
        -- the shared pool's own contents (except reading from it). Copy on
        -- the left, the two resets stacked on the right.
        --------------------------------------------------------------------
        prefsFrame.copyPrefsLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.copyPrefsLabel:SetPoint("TOPLEFT", PREFS_COLUMN1_X, -320)
        prefsFrame.copyPrefsLabel:SetText(L.COPY_PREFERENCES_FROM)

        prefsFrame.copyPrefsDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
        prefsFrame.copyPrefsDropdown:SetPoint("TOPLEFT", prefsFrame.copyPrefsLabel, "BOTTOMLEFT", -4, -6)
        prefsFrame.copyPrefsDropdown:SetWidth(170)
        prefsFrame.copyPrefsDropdown:SetDefaultText(L.COPY_PREFERENCES_NONE)
        prefsFrame.copyPrefsDropdown:SetupMenu(function(_, rootDescription)
            local function IsSelected(charKey) return prefsFrame.copyPrefsSource == charKey end
            local function SetSelected(charKey) prefsFrame.copyPrefsSource = charKey end

            local snapshots = Embolsao:GetCharacterSnapshots()
            local charKeys = {}
            for charKey in pairs(snapshots) do table.insert(charKeys, charKey) end
            table.sort(charKeys)

            if #charKeys == 0 then
                rootDescription:CreateTitle(L.COPY_PREFERENCES_NONE)
                return
            end
            for _, charKey in ipairs(charKeys) do
                local snapshot = snapshots[charKey]
                local label = string.format(L.COPY_PREFERENCES_LAST_PLAYED, snapshot.name, FormatLastPlayed(snapshot.savedAt))
                rootDescription:CreateRadio(label, IsSelected, SetSelected, charKey)
            end
        end)

        prefsFrame.copyPrefsButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        prefsFrame.copyPrefsButton:SetSize(70, 22)
        prefsFrame.copyPrefsButton:SetPoint("LEFT", prefsFrame.copyPrefsDropdown, "RIGHT", 8, 0)
        prefsFrame.copyPrefsButton:SetText(L.COPY)
        prefsFrame.copyPrefsButton:SetScript("OnClick", function()
            local charKey = prefsFrame.copyPrefsSource
            local snapshot = charKey and Embolsao:GetCharacterSnapshots()[charKey]
            if not snapshot then return end
            StaticPopup_Show("EMBOLSAO_COPY_PREFERENCES", snapshot.name, nil, { charKey = charKey })
        end)

        prefsFrame.resetToSharedButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        prefsFrame.resetToSharedButton:SetSize(240, 22)
        prefsFrame.resetToSharedButton:SetPoint("TOPLEFT", PREFS_COLUMN2_X, -320)
        prefsFrame.resetToSharedButton:SetText(L.RESET_TO_SHARED)
        prefsFrame.resetToSharedButton:SetScript("OnClick", function()
            StaticPopup_Show("EMBOLSAO_RESET_TO_SHARED")
        end)

        prefsFrame.resetToDefaultButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        prefsFrame.resetToDefaultButton:SetSize(240, 22)
        prefsFrame.resetToDefaultButton:SetPoint("TOPLEFT", prefsFrame.resetToSharedButton, "BOTTOMLEFT", 0, -8)
        prefsFrame.resetToDefaultButton:SetText(L.RESET_TO_DEFAULT_TABS)
        prefsFrame.resetToDefaultButton:SetScript("OnClick", function()
            StaticPopup_Show("EMBOLSAO_RESET_TO_DEFAULT_TABS")
        end)

        --------------------------------------------------------------------
        -- Manage Tabs: full width, it needs the room (icon + name + up/down/
        -- visible/delete per row).
        --------------------------------------------------------------------
        prefsFrame.bagsPanel = BuildTabManagerPanel(content, "bags", L.PANE_BAGS, PREFS_COLUMN1_X, -400)
        prefsFrame.bankPanel = BuildTabManagerPanel(content, "bank", L.PANE_BANK, PREFS_COLUMN2_X, -400)

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
    prefsFrame.copyPrefsSource = nil
    prefsFrame.copyPrefsDropdown:GenerateMenu()
    RefreshTabManagerList()
    prefsFrame:Show()
end


UI.ShowPreferencesFrame = ShowPreferencesFrame
-- Set unconditionally (not just while the window is shown) -- called from
-- TabEditor.lua's EMBOLSAO_DELETE_TAB popup, reachable from both the tab
-- bar's own right-click menu and this file's Manage Tabs delete button, so
-- it has to work whether or not Preferences happens to be open right now.
UI.RefreshTabManagerList = function()
    if prefsFrame and prefsFrame:IsShown() then
        RefreshTabManagerList()
    end
end
