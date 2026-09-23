local ADDON_NAME, Embolsao = ...
_G.Embolsao = Embolsao

Embolsao.VirtualInventory = {}
Embolsao.EmptySlots = {}
Embolsao.EmptySlotGroups = {}
Embolsao.BankVirtualInventory = {}
Embolsao.BankEmptySlots = {}
Embolsao.BankEmptySlotGroups = {}
Embolsao.RecentItemIDs = {} -- replaced by the persisted per-character table in InitDB()
Embolsao.bagsSettled = false -- set on the first BAG_UPDATE_DELAYED; see UpdateRecentItems
Embolsao.AtBank = false -- mirrored from UI.lua's own BANKFRAME_OPENED/CLOSED tracking
Embolsao.BankViewMode = "PERSONAL" -- or "WARBAND" -- which pool ScanBank() populates while at the bank
Embolsao.BankOffline = false -- the bank pane is showing a saved copy (read only), away from any banker
Embolsao.bankSettled = false -- at a banker, once the bank's data has had time to load; see ScanBank

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
    -- The bank pane's own set of tabs (Preferences -> "Separate tabs for Bank
    -- and Bags"): same shapes as the five above, kept apart. See Filters.bank.
    bankCustomTabs = true,
    bankHiddenTabs = true,
    bankTabOrder = true,
    bankBuiltInOverrides = true,
    bankActiveTab = true,
    collapsedHeadersGlobal = true, -- [headerKey] = true, used when syncCategoryVisibility is on
    collapsedHeaders = true, -- [tabID] = { [headerKey] = true }, used when syncCategoryVisibility is off
    tabSort = true, -- [tabID] = { mode = "NAME"|..., ascending = bool }; a tab with no entry falls back to sortMode/sortAscending
}

