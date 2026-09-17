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
local FOOTER_HEIGHT = 24 -- money + XP strip, pinned below the scroll areas
local FOOTER_GAP = 6 -- breathing room between the item grid and the footer
local BOTTOM_MARGIN = 4 -- from the tab panel/footer down to the window's own edge
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
local FEEDBACK_EMAIL = "lechuckthepirate@gmail.com"

-- Mirrors the latest entry in CHANGELOG.md -- update this alongside it (and
-- the version bump) on every release, it's shown as-is in the beta notice
-- popup's changelog box.
local LATEST_CHANGELOG_TEXT = [[
- Category headers (Sort By Category) can now be collapsed/expanded individually, plus Collapse All / Expand All in the main menu. Collapse state can be remembered per tab or shared across every tab.
- Renamed "Sort By: Type" to "Sort By: Category".
- Right-click empty space on the tab bar to quickly re-show hidden tabs.
- Tab/filter customization is now shared across every character by default, like Blizzard's own Account Keybindings, with a new preference to make one character keep its own copy instead.
- Empty bag slots are now grouped into a dedicated "Empty Slots" category: one counter for ordinary bags, plus a separate counter for each special bag equipped (reagent bag, keyring). Right-click a counter to open just that bag.
- Keyring contents (Classic Era/TBC) are now shown in the merged inventory too, not just counted.
- Added a money and XP footer pinned to the bottom of the window.
- Bank bags can now be opened at the same time as Embolsao's own window.
- Fixed a bag-opening crash and a stale keyring/reagent bag mix-up on retail.
- Fixed a bagID collision on Classic Era/TBC affecting the first bank bag.
- Fixed the bag keybind (B) occasionally getting stuck on Blizzard's native bags after peeking at a special bag.
- Added this "still in beta" notice.]]

local frame
local tabButtons = {}
local itemButtons = {}
-- Forward-declared: CreateMainFrame calls this before it's defined below.
local CreateMenuButton

-- Small icon that follows the cursor while dragging a tab to reorder it --
-- without this, dragging looked like it did nothing until you let go.
-- Smaller than the real tab icon on purpose -- at full size the ghost sat
-- right on top of the drop-line indicator and hid it.
local DRAG_GHOST_SIZE = TAB_ICON_SIZE * 0.5

local dragGhost

local function EnsureDragGhost()
    if dragGhost then return dragGhost end

    dragGhost = CreateFrame("Frame", nil, UIParent)
    dragGhost:SetSize(DRAG_GHOST_SIZE, DRAG_GHOST_SIZE)
    dragGhost:SetFrameStrata("TOOLTIP")
    dragGhost:EnableMouse(false)
    dragGhost:Hide()

    dragGhost.icon = dragGhost:CreateTexture(nil, "OVERLAY")
    dragGhost.icon:SetAllPoints()
    dragGhost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dragGhost.icon:SetAlpha(0.9)

    return dragGhost
end

local function UpdateDragGhostPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    dragGhost:ClearAllPoints()
    dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale + TAB_ICON_SIZE)
end

-- Bar shown between two tabs at wherever the dragged tab would land --
-- clearer than highlighting a whole target button, since it shows the
-- actual insertion point rather than "swap with this one". Thick and bright
-- on purpose so it still reads clearly with the drag ghost hovering nearby.
local dropIndicator

local function EnsureDropIndicator()
    if dropIndicator then return dropIndicator end
    dropIndicator = frame.tabColumn:CreateTexture(nil, "OVERLAY")
    dropIndicator:SetHeight(4)
    dropIndicator:SetColorTexture(0.3, 1, 1, 1)
    dropIndicator:Hide()
    return dropIndicator
end

-- Reads the identity of whatever item is on the cursor (without consuming
-- it -- handed right back to its own slot) and, if there is one, asks for
-- confirmation to hide it on the given tab. Used when an item from the bag
-- grid gets dropped straight onto a tab button.
local function TryHideCursorItemOnTab(tabData)
    local cursorItem = C_Cursor.GetCursorItem()
    if not cursorItem then return end
    local bagID, slot = cursorItem:GetBagAndSlot()
    if not bagID then return end

    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if info and info.itemID then
        Embolsao.TabEditor:ConfirmHideItemOnTab(info.itemID, tabData)
    end

    C_Container.PickupContainerItem(bagID, slot)
end

-- Returns the tab button the drag should insert before (or, for the very
-- last slot, the one to insert after) plus that placeAfter flag.
--
-- Deliberately NOT based on "which button is under the cursor" -- that left
-- a dead zone in the gap between two icons (TAB_PADDING of empty space) where
-- nothing was hovered and the indicator just disappeared, which read as the
-- drop target snapping to "on top of an icon" instead of "between icons".
-- Walking the column by Y position covers every pixel continuously: the
-- first button whose center the cursor is still above (screen Y increases
-- upward) is where the icon would land, whether the cursor is directly over
-- an icon or sitting in the gap before it.
local function GetDropTarget(draggedButton)
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / UIParent:GetEffectiveScale()

    for _, btn in ipairs(tabButtons) do
        if btn ~= draggedButton and btn.tabData then
            local _, centerY = btn:GetCenter()
            if centerY and cursorY > centerY then
                return btn, false
            end
        end
    end

    -- Cursor is below every other button: land after the last one.
    for i = #tabButtons, 1, -1 do
        local btn = tabButtons[i]
        if btn ~= draggedButton and btn.tabData then
            return btn, true
        end
    end

    return nil
end

local function GetAddonVersion()
    local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return GetMeta(ADDON_NAME, "Version") or "?"
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
    local author = GetMeta(ADDON_NAME, "Author") or "?"
    aboutFrame.info:SetText(string.format("Embolsao!! v%s\n|cffffffffby %s|r", GetAddonVersion(), author))

    aboutFrame:Show()
end

local betaNoticeFrame

