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
local ITEMS_PER_ROW = 8
local CONTENT_TOP_OFFSET = 70
local TOOLBAR_Y = -34 -- search box / menu button row, a bit above the item grid
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

-- Reuses Blizzard's own "PortraitFrameFlatTemplate" (the same base every
-- portrait-style dialog in the game uses, bags included) so our window gets
-- the native background/border/portrait/close-button for free instead of a
-- hand-rolled backdrop.
local function CreateMainFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "EmbolsaoFrame", UIParent, "PortraitFrameFlatTemplate")
    frame:SetSize(
        TAB_ICON_SIZE + TAB_PANEL_PADDING * 2 + TAB_TO_ITEMS_GAP + ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING) + 20,
        420
    )
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
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
    frame.tabPanel:SetWidth(TAB_ICON_SIZE + TAB_PANEL_PADDING * 2)
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

    -- Anchor both opposite corners (not just SetPoint+SetWidth) so this frame
    -- always has a fully resolved rect -- a single-anchor frame with no
    -- explicit height left its height undefined, which was enough to make
    -- every child button inside it fail to resolve a screen position at all
    -- (GetLeft/GetTop/etc all nil) despite reporting IsShown()/IsVisible() as
    -- true. Confirmed by direct in-game inspection.
    frame.tabColumn = CreateFrame("Frame", nil, frame.tabPanel)
    frame.tabColumn:SetPoint("TOPLEFT", TAB_PANEL_PADDING, -TAB_PANEL_PADDING)
    frame.tabColumn:SetPoint("BOTTOMRIGHT", -TAB_PANEL_PADDING, TAB_PANEL_PADDING)

    -- Item grid, well clear of the tab panel, using real ItemButton widgets
    -- so icons/borders/counts render exactly like Blizzard's own bag slots.
    frame.itemContainer = CreateFrame("Frame", nil, frame)
    frame.itemContainer:SetPoint("TOPLEFT", frame.tabPanel, "TOPRIGHT", TAB_TO_ITEMS_GAP, 0)
    frame.itemContainer:SetPoint("BOTTOMRIGHT", -10, 10)

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

    btn:SetScript("OnClick", function()
        Embolsao.db.activeTab = tabData.id
        UI:Refresh()
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

    rootDescription:CreateButton(L.PREFERENCES, function()
        print("|cffffd200Embolsao:|r " .. L.PREFERENCES_COMING_SOON)
    end)

    rootDescription:CreateButton(L.ABOUT, ShowAboutFrame)
end

function CreateMenuButton()
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(24, 24)
    btn:SetPoint("TOPRIGHT", -16, TOOLBAR_Y)

    -- The exact arrow atlas Blizzard's own WowStyle2DropdownTemplate uses
    -- for its chevron (confirmed in MenuTemplates.xml) -- a Unicode triangle
    -- glyph turned out invisible, the default UI fonts don't cover it.
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("CENTER")
    btn.icon:SetAtlas("common-dropdown-c-button-hover-arrow", true)

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
local function GetOrCreateItemButton(index)
    local btn = itemButtons[index]
    if btn then return btn end

    btn = CreateFrame("ItemButton", nil, frame.itemContainer)
    local col = (index - 1) % ITEMS_PER_ROW
    local row = math.floor((index - 1) / ITEMS_PER_ROW)
    btn:SetPoint("TOPLEFT", col * (ITEM_SIZE + ITEM_PADDING), -row * (ITEM_SIZE + ITEM_PADDING))

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

function UI:BuildTabs()
    for _, btn in ipairs(tabButtons) do
        btn:Hide()
    end
    wipe(tabButtons)

    frame.currentTabs = Embolsao.Filters:GetAllTabs()
    for index, tabData in ipairs(frame.currentTabs) do
        tabButtons[index] = CreateTabButton(index, tabData)
    end
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
        local _, _, _, _, _, classA, subA = GetItemInfoInstant(a.itemID)
        local _, _, _, _, _, classB, subB = GetItemInfoInstant(b.itemID)
        classA, classB = classA or 0, classB or 0
        if classA ~= classB then
            return classA < classB and -1 or 1
        end
        subA, subB = subA or 0, subB or 0
        if subA ~= subB then
            return subA < subB and -1 or 1
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

function UI:Refresh()
    if not frame or not frame:IsShown() then return end
    if not frame.currentTabs then
        self:BuildTabs()
    end
    self:UpdateSelectedTab()

    local entries = self:GetFilteredEntries()
    for index, entry in ipairs(entries) do
        local btn = GetOrCreateItemButton(index)
        btn.itemID = entry.itemID
        local location = entry.locations and entry.locations[1]
        btn:SetBagID(location and location.bagID)
        btn:SetID(location and location.slot or 0)
        SetItemButtonTexture(btn, entry.icon)
        SetItemButtonCount(btn, entry.count)
        SetItemButtonQuality(btn, entry.quality, entry.itemID)
        btn:Show()
    end

    for index = #entries + 1, #itemButtons do
        itemButtons[index].itemID = nil
        itemButtons[index]:Hide()
    end

    -- Empty-slot button always comes right after the last real item, on
    -- every tab, regardless of what's filtered -- it's not tied to the
    -- active category, it's just "the place to drop new stacks".
    local slotButton = frame.emptySlotButton
    local col = #entries % ITEMS_PER_ROW
    local row = math.floor(#entries / ITEMS_PER_ROW)
    slotButton:ClearAllPoints()
    slotButton:SetPoint("TOPLEFT", col * (ITEM_SIZE + ITEM_PADDING), -row * (ITEM_SIZE + ITEM_PADDING))
    slotButton.Count:SetText(tostring(#Embolsao.EmptySlots))
    slotButton.Count:Show()
    slotButton:Show()
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
