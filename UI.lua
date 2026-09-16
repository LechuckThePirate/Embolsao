local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

Embolsao.UI = {}
local UI = Embolsao.UI

local TAB_ICON_SIZE = 30
local TAB_PADDING = 16
local TAB_PANEL_PADDING = 12
local TAB_TO_ITEMS_GAP = 18
local ITEM_SIZE = 37
local ITEM_PADDING = 4
local ITEMS_PER_ROW = 8 -- default/minimum; grows as the window is resized wider
local HEADER_ROW_HEIGHT = 20 -- Sort By Type class/subclass separators
local HEADER_INDENT_STEP = 14 -- per nesting level, so subclass headers read as nested under their class
local CONTENT_TOP_OFFSET = 70
local TOOLBAR_Y = -34 -- search box / menu button row, a bit above the item grid
-- UIPanelScrollFrameTemplate's scrollbar sits outside the scroll frame's own
-- right edge (anchored TOPRIGHT x=6, width 16) -- reserve that much space so
-- it doesn't overlap the last column of icons/tabs.
local SCROLLBAR_CLEARANCE = 22
local PORTRAIT_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icons\\embolsao-icon.png"

-- All the native frames we take over display duty from. Combined bags is one
-- frame; legacy (non-combined) mode can have the backpack plus up to 5 more
-- bag frames open side by side, so we cover the full set either way.
local NATIVE_BAG_FRAME_NAMES = {
    "ContainerFrameCombinedBags",
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
}

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/embolsao"

local frame
local tabButtons = {}
local itemButtons = {}
-- Forward-declared: CreateMainFrame calls these before they're defined below.
local CreateEmptySlotButton
local CreateMenuButton

-- GetMouseFocus() is the older single-frame API; newer clients expose
-- GetMouseFoci() (plural, topmost-first) instead and may not keep the old
-- one around, so try both rather than bet on either existing.
local function GetFrameUnderMouse()
    if GetMouseFoci then
        local foci = GetMouseFoci()
        return foci and foci[1]
    end
    if GetMouseFocus then
        return GetMouseFocus()
    end
    return nil
end

local aboutFrame

-- Standalone window (not a StaticPopup -- those can't fit an icon or a
-- clickable text field) that always opens screen-centered, independent of
-- wherever the main window happens to be parked.
local function ShowAboutFrame()
    if not aboutFrame then
        aboutFrame = CreateFrame("Frame", "EmbolsaoAboutFrame", UIParent, "BackdropTemplate")
        aboutFrame:SetSize(340, 260)
        aboutFrame:SetPoint("CENTER")
        aboutFrame:SetFrameStrata("DIALOG")
        aboutFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        aboutFrame:SetBackdropColor(0, 0, 0, 0.9)
        aboutFrame:SetMovable(true)
        aboutFrame:EnableMouse(true)
        aboutFrame:RegisterForDrag("LeftButton")
        aboutFrame:SetScript("OnDragStart", aboutFrame.StartMoving)
        aboutFrame:SetScript("OnDragStop", aboutFrame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "EmbolsaoAboutFrame")

        local close = CreateFrame("Button", nil, aboutFrame, "UIPanelCloseButtonDefaultAnchors")
        close:SetPoint("TOPRIGHT", -2, -2)

        aboutFrame.icon = aboutFrame:CreateTexture(nil, "ARTWORK")
        aboutFrame.icon:SetSize(64, 64)
        aboutFrame.icon:SetPoint("TOP", 0, -24)
        aboutFrame.icon:SetTexture(PORTRAIT_ICON)

        aboutFrame.info = aboutFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        aboutFrame.info:SetPoint("TOP", aboutFrame.icon, "BOTTOM", 0, -14)
        aboutFrame.info:SetJustifyH("CENTER")

        aboutFrame.urlLabel = aboutFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        aboutFrame.urlLabel:SetPoint("TOP", aboutFrame.info, "BOTTOM", 0, -20)
        aboutFrame.urlLabel:SetText(L.ABOUT_URL_LABEL)

        -- Read-only, auto-selects its full text on click/focus so the
        -- player can Ctrl+C it -- WoW addons have no API to write to the
        -- system clipboard directly. No template/backdrop on purpose: styled
        -- to read as a plain link (blue, no border/box) rather than an
        -- obvious input field.
        aboutFrame.urlBox = CreateFrame("EditBox", nil, aboutFrame)
        aboutFrame.urlBox:SetSize(300, 20)
        aboutFrame.urlBox:SetPoint("TOP", aboutFrame.urlLabel, "BOTTOM", 0, -6)
        aboutFrame.urlBox:SetAutoFocus(false)
        aboutFrame.urlBox:SetJustifyH("CENTER")
        aboutFrame.urlBox:SetFontObject(GameFontHighlightSmall)
        aboutFrame.urlBox:SetTextColor(0.4, 0.7, 1, 1)
        aboutFrame.urlBox:SetText(CURSEFORGE_URL)
        aboutFrame.urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        aboutFrame.urlBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        aboutFrame.urlBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        aboutFrame.urlBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        aboutFrame.urlBox:SetScript("OnEnter", function(self) self:SetTextColor(0.6, 0.85, 1, 1) end)
        aboutFrame.urlBox:SetScript("OnLeave", function(self) self:SetTextColor(0.4, 0.7, 1, 1) end)

        local closeButton = CreateFrame("Button", nil, aboutFrame, "UIPanelButtonTemplate")
        closeButton:SetSize(100, 22)
        closeButton:SetPoint("BOTTOM", 0, 16)
        closeButton:SetText(CLOSE)
        closeButton:SetScript("OnClick", function() aboutFrame:Hide() end)
    end

    local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = GetMeta(ADDON_NAME, "Version") or "?"
    local author = GetMeta(ADDON_NAME, "Author") or "?"
    aboutFrame.info:SetText(string.format("Embolsao!! v%s\n|cffffffffby %s|r", version, author))

    aboutFrame:Show()