-- Shown once per login (PLAYER_LOGIN in Core.lua) until dismissed via its
-- own checkbox -- same standalone/screen-centered treatment as the About
-- window, just bigger to fit the changelog box.
local function ShowBetaNoticeFrame()
    if not betaNoticeFrame then
        betaNoticeFrame = CreateFrame("Frame", "EmbolsaoBetaNoticeFrame", UIParent, "BackdropTemplate")
        betaNoticeFrame:SetSize(380, 480)
        betaNoticeFrame:SetPoint("CENTER")
        betaNoticeFrame:SetFrameStrata("DIALOG")
        betaNoticeFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        betaNoticeFrame:SetBackdropColor(0, 0, 0, 0.9)
        betaNoticeFrame:SetMovable(true)
        betaNoticeFrame:EnableMouse(true)
        betaNoticeFrame:RegisterForDrag("LeftButton")
        betaNoticeFrame:SetScript("OnDragStart", betaNoticeFrame.StartMoving)
        betaNoticeFrame:SetScript("OnDragStop", betaNoticeFrame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "EmbolsaoBetaNoticeFrame")

        local close = CreateFrame("Button", nil, betaNoticeFrame, "UIPanelCloseButtonDefaultAnchors")
        close:SetPoint("TOPRIGHT", -2, -2)

        betaNoticeFrame.icon = betaNoticeFrame:CreateTexture(nil, "ARTWORK")
        betaNoticeFrame.icon:SetSize(48, 48)
        betaNoticeFrame.icon:SetPoint("TOP", 0, -16)
        betaNoticeFrame.icon:SetTexture(PORTRAIT_ICON)

        betaNoticeFrame.title = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        betaNoticeFrame.title:SetPoint("TOP", 0, -70)
        betaNoticeFrame.title:SetText(L.BETA_NOTICE_TITLE)

        betaNoticeFrame.body = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        betaNoticeFrame.body:SetPoint("TOP", 0, -96)
        betaNoticeFrame.body:SetWidth(340)
        betaNoticeFrame.body:SetJustifyH("CENTER")
        betaNoticeFrame.body:SetText(L.BETA_NOTICE_BODY)

        -- Read-only, auto-selects its full text on click/focus so the player
        -- can Ctrl+C it, same trick as the About window's CurseForge link --
        -- there's no API to write to the system clipboard directly.
        betaNoticeFrame.emailBox = CreateFrame("EditBox", nil, betaNoticeFrame)
        betaNoticeFrame.emailBox:SetSize(300, 20)
        betaNoticeFrame.emailBox:SetPoint("TOP", betaNoticeFrame.body, "BOTTOM", 0, -10)
        betaNoticeFrame.emailBox:SetAutoFocus(false)
        betaNoticeFrame.emailBox:SetJustifyH("CENTER")
        betaNoticeFrame.emailBox:SetFontObject(GameFontHighlightSmall)
        betaNoticeFrame.emailBox:SetTextColor(0.4, 0.7, 1, 1)
        betaNoticeFrame.emailBox:SetText(FEEDBACK_EMAIL)
        betaNoticeFrame.emailBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        betaNoticeFrame.emailBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        betaNoticeFrame.emailBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        betaNoticeFrame.emailBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        betaNoticeFrame.emailBox:SetScript("OnEnter", function(self) self:SetTextColor(0.6, 0.85, 1, 1) end)
        betaNoticeFrame.emailBox:SetScript("OnLeave", function(self) self:SetTextColor(0.4, 0.7, 1, 1) end)

        betaNoticeFrame.changelogLabel = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        betaNoticeFrame.changelogLabel:SetPoint("TOPLEFT", 20, -180)

        betaNoticeFrame.changelogScroll = CreateFrame("ScrollFrame", nil, betaNoticeFrame, "UIPanelScrollFrameTemplate")
        betaNoticeFrame.changelogScroll:SetPoint("TOPLEFT", betaNoticeFrame.changelogLabel, "BOTTOMLEFT", 0, -8)
        betaNoticeFrame.changelogScroll:SetPoint("BOTTOMRIGHT", -20 - SCROLLBAR_CLEARANCE, 56)

        betaNoticeFrame.changelogContent = CreateFrame("Frame", nil, betaNoticeFrame.changelogScroll)
        betaNoticeFrame.changelogContent:SetPoint("TOPLEFT")
        betaNoticeFrame.changelogContent:SetSize(1, 1)
        betaNoticeFrame.changelogScroll:SetScrollChild(betaNoticeFrame.changelogContent)

        betaNoticeFrame.changelogText = betaNoticeFrame.changelogContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        betaNoticeFrame.changelogText:SetPoint("TOPLEFT")
        betaNoticeFrame.changelogText:SetJustifyH("LEFT")
        betaNoticeFrame.changelogText:SetText(LATEST_CHANGELOG_TEXT)

        betaNoticeFrame.dontShowAgainCheck = CreateFrame("CheckButton", nil, betaNoticeFrame, "UICheckButtonTemplate")
        betaNoticeFrame.dontShowAgainCheck:SetSize(22, 22)
        betaNoticeFrame.dontShowAgainCheck:SetPoint("BOTTOMLEFT", 16, 16)
        -- Stores the version it was dismissed FOR, not just a bare true/false
        -- -- ticking it only silences this notice until the next release, so
        -- whatever's new (and whoever's still hitting bugs) gets seen again.
        betaNoticeFrame.dontShowAgainCheck:SetScript("OnClick", function(self)
            Embolsao.db.betaNoticeDismissedVersion = self:GetChecked() and GetAddonVersion() or ""
        end)

        betaNoticeFrame.dontShowAgainLabel = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        betaNoticeFrame.dontShowAgainLabel:SetPoint("LEFT", betaNoticeFrame.dontShowAgainCheck, "RIGHT", 2, 0)
        betaNoticeFrame.dontShowAgainLabel:SetText(L.DONT_SHOW_AGAIN)

        local closeButton = CreateFrame("Button", nil, betaNoticeFrame, "UIPanelButtonTemplate")
        closeButton:SetSize(90, 22)
        closeButton:SetPoint("BOTTOMRIGHT", -16, 14)
        closeButton:SetText(CLOSE)
        closeButton:SetScript("OnClick", function() betaNoticeFrame:Hide() end)
    end

    local version = GetAddonVersion()
    betaNoticeFrame.changelogLabel:SetText(string.format(L.BETA_NOTICE_CHANGELOG_LABEL, version))

    -- Wraps at the scroll frame's own width, which is only known once it's
    -- actually laid out -- text width/height has to be (re)computed on every
    -- show rather than once at creation.
    betaNoticeFrame.changelogText:SetWidth(betaNoticeFrame.changelogScroll:GetWidth())
    betaNoticeFrame.changelogContent:SetSize(
        betaNoticeFrame.changelogScroll:GetWidth(),
        betaNoticeFrame.changelogText:GetStringHeight()
    )
    betaNoticeFrame.dontShowAgainCheck:SetChecked(Embolsao.db.betaNoticeDismissedVersion == version)

    betaNoticeFrame:Show()
end

