local ADDON_NAME, Embolsao = ...
_G.Embolsao = Embolsao

Embolsao.VirtualInventory = {}

local DEFAULT_DB = {
    ignoredItemIDs = {},
    customTabs = {},
    activeTab = "ALL",
}

local function InitDB()
    EmbolsaoDB = EmbolsaoDB or {}
    for key, defaultValue in pairs(DEFAULT_DB) do
        if EmbolsaoDB[key] == nil then
            EmbolsaoDB[key] = (type(defaultValue) == "table") and {} or defaultValue
        end
    end
    Embolsao.db = EmbolsaoDB
end

function Embolsao:IsItemIgnored(itemID)
    return itemID ~= nil and self.db.ignoredItemIDs[itemID] == true
end

function Embolsao:SetItemIgnored(itemID, ignored)
    if not itemID then return end
    self.db.ignoredItemIDs[itemID] = ignored and true or nil
end

-- Groups every stack of a given itemID across all bags into a single virtual entry.
local function ScanBag(bagID, inventory)
    local numSlots = C_Container.GetContainerNumSlots(bagID)
    if not numSlots or numSlots == 0 then return end

    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.itemID then
            local itemID = info.itemID
            local entry = inventory[itemID]
            if not entry then
                entry = {
                    itemID = itemID,
                    count = 0,
                    icon = info.iconFileID,
                    quality = info.quality,
                    hyperlink = info.hyperlink,
                    locations = {},
                }
                inventory[itemID] = entry
            end
            entry.count = entry.count + (info.stackCount or 1)
            entry.hyperlink = entry.hyperlink or info.hyperlink
            table.insert(entry.locations, { bagID = bagID, slot = slot })
        end
    end
end

function Embolsao:ScanBags()
    local inventory = {}
    for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        ScanBag(bagID, inventory)
    end
    if REAGENTBAG_CONTAINER then
        ScanBag(REAGENTBAG_CONTAINER, inventory)
    end
    self.VirtualInventory = inventory
    return inventory
end

local function RefreshUI()
    if Embolsao.UI and Embolsao.UI.Refresh then
        Embolsao.UI:Refresh()
    end
end

local eventFrame = CreateFrame("Frame", "EmbolsaoEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            InitDB()
            Embolsao:ScanBags()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        Embolsao:ScanBags()
        RefreshUI()
    end
end)