end

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
local function RefreshTabManagerList()
    local content = prefsFrame.tabListContent
    prefsFrame.tabRows = prefsFrame.tabRows or {}

    local tabs = Embolsao.Filters:GetAllTabs()
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
            Embolsao.Filters:SetTabHidden(tabData.id, not self:GetChecked())
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerList()
        end)
        row.visibleCheck:SetEnabled(not isAll) -- "All" is always visible, no exceptions
        row.upButton:SetScript("OnClick", function()
            Embolsao.Filters:MoveTab(tabData.id, -1)
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerList()
        end)
        row.upButton:SetEnabled(i > 1 and not isAll)
        row.downButton:SetScript("OnClick", function()
            Embolsao.Filters:MoveTab(tabData.id, 1)
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

local function ShowPreferencesFrame()
    if not prefsFrame then
        prefsFrame = CreateFrame("Frame", "EmbolsaoPreferencesFrame", UIParent, "BackdropTemplate")
        prefsFrame:SetSize(320, 540)
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

        local close = CreateFrame("Button", nil, prefsFrame, "UIPanelCloseButtonDefaultAnchors")
        close:SetPoint("TOPRIGHT", -2, -2)

        prefsFrame.title = prefsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        prefsFrame.title:SetPoint("TOP", 0, -16)
        prefsFrame.title:SetText(L.PREFERENCES)

        prefsFrame.tabLabel = prefsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.tabLabel:SetPoint("TOPLEFT", 24, -52)
        prefsFrame.tabLabel:SetText(L.DEFAULT_TAB)

        -- Text automatically reflects whichever radio is selected -- no need
        -- to set it ourselves, Blizzard_Menu does that once the menu opens.
        prefsFrame.tabDropdown = CreateFrame("DropdownButton", nil, prefsFrame, "WowStyle1DropdownTemplate")
        prefsFrame.tabDropdown:SetPoint("TOPLEFT", prefsFrame.tabLabel, "BOTTOMLEFT", 0, -6)
        prefsFrame.tabDropdown:SetWidth(220)
        prefsFrame.tabDropdown:SetupMenu(BuildDefaultTabMenu)

        prefsFrame.consolidateCheck = CreatePreferenceCheckbox(
            prefsFrame, L.CONSOLIDATE_STACKS, "consolidateStacks", -122,
            function()
                Embolsao:ScanBags()
                UI:Refresh()
            end
        )

        prefsFrame.rememberPosCheck = CreatePreferenceCheckbox(
            prefsFrame, L.REMEMBER_POSITION, "rememberPosition", -152
        )

        prefsFrame.groupByClassCheck = CreatePreferenceCheckbox(
            prefsFrame, L.GROUP_BY_CLASS, "groupByClass", -182,
            function() UI:Refresh() end
        )

        prefsFrame.groupBySubClassCheck = CreatePreferenceCheckbox(
            prefsFrame, L.GROUP_BY_SUBCLASS, "groupBySubClass", -212,
            function() UI:Refresh() end
        )

        prefsFrame.manageTabsLabel = prefsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.manageTabsLabel:SetPoint("TOPLEFT", 24, -246)
        prefsFrame.manageTabsLabel:SetText(L.MANAGE_TABS)

        prefsFrame.tabListScrollFrame = CreateFrame("ScrollFrame", nil, prefsFrame, "UIPanelScrollFrameTemplate")
        prefsFrame.tabListScrollFrame:SetPoint("TOPLEFT", prefsFrame.manageTabsLabel, "BOTTOMLEFT", 0, -8)
        prefsFrame.tabListScrollFrame:SetPoint("BOTTOMRIGHT", -24 - 22, 50)

        prefsFrame.tabListContent = CreateFrame("Frame", nil, prefsFrame.tabListScrollFrame)
        prefsFrame.tabListContent:SetPoint("TOPLEFT")
        prefsFrame.tabListContent:SetSize(1, 1)
        prefsFrame.tabListScrollFrame:SetScrollChild(prefsFrame.tabListContent)

        local closeButton = CreateFrame("Button", nil, prefsFrame, "UIPanelButtonTemplate")
        closeButton:SetSize(100, 22)
        closeButton:SetPoint("BOTTOM", 0, 16)
        closeButton:SetText(CLOSE)
        closeButton:SetScript("OnClick", function() prefsFrame:Hide() end)
    end

    RefreshTabManagerList()
    prefsFrame:Show()
end

-- Reuses Blizzard's own "PortraitFrameFlatTemplate" (the same base every
-- portrait-style dialog in the game uses, bags included) so our window gets
-- the native background/border/portrait/close-button for free instead of a
-- hand-rolled backdrop.
local function CreateMainFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "EmbolsaoFrame", UIParent, "PortraitFrameFlatTemplate")
    local defaultWidth = TAB_ICON_SIZE + TAB_PANEL_PADDING * 2 + SCROLLBAR_CLEARANCE
        + TAB_TO_ITEMS_GAP
        + ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING) + SCROLLBAR_CLEARANCE + 20
    local defaultHeight = 420
    frame:SetSize(defaultWidth, defaultHeight)
    local savedPosition = Embolsao.db.rememberPosition and Embolsao.db.windowPosition
    if savedPosition then
        frame:SetPoint(savedPosition.point, UIParent, savedPosition.point, savedPosition.x, savedPosition.y)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if Embolsao.db.rememberPosition then
            local point, _, _, x, y = self:GetPoint()
            Embolsao.db.windowPosition = { point = point, x = x, y = y }
        end
    end)

    -- Reflow the item grid (column count depends on the item area's current
    -- width) on any size change, not just while the resize button is being
    -- actively dragged -- covers both live dragging and the final settle.
    frame:SetResizable(true)
    frame:SetScript("OnSizeChanged", function()
        UI:Refresh()
    end)

    local resizeButton = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
    resizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeButton:Init(frame, defaultWidth, defaultHeight, defaultWidth * 2, defaultHeight * 2)

    frame:Hide()

    -- Let Escape close us too, same as any other native panel.
    tinsert(UISpecialFrames, "EmbolsaoFrame")

    frame:SetPortraitToAsset(PORTRAIT_ICON)
    if frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText("Embolsao!!")
    elseif frame.TitleText then
        frame.TitleText:SetText("Embolsao!!")
    end

    -- Recessed side panel for the filter tabs, visually distinct from the
    -- item grid so tabs don't read as just more bag slots.
    frame.tabPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.tabPanel:SetPoint("TOPLEFT", 10, -CONTENT_TOP_OFFSET)
    frame.tabPanel:SetPoint("BOTTOMLEFT", 10, 10)
    frame.tabPanel:SetWidth(TAB_ICON_SIZE + TAB_PANEL_PADDING * 2 + SCROLLBAR_CLEARANCE)
    frame.tabPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame.tabPanel:SetBackdropColor(0, 0, 0, 0.35)
    frame.tabPanel:SetBackdropBorderColor(1, 1, 1, 0.25)

    -- Own search box, not Blizzard's native bag one (that just drives the
    -- native frame's own SetMatchesSearch dimming, which does nothing now
    -- that frame is hidden) -- filters our own list by item name instead.
    -- Aligned with the item grid's left edge (same X as itemContainer),
    -- not the window's, so it doesn't sit under the portrait icon.
    frame.searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    frame.searchBox:SetSize(150, 20)
    frame.searchBox:SetPoint("TOPLEFT", frame.tabPanel, "TOPRIGHT", TAB_TO_ITEMS_GAP, CONTENT_TOP_OFFSET + TOOLBAR_Y)
    frame.searchBox:HookScript("OnTextChanged", function(self)
        UI.searchText = self:GetText() or ""
        UI:Refresh()
    end)

    -- Both the tab column and the item grid are wrapped in a real
    -- UIPanelScrollFrameTemplate (mouse wheel + scrollbar included for
    -- free) instead of a fixed-size frame, since both lists can outgrow
    -- the visible area -- the item grid already does with a decent-sized
    -- inventory, and the tab column will too once custom tabs exist.
    frame.tabScrollFrame = CreateFrame("ScrollFrame", nil, frame.tabPanel, "UIPanelScrollFrameTemplate")
    frame.tabScrollFrame:SetPoint("TOPLEFT", TAB_PANEL_PADDING, -TAB_PANEL_PADDING)
    frame.tabScrollFrame:SetPoint("BOTTOMRIGHT", -TAB_PANEL_PADDING - SCROLLBAR_CLEARANCE, TAB_PANEL_PADDING)

    -- Anchored on TOPLEFT only, with an explicit width and a height kept up
    -- to date in UI:Refresh -- a scroll child's rect must always be fully
    -- resolved (single-anchor-only frames with no size were the whole
    -- "buttons exist but GetLeft/GetTop return nil" bug from earlier).
    frame.tabColumn = CreateFrame("Frame", nil, frame.tabScrollFrame)
    frame.tabColumn:SetPoint("TOPLEFT")
    frame.tabColumn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
    frame.tabScrollFrame:SetScrollChild(frame.tabColumn)

    -- Item grid, well clear of the tab panel, using real ItemButton widgets
    -- so icons/borders/counts render exactly like Blizzard's own bag slots.
    frame.itemScrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.itemScrollFrame:SetPoint("TOPLEFT", frame.tabPanel, "TOPRIGHT", TAB_TO_ITEMS_GAP, 0)
    frame.itemScrollFrame:SetPoint("BOTTOMRIGHT", -10 - SCROLLBAR_CLEARANCE, 10)

    frame.itemContainer = CreateFrame("Frame", nil, frame.itemScrollFrame)
    frame.itemContainer:SetPoint("TOPLEFT")
    frame.itemContainer:SetSize(ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING), ITEM_SIZE)
    frame.itemScrollFrame:SetScrollChild(frame.itemContainer)

    frame.emptySlotButton = CreateEmptySlotButton()
    frame.menuButton = CreateMenuButton()

    return frame
