local ADDON_NAME, Embolsao = ...
_G.Embolsao = Embolsao

Embolsao.VirtualInventory = {}
Embolsao.EmptySlots = {}
Embolsao.EmptySlotGroups = {}

-- Tab/filter customization (custom tabs, hidden items, category rules, tab
-- order) is shared across characters by default, same as Blizzard's own
-- Account Keybindings -- with a Preferences toggle ("Character Specific
-- Customization") a player can flip per-character to make that one
-- character keep its own independent copy instead, exactly like ticking
-- "Character Specific Keybindings" in Key Bindings.
local PER_CHARACTER_KEYS = {
    customTabs = true,
    hiddenTabs = true, -- set of tab IDs (built-in or custom) hidden from the tab bar
    tabOrder = true, -- ordered list of tab IDs; anything missing gets appended
    builtInOverrides = true, -- per-built-in-tab {hiddenItemIDs, categoryRules} overlay
    activeTab = true,
    collapsedHeadersGlobal = true, -- [headerKey] = true, used when syncCategoryVisibility is on
    collapsedHeaders = true, -- [tabID] = { [headerKey] = true }, used when syncCategoryVisibility is off
}

local DEFAULT_DB = {
    customTabs = {},
    hiddenTabs = {},
    tabOrder = {},
    builtInOverrides = {},
    activeTab = "ALL",
    sortMode = "NAME",
    sortAscending = true,
    defaultTab = "LAST", -- "LAST" = reopen on whichever tab was active last
    consolidateStacks = true,
    rememberPosition = true,
    groupByClass = true, -- Sort By Type: show a class header before each group
    groupBySubClass = false, -- ...and a nested subclass header too
    syncCategoryVisibility = true, -- one shared collapse state for every tab, instead of one per tab
    collapsedHeadersGlobal = {},
    collapsedHeaders = {},
    disabled = false, -- minimap button toggle: leaves native bags alone entirely
    minimapAngle = 225, -- position around the minimap ring, in degrees
    showMinimapButton = true,
    betaNoticeDismissedVersion = "", -- version the "Don't show this message again" checkbox was ticked for; resets (shows again) on every new version
}

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

-- Embolsao.db reads/writes as one flat table everywhere else in the addon,
-- but for the PER_CHARACTER_KEYS it's actually a thin proxy in front of
-- whichever of two real stores this character is currently using: this
-- metatable (and EmbolsaoCharDB.useCharacterSpecific) is the only place
-- that needs to know which one that is.
local function InitDB()
    EmbolsaoDB = EmbolsaoDB or {}
    EmbolsaoDB.sharedCharData = EmbolsaoDB.sharedCharData or {}
    EmbolsaoCharDB = EmbolsaoCharDB or {}

    -- One-time migration, covering two earlier layouts: the very first
    -- releases kept everything directly on the account-wide EmbolsaoDB;
    -- a later one moved it unconditionally onto the per-character
    -- EmbolsaoCharDB. Either way, promote whatever's already there into the
    -- new shared bucket the first time this runs, since sharing is the
    -- default -- guarded by a flag so it never fires again and clobbers a
    -- real, intentional character-specific divergence made after today.
    if not EmbolsaoDB.sharedCharDataMigrated then
        for key in pairs(PER_CHARACTER_KEYS) do
            if EmbolsaoDB[key] ~= nil then
                EmbolsaoDB.sharedCharData[key] = EmbolsaoDB[key]
                EmbolsaoDB[key] = nil
            elseif EmbolsaoCharDB[key] ~= nil then
                EmbolsaoDB.sharedCharData[key] = DeepCopy(EmbolsaoCharDB[key])
            end
        end
        EmbolsaoDB.sharedCharDataMigrated = true
    end

    if EmbolsaoCharDB.useCharacterSpecific == nil then
        EmbolsaoCharDB.useCharacterSpecific = false
    end

    for key, defaultValue in pairs(DEFAULT_DB) do
        if PER_CHARACTER_KEYS[key] then
            if EmbolsaoDB.sharedCharData[key] == nil then
                EmbolsaoDB.sharedCharData[key] = (type(defaultValue) == "table") and {} or defaultValue
            end
            if EmbolsaoCharDB[key] == nil then
                EmbolsaoCharDB[key] = (type(defaultValue) == "table") and {} or defaultValue
            end
        elseif EmbolsaoDB[key] == nil then
            EmbolsaoDB[key] = (type(defaultValue) == "table") and {} or defaultValue
        end
    end

    local function ActiveCharStore()
        return EmbolsaoCharDB.useCharacterSpecific and EmbolsaoCharDB or EmbolsaoDB.sharedCharData
    end

    Embolsao.db = setmetatable({}, {
        __index = function(_, key)
            if PER_CHARACTER_KEYS[key] then
                return ActiveCharStore()[key]
            end
            return EmbolsaoDB[key]
        end,
        __newindex = function(_, key, value)
            if PER_CHARACTER_KEYS[key] then
                ActiveCharStore()[key] = value
            else
                EmbolsaoDB[key] = value
            end
        end,
    })
end

-- Preferences -> "Character Specific Customization". Turning it ON snapshots
-- whatever this character currently sees (the shared data) into its own
-- copy so the switch is seamless, then starts reading/writing there instead.
-- Turning it back OFF just points back at the shared data -- the
-- character-specific copy is left in EmbolsaoCharDB untouched, in case the
-- player flips it on again later.
function Embolsao:SetUseCharacterSpecificData(enabled)
    enabled = enabled and true or false
    if enabled == EmbolsaoCharDB.useCharacterSpecific then return end

    if enabled then
        for key in pairs(PER_CHARACTER_KEYS) do
            EmbolsaoCharDB[key] = DeepCopy(EmbolsaoDB.sharedCharData[key])
        end
    end

    EmbolsaoCharDB.useCharacterSpecific = enabled
end

-- The keyring (Classic/TBC only) is a special-cased pseudo-container even in
-- Blizzard's own code -- C_Container.GetContainerNumSlots(KEYRING_CONTAINER)
-- always reports 0, silently. Their own ContainerFrame code checks for it
-- explicitly and calls GetKeyRingSize() instead (confirmed in Blizzard's own
-- Classic/ContainerFrame_Shared.lua); C_Container.GetContainerItemInfo and
-- PickupContainerItem work completely normally on it once you know the real
-- size, so this is the only thing that actually needs special-casing.
local function GetBagNumSlots(bagID)
    -- Embolsao.IsClassic matters here too: KEYRING_CONTAINER on retail is a
    -- stale leftover value that happens to collide with a real bagID there
    -- (the reagent bag), and GetKeyRingSize() still responds with garbage
    -- instead of nil/0 -- without this guard the reagent bag was reporting
    -- a bogus 100+ slot count (its actual symptom: a wall of phantom empty
    -- slots rendered under a key icon).
    if Embolsao.IsClassic and bagID == KEYRING_CONTAINER and GetKeyRingSize then
        return GetKeyRingSize()
    end
    return C_Container.GetContainerNumSlots(bagID)
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
    if not bagID then return end
    local numSlots = GetBagNumSlots(bagID)
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

-- Bag 5 is the reagent bag on retail (Enum.BagIndex.ReagentBag; Blizzard's
-- own ContainerFrame_IsReagentBag hardcodes the same literal). There's no
-- REAGENTBAG_CONTAINER global -- that was a guess that silently never
-- matched anything, so the reagent bag was never actually scanned.
--
-- Classic/TBC have no reagent bag at all -- that expansion feature doesn't
-- exist there -- so bag 5 is just the next container ID in line, which
-- means it's the FIRST BANK BAG SLOT the moment the player is at a banker.
-- Treating it as "the reagent bag" there silently hijacked that bank bag's
-- own contents into the merged view. Embolsao.IsClassic (Compat.lua) is
-- what actually distinguishes the two, not the bagID itself.
local REAGENT_BAG_ID = (not Embolsao.IsClassic) and 5 or nil

-- A bag counts as "special" if C_Container.GetContainerNumFreeSlots reports
-- a nonzero bagFamily (the reagent bag, profession-specific bags like a Herb
-- Bag or Soul Bag, etc.) -- it gets its own empty-slot counter in the UI
-- instead of being lumped into the shared "general" one the backpack and
-- every plain, unrestricted bag use. The keyring is unconditionally special
-- -- it's not a "bag" GetContainerNumFreeSlots has any real opinion about.
local function IsSpecialBag(bagID)
    -- The reagent bag's own bagFamily (from GetContainerNumFreeSlots below)
    -- reads 0 on retail -- that flag describes what a bag ACCEPTS, not
    -- what it IS, and the reagent bag apparently doesn't set one for
    -- itself -- so it needs an explicit bagID check instead.
    if REAGENT_BAG_ID and bagID == REAGENT_BAG_ID then return true end
    -- Same stale-global collision as GetBagNumSlots above: on retail,
    -- KEYRING_CONTAINER is left over and can match a real bagID (the
    -- reagent bag, hence the check above has to come first), so this
    -- check must be Classic-only too.
    if Embolsao.IsClassic and bagID == KEYRING_CONTAINER then return true end
    local _, bagFamily = C_Container.GetContainerNumFreeSlots(bagID)
    return bagFamily ~= nil and bagFamily ~= 0
end

-- One group per special bag currently equipped -- even a completely full
-- one, so its counter reads 0 instead of just disappearing -- plus one
-- shared "general" group (always first) for the backpack and any plain bag.
local function BuildEmptySlotGroups(emptySlots)
    local slotsByBag = {}
    for _, slotInfo in ipairs(emptySlots) do
        local list = slotsByBag[slotInfo.bagID]
        if not list then
            list = {}
            slotsByBag[slotInfo.bagID] = list
        end
        table.insert(list, slotInfo)
    end

    local generalSlots = {}
    local generalBagIDs = {}
    local groups = {}

    local function AddBag(bagID)
        if not bagID or (GetBagNumSlots(bagID) or 0) == 0 then return end
        if IsSpecialBag(bagID) then
            table.insert(groups, { id = "bag:" .. bagID, bagID = bagID, slots = slotsByBag[bagID] or {} })
        else
            table.insert(generalBagIDs, bagID)
            for _, slotInfo in ipairs(slotsByBag[bagID] or {}) do
                table.insert(generalSlots, slotInfo)
            end
        end
    end

    for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        AddBag(bagID)
    end
    AddBag(REAGENT_BAG_ID)
    -- Retail still has IsKeyRingEnabled/KEYRING_CONTAINER/GetKeyRingSize as
    -- leftover globals even though the feature was removed there -- and
    -- GetKeyRingSize() on retail doesn't return 0, it returns some other
    -- stale value (100+ "free slots" for a bag that doesn't exist). Classic
    -- is the only flavor that actually has a keyring, so gate on that
    -- first, not just on whether the old API happens to still respond.
    if Embolsao.IsClassic and IsKeyRingEnabled and IsKeyRingEnabled() then
        AddBag(KEYRING_CONTAINER)
    end

    -- bagIDs (every plain bag, even a full one) lets the "general" button's
    -- right-click open exactly those bags -- not ToggleAllBags(), which
    -- would also pop open every special bag that already has its own
    -- dedicated button/group.
    table.insert(groups, 1, { id = "general", slots = generalSlots, bagIDs = generalBagIDs })
    return groups
end

function Embolsao:ScanBags()
    local inventory = {}
    local emptySlots = {}
    local consolidate = self.db == nil or self.db.consolidateStacks ~= false
    for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        ScanBag(bagID, inventory, emptySlots, consolidate)
    end
    ScanBag(REAGENT_BAG_ID, inventory, emptySlots, consolidate)
    -- Classic-family clients only -- see the matching guard in
    -- BuildEmptySlotGroups for why Embolsao.IsClassic has to be checked
    -- too, not just IsKeyRingEnabled().
    if Embolsao.IsClassic and IsKeyRingEnabled and IsKeyRingEnabled() then
        ScanBag(KEYRING_CONTAINER, inventory, emptySlots, consolidate)
    end
    self.VirtualInventory = inventory
    self.EmptySlots = emptySlots
    self.EmptySlotGroups = BuildEmptySlotGroups(emptySlots)
    return inventory
end

local function RefreshUI()
    if Embolsao.UI and Embolsao.UI.Refresh then
        Embolsao.UI:Refresh()
    end
end

local eventFrame = CreateFrame("Frame", "EmbolsaoEventFrame")
local hasCheckedBetaNotice = false

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- PLAYER_LOGIN only fires on a real login, not on /reload -- this
        -- fires on both, but also on every subsequent zone/loading screen,
        -- so it's gated to run just once per UI load with its own local
        -- flag (not persisted -- a fresh UI load should always re-check).
        -- UI.lua itself decides whether the current version has already
        -- been dismissed.
        if not hasCheckedBetaNotice then
            hasCheckedBetaNotice = true
            if Embolsao.UI and Embolsao.UI.ShowBetaNotice then
                Embolsao.UI:ShowBetaNotice(true)
            end
        end
    end
end)
