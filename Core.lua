local ADDON_NAME, Embolsao = ...
_G.Embolsao = Embolsao

Embolsao.VirtualInventory = {}
Embolsao.EmptySlots = {}

local DEFAULT_DB = {
    customTabs = {},
    hiddenTabs = {}, -- set of tab IDs (built-in or custom) hidden from the tab bar
    tabOrder = {}, -- ordered list of tab IDs; anything missing gets appended
    activeTab = "ALL",
    sortMode = "NAME",
    sortAscending = true,
    defaultTab = "LAST", -- "LAST" = reopen on whichever tab was active last
    consolidateStacks = true,
    rememberPosition = true,
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

-- Groups every stack of a given itemID across all bags into a single virtual
-- entry, and separately tracks every genuinely empty slot -- the merged view
-- has no visual "empty square" of its own, so this is what backs the
-- dedicated empty-slot button UI uses as a drop target for new stacks.
-- Reagent bag slots are scanned last so regular bag slots get picked first
-- when placing an arbitrary (non-reagent) item.
--
-- When `consolidate` is off (Preferences -> Consolidate Stacks), each real
-- (bagID, slot) gets its own entry instead of being merged by itemID -- a
-- key of "bagID:slot" instead of itemID keeps every physical stack distinct.
local function ScanBag(bagID, inventory, emptySlots, consolidate)
    local numSlots = C_Container.GetContainerNumSlots(bagID)
    if not numSlots or numSlots == 0 then return end

    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.itemID then
            local itemID = info.itemID
            local key = consolidate and itemID or (bagID .. ":" .. slot)
            local entry = inventory[key]
            if not entry then
                entry = {
                    itemID = itemID,
                    count = 0,
                    icon = info.iconFileID,
                    quality = info.quality,
                    hyperlink = info.hyperlink,
                    locations = {},
                }
                inventory[key] = entry
            end
            entry.count = entry.count + (info.stackCount or 1)
            entry.hyperlink = entry.hyperlink or info.hyperlink
            table.insert(entry.locations, { bagID = bagID, slot = slot })
        else
            table.insert(emptySlots, { bagID = bagID, slot = slot })
        end
    end
end

-- Bag 5 is the reagent bag (Enum.BagIndex.ReagentBag; Blizzard's own
-- ContainerFrame_IsReagentBag hardcodes the same literal). There's no
-- REAGENTBAG_CONTAINER global -- that was a guess that silently never
-- matched anything, so the reagent bag was never actually scanned.
local REAGENT_BAG_ID = 5

function Embolsao:ScanBags()
    local inventory = {}
    local emptySlots = {}
    local consolidate = self.db == nil or self.db.consolidateStacks ~= false
    for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        ScanBag(bagID, inventory, emptySlots, consolidate)
    end
    ScanBag(REAGENT_BAG_ID, inventory, emptySlots, consolidate)
    self.VirtualInventory = inventory
    self.EmptySlots = emptySlots
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