end

local function CreateTabButton(index, tabData)
    local btn = CreateFrame("Button", nil, frame.tabColumn)
    btn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
    btn:SetPoint("TOP", 0, -(index - 1) * (TAB_ICON_SIZE + TAB_PADDING))

    -- A background plate (plus the selection highlight below) makes these
    -- read as buttons rather than item slots, unlike the plain icon we used
    -- before.
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetPoint("TOPLEFT", -4, 4)
    btn.bg:SetPoint("BOTTOMRIGHT", 4, -4)
    btn.bg:SetColorTexture(0, 0, 0, 0.5)

    btn.selectedBg = btn:CreateTexture(nil, "BORDER")
    btn.selectedBg:SetAllPoints(btn.bg)
    btn.selectedBg:SetColorTexture(1, 0.82, 0, 0.35)
    btn.selectedBg:Hide()

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture(tabData.icon)
    -- Trim the icon's built-in border so square icons stack cleanly.
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tabData.name)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            Embolsao.TabEditor:ShowTabContextMenu(self, tabData)
            return
        end
        Embolsao.db.activeTab = tabData.id
        UI:Refresh()
    end)

    -- Drag-to-reorder: OnDragStart fires on this button, but OnDragStop
    -- also always fires here (not on whatever's under the cursor when you
    -- let go) -- so the drop target has to be looked up explicitly via
    -- GetFrameUnderMouse() rather than relied on to fire its own handler.
    -- "All" (tabData.id == "ALL") is exempt: it can't move and nothing can
    -- land ahead of it, enforced in Filters:MoveTabToPosition.
    btn.tabData = tabData
    if tabData.id ~= "ALL" then
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function(self)
            self:SetAlpha(0.4)
        end)
        btn:SetScript("OnDragStop", function(self)
            self:SetAlpha(1)
            local target = GetFrameUnderMouse()
            if target and target.tabData and target.tabData.id ~= self.tabData.id then
                Embolsao.Filters:MoveTabToPosition(self.tabData.id, target.tabData.id)
                UI:BuildTabs()
                UI:Refresh()
            end
        end)
    end

    return btn
