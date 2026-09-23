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
function Gearset:Equip(tab)
    local before = CaptureEquippedSnapshot()

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

    local after = CaptureEquippedSnapshot()
    local replaced = {}
    for slotID, beforeItemID in pairs(before) do
        if beforeItemID and beforeItemID ~= after[slotID] then
            table.insert(replaced, beforeItemID)
        end
    end
    self:SetPreviousEquipped(tab, replaced)
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
    for _, itemID in ipairs(self:GetPreviousEquipped(tab)) do
        Embolsao.EquipItemByName(itemID)
    end

    for slotID = 1, NUM_EQUIP_SLOTS do
        local itemID = GetInventoryItemID("player", slotID)
        if itemID and tab.forcedItemIDs[itemID] then
            Embolsao.PickupInventoryItem(slotID)
            Embolsao.PutItemInBackpack()
        end
    end

    self:ClearPreviousEquipped(tab)
end

function Gearset:SetPreviousEquipped(tab, itemIDs)
    tab.previousEquipped = { itemIDs = itemIDs, dismissed = false }
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

-- Heuristic for the tab button's "currently worn" indicator: every item in
-- the set is equipped SOMEWHERE right now, not necessarily just equipped
-- via this addon -- if the player already happened to be wearing a
-- matching loadout, that still counts.
function Gearset:IsEquipped(tab)
    local itemIDs = tab.forcedItemIDs
    if not itemIDs or not next(itemIDs) then return false end

    local equippedItemIDs = {}
    for slotID = 1, NUM_EQUIP_SLOTS do
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then equippedItemIDs[itemID] = true end
    end

    for itemID in pairs(itemIDs) do
        if not equippedItemIDs[itemID] then return false end
    end
    return true
end