-- onlyIfNotDismissed: used by the PLAYER_LOGIN auto-open (Core.lua) so it's
-- a no-op once this exact version has been dismissed, instead of forcing the
-- window every login. A future manual "show it again" entry point (About
-- menu, etc.) would call this with no argument to always show.
function UI:ShowBetaNotice(onlyIfNotDismissed)
    if onlyIfNotDismissed and Embolsao.db.betaNoticeDismissedVersion == GetAddonVersion() then
        return
    end
    ShowBetaNoticeFrame()
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
        prefsFrame:SetSize(320, 630)
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

        prefsFrame.syncCategoryVisibilityCheck = CreatePreferenceCheckbox(
            prefsFrame, L.SYNC_CATEGORY_VISIBILITY, "syncCategoryVisibility", -242,
            function() UI:Refresh() end
        )

        prefsFrame.minimapButtonCheck = CreatePreferenceCheckbox(
            prefsFrame, L.MINIMAP_ENABLE_BUTTON, "showMinimapButton", -272,
            function() Embolsao.Minimap:SetShown(Embolsao.db.showMinimapButton) end
        )

        -- Not a plain Embolsao.db key -- it controls WHICH store Embolsao.db
        -- itself reads from (see Core.lua), so it needs its own get/set
        -- straight to EmbolsaoCharDB instead of going through CreatePreferenceCheckbox.
        prefsFrame.charSpecificCheck = CreateFrame("CheckButton", nil, prefsFrame, "UICheckButtonTemplate")
        prefsFrame.charSpecificCheck:SetSize(24, 24)
        prefsFrame.charSpecificCheck:SetPoint("TOPLEFT", 24, -302)
        prefsFrame.charSpecificCheck:SetScript("OnClick", function(self)
            Embolsao:SetUseCharacterSpecificData(self:GetChecked())
            UI:BuildTabs()
            UI:Refresh()
            RefreshTabManagerList()
        end)

        prefsFrame.charSpecificLabel = prefsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.charSpecificLabel:SetPoint("LEFT", prefsFrame.charSpecificCheck, "RIGHT", 4, 0)
        prefsFrame.charSpecificLabel:SetText(L.CHARACTER_SPECIFIC_CUSTOMIZATION)

        prefsFrame.manageTabsLabel = prefsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        prefsFrame.manageTabsLabel:SetPoint("TOPLEFT", 24, -336)
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

    prefsFrame.charSpecificCheck:SetChecked(EmbolsaoCharDB.useCharacterSpecific)
    RefreshTabManagerList()
    prefsFrame:Show()
end

-- Right-click on empty space in the tab sidebar (not on a tab button itself
-- -- those already have their own right-click menu) lists every currently
-- hidden tab, one click each to bring it back, instead of having to go into
-- Preferences just to re-show something.
local function ShowHiddenTabsMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        local hasHidden = false
        for _, tabData in ipairs(Embolsao.Filters:GetAllTabs()) do
            if tabData.hidden then
                hasHidden = true
                rootDescription:CreateButton(tabData.name, function()
                    Embolsao.Filters:SetTabHidden(tabData.id, false)
                    UI:BuildTabs()
                    UI:Refresh()
                end)
            end
        end
        if not hasHidden then
            rootDescription:CreateTitle(L.NO_HIDDEN_TABS)
        end
    end)
end

-- Reuses Blizzard's own portrait-style panel template (the same base every
-- portrait dialog in the game uses, bags included) so our window gets the
-- native background/border/portrait/close-button for free instead of a
-- hand-rolled backdrop. Compat.lua picks the actual template name -- retail
-- has a "flat" variant that Classic doesn't ship, but both sit on top of the
-- same PortraitFrameMixin, so nothing else here needs to know the difference.
local function CreateMainFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "EmbolsaoFrame", UIParent, Embolsao.PORTRAIT_FRAME_TEMPLATE)
    local defaultWidth = TAB_ICON_SIZE + TAB_PANEL_PADDING * 2 + SCROLLBAR_CLEARANCE
        + TAB_TO_ITEMS_GAP
        + ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING) + SCROLLBAR_CLEARANCE + 20
    local defaultHeight = 420

    local savedSize = Embolsao.db.rememberPosition and Embolsao.db.windowSize
    frame:SetSize(savedSize and savedSize.width or defaultWidth, savedSize and savedSize.height or defaultHeight)

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
    -- Also persist the new size here so a manual resize survives a reload,
    -- same as the drag-to-move position above.
    frame:SetResizable(true)
    frame:SetScript("OnSizeChanged", function(self)
        UI:Refresh()
        if Embolsao.db.rememberPosition then
            Embolsao.db.windowSize = { width = self:GetWidth(), height = self:GetHeight() }
        end
    end)

    local resizeButton = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
    resizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeButton:Init(frame, defaultWidth, defaultHeight, defaultWidth * 2, defaultHeight * 2)

    frame:Hide()
    frame:HookScript("OnHide", function() UI:ToggleStackExpansion(nil) end)

    -- Let Escape close us too, same as any other native panel.
    tinsert(UISpecialFrames, "EmbolsaoFrame")

    frame:SetPortraitToAsset(PORTRAIT_ICON)
    -- Version in the title bar itself (not just About) so it's obvious at a
    -- glance which build is actually loaded -- handy when the same account
    -- has the addon installed across multiple client flavors separately.
    local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local titleText = string.format("Embolsao!! v%s", GetMeta(ADDON_NAME, "Version") or "?")
    if frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText(titleText)
    elseif frame.TitleText then
        frame.TitleText:SetText(titleText)
    end

    -- Recessed side panel for the filter tabs, visually distinct from the
    -- item grid so tabs don't read as just more bag slots.
    frame.tabPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.tabPanel:SetPoint("TOPLEFT", 10, -CONTENT_TOP_OFFSET)
    frame.tabPanel:SetPoint("BOTTOMLEFT", 10, BOTTOM_MARGIN)
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
    -- Right-click anywhere in here that isn't a tab button (tab buttons are
    -- children and get first pick of the click) falls through to this --
    -- covers both the thin margin around the column and any empty space
    -- below the last tab, since the scroll frame itself always spans the
    -- full visible area regardless of how much content is actually in it.
    frame.tabScrollFrame:HookScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ShowHiddenTabsMenu(self)
        end
    end)

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
    frame.itemScrollFrame:SetPoint("BOTTOMRIGHT", -10 - SCROLLBAR_CLEARANCE, BOTTOM_MARGIN + FOOTER_HEIGHT + FOOTER_GAP)

    frame.itemContainer = CreateFrame("Frame", nil, frame.itemScrollFrame)
    frame.itemContainer:SetPoint("TOPLEFT")
    frame.itemContainer:SetSize(ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING), ITEM_SIZE)
    frame.itemScrollFrame:SetScrollChild(frame.itemContainer)

    frame.menuButton = CreateMenuButton()

    -- Money + XP strip, pinned to the bottom of the window itself (not the
    -- scroll areas) so it never moves as the item grid scrolls -- same
    -- fixed footer Blizzard's own bag window has. Recessed like the tab
    -- panel so it visibly reads as its own strip, not just floating text.
    -- SmallMoneyFrameTemplate is the same template both retail and Classic
    -- use for this (retail's own container money frame just adds a
    -- decorative border on top of it), and once set to type "PLAYER" it
    -- keeps itself in sync with PLAYER_MONEY on its own -- nothing else
    -- here needs to touch it again.
    frame.footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.footer:SetHeight(FOOTER_HEIGHT)
    frame.footer:SetPoint("TOPLEFT", frame.itemScrollFrame, "BOTTOMLEFT", 0, -FOOTER_GAP)
    frame.footer:SetPoint("TOPRIGHT", frame.itemScrollFrame, "BOTTOMRIGHT", 0, -FOOTER_GAP)
    frame.footer:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame.footer:SetBackdropColor(0, 0, 0, 0.35)
    frame.footer:SetBackdropBorderColor(1, 1, 1, 0.25)

    frame.footer.xpText = frame.footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.footer.xpText:SetPoint("LEFT", 8, 0)

    frame.footer.moneyFrame = CreateFrame("Frame", nil, frame.footer, "SmallMoneyFrameTemplate")
    frame.footer.moneyFrame:SetPoint("RIGHT", -8, 0)
    SmallMoneyFrame_OnLoad(frame.footer.moneyFrame)
    MoneyFrame_SetType(frame.footer.moneyFrame, "PLAYER")

    return frame