end

-- Always the last button in the tab column, regardless of how many real
-- tabs exist -- opens the create-tab form.
local function CreateNewTabButton()
    local btn = CreateFrame("Button", nil, frame.tabColumn)
    btn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetPoint("TOPLEFT", -4, 4)
    btn.bg:SetPoint("BOTTOMRIGHT", 4, -4)
    btn.bg:SetColorTexture(0, 0, 0, 0.5)

    btn.label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    btn.label:SetAllPoints()
    btn.label:SetText("+")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.NEW_TAB_TOOLTIP)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    btn:SetScript("OnClick", function()
        Embolsao.TabEditor:Show(nil)
    end)

    return btn
end

local SORT_MODES = {
    { id = "NAME", label = L.SORT_NAME },
    { id = "TYPE", label = L.SORT_TYPE },
    { id = "QUANTITY", label = L.SORT_QUANTITY },
    { id = "QUALITY", label = L.SORT_QUALITY },
}

local function BuildEmbolsaoMenu(owner, rootDescription)
    local sortSubmenu = rootDescription:CreateButton(L.SORT_BY)

    local function IsSortSelected(mode)
        return Embolsao.db.sortMode == mode
    end
    local function SetSort(mode)
        Embolsao.db.sortMode = mode
        UI:Refresh()
    end

    for _, sortOption in ipairs(SORT_MODES) do
        sortSubmenu:CreateRadio(sortOption.label, IsSortSelected, SetSort, sortOption.id)
    end

    sortSubmenu:CreateDivider()

    local function IsDirectionSelected(ascending)
        return Embolsao.db.sortAscending == ascending
    end
    local function SetDirection(ascending)
        Embolsao.db.sortAscending = ascending
        UI:Refresh()
    end
    sortSubmenu:CreateRadio(L.SORT_ASCENDING, IsDirectionSelected, SetDirection, true)
    sortSubmenu:CreateRadio(L.SORT_DESCENDING, IsDirectionSelected, SetDirection, false)

    rootDescription:CreateDivider()

    rootDescription:CreateButton(L.PREFERENCES, ShowPreferencesFrame)

    rootDescription:CreateButton(L.ABOUT, ShowAboutFrame)
