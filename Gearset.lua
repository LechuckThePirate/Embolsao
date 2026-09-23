local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

-- Gearset-specific logic (see Filters.lua's tabType == "gearset" branch and
-- TabEditor.lua's type chooser): how many of a given equip slot a tab's
-- Items list can hold at once, kept separate from the tab-editing UI since
-- the equip/unequip engine (still to come) will live here too.
Embolsao.Gearset = {}
local Gearset = Embolsao.Gearset

-- Every equip slot allows exactly one item except these two.
local BUCKET_MAX = {
    INVTYPE_FINGER = 2,
    INVTYPE_TRINKET = 2,
}

-- Ranged weapons and relics both use the single ranged slot -- different
-- equipLoc strings, same bucket.
local RANGED_TYPES = {
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_RELIC = true,
}

-- Main hand + off hand together hold at most 2 "hand points": a two-hander
-- takes both by itself, everything else that goes in either hand (a
-- one-handed weapon, a main-hand-only or off-hand-only weapon, a shield, a
-- held off-hand item) takes one. This doesn't need to know which classes
-- can actually dual-wield -- WoW's own equip call already refuses an
-- invalid combo for the current class at equip time; this only asks "does
-- the SET run out of hands", which is the same question for anyone.
local HAND_POINTS = {
    INVTYPE_2HWEAPON = 2,
    INVTYPE_WEAPON = 1,
    INVTYPE_WEAPONMAINHAND = 1,
    INVTYPE_WEAPONOFFHAND = 1,
    INVTYPE_SHIELD = 1,
    INVTYPE_HOLDABLE = 1,
}

function Gearset:GetItemEquipLoc(itemID)
    local _, _, _, equipLoc = Embolsao.GetItemInfoInstant(itemID)
    return equipLoc
end

local function NormalizeBucket(equipLoc)
    if RANGED_TYPES[equipLoc] then return "RANGED" end
    return equipLoc
end

-- Everything currently in the set, tallied per equip slot -- used both to
-- validate a new drop (CanAddItem) and, later, to actually equip the set.
local function TallySlotUsage(itemIDSet)
    local bucketCounts, handPoints = {}, 0
    for itemID in pairs(itemIDSet) do
        local equipLoc = Gearset:GetItemEquipLoc(itemID)
        if HAND_POINTS[equipLoc] then
            handPoints = handPoints + HAND_POINTS[equipLoc]
        elseif equipLoc and equipLoc ~= "" then
            local bucket = NormalizeBucket(equipLoc)
            bucketCounts[bucket] = (bucketCounts[bucket] or 0) + 1
        end
    end
    return bucketCounts, handPoints
end

-- Whether itemID could be added to a Gearset tab's Items list (itemIDSet)
-- without exceeding what the character can actually wear of that kind at
-- once (two rings, two trinkets, a full set of hands). Returns true, or
-- false plus a player-facing reason.
function Gearset:CanAddItem(itemIDSet, itemID)
    if itemIDSet[itemID] then
        return true -- already in the set -- not this function's problem to flag
    end

    local equipLoc = self:GetItemEquipLoc(itemID)
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP" then
        return true -- not equippable gear at all (reagents, consumables...) -- nothing to ration
    end

    local bucketCounts, handPoints = TallySlotUsage(itemIDSet)

    if HAND_POINTS[equipLoc] then
        if handPoints + HAND_POINTS[equipLoc] > 2 then
            return false, L.GEARSET_SLOT_FULL
        end
        return true
    end

    local bucket = NormalizeBucket(equipLoc)
    local max = BUCKET_MAX[bucket] or 1
    if (bucketCounts[bucket] or 0) >= max then
        return false, L.GEARSET_SLOT_FULL
    end
    return true
end

--------------------------------------------------------------------------
-- Equip / unequip. "Previously equipped" (whatever a gearset's items
-- replaced) is stored directly on the tab table (tab.previousEquipped =
-- { itemIDs = {...}, dismissed = bool }) -- an ad-hoc field outside
-- Filters.lua's normal shape, but Lua tables serialize to SavedVariables
-- as-is regardless of which file added a key, so this needs no plumbing
-- there. Kept behind this file's own accessors so nothing else reaches
-- into the raw field directly.
--------------------------------------------------------------------------

local NUM_EQUIP_SLOTS = 19 -- INVSLOT_TABARD, the last real gear slot; bag/relic slots beyond it aren't gearset-relevant
local INVSLOT_MAINHAND = 16
local INVSLOT_OFFHAND = 17

local function CaptureEquippedSnapshot()
    local snapshot = {}
    for slotID = 1, NUM_EQUIP_SLOTS do
        snapshot[slotID] = GetInventoryItemID("player", slotID)
    end
    return snapshot
end

local function CountWornItems()
    local count = 0
    for slotID = 1, NUM_EQUIP_SLOTS do
        if GetInventoryItemID("player", slotID) then
            count = count + 1
        end
    end
    return count
end

-- Free slots across every bag in the bags domain (backpack, regular bags,
-- reagent bag, keyring) -- the same per-flavor bag range Core.lua's own
-- scanning already works out, reused rather than re-derived here.
local function CountFreeBagSlots()
    local free = 0
    for _, bagID in ipairs(Embolsao.GetBagsDomainBagIDs()) do
        free = free + (C_Container.GetContainerNumFreeSlots(bagID) or 0)
    end
    return free
end

-- Hand-consuming items with a KNOWN destination slot (2H, mainhand-only,
-- offhand-only, shield, holdable) go first and claim that hand outright;
-- a plain one-handed weapon (ambiguous -- either hand) goes last, explicitly
-- filling whichever hand is still free. Explicit throughout rather than
-- relying on EquipItemByName's own guess, which only looks at what's
-- CURRENTLY worn -- not reliable when this same pass is about to fill both
-- hands itself (dual-wielding two 1H weapons from the same gearset).
local function BuildEquipPlan(itemIDSet)
    local fixed, ambiguous, rest = {}, {}, {}
    for itemID in pairs(itemIDSet) do
        local equipLoc = Gearset:GetItemEquipLoc(itemID)
        if equipLoc == "INVTYPE_WEAPON" then
            table.insert(ambiguous, itemID)
        elseif HAND_POINTS[equipLoc] then
            table.insert(fixed, itemID)
        else
            table.insert(rest, itemID)
        end
    end
    return fixed, ambiguous, rest
end

-- Equips every item in the tab's Items list, then diffs the equipped
-- loadout from before to after to work out what got replaced -- simpler
-- and more robust than predicting each item's destination slot up front,
-- and it's the only way to know what a "rest"-bucket item (armor, etc.)
-- actually displaced without walking Blizzard's own equip-location tables.
-- "Unequip everything else" (tab.unequipEverythingElse) checked BEFORE
-- anything is touched: every currently-worn item needs a free bag slot to
-- land in, and refusing up front (nothing unequipped yet) is the only safe
-- option -- there's no good way to "partially" unequip and stop partway
-- through once bags start filling up.
function Gearset:Equip(tab)
    if tab.unequipEverythingElse then
        local worn = CountWornItems()
        if worn > CountFreeBagSlots() then
            UIErrorsFrame:AddMessage(L.GEARSET_NOT_ENOUGH_BAG_SPACE, 1, 0.2, 0.2)
            return
        end
    end

    local before = CaptureEquippedSnapshot()

    if tab.unequipEverythingElse then
        for slotID = 1, NUM_EQUIP_SLOTS do
            if GetInventoryItemID("player", slotID) then
                Embolsao.PickupInventoryItem(slotID)
                Embolsao.PutItemInBackpack()
            end
        end
    end

    local fixed, ambiguous, rest = BuildEquipPlan(tab.forcedItemIDs)
    local mainHandTaken, offHandTaken = false, false

    for _, itemID in ipairs(fixed) do
        local equipLoc = self:GetItemEquipLoc(itemID)
        if equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
            Embolsao.EquipItemByName(itemID, INVSLOT_MAINHAND)
            mainHandTaken = true
        else -- INVTYPE_WEAPONOFFHAND, INVTYPE_SHIELD, INVTYPE_HOLDABLE
            Embolsao.EquipItemByName(itemID, INVSLOT_OFFHAND)
            offHandTaken = true
        end
    end
    for _, itemID in ipairs(ambiguous) do
        -- CanAddItem already keeps a gearset from holding more than the
        -- hands can take, so by the time a third would-be ambiguous weapon
        -- shows up here (if ever) there's simply nowhere left to put it.
        if not mainHandTaken then
            Embolsao.EquipItemByName(itemID, INVSLOT_MAINHAND)
            mainHandTaken = true
        elseif not offHandTaken then
            Embolsao.EquipItemByName(itemID, INVSLOT_OFFHAND)
            offHandTaken = true
        end
    end
    for _, itemID in ipairs(rest) do
        Embolsao.EquipItemByName(itemID)
    end

    -- GetInventoryItemID doesn't reliably reflect an EquipItemByName call
    -- made in the very same instant -- confirmed live: previousEquipped
    -- came back empty even though a real swap had just happened (diffing
    -- "before" against an "after" that hadn't actually changed yet). A
    -- single C_Timer.After(0, ...) tick (one frame) still wasn't enough --
    -- confirmed with debug prints, after[] read identical to before[] a
    -- frame later despite the swap having visibly happened by then. 0.5s
    -- instead: comfortably past any real-world equip/network latency,
    -- imperceptible for a menu click.
    C_Timer.After(0.5, function()
        local after = CaptureEquippedSnapshot()
        -- In ascending slot order, each remembered WITH the slot it came
        -- from: restoring by item alone can't tell two daggers (or two
        -- rings/trinkets) apart -- both look like "a one-handed weapon" and
        -- end up fighting over the same hand. Main hand (16) before off
        -- hand (17) also happens to be the order a restore wants.
        local replaced, replacedSlots = {}, {}
        for slotID = 1, NUM_EQUIP_SLOTS do
            local beforeItemID = before[slotID]
            if beforeItemID and beforeItemID ~= after[slotID] then
                table.insert(replaced, beforeItemID)
                table.insert(replacedSlots, slotID)
            end
        end
        Gearset:SetPreviousEquipped(tab, replaced, replacedSlots)
        Embolsao.UI:BuildTabs()
        Embolsao.UI:Refresh()
    end)
end

-- Best-effort: re-equips whatever the last Equip() replaced, wherever it
-- currently is (bags or already worn elsewhere). An item the player no
-- longer has (sold, mailed off, disenchanted...) is silently skipped --
-- EquipItemByName just does nothing for it, same as double-clicking a bag
-- item that isn't there anymore.
--
-- That alone isn't enough, though: a slot that was EMPTY before Equip() ran
-- has nothing in previousEquipped to swap back in (the before/after diff in
-- Equip() only records a slot that held something), so re-equipping the
-- list leaves that gearset item sitting there un-touched. The second pass
-- below catches exactly that -- anything still equipped that belongs to
-- this gearset gets explicitly taken off and put back in the bags.
function Gearset:Unequip(tab)
    local slots = tab.previousEquipped and tab.previousEquipped.slots
    for index, itemID in ipairs(self:GetPreviousEquipped(tab)) do
        local slotID = slots and slots[index]
        if slotID then
            -- Back exactly where it came from -- the only way two
            -- interchangeable items (dual-wielded daggers, two rings) each
            -- return to their own slot instead of both aiming at the first.
            Embolsao.EquipItemByName(itemID, slotID)
        else
            -- Saved before slots were remembered: fall back to guessing a
            -- hand from the item type, same as Equip() does.
            local equipLoc = self:GetItemEquipLoc(itemID)
            if equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
                Embolsao.EquipItemByName(itemID, INVSLOT_MAINHAND)
            elseif equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
                Embolsao.EquipItemByName(itemID, INVSLOT_OFFHAND)
            else
                Embolsao.EquipItemByName(itemID)
            end
        end
    end

    -- Same deferral as Equip() (0.5s, not just one frame -- see there).
    C_Timer.After(0.5, function()
        for slotID = 1, NUM_EQUIP_SLOTS do
            local itemID = GetInventoryItemID("player", slotID)
            if itemID and tab.forcedItemIDs[itemID] then
                Embolsao.PickupInventoryItem(slotID)
                Embolsao.PutItemInBackpack()
            end
        end
        Gearset:ClearPreviousEquipped(tab)
        Embolsao.UI:BuildTabs()
        Embolsao.UI:Refresh()
    end)
end

-- slots: parallel to itemIDs -- slots[i] is the equip slot itemIDs[i] was
-- taken out of (nil for data saved before slots were remembered).
function Gearset:SetPreviousEquipped(tab, itemIDs, slots)
    tab.previousEquipped = { itemIDs = itemIDs, slots = slots, dismissed = false }
end

function Gearset:GetPreviousEquipped(tab)
    return (tab.previousEquipped and tab.previousEquipped.itemIDs) or {}
end

function Gearset:ClearPreviousEquipped(tab)
    tab.previousEquipped = nil
end

function Gearset:DismissPreviousEquipped(tab)
    if tab.previousEquipped then
        tab.previousEquipped.dismissed = true
    end
end

-- Whether any item of the set is sitting in the bags right now -- i.e.
-- whether there is anything to equip. Equip is pointless (and hidden, see
-- UI.lua / TabEditor's tab menu) when the whole set is worn already, in the
-- bank, or simply not owned.
function Gearset:HasItemsInBags(tab)
    local itemIDs = tab.forcedItemIDs
    if not itemIDs then return false end
    for _, entry in pairs(Embolsao.VirtualInventory) do
        if itemIDs[entry.itemID] then return true end
    end
    return false
end

-- Equip (if something in the set is in the bags) or Unequip (if it's all
-- worn) has something to do. Neither otherwise.
function Gearset:CanToggle(tab)
    return self:IsEquipped(tab) or self:HasItemsInBags(tab)
end

function Gearset:GetEquippedItemIDs()
    local equipped = {}
    for slotID = 1, NUM_EQUIP_SLOTS do
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then equipped[itemID] = true end
    end
    return equipped
end

-- Heuristic for the tab button's "currently worn" indicator: every item in
-- the set is equipped SOMEWHERE right now, not necessarily just equipped
-- via this addon -- if the player already happened to be wearing a
-- matching loadout, that still counts.
function Gearset:IsEquipped(tab)
    local itemIDs = tab.forcedItemIDs
    if not itemIDs or not next(itemIDs) then return false end

    local equippedItemIDs = self:GetEquippedItemIDs()
    for itemID in pairs(itemIDs) do
        if not equippedItemIDs[itemID] then return false end
    end
    return true
end

--------------------------------------------------------------------------
-- Equipped / Unavailable / Previously Equipped rows (Layout.BuildLayoutRows'
-- gearsetGroups param) -- an item that isn't sitting in a bag right now
-- (worn, or simply not owned) has no real entry to show, so one gets built
-- by hand from cached item info instead. isVirtual marks it for UI.lua's
-- item-button code (no real bagID/slot, so no click/drag actions).
--------------------------------------------------------------------------

function Gearset:BuildVirtualEntry(itemID, extraFields)
    local _, _, quality, _, _, _, _, _, _, icon = Embolsao.GetItemInfo(itemID)
    local entry = {
        itemID = itemID,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        quality = quality,
        count = 0,
        isVirtual = true,
    }
    if extraFields then
        for key, value in pairs(extraFields) do
            entry[key] = value
        end
    end
    return entry
end

-- entries: the tab's own (already gearset-filtered) bag items -- anything
-- in the set NOT among them is either worn or unavailable. pinnedSource:
-- every bag item regardless of tab, needed for Previously Equipped since
-- what got replaced isn't necessarily a member of this gearset at all.
function Gearset:BuildGroups(tab, entries, pinnedSource)
    local inBag = {}
    for _, entry in ipairs(entries) do
        inBag[entry.itemID] = true
    end
    local equippedItemIDs = self:GetEquippedItemIDs()

    local equipped, unavailable = {}, {}
    for itemID in pairs(tab.forcedItemIDs or {}) do
        if not inBag[itemID] then
            if equippedItemIDs[itemID] then
                table.insert(equipped, self:BuildVirtualEntry(itemID, { isGearsetEquipped = true }))
            else
                table.insert(unavailable, self:BuildVirtualEntry(itemID, { isUnavailable = true }))
            end
        end
    end

    local previouslyEquipped = {}
    if tab.previousEquipped and not tab.previousEquipped.dismissed then
        for _, itemID in ipairs(tab.previousEquipped.itemIDs or {}) do
            local entry
            for _, candidate in ipairs(pinnedSource) do
                if candidate.itemID == itemID then
                    entry = candidate
                    break
                end
            end
            if not entry then
                entry = self:BuildVirtualEntry(itemID, equippedItemIDs[itemID]
                    and { isGearsetEquipped = true } or { isUnavailable = true })
            end
            table.insert(previouslyEquipped, entry)
        end
    end

    return { equipped = equipped, unavailable = unavailable, previouslyEquipped = previouslyEquipped }
end