end

-- Retail moved this one behind the GameRulesUtil namespace; Classic still
-- has it as a bare global. Confirmed both ways against Blizzard's own
-- GameRulesUtil.lua -- calling the bare global on retail is exactly what
-- crashed here ("attempt to call a nil value").
local function IsAtEffectiveMaxLevel()
    if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
        return GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
    end
    return IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() or false
end

-- Not max level -> "1234 / 5678"; at max level (or XP gain is otherwise
-- disabled, e.g. WoW Trial) there's no next-level total to show at all, so
-- the label just goes blank instead of reading "0 / 0" or similar nonsense.
local function UpdateFooterXP()
    if not frame then return end
    if IsAtEffectiveMaxLevel() or IsXPUserDisabled() then
        frame.footer.xpText:SetText("")
        return
    end

    local currXP, maxXP = UnitXP("player"), UnitXPMax("player")
    local percent = maxXP > 0 and math.floor((currXP / maxXP) * 100 + 0.5) or 0
    frame.footer.xpText:SetText(string.format("%d / %d (%d%%)", currXP, maxXP, percent))
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

    -- Right-click now always has at least Edit to offer, "All" included --
    -- built-in tabs (All among them) can have hidden items/category rules
    -- layered on top since Filters:UpdateBuiltInOverride. It's still the
    -- only thing "All"'s menu offers (no Hide, no Delete), but that's a
    -- real option now, not an empty menu.
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            Embolsao.TabEditor:ShowTabContextMenu(self, tabData)
            return
        end
        Embolsao.db.activeTab = tabData.id
        UI:Refresh()
    end)

    -- Drag an item from the bag grid straight onto this tab to hide it
    -- there (with confirmation) -- a quicker shortcut than opening the tab
    -- editor's own drop zone. OnReceiveDrag covers releasing the drag
    -- directly over the button; OnMouseUp covers picking the item up with a
    -- click first and then clicking the tab.
    btn:SetScript("OnReceiveDrag", function(self)
        TryHideCursorItemOnTab(tabData)
    end)
    btn:SetScript("OnMouseUp", function(self)
        if CursorHasItem() then
            TryHideCursorItemOnTab(tabData)
        end
    end)

    -- Drag-to-reorder: OnDragStart fires on this button, but OnDragStop
    -- also always fires here (not on whatever's under the cursor when you
    -- let go) -- so the drop target has to be computed explicitly via
    -- GetDropTarget() (cursor Y vs. every tab's position) rather than relied
    -- on to fire its own handler.
    -- "All" (tabData.id == "ALL") is exempt: it can't move and nothing can
    -- land ahead of it, enforced in Filters:MoveTabRelative.
    --
    -- A dimmed-alpha source button alone gave zero feedback that anything
    -- was happening until you let go -- added a cursor-following ghost icon
    -- plus a line between tabs showing exactly where the drop would insert
    -- (above/below the hovered tab, whichever half the cursor is over),
    -- both driven by an OnUpdate for the duration of the drag.
    btn.tabData = tabData
    if tabData.id ~= "ALL" then
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function(self)
            self:SetAlpha(0.4)

            local ghost = EnsureDragGhost()
            ghost.icon:SetTexture(tabData.icon)
            UpdateDragGhostPosition()
            ghost:Show()

            self:SetScript("OnUpdate", function(self)
                UpdateDragGhostPosition()

                local target, placeAfter = GetDropTarget(self)
                UI.dropTarget, UI.dropAfter = target, placeAfter

                local indicator = EnsureDropIndicator()
                if target then
                    indicator:ClearAllPoints()
                    if placeAfter then
                        indicator:SetPoint("TOPLEFT", target, "BOTTOMLEFT", -4, 2)
                        indicator:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 4, 2)
                    else
                        indicator:SetPoint("BOTTOMLEFT", target, "TOPLEFT", -4, -2)
                        indicator:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", 4, -2)
                    end
                    indicator:Show()
                else
                    indicator:Hide()
                end
            end)
        end)
        btn:SetScript("OnDragStop", function(self)
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
            dragGhost:Hide()
            if dropIndicator then
                dropIndicator:Hide()
            end

            local target, placeAfter = UI.dropTarget, UI.dropAfter
            UI.dropTarget, UI.dropAfter = nil, nil
            if target then
                Embolsao.Filters:MoveTabRelative(self.tabData.id, target.tabData.id, placeAfter)
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

-- Sort By Type collapse state, saved so it survives a reload instead of
-- resetting every time the bag opens. Preferences -> "Synchronize Category
-- Visibility" (default on) picks between one shared collapse state for
-- every tab, or a separate one remembered per tab.
local function GetCollapsedHeaders()
    if Embolsao.db.syncCategoryVisibility then
        return Embolsao.db.collapsedHeadersGlobal
    end

    local tabID = Embolsao.db.activeTab
    local perTab = Embolsao.db.collapsedHeaders[tabID]
    if not perTab then
        perTab = {}
        Embolsao.db.collapsedHeaders[tabID] = perTab
    end
    return perTab
end

local function CollapseAllHeaders()
    local collapsed = GetCollapsedHeaders()
    for _, entry in ipairs(UI:GetFilteredEntries()) do
        local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(entry.itemID)
        collapsed["class:" .. classID] = true
        collapsed["sub:" .. classID .. ":" .. subClassID] = true
    end
    collapsed["emptyslots"] = true
    UI:Refresh()
end

local function ExpandAllHeaders()
    wipe(GetCollapsedHeaders())
    UI:Refresh()
end

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

    -- Only meaningful while actually grouped by category -- collapsing
    -- headers that aren't even shown wouldn't do anything.
    if Embolsao.db.sortMode == "TYPE" then
        rootDescription:CreateButton(L.COLLAPSE_ALL_CATEGORIES, CollapseAllHeaders)
        rootDescription:CreateButton(L.EXPAND_ALL_CATEGORIES, ExpandAllHeaders)
        rootDescription:CreateDivider()
    end

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
-- drop a picked-up or split-off item to start a new stack. One pooled button
-- per Embolsao.EmptySlotGroups entry -- the shared "general" bucket (icon:
-- the plain empty-slot atlas) plus one per special bag currently equipped
-- (icon: that bag's own portrait via C_Container.SetBagPortraitTexture, so
-- it's obvious at a glance which bag it is) -- each targeting the first
-- genuinely empty (bagID, slot) within its own group. Desaturated and
-- faded on purpose so a run of them doesn't visually compete with real
-- items sitting right next to them.
local emptySlotButtons = {}

local function GetOrCreateEmptySlotButton(index)
    local btn = emptySlotButtons[index]
    if btn then return btn end

    btn = CreateFrame("ItemButton", nil, frame.itemContainer)
    btn.minDisplayCount = 0

    local function PlaceCursorItem()
        local slotInfo = btn.group and btn.group.slots[1]
        if not slotInfo then return end
        C_Container.PickupContainerItem(slotInfo.bagID, slotInfo.slot)
    end

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local bagName = self.group and self.group.bagID and C_Container.GetBagName(self.group.bagID)
        GameTooltip:SetText(bagName and string.format(L.EMPTY_SLOT_TITLE_BAG, bagName) or L.EMPTY_SLOT_TITLE)
        GameTooltip:AddLine(L.EMPTY_SLOT_DESC, 1, 1, 1, true)
        if self.group then
            GameTooltip:AddLine(self.group.bagID and L.EMPTY_SLOT_OPEN_BAG_HINT or L.EMPTY_SLOT_OPEN_ALL_BAGS_HINT, 1, 1, 1, true)
        end
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

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if self.group then
                -- A special bag (reagent bag, keyring, profession bag) maps
                -- to one real bagID and opens just that one; the shared
                -- "general" bucket has a list of every plain bag instead, so
                -- it opens exactly those -- not the special ones too.
                UI:OpenNativeBags(self.group.bagID or self.group.bagIDs)
            end
            return
        end
        if CursorHasItem() then
            PlaceCursorItem()
        end
    end)
    btn:SetScript("OnReceiveDrag", PlaceCursorItem)

    emptySlotButtons[index] = btn
    return btn
end

-- Bare "ItemButton" is Blizzard's own intrinsic widget type (icon + count +
-- quality border), the same one every item slot in the game is built from.
-- We don't pull in ContainerFrameItemButtonTemplate itself, since that one
-- hard-requires a real container-frame parent (it calls things like
-- self:GetParent():IsCombinedBagContainer()) -- not something we want to
-- fake just to show a merged/virtual stack that isn't one real bag slot.
--
-- Shared between the main grid and the stack-expansion popout below: both
-- are real ItemButtons bound to a real (bagID, slot) via SetBagID/SetID, so
-- the exact same click/drag handling works for either -- a popout button is
-- just one that happens to act on one specific real stack out of several
-- backing the same merged entry, instead of always locations[1].
local function SetupItemButtonInteractions(btn)
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

        -- Ctrl+Left-click on a merged super-stack expands it into its real,
        -- individually-interactive stacks in a popout below the button.
        -- Checked as a raw modifier (not via IsModifiedClick) so it can't
        -- be shadowed by whatever the player has bound to Modified Click
        -- Actions -- same reasoning as Split Stack below.
        if mouseButton == "LeftButton" and IsControlKeyDown()
            and not IsShiftKeyDown() and not IsAltKeyDown() then
            if self.locations and #self.locations > 1 then
                UI:ToggleStackExpansion(self.itemID, self)
            end
            return
        end

        -- Split stack: reuse Blizzard's own StackSplitFrame popup, the same
        -- one bags/bank/mail/trade all share, instead of building our own.
        if not CursorHasItem() and IsModifiedClick("SPLITSTACK") then
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            local itemCount = info and info.stackCount
            if itemCount and itemCount > 1 and not info.isLocked then
                self.SplitStack = SplitItemStack
                Embolsao:OpenStackSplitFrame(itemCount, self, "BOTTOMRIGHT", "TOPRIGHT")
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
end