end

function CreateMenuButton()
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(70, 24)
    btn:SetPoint("TOPRIGHT", -16, TOOLBAR_Y)

    -- The exact arrow atlas Blizzard's own WowStyle2DropdownTemplate uses
    -- for its chevron (confirmed in MenuTemplates.xml) -- a Unicode triangle
    -- glyph turned out invisible, the default UI fonts don't cover it.
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("RIGHT", -2, 0)
    btn.icon:SetAtlas("common-dropdown-c-button-hover-arrow", true)

    btn.label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    btn.label:SetPoint("RIGHT", btn.icon, "LEFT", -4, 1)
    btn.label:SetText(L.MENU_TOOLTIP)

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.MENU_TOOLTIP)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    btn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, BuildEmbolsaoMenu)
    end)

    return btn
end

-- Callback StackSplitFrame invokes as button:SplitStack(amount) once the
-- player confirms a split quantity in its popup.
local function SplitItemStack(button, split)
    C_Container.SplitContainerItem(button:GetBagID(), button:GetID(), split)
end

-- The merged/virtual view has no visual "empty square" of its own (one
-- button per itemID, not per physical slot), so there's normally nowhere to
-- drop a picked-up or split-off item to start a new stack. This dedicated
-- slot is always the last button in the grid and targets the first
-- genuinely empty (bagID, slot) from Embolsao.EmptySlots.
function CreateEmptySlotButton()
    local btn = CreateFrame("ItemButton", nil, frame.itemContainer)
    btn.icon:SetAtlas("bags-item-slot64")
    btn.minDisplayCount = 0

    local function PlaceCursorItem()
        local slotInfo = Embolsao.EmptySlots and Embolsao.EmptySlots[1]
        if not slotInfo then return end
        C_Container.PickupContainerItem(slotInfo.bagID, slotInfo.slot)
    end

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.EMPTY_SLOT_TITLE)
        GameTooltip:AddLine(L.EMPTY_SLOT_DESC, 1, 1, 1, true)
        GameTooltip:Show()

        if CursorHasItem() then
            self.IconBorder:Show()
            self.IconBorder:SetVertexColor(1, 0.82, 0, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip_Hide()
        self.IconBorder:Hide()
    end)

    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function()
        if CursorHasItem() then
            PlaceCursorItem()
        end
    end)
    btn:SetScript("OnReceiveDrag", PlaceCursorItem)

    return btn
end

-- Bare "ItemButton" is Blizzard's own intrinsic widget type (icon + count +
-- quality border), the same one every item slot in the game is built from.
-- We don't pull in ContainerFrameItemButtonTemplate itself, since that one
-- hard-requires a real container-frame parent (it calls things like
-- self:GetParent():IsCombinedBagContainer()) -- not something we want to
-- fake just to show a merged/virtual stack that isn't one real bag slot.
--
-- Each button acts on entry.locations[1] -- the first real (bagID, slot)
-- backing that merged stack. Picking up/using it only affects that one real
-- stack, not the whole merged count; a real "expand to actual stacks" view
-- is future work (see the roadmap discussion).
-- Positioning is NOT done here -- it happens every UI:Refresh (even for
-- reused buttons), since the column count depends on the window's current
-- width and needs to reflow existing buttons too when that changes.
local function GetOrCreateItemButton(index)
    local btn = itemButtons[index]
    if btn then return btn end

    btn = CreateFrame("ItemButton", nil, frame.itemContainer)

    btn:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    btn:SetScript("OnHide", function(self)
        if self.hasStackSplit == 1 then
            StackSplitFrame:Hide()
        end
    end)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, mouseButton)
        if not self.itemID then return end
        local bagID, slot = self:GetBagID(), self:GetID()

        -- Our own Shift+right-click (ignore toggle) takes priority even
        -- though Shift is itself one of Blizzard's "modified click" keys.
        if mouseButton == "RightButton" and IsShiftKeyDown() then
            Embolsao:SetItemIgnored(self.itemID, not Embolsao:IsItemIgnored(self.itemID))
            UI:Refresh()
            return
        end

        -- Split stack: reuse Blizzard's own StackSplitFrame popup, the same
        -- one bags/bank/mail/trade all share, instead of building our own.
        if not CursorHasItem() and IsModifiedClick("SPLITSTACK") then
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            local itemCount = info and info.stackCount
            if itemCount and itemCount > 1 and not info.isLocked then
                self.SplitStack = SplitItemStack
                StackSplitFrame:OpenStackSplitFrame(itemCount, self, "BOTTOMRIGHT", "TOPRIGHT")
            end
            return
        end

        -- Any OTHER modified click (Alt/Ctrl/whatever the player has bound
        -- to Delete Item, Compare, etc. in Key Bindings -> Modified Click
        -- Actions) is something we don't replicate. Bail instead of
        -- guessing -- blindly falling through to UseContainerItem for e.g.
        -- Alt+right-click tripped WoW's protected-action guard.
        if IsModifiedClick() then
            return
        end

        if mouseButton == "RightButton" then
            C_Container.UseContainerItem(bagID, slot)
        else
            C_Container.PickupContainerItem(bagID, slot)
        end
    end)

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if not self.itemID then return end
        C_Container.PickupContainerItem(self:GetBagID(), self:GetID())
    end)
    btn:SetScript("OnReceiveDrag", function(self)
        if not self.itemID then return end
        C_Container.PickupContainerItem(self:GetBagID(), self:GetID())
    end)

    itemButtons[index] = btn
    return btn