local DEFAULT_DB = {
    customTabs = {},
    hiddenTabs = {},
    tabOrder = {},
    builtInOverrides = {},
    activeTab = "ALL",
    bankCustomTabs = {},
    bankHiddenTabs = {},
    bankTabOrder = {},
    bankBuiltInOverrides = {},
    bankActiveTab = "ALL",
    separateBankTabs = true, -- the bank pane keeps its own tabs instead of sharing the bags'
    sortMode = "TYPE", -- default for any tab that hasn't been given its own sort yet (see tabSort)
    sortAscending = true,
    tabSort = {},
    defaultTab = "LAST", -- "LAST" = reopen on whichever tab was active last
    consolidateStacks = true,
    rememberPosition = true,
    groupByClass = false, -- Sort By Type: show a class header before each group
    groupBySubClass = false, -- ...and a nested subclass header too
    syncCategoryVisibility = true, -- one shared collapse state for every tab, instead of one per tab
    collapsedHeadersGlobal = {},
    collapsedHeaders = {},
    disabled = false, -- minimap button toggle: leaves native bags alone entirely
    minimapAngle = 225, -- position around the minimap ring, in degrees
    showMinimapButton = true,
    betaNoticeDismissedVersion = "", -- version the "Don't show this message again" checkbox was ticked for; resets (shows again) on every new version
    mergeBankStorage = true, -- merge personal bank storage into the same view as your bags while at a banker
    showRecentCategory = true, -- pin the "Recent" category (see Filters.lua) always-first, next to "All"
    showJunkCategory = true, -- pin a "Junk" (grey items) category right under Recent, with a sell-all button at vendors
    showQuestCategory = true, -- pin a "Quest Items" category right under Junk: quest starters and items tied to an in-progress quest
    autoSellJunk = false, -- sell every grey item automatically whenever a vendor window opens
    closeOnCombat = false, -- close the bags window (and the bank part) when combat starts
    offlineBank = true, -- remember the bank's contents at every visit, to look at them away from a banker
    fadeAlpha = 0.5, -- (0.1-1.0) how opaque the window stays while the character moves (like the world map); 1.0 = no fade at all
    backgroundOpacity = 1, -- (0.1-1.0) the window's resting background opacity, independent of fadeAlpha
    junkItemIDs = {}, -- [itemID] = true: items the player marked as junk by hand (item actions menu), on top of grey ones
    bindings = {}, -- [actionID] = modifier combo; anything missing uses its default (see UI.lua's BINDING_ACTIONS)
    showGearsetBar = true, -- the floating bar of Gearset buttons (GearsetBar.lua); only ever appears once a Gearset tab exists
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

    -- First time THIS character has ever loaded with the flag unset (every
    -- character from before this option existed, or a brand new one):
    -- default it on, but -- same as flipping the Preferences checkbox by
    -- hand (SetUseCharacterSpecificData) -- seed it with a copy of the
    -- shared data first, so the switch is invisible.
    --
    -- BUG (shipped, fixed here): this used to run BEFORE the defaulting
    -- loop above and just set the flag, with no copy -- the loop then saw
    -- EmbolsaoCharDB's keys as nil and defaulted them to EMPTY, not to the
    -- shared data. Every character logging in for the first time after
    -- "Character Specific Customization" defaulted to true (not just on
    -- this account) would silently lose sight of their real tabs, category
    -- rules etc., even though the shared copy sat untouched the whole time.
    if EmbolsaoCharDB.useCharacterSpecific == nil then
        for key in pairs(PER_CHARACTER_KEYS) do
            EmbolsaoCharDB[key] = DeepCopy(EmbolsaoDB.sharedCharData[key])
        end
        EmbolsaoCharDB.useCharacterSpecific = true
    end

    local function ActiveCharStore()
        return EmbolsaoCharDB.useCharacterSpecific and EmbolsaoCharDB or EmbolsaoDB.sharedCharData
    end

    -- Per character on purpose (never the shared/proxied store): these are
    -- items sitting in THIS character's bags.
    EmbolsaoCharDB.recentItems = EmbolsaoCharDB.recentItems or {}
    Embolsao.RecentItemIDs = EmbolsaoCharDB.recentItems

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

--------------------------------------------------------------------------
-- Cross-character preference copy/reset (Preferences -> Manage Tabs). A
-- character in-session has no way to read another character's
-- SavedVariables -- those only ever load for whoever's currently logged
-- in -- so "copy from an alt" needs every character to leave a snapshot of
-- its OWN per-character customization (PER_CHARACTER_KEYS) in the
-- account-wide store, refreshed on login and logout, that any other
-- character can read back later. Necessarily as-of-last-session, not live.
--------------------------------------------------------------------------

local function GetCharKey()
    local playerName, realmName = UnitName("player"), GetRealmName()
    if not playerName or not realmName then return nil end
    return playerName .. "-" .. realmName
end

-- Snapshots THIS character's own EmbolsaoCharDB slot -- its customization
-- whether or not it's the one currently active (useCharacterSpecific could
-- be off, reading from the shared pool instead) -- since that's what
-- "copy FROM this character" should mean: its own saved work, not
-- whatever it happens to be looking at right now.
function Embolsao:SnapshotCharacterPreferences()
    local charKey = GetCharKey()
    if not charKey or not EmbolsaoDB then return end

    local data = {}
    for key in pairs(PER_CHARACTER_KEYS) do
        data[key] = DeepCopy(EmbolsaoCharDB[key])
    end

    EmbolsaoDB.characterSnapshots = EmbolsaoDB.characterSnapshots or {}
    EmbolsaoDB.characterSnapshots[charKey] = {
        name = UnitName("player"),
        data = data,
        savedAt = time(),
    }
end

-- Every OTHER character's snapshot (this one excluded), for the "Copy
-- Preferences From" dropdown.
function Embolsao:GetCharacterSnapshots()
    local charKey = GetCharKey()
    local result = {}
    for key, snapshot in pairs((EmbolsaoDB and EmbolsaoDB.characterSnapshots) or {}) do
        if key ~= charKey then
            result[key] = snapshot
        end
    end
    return result
end

-- Copies a snapshotted alt's per-character customization into this
-- character's own slot, and switches this character to use it (copying
-- data nobody then looks at would be pointless).
function Embolsao:CopyPreferencesFromCharacter(sourceCharKey)
    local snapshot = EmbolsaoDB and EmbolsaoDB.characterSnapshots and EmbolsaoDB.characterSnapshots[sourceCharKey]
    if not snapshot then return false end

    for key in pairs(PER_CHARACTER_KEYS) do
        EmbolsaoCharDB[key] = DeepCopy(snapshot.data[key])
    end
    EmbolsaoCharDB.useCharacterSpecific = true
    return true
end

