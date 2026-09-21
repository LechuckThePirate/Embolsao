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
local GROUP_GAP_HEIGHT = 10 -- vertical space closing off the pinned "Recent" group
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

-- All the native frames we take over display duty from, across BOTH windows
-- (bags and bank) -- GetOwningWindow (further down) sorts out which window,
-- if either, actually owns a given one. Combined bags is one frame; legacy
-- (non-combined) mode can have the backpack plus up to 5 more bag frames
-- open side by side, so we cover the full set either way. BankFrame is
-- the bank's storage window -- see IsBankStorageFrame below.
local NATIVE_BAG_FRAME_NAMES = {
    "ContainerFrameCombinedBags",
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
    "BankFrame",
}

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/embolsao"
local FEEDBACK_EMAIL = "lechuckthepirate@gmail.com"

-- Mirrors the latest entry in CHANGELOG.md -- update this alongside it (and
-- the version bump) on every release, it's shown as-is in the beta notice
-- popup's changelog box.
local LATEST_CHANGELOG_TEXT = [[
- Support for the Classic "Forever" beta (see the notice above).
- Bank and bags now share one window: bank on the left, bags on the right, each with its own tabs, search and footer. An X on the bank part closes just it.
- The bank has its own tabs (Preferences: "Separate tabs for Bank and Bags"). Right-click at a banker moves every stack of a super-stack, and you can buy bank tabs / bag slots from the bank footer.
- New "Recent" and "Junk" groups (Junk has a sell-all coin button, plus an optional auto-sell in Preferences). "Empty Slots" is always its own category, and bags of the same profession share one counter.
- Sort mode and direction are remembered per tab.
- New Bindings window (main menu): pick the modifier for showing a super-stack's stacks, splitting, and a new item actions menu (Alt+Click by default). Tooltips list the shortcuts, and the items an action can't use fade while you hold its key.
- Fixed right-click use of items (hearthstones, scrolls, quest items) being blocked, and right-click on an empty-slot counter with combined bags.
- Only "All" ships as a default tab now. Drop an item on a tab's icon to use its icon; category pickers are sorted alphabetically.
- Rested XP in the footer, a scrollable and resizable Preferences window, and a "What's New" button in About.]]

-- Notices for the welcome window, shown ABOVE the changelog -- for things a
-- player should know about this version that aren't a feature (a known
-- client bug, a temporary limitation...). Edit this list on each release:
-- add an entry, or delete the ones that no longer apply. Each entry is
--   key     -- the locale string holding its text (enUS.lua / esES.lua)
--   applies -- optional; the notice only shows when it returns true, so one
--              meant for a single game client doesn't bother everyone else
-- With nothing applicable the window looks exactly as before.
local VERSION_NOTICES = {
    {
        -- Classic "Forever" beta (client 1.60.x): SavedVariables don't reach
        -- addons on load. See ForeverSVFallback.lua -- remove both together.
        key = "NOTICE_FOREVER_SAVEDVARIABLES",
        applies = function()
            local build = select(4, GetBuildInfo())
            return build >= 16000 and build < 20000
        end,
    },
}

-- All the applicable notices as one block of text (blank line between them),
-- or "" when there are none.
local function BuildVersionNoticeText()
    local parts = {}
    for _, notice in ipairs(VERSION_NOTICES) do
        if not notice.applies or notice.applies() then
            table.insert(parts, L[notice.key])
        end
    end
    if #parts == 0 then return "" end
    return "|cffff8800" .. L.NOTICE_HEADER .. "|r\n" .. table.concat(parts, "\n\n")
end

-- Small icon that follows the cursor while dragging a tab to reorder it --
-- without this, dragging looked like it did nothing until you let go.
-- Smaller than the real tab icon on purpose -- at full size the ghost sat
-- right on top of the drop-line indicator and hid it. Shared across both
-- windows -- only one tab drag can ever be in progress at a time.
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

-- Reads the identity of whatever item is on the cursor (without consuming
-- it -- handed right back to its own slot) and, if there is one, asks for
-- confirmation to hide it on the given tab. Used when an item from the bag
-- grid gets dropped straight onto a tab button. Shared -- doesn't touch any
-- per-window state, just the cursor and Filters/TabEditor.
local function TryHideCursorItemOnTab(tabData, domain)
    local cursorItem = C_Cursor.GetCursorItem()
    if not cursorItem then return end
    local bagID, slot = cursorItem:GetBagAndSlot()
    if not bagID then return end

    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if info and info.itemID then
        Embolsao.TabEditor:ConfirmHideItemOnTab(info.itemID, tabData, domain)
    end

    C_Container.PickupContainerItem(bagID, slot)
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
        aboutFrame:SetSize(340, 290)
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

        -- Reopens the welcome/changelog window on demand -- otherwise, once
        -- it's been dismissed for a version, the only way back was waiting
        -- for the next release.
        local whatsNewButton = CreateFrame("Button", nil, aboutFrame, "UIPanelButtonTemplate")
        whatsNewButton:SetSize(140, 22)
        whatsNewButton:SetPoint("BOTTOM", closeButton, "TOP", 0, 6)
        whatsNewButton:SetText(L.WHATS_NEW)
        whatsNewButton:SetScript("OnClick", function()
            aboutFrame:Hide()
            UI:ShowBetaNotice()
        end)
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
local BETA_NOTICE_BASE_HEIGHT = 480

local function ShowBetaNoticeFrame()
    if not betaNoticeFrame then
        betaNoticeFrame = CreateFrame("Frame", "EmbolsaoBetaNoticeFrame", UIParent, "BackdropTemplate")
        betaNoticeFrame:SetSize(380, BETA_NOTICE_BASE_HEIGHT)
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

        -- Per-version notices (VERSION_NOTICES); laid out on every show, see
        -- ShowBetaNoticeFrame.
        betaNoticeFrame.noticeText = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        betaNoticeFrame.noticeText:SetPoint("TOP", betaNoticeFrame.emailBox, "BOTTOM", 0, -14)
        betaNoticeFrame.noticeText:SetWidth(340)
        betaNoticeFrame.noticeText:SetJustifyH("LEFT")
        betaNoticeFrame.noticeText:Hide()

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

    -- Notices go between the feedback line and the changelog: when there are
    -- any, the changelog label moves down below them and the window grows by
    -- the height they take (up to the screen), so the changelog box keeps its
    -- size instead of being squeezed. With none, it's laid out as it always was.
    local noticeText = BuildVersionNoticeText()
    betaNoticeFrame.changelogLabel:ClearAllPoints()
    if noticeText ~= "" then
        betaNoticeFrame.noticeText:SetText(noticeText)
        betaNoticeFrame.noticeText:Show()
        betaNoticeFrame.changelogLabel:SetPoint("TOPLEFT", betaNoticeFrame.noticeText, "BOTTOMLEFT", 0, -14)
        local extra = betaNoticeFrame.noticeText:GetStringHeight() + 14
        betaNoticeFrame:SetHeight(math.min(BETA_NOTICE_BASE_HEIGHT + extra, UIParent:GetHeight() - 40))
    else
        betaNoticeFrame.noticeText:Hide()
        betaNoticeFrame.changelogLabel:SetPoint("TOPLEFT", 20, -180)
        betaNoticeFrame:SetHeight(BETA_NOTICE_BASE_HEIGHT)
    end

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
local PREFS_CONTENT_HEIGHT = 690
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

        prefsFrame.groupByClassCheck = CreatePreferenceCheckbox(
            content, L.GROUP_BY_CLASS, "groupByClass", -138,
            function() UI:Refresh() end
        )

        prefsFrame.groupBySubClassCheck = CreatePreferenceCheckbox(
            content, L.GROUP_BY_SUBCLASS, "groupBySubClass", -168,
            function() UI:Refresh() end
        )

        prefsFrame.syncCategoryVisibilityCheck = CreatePreferenceCheckbox(
            content, L.SYNC_CATEGORY_VISIBILITY, "syncCategoryVisibility", -198,
            function() UI:Refresh() end
        )

        prefsFrame.minimapButtonCheck = CreatePreferenceCheckbox(
            content, L.MINIMAP_ENABLE_BUTTON, "showMinimapButton", -228,
            function() Embolsao.Minimap:SetShown(Embolsao.db.showMinimapButton) end
        )

        prefsFrame.mergeBankStorageCheck = CreatePreferenceCheckbox(
            content, L.MERGE_BANK_STORAGE, "mergeBankStorage", -258,
            function() UI:RefreshBankAvailability() end
        )

        -- Off: the bank pane shares the bags' tabs, as it used to. On (the
        -- default): it has its own, kept apart. Switching rebuilds both panes'
        -- tab bars, and the tab manager below follows (it only offers the
        -- bags/bank choice while this is on).
        prefsFrame.separateBankTabsCheck = CreatePreferenceCheckbox(
            content, L.SEPARATE_BANK_TABS, "separateBankTabs", -288,
            function()
                UI:BuildTabs()
                UI:Refresh()
                UpdateTabManagerDomainControl()
                RefreshTabManagerList()
            end
        )

        prefsFrame.showRecentCategoryCheck = CreatePreferenceCheckbox(
            content, L.SHOW_RECENT_CATEGORY, "showRecentCategory", -318,
            function() UI:Refresh() end
        )

        prefsFrame.showJunkCategoryCheck = CreatePreferenceCheckbox(
            content, L.SHOW_JUNK_CATEGORY, "showJunkCategory", -348,
            function() UI:Refresh() end
        )

        prefsFrame.autoSellJunkCheck = CreatePreferenceCheckbox(
            content, L.AUTO_SELL_JUNK, "autoSellJunk", -378
        )

        -- Not a plain Embolsao.db key -- it controls WHICH store Embolsao.db
        -- itself reads from (see Core.lua), so it needs its own get/set
        -- straight to EmbolsaoCharDB instead of going through CreatePreferenceCheckbox.
        prefsFrame.charSpecificCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        prefsFrame.charSpecificCheck:SetSize(24, 24)
        prefsFrame.charSpecificCheck:SetPoint("TOPLEFT", 24, -408)
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
        prefsFrame.manageTabsLabel:SetPoint("TOPLEFT", 24, -442)
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

-- Right-click on empty space in the tab sidebar (not on a tab button itself
-- -- those already have their own right-click menu) lists every currently
-- hidden tab, one click each to bring it back, instead of having to go into
-- Preferences just to re-show something. Generic over `owner` -- works
-- identically for either window's tab sidebar.
local function ShowHiddenTabsMenu(owner, domain)
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        local hasHidden = false
        local filters = Embolsao:GetFilters(domain)
        for _, tabData in ipairs(filters:GetAllTabs()) do
            if tabData.hidden then
                hasHidden = true
                rootDescription:CreateButton(tabData.name, function()
                    filters:SetTabHidden(tabData.id, false)
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
        local info = C_Container.GetContainerItemInfo(btn:GetBagID(), btn:GetID())
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

--------------------------------------------------------------------------
-- Pawn ("bag upgrade advisor") integration. Optional -- everything here is
-- a no-op if Pawn isn't installed. Our item buttons are plain ItemButtons,
-- not Blizzard's ContainerFrameItemButtonTemplate, so Pawn's own bag hook
-- (PawnBags.lua, hooksecurefunc on ContainerFrameN's UpdateItems) never
-- sees them -- this reimplements the green-arrow overlay via Pawn's own
-- documented third-party-bag integration contract instead (see the header
-- comment in Pawn's PawnBags.lua, or its GitHub source):
--   1. Call PawnShouldItemLinkHaveUpgradeArrow(link, true) per item.
--   2. nil means "ask again shortly" (Pawn throttles itself); true/false
--      is the real answer.
--   3. Call PawnRegisterThirdPartyBag(name, {RefreshAll=...}) once, so Pawn
--      knows we're handling this ourselves (and disables its own native-bag
--      hook, which would never have found our buttons anyway).
-- Shared across both windows: RefreshAllPawnIcons (below, after both windows
-- exist) walks every registered window's buttons.
--------------------------------------------------------------------------

-- Same atlas/anchor Blizzard's own ContainerFrameItemButtonTemplate uses for
-- this (confirmed against Classic and retail ContainerFrame.xml -- identical
-- in both) -- our buttons don't inherit that template, so it has to be
-- created by hand.
local function CreateUpgradeIcon(btn)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetAtlas("bags-greenarrow", true)
    icon:SetPoint("TOPLEFT", 0, 0)
    icon:Hide()
    return icon
end

-- Small "X" in the opposite corner from the Pawn upgrade arrow -- only
-- shown on items currently sitting in the "Recent" group (BuildLayoutRows).
-- Forgets the item in Embolsao's own recent set (and clears Blizzard's flag
-- on each merged location so the next scan doesn't re-adopt it), then
-- rescans -- the item then shows up wherever it actually belongs instead.
local function CreateRecentDismissButton(btn, win)
    local dismiss = CreateFrame("Button", nil, btn)
    dismiss:SetSize(14, 14)
    dismiss:SetPoint("TOPRIGHT", 1, 1)
    -- Above the secure right-click overlay (CreateUseOverlay, btn level + 2),
    -- which otherwise covers the whole button and would swallow this click.
    dismiss:SetFrameLevel(btn:GetFrameLevel() + 3)
    dismiss:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    dismiss:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up", "ADD")
    dismiss:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.DISMISS_RECENT_HINT)
        GameTooltip:Show()
    end)
    dismiss:SetScript("OnLeave", GameTooltip_Hide)
    dismiss:SetScript("OnClick", function(self)
        local owner = self:GetParent()
        if owner.itemID then
            Embolsao:DismissRecentItem(owner.itemID, owner.locations)
            Embolsao:ScanBags()
            UI:Refresh()
        end
    end)
    dismiss:Hide()
    return dismiss
end