-- Each button acts on entry.locations[1] -- the first real (bagID, slot)
-- backing that merged stack. Picking up/using it only affects that one real
-- stack, not the whole merged count; Ctrl+Click opens a popout (below) to
-- get at the others individually.
-- Positioning is NOT done here -- it happens every UI:Refresh (even for
-- reused buttons), since the column count depends on the window's current
-- width and needs to reflow existing buttons too when that changes.
local function GetOrCreateItemButton(index)
    local btn = itemButtons[index]
    if btn then return btn end

    btn = CreateFrame("ItemButton", nil, frame.itemContainer)
    SetupItemButtonInteractions(btn)

    itemButtons[index] = btn
    return btn
end

--------------------------------------------------------------------------
-- Stack expansion popout: Ctrl+Click a merged super-stack (see
-- SetupItemButtonInteractions above) to see and interact with the real
-- stacks backing it individually, as a small grid of real item buttons
-- anchored right below the clicked one -- a mini-bag for that one item.
--------------------------------------------------------------------------

local STACK_POPOUT_COLUMNS = 6
local STACK_POPOUT_PADDING = 10

local stackPopout
local stackPopoutButtons = {}

local function GetOrCreateStackPopoutButton(index)
    local btn = stackPopoutButtons[index]
    if btn then return btn end

    btn = CreateFrame("ItemButton", nil, stackPopout)
    local col = (index - 1) % STACK_POPOUT_COLUMNS
    local row = math.floor((index - 1) / STACK_POPOUT_COLUMNS)
    btn:SetPoint("TOPLEFT", STACK_POPOUT_PADDING + col * (ITEM_SIZE + ITEM_PADDING),
        -(STACK_POPOUT_PADDING + 20) - row * (ITEM_SIZE + ITEM_PADDING))
    SetupItemButtonInteractions(btn)

    stackPopoutButtons[index] = btn
    return btn
end

local function EnsureStackPopout()
    if stackPopout then return stackPopout end

    stackPopout = CreateFrame("Frame", "EmbolsaoStackPopoutFrame", UIParent, "BackdropTemplate")
    stackPopout:SetFrameStrata("DIALOG")
    stackPopout:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    stackPopout:SetBackdropColor(0, 0, 0, 0.95)
    stackPopout:EnableMouse(true)
    stackPopout:Hide()
    tinsert(UISpecialFrames, "EmbolsaoStackPopoutFrame")

    local close = CreateFrame("Button", nil, stackPopout, "UIPanelCloseButtonDefaultAnchors")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() UI:ToggleStackExpansion(nil) end)

    return stackPopout
end

