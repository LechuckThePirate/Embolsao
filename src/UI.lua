local ADDON_NAME, Embolsao = ...

Embolsao.UI = {}
local UI = Embolsao.UI

local ICON_SIZE = 32
local ICON_PADDING = 4
local ICONS_PER_ROW = 8
local TAB_WIDTH = 84

local frame

local function CreateMainFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "EmbolsaoFrame", UIParent, "BackdropTemplate")
    frame:SetSize(ICONS_PER_ROW * (ICON_SIZE + ICON_PADDING) + ICON_PADDING, 400)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -8)
    frame.title:SetText("Embolsao!!")

    frame.tabContainer = CreateFrame("Frame", nil, frame)
    frame.tabContainer:SetPoint("TOPLEFT", 8, -28)
    frame.tabContainer:SetPoint("TOPRIGHT", -8, -28)
    frame.tabContainer:SetHeight(22)
    frame.tabs = {}

    frame.itemContainer = CreateFrame("Frame", nil, frame)
    frame.itemContainer:SetPoint("TOPLEFT", 8, -56)
    frame.itemContainer:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.itemButtons = {}

    return frame
end

local function CreateTabButton(index, tabData)
    local btn = CreateFrame("Button", nil, frame.tabContainer, "UIPanelButtonTemplate")
    btn:SetSize(TAB_WIDTH - 4, 22)
    btn:SetText(tabData.name)
    btn:SetPoint("LEFT", (index - 1) * TAB_WIDTH, 0)
    btn:SetScript("OnClick", function()
        Embolsao.db.activeTab = tabData.id
        UI:Refresh()
    end)
    return btn
end

local function GetOrCreateItemButton(index)
    local btn = frame.itemButtons[index]
    if btn then return btn end

    btn = CreateFrame("Button", nil, frame.itemContainer)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    local col = (index - 1) % ICONS_PER_ROW
    local row = math.floor((index - 1) / ICONS_PER_ROW)
    btn:SetPoint("TOPLEFT", col * (ICON_SIZE + ICON_PADDING), -row * (ICON_SIZE + ICON_PADDING))

    btn.icon = btn:CreateTexture(nil, "BACKGROUND")
    btn.icon:SetAllPoints()

    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.count:SetPoint("BOTTOMRIGHT", -2, 2)

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

    frame.itemButtons[index] = btn
    return btn
end

function UI:BuildTabs()
    for _, btn in ipairs(frame.tabs) do
        btn:Hide()
    end
    wipe(frame.tabs)

    frame.currentTabs = Embolsao.Filters:GetAllTabs()
    for index, tabData in ipairs(frame.currentTabs) do
        frame.tabs[index] = CreateTabButton(index, tabData)
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

    local entries = self:GetFilteredEntries()
    for index, entry in ipairs(entries) do
        local btn = GetOrCreateItemButton(index)
        btn.itemID = entry.itemID
        btn.icon:SetTexture(entry.icon)
        btn.count:SetText(entry.count > 1 and entry.count or "")
        btn:Show()
    end

    for index = #entries + 1, #frame.itemButtons do
        frame.itemButtons[index].itemID = nil
        frame.itemButtons[index]:Hide()
    end
end

-- WoW lets the player toggle between the legacy per-bag frames (ContainerFrame1..N)
-- and the single ContainerFrameCombinedBags frame at any time, so we hook both and
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

local function AnchorToActiveBagFrame()
    local bagFrame = GetActiveBagFrame()
    if not bagFrame then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", bagFrame, "TOPRIGHT", 8, 0)
end

local function OnBagFrameShow()
    CreateMainFrame()
    if not frame.currentTabs then
        UI:BuildTabs()
    end
    AnchorToActiveBagFrame()
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
