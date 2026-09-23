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