end

-- Sort By Type class/subclass separators (Preferences -> Group By
-- Class/Subclass). A plain label + horizontal line, indented per nesting
-- level so a subclass header reads as nested under its class header.
local headerRows = {}

local function GetOrCreateHeaderRow(index)
    local header = headerRows[index]
    if header then return header end

    header = CreateFrame("Frame", nil, frame.itemContainer)
    header:SetHeight(HEADER_ROW_HEIGHT)

    header.text = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header.text:SetPoint("LEFT")

    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetHeight(1)
    header.line:SetColorTexture(1, 1, 1, 0.25)
    header.line:SetPoint("LEFT", header.text, "RIGHT", 6, 0)
    header.line:SetPoint("RIGHT")

    headerRows[index] = header
    return header
end

function UI:BuildTabs()
    for _, btn in ipairs(tabButtons) do
        btn:Hide()
    end
    wipe(tabButtons)

    -- Only visible tabs get a clickable button; hidden ones still exist for
    -- Preferences' tab manager and for GetFilteredEntries' tabs lookup below.
    frame.currentTabs = Embolsao.Filters:GetVisibleTabs()
    for index, tabData in ipairs(frame.currentTabs) do
        tabButtons[index] = CreateTabButton(index, tabData)
    end

    if not frame.newTabButton then
        frame.newTabButton = CreateNewTabButton()
    end
    local tabCount = #frame.currentTabs
    frame.newTabButton:SetPoint("TOP", 0, -tabCount * (TAB_ICON_SIZE + TAB_PADDING))
    frame.newTabButton:Show()

    frame.tabColumn:SetHeight((tabCount + 1) * (TAB_ICON_SIZE + TAB_PADDING))
end

function UI:UpdateSelectedTab()
    local activeTab = Embolsao.db.activeTab
    for index, tabData in ipairs(frame.currentTabs or {}) do
        local btn = tabButtons[index]
        local isActive = tabData.id == activeTab
        btn.icon:SetDesaturated(not isActive)
        btn.icon:SetAlpha(isActive and 1 or 0.55)
        btn.selectedBg:SetShown(isActive)
    end
end

-- Returns -1/0/1 for "a naturally comes before/tied/after b" regardless of
-- sort direction; the direction flag (sortAscending) is applied uniformly
-- afterward so every mode responds to the ascending/descending toggle the
-- same way, without each branch needing its own idea of "natural" order.
local function NaturalCompare(a, b)
    local mode = Embolsao.db.sortMode

    if mode == "QUANTITY" then
        if a.count ~= b.count then
            return a.count < b.count and -1 or 1
        end
    elseif mode == "QUALITY" then
        local qualityA, qualityB = a.quality or 0, b.quality or 0
        if qualityA ~= qualityB then
            return qualityA < qualityB and -1 or 1
        end
    elseif mode == "TYPE" then
        -- Compare by the localized class/subclass NAME, not the raw
        -- numeric classID -- Enum.ItemClass IDs don't run in alphabetical
        -- order (e.g. Consumable=0, Weapon=2, Armor=4), so sorting by ID
        -- produced a grouping order that looked arbitrary.
        local _, _, _, _, _, classA, subA = GetItemInfoInstant(a.itemID)
        local _, _, _, _, _, classB, subB = GetItemInfoInstant(b.itemID)
        local classNameA = classA and C_Item.GetItemClassInfo(classA) or ""
        local classNameB = classB and C_Item.GetItemClassInfo(classB) or ""
        if classNameA ~= classNameB then
            return classNameA < classNameB and -1 or 1
        end
        local subNameA = (classA and subA) and C_Item.GetItemSubClassInfo(classA, subA) or ""
        local subNameB = (classB and subB) and C_Item.GetItemSubClassInfo(classB, subB) or ""
        if subNameA ~= subNameB then
            return subNameA < subNameB and -1 or 1
        end
    else -- NAME (default)
        local nameA, nameB = GetItemInfo(a.itemID), GetItemInfo(b.itemID)
        if nameA and nameB and nameA ~= nameB then
            return nameA < nameB and -1 or 1
        end
    end

    return 0
end