-- Right-click "use" needs a secure path. C_Container.UseContainerItem is
-- protected for anything that casts a spell or has an on-use effect
-- (hearthstone, scrolls, quest items...), so calling it from our own click
-- handler makes the client raise "Embolsao has been blocked from an action
-- only available to the Blizzard UI". Blizzard's own bag buttons get away
-- with it because their handler is Blizzard code. The standard fix for an
-- addon: an invisible SecureActionButtonTemplate laid over each item button
-- that performs the "item" action for "<bagID> <slot>" on right-click, while
-- everything else (tooltip, left click, drag, split) is forwarded to the
-- visible button's own handlers.
--
-- The overlay is a child of the item button and anchored to it once, so the
-- (unprotected) button can still be moved, shown and hidden during combat.
-- Only its attributes are locked in combat -- they are refreshed in
-- UpdateUseOverlay and again when combat ends (PLAYER_REGEN_ENABLED below).
--
-- Negative bagIDs (Classic's main bank container, the keyring) can't be
-- expressed in the "<bag> <slot>" form, so those keep the old direct call;
-- they only ever move items to/from the bank, which isn't protected.
local function IsModernBankOpen()
    return Embolsao.AtBank == true and Embolsao:UsesModernBank()
end

-- Right-click at a banker means "move it to the other side" (deposit from the
-- bags, withdraw from the bank). A merged super-stack is several real stacks
-- shown as one, so that has to move ALL of them, not just the first: one every
-- MOVE_INTERVAL seconds rather than all in the same instant -- each move picks
-- its own free destination slot, and asking for several before the first has
-- landed can make the game hand two of them the same one. The first goes right
-- away, so a click still feels immediate. Moving items isn't a protected
-- action (unlike using them), so this runs from plain code.
--   locations: the real (bagID, slot) stacks; bankType: which bank the modern
--   bank should be told (nil on the classic bank, which takes no such argument)
local MOVE_INTERVAL = 0.12
local movingStacks = false

local function MoveStacksAcrossBank(locations, bankType)
    if movingStacks then return end

    -- Snapshot now: the item buttons re-lay themselves out as stacks leave.
    local queue = {}
    for _, location in ipairs(locations) do
        local info = C_Container.GetContainerItemInfo(location.bagID, location.slot)
        if info then
            table.insert(queue, { bagID = location.bagID, slot = location.slot, itemID = info.itemID })
        end
    end
    if #queue == 0 then return end

    local index = 0
    -- Returns true when there's nothing left to move.
    local function MoveNext()
        index = index + 1
        local item = queue[index]
        -- Skipped if it already moved, changed, or is still in flight.
        local info = item and C_Container.GetContainerItemInfo(item.bagID, item.slot)
        if info and info.itemID == item.itemID and not info.isLocked then
            if bankType then
                C_Container.UseContainerItem(item.bagID, item.slot, nil, bankType)
            else
                C_Container.UseContainerItem(item.bagID, item.slot)
            end
        end
        return index >= #queue
    end

    if MoveNext() then return end

    movingStacks = true
    C_Timer.NewTicker(MOVE_INTERVAL, function(ticker)
        -- Stop if the banker window closed on us.
        if not Embolsao.AtBank or MoveNext() then
            ticker:Cancel()
            movingStacks = false
        end
    end)
end

local MODIFIED_CLICK_PREFIXES = {
    "shift-", "ctrl-", "alt-", "ctrl-shift-", "alt-shift-", "alt-ctrl-", "alt-ctrl-shift-",
}

local function CreateUseOverlay(btn)
    local overlay = CreateFrame("Button", nil, btn, "SecureActionButtonTemplate")
    overlay:SetAllPoints(btn)
    overlay:SetFrameLevel(btn:GetFrameLevel() + 2)
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:RegisterForDrag("LeftButton")

    -- Secure buttons fire on key/mouse DOWN when the ActionButtonUseKeyDown
    -- CVar is on (its default), but we only register for the UP click above --
    -- without this SecureActionButton_OnClick sees the "wrong" half of the
    -- click and silently does nothing, no error.
    overlay:SetAttribute("useOnKeyDown", false)

    overlay:SetAttribute("type2", "item")
    -- Modified right-clicks aren't "use" (the visible button's handler
    -- ignores them too); an empty string is Blizzard's explicit "no action".
    for _, prefix in ipairs(MODIFIED_CLICK_PREFIXES) do
        overlay:SetAttribute(prefix .. "type2", "")
    end

    local function Forward(scriptName, ...)
        local handler = btn:GetScript(scriptName)
        if handler then handler(btn, ...) end
    end
    overlay:SetScript("OnEnter", function()
        btn:LockHighlight()
        Forward("OnEnter")
    end)
    overlay:SetScript("OnLeave", function()
        btn:UnlockHighlight()
        Forward("OnLeave")
    end)
    overlay:SetScript("OnDragStart", function() Forward("OnDragStart") end)
    overlay:SetScript("OnReceiveDrag", function() Forward("OnReceiveDrag") end)
    overlay:SetScript("PostClick", function(_, mouseButton) Forward("OnClick", mouseButton) end)
    return overlay
end

