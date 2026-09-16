local ADDON_NAME, Embolsao = ...

Embolsao.UI = {}
local UI = Embolsao.UI

local TAB_ICON_SIZE = 32
local TAB_PADDING = 6
local ITEM_SIZE = 37
local ITEM_PADDING = 4
local ITEMS_PER_ROW = 8
local LEFT_COLUMN_WIDTH = TAB_ICON_SIZE + 16
local CONTENT_TOP_OFFSET = 70
local PORTRAIT_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icons\\embolsao-icon.png"

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
    frame:SetSize(LEFT_COLUMN_WIDTH + ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING) + 24, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame:SetPortraitToAsset(PORTRAIT_ICON)
    if frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText("Embolsao!!")
    elseif frame.TitleText then
        frame.TitleText:SetText("Embolsao!!")
    end

    -- Vertical filter tabs down the left edge.
    frame.tabColumn = CreateFrame("Frame", nil, frame)
    frame.tabColumn:SetPoint("TOPLEFT", 10, -CONTENT_TOP_OFFSET)
    frame.tabColumn:SetPoint("BOTTOMLEFT", 10, 10)
    frame.tabColumn:SetWidth(TAB_ICON_SIZE)

    -- Item grid to the right of the tabs, using real ItemButton widgets so
    -- icons/borders/counts render exactly like Blizzard's own bag slots.
    frame.itemContainer = CreateFrame("Frame", nil, frame)
    frame.itemContainer:SetPoint("TOPLEFT", frame.tabColumn, "TOPRIGHT", 10, 0)
    frame.itemContainer:SetPoint("BOTTOMRIGHT", -10, 10)

    return frame
end

local function CreateTabButton(index, tabData)
    local btn = CreateFrame("Button", nil, frame.tabColumn)
    btn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
    btn:SetPoint("TOP", 0, -(index - 1) * (TAB_ICON_SIZE + TAB_PADDING))

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

-- Bare "ItemButton" is Blizzard's own intrinsic widget type (icon + count +
-- quality border), the same one every item slot in the game is built from.
-- We don't pull in ContainerFrameItemButtonTemplate itself, since that one
-- hard-requires a real container-frame parent (it calls things like
-- self:GetParent():IsCombinedBagContainer()) -- not something we want to
-- fake just to show a merged/virtual stack that isn't one real bag slot.
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

    -- Right-click toggles the item in/out of the shared ignored-item list.
    -- On its own this does nothing visible; a custom tab must opt in via
    -- `useIgnoredList = true` for it to actually exclude anything.
    btn:RegisterForClicks("RightButtonUp")
    btn:SetScript("OnClick", function(self)
        if not self.itemID then return end
        Embolsao:SetItemIgnored(self.itemID, not Embolsao:IsItemIgnored(self.itemID))
        UI:Refresh()
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

-- WoW lets the player toggle between the legacy per-bag frames (ContainerFrame1..N)
-- and the single ContainerFrameCombinedBags frame at any time, so we hook both and
-- pick whichever is actually on screen rather than assuming combined mode.
local function IsAnyBagFrameShown()
    return (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown())
        or (ContainerFrame1 and ContainerFrame1:IsShown())
end

local function OnBagFrameShow()
    CreateMainFrame()
    if not frame.currentTabs then
        UI:BuildTabs()
    end
    frame:Show()
    Embolsao:ScanBags()
    UI:Refresh()
end

local function OnBagFrameHide()
    if frame and not IsAnyBagFrameShown() then
        frame:Hide()
    end
end

-- ContainerFrameCombinedBags/ContainerFrame1 belong to Blizzard_ContainerFrame, a
-- load-on-demand module that only loads the first time the player opens a bag.
-- It's almost never loaded yet at PLAYER_LOGIN, so we wait for its ADDON_LOADED
-- (and still check at PLAYER_LOGIN in case some other addon forced it earlier).
local hooksInstalled = false
local function InstallBagFrameHooks()
    if hooksInstalled then return end
    if not (ContainerFrameCombinedBags or ContainerFrame1) then return end
    hooksInstalled = true

    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", OnBagFrameShow)
        ContainerFrameCombinedBags:HookScript("OnHide", OnBagFrameHide)
    end
    if ContainerFrame1 then
        ContainerFrame1:HookScript("OnShow", OnBagFrameShow)
        ContainerFrame1:HookScript("OnHide", OnBagFrameHide)
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
