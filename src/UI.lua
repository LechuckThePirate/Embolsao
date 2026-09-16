local ADDON_NAME, Embolsao = ...

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
local PORTRAIT_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icons\\embolsao-icon.png"

-- All the native frames we take over display duty from. Combined bags is one
-- frame; legacy (non-combined) mode can have the backpack plus up to 5 more
-- bag frames open side by side, so we cover the full set either way.
local NATIVE_BAG_FRAME_NAMES = {
    "ContainerFrameCombinedBags",
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
}

local frame
local tabButtons = {}
local itemButtons = {}

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

-- Callback StackSplitFrame invokes as button:SplitStack(amount) once the
-- player confirms a split quantity in its popup.
local function SplitItemStack(button, split)
    C_Container.SplitContainerItem(button:GetBagID(), button:GetID(), split)
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

    local results = {}
    for _, entry in pairs(Embolsao.VirtualInventory) do
        if activeFilter.predicate(entry) then
            table.insert(results, entry)
        end
    end
    table.sort(results, function(a, b) return a.itemID < b.itemID end)
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