-- Points the overlay at whatever (bagID, slot) the button now shows. Skipped
-- entirely in combat (creating or changing a protected frame is locked out);
-- the refresh that follows PLAYER_REGEN_ENABLED catches up.
local function UpdateUseOverlay(btn, bagID, slot)
    if InCombatLockdown() then return end

    local overlay = btn.UseOverlay
    if not overlay then
        overlay = CreateUseOverlay(btn)
        btn.UseOverlay = overlay
    end

    -- At a modern bank, right-click means deposit/withdraw, which needs the
    -- bank type passed along (Blizzard's own item buttons do the same) -- the
    -- secure "use item" action has no way to say that, so it's switched off
    -- there and the click handler moves the item itself.
    local action
    if bagID and bagID >= 0 and slot and slot > 0 and not Embolsao.AtBank then
        action = bagID .. " " .. slot
    end
    if btn.useOverlayAction ~= action then
        overlay:SetAttribute("item2", action)
        btn.useOverlayAction = action
    end
end

-- Vendor state for the Junk group's sell button. Tracked from
-- MERCHANT_SHOW/CLOSED (bottom of file) rather than only asking MerchantFrame,
-- which may not be shown yet at the moment the event reaches us; the frame
-- check still covers a /reload done while standing at a vendor.
local merchantOpen = false
local function IsAtMerchant()
    return merchantOpen or (_G.MerchantFrame ~= nil and _G.MerchantFrame:IsShown())
end

-- Sells every grey stack in `entries` (the Junk group as currently listed),
-- one item every SELL_INTERVAL seconds instead of all in the same frame --
-- a burst of dozens of sell calls at once is the kind of thing servers
-- throttle, and this way it also stops the moment the vendor window closes.
-- Plain C_Container.UseContainerItem is fine here: selling is not a
-- protected action (only spell-casting/on-use items are, see CreateUseOverlay).
local SELL_INTERVAL = 0.08
local sellingJunk = false

local function SellJunkEntries(entries)
    if sellingJunk or not IsAtMerchant() then return end

    local queue = {}
    local total = 0
    for _, entry in ipairs(entries) do
        if entry.isJunk then
            local sellPrice = select(11, Embolsao.GetItemInfo(entry.itemID))
            total = total + (sellPrice or 0) * entry.count
            for _, location in ipairs(entry.locations) do
                table.insert(queue, location)
            end
        end
    end
    if #queue == 0 then return end

    -- Always says so when it starts: this is the only place Embolsao ever
    -- sells anything, so no message means the sale wasn't ours.
    print(string.format(L.SELLING_JUNK, #queue, Embolsao.GetCoinTextureString(total)))

    sellingJunk = true
    local index = 0
    C_Timer.NewTicker(SELL_INTERVAL, function(ticker)
        if not IsAtMerchant() then
            ticker:Cancel()
            sellingJunk = false
            return
        end

        index = index + 1
        local location = queue[index]
        local info = location and C_Container.GetContainerItemInfo(location.bagID, location.slot)
        -- Re-checked per slot: things may have moved since the list was
        -- built, and some grey items have no vendor value at all. "Junk" is
        -- grey quality OR something the player marked as junk by hand.
        local userJunk = Embolsao.db and Embolsao.db.junkItemIDs
        local isJunk = info and (info.quality == 0 or (userJunk and userJunk[info.itemID]))
        if isJunk and not info.hasNoValue then
            C_Container.UseContainerItem(location.bagID, location.slot)
        end

        if index >= #queue then
            ticker:Cancel()
            sellingJunk = false
        end
    end)
end

local pawnRegistered = false
local pawnWindows = {} -- populated once both windows exist, see bottom of file

local function EnsurePawnRegistered()
    if pawnRegistered or not PawnRegisterThirdPartyBag then return end
    pawnRegistered = true
    PawnRegisterThirdPartyBag(ADDON_NAME, { RefreshAll = function()
        for _, win in ipairs(pawnWindows) do
            win.RefreshPawnIcons()
        end
    end })
end

local function UpdatePawnUpgradeIcon(btn, hyperlink)
    if not btn.UpgradeIcon then return end
    if not hyperlink or not PawnShouldItemLinkHaveUpgradeArrow then
        btn.pawnHyperlink = nil
        btn.UpgradeIcon:Hide()
        return
    end

    EnsurePawnRegistered()
    btn.pawnHyperlink = hyperlink
    local isUpgrade = PawnShouldItemLinkHaveUpgradeArrow(hyperlink, true)
    if isUpgrade == nil then
        -- Pawn isn't ready to answer yet (throttled) -- retry next frame,
        -- same pattern Pawn's own bag hook uses internally. Bails if this
        -- button has since been reused for a different item/hyperlink.
        C_Timer.After(0, function()
            if btn.pawnHyperlink == hyperlink then
                UpdatePawnUpgradeIcon(btn, hyperlink)
            end
        end)
        return
    end
    btn.UpgradeIcon:SetShown(isUpgrade)
end

-- Returns -1/0/1 for "a naturally comes before/tied/after b" regardless of
-- sort direction; the direction flag (sortAscending) is applied uniformly
-- afterward so every mode responds to the ascending/descending toggle the
-- same way, without each branch needing its own idea of "natural" order.
-- Sort mode/direction are remembered per tab (Embolsao.db.tabSort[tabID]); a
-- tab nobody has touched yet falls back to the global sortMode/sortAscending,
-- so whatever a player had chosen before this was per-tab carries over as
-- every tab's starting point. Shared between both windows, same as the tabs.
local function GetTabSort(tabID)
    local saved = Embolsao.db.tabSort[tabID]
    local mode = saved and saved.mode or Embolsao.db.sortMode
    local ascending
    if saved and saved.ascending ~= nil then
        ascending = saved.ascending
    else
        ascending = Embolsao.db.sortAscending
    end
    return mode, ascending
end

local function SetTabSort(tabID, mode, ascending)
    local currentMode, currentAscending = GetTabSort(tabID)
    Embolsao.db.tabSort[tabID] = {
        mode = mode or currentMode,
        ascending = (ascending == nil) and currentAscending or ascending,
    }
end

local function NaturalCompare(a, b, mode)
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
        local _, _, _, _, _, classA, subA = Embolsao.GetItemInfoInstant(a.itemID)
        local _, _, _, _, _, classB, subB = Embolsao.GetItemInfoInstant(b.itemID)
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
        local nameA, nameB = Embolsao.GetItemInfo(a.itemID), Embolsao.GetItemInfo(b.itemID)
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
local function MakeComparator(mode, ascending)
    return function(a, b)
        local natural = NaturalCompare(a, b, mode)
        if natural ~= 0 then
            if ascending then
                return natural < 0
            else
                return natural > 0
            end
        end
        return a.itemID < b.itemID
    end
end

-- Sort By Type collapse state, saved so it survives a reload instead of
-- resetting every time the bag opens. Preferences -> "Synchronize Category
-- Visibility" (default on) picks between one shared collapse state for
-- every tab, or a separate one remembered per tab. Shared between both
-- windows -- tabs themselves are shared, so their collapse state is too.
-- tabID: the calling window's own active tab (the two windows track theirs
-- independently).
local function GetCollapsedHeaders(tabID)
    if Embolsao.db.syncCategoryVisibility then
        return Embolsao.db.collapsedHeadersGlobal
    end

    local perTab = Embolsao.db.collapsedHeaders[tabID]
    if not perTab then
        perTab = {}
        Embolsao.db.collapsedHeaders[tabID] = perTab
    end
    return perTab
end

-- entries: whichever window's own UI:GetFilteredEntries() result invoked
-- this from its menu -- the collapse keys themselves are shared, but which
-- classes/subclasses actually exist to collapse depends on what that window
-- is currently looking at (bags vs. bank contents).
local function CollapseAllHeaders(entries, win)
    local collapsed = GetCollapsedHeaders(win.StateID(win.GetActiveTab()))
    for _, entry in ipairs(entries) do
        local _, _, _, _, _, classID, subClassID = Embolsao.GetItemInfoInstant(entry.itemID)
        collapsed["class:" .. classID] = true
        collapsed["sub:" .. classID .. ":" .. subClassID] = true
    end
    collapsed["emptyslots"] = true
    UI:Refresh()
end

local function ExpandAllHeaders(win)
    wipe(GetCollapsedHeaders(win.StateID(win.GetActiveTab())))
    UI:Refresh()
end

-- Builds a flat sequence of {kind="header", level=, text=} and
-- {kind="item", entry=} rows to lay out, only when sorted by Type and at
-- least one grouping preference is on. Headers only ever appear when the
-- class/subclass actually changes between two consecutive (already sorted)
-- entries -- since we never invent a header for a class/subclass with no
-- entries in the list, an empty one simply never gets one, in either
-- sort direction (ascending/descending just changes the order we walk in,
-- not how boundaries are detected). emptySlotGroups is passed in rather
-- than read from a single shared place -- bags and bank each have their own.
-- entries: what the active tab shows. pinnedSource: every bag item passing
-- the search box regardless of tab, which the pinned Recent/Junk groups draw from.
local function BuildLayoutRows(entries, pinnedSource, emptySlotGroups, tabID, tabName)
    local groupByClass = Embolsao.db.groupByClass
    local groupBySubClass = Embolsao.db.groupBySubClass
    local sortMode = GetTabSort(tabID)
    local grouping = sortMode == "TYPE" and (groupByClass or groupBySubClass)
    local collapsed = GetCollapsedHeaders(tabID)

    local rows = {}

    -- "Recent" and then "Junk" are pinned first, regardless of sort mode AND
    -- of which tab is active: they draw from pinnedSource (every bag item
    -- that passes the search box), not from `entries` (what the active tab's
    -- own filter lets through) -- so a recent item shows up on a custom tab
    -- with strict category rules too, and Sell Junk always covers all the
    -- junk in the group. An item shows in a pinned group INSTEAD of its usual
    -- category, not in addition to it: Recent until dismissed (the small
    -- button on the item, see CreateRecentDismissButton), and an item that's
    -- both recent and grey belongs to Recent.
    local recentEntries, junkEntries, pinned = {}, {}, {}
    if Embolsao.db.showRecentCategory ~= false then
        for _, entry in ipairs(pinnedSource) do
            if Embolsao.Filters:IsEntryRecent(entry) then
                table.insert(recentEntries, entry)
                pinned[entry] = true
            end
        end
    end
    if Embolsao.db.showJunkCategory ~= false then
        for _, entry in ipairs(pinnedSource) do
            if not pinned[entry] and Embolsao.Filters:IsEntryJunk(entry) then
                table.insert(junkEntries, entry)
                pinned[entry] = true
            end
        end
    end

    local remainingEntries = entries
    if next(pinned) ~= nil then
        remainingEntries = {}
        for _, entry in ipairs(entries) do
            if not pinned[entry] then
                table.insert(remainingEntries, entry)
            end
        end
    end
    local hasEmptySlots = emptySlotGroups and #emptySlotGroups > 0

    -- Without a break after a pinned group, whatever follows would either
    -- continue its last (partially filled) row -- when nothing is grouped --
    -- or sit flush against it, reading as part of the group either way.
    if #recentEntries > 0 then
        local key = "recentitems"
        local recentCollapsed = collapsed[key] == true
        table.insert(rows, {
            kind = "header", level = 0, key = key, collapsed = recentCollapsed,
            text = L.RECENT_ITEMS,
        })
        if not recentCollapsed then
            for _, entry in ipairs(recentEntries) do
                table.insert(rows, { kind = "item", entry = entry, isRecent = true })
            end
        end

        if #junkEntries > 0 or #remainingEntries > 0 or hasEmptySlots then
            table.insert(rows, { kind = "gap" })
        end
    end

    -- The Junk header carries the sell-all button (see GetOrCreateHeaderRow).
    if #junkEntries > 0 then
        local key = "junkitems"
        local junkCollapsed = collapsed[key] == true
        table.insert(rows, {
            kind = "header", level = 0, key = key, collapsed = junkCollapsed,
            text = L.JUNK_ITEMS,
        })
        if not junkCollapsed then
            for _, entry in ipairs(junkEntries) do
                table.insert(rows, { kind = "item", entry = entry })
            end
        end

        if #remainingEntries > 0 or hasEmptySlots then
            table.insert(rows, { kind = "gap" })
        end
    end

    if not grouping then
        -- Not grouped by category: everything that's left is one group named
        -- after the tab itself, so it reads as a section of its own under
        -- the pinned Recent/Junk groups instead of running on from them.
        -- Skipped only when there is nothing left to show (or no name).
        if tabName and #remainingEntries > 0 then
            local key = "tabitems"
            local tabCollapsed = collapsed[key] == true
            table.insert(rows, {
                kind = "header", level = 0, key = key, collapsed = tabCollapsed,
                text = tabName,
            })
            if not tabCollapsed then
                for _, entry in ipairs(remainingEntries) do
                    table.insert(rows, { kind = "item", entry = entry })
                end
            end
        else
            for _, entry in ipairs(remainingEntries) do
                table.insert(rows, { kind = "item", entry = entry })
            end
        end
    else
        local lastClassID, lastSubClassID = nil, nil
        local classCollapsed, subClassCollapsed = false, false
        for _, entry in ipairs(remainingEntries) do
            local _, _, _, _, _, classID, subClassID = Embolsao.GetItemInfoInstant(entry.itemID)

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

    -- Empty slots always come last -- one per emptySlotGroups entry (built
    -- in Core.lua: the shared "general" bucket plus one per special bag
    -- currently equipped), not tied to the active tab or to filtering, just
    -- "the place to drop new stacks". Sorted by Category gets them a header
    -- of their own so they don't read as part of whatever real category
    -- happened to sort last. Same treatment in every mode now, mirroring
    -- Recent at the top: a collapsible header of its own, set off from
    -- whatever comes before it by a gap (unless one is already there).
    if hasEmptySlots then
        if #rows > 0 and rows[#rows].kind ~= "gap" then
            table.insert(rows, { kind = "gap" })
        end

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
    end

    return rows
end

-- What a special-bag family (the bitmask C_Container.GetContainerNumFreeSlots
-- reports as "bagFamily", stored on the empty-slot group by Core.lua) is
-- called on its button's tooltip: the profession/kind, not the name of one
-- particular bag -- two different mining bags are both just "Mining".
-- Anything not listed falls back to the bag's own name.
local BAG_FAMILY_LABEL_KEYS = {
    [1] = "BAG_FAMILY_QUIVER",
    [2] = "BAG_FAMILY_AMMO",
    [4] = "BAG_FAMILY_SOUL",
    [8] = "BAG_FAMILY_LEATHERWORKING",
    [16] = "BAG_FAMILY_INSCRIPTION",
    [32] = "BAG_FAMILY_HERBALISM",
    [64] = "BAG_FAMILY_ENCHANTING",
    [128] = "BAG_FAMILY_ENGINEERING",
    [512] = "BAG_FAMILY_JEWELCRAFTING",
    [1024] = "BAG_FAMILY_MINING",
}

local SORT_MODES = {
    { id = "NAME", label = L.SORT_NAME },
    { id = "TYPE", label = L.SORT_TYPE },
    { id = "QUANTITY", label = L.SORT_QUANTITY },
    { id = "QUALITY", label = L.SORT_QUALITY },
}

-- The two windows (created below, once CreateWindow exists) and the single
-- frame they both live in -- declared up here because the menu and the frame's
-- layout code need to see them.
local bagsWindow, bankWindow
local host

-- Sizes of the ONE window. It holds up to two "panes" side by side (bank on
-- the left, bags on the right), each as wide as the plain single window has
-- always been; a bank visit doubles the window and splits the space evenly
-- between them, with a separator in the middle.
local PANE_DEFAULT_WIDTH = TAB_ICON_SIZE + TAB_PANEL_PADDING * 2 + SCROLLBAR_CLEARANCE
    + TAB_TO_ITEMS_GAP
    + ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING) + SCROLLBAR_CLEARANCE + 20
local PANE_DEFAULT_HEIGHT = 420
local PANE_SEPARATOR_WIDTH = 8
-- Extra vertical room under the toolbar for a pane's name, when two panes
-- share the window.
local PANE_LABEL_EXTRA = 22

-- Sort By / Collapse All / Expand All belong to a pane (they act on the tab
-- it's showing); the rest of the menu is shared.
local function BuildPaneMenu(win, parent)
    -- Sort mode/direction apply to (and are remembered by) whichever tab
    -- this pane is currently showing, not to every tab at once.
    local tabID = win.StateID(win.GetActiveTab())
    local activeSortMode = GetTabSort(tabID)

    local sortSubmenu = parent:CreateButton(L.SORT_BY)

    local function IsSortSelected(mode)
        return (GetTabSort(tabID)) == mode
    end
    local function SetSort(mode)
        SetTabSort(tabID, mode, nil)
        UI:Refresh()
    end

    for _, sortOption in ipairs(SORT_MODES) do
        sortSubmenu:CreateRadio(sortOption.label, IsSortSelected, SetSort, sortOption.id)
    end

    sortSubmenu:CreateDivider()

    local function IsDirectionSelected(ascending)
        local _, currentAscending = GetTabSort(tabID)
        return currentAscending == ascending
    end
    local function SetDirection(ascending)
        SetTabSort(tabID, nil, ascending)
        UI:Refresh()
    end
    sortSubmenu:CreateRadio(L.SORT_ASCENDING, IsDirectionSelected, SetDirection, true)
    sortSubmenu:CreateRadio(L.SORT_DESCENDING, IsDirectionSelected, SetDirection, false)

    -- Only meaningful while actually grouped by category -- collapsing
    -- headers that aren't even shown wouldn't do anything.
    if activeSortMode == "TYPE" then
        parent:CreateButton(L.COLLAPSE_ALL_CATEGORIES, function()
            CollapseAllHeaders(win.GetFilteredEntries(), win)
        end)
        parent:CreateButton(L.EXPAND_ALL_CATEGORIES, function()
            ExpandAllHeaders(win)
        end)
    end
end

-- The window's one menu. With a single pane showing it is what it always was;
-- with two (bank + bags), the per-pane entries move into a submenu each, named
-- after the pane, so it's clear which one they'll act on.
local function BuildEmbolsaoMenu(rootDescription)
    local panes = {}
    if bankWindow.IsShown() then
        table.insert(panes, { win = bankWindow, label = L.PANE_BANK })
    end
    if bagsWindow.IsShown() then
        table.insert(panes, { win = bagsWindow, label = L.PANE_BAGS })
    end
    if #panes == 0 then
        panes[1] = { win = bagsWindow, label = L.PANE_BAGS }
    end

    if #panes == 1 then
        BuildPaneMenu(panes[1].win, rootDescription)
    else
        for _, pane in ipairs(panes) do
            BuildPaneMenu(pane.win, rootDescription:CreateButton(pane.label))
        end
    end

    rootDescription:CreateDivider()

    rootDescription:CreateButton(L.PREFERENCES, ShowPreferencesFrame)

    rootDescription:CreateButton(L.BINDINGS, ShowBindingsFrame)

    rootDescription:CreateButton(L.ABOUT, ShowAboutFrame)
end

-- Sizes and places the window for whichever panes are showing right now: none
-- (hide it), one (that pane fills it), or two (bank left, bags right, half
-- each, separator between). Called every time a pane is shown or hidden. The
-- window's right edge stays put while its width changes, so opening the bank
-- grows it to the left and the bags don't move under the player's cursor.
local function LayoutHost()
    if not host then return end

    local bankShown = bankWindow.IsShown()
    local bagsShown = bagsWindow.IsShown()
    if not bankShown and not bagsShown then
        host:Hide()
        return
    end

    local count = (bankShown and 1 or 0) + (bagsShown and 1 or 0)
    local merged = count == 2
    local separator = merged and PANE_SEPARATOR_WIDTH or 0
    host.paneCount = count

    -- Resize limits scale with the number of panes (the resize button reads
    -- these fields each time it enforces them).
    local resizeButton = host.resizeButton
    resizeButton.minWidth = PANE_DEFAULT_WIDTH * count + separator
    resizeButton.maxWidth = PANE_DEFAULT_WIDTH * 2 * count + separator

    local newWidth = host.paneWidth * count + separator
    if math.abs(host:GetWidth() - newWidth) > 0.5 then
        local right, top = host:GetRight(), host:GetTop()
        if right and top then
            host:ClearAllPoints()
            host:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
        end
        host:SetWidth(newWidth)
    end

    if merged then
        local bankFrame, bagsFrame = bankWindow.GetFrame(), bagsWindow.GetFrame()
        bankFrame:ClearAllPoints()
        bankFrame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        bankFrame:SetPoint("BOTTOMRIGHT", host, "BOTTOM", -separator / 2, 0)
        bagsFrame:ClearAllPoints()
        bagsFrame:SetPoint("TOPLEFT", host, "TOP", separator / 2, 0)
        bagsFrame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    else
        local only = (bankShown and bankWindow or bagsWindow).GetFrame()
        only:ClearAllPoints()
        only:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        only:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    end

    bankWindow.SetMergedLayout(merged)
    bagsWindow.SetMergedLayout(merged)
    host.separator:SetShown(merged)
    host:Show()

    -- Growing to the left can push the bank part past the screen's left edge
    -- when the window was parked near it: slide the whole window back on
    -- screen (once the new size has taken effect, next frame).
    if merged then
        C_Timer.After(0, function()
            if not host:IsShown() then return end
            local left = host:GetLeft()
            if left and left < 0 then
                local point, relativeTo, relativePoint, x, y = host:GetPoint()
                host:ClearAllPoints()
                host:SetPoint(point, relativeTo, relativePoint, x - left, y)
            end
        end)
    end
end

local function CreateHostMenuButton()
    local btn = CreateFrame("Button", nil, host)
    btn:SetSize(70, 24)
    btn:SetPoint("TOPRIGHT", -16, TOOLBAR_Y)

    -- The exact arrow atlas Blizzard's own WowStyle2DropdownTemplate uses
    -- for its chevron (confirmed in MenuTemplates.xml) -- a Unicode
    -- triangle glyph turned out invisible, the default UI fonts don't
    -- cover it.
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
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            BuildEmbolsaoMenu(rootDescription)
        end)
    end)

    return btn
end

