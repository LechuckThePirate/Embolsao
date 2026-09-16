local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

Embolsao.Filters = {}
local Filters = Embolsao.Filters

local function GetClassIDs(itemID)
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    return classID, subClassID
end

Filters.BuiltIn = {
    {
        id = "ALL",
        name = L.ALL,
        icon = "Interface\\Icons\\INV_Misc_Bag_08",
        predicate = function() return true end,
    },
    {
        id = "WEAPON",
        name = L.WEAPONS,
        icon = "Interface\\Icons\\INV_Sword_04",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Weapon
        end,
    },
    {
        id = "ARMOR",
        name = L.GEAR,
        icon = "Interface\\Icons\\INV_Chest_Chain_05",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Armor
        end,
    },
    {
        id = "CONSUMABLE",
        name = L.CONSUMABLES,
        icon = "Interface\\Icons\\INV_Potion_54",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Consumable
        end,
    },
    {
        id = "TRADEGOODS",
        name = L.TRADEGOODS,
        icon = "Interface\\Icons\\INV_Ore_Copper_01",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Tradegoods
        end,
    },
    {
        id = "QUESTITEM",
        name = L.QUESTITEMS,
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        predicate = function(entry)
            return GetClassIDs(entry.itemID) == Enum.ItemClass.Questitem
        end,
    },
    {
        id = "MISC",
        name = L.MISC,
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        predicate = function(entry)
            local classID = GetClassIDs(entry.itemID)
            return classID == Enum.ItemClass.Miscellaneous or classID == Enum.ItemClass.Projectile
        end,
    },
}

function Filters:IsBuiltIn(id)
    for _, tab in ipairs(Filters.BuiltIn) do
        if tab.id == id then return true end
    end
    return false
end

function Filters:GetCustomTab(id)
    for _, tab in ipairs(Embolsao.db.customTabs) do
        if tab.id == id then return tab end
    end
    return nil
end

-- A custom tab matches by explicit itemID exclusion first (the "hidden
-- items" list, always a blocklist), then by its ordered category rules.
-- Each rule is {classID, subClassID (optional), mode = "show"|"hide"}; the
-- most specific matching rule wins (a subclass-scoped rule beats a
-- class-wide one). If no rule matches an item at all: the tab acts as a
-- blocklist (show it) UNLESS it has at least one "show" rule anywhere, in
-- which case it's operating as a whitelist and unmatched items are hidden.
-- A tab with no rules and no hidden items at all matches everything.
--
-- A rule can also target ALL_CATEGORIES explicitly (lowest specificity, 0)
-- so a tab can say e.g. "Show: All Categories" + "Hide: Weapon > Sword" to
-- mean "show everything except swords", with the exception spelled out as
-- a real rule instead of only being inferable from rule presence.
Filters.ALL_CATEGORIES = -1

function Filters:MatchesCustomTab(entry, tab)
    if tab.hiddenItemIDs and tab.hiddenItemIDs[entry.itemID] then
        return false
    end

    local rules = tab.categoryRules
    if not rules or #rules == 0 then
        return true
    end

    local classID, subClassID = GetClassIDs(entry.itemID)
    local hasShowRule = false
    local bestRule, bestSpecificity = nil, -1
    for _, rule in ipairs(rules) do
        if rule.mode == "show" then
            hasShowRule = true
        end

        local matches, specificity
        if rule.classID == Filters.ALL_CATEGORIES then
            matches, specificity = true, 0
        elseif rule.classID == classID and (rule.subClassID == nil or rule.subClassID == subClassID) then
            matches, specificity = true, rule.subClassID and 2 or 1
        end

        if matches and specificity > bestSpecificity then
            bestSpecificity = specificity
            bestRule = rule
        end
    end

    if bestRule then
        return bestRule.mode == "show"
    end
    return not hasShowRule
end

-- Full tab list (built-in + custom), in the player's saved order, each
-- carrying `hidden`/`isBuiltIn` flags. Callers that want only what should
-- actually render as a clickable tab should use GetVisibleTabs() instead --
-- this one exists for management UIs (Preferences) that need to show
-- everything, hidden tabs included.
function Filters:GetAllTabs()
    local byID = {}

    for _, tab in ipairs(Filters.BuiltIn) do
        byID[tab.id] = {
            id = tab.id,
            name = tab.name,
            icon = tab.icon,
            predicate = tab.predicate,
            isBuiltIn = true,
            hidden = Embolsao.db.hiddenTabs[tab.id] == true,
        }
    end

    for _, customTab in ipairs(Embolsao.db.customTabs) do
        byID[customTab.id] = {
            id = customTab.id,
            name = customTab.name,
            icon = customTab.icon or "Interface\\Icons\\INV_Misc_Bag_10",
            predicate = function(entry) return Filters:MatchesCustomTab(entry, customTab) end,
            isBuiltIn = false,
            hidden = Embolsao.db.hiddenTabs[customTab.id] == true,
        }
    end

    -- Respect saved order; anything not in it yet (freshly created, or an
    -- upgrade from before ordering existed) gets appended, built-ins first.
    local order, seen = {}, {}
    for _, id in ipairs(Embolsao.db.tabOrder) do
        if byID[id] and not seen[id] then
            table.insert(order, byID[id])
            seen[id] = true
        end
    end
    for _, tab in ipairs(Filters.BuiltIn) do
        if not seen[tab.id] then
            table.insert(order, byID[tab.id])
            seen[tab.id] = true
        end
    end
    for _, customTab in ipairs(Embolsao.db.customTabs) do
        if not seen[customTab.id] then
            table.insert(order, byID[customTab.id])
            seen[customTab.id] = true
        end
    end

    -- "All" is always first and always visible -- enforced here (not just
    -- at the write side in SetTabHidden/MoveTab/MoveTabToPosition) so the
    -- invariant holds even against old/hand-edited saved data.
    for i, tab in ipairs(order) do
        if tab.id == "ALL" then
            tab.hidden = false
            if i ~= 1 then
                table.remove(order, i)
                table.insert(order, 1, tab)
            end
            break
        end
    end

    return order
end

function Filters:GetVisibleTabs()
    local visible = {}
    for _, tab in ipairs(self:GetAllTabs()) do
        if not tab.hidden then
            table.insert(visible, tab)
        end
    end
    return visible
end

function Filters:SetTabHidden(id, hidden)
    if id == "ALL" then return end -- always visible, no exceptions
    Embolsao.db.hiddenTabs[id] = hidden and true or nil
end

local function GetTabOrderIDs()
    local order = {}
    for _, tab in ipairs(Filters:GetAllTabs()) do
        table.insert(order, tab.id)
    end
    return order
end

-- Swaps the tab at `id` with its neighbor in the given direction (-1 up/left,
-- 1 down/right). Rebuilds tabOrder from GetAllTabs() first so this works
-- correctly even the first time it's called (before tabOrder has ever been
-- fully populated). "All" never moves and nothing can swap past it into
-- position 1.
function Filters:MoveTab(id, direction)
    if id == "ALL" then return end

    local order = GetTabOrderIDs()

    local index
    for i, tabID in ipairs(order) do
        if tabID == id then
            index = i
            break
        end
    end
    if not index then return end

    local newIndex = index + direction
    if newIndex < 1 or newIndex > #order then return end
    if order[newIndex] == "ALL" then return end

    order[index], order[newIndex] = order[newIndex], order[index]
    Embolsao.db.tabOrder = order