-- Overwrites this character's own customization with a fresh copy of the
-- shared pool every character without its own copy already uses --
-- distinct from just flipping "Character Specific Customization" off
-- (which leaves whatever this character had untouched, just unused). Stays
-- in character-specific mode afterward: the point is a starting copy to
-- build from, not to go back to reading the shared pool live.
function Embolsao:ResetCharacterToShared()
    for key in pairs(PER_CHARACTER_KEYS) do
        EmbolsaoCharDB[key] = DeepCopy(EmbolsaoDB.sharedCharData[key])
    end
    EmbolsaoCharDB.useCharacterSpecific = true
end

-- Wipes this character's own customization back to the untouched, factory
-- starting point (empty tabs, no rules) -- same values DEFAULT_DB seeds a
-- brand new character with. Never touches the shared pool or any other
-- character's data.
function Embolsao:ResetCharacterToDefault()
    for key, defaultValue in pairs(DEFAULT_DB) do
        if PER_CHARACTER_KEYS[key] then
            EmbolsaoCharDB[key] = (type(defaultValue) == "table") and {} or defaultValue
        end
    end
    EmbolsaoCharDB.useCharacterSpecific = true
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
--
-- Two optional extras serve the offline bank. `snapBag` scans a saved copy of
-- the bag instead of the live one (same entries come out); `capture`, given a
-- table, records what the live scan saw so it can be saved as that copy.
local function ScanBag(bagID, inventory, emptySlots, consolidate, snapBag, capture)
    if not bagID then return end
    local numSlots = snapBag and snapBag.n or GetBagNumSlots(bagID)
    if not numSlots or numSlots == 0 then return end

    local captured
    if capture then
        captured = {
            n = numSlots,
            family = select(2, C_Container.GetContainerNumFreeSlots(bagID)) or 0,
            slots = {},
        }
        capture[bagID] = captured
    end

    for slot = 1, numSlots do
        local info
        if snapBag then
            local saved = snapBag.slots[slot]
            if saved then
                info = {
                    itemID = saved.i, stackCount = saved.c, iconFileID = saved.ic,
                    quality = saved.q, hyperlink = saved.l,
                }
            end
        else
            info = C_Container.GetContainerItemInfo(bagID, slot)
        end
        if captured and info and info.itemID then
            captured.slots[slot] = {
                i = info.itemID, c = info.stackCount or 1, ic = info.iconFileID,
                q = info.quality, l = info.hyperlink,
            }
        end
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
            -- Item level and stats for advanced tab filters (Filters.lua) --
            -- computed once per entry, not per occurrence of a merged stack,
            -- same as quality/hyperlink above. Needs the hyperlink (random
            -- enchants/bonuses affect both), so this waits until one is
            -- actually available rather than running off a bare itemID.
            if entry.itemLevel == nil and entry.hyperlink then
                entry.itemLevel = Embolsao:GetEffectiveItemLevel(entry.itemID, entry.hyperlink)
                entry.stats = Embolsao:GetItemStatsTable(entry.hyperlink)
            end
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
local function IsSpecialBag(bagID, snapBag)
    if snapBag then return (snapBag.family or 0) ~= 0 end
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