-- The ONE window frame both panes live in: Blizzard's portrait-style panel
-- (border, portrait, title, close button for free), the drag, the resize
-- grip, the position and size that are remembered between sessions, the
-- menu, and the separator between the panes. The window size is stored as
-- the width of ONE pane, so it means the same whether the bank is showing
-- or not, and resizing it resizes both panes together.
local function EnsureHost()
    if host then return host end

    host = CreateFrame("Frame", "EmbolsaoWindowFrame", UIParent, Embolsao.PORTRAIT_FRAME_TEMPLATE)

    local savedSize = Embolsao.db.rememberPosition and Embolsao.db.windowSize
    host.paneWidth = savedSize and savedSize.width or PANE_DEFAULT_WIDTH
    host.paneCount = 1
    host:SetSize(host.paneWidth, savedSize and savedSize.height or PANE_DEFAULT_HEIGHT)

    local savedPosition = Embolsao.db.rememberPosition and Embolsao.db.windowPosition
    if savedPosition then
        host:SetPoint(savedPosition.point, UIParent, savedPosition.relativePoint or savedPosition.point,
            savedPosition.x, savedPosition.y)
    else
        host:SetPoint("CENTER")
    end

    host:SetFrameStrata("HIGH")
    host:SetClampedToScreen(true)
    host:SetMovable(true)
    host:EnableMouse(true)
    host:RegisterForDrag("LeftButton")
    host:SetScript("OnDragStart", host.StartMoving)
    host:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if Embolsao.db.rememberPosition then
            local point, _, relativePoint, x, y = self:GetPoint()
            Embolsao.db.windowPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
        end
    end)

    -- Remember the width of one pane (see above), whichever way the window
    -- got resized. Must be set BEFORE the resize button's Init below, which
    -- wraps whatever OnSizeChanged script is there.
    host:SetResizable(true)
    host:SetScript("OnSizeChanged", function(self, width, height)
        local separator = self.paneCount == 2 and PANE_SEPARATOR_WIDTH or 0
        self.paneWidth = (width - separator) / self.paneCount
        if Embolsao.db.rememberPosition then
            Embolsao.db.windowSize = { width = self.paneWidth, height = height }
        end
    end)

    local resizeButton = CreateFrame("Button", nil, host, "PanelResizeButtonTemplate")
    resizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeButton:Init(host, PANE_DEFAULT_WIDTH, PANE_DEFAULT_HEIGHT, PANE_DEFAULT_WIDTH * 2, PANE_DEFAULT_HEIGHT * 2)
    host.resizeButton = resizeButton

    host:Hide()
    -- Closing the window (its own X, Escape...) closes both parts.
    host:HookScript("OnHide", function()
        bagsWindow.Hide()
        bankWindow.Hide()
    end)

    -- Let Escape close us too, same as any other native panel.
    tinsert(UISpecialFrames, "EmbolsaoWindowFrame")

    host:SetPortraitToAsset(PORTRAIT_ICON)
    local title = string.format("Embolsao!! v%s", GetAddonVersion())
    if host.TitleContainer and host.TitleContainer.TitleText then
        host.TitleContainer.TitleText:SetText(title)
    elseif host.TitleText then
        host.TitleText:SetText(title)
    end

    host.menuButton = CreateHostMenuButton()

    -- The divider between the two panes; only there while both are.
    host.separator = host:CreateTexture(nil, "ARTWORK")
    host.separator:SetColorTexture(1, 1, 1, 0.25)
    host.separator:SetWidth(2)
    host.separator:SetPoint("TOP", host, "TOP", 0, -(CONTENT_TOP_OFFSET - 6))
    host.separator:SetPoint("BOTTOM", host, "BOTTOM", 0, BOTTOM_MARGIN + 2)
    host.separator:Hide()

    return host
end

--------------------------------------------------------------------------
-- Pane factory: everything that's genuinely tied to ONE pane of the Embolsao
-- window (its tab panel, search box, item grid, footer, drag state, stack
-- popout) lives here as a local instead of a module-level singleton, so each
-- call produces one independent, fully-featured pane. Called once for the
-- bags pane and once for the bank pane (further down) -- both get tabs,
-- search, sort, collapsible categories, empty-slot groups and stack popouts
-- identically, since it's the exact same code either way. The two panes share
-- ONE window frame (EnsureHost); the internal names still say "window".
--
-- config fields:
--   id                 -- "Bags" | "Bank", used for frame/global names
--   paneLabel()        -- the pane's name, shown above it when two panes share the window
--   closablePane       -- give the pane its own X, closing just that pane (bank)
--   OnShown()          -- optional; runs right after the pane is shown from a native frame
--   hasFooter          -- money/XP strip (bags) or bank purchase strip (bank)
--   hasBankPurchase    -- footer offers to buy more bank space (bank only)
--   hasBankModeToggle  -- Bank/Warband Bank toggle (bank only)
--   applyDefaultTab    -- honor the "Default Tab" preference on open (bags only)
--   GetInventory()          -> the merged {[itemID]=entry} table to show
--   GetEmptySlotGroups()    -> that pool's empty-slot groups (Core.lua)
--   GetActiveTab() / SetActiveTab(id)
--   Rescan()           -- (re)populate GetInventory()'s backing data
--   IsManagedFrame(bagFrame) -- which native frames this window takes over
--------------------------------------------------------------------------

-- Every native frame either window has hooked OnShow/OnHide for -- shared,
-- since a frame belongs to at most one window's domain and both windows'
-- HandleNativeShow/Hide filter this same list via their own IsManagedFrame.
-- Declared here (not down by InstallBagFrameHooks, where it conceptually
-- lives) so CreateWindow's closures below can see it as an upvalue.
local nativeBagFrames = {}

-- Guards against a window's own SuppressNativeFrames() (below) hiding a
-- native frame and having that immediately fire OnBagFrameHide right back
-- at us, undoing the takeover it was just doing. Shared: only one
-- suppression pass across either window is ever in flight at a time.
local suppressingNativeHide = false

