local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

Embolsao.Filters = {}
local Filters = Embolsao.Filters

-- Tabs live in two independent sets, one per pane of the window: the bags' and
-- the bank's. Both are this same code: `Filters` is the bags' set, and
-- `Filters.bank` (bottom of the file) is a second instance with its own saved
-- data. Every method that touches saved data goes through self.keys -- which
-- db keys hold this set's custom tabs, hidden tabs, order and built-in
-- overrides -- and statePrefix, which keeps per-tab sort/collapse state apart
-- (the built-in "All" tab exists in both sets, so its ID alone would collide).
Filters.keys = {
    customTabs = "customTabs",
    hiddenTabs = "hiddenTabs",
    tabOrder = "tabOrder",
    builtInOverrides = "builtInOverrides",
    statePrefix = "",
}

local function GetClassIDs(itemID)
    local _, _, _, _, _, classID, subClassID = Embolsao.GetItemInfoInstant(itemID)
    return classID, subClassID
end

-- The only built-in tab. Every other tab (Weapons, Armor, Consumables...) used
-- to ship by default; they now start out as nothing and players build the
-- ones they want as custom tabs, so the tab bar is entirely theirs. "All"
-- stays because the view needs somewhere to land when no tab is left.
Filters.BuiltIn = {
    {
        id = "ALL",
        name = L.ALL,
        icon = "Interface\\Icons\\INV_Misc_Bag_08",
        predicate = function() return true end,
    },
}

-- Not a tab -- a special group UI.lua's BuildLayoutRows pins to the very top
-- of every tab (independent of the tab's own filter), the same way "Empty
-- Slots" gets pinned to the bottom. Seeded from
-- Blizzard's own "new item" flag (C_NewItems -- the green glow native bags
-- show on a freshly-acquired item, on Classic/TBC too) but tracked by us:
-- Core.lua's UpdateRecentItems copies the flag into a persisted per-character
-- set as soon as it's seen and stamps entry.isRecent, because Blizzard clears
-- the flag itself whenever a native container frame is hidden. An entry is
-- recent if ANY of its merged locations was flagged, since consolidating
-- stacks means a freshly-picked-up item might land in the same virtual entry
-- as an older one. Bank entries are never stamped, so never recent.
function Filters:IsEntryRecent(entry)
    return entry.isRecent == true
end

-- Same idea as Recent: a group pulled out of the active tab's entries and
-- pinned (just under Recent), not a tab. Grey-quality items in the bags;
-- Core.lua stamps entry.isJunk on every bag scan.
function Filters:IsEntryJunk(entry)
    return entry.isJunk == true
end

-- Same idea again: quest-starter items (not yet picked up) and items tied to
-- an in-progress quest. Core.lua's ScanBags stamps entry.questID/isQuestItem
-- (bags-only -- quests can't be turned in from the bank, same as Junk).
function Filters:IsEntryQuestItem(entry)
    return entry.questID ~= nil or entry.isQuestItem == true
end

function Filters:IsBuiltIn(id)
    for _, tab in ipairs(Filters.BuiltIn) do
        if tab.id == id then return true end
    end
    return false
end

-- The raw factory definition (name/icon/predicate) for a built-in tab --
-- unlike GetAllTabs()'s entries, this never reflects player customization.
function Filters:GetBuiltInDefinition(id)
    for _, tab in ipairs(Filters.BuiltIn) do
        if tab.id == id then return tab end
    end
    return nil
end

function Filters:GetBuiltInOverride(id)
    return Embolsao.db[self.keys.builtInOverrides][id]
end

function Filters:UpdateBuiltInOverride(id, data)
    if not self:IsBuiltIn(id) then return end
    Embolsao.db[self.keys.builtInOverrides][id] = {
        hiddenItemIDs = data.hiddenItemIDs or {},
        forcedItemIDs = data.forcedItemIDs or {},
        categoryRules = data.categoryRules or {},
        advancedFilters = data.advancedFilters or {},
    }
end

function Filters:ResetBuiltInOverride(id)
    Embolsao.db[self.keys.builtInOverrides][id] = nil
end

function Filters:GetCustomTab(id)
    for _, tab in ipairs(Embolsao.db[self.keys.customTabs]) do
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

-- Advanced filters (quality/itemLevel/stat conditions, set from TabEditor's
-- Advanced Filters section) are a separate layer from the category rules
-- above, not one more kind of category rule: category rules pick the single
-- MOST SPECIFIC match (a classification), but "quality >= Rare" and
-- "itemLevel > 200" aren't competing for specificity against each other --
-- they're independent criteria that must ALL hold at once. So every
-- condition is AND-ed, evaluated only after an item has already cleared the
-- category rules. A stat an item doesn't have reads as 0 (entry.stats only
-- carries the stats an item actually has), so "no Intellect" is just
-- "Intellect == 0" -- there's no separate "has"/"missing" concept to check.
local function CompareValue(value, operator, target)
    value = value or 0
    if operator == ">" then return value > target end
    if operator == ">=" then return value >= target end
    if operator == "<" then return value < target end
    if operator == "<=" then return value <= target end
    if operator == "~=" then return value ~= target end
    return value == target -- "==" and any unrecognized operator
