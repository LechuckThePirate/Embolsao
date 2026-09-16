local ADDON_NAME, Embolsao = ...

Embolsao.UI = {}
local UI = Embolsao.UI

local TAB_ICON_SIZE = 28
local TAB_PADDING = 4

local tabBar
local tabButtons = {}

-- WoW lets the player toggle between the legacy per-bag frames (ContainerFrame1..N)
-- and the single ContainerFrameCombinedBags frame at any time, so we check both and
-- pick whichever is actually on screen rather than assuming combined mode.
local function IsAnyBagFrameShown()
    return (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown())
        or (ContainerFrame1 and ContainerFrame1:IsShown())
end

local function GetActiveBagFrame()
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        return ContainerFrameCombinedBags
    end
    return ContainerFrame1
end

local function CreateTabBar()
    if tabBar then return tabBar end

    tabBar = CreateFrame("Frame", "EmbolsaoTabBar", UIParent)
    tabBar:SetHeight(TAB_ICON_SIZE)
    tabBar:SetFrameStrata("HIGH")
    tabBar:Hide()

    return tabBar
end

local function CreateTabButton(index, tabData)
    local btn = CreateFrame("Button", nil, tabBar)
    btn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
    btn:SetPoint("LEFT", (index - 1) * (TAB_ICON_SIZE + TAB_PADDING), 0)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture(tabData.icon)
    -- Trim the icon's built-in border so square icons tile cleanly in a row.
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
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

function UI:BuildTabs()
    CreateTabBar()
    for _, btn in ipairs(tabButtons) do
        btn:Hide()
    end
    wipe(tabButtons)

    tabBar.currentTabs = Embolsao.Filters:GetAllTabs()
    for index, tabData in ipairs(tabBar.currentTabs) do
        tabButtons[index] = CreateTabButton(index, tabData)
    end

    local tabCount = #tabBar.currentTabs
    tabBar:SetWidth(tabCount * TAB_ICON_SIZE + math.max(tabCount - 1, 0) * TAB_PADDING)
end

function UI:UpdateSelectedTab()
    local activeTab = Embolsao.db.activeTab
    for index, tabData in ipairs(tabBar.currentTabs or {}) do
        local btn = tabButtons[index]
        local isActive = tabData.id == activeTab
        btn.icon:SetDesaturated(not isActive)
        btn.icon:SetAlpha(isActive and 1 or 0.55)
    end
end

function UI:AnchorTabBar()
    local bagFrame = GetActiveBagFrame()
    if not bagFrame then return end
    tabBar:ClearAllPoints()
    tabBar:SetPoint("BOTTOMLEFT", bagFrame, "TOPLEFT", 8, 4)
end

-- The "real" filtering: instead of drawing our own item grid, we dim out
-- non-matching items directly on Blizzard's own bag frame(s), the same way
-- typing in the bag's search box does (itemButton:SetMatchesSearch). Works
-- for both combined-bags and legacy multi-frame layouts via Blizzard's own
-- frame enumerator, so we don't have to special-case either mode here.
function UI:Refresh()
    if not tabBar or not tabBar:IsShown() then return end
    if not tabBar.currentTabs then
        self:BuildTabs()
    end
    self:UpdateSelectedTab()

    if not ContainerFrameUtil_EnumerateContainerFrames then return end

    local activeTab = Embolsao.db.activeTab
    local activeFilter
    for _, tab in ipairs(tabBar.currentTabs) do
        if tab.id == activeTab then
            activeFilter = tab
            break
        end
    end
    activeFilter = activeFilter or tabBar.currentTabs[1]

    for _, containerFrame in ContainerFrameUtil_EnumerateContainerFrames() do
        for _, itemButton in containerFrame:EnumerateValidItems() do
            local bagID, slot = itemButton:GetBagID(), itemButton:GetID()
            local info = bagID and slot and C_Container.GetContainerItemInfo(bagID, slot)
            local matches = true
            if info and info.itemID then
                matches = activeFilter.predicate({ itemID = info.itemID })
            end
            itemButton:SetMatchesSearch(matches)
        end
    end
end

local function OnBagFrameShow()
    CreateTabBar()
    if not tabBar.currentTabs then
        UI:BuildTabs()
    end
    UI:AnchorTabBar()
    tabBar:Show()
    Embolsao:ScanBags()
    UI:Refresh()
end

local function OnBagFrameHide()
    if tabBar and not IsAnyBagFrameShown() then
        tabBar:Hide()
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