-- Re-resolves the currently-expanded itemID against the live inventory
-- (called on open and again on every UI:Refresh while it's open, so moving
-- one of the real stacks around updates the popout instead of it going
-- stale) and lays out one real button per real (bagID, slot) location.
-- Closes itself automatically once the item no longer resolves to a
-- super-stack -- e.g. the player moved or used all but one real stack.
local function RefreshStackPopout()
    local entry = Embolsao.VirtualInventory[UI.stackPopoutItemID]
    if not entry or not entry.locations or #entry.locations < 2 then
        UI:ToggleStackExpansion(nil)
        return
    end

    local popout = EnsureStackPopout()
    local numLocations = #entry.locations
    local columns = math.min(STACK_POPOUT_COLUMNS, numLocations)
    local rows = math.ceil(numLocations / STACK_POPOUT_COLUMNS)

    for i, location in ipairs(entry.locations) do
        local btn = GetOrCreateStackPopoutButton(i)
        -- Each real stack's own count/quality, read fresh per slot --
        -- NOT the merged entry's aggregate count.
        local info = C_Container.GetContainerItemInfo(location.bagID, location.slot)
        btn.itemID = entry.itemID
        btn.locations = nil -- a real single stack, not itself expandable
        btn:SetBagID(location.bagID)
        btn:SetID(location.slot)
        if info then
            SetItemButtonTexture(btn, info.iconFileID)
            SetItemButtonCount(btn, info.stackCount)
            SetItemButtonQuality(btn, info.quality, entry.itemID)
        end
        btn:Show()
    end

    for i = numLocations + 1, #stackPopoutButtons do
        stackPopoutButtons[i].itemID = nil
        stackPopoutButtons[i]:Hide()
    end

    popout:SetSize(
        columns * (ITEM_SIZE + ITEM_PADDING) + STACK_POPOUT_PADDING * 2,
        rows * (ITEM_SIZE + ITEM_PADDING) + STACK_POPOUT_PADDING * 2 + 20
    )
end

-- Pass itemID = nil (or omit it) to close. Ctrl+Clicking the
-- already-expanded stack closes it (toggle); Ctrl+Clicking a different one
-- switches straight to that one.
function UI:ToggleStackExpansion(itemID, anchorButton)
    if not itemID or itemID == UI.stackPopoutItemID then
        UI.stackPopoutItemID = nil
        if stackPopout then stackPopout:Hide() end
        return
    end

    UI.stackPopoutItemID = itemID
    local popout = EnsureStackPopout()
    if anchorButton then
        popout:ClearAllPoints()
        popout:SetPoint("TOP", anchorButton, "BOTTOM", 0, -6)
    end
    popout:Show()
    RefreshStackPopout()
end

-- Sort By Type class/subclass separators (Preferences -> Group By
-- Class/Subclass). A plain label + horizontal line, indented per nesting
-- level so a subclass header reads as nested under its class header, plus
-- a +/- toggle to collapse the items under it. Keyed by classID (and
-- subClassID for subclass headers), not by display text, so it survives a
-- locale change and can't collide with an unrelated category that happens
-- to share a name. Saved per character (see GetCollapsedHeaders above), so
-- it survives a reload too.
local headerRows = {}