end

function Filters:MatchesAdvancedFilters(entry, tab)
    local conditions = tab.advancedFilters
    if not conditions or #conditions == 0 then return true end

    for _, condition in ipairs(conditions) do
        local value
        if condition.type == "quality" then
            value = entry.quality
        elseif condition.type == "itemLevel" then
            value = entry.itemLevel
        elseif condition.type == "stat" then
            value = entry.stats and entry.stats[condition.statKey]
        end
        if not CompareValue(value, condition.operator, condition.value) then
            return false
        end
    end
    return true
end

-- A Gearset tab (see GearsetEditor.lua) is a strict whitelist, not a
-- classification: it shows ONLY the items the player dragged into its
-- "Items" list (stored in forcedItemIDs -- the same field a Filter tab uses
-- for "always show this regardless of rules", reused here since "only show
-- these" is that same idea with nothing else left to override). No category
-- rules, no advanced filters, no hidden items -- those sections don't even
-- show in the editor for this tab type, so there's nothing else to check.
function Filters:MatchesCustomTab(entry, tab)
    if tab.tabType == "gearset" then
        return tab.forcedItemIDs ~= nil and tab.forcedItemIDs[entry.itemID] == true
    end

    if tab.hiddenItemIDs and tab.hiddenItemIDs[entry.itemID] then
        return false
    end
    -- Forced items bypass everything below (category rules AND advanced
    -- filters) -- the whole point is to show a specific item regardless of
    -- what the tab would otherwise decide. Checked after hiddenItemIDs, not
    -- before: an item explicitly hidden stays hidden even if also forced,
    -- since hiding is the more explicit "never show this" intent.
    if tab.forcedItemIDs and tab.forcedItemIDs[entry.itemID] then
        return true
    end

    local rules = tab.categoryRules
    if not rules or #rules == 0 then
        return Filters:MatchesAdvancedFilters(entry, tab)
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

    local passesCategoryRules
    if bestRule then
        passesCategoryRules = bestRule.mode == "show"
    else
        passesCategoryRules = not hasShowRule
    end
    if not passesCategoryRules then return false end
    return Filters:MatchesAdvancedFilters(entry, tab)
end

-- Full tab list (built-in + custom), in the player's saved order, each
-- carrying `hidden`/`isBuiltIn` flags. Callers that want only what should
-- actually render as a clickable tab should use GetVisibleTabs() instead --
-- this one exists for management UIs (Preferences) that need to show
-- everything, hidden tabs included.
function Filters:GetAllTabs()
    local byID = {}

    for _, tab in ipairs(Filters.BuiltIn) do
        -- Narrows the factory predicate: an item still has to pass the
        -- built-in class check first, then the player's own hidden items /
        -- category rules on top of that. The override is looked up on every
        -- call, not captured here: tab lists get cached (the windows keep
        -- theirs until the next BuildTabs), and an override created after
        -- that -- e.g. by dragging an item onto a tab that had none yet --
        -- must still take effect immediately instead of after a reload.
        local function predicate(entry)
            if not tab.predicate(entry) then return false end
            local override = Embolsao.db[self.keys.builtInOverrides][tab.id]
            return override == nil or Filters:MatchesCustomTab(entry, override)
        end

        byID[tab.id] = {
            id = tab.id,
            name = tab.name,
            icon = tab.icon,
            predicate = predicate,
            isBuiltIn = true,
            hidden = Embolsao.db[self.keys.hiddenTabs][tab.id] == true,
        }
    end

    for _, customTab in ipairs(Embolsao.db[self.keys.customTabs]) do
        byID[customTab.id] = {
            id = customTab.id,
            name = customTab.name,
            icon = customTab.icon or "Interface\\Icons\\INV_Misc_Bag_10",
            predicate = function(entry) return Filters:MatchesCustomTab(entry, customTab) end,
            isBuiltIn = false,
            tabType = customTab.tabType or "filter", -- lets callers (TabEditor's Edit menu, tab buttons) route to the right editor / show a Gearset indicator without a separate lookup
            hidden = Embolsao.db[self.keys.hiddenTabs][customTab.id] == true,
        }
    end

    -- Respect saved order; anything not in it yet (freshly created, or an
    -- upgrade from before ordering existed) gets appended, built-ins first.
    local order, seen = {}, {}
    for _, id in ipairs(Embolsao.db[self.keys.tabOrder]) do
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
    for _, customTab in ipairs(Embolsao.db[self.keys.customTabs]) do
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
    Embolsao.db[self.keys.hiddenTabs][id] = hidden and true or nil
end

local function GetTabOrderIDs(filters)
    local order = {}
    for _, tab in ipairs(filters:GetAllTabs()) do
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

    local order = GetTabOrderIDs(self)

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
    Embolsao.db[self.keys.tabOrder] = order
end

-- Used by drag-to-reorder in the main window: moves `id` to sit right before
-- (placeAfter == false) or right after (placeAfter == true) `targetID`'s
-- current position. "All" never moves, and nothing can land ahead of it in
-- position 1 (dropping ahead of All just means "right after All").
function Filters:MoveTabRelative(id, targetID, placeAfter)
    if id == targetID or id == "ALL" then return end

    local order = GetTabOrderIDs(self)

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
        if placeAfter then
            toIndex = toIndex + 1
        end
        if toIndex <= 1 and order[1] == "ALL" then
            toIndex = 2
        end
        table.insert(order, toIndex, id)
    end

    Embolsao.db[self.keys.tabOrder] = order
end

local function GenerateCustomTabID()
    return string.format("custom%d%03d", time(), math.random(0, 999))
end

function Filters:CreateCustomTab(data)
    local tab = {
        id = GenerateCustomTabID(),
        name = data.name,
        icon = data.icon,
        tabType = data.tabType or "filter", -- fixed for the tab's lifetime, chosen only at creation (see GearsetEditor.lua)
        hiddenItemIDs = data.hiddenItemIDs or {},
        forcedItemIDs = data.forcedItemIDs or {},
        categoryRules = data.categoryRules or {},
        advancedFilters = data.advancedFilters or {},
    }
    table.insert(Embolsao.db[self.keys.customTabs], tab)
    table.insert(Embolsao.db[self.keys.tabOrder], tab.id)
    return tab
end

function Filters:UpdateCustomTab(id, data)
    local tab = self:GetCustomTab(id)
    if not tab then return end
    tab.name = data.name
    tab.icon = data.icon
    tab.hiddenItemIDs = data.hiddenItemIDs or {}
    tab.forcedItemIDs = data.forcedItemIDs or {}
    tab.categoryRules = data.categoryRules or {}
    tab.advancedFilters = data.advancedFilters or {}
end

function Filters:DeleteCustomTab(id)
    for i, tab in ipairs(Embolsao.db[self.keys.customTabs]) do
        if tab.id == id then
            table.remove(Embolsao.db[self.keys.customTabs], i)
            break
        end
    end
    for i, orderedID in ipairs(Embolsao.db[self.keys.tabOrder]) do
        if orderedID == id then
            table.remove(Embolsao.db[self.keys.tabOrder], i)
            break
        end
    end
    Embolsao.db[self.keys.hiddenTabs][id] = nil
    Embolsao.db.collapsedHeaders[self.keys.statePrefix .. id] = nil
    Embolsao.db.tabSort[self.keys.statePrefix .. id] = nil
end

-- Resolved hiddenItemIDs set for a tab (built-in override or custom),
-- or nil if that tab has no hidden items at all. Also used by
-- Layout.BuildLayoutRows to keep the pinned Recent/Junk/Quest Items groups
-- honoring Hidden Items -- those groups otherwise draw from every bag item
-- regardless of the active tab's own category rules (see the comment on
-- BuildLayoutRows), which used to mean a hidden item still showed up there.
function Filters:GetTabHiddenItemIDs(tabID)
    if self:IsBuiltIn(tabID) then
        local override = self:GetBuiltInOverride(tabID)
        return override and override.hiddenItemIDs
    end
    local tab = self:GetCustomTab(tabID)
    return tab and tab.hiddenItemIDs
end

function Filters:IsItemHiddenOnTab(tabID, itemID)
    local hiddenItemIDs = self:GetTabHiddenItemIDs(tabID)
    return hiddenItemIDs ~= nil and hiddenItemIDs[itemID] == true
end

-- Used by dragging an item straight onto a tab button in the main window --
-- a quicker shortcut than opening the tab editor's own drop zone. Works for
-- both custom tabs and (now that they support overrides) built-in ones.
function Filters:HideItemOnTab(tabID, itemID)
    if self:IsBuiltIn(tabID) then
        local override = self:GetBuiltInOverride(tabID)
        if not override then
            override = { hiddenItemIDs = {}, categoryRules = {}, advancedFilters = {} }
            Embolsao.db[self.keys.builtInOverrides][tabID] = override
        end
        override.hiddenItemIDs[itemID] = true
        return
    end

    local tab = self:GetCustomTab(tabID)
    if not tab then return end
    tab.hiddenItemIDs = tab.hiddenItemIDs or {}
    tab.hiddenItemIDs[itemID] = true
end

-- Item class/subclass name lookups for the custom-tab category picker.
-- Classes run 0-19; rather than hardcode that range (fragile if Blizzard
-- adds one), probe a generous 0-31 and keep whatever resolves to a name.
--
-- Both come back sorted by localized name -- Blizzard's IDs don't follow
-- alphabetical order (Consumable=0, Weapon=2, Armor=4...), so listing them in
-- ID order looked random. The pinned "All Categories" / "Any" choices are
-- added by the caller before these, so they stay first. strcmputf8i (where
-- the client has it) compares case- and accent-insensitively, which plain
-- "<" doesn't for non-English names.
local function CompareByName(a, b)
    if strcmputf8i then
        return strcmputf8i(a.name, b.name) < 0
    end
    return a.name:lower() < b.name:lower()
end

-- Blizzard keeps retired item classes around in the data with "(OBSOLETE)"
-- baked into their (localized) names -- Jewelry, Money, Permanent, Generic --
-- and no item can be in one anymore, so they only clutter the picker. Matched
-- on "obsol" so it also catches the translated spellings (OBSOLETO, ...).
local function IsObsoleteName(name)
    return name:lower():find("obsol", 1, true) ~= nil
end

function Filters:GetItemClasses()
    local classes = {}
    for classID = 0, 31 do
        local name = C_Item.GetItemClassInfo(classID)
        if name and not IsObsoleteName(name) then
            table.insert(classes, { classID = classID, name = name })
        end
    end
    table.sort(classes, CompareByName)
    return classes
end

function Filters:GetItemSubClasses(classID)
    local subClasses = {}
    for subClassID = 0, 31 do
        local name = C_Item.GetItemSubClassInfo(classID, subClassID)
        if name and not IsObsoleteName(name) then
            table.insert(subClasses, { subClassID = subClassID, name = name })
        end
    end
    table.sort(subClasses, CompareByName)
    return subClasses
end

-- The bank's own set of tabs: same behavior, separate saved data.
Filters.bank = setmetatable({
    keys = {
        customTabs = "bankCustomTabs",
        hiddenTabs = "bankHiddenTabs",
        tabOrder = "bankTabOrder",
        builtInOverrides = "bankBuiltInOverrides",
        statePrefix = "bank:",
    },
}, { __index = Filters })

-- The tab set a pane uses. domain is "bags" or "bank"; the bank only gets its
-- own set when Preferences -> "Separate tabs for Bank and Bags" is on --
-- otherwise both panes share the bags' tabs, as before.
function Embolsao:GetFilters(domain)
    if domain == "bank" and self.db.separateBankTabs then
        return Filters.bank
    end
    return Filters
end

-- Prefix for a pane's per-tab saved state (sort, collapsed categories), so the
-- two "All" tabs of separate sets don't share it.
function Embolsao:GetTabStatePrefix(domain)
    return self:GetFilters(domain).keys.statePrefix
end