-- itemID is always the tiebreaker (ascending, regardless of sort direction),
-- both for stability and as the fallback when the "real" sort data (name,
-- category) isn't available yet -- e.g. an item whose info hasn't been
-- cached client-side just falls back to itemID order until a later refresh.
local function CompareEntries(a, b)
    local natural = NaturalCompare(a, b)
    if natural ~= 0 then
        if Embolsao.db.sortAscending then
            return natural < 0
        else
            return natural > 0
        end
    end
    return a.itemID < b.itemID
end

function UI:GetFilteredEntries()
    local tabs = frame.currentTabs or Embolsao.Filters:GetAllTabs()
    local activeTab = Embolsao.db.activeTab

    local activeFilter
    for _, tab in ipairs(tabs) do
        if tab.id == activeTab then
            activeFilter = tab
            break
        end
    end
    activeFilter = activeFilter or tabs[1]

    local search = (self.searchText or ""):lower()

    local results = {}
    for _, entry in pairs(Embolsao.VirtualInventory) do
        if activeFilter.predicate(entry) then
            local matchesSearch = true
            if search ~= "" then
                local name = GetItemInfo(entry.itemID)
                matchesSearch = name ~= nil and name:lower():find(search, 1, true) ~= nil
            end
            if matchesSearch then
                table.insert(results, entry)
            end
        end
    end
    table.sort(results, CompareEntries)
    return results
end

-- Builds a flat sequence of {kind="header", level=, text=} and
-- {kind="item", entry=} rows to lay out, only when sorted by Type and at
-- least one grouping preference is on. Headers only ever appear when the
-- class/subclass actually changes between two consecutive (already sorted)
-- entries -- since we never invent a header for a class/subclass with no
-- entries in the list, an empty one simply never gets one, in either
-- sort direction (ascending/descending just changes the order we walk in,
-- not how boundaries are detected).
local function BuildLayoutRows(entries)
    local groupByClass = Embolsao.db.groupByClass
    local groupBySubClass = Embolsao.db.groupBySubClass

    local rows = {}
    if Embolsao.db.sortMode ~= "TYPE" or not (groupByClass or groupBySubClass) then
        for _, entry in ipairs(entries) do
            table.insert(rows, { kind = "item", entry = entry })
        end
        return rows
    end

    local lastClassID, lastSubClassID = nil, nil
    for _, entry in ipairs(entries) do
        local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(entry.itemID)

        if groupByClass and classID ~= lastClassID then
            table.insert(rows, { kind = "header", level = 0, text = C_Item.GetItemClassInfo(classID) or "?" })
            lastSubClassID = nil -- force the subclass header to repeat under the new class
        end

        if groupBySubClass and (classID ~= lastClassID or subClassID ~= lastSubClassID) then
            table.insert(rows, { kind = "header", level = 1, text = C_Item.GetItemSubClassInfo(classID, subClassID) or "?" })
        end

        table.insert(rows, { kind = "item", entry = entry })
        lastClassID, lastSubClassID = classID, subClassID
    end

    return rows
end

