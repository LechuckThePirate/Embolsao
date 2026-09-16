local ADDON_NAME, Embolsao = ...

Embolsao.Filters = {}
local Filters = Embolsao.Filters

local function GetClassIDs(itemID)
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    return classID, subClassID
end

Filters.BuiltIn = {
    {
        id = "ALL",
        name = "Todo",
        predicate = function() return true end,
    },
    {
        id = "WEAPON",
        name = "Armas",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Weapon
        end,
    },
    {
        id = "ARMOR",
        name = "Equipo",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Armor
        end,
    },
    {
        id = "CONSUMABLE",
        name = "Consumibles",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Consumable
        end,
    },
    {
        id = "TRADEGOODS",
        name = "Comercio",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Tradegoods
        end,
    },
    {
        id = "QUESTITEM",
        name = "Mision",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Questitem
        end,
    },
    {
        id = "MISC",
        name = "Miscelanea",
        predicate = function(entry)
            local classID = GetClassIDs(entry.itemID)
            return classID == Enum.ItemClass.Miscellaneous or classID == Enum.ItemClass.Projectile
        end,
    },
}

-- A custom tab matches by explicit itemID override first, falling back to its
-- category/subcategory allow-list. This lets a tab do things like "show
-- equipment + weapons" (categories) or "always show this one trinket" (itemIDs)
-- even if the trinket's own category is hidden elsewhere.
-- `useIgnoredList` is opt-in per tab: the shared ignored-item list (toggled via
-- right-click) is just one ingredient a tab can pull in, not a global filter.
function Filters:MatchesCustomTab(entry, tab)
    if tab.useIgnoredList and Embolsao:IsItemIgnored(entry.itemID) then
        return false
    end

    if tab.itemIDs and tab.itemIDs[entry.itemID] ~= nil then
        return tab.itemIDs[entry.itemID] == true
    end

    local classID, subClassID = GetClassIDs(entry.itemID)
    local categoryRule = tab.categories and classID and tab.categories[classID]
    if categoryRule == true then
        return true
    elseif type(categoryRule) == "table" then
        return subClassID ~= nil and categoryRule[subClassID] == true
    end

    return false
end

function Filters:GetAllTabs()
    local tabs = {}
    for _, tab in ipairs(Filters.BuiltIn) do
        table.insert(tabs, tab)
    end
    for _, customTab in ipairs(Embolsao.db.customTabs) do
        table.insert(tabs, {
            id = customTab.id,
            name = customTab.name,
            predicate = function(entry) return Filters:MatchesCustomTab(entry, customTab) end,
        })
    end
    return tabs
end