-- Every bagID Embolsao:ScanBags() itself scans -- shared with
-- BuildEmptySlotGroups below so the two can never drift apart about what
-- "the bags domain" actually covers.
local function GetBagsDomainBagIDs()
    local bagIDs = {}
    for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        table.insert(bagIDs, bagID)
    end
    if REAGENT_BAG_ID then
        table.insert(bagIDs, REAGENT_BAG_ID)
    end
    -- Retail still has IsKeyRingEnabled/KEYRING_CONTAINER/GetKeyRingSize as
    -- leftover globals even though the feature was removed there -- and
    -- GetKeyRingSize() on retail doesn't return 0, it returns some other
    -- stale value (100+ "free slots" for a bag that doesn't exist). Classic
    -- is the only flavor that actually has a keyring, so gate on that
    -- first, not just on whether the old API happens to still respond.
    if Embolsao.IsClassic and IsKeyRingEnabled and IsKeyRingEnabled() then
        table.insert(bagIDs, KEYRING_CONTAINER)
    end
    return bagIDs
end
-- Exposed for Gearset.lua's "Unequip everything else" bag-space check --
-- same per-flavor bag range this file already carefully works out (reagent
-- bag, keyring quirks), not worth re-deriving there.
Embolsao.GetBagsDomainBagIDs = GetBagsDomainBagIDs

-- One group per special bag currently equipped -- even a completely full
-- one, so its counter reads 0 instead of just disappearing -- plus one
-- shared "general" group (always first) for the backpack and any plain bag.
-- bagIDs is the exact domain to consider -- the bags window's own (backpack
-- + regular bags + reagent bag + keyring) or the bank window's (personal or
-- Warband Bank) -- so the same function serves both without mixing them up.
-- snapshot: build the groups from a saved bank instead of the live bags (the
-- offline bank); bag sizes and kinds then come from it.
local function BuildEmptySlotGroups(emptySlots, bagIDs, snapshot)
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
    local specialGroupsByKey = {}

    for _, bagID in ipairs(bagIDs) do
        local snapBag = snapshot and snapshot.bags[bagID]
        local numSlots
        if snapshot then
            numSlots = snapBag and snapBag.n
        else
            numSlots = GetBagNumSlots(bagID)
        end
        if (numSlots or 0) > 0 then
            if IsSpecialBag(bagID, snapBag) then
                -- Special bags of the same kind share ONE group/button: two
                -- Mining Bags are just more room for the same items, so
                -- they read as a single counter, not two. "Same kind" is the
                -- bag's family (a bitmask of what it accepts -- mining, herbs,
                -- enchanting...); the reagent bag and the keyring have no
                -- family to speak of, so each is its own kind.
                local key, family
                if REAGENT_BAG_ID and bagID == REAGENT_BAG_ID then
                    key = "reagent"
                elseif Embolsao.IsClassic and bagID == KEYRING_CONTAINER then
                    key = "keyring"
                else
                    family = snapBag and snapBag.family or select(2, C_Container.GetContainerNumFreeSlots(bagID))
                    key = "family:" .. tostring(family)
                end

                local group = specialGroupsByKey[key]
                if not group then
                    -- bagID stays the first bag of the kind (its icon
                    -- represents the button); bagIDs only appears once a
                    -- second bag joins, and is what opening "this group"
                    -- natively should open. family is kept so the UI can
                    -- label the button by profession rather than by the
                    -- name of whichever bag happens to be first.
                    group = { id = "bag:" .. bagID, bagID = bagID, slots = {}, family = family }
                    specialGroupsByKey[key] = group
                    table.insert(groups, group)
                else
                    group.bagIDs = group.bagIDs or { group.bagID }
                    table.insert(group.bagIDs, bagID)
                end
                for _, slotInfo in ipairs(slotsByBag[bagID] or {}) do
                    table.insert(group.slots, slotInfo)
                end
            else
                table.insert(generalBagIDs, bagID)
                for _, slotInfo in ipairs(slotsByBag[bagID] or {}) do
                    table.insert(generalSlots, slotInfo)
                end
            end
        end
    end

    -- bagIDs (every plain bag, even a full one) lets the "general" button's
    -- right-click open exactly those bags -- not ToggleAllBags(), which
    -- would also pop open every special bag that already has its own
    -- dedicated button/group.
    table.insert(groups, 1, { id = "general", slots = generalSlots, bagIDs = generalBagIDs })
    return groups
end