function UI:Refresh()
    if not frame or not frame:IsShown() then return end
    if not frame.currentTabs then
        self:BuildTabs()
    end
    self:UpdateSelectedTab()

    -- Column count tracks the item area's current width, so widening the
    -- window (resize grip, bottom-right) adds columns instead of just
    -- revealing empty space; the resize button's own min-width clamp keeps
    -- this from ever dropping below ITEMS_PER_ROW.
    local itemsPerRow = math.max(ITEMS_PER_ROW, math.floor(frame.itemScrollFrame:GetWidth() / (ITEM_SIZE + ITEM_PADDING)))
    frame.itemContainer:SetWidth(itemsPerRow * (ITEM_SIZE + ITEM_PADDING))

    local entries = self:GetFilteredEntries()
    local rows = BuildLayoutRows(entries)

    -- Headers and item cells have different row heights, so position is
    -- tracked as a running pixel offset rather than a uniform row index --
    -- a header always starts a fresh row (breaking out of a partial item
    -- row first if needed) and consumes HEADER_ROW_HEIGHT; items pack
    -- left-to-right at ITEM_SIZE+ITEM_PADDING each, wrapping at itemsPerRow.
    local yOffset, col = 0, 0
    local itemIndex, headerIndex = 0, 0

    for _, row in ipairs(rows) do
        if row.kind == "header" then
            if col > 0 then
                yOffset = yOffset + (ITEM_SIZE + ITEM_PADDING)
                col = 0
            end

            headerIndex = headerIndex + 1
            local header = GetOrCreateHeaderRow(headerIndex)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", row.level * HEADER_INDENT_STEP, -yOffset)
            header:SetPoint("TOPRIGHT", 0, -yOffset)
            header.text:SetFontObject(row.level == 0 and GameFontNormalSmall or GameFontDisableSmall)
            header.text:SetText(row.text)
            header:Show()

            yOffset = yOffset + HEADER_ROW_HEIGHT
        else
            local entry = row.entry
            itemIndex = itemIndex + 1
            local btn = GetOrCreateItemButton(itemIndex)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", col * (ITEM_SIZE + ITEM_PADDING), -yOffset)
            btn.itemID = entry.itemID
            local location = entry.locations and entry.locations[1]
            btn:SetBagID(location and location.bagID)
            btn:SetID(location and location.slot or 0)
            SetItemButtonTexture(btn, entry.icon)
            SetItemButtonCount(btn, entry.count)
            SetItemButtonQuality(btn, entry.quality, entry.itemID)
            btn:Show()

            col = col + 1
            if col >= itemsPerRow then
                col = 0
                yOffset = yOffset + (ITEM_SIZE + ITEM_PADDING)
            end
        end
    end

    for index = itemIndex + 1, #itemButtons do
        itemButtons[index].itemID = nil
        itemButtons[index]:Hide()
    end
    for index = headerIndex + 1, #headerRows do
        headerRows[index]:Hide()
    end

    -- Empty-slot button always comes right after the last real item,
    -- continuing on the current (possibly partial) row -- it's not tied to
    -- the active category or to grouping, just "the place to drop new
    -- stacks".
    local slotButton = frame.emptySlotButton
    slotButton:ClearAllPoints()
    slotButton:SetPoint("TOPLEFT", col * (ITEM_SIZE + ITEM_PADDING), -yOffset)
    slotButton.Count:SetText(tostring(#Embolsao.EmptySlots))
    slotButton.Count:Show()
    slotButton:Show()

    -- Whatever row the empty-slot button landed on, that row's height still
    -- counts toward the total scrollable content height.
    frame.itemContainer:SetHeight(yOffset + (ITEM_SIZE + ITEM_PADDING))
end

-- We take over display duty for bags entirely: our window shows, the native
-- frame(s) get hidden (not just dimmed) so there's only one bag UI on
-- screen. The guard flag matters because HIDING the native frame ourselves
-- fires its own OnHide script (which we also hook below) -- without the
-- flag, that would immediately hide our just-opened window right back.
--
-- The OnHide from our own Hide() call doesn't fire synchronously inside the
-- loop below -- it's deferred until the current OnShow dispatch finishes, so
-- clearing the flag has to wait a frame too (C_Timer.After(0, ...)) or the
-- deferred OnHide arrives after we've already un-guarded and hides us right
-- back. Confirmed by instrumenting both handlers and watching the actual
-- firing order in-game.
local nativeBagFrames = {}
local suppressingNativeHide = false

local function IsAnyNativeBagFrameShown()
    for _, bagFrame in ipairs(nativeBagFrames) do
        if bagFrame:IsShown() then
            return true
        end
    end
    return false
end

local function SuppressNativeBagFrames()
    suppressingNativeHide = true
    for _, bagFrame in ipairs(nativeBagFrames) do
        bagFrame:Hide()
    end
    C_Timer.After(0, function()
        suppressingNativeHide = false
    end)
end

local function OnBagFrameShow()
    CreateMainFrame()
    if not frame.currentTabs then
        UI:BuildTabs()
    end
    if Embolsao.db.defaultTab and Embolsao.db.defaultTab ~= "LAST" then
        Embolsao.db.activeTab = Embolsao.db.defaultTab
    end
    frame:Show()
    Embolsao:ScanBags()
    UI:Refresh()
    SuppressNativeBagFrames()
end

local function OnBagFrameHide()
    if suppressingNativeHide then return end
    if frame and not IsAnyNativeBagFrameShown() then
        frame:Hide()
    end
end

-- ContainerFrameCombinedBags/ContainerFrame1..6 belong to Blizzard_ContainerFrame,
-- a load-on-demand module that only loads the first time the player opens a bag.
-- It's almost never loaded yet at PLAYER_LOGIN, so we wait for its ADDON_LOADED
-- (and still check at PLAYER_LOGIN in case some other addon forced it earlier).
--
-- Known limitation: since we hide the native frame(s) rather than truly close
-- them, Blizzard's own "is the bag open" tracking thinks it's closed. Pressing
-- the bag keybind again won't close our window (it'll just look like nothing
-- happened) -- use the close button or Escape instead. Fixing the keybind
-- properly means overriding ToggleBackpack/ToggleAllBags themselves; flagged
-- for later if this turns out to be annoying in practice.
local hooksInstalled = false
local function InstallBagFrameHooks()
    if hooksInstalled then return end

    local foundAny = false
    for _, name in ipairs(NATIVE_BAG_FRAME_NAMES) do
        local bagFrame = _G[name]
        if bagFrame then
            foundAny = true
            table.insert(nativeBagFrames, bagFrame)
            bagFrame:HookScript("OnShow", OnBagFrameShow)
            bagFrame:HookScript("OnHide", OnBagFrameHide)
        end
    end

    if foundAny then
        hooksInstalled = true
    end
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon ~= "Blizzard_ContainerFrame" then
        return
    end
    InstallBagFrameHooks()
end)