local function CreateWindow(config)
    local win = {}
    win.searchText = ""
    win.stackPopoutItemID = nil
    win.dropTarget, win.dropAfter = nil, nil
    win.suppressTakeoverOnce = nil
    win.keepOpenDuringPeek = nil

    local frame
    local tabButtons = {}
    local itemButtons = {}
    local headerRows = {}
    local emptySlotButtons = {}
    local dropIndicator
    local stackPopout
    local stackPopoutButtons = {}

    -- Showing or hiding a pane has to lay the window out EXPLICITLY. A pane
    -- is a child of the window frame, which starts hidden -- and a child of a
    -- hidden frame never gets its OnShow when Show() is called (it isn't
    -- visible yet), so waiting on that event would leave the window hidden
    -- forever: the native bag sound plays, nothing appears, no error.
    local function ShowPane()
        frame:Show()
        LayoutHost()
    end

    local function HidePane()
        if frame then frame:Hide() end
        -- Same reason as above: the pane's own OnHide won't fire if the whole
        -- window is already hidden, but its stack popout still has to go.
        win.ToggleStackExpansion(nil)
        LayoutHost()
    end

    -- The tab this window is actually showing: config.GetActiveTab() can name
    -- a tab that has since been hidden/deleted, in which case the window falls
    -- back to its first tab -- per-tab state (sort, collapsed headers) has to
    -- key off that same effective tab, not the stale saved ID.
    function win.GetActiveTab()
        local activeTab = config.GetActiveTab()
        local tabs = frame and frame.currentTabs
        if not tabs then return activeTab end
        for _, tab in ipairs(tabs) do
            if tab.id == activeTab then return activeTab end
        end
        return tabs[1] and tabs[1].id or activeTab
    end

    -- A tab's ID as its saved per-tab state (sort, collapsed categories) is
    -- keyed: prefixed for the bank's own set of tabs, since "All" exists in both
    -- sets and would otherwise share that state (see Filters.keys.statePrefix).
    function win.StateID(tabID)
        return Embolsao:GetTabStatePrefix(config.domain) .. tabID
    end

    -- Called by LayoutHost whenever the window switches between one pane and
    -- two. With two, each pane gets its name above its tabs and items (which
    -- pushes them down a row) and, for a pane that can close on its own, an X;
    -- alone, it looks exactly like the plain single window always did.
    function win.SetMergedLayout(merged)
        if not frame or not frame.tabPanel then return end

        local extra = merged and PANE_LABEL_EXTRA or 0
        frame.tabPanel:ClearAllPoints()
        frame.tabPanel:SetPoint("TOPLEFT", 10, -(CONTENT_TOP_OFFSET + extra))
        frame.tabPanel:SetPoint("BOTTOMLEFT", 10, BOTTOM_MARGIN)

        -- The search box stays on the toolbar row whatever the tab panel
        -- does, so its offset from the panel's top grows by the same amount.
        frame.searchBox:ClearAllPoints()
        frame.searchBox:SetPoint("TOPLEFT", frame.tabPanel, "TOPRIGHT", TAB_TO_ITEMS_GAP, CONTENT_TOP_OFFSET + extra + TOOLBAR_Y)

        frame.paneLabel:SetShown(merged)
        if frame.closePaneButton then
            frame.closePaneButton:SetShown(merged)
        end
    end

    local function EnsureDropIndicator()
        if dropIndicator then return dropIndicator end
        dropIndicator = frame.tabColumn:CreateTexture(nil, "OVERLAY")
        dropIndicator:SetHeight(4)
        dropIndicator:SetColorTexture(0.3, 1, 1, 1)
        dropIndicator:Hide()
        return dropIndicator
    end

    -- Returns the tab button the drag should insert before (or, for the
    -- very last slot, the one to insert after) plus that placeAfter flag.
    -- See the original comment history for why this walks by Y position
    -- rather than "whichever button is under the cursor".
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

        for i = #tabButtons, 1, -1 do
            local btn = tabButtons[i]
            if btn ~= draggedButton and btn.tabData then
                return btn, true
            end
        end

        return nil
    end

    local function CreateTabButton(index, tabData)
        local btn = CreateFrame("Button", nil, frame.tabColumn)
        btn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
        btn:SetPoint("TOP", 0, -(index - 1) * (TAB_ICON_SIZE + TAB_PADDING))

        -- A background plate (plus the selection highlight below) makes
        -- these read as buttons rather than item slots.
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

        -- Right-click now always has at least Edit to offer, "All" included
        -- -- built-in tabs (All among them) can have hidden items/category
        -- rules layered on top since Filters:UpdateBuiltInOverride.
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                Embolsao.TabEditor:ShowTabContextMenu(self, tabData, config.domain)
                return
            end
            config.SetActiveTab(tabData.id)
            win.Refresh()
        end)

        -- Drag an item from the bag grid straight onto this tab to hide it
        -- there (with confirmation) -- OnReceiveDrag covers releasing the
        -- drag directly over the button; OnMouseUp covers picking the item
        -- up with a click first and then clicking the tab.
        btn:SetScript("OnReceiveDrag", function(self)
            TryHideCursorItemOnTab(tabData, config.domain)
        end)
        btn:SetScript("OnMouseUp", function(self)
            if CursorHasItem() then
                TryHideCursorItemOnTab(tabData, config.domain)
            end
        end)

        -- Drag-to-reorder: OnDragStart fires on this button, but OnDragStop
        -- also always fires here (not on whatever's under the cursor when
        -- you let go) -- so the drop target has to be computed explicitly
        -- via GetDropTarget() rather than relied on to fire its own handler.
        -- "All" (tabData.id == "ALL") is exempt: it can't move.
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
                    win.dropTarget, win.dropAfter = target, placeAfter

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

                local target, placeAfter = win.dropTarget, win.dropAfter
                win.dropTarget, win.dropAfter = nil, nil
                if target then
                    Embolsao:GetFilters(config.domain):MoveTabRelative(self.tabData.id, target.tabData.id, placeAfter)
                    win.BuildTabs()
                    win.Refresh()
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
            Embolsao.TabEditor:Show(nil, config.domain)
        end)

        return btn
    end

    -- One PANE: everything that used to make up a whole window (tab panel,
    -- search box, item grid, footer). It's now a child of the single shared
    -- window frame (EnsureHost above), which supplies the border, portrait,
    -- title, menu, dragging and resizing; LayoutHost decides where in that
    -- frame each pane sits and how wide the frame is.
    local function EnsureFrame()
        if frame then return frame end

        EnsureHost()
        frame = CreateFrame("Frame", "Embolsao" .. config.id .. "Pane", host)
        frame:SetAllPoints(host)
        frame:Hide()

        -- The item grid's column count depends on the pane's current width:
        -- reflow whenever it changes (window resized, bank part opened...).
        frame:SetScript("OnSizeChanged", function() win.Refresh() end)
        -- The window is laid out by ShowPane/HidePane, deliberately NOT from
        -- here: when the whole window closes, every pane gets an OnHide too
        -- while still flagged as shown, and re-laying out from that would
        -- open the window right back.
        frame:HookScript("OnHide", function()
            win.ToggleStackExpansion(nil)
        end)

        -- Recessed side panel for the filter tabs, visually distinct from
        -- the item grid so tabs don't read as just more bag slots. Its real
        -- anchors are set by win.SetMergedLayout (below), which also makes room
        -- for the pane's name label when two panes share the window.
        frame.tabPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.tabPanel:SetWidth(TAB_ICON_SIZE + TAB_PANEL_PADDING * 2 + SCROLLBAR_CLEARANCE)
        frame.tabPanel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame.tabPanel:SetBackdropColor(0, 0, 0, 0.35)
        frame.tabPanel:SetBackdropBorderColor(1, 1, 1, 0.25)

        -- Own search box, not Blizzard's native bag one -- filters our own
        -- list by item name instead. Aligned with the item grid's left edge,
        -- not the pane's, so it doesn't sit under the portrait icon.
        frame.searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
        frame.searchBox:SetSize(150, 20)
        frame.searchBox:HookScript("OnTextChanged", function(self)
            win.searchText = self:GetText() or ""
            win.Refresh()
        end)

        -- The pane's name ("Bags" / "Bank"), a size up from the rest of the
        -- text, just above its tabs and items -- only shown while two panes
        -- share the window and it matters which is which.
        frame.paneLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        frame.paneLabel:SetPoint("TOPLEFT", 14, -CONTENT_TOP_OFFSET)
        frame.paneLabel:SetText(config.paneLabel())
        frame.paneLabel:Hide()

        -- Closes just this pane (the window's own X closes everything). Only
        -- panes that can come and go on their own have one -- the bank part.
        if config.closablePane then
            local closePane = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
            closePane:SetSize(22, 22)
            closePane:SetPoint("TOPRIGHT", -12, -(CONTENT_TOP_OFFSET - 4))
            closePane:SetScript("OnClick", function() win.Hide() end)
            closePane:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L.CLOSE_PANE_TOOLTIP)
                GameTooltip:Show()
            end)
            closePane:SetScript("OnLeave", GameTooltip_Hide)
            closePane:Hide()
            frame.closePaneButton = closePane
        end

        -- Both the tab column and the item grid are wrapped in a real
        -- UIPanelScrollFrameTemplate (mouse wheel + scrollbar included for
        -- free) since both lists can outgrow the visible area.
        frame.tabScrollFrame = CreateFrame("ScrollFrame", nil, frame.tabPanel, "UIPanelScrollFrameTemplate")
        frame.tabScrollFrame:SetPoint("TOPLEFT", TAB_PANEL_PADDING, -TAB_PANEL_PADDING)
        frame.tabScrollFrame:SetPoint("BOTTOMRIGHT", -TAB_PANEL_PADDING - SCROLLBAR_CLEARANCE, TAB_PANEL_PADDING)
        -- Right-click anywhere in here that isn't a tab button falls
        -- through to this -- covers the thin margin around the column and
        -- any empty space below the last tab.
        frame.tabScrollFrame:HookScript("OnMouseUp", function(self, mouseButton)
            if mouseButton == "RightButton" then
                ShowHiddenTabsMenu(self, config.domain)
            end
        end)

        -- Anchored on TOPLEFT only, with an explicit width and a height kept
        -- up to date in Refresh -- a scroll child's rect must always be
        -- fully resolved.
        frame.tabColumn = CreateFrame("Frame", nil, frame.tabScrollFrame)
        frame.tabColumn:SetPoint("TOPLEFT")
        frame.tabColumn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
        frame.tabScrollFrame:SetScrollChild(frame.tabColumn)

        -- Item grid, well clear of the tab panel, using real ItemButton
        -- widgets so icons/borders/counts render like Blizzard's own bag
        -- slots.
        frame.itemScrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.itemScrollFrame:SetPoint("TOPLEFT", frame.tabPanel, "TOPRIGHT", TAB_TO_ITEMS_GAP, 0)
        local footerClearance = config.hasFooter and (BOTTOM_MARGIN + FOOTER_HEIGHT + FOOTER_GAP) or BOTTOM_MARGIN
        frame.itemScrollFrame:SetPoint("BOTTOMRIGHT", -10 - SCROLLBAR_CLEARANCE, footerClearance)

        frame.itemContainer = CreateFrame("Frame", nil, frame.itemScrollFrame)
        frame.itemContainer:SetPoint("TOPLEFT")
        frame.itemContainer:SetSize(ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING), ITEM_SIZE)
        frame.itemScrollFrame:SetScrollChild(frame.itemContainer)

        -- Anchors for the tab panel and search box (see SetMergedLayout).
        win.SetMergedLayout(false)

        if config.hasBankModeToggle then
            -- "Bank" / "Warband Bank" toggle -- switches which pool this
            -- window shows; the tabs, search box and sort options
            -- underneath stay exactly the same either way.
            frame.bankModeToggle = CreateFrame("Frame", nil, frame)
            frame.bankModeToggle:SetSize(1, 22)
            -- Top-right of this pane's own toolbar row (the window's single
            -- menu button lives at the far right of the whole window).
            frame.bankModeToggle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, TOOLBAR_Y)
            frame.bankModeToggle:Hide()

            local function CreateBankModeButton(text)
                local btn = CreateFrame("Button", nil, frame.bankModeToggle, "UIPanelButtonTemplate")
                btn:SetSize(90, 22)
                btn:SetText(text)
                return btn
            end

            frame.bankModeToggle.warbandButton = CreateBankModeButton(L.BANK_VIEW_WARBAND)
            frame.bankModeToggle.warbandButton:SetPoint("TOPRIGHT", 0, 0)
            frame.bankModeToggle.warbandButton:SetScript("OnClick", function()
                Embolsao.BankViewMode = "WARBAND"
                Embolsao:ScanBank()
                win.Refresh()
                win.UpdateBankModeToggle()
            end)

            frame.bankModeToggle.personalButton = CreateBankModeButton(L.BANK_VIEW_PERSONAL)
            frame.bankModeToggle.personalButton:SetPoint("TOPRIGHT", frame.bankModeToggle.warbandButton, "TOPLEFT", -4, 0)
            frame.bankModeToggle.personalButton:SetScript("OnClick", function()
                Embolsao.BankViewMode = "PERSONAL"
                Embolsao:ScanBank()
                win.Refresh()
                win.UpdateBankModeToggle()
            end)
        end

        if config.hasFooter then
            -- Money + XP strip, pinned to the bottom of the window itself
            -- (not the scroll areas) so it never moves as the item grid
            -- scrolls -- same fixed footer Blizzard's own bag window has.
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

            -- The XP text (now longer, with rested XP) stops short of the
            -- money instead of running underneath it on a narrow window.
            frame.footer.xpText:SetPoint("RIGHT", frame.footer.moneyFrame, "LEFT", -6, 0)
            frame.footer.xpText:SetJustifyH("LEFT")
            frame.footer.xpText:SetWordWrap(false)

            if config.hasBankPurchase then
                -- Bank footer: "Buy ..." button plus what the next purchase
                -- costs, on the left; the player's own money stays on the
                -- right. Shown only while there is something to buy
                -- (UpdateBankFooter).
                local buy = CreateFrame("Button", nil, frame.footer, "UIPanelButtonTemplate")
                buy:SetHeight(20)
                buy:SetPoint("LEFT", 6, 0)
                buy:SetScript("OnClick", function()
                    Embolsao:RequestBankPurchase()
                end)
                buy:SetScript("OnEnter", function(self)
                    local purchase = frame.footer.purchase
                    if not purchase then return end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(self:GetText())
                    if not purchase.canAfford then
                        GameTooltip:AddLine(L.BUY_BANK_NOT_ENOUGH_MONEY, 1, 0.2, 0.2)
                    end
                    GameTooltip:Show()
                end)
                buy:SetScript("OnLeave", GameTooltip_Hide)
                frame.footer.purchaseButton = buy

                local cost = CreateFrame("Frame", nil, frame.footer, "SmallMoneyFrameTemplate")
                cost:SetPoint("LEFT", buy, "RIGHT", 8, 0)
                SmallMoneyFrame_OnLoad(cost)
                MoneyFrame_SetType(cost, "STATIC")
                frame.footer.purchaseCost = cost

                buy:Hide()
                cost:Hide()
            end
        end

        return frame
    end

    -- Retail moved this one behind the GameRulesUtil namespace; Classic
    -- still has it as a bare global.
    local function IsAtEffectiveMaxLevel()
        if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
            return GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
        end
        return IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() or false
    end

    -- Not max level -> "1234 / 5678"; at max level (or XP gain is otherwise
    -- disabled) there's no next-level total to show, so it goes blank.
    local function UpdateFooterXP()
        if not config.hasFooter or config.hasBankPurchase or not frame then return end
        if IsAtEffectiveMaxLevel() or IsXPUserDisabled() then
            frame.footer.xpText:SetText("")
            return
        end

        local currXP, maxXP = UnitXP("player"), UnitXPMax("player")
        local percent = maxXP > 0 and math.floor((currXP / maxXP) * 100 + 0.5) or 0
        local text = string.format("%d / %d (%d%%)", currXP, maxXP, percent)

        -- Rested XP, only when there is any: in Blizzard's own rested-bar blue,
        -- as an amount and as a share of the current level (it can exceed 100%
        -- -- rested XP can bank up to a level and a half).
        local rested = GetXPExhaustion and GetXPExhaustion()
        if rested and rested > 0 then
            local restedPercent = maxXP > 0 and math.floor((rested / maxXP) * 100 + 0.5) or 0
            text = text .. "  |cff4d9bff" .. string.format(L.RESTED_XP, rested, restedPercent) .. "|r"
        end

        frame.footer.xpText:SetText(text)
    end
    win.UpdateFooterXP = UpdateFooterXP

    -- Shows/hides the Bank/Warband Bank toggle and reflects which one is
    -- currently selected (the active one disabled, reading as "you're here").
    -- The bank footer's "Buy ..." button: what the next purchase is (a bank
    -- tab for whichever bank is being viewed, or Classic's next bag slot) and
    -- what it costs; hidden when there's nothing to buy or no banker.
    function win.UpdateBankFooter()
        if not config.hasBankPurchase or not frame or not frame.footer or not frame.footer.purchaseButton then return end

        local footer = frame.footer
        local purchase = Embolsao:GetNextBankPurchase()
        footer.purchase = purchase
        footer.purchaseButton:SetShown(purchase ~= nil)
        footer.purchaseCost:SetShown(purchase ~= nil)
        if not purchase then return end

        local label = L.BUY_BANK_SLOT
        if purchase.kind == "tab" then
            label = (purchase.bankType == Enum.BankType.Account) and L.BUY_WARBAND_TAB or L.BUY_BANK_TAB
        end
        footer.purchaseButton:SetText(label)
        footer.purchaseButton:SetWidth(footer.purchaseButton:GetFontString():GetStringWidth() + 28)
        footer.purchaseButton:SetEnabled(purchase.canAfford)

        MoneyFrame_Update(footer.purchaseCost, purchase.cost)
        if SetMoneyFrameColorByFrame then
            SetMoneyFrameColorByFrame(footer.purchaseCost, purchase.canAfford and "white" or "red")
        end
    end

    function win.UpdateBankModeToggle()
        if not config.hasBankModeToggle or not frame or not frame.bankModeToggle then return end

        -- Switching between the personal and Warband banks changes what
        -- there is to buy, and this runs on every bank refresh anyway.
        win.UpdateBankFooter()

        local showToggle = Embolsao:CanUseWarbandBank()
        frame.bankModeToggle:SetShown(showToggle)
        if not showToggle then return end

        local isWarband = Embolsao.BankViewMode == "WARBAND"
        frame.bankModeToggle.personalButton:SetEnabled(isWarband)
        frame.bankModeToggle.warbandButton:SetEnabled(not isWarband)
    end

    -- The "item actions" menu: what the MENU binding (Alt+Click by default)
    -- opens on an item. Entries only appear when they make sense for that
    -- item; the junk/recent/sell ones belong to the bags window alone (the
    -- bank has no such groups, and nothing is sold from there).
    local function ShowItemActionsMenu(btn)
        local itemID = btn.itemID
        if not itemID then return end

        local bagID, slot = btn:GetBagID(), btn:GetID()
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        local name = Embolsao.GetItemInfo(itemID) or tostring(itemID)
        local link = info and info.hyperlink
        local isBagsWindow = config.id == "Bags"
        local isRecent = btn.RecentDismiss ~= nil and btn.RecentDismiss:IsShown()

        -- The tab this window is showing, for "Hide on <tab>".
        local activeTabID = win.GetActiveTab()
        local tabData
        for _, tab in ipairs(frame.currentTabs or {}) do
            if tab.id == activeTabID then
                tabData = tab
                break
            end
        end

        MenuUtil.CreateContextMenu(btn, function(_, root)
            root:CreateTitle(name)

            -- A merged super-stack (several real stacks shown as one): open
            -- them individually in the popout -- the same action as the
            -- STACKS binding, and closing it again when it's already open.
            if btn.locations and #btn.locations > 1 then
                root:CreateButton(
                    win.stackPopoutItemID == itemID and L.MENU_STACKS_HIDE or L.MENU_STACKS_SHOW,
                    function() win.ToggleStackExpansion(itemID, btn) end
                )
            end

            if info and (info.stackCount or 1) > 1 and not info.isLocked then
                root:CreateButton(L.MENU_SPLIT, function() StartSplit(btn) end)
            end

            if link then
                root:CreateButton(L.MENU_LINK, function()
                    if not ChatEdit_InsertLink(link) then
                        ChatFrame_OpenChat(link)
                    end
                end)
            end

            if tabData and Embolsao.TabEditor then
                root:CreateButton(string.format(L.MENU_HIDE_ON_TAB, tabData.name), function()
                    Embolsao.TabEditor:ConfirmHideItemOnTab(itemID, tabData, config.domain)
                end)
            end

            if isBagsWindow then
                -- Grey items are junk by quality and stay that way; anything
                -- else can be put on (or taken off) the player's own junk list.
                if info and info.quality ~= 0 then
                    local junkList = Embolsao.db.junkItemIDs
                    local function ToggleJunk()
                        junkList[itemID] = (not junkList[itemID]) or nil
                        Embolsao:ScanBags()
                        UI:Refresh()
                    end
                    root:CreateButton(junkList[itemID] and L.MENU_UNMARK_JUNK or L.MENU_MARK_JUNK, ToggleJunk)
                end

                if isRecent then
                    root:CreateButton(L.MENU_DISMISS_RECENT, function()
                        Embolsao:DismissRecentItem(itemID, btn.locations)
                        Embolsao:ScanBags()
                        UI:Refresh()
                    end)
                end

                if IsAtMerchant() and info and not info.hasNoValue then
                    root:CreateButton(L.MENU_SELL, function()
                        C_Container.UseContainerItem(bagID, slot)
                    end)
                end
            end
        end)
    end

    -- Bare "ItemButton" is Blizzard's own intrinsic widget type (icon +
    -- count + quality border). We don't pull in
    -- ContainerFrameItemButtonTemplate itself, since that hard-requires a
    -- real container-frame parent. Shared between the main grid and the
    -- stack-expansion popout below: both are real ItemButtons bound to a
    -- real (bagID, slot) via SetBagID/SetID.
    local function SetupItemButtonInteractions(btn)
        btn.UpgradeIcon = CreateUpgradeIcon(btn)
        btn.RecentDismiss = CreateRecentDismissButton(btn, win)

        -- Flagged so the modifier-key refresh at the bottom of the file knows
        -- this tooltip is ours and can be rebuilt when Ctrl/Shift/Alt changes.
        btn.isEmbolsaoItemButton = true
        btn:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            AddBindingHints(self)
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

            -- Modifier + left-click runs whichever action the player bound to
            -- that exact combo in the Bindings window (defaults: Ctrl = show a
            -- merged stack's real stacks in a popout, Shift = split, Alt = the
            -- item actions menu). Read from the raw key state, so Blizzard's
            -- own Modified Click Actions settings can't shadow it.
            if mouseButton == "LeftButton" then
                local action = ActionForCurrentClick()
                if action == "STACKS" then
                    if self.locations and #self.locations > 1 then
                        win.ToggleStackExpansion(self.itemID, self)
                    end
                    return
                elseif action and not CursorHasItem() then
                    if action == "SPLIT" then
                        StartSplit(self)
                    elseif action == "MENU" then
                        ShowItemActionsMenu(self)
                    end
                    return
                end
            end

            -- Any OTHER modified click is something we don't replicate.
            -- Bail instead of guessing.
            if CurrentModifierCombo() ~= "" then
                return
            end

            if mouseButton == "RightButton" then
                -- Normally already done by the secure overlay (see
                -- CreateUseOverlay); only the cases it can't express get here.
                if Embolsao.AtBank then
                    -- Deposit/withdraw. The secure "use item" overlay does
                    -- exactly one stack, so it's switched off at a banker (see
                    -- UpdateUseOverlay) and this moves every stack the button
                    -- stands for. The modern bank must also be told which bank
                    -- (personal or Warband) the click is about.
                    local bankType
                    if IsModernBankOpen() then
                        bankType = Embolsao.BankViewMode == "WARBAND"
                            and Enum.BankType.Account or Enum.BankType.Character
                    end
                    if self.locations and #self.locations > 0 then
                        MoveStacksAcrossBank(self.locations, bankType)
                    else
                        MoveStacksAcrossBank({ { bagID = bagID, slot = slot } }, bankType)
                    end
                elseif not self.useOverlayAction then
                    C_Container.UseContainerItem(bagID, slot)
                end
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
    -- backing that merged stack. Positioning is NOT done here -- it happens
    -- every Refresh (even for reused buttons), since the column count
    -- depends on the window's current width.
    local function GetOrCreateItemButton(index)
        local btn = itemButtons[index]
        if btn then return btn end

        btn = CreateFrame("ItemButton", nil, frame.itemContainer)
        SetupItemButtonInteractions(btn)

        itemButtons[index] = btn
        return btn
    end

    -- The merged/virtual view has no visual "empty square" of its own (one
    -- button per itemID, not per physical slot), so there's normally
    -- nowhere to drop a picked-up or split-off item to start a new stack.
    -- One pooled button per GetEmptySlotGroups() entry.
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
            local bagName
            if self.group and self.group.bagID then
                local familyKey = self.group.family and BAG_FAMILY_LABEL_KEYS[self.group.family]
                bagName = (familyKey and L[familyKey]) or C_Container.GetBagName(self.group.bagID)
            end
            GameTooltip:SetText(bagName and string.format(L.EMPTY_SLOT_TITLE_BAG, bagName) or L.EMPTY_SLOT_TITLE)
            GameTooltip:AddLine(L.EMPTY_SLOT_DESC, 1, 1, 1, true)
            if self.group then
                local hint = L.EMPTY_SLOT_OPEN_ALL_BAGS_HINT
                if self.group.bagID then
                    -- bagIDs on a special group means several bags of the
                    -- same kind were merged into this one button.
                    hint = self.group.bagIDs and L.EMPTY_SLOT_OPEN_BAGS_HINT or L.EMPTY_SLOT_OPEN_BAG_HINT
                end
                GameTooltip:AddLine(hint, 1, 1, 1, true)
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
                    -- A lone special bag maps to one real bagID and opens
                    -- just that one; the shared "general" bucket, and any
                    -- special group merging several bags of one kind, have
                    -- a list of bagIDs to open instead.
                    win.OpenNativeBags(self.group.bagIDs or self.group.bagID)
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

        -- Action button at the right end of the two pinned groups' headers
        -- (see Refresh, which picks its icon per header key):
        --   Recent -> remove everything listed under it from Recent
        --   Junk   -> sell everything listed under it (only at a vendor)
        -- Both are scoped to what this window is showing -- the active tab
        -- and search -- exactly the items visible in the group.
        local action = CreateFrame("Button", nil, header)
        action:SetSize(14, 14)
        action:SetPoint("RIGHT", 0, 0)
        action:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if header.key == "recentitems" then
                GameTooltip:SetText(L.DISMISS_ALL_RECENT_HINT)
            elseif header.key == "junkitems" then
                if IsAtMerchant() then
                    GameTooltip:SetText(L.SELL_JUNK_HINT)
                    local total = 0
                    for _, entry in ipairs(win.GetFilteredEntries(true)) do
                        if entry.isJunk then
                            local sellPrice = select(11, Embolsao.GetItemInfo(entry.itemID))
                            total = total + (sellPrice or 0) * entry.count
                        end
                    end
                    if total > 0 then
                        GameTooltip:AddLine(Embolsao.GetCoinTextureString(total), 1, 1, 1)
                    end
                else
                    GameTooltip:SetText(L.SELL_JUNK_NO_VENDOR)
                end
            end
            GameTooltip:Show()
        end)
        action:SetScript("OnLeave", GameTooltip_Hide)
        action:SetScript("OnClick", function()
            if header.key == "recentitems" then
                for _, entry in ipairs(win.GetFilteredEntries(true)) do
                    if entry.isRecent then
                        Embolsao:DismissRecentItem(entry.itemID, entry.locations)
                    end
                end
                Embolsao:ScanBags()
                UI:Refresh()
            elseif header.key == "junkitems" then
                SellJunkEntries(win.GetFilteredEntries(true))
            end
        end)
        action:Hide()
        header.actionButton = action

        header:SetScript("OnMouseUp", function(self)
            if not self.key then return end
            local collapsed = GetCollapsedHeaders(win.StateID(win.GetActiveTab()))
            if collapsed[self.key] then
                collapsed[self.key] = nil
            else
                collapsed[self.key] = true
            end
            win.Refresh()
        end)

        headerRows[index] = header
        return header
    end

    --------------------------------------------------------------------
    -- Stack expansion popout: Ctrl+Click a merged super-stack to see and
    -- interact with the real stacks backing it individually.
    --------------------------------------------------------------------

    local STACK_POPOUT_COLUMNS = 6
    local STACK_POPOUT_PADDING = 10

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

        stackPopout = CreateFrame("Frame", "Embolsao" .. config.id .. "StackPopoutFrame", UIParent, "BackdropTemplate")
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
        tinsert(UISpecialFrames, "Embolsao" .. config.id .. "StackPopoutFrame")

        local close = CreateFrame("Button", nil, stackPopout, "UIPanelCloseButtonDefaultAnchors")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() win.ToggleStackExpansion(nil) end)

        return stackPopout
    end

    -- Re-resolves the currently-expanded itemID against the live inventory
    -- (called on open and again on every Refresh while it's open) and lays
    -- out one real button per real (bagID, slot) location. Closes itself
    -- automatically once the item no longer resolves to a super-stack.
    local function RefreshStackPopout()
        local entry = config.GetInventory()[win.stackPopoutItemID]
        if not entry or not entry.locations or #entry.locations < 2 then
            win.ToggleStackExpansion(nil)
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
            UpdateUseOverlay(btn, location.bagID, location.slot)
            if info then
                SetItemButtonTexture(btn, info.iconFileID)
                SetItemButtonCount(btn, info.stackCount)
                SetItemButtonQuality(btn, info.quality, entry.itemID)
            end
            UpdatePawnUpgradeIcon(btn, info and info.hyperlink)
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
    -- already-expanded stack closes it (toggle); Ctrl+Clicking a different
    -- one switches straight to that one.
    function win.ToggleStackExpansion(itemID, anchorButton)
        if not itemID or itemID == win.stackPopoutItemID then
            win.stackPopoutItemID = nil
            if stackPopout then stackPopout:Hide() end
            return
        end

        win.stackPopoutItemID = itemID
        local popout = EnsureStackPopout()
        if anchorButton then
            popout:ClearAllPoints()
            popout:SetPoint("TOP", anchorButton, "BOTTOM", 0, -6)
        end
        popout:Show()
        RefreshStackPopout()
        win.ApplyModifierDimming(ActionForCurrentClick())
    end

    -- While the modifier bound to STACKS or SPLIT is held, the items that
    -- action can't do anything with fade out, so what the click will work on
    -- stands out at a glance. actionID is what ActionForCurrentClick() says
    -- (nil = no bound modifier held: everything back to full strength). Menu
    -- applies to every item, so it fades nothing. The popout's own stacks
    -- never fade for STACKS -- they're the result of that very action.
    local DIMMED_ITEM_ALPHA = 0.3
    function win.ApplyModifierDimming(actionID)
        local function Apply(btn, isPopout)
            local dim = false
            if actionID and btn:IsShown() and btn.itemID and not (isPopout and actionID == "STACKS") then
                dim = not BindingApplies(actionID, btn)
            end
            btn:SetAlpha(dim and DIMMED_ITEM_ALPHA or 1)
        end
        for _, btn in pairs(itemButtons) do Apply(btn, false) end
        for _, btn in pairs(stackPopoutButtons) do Apply(btn, true) end
    end

    function win.RefreshPawnIcons()
        for _, btn in pairs(itemButtons) do
            if btn.itemID then UpdatePawnUpgradeIcon(btn, btn.pawnHyperlink) end
        end
        for _, btn in pairs(stackPopoutButtons) do
            if btn.itemID then UpdatePawnUpgradeIcon(btn, btn.pawnHyperlink) end
        end
    end

    function win.BuildTabs()
        if not frame then return end
        for _, btn in ipairs(tabButtons) do
            btn:Hide()
        end
        wipe(tabButtons)

        -- Only visible tabs get a clickable button; hidden ones still exist
        -- for Preferences' tab manager and for GetFilteredEntries' lookup.
        frame.currentTabs = Embolsao:GetFilters(config.domain):GetVisibleTabs()
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

    function win.UpdateSelectedTab()
        local activeTab = config.GetActiveTab()
        for index, tabData in ipairs(frame.currentTabs or {}) do
            local btn = tabButtons[index]
            local isActive = tabData.id == activeTab
            btn.icon:SetDesaturated(not isActive)
            btn.icon:SetAlpha(isActive and 1 or 0.55)
            btn.selectedBg:SetShown(isActive)
        end
    end

    -- ignoreTab: skip the active tab's own filter (search still applies) --
    -- the set the pinned Recent/Junk groups are built from, which are the
    -- same on every tab.
    function win.GetFilteredEntries(ignoreTab)
        local tabs = frame.currentTabs or Embolsao:GetFilters(config.domain):GetAllTabs()
        local activeTab = config.GetActiveTab()

        local activeFilter
        for _, tab in ipairs(tabs) do
            if tab.id == activeTab then
                activeFilter = tab
                break
            end
        end
        activeFilter = activeFilter or tabs[1]

        local search = (win.searchText or ""):lower()

        local results = {}
        for _, entry in pairs(config.GetInventory()) do
            if ignoreTab or activeFilter.predicate(entry) then
                local matchesSearch = true
                if search ~= "" then
                    local name = Embolsao.GetItemInfo(entry.itemID)
                    matchesSearch = name ~= nil and name:lower():find(search, 1, true) ~= nil
                end
                if matchesSearch then
                    table.insert(results, entry)
                end
            end
        end
        local sortMode, sortAscending = GetTabSort(win.StateID(activeFilter.id))
        table.sort(results, MakeComparator(sortMode, sortAscending))
        return results
    end

    function win.Refresh()
        if not frame or not frame:IsShown() then return end
        if not frame.currentTabs then
            win.BuildTabs()
        end
        win.UpdateSelectedTab()

        -- Column count tracks the item area's current width, so widening
        -- the window adds columns instead of just revealing empty space.
        local itemsPerRow = math.max(ITEMS_PER_ROW, math.floor(frame.itemScrollFrame:GetWidth() / (ITEM_SIZE + ITEM_PADDING)))
        frame.itemContainer:SetWidth(itemsPerRow * (ITEM_SIZE + ITEM_PADDING))

        local entries = win.GetFilteredEntries()
        local activeTabID = win.GetActiveTab()
        local activeTabName
        for _, tab in ipairs(frame.currentTabs or {}) do
            if tab.id == activeTabID then
                activeTabName = tab.name
                break
            end
        end
        local rows = BuildLayoutRows(entries, win.GetFilteredEntries(true), config.GetEmptySlotGroups(), win.StateID(activeTabID), activeTabName)

        -- Headers and item cells have different row heights, so position is
        -- tracked as a running pixel offset rather than a uniform row index.
        local yOffset, col = 0, 0
        local itemIndex, headerIndex, emptySlotIndex = 0, 0, 0

        for _, row in ipairs(rows) do
            if row.kind == "gap" then
                if col > 0 then
                    yOffset = yOffset + (ITEM_SIZE + ITEM_PADDING)
                    col = 0
                end
                yOffset = yOffset + GROUP_GAP_HEIGHT
            elseif row.kind == "header" then
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
                -- Only the Recent and Junk headers carry an action button;
                -- the rule stops short of it there, and runs edge to edge on
                -- every other header.
                local actionIcon
                if row.key == "recentitems" then
                    actionIcon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
                elseif row.key == "junkitems" then
                    actionIcon = "Interface\\Icons\\INV_Misc_Coin_01"
                end
                local action = header.actionButton
                header.line:ClearAllPoints()
                header.line:SetPoint("LEFT", header.text, "RIGHT", 6, 0)
                if actionIcon then
                    action:SetNormalTexture(actionIcon)
                    action:SetHighlightTexture(actionIcon, "ADD")
                    -- Selling only works with a vendor window open; grey the
                    -- coin out otherwise so it reads as unavailable.
                    action:GetNormalTexture():SetDesaturated(row.key == "junkitems" and not IsAtMerchant())
                    action:Show()
                    header.line:SetPoint("RIGHT", action, "LEFT", -4, 0)
                else
                    action:Hide()
                    header.line:SetPoint("RIGHT")
                end
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
                    -- Blizzard's own code hardcodes this rather than
                    -- resolving it through SetBagPortraitTexture too.
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
                UpdateUseOverlay(btn, location and location.bagID, location and location.slot)
                SetItemButtonTexture(btn, entry.icon)
                SetItemButtonCount(btn, entry.count)
                SetItemButtonQuality(btn, entry.quality, entry.itemID)
                UpdatePawnUpgradeIcon(btn, entry.hyperlink)
                btn.RecentDismiss:SetShown(row.isRecent == true)
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
        if win.stackPopoutItemID then
            RefreshStackPopout()
        end

        -- Buttons are reused for different items on every refresh -- redo
        -- the fade for a modifier that's being held right now.
        win.ApplyModifierDimming(ActionForCurrentClick())
    end

    -- One-off peek at Blizzard's own bag window, without touching the
    -- persistent "disabled" setting.
    --
    -- With a single bagID, opens just that one bag via ToggleBag alongside
    -- this window, which stays open. With a list of bagIDs or no bagID at
    -- all, it's a full swap instead: closes this window first so the two
    -- don't end up stacked on top of each other.
    function win.OpenNativeBags(bagID)
        -- Modern clients (retail, the Classic "Forever" beta) default to
        -- Blizzard's "Combine all bags" mode, where there is no per-bag
        -- window at all: ToggleBag(id) just toggles the one combined frame
        -- (ContainerFrame.lua -> ToggleBag_Combined), whose frame ID never
        -- matches the bag we asked for. That made the single-bag peek below
        -- get suppressed straight away, and a list of bags toggle the
        -- combined frame open, closed, open... So in that mode the peek is
        -- always the full swap: this window closes, the combined native
        -- frame opens, untouched.
        local settings = _G.ContainerFrameSettingsManager
        local combinedID = type(bagID) == "number" and bagID or nil
        if settings and settings.IsUsingCombinedBags and settings:IsUsingCombinedBags(combinedID)
            and _G.OpenBackpack then
            if frame and frame:IsShown() then
                HidePane()
            end
            win.suppressTakeoverOnce = true
            _G.OpenBackpack()
            return
        end

        local isSinglePeek = type(bagID) == "number"

        if isSinglePeek then
            -- Scoped to this exact bagID -- a blanket exemption would let
            -- OTHER native frames slip past untouched too in the same tick.
            win.keepOpenDuringPeek = bagID
            win.suppressTakeoverOnce = bagID
        else
            if frame and frame:IsShown() then
                HidePane()
            end
            win.suppressTakeoverOnce = true
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

    -- We take over display duty for bags entirely: this window shows, the
    -- native frame(s) it manages get hidden. Called by the shared
    -- OnBagFrameShow dispatcher once it's determined this window owns the
    -- frame that just showed.
    function win.HandleNativeShow(nativeFrame)
        -- "Disabled" via the minimap button's menu, or a one-shot bypass
        -- from OpenNativeBags -- either way, leave native alone.
        --
        -- win.suppressTakeoverOnce is either `true` (blanket) or a specific
        -- bagID (a single-bag peek), scoped the same way as before.
        local suppressThis = Embolsao.db.disabled
            or win.suppressTakeoverOnce == true
            or (type(win.suppressTakeoverOnce) == "number" and nativeFrame:GetID() == win.suppressTakeoverOnce)

        if suppressThis then
            C_Timer.After(0, function()
                win.suppressTakeoverOnce = nil
            end)
            return
        end

        EnsureFrame()
        if not frame.currentTabs then
            win.BuildTabs()
        end
        if config.applyDefaultTab and Embolsao.db.defaultTab and Embolsao.db.defaultTab ~= "LAST" then
            config.SetActiveTab(Embolsao.db.defaultTab)
        end
        ShowPane()
        if config.OnShown then config.OnShown() end

        local function ScanAndSuppress()
            config.Rescan()
            win.Refresh()
            UpdateFooterXP()
            win.UpdateBankModeToggle()
            win.SuppressNativeFrames()
        end

        -- The bank's own item data turns out not to be queryable via
        -- C_Container.GetContainerItemInfo until Blizzard's native bank
        -- frame has actually been visible/processing for a moment --
        -- confirmed live: hiding it immediately left every slot reading as
        -- empty, even on repeated manual rescans, while it worked instantly
        -- with the native frame left alone. config.rescanDelay (bank only)
        -- gives it that moment before we scan and take over display duty;
        -- bags has no such delay -- carried bag contents are always live.
        if config.rescanDelay then
            -- Only the SCAN waits. The native frame itself is taken out of
            -- sight right now (transparent and off-screen -- see
            -- SuppressNativeFrames; it stays "shown", so the data keeps
            -- loading): waiting to do that as well left Blizzard's bank
            -- window visible for that whole delay before ours took over.
            win.SuppressNativeFrames(true)
            C_Timer.After(config.rescanDelay, ScanAndSuppress)
        else
            ScanAndSuppress()
        end
    end

    function win.HandleNativeHide(nativeFrame)
        -- One-shot: a single-bag peek leaves this window open on purpose,
        -- so the native frame it opened closing again shouldn't take this
        -- window down with it.
        if win.keepOpenDuringPeek and nativeFrame:GetID() == win.keepOpenDuringPeek then
            win.keepOpenDuringPeek = nil
            return
        end
        if frame and not win.IsAnyManagedFrameShown() then
            HidePane()
        end
    end

    -- nativeBagFrames is the single shared list of every hooked native
    -- frame (both windows' domains) -- declared once near the top of the
    -- file, before either window is created.
    -- onlyBankFrame: just move the bank's own frame away, leaving any other
    -- native frame this window manages alone for now -- they are actually hidden,
    -- which is what can starve the bank data loading (see the rescanDelay
    -- comment in HandleNativeShow), so those wait for the delayed pass.
    function win.SuppressNativeFrames(onlyBankFrame)
        suppressingNativeHide = true
        for _, bagFrame in ipairs(nativeBagFrames) do
            if config.IsManagedFrame(bagFrame) then
                if bagFrame == _G.BankFrame then
                    -- BankFrame's own OnHide handler calls CloseBankFrame()
                    -- directly (confirmed against Blizzard's own
                    -- Classic/BankFrame.lua, and BankFrameBaseMixin:OnHide on
                    -- the modern bank -- retail and Forever) -- actually hiding it would
                    -- end the whole banking interaction with the server,
                    -- taking this window down with it, and also unregisters
                    -- the PLAYERBANKSLOTS_CHANGED listener that's what
                    -- actually populates bank item data in the first place.
                    -- Moved off-screen instead of hidden, so it stays
                    -- "shown" (IsShown() true) and keeps working normally
                    -- from the game's perspective -- just nowhere the
                    -- player can see or click it.
                    bagFrame:SetClampedToScreen(false)
                    bagFrame:EnableMouse(false)
                    bagFrame:EnableKeyboard(false)
                    bagFrame:SetAlpha(0)
                    bagFrame:ClearAllPoints()
                    bagFrame:SetPoint("CENTER", UIParent, "CENTER", -10000, -10000)
                    -- Its children (the modern bank's item buttons) keep
                    -- their own mouse handling. Sent to the back so that if
                    -- the UI panel manager ever pulls the frame back on
                    -- screen, whatever invisible buttons that brings can't sit
                    -- on top of our windows and eat their clicks.
                    if not bagFrame.embolsaoOldStrata then
                        bagFrame.embolsaoOldStrata = bagFrame:GetFrameStrata()
                    end
                    bagFrame:SetFrameStrata("BACKGROUND")
                elseif not onlyBankFrame then
                    bagFrame:Hide()
                end
            end
        end
        C_Timer.After(0, function()
            suppressingNativeHide = false
        end)
    end

    function win.IsAnyManagedFrameShown()
        for _, bagFrame in ipairs(nativeBagFrames) do
            if bagFrame:IsShown() and config.IsManagedFrame(bagFrame) then
                return true
            end
        end
        return false
    end

    win.IsManagedFrame = config.IsManagedFrame

    win.EnsureFrame = EnsureFrame
    win.GetFrame = function() return frame end
    win.IsShown = function() return frame and frame:IsShown() end
    win.Hide = HidePane

    return win
end

--------------------------------------------------------------------------
-- The two windows. Bags is the original window, unchanged in behavior;
-- Bank is the new one, sharing every bit of chrome/interaction the factory
-- above provides but scanning/showing bank storage instead.
--------------------------------------------------------------------------

-- ContainerFrameCombinedBags (retail only) shows several bags in one window
-- at once, so it can't be selectively split into "ours" vs "the bank's" the
-- way each individual ContainerFrameN can via its own :GetID() -- it's an
-- all-or-nothing frame, and it's always bags-domain (the bank's own tabs
-- render through individual ContainerFrameN, never combined).
local function IsCombinedBagsFrame(bagFrame)
    return bagFrame and bagFrame.GetName and bagFrame:GetName() == "ContainerFrameCombinedBags"
end

-- Classic/TBC's bank "Item Slots" grid isn't a ContainerFrameN at all --
-- it's BankFrame itself, permanently carrying :GetID() == BANK_CONTAINER
-- (set once by Blizzard's own code, confirmed against Classic/BankFrame.lua)
-- rather than being reassigned per-bag the way ContainerFrameN is. Retail's
-- BankFrame is a completely different beast: just the modern Bank Panel's
-- outer chrome (title bar, tab strip, purchase/deposit buttons) -- actual
-- bank tab contents (Enum.BagIndex.CharacterBankTab_*) render through their
-- own separate ContainerFrameN frames, covered by IsBankManagedBagID below.
-- Checked by identity, not GetID(): an untouched frame defaults to GetID()
-- 0, which would otherwise be mistaken for the backpack on retail.
--
-- Update: the modern bank's BankFrame (retail, and Classic "Forever" -- see
-- Embolsao:UsesModernBank) is the same story in the one way that matters
-- here: its OnHide calls C_Bank.CloseBankFrame() (Blizzard's
-- BankFrameBaseMixin), so it too must never be hidden, only moved away --
-- and it too must never be mistaken for the backpack by its default ID of 0.
-- So it's claimed by identity on every flavor.
local function IsBankStorageFrame(bagFrame)
    return _G.BankFrame ~= nil and bagFrame == _G.BankFrame
end

-- Bag 5 is the reagent bag on retail; Classic/TBC have no reagent bag at
-- all, so that same bagID is just the first bank bag slot there instead --
-- REAGENT_BAG_ID and IsBankManagedBagID are mutually exclusive per flavor
-- rather than both claiming "bagID 5 and up" (that collision is exactly
-- what hijacked Classic's first bank bag slot earlier this cycle).
local REAGENT_BAG_ID = (not Embolsao.IsClassic) and 5 or nil

local function IsBagsManagedBagID(bagID)
    if bagID == nil then return false end
    if bagID >= BACKPACK_CONTAINER and bagID <= NUM_BAG_SLOTS then return true end
    if REAGENT_BAG_ID and bagID == REAGENT_BAG_ID then return true end
    -- Retail leaves IsKeyRingEnabled/KEYRING_CONTAINER as stale globals even
    -- though the keyring was removed there -- Embolsao.IsClassic is what
    -- actually tells the two apart.
    if Embolsao.IsClassic and bagID == KEYRING_CONTAINER and IsKeyRingEnabled and IsKeyRingEnabled() then return true end
    return false
end

local function IsBankManagedBagID(bagID)
    if bagID == nil or not Embolsao.db.mergeBankStorage then return false end
    for _, id in ipairs(Embolsao.PersonalBankBagIDs) do
        if bagID == id then return true end
    end
    for _, id in ipairs(Embolsao.WarbandBankBagIDs) do
        if bagID == id then return true end
    end
    return false
end

bagsWindow = CreateWindow({
    id = "Bags",
    domain = "bags", -- which set of tabs this pane uses (Embolsao:GetFilters)
    paneLabel = function() return L.PANE_BAGS end,
    hasFooter = true,
    hasBankModeToggle = false,
    applyDefaultTab = true,
    -- Opening the bags while standing at a banker also brings the bank part
    -- back if it was closed on its own (its X) -- the way to reopen it
    -- without walking away and back.
    OnShown = function()
        if Embolsao.AtBank and Embolsao.db.mergeBankStorage
            and _G.BankFrame and _G.BankFrame:IsShown() and not bankWindow.IsShown() then
            bankWindow.HandleNativeShow(_G.BankFrame)
        end
    end,
    GetInventory = function() return Embolsao.VirtualInventory end,
    GetEmptySlotGroups = function() return Embolsao.EmptySlotGroups end,
    GetActiveTab = function() return Embolsao.db.activeTab end,
    SetActiveTab = function(id) Embolsao.db.activeTab = id end,
    Rescan = function() Embolsao:ScanBags() end,
    IsManagedFrame = function(bagFrame)
        if IsCombinedBagsFrame(bagFrame) then return true end
        -- The bank frame's default ID is 0 -- the backpack's -- which made
        -- this window claim (and hide) it instead of the bank window.
        if IsBankStorageFrame(bagFrame) then return false end
        return IsBagsManagedBagID(bagFrame and bagFrame:GetID())
    end,
})

-- With Preferences -> "Separate tabs for Bank and Bags" on, the bank's
-- selected tab is remembered like the bags' (Embolsao.db.bankActiveTab);
-- sharing the bags' tabs, it isn't persisted and just starts on "All".
local bankActiveTab = "ALL"

bankWindow = CreateWindow({
    id = "Bank",
    domain = "bank",
    paneLabel = function() return L.PANE_BANK end,
    -- Can be closed on its own with the X on its pane, leaving the bags.
    closablePane = true,
    -- The bank has no XP line, but its footer has a better use: buying more
    -- bank space (see UpdateBankFooter) next to the player's money.
    hasFooter = true,
    hasBankPurchase = true,
    hasBankModeToggle = true,
    applyDefaultTab = false,
    -- See the comment on ScanAndSuppress in HandleNativeShow -- the bank's
    -- own item data needs Blizzard's native frame left alone for a moment
    -- before it's actually queryable.
    rescanDelay = 0.5,
    GetInventory = function() return Embolsao.BankVirtualInventory end,
    GetEmptySlotGroups = function() return Embolsao.BankEmptySlotGroups end,
    GetActiveTab = function()
        if Embolsao.db.separateBankTabs then return Embolsao.db.bankActiveTab end
        return bankActiveTab
    end,
    SetActiveTab = function(id)
        if Embolsao.db.separateBankTabs then
            Embolsao.db.bankActiveTab = id
        else
            bankActiveTab = id
        end
    end,
    Rescan = function() Embolsao:ScanBank() end,
    IsManagedFrame = function(bagFrame)
        if not Embolsao.db.mergeBankStorage then return false end
        -- By identity, never the GetID()-based check below: an untouched
        -- frame's ID is 0, which is the backpack.
        if IsBankStorageFrame(bagFrame) then return true end
        return IsBankManagedBagID(bagFrame and bagFrame:GetID())
    end,
})

pawnWindows[1], pawnWindows[2] = bagsWindow, bankWindow

-- The footer's XP line used to refresh only when the window opened; keep it
-- current while it's up (XP gained, rested XP changing, a level-up). Not every
-- flavor has every one of these events, so registration mustn't be fatal.
local xpEventFrame = CreateFrame("Frame")
for _, xpEvent in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP" }) do
    pcall(xpEventFrame.RegisterEvent, xpEventFrame, xpEvent)
end
xpEventFrame:SetScript("OnEvent", function()
    bagsWindow.UpdateFooterXP()
end)

-- Holding or releasing Ctrl/Shift/Alt while the cursor is on one of our item
-- buttons rebuilds its tooltip, so the binding hint for the combo being held
-- lights up (AddBindingHints) -- the tooltip otherwise only builds on entry.
local modifierFrame = CreateFrame("Frame")
modifierFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
modifierFrame:SetScript("OnEvent", function()
    -- Fade out (or restore) the items the action bound to the held modifier
    -- can't act on, in both windows.
    local action = ActionForCurrentClick()
    bagsWindow.ApplyModifierDimming(action)
    bankWindow.ApplyModifierDimming(action)

    if not GameTooltip:IsShown() then return end
    local owner = GameTooltip:GetOwner()
    if owner and owner.isEmbolsaoItemButton then
        local onEnter = owner:GetScript("OnEnter")
        if onEnter then onEnter(owner) end
    end
end)

-- The bank footer's purchase button follows what's affordable and what's left
-- to buy: after a purchase (a new tab / bag slot appears), and as money
-- changes. Nothing to do away from a banker. The event names differ by bank
-- (Classic: PLAYERBANKBAGSLOTS_CHANGED; modern: BANK_TABS_CHANGED), and an
-- unknown one must not be fatal.
local bankPurchaseEventFrame = CreateFrame("Frame")
for _, purchaseEvent in ipairs({ "PLAYER_MONEY", "BANK_TABS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED" }) do
    pcall(bankPurchaseEventFrame.RegisterEvent, bankPurchaseEventFrame, purchaseEvent)
end
bankPurchaseEventFrame:SetScript("OnEvent", function()
    if not Embolsao.AtBank then return end
    Embolsao:ScanBank()
    bankWindow.Refresh()
    bankWindow.UpdateBankModeToggle()
end)

local function GetOwningWindow(bagFrame)
    if bagsWindow.IsManagedFrame(bagFrame) then return bagsWindow end
    if bankWindow.IsManagedFrame(bagFrame) then return bankWindow end
    return nil
end

-- We take over display duty for bags/bank entirely: the owning window
-- shows, the native frame(s) it manages get hidden (not just dimmed). The
-- suppressingNativeHide flag matters because HIDING the native frame
-- ourselves fires its own OnHide script (hooked below too) -- without it,
-- that would immediately hide our just-opened window right back.
-- Defined further down (they need RestoreBankFrameAppearance and the bank
-- window). The BankFrame's own show/hide is the one bank signal that exists on
-- every flavor: the modern bank may never fire BANKFRAME_OPENED/CLOSED
-- (Blizzard opens it through BankFrame_Open() now), so the state can't hang
-- on those events alone.
local HandleBankOpened, HandleBankClosed

local function OnBagFrameShow(self)
    if self == _G.BankFrame then HandleBankOpened() end
    local win = GetOwningWindow(self)
    if win then win.HandleNativeShow(self) end
end

local function OnBagFrameHide(self)
    if suppressingNativeHide then return end
    if self == _G.BankFrame then HandleBankClosed() end
    local win = GetOwningWindow(self)
    if win then win.HandleNativeHide(self) end
end

local function IsAnyNativeBagFrameShown()
    for _, bagFrame in ipairs(nativeBagFrames) do
        if bagFrame:IsShown() then
            return true
        end
    end
    return false
end

-- Undoes the off-screen trick from win.SuppressNativeFrames above -- called
-- whenever BankFrame should go back to behaving completely normally: on
-- leaving the bank (so the next visit starts from a clean, correctly
-- positioned frame rather than compounding leftover state) and when "Use
-- Embolsao for Bank" gets turned off (UI:RefreshBankAvailability), so
-- native bank display isn't left permanently broken by our own hack.
local function RestoreBankFrameAppearance()
    local bankFrame = _G.BankFrame
    if bankFrame then
        bankFrame:SetClampedToScreen(true)
        bankFrame:EnableMouse(true)
        bankFrame:EnableKeyboard(true)
        bankFrame:SetAlpha(1)
        if bankFrame.embolsaoOldStrata then
            bankFrame:SetFrameStrata(bankFrame.embolsaoOldStrata)
            bankFrame.embolsaoOldStrata = nil
        end
    end
end

-- Visiting a banker shows the bank's native frame(s) -- BankFrame itself on
-- Classic/TBC, individual ContainerFrameN's on retail (already covered by
-- the general hook list). This handler exists for three things the generic
-- OnShow/OnHide dispatch above can't do on its own:
--   1. Classic/TBC's BankFrame doesn't reliably exist yet the one time
--      InstallBagFrameHooks scans for native frames right after
--      login/reload -- confirmed live. Hooking it here too, the first time
--      it's actually needed, doesn't depend on that startup timing at all.
--   2. Resetting BankViewMode back to "PERSONAL" once the bank closes --
--      there's no "Warband Bank" to speak of once you've walked away.
--   3. Undoing the off-screen suppression trick each time the bank closes,
--      so the next visit starts clean.
--   4. On the modern bank, re-reading which bank tabs exist (their bag IDs
--      depend on the flavor and on which tabs this character has bought).
-- Both handlers are safe to run more than once for the same visit -- they're
-- reached from the BankFrame's own OnShow/OnHide hooks AND from the events.
HandleBankOpened = function()
    Embolsao.AtBank = true
    Embolsao:RefreshModernBankBagIDs()
    -- Right-click on a bag item means "deposit" now, not "use" (see
    -- UpdateUseOverlay) -- re-point the overlays.
    UI:Refresh()
end

HandleBankClosed = function()
    Embolsao.AtBank = false
    Embolsao.BankViewMode = "PERSONAL"
    bankWindow.Hide()
    RestoreBankFrameAppearance()
    UI:Refresh()
end

local bankEventFrame = CreateFrame("Frame")
bankEventFrame:RegisterEvent("BANKFRAME_OPENED")
bankEventFrame:RegisterEvent("BANKFRAME_CLOSED")
bankEventFrame:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_CLOSED" then
        HandleBankClosed()
        return
    end

    HandleBankOpened()

    local justHooked = false
    if _G.BankFrame and not tContains(nativeBagFrames, _G.BankFrame) then
        table.insert(nativeBagFrames, _G.BankFrame)
        _G.BankFrame:HookScript("OnShow", OnBagFrameShow)
        _G.BankFrame:HookScript("OnHide", OnBagFrameHide)
        justHooked = true
    end

    -- BankFrame is already shown by the time this event fires -- the hook
    -- just added above only fires on the NEXT show, so this one has to be
    -- driven by hand right now instead of waiting for that. Classic/TBC does
    -- it on every visit (long-standing behavior there); the modern bank has
    -- its OnShow hook installed with the other native frames, so only the
    -- first-ever, just-hooked case needs it.
    if _G.BankFrame and _G.BankFrame:IsShown() and (justHooked or not Embolsao:UsesModernBank()) then
        OnBagFrameShow(_G.BankFrame)
    end
end)

function UI:ShowPreferences()
    ShowPreferencesFrame()
end

-- Bags-window peek: right-click on a special bag's empty-slot button, or
-- the minimap menu's "Open Default Bags". The bank window has its own
-- OpenNativeBags for its own empty-slot buttons (win.OpenNativeBags,
-- called directly there, never through here).
function UI:OpenNativeBags(bagID)
    bagsWindow.OpenNativeBags(bagID)
end

-- Minimap button's "Disable Embolsao" toggle: leaves native bags/bank alone
-- entirely from here on -- OnBagFrameShow bails immediately instead of
-- taking over, for both windows. Just closes whichever window(s) are
-- currently open on the way through.
function UI:SetDisabled(disabled)
    Embolsao.db.disabled = disabled and true or false

    if disabled then
        bagsWindow.Hide()
        bankWindow.Hide()
    elseif IsAnyNativeBagFrameShown() then
        for _, bagFrame in ipairs(nativeBagFrames) do
            bagFrame:Hide()
        end
    end
end

-- Preferences -> "Use Embolsao for Bank" toggled off while at the bank:
-- hide our bank window and let native take back over from here. Toggled
-- on: nothing to do until the next bank interaction naturally re-triggers
-- HandleNativeShow for whatever bank frame shows next.
function UI:RefreshBankAvailability()
    if not Embolsao.db.mergeBankStorage then
        bankWindow.Hide()
        RestoreBankFrameAppearance()
    end
end

function UI:Refresh()
    bagsWindow.Refresh()
    bankWindow.Refresh()
end

function UI:BuildTabs()
    bagsWindow.BuildTabs()
    bankWindow.BuildTabs()
    -- Rebuilding tabs can change what the currently active tab even is
    -- (e.g. it was just deleted) -- Refresh re-derives everything
    -- downstream of that.
    bagsWindow.Refresh()
    bankWindow.Refresh()
end

-- Blizzard's own "is the bag open" tracking thinks bags are closed once we
-- hide the native frame(s) (we only ever hide them, never truly close
-- them), so pressing the bag keybind again just re-runs "open" and does
-- nothing visible. Wrapping the keybind's own functions instead of
-- touching the keybind itself: if the bags window is currently up, close
-- IT and skip calling the real toggle at all; otherwise fall through to
-- Blizzard's original behavior untouched. Bags-only -- there's no keybind
-- for the bank window, it opens/closes only via BANKFRAME_OPENED/CLOSED.
local function WrapBagToggle(original)
    return function(...)
        if bagsWindow.IsShown() then
            bagsWindow.Hide()
            -- It's one window: closing it with the bags key closes the bank
            -- part too (pressing the key again brings both back while still
            -- at the banker -- see the bags pane's OnShown).
            bankWindow.Hide()
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

-- ContainerFrameCombinedBags/ContainerFrame1..6/BankFrame belong to
-- Blizzard_UIPanels_Game, a load-on-demand module that only loads the first
-- time the player opens a bag. It's almost never loaded yet at
-- PLAYER_LOGIN, so we wait for its ADDON_LOADED (and still check at
-- PLAYER_LOGIN in case some other addon forced it earlier).
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
        Embolsao:InitBankBagIDs()
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

-- The secure right-click overlays on item buttons can't be re-pointed while
-- in combat (UpdateUseOverlay skips them), so whatever changed meanwhile is
-- applied by a refresh the moment combat ends.
local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function()
    UI:Refresh()
end)

-- Vendor open/close: drives the Junk group's sell button (enabled look, tooltip)
-- and stops an in-progress sell if the window is closed on us. With
-- Preferences -> "Auto-sell Junk" on, opening a vendor also sells every grey
-- item in the bags right away: straight from the bag scan, not from the
-- Junk group as displayed, so it doesn't depend on the group being shown, on
-- the active tab or on the search box. Same sell routine (and the same chat
-- message) as the button.
local function AutoSellJunk()
    Embolsao:ScanBags()
    local entries = {}
    for _, entry in pairs(Embolsao.VirtualInventory) do
        table.insert(entries, entry)
    end
    SellJunkEntries(entries)
end

local merchantFrame = CreateFrame("Frame")
merchantFrame:RegisterEvent("MERCHANT_SHOW")
merchantFrame:RegisterEvent("MERCHANT_CLOSED")
merchantFrame:SetScript("OnEvent", function(_, event)
    merchantOpen = event == "MERCHANT_SHOW"
    if merchantOpen and Embolsao.db and Embolsao.db.autoSellJunk then
        AutoSellJunk()
    end
    UI:Refresh()
end)