local function GetOrCreateHeaderRow(index)
    local header = headerRows[index]
    if header then return header end

    header = CreateFrame("Frame", nil, frame.itemContainer)
    header:SetHeight(HEADER_ROW_HEIGHT)
    header:EnableMouse(true)

    header.toggleIcon = header:CreateTexture(nil, "ARTWORK")
    header.toggleIcon:SetSize(12, 12)
    header.toggleIcon:SetPoint("LEFT")

    header.text = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header.text:SetPoint("LEFT", header.toggleIcon, "RIGHT", 4, 0)

    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetHeight(1)
    header.line:SetColorTexture(1, 1, 1, 0.25)
    header.line:SetPoint("LEFT", header.text, "RIGHT", 6, 0)
    header.line:SetPoint("RIGHT")

    header:SetScript("OnMouseUp", function(self)
        if not self.key then return end
        local collapsed = GetCollapsedHeaders()
        if collapsed[self.key] then
            collapsed[self.key] = nil
        else
            collapsed[self.key] = true
        end
        UI:Refresh()
    end)

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
    local grouping = Embolsao.db.sortMode == "TYPE" and (groupByClass or groupBySubClass)
    local collapsed = GetCollapsedHeaders()

    local rows = {}

    if not grouping then
        for _, entry in ipairs(entries) do
            table.insert(rows, { kind = "item", entry = entry })
        end
    else
        local lastClassID, lastSubClassID = nil, nil
        local classCollapsed, subClassCollapsed = false, false
        for _, entry in ipairs(entries) do
            local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(entry.itemID)

            if groupByClass and classID ~= lastClassID then
                local key = "class:" .. classID
                classCollapsed = collapsed[key] == true
                table.insert(rows, {
                    kind = "header", level = 0, key = key, collapsed = classCollapsed,
                    text = C_Item.GetItemClassInfo(classID) or "?",
                })
                lastSubClassID = nil -- force the subclass header to repeat under the new class
            end

            if groupBySubClass and (classID ~= lastClassID or subClassID ~= lastSubClassID) then
                local key = "sub:" .. classID .. ":" .. subClassID
                subClassCollapsed = collapsed[key] == true
                -- A collapsed class already hides everything under it -- no
                -- point also showing (or tracking clicks on) the subclass
                -- header it would otherwise contain.
                if not classCollapsed then
                    table.insert(rows, {
                        kind = "header", level = 1, key = key, collapsed = subClassCollapsed,
                        text = C_Item.GetItemSubClassInfo(classID, subClassID) or "?",
                    })
                end
            end

            if not classCollapsed and not subClassCollapsed then
                table.insert(rows, { kind = "item", entry = entry })
            end
            lastClassID, lastSubClassID = classID, subClassID
        end
    end

    -- Empty slots always come last -- one per Embolsao.EmptySlotGroups entry
    -- (built in Core.lua: the shared "general" bucket plus one per special
    -- bag currently equipped), not tied to the active tab or to filtering,
    -- just "the place to drop new stacks". Sorted by Category gets them a
    -- header of their own so they don't read as part of whatever real
    -- category happened to sort last.
    local emptySlotGroups = Embolsao.EmptySlotGroups
    if emptySlotGroups and #emptySlotGroups > 0 then
        if grouping then
            local key = "emptyslots"
            local emptyCollapsed = collapsed[key] == true
            table.insert(rows, {
                kind = "header", level = 0, key = key, collapsed = emptyCollapsed,
                text = L.EMPTY_SLOTS_CATEGORY,
            })
            if not emptyCollapsed then
                for _, group in ipairs(emptySlotGroups) do
                    table.insert(rows, { kind = "emptyslot", group = group })
                end
            end
        else
            for _, group in ipairs(emptySlotGroups) do
                table.insert(rows, { kind = "emptyslot", group = group })
            end
        end
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
    local itemIndex, headerIndex, emptySlotIndex = 0, 0, 0

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
            header.key = row.key
            header.toggleIcon:SetTexture(row.collapsed
                and "Interface\\Buttons\\UI-PlusButton-Up"
                or "Interface\\Buttons\\UI-MinusButton-Up")
            header:Show()

            yOffset = yOffset + HEADER_ROW_HEIGHT
        elseif row.kind == "emptyslot" then
            local group = row.group
            emptySlotIndex = emptySlotIndex + 1
            local btn = GetOrCreateEmptySlotButton(emptySlotIndex)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", col * (ITEM_SIZE + ITEM_PADDING), -yOffset)
            btn.group = group
            if Embolsao.IsClassic and group.bagID == KEYRING_CONTAINER then
                -- Blizzard's own code hardcodes this rather than resolving
                -- it through SetBagPortraitTexture too -- the keyring has no
                -- real equipped "item" backing it to pull an icon from.
                -- Embolsao.IsClassic guard: KEYRING_CONTAINER is a stale
                -- leftover value on retail that can collide with a real
                -- bagID (the reagent bag), which is what made a reagent bag
                -- group render with the key icon there.
                btn.icon:SetTexture("Interface\\ContainerFrame\\KeyRing-Bag-Icon")
            elseif group.bagID then
                C_Container.SetBagPortraitTexture(btn.icon, group.bagID)
            else
                btn.icon:SetAtlas("bags-item-slot64")
            end
            btn.icon:SetDesaturated(true)
            btn.icon:SetAlpha(0.5)
            btn.Count:SetText(tostring(#group.slots))
            btn.Count:Show()
            btn:Show()

            col = col + 1
            if col >= itemsPerRow then
                col = 0
                yOffset = yOffset + (ITEM_SIZE + ITEM_PADDING)
            end
        else
            local entry = row.entry
            itemIndex = itemIndex + 1
            local btn = GetOrCreateItemButton(itemIndex)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", col * (ITEM_SIZE + ITEM_PADDING), -yOffset)
            btn.itemID = entry.itemID
            btn.locations = entry.locations
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
        itemButtons[index].locations = nil
        itemButtons[index]:Hide()
    end
    for index = headerIndex + 1, #headerRows do
        headerRows[index]:Hide()
    end
    for index = emptySlotIndex + 1, #emptySlotButtons do
        emptySlotButtons[index].group = nil
        emptySlotButtons[index]:Hide()
    end

    -- Whatever row the last button landed on, that row's height still
    -- counts toward the total scrollable content height.
    frame.itemContainer:SetHeight(yOffset + (ITEM_SIZE + ITEM_PADDING))

    -- Keep an open stack-expansion popout in sync with whatever just
    -- changed (or close it if its super-stack doesn't exist anymore).
    if self.stackPopoutItemID then
        RefreshStackPopout()
    end
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

-- Bank storage (BANK_CONTAINER) and bank bag slots aren't ours to manage at
-- all -- they're not scanned anywhere in Core.lua, so Embolsao has no idea
-- what's in them. Matches Embolsao:ScanBags()'s own domain exactly: the
-- backpack, regular bag slots, the reagent bag (retail only), and the
-- keyring (Classic only) -- anything else (bank included) is native
-- Blizzard's problem, not ours, and should be left alone even while our own
-- window is open.
--
-- Classic/TBC have no reagent bag at all, so bag 5 there is just the next
-- container ID in line -- the FIRST BANK BAG SLOT the moment the player is
-- at a banker. Treating it as "ours" there hijacked that bank bag's own
-- frame, which is exactly what broke it (it never opened).
local REAGENT_BAG_ID = (not Embolsao.IsClassic) and 5 or nil

local function IsEmbolsaoManagedBag(bagID)
    if bagID == nil then return false end
    if bagID >= BACKPACK_CONTAINER and bagID <= NUM_BAG_SLOTS then return true end
    if REAGENT_BAG_ID and bagID == REAGENT_BAG_ID then return true end
    -- Retail leaves IsKeyRingEnabled/KEYRING_CONTAINER as stale globals even
    -- though the keyring was removed there -- Embolsao.IsClassic is what
    -- actually tells the two apart, same as REAGENT_BAG_ID above.
    if Embolsao.IsClassic and bagID == KEYRING_CONTAINER and IsKeyRingEnabled and IsKeyRingEnabled() then return true end
    return false
end

-- ContainerFrameCombinedBags (retail only) shows several bags in one window
-- at once, so it can't be selectively split into "ours" vs "the bank's" the
-- way each individual ContainerFrameN can via its own :GetID() -- it's an
-- all-or-nothing frame.
local function IsCombinedBagsFrame(bagFrame)
    return bagFrame and bagFrame.GetName and bagFrame:GetName() == "ContainerFrameCombinedBags"
end

local function IsAnyNativeBagFrameShown()
    for _, bagFrame in ipairs(nativeBagFrames) do
        if bagFrame:IsShown() then
            return true
        end
    end
    return false
end

-- Same as above, but only counts a frame Embolsao actually stands in for --
-- a bank bag sitting open shouldn't keep Embolsao open, or close it, on its
-- own merits.
local function IsAnyManagedBagFrameShown()
    for _, bagFrame in ipairs(nativeBagFrames) do
        if bagFrame:IsShown() and (IsCombinedBagsFrame(bagFrame) or IsEmbolsaoManagedBag(bagFrame:GetID())) then
            return true
        end
    end
    return false
end

local function SuppressNativeBagFrames()
    suppressingNativeHide = true
    for _, bagFrame in ipairs(nativeBagFrames) do
        if IsCombinedBagsFrame(bagFrame) or IsEmbolsaoManagedBag(bagFrame:GetID()) then
            bagFrame:Hide()
        end
    end
    C_Timer.After(0, function()
        suppressingNativeHide = false
    end)
end

-- Visiting a banker shows the player's own bags alongside the bank's, all
-- native, so items can be dragged between them and bank bags can be opened
-- individually. On the combined-bags frame (retail) that can't be split
-- apart, so we step aside for it entirely -- same as "Disable Embolsao" --
-- for as long as the bank is open. Individual ContainerFrameN frames don't
-- need this at all: each one's own :GetID() already says whether it's ours.
local atBank = false
local bankEventFrame = CreateFrame("Frame")
bankEventFrame:RegisterEvent("BANKFRAME_OPENED")
bankEventFrame:RegisterEvent("BANKFRAME_CLOSED")
bankEventFrame:SetScript("OnEvent", function(_, event)
    atBank = (event == "BANKFRAME_OPENED")
end)

local function OnBagFrameShow(self)
    -- A bank bag (or the bank's own storage) opening in its own frame is
    -- never ours to take over -- let it show completely normally.
    if not IsCombinedBagsFrame(self) and not IsEmbolsaoManagedBag(self and self:GetID()) then
        return
    end

    -- "Disabled" via the minimap button's menu, a one-shot bypass from
    -- UI:OpenNativeBags(), or (combined-bags frame only) the bank being
    -- open -- either way, leave the native frame(s) alone and let
    -- Blizzard's own bag window show normally.
    --
    -- UI.suppressTakeoverOnce is either `true` (blanket -- "Open Default
    -- Bags", a bagID list peek) or a specific bagID (a single-bag peek).
    -- It must stay scoped to that one bagID rather than exempting every
    -- frame: Blizzard's own bag-open bookkeeping can fire OnShow for OTHER
    -- ContainerFrameN's in the same tick as the one bag we asked to peek
    -- (e.g. the backpack reopening alongside the reagent bag), and a
    -- blanket exemption let all of those slip past untouched too --
    -- visibly "every bag opens at once" instead of just the one we wanted.
    local suppressThis = Embolsao.db.disabled
        or UI.suppressTakeoverOnce == true
        or (type(UI.suppressTakeoverOnce) == "number" and self:GetID() == UI.suppressTakeoverOnce)
        or (IsCombinedBagsFrame(self) and atBank)

    if suppressThis then
        -- Cleared a frame later, not here: without combined bags, opening
        -- bags fires OnShow separately for every individual ContainerFrameN,
        -- and clearing a blanket `true` on the very first one left every
        -- frame after that falling straight back into our own takeover. A
        -- numeric (single-bagID) value only ever matches one frame anyway,
        -- but is cleared the same way for consistency.
        C_Timer.After(0, function()
            UI.suppressTakeoverOnce = nil
        end)
        return
    end

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
    UpdateFooterXP()
    SuppressNativeBagFrames()
end

local function OnBagFrameHide(self)
    if suppressingNativeHide then return end
    -- A bank bag closing again is no concern of ours -- Embolsao was never
    -- standing in for it, so its own visibility shouldn't react to this.
    if not IsCombinedBagsFrame(self) and not IsEmbolsaoManagedBag(self and self:GetID()) then
        return
    end
    -- One-shot: a single-bag peek (UI:OpenNativeBags(bagID)) leaves our own
    -- window open on purpose, so the native frame it opened closing again
    -- shouldn't take Embolsao down with it the way it normally would.
    --
    -- Scoped to the exact bagID that was peeked, same reasoning as
    -- suppressTakeoverOnce above: if some OTHER managed frame also
    -- transiently shows/hides while the peek is active (Blizzard's own
    -- bag-open bookkeeping reshuffling frames), an unscoped flag could get
    -- consumed by that unrelated hide instead -- leaving nothing left to
    -- protect Embolsao's window when the actually-peeked bag closes for
    -- real, so it got hidden right along with it.
    if UI.keepOpenDuringPeek and self:GetID() == UI.keepOpenDuringPeek then
        UI.keepOpenDuringPeek = nil
        return
    end
    if frame and not IsAnyManagedBagFrameShown() then
        frame:Hide()
    end
end

function UI:ShowPreferences()
    ShowPreferencesFrame()
end

-- One-off peek at Blizzard's own bag window, without touching the
-- persistent "disabled" setting.
--
-- With a single bagID (right-click on a special bag's empty-slot button),
-- opens just that one bag via ToggleBag alongside our own window, which
-- stays open -- Blizzard's own combined-bags setting only ever applies to
-- plain, unrestricted bags (ContainerFrame_IsGenericHeldBag), so a special
-- bag like the reagent bag, the keyring, or a profession bag already always
-- opens on its own here regardless of that setting.
--
-- With a list of bagIDs (right-click on the shared "general" empty-slot
-- button) or no bagID at all (the minimap menu's "Open Default Bags"), it's
-- a full swap instead: closes our window first so the two don't end up
-- stacked on top of each other, since Blizzard's own "is it open" tracking
-- already thinks the native frame is closed (we only ever hide it, never
-- truly close it) and would otherwise show both. A list opens exactly those
-- bags one by one -- not ToggleAllBags(), which would also pop open every
-- special bag that already has its own dedicated button/group.
function UI:OpenNativeBags(bagID)
    local isSinglePeek = type(bagID) == "number"

    if isSinglePeek then
        -- Scoped to this exact bagID -- see the matching comments on
        -- OnBagFrameShow/OnBagFrameHide for why a blanket `true` doesn't
        -- work for a single-bag peek.
        self.keepOpenDuringPeek = bagID
        self.suppressTakeoverOnce = bagID
    else
        if frame and frame:IsShown() then
            frame:Hide()
        end
        self.suppressTakeoverOnce = true
    end

    if isSinglePeek then
        ToggleBag(bagID)
    elseif type(bagID) == "table" then
        for _, id in ipairs(bagID) do
            ToggleBag(id)
        end
    else
        ToggleAllBags()
    end
end

-- Minimap button's "Disable Embolsao" toggle: leaves native bags alone
-- entirely from here on: OnBagFrameShow bails immediately instead of
-- taking over. Just closes whichever window is currently open on the way
-- through -- the player presses the bag key again to see the other one.
function UI:SetDisabled(disabled)
    Embolsao.db.disabled = disabled and true or false

    if disabled then
        if frame and frame:IsShown() then
            frame:Hide()
        end
    elseif IsAnyNativeBagFrameShown() then
        for _, bagFrame in ipairs(nativeBagFrames) do
            bagFrame:Hide()
        end
    end
end

-- Blizzard's own "is the bag open" tracking thinks bags are closed once we
-- hide the native frame(s) (we only ever hide them, never truly close them),
-- so pressing the bag keybind again just re-runs "open" and does nothing
-- visible -- the classic B-then-B-to-close habit stops working. Wrapping
-- the keybind's own functions instead of touching the keybind itself: if
-- our window is currently up, close IT and skip calling the real toggle at
-- all; otherwise fall through to Blizzard's original behavior untouched.
local function WrapBagToggle(original)
    return function(...)
        if frame and frame:IsShown() then
            frame:Hide()
            return
        end
        return original(...)
    end
end

local bagToggleFunctionsWrapped = false
local function WrapBagToggleFunctions()
    if bagToggleFunctionsWrapped then return end
    if not (ToggleBackpack and ToggleAllBags) then return end

    ToggleBackpack = WrapBagToggle(ToggleBackpack)
    ToggleAllBags = WrapBagToggle(ToggleAllBags)
    bagToggleFunctionsWrapped = true
end

-- ContainerFrameCombinedBags/ContainerFrame1..6 belong to Blizzard_UIPanels_Game,
-- a load-on-demand module that only loads the first time the player opens a bag.
-- It's almost never loaded yet at PLAYER_LOGIN, so we wait for its ADDON_LOADED
-- (and still check at PLAYER_LOGIN in case some other addon forced it earlier).
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
        WrapBagToggleFunctions()
    end
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon ~= "Blizzard_UIPanels_Game" then
        return
    end
    InstallBagFrameHooks()
end)

-- Keeps the footer's XP text live while the window is open. The money side
-- of the footer doesn't need this -- SmallMoneyFrameTemplate already
-- listens for PLAYER_MONEY on its own.
local xpUpdateFrame = CreateFrame("Frame")
xpUpdateFrame:RegisterEvent("PLAYER_XP_UPDATE")
xpUpdateFrame:RegisterEvent("PLAYER_LEVEL_UP")
xpUpdateFrame:RegisterEvent("DISABLE_XP_GAIN")
xpUpdateFrame:RegisterEvent("ENABLE_XP_GAIN")
xpUpdateFrame:SetScript("OnEvent", UpdateFooterXP)