end

-- Used by drag-to-reorder in the main window: moves `id` to sit at
-- `targetID`'s current position, shifting everything between. "All" never
-- moves, and nothing can land ahead of it in position 1 (dropping onto All
-- itself just means "right after All").
function Filters:MoveTabToPosition(id, targetID)
    if id == targetID or id == "ALL" then return end

    local order = GetTabOrderIDs()

    local fromIndex
    for i, tabID in ipairs(order) do
        if tabID == id then
            fromIndex = i
            break
        end
    end
    if not fromIndex then return end
    table.remove(order, fromIndex)

    local toIndex
    for i, tabID in ipairs(order) do
        if tabID == targetID then
            toIndex = i
            break
        end
    end

    if not toIndex then
        table.insert(order, id)
    else
        if toIndex == 1 and order[1] == "ALL" then
            toIndex = 2
        end
        table.insert(order, toIndex, id)
    end

    Embolsao.db.tabOrder = order
end

local function GenerateCustomTabID()
    return string.format("custom%d%03d", time(), math.random(0, 999))
end

function Filters:CreateCustomTab(data)
    local tab = {
        id = GenerateCustomTabID(),
        name = data.name,
        icon = data.icon,
        hiddenItemIDs = data.hiddenItemIDs or {},
        categoryRules = data.categoryRules or {},
    }
    table.insert(Embolsao.db.customTabs, tab)
    table.insert(Embolsao.db.tabOrder, tab.id)
    return tab
end

function Filters:UpdateCustomTab(id, data)
    local tab = self:GetCustomTab(id)
    if not tab then return end
    tab.name = data.name
    tab.icon = data.icon
    tab.hiddenItemIDs = data.hiddenItemIDs or {}
    tab.categoryRules = data.categoryRules or {}
end

function Filters:DeleteCustomTab(id)
    for i, tab in ipairs(Embolsao.db.customTabs) do
        if tab.id == id then
            table.remove(Embolsao.db.customTabs, i)
            break
        end
    end
    for i, orderedID in ipairs(Embolsao.db.tabOrder) do
        if orderedID == id then
            table.remove(Embolsao.db.tabOrder, i)
            break
        end
    end
    Embolsao.db.hiddenTabs[id] = nil
end

-- Item class/subclass name lookups for the custom-tab category picker.
-- Classes run 0-19; rather than hardcode that range (fragile if Blizzard
-- adds one), probe a generous 0-31 and keep whatever resolves to a name.
function Filters:GetItemClasses()
    local classes = {}
    for classID = 0, 31 do
        local name = C_Item.GetItemClassInfo(classID)
        if name then
            table.insert(classes, { classID = classID, name = name })
        end
    end
    return classes
end

function Filters:GetItemSubClasses(classID)
    local subClasses = {}
    for subClassID = 0, 31 do
        local name = C_Item.GetItemSubClassInfo(classID, subClassID)
        if name then
            table.insert(subClasses, { subClassID = subClassID, name = name })
        end
    end
    return subClasses
end