-- "Recent" is our own record, not Blizzard's live C_NewItems flag: Blizzard
-- wipes that flag for every item in a native container frame each time the
-- frame is hidden (ContainerFrame.lua's UpdateNewItemList) -- and we
-- show/hide those frames constantly just to suppress them -- so a Recent group
-- driven by the raw flag emptied itself without the player dismissing
-- anything. Instead each scan copies the flag into RecentItemIDs (persisted
-- per character) the moment it's seen, and an item stays there until it's
-- dismissed or leaves the bags. Only bag entries get entry.isRecent, so the
-- bank window never shows a Recent group.
--
-- allowPrune: dropping ids that aren't in the bags anymore is only safe once
-- the bags have actually loaded, or a scan that runs too early would wipe
-- everything that was persisted.
function Embolsao:UpdateRecentItems(inventory, allowPrune)
    local recent = self.RecentItemIDs
    if not recent then return end

    local canReadFlags = C_NewItems and C_NewItems.IsNewItem
    local present = {}
    for _, entry in pairs(inventory) do
        present[entry.itemID] = true
        if canReadFlags and not recent[entry.itemID] then
            for _, location in ipairs(entry.locations) do
                if C_NewItems.IsNewItem(location.bagID, location.slot) then
                    recent[entry.itemID] = true
                    break
                end
            end
        end
        entry.isRecent = recent[entry.itemID] == true
    end

    if allowPrune and next(inventory) ~= nil then
        for itemID in pairs(recent) do
            if not present[itemID] then
                recent[itemID] = nil
            end
        end
    end
end

-- Dismiss button on a Recent item: forget it on our side and clear
-- Blizzard's flag too, so the next scan doesn't just re-adopt it.
function Embolsao:DismissRecentItem(itemID, locations)
    if self.RecentItemIDs then
        self.RecentItemIDs[itemID] = nil
    end
    if C_NewItems and C_NewItems.RemoveNewItem then
        for _, location in ipairs(locations or {}) do
            C_NewItems.RemoveNewItem(location.bagID, location.slot)
        end
    end
end

-- Quest-starter items (not yet picked up) and items tied to an in-progress
-- quest, for the pinned "Quest Items" group (Layout.BuildLayoutRows) --
-- per-slot, not per-itemID (GetContainerItemQuestInfo has no itemID form),
-- so a merged stack reads off its first real location, same as
-- entry.hyperlink/itemLevel/stats already do above.
local function GetEntryQuestInfo(entry)
    local location = entry.locations and entry.locations[1]
    if not location then return nil, false end
    local ok, questInfo = pcall(C_Container.GetContainerItemQuestInfo, location.bagID, location.slot)
    if not ok or type(questInfo) ~= "table" then return nil, false end
    return questInfo.questID or questInfo.questId, questInfo.isActive == true, questInfo.isQuestItem == true
end

function Embolsao:ScanBags()
    local inventory = {}
    local emptySlots = {}
    local consolidate = self.db == nil or self.db.consolidateStacks ~= false
    local bagIDs = GetBagsDomainBagIDs()
    for _, bagID in ipairs(bagIDs) do
        ScanBag(bagID, inventory, emptySlots, consolidate)
    end
    self:UpdateRecentItems(inventory, self.bagsSettled)
    -- "Junk" (the grey-quality group UI.lua pins under Recent) is bags-only
    -- like Recent: bank entries are never stamped, so the bank window never
    -- offers to sell anything. Quest items are the same story -- can't turn
    -- one in from the bank either.
    local userJunk = self.db and self.db.junkItemIDs or {}
    for _, entry in pairs(inventory) do
        entry.isJunk = entry.quality == 0 or userJunk[entry.itemID] == true
        entry.questID, entry.isQuestActive, entry.isQuestItem = GetEntryQuestInfo(entry)
    end
    self.VirtualInventory = inventory
    self.EmptySlots = emptySlots
    self.EmptySlotGroups = BuildEmptySlotGroups(emptySlots, bagIDs)
    return inventory
end

-- Same shape as ScanBags above, but for the bank window's own pool instead
-- of the player's carried bags -- kept as a fully separate scan/table pair
-- rather than folded into the same one, since the bank now gets its own
-- Embolsao-styled window (UI.lua) instead of merging into the bags window.
-- BankViewMode picks which of the two (mutually exclusive) bank pools to
-- show; Warband Bank is account-wide, not "yours" the same way personal
-- storage is, so it's never mixed with the personal one either.
function Embolsao:ScanBank()
    -- The offline bank shows a saved copy: live scans (which run on every bag
    -- event, banker or not) must not replace it with an empty bank.
    if self.BankOffline then
        return self:ScanBankOffline()
    end

    -- On the modern bank the tab list is only known once the bank data has
    -- arrived, which can be a moment after the frame shows -- so it's
    -- re-read on every scan while at a banker, not just when it opens.
    if self.AtBank then
        self:RefreshModernBankBagIDs()
    end

    local inventory = {}
    local emptySlots = {}
    local consolidate = self.db == nil or self.db.consolidateStacks ~= false

    -- What is seen at the banker is also kept, for the offline bank -- but
    -- only once the bank has settled (UI.lua sets bankSettled after its delayed
    -- first scan): the first scans after opening can read every slot as empty,
    -- and that must never replace a good copy.
    local capture = (self.AtBank and self.bankSettled and self.db and self.db.offlineBank ~= false) and {} or nil

    local bagIDs = (self.BankViewMode == "WARBAND") and Embolsao.WarbandBankBagIDs or Embolsao.PersonalBankBagIDs
    for _, bagID in ipairs(bagIDs) do
        ScanBag(bagID, inventory, emptySlots, consolidate, nil, capture)
    end

    self.BankVirtualInventory = inventory
    self.BankEmptySlots = emptySlots
    self.BankEmptySlotGroups = BuildEmptySlotGroups(emptySlots, bagIDs)

    if capture and next(capture) then
        self:SaveBankSnapshot(self.BankViewMode, bagIDs, capture)
    end
    return inventory
end

-- The saved copies of the bank: the personal bank belongs to this character;
-- the Warband bank is account-wide, so any character's visit refreshes the one
-- everybody sees.
function Embolsao:GetBankSnapshot(view)
    if view == "WARBAND" then
        return EmbolsaoDB and EmbolsaoDB.warbandBankSnapshot
    end
    return EmbolsaoCharDB and EmbolsaoCharDB.bankSnapshot
end

function Embolsao:SaveBankSnapshot(view, bagIDs, bags)
    local snapshot = {
        time = time(),
        bagIDs = { unpack(bagIDs) },
        bags = bags,
    }
    if view == "WARBAND" then
        if EmbolsaoDB then EmbolsaoDB.warbandBankSnapshot = snapshot end
    elseif EmbolsaoCharDB then
        EmbolsaoCharDB.bankSnapshot = snapshot
    end
end

-- Fills the bank's tables from the saved copy of BankViewMode's bank instead of
-- the live one. Returns false when there is no copy to show.
function Embolsao:ScanBankOffline()
    local snapshot = self:GetBankSnapshot(self.BankViewMode)
    if not snapshot then return false end

    local inventory = {}
    local emptySlots = {}
    local consolidate = self.db == nil or self.db.consolidateStacks ~= false
    for _, bagID in ipairs(snapshot.bagIDs) do
        ScanBag(bagID, inventory, emptySlots, consolidate, snapshot.bags[bagID] or { n = 0, slots = {} })
    end

    self.BankVirtualInventory = inventory
    self.BankEmptySlots = emptySlots
    self.BankEmptySlotGroups = BuildEmptySlotGroups(emptySlots, snapshot.bagIDs, snapshot)
    return inventory
end

local function RefreshUI()
    if Embolsao.UI and Embolsao.UI.Refresh then
        Embolsao.UI:Refresh()
    end
end

-- The game's "blocked from an action only available to the Blizzard UI" popup
-- names the addon but not what it tried to do. These two events carry the
-- function, and they fire right at the offending call, so the stack at that
-- moment says where in this addon it came from. Printed to chat (a few times
-- per session at most) so a report can say exactly what happened.
local blockedReports = 0
local blockedFrame = CreateFrame("Frame")
for _, blockedEvent in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(blockedFrame.RegisterEvent, blockedFrame, blockedEvent)
end
blockedFrame:SetScript("OnEvent", function(_, event, addonName, functionName)
    if addonName ~= ADDON_NAME or blockedReports >= 3 then return end
    blockedReports = blockedReports + 1
    print(string.format("|cffff5555Embolsao|r: %s -- %s", event, tostring(functionName)))
    -- Also kept in the saved variables (the chat line scrolls away), full
    -- stack included, so it can be read from the file after a /reload.
    if EmbolsaoDB then
        EmbolsaoDB.lastBlockedAction = {
            event = event,
            functionName = tostring(functionName),
            stack = debugstack and debugstack(2, 20, 0) or "",
            time = date and date("%Y-%m-%d %H:%M:%S") or "",
        }
    end
end)

local eventFrame = CreateFrame("Frame", "EmbolsaoEventFrame")
local hasCheckedBetaNotice = false

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
-- Not every client has this event (Classic flavors); an unknown event name
-- must not take the whole addon down.
pcall(eventFrame.RegisterEvent, eventFrame, "BAG_NEW_ITEMS_UPDATED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            -- TEMPORARY: Forever beta client doesn't hand SavedVariables back
            -- on load; see ForeverSVFallback.lua (delete it and this call
            -- once Blizzard fixes that).
            if Embolsao.RestoreSavedVariablesFallback then
                Embolsao:RestoreSavedVariablesFallback()
            end
            InitDB()
            Embolsao:ScanBags()
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_NEW_ITEMS_UPDATED" then
        Embolsao.bagsSettled = true
        Embolsao:ScanBags()
        Embolsao:ScanBank()
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
            Embolsao:SnapshotCharacterPreferences()
        end
    elseif event == "PLAYER_LOGOUT" then
        Embolsao:SnapshotCharacterPreferences()
    end
end)
