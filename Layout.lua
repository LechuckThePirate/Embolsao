-- Sorting, grouping and row layout for the item grid: the per-tab sort/grouping
-- settings, the comparators, the collapsed-header state and BuildLayoutRows,
-- which turns a tab's entries into the flat list of header / item / gap /
-- empty-slot rows the window then places. Pure data in, rows out -- no frames --
-- split out of UI.lua (see the file-size and Lua 5.1 local/upvalue limits
-- notes there). Everything is exported on Embolsao.Layout at the bottom.
local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

local UIC = Embolsao.UIConst
local ITEM_SIZE, ITEM_PADDING = UIC.ITEM_SIZE, UIC.ITEM_PADDING
local HEADER_ROW_HEIGHT, GROUP_GAP_HEIGHT = UIC.HEADER_ROW_HEIGHT, UIC.GROUP_GAP_HEIGHT

local Layout = {}
Embolsao.Layout = Layout

local SORT_MODES = {
    { id = "NAME", label = L.SORT_NAME },
    { id = "TYPE", label = L.SORT_TYPE },
    { id = "QUANTITY", label = L.SORT_QUANTITY },
    { id = "QUALITY", label = L.SORT_QUALITY },
}

-- Returns -1/0/1 for "a naturally comes before/tied/after b" regardless of
-- sort direction; the direction flag (sortAscending) is applied uniformly
-- afterward so every mode responds to the ascending/descending toggle the
-- same way, without each branch needing its own idea of "natural" order.
-- Sort mode/direction are remembered per tab (Embolsao.db.tabSort[tabID]); a
-- tab nobody has touched yet falls back to the global sortMode/sortAscending,
-- so whatever a player had chosen before this was per-tab carries over as
-- every tab's starting point. Shared between both windows, same as the tabs.
local function GetTabSort(tabID)
    local saved = Embolsao.db.tabSort[tabID]
    local mode = saved and saved.mode or Embolsao.db.sortMode
    local ascending
    if saved and saved.ascending ~= nil then
        ascending = saved.ascending
    else
        ascending = Embolsao.db.sortAscending
    end
    return mode, ascending
end

local function SetTabSort(tabID, mode, ascending)
    local currentMode, currentAscending = GetTabSort(tabID)
    local saved = Embolsao.db.tabSort[tabID] or {}
    -- Updated in place: the same entry also carries the tab's grouping.
    saved.mode = mode or currentMode
    saved.ascending = (ascending == nil) and currentAscending or ascending
    Embolsao.db.tabSort[tabID] = saved
end

-- Whether the category / subcategory headers show while the tab sorts by
-- category. Per tab, kept in the tab's sort entry (edited from the sort menu
-- and from the tab's own editor); a tab that hasn't been given its own gets
-- the global default (Embolsao.db.groupByClass / groupBySubClass).
local function GetTabGrouping(tabID)
    local saved = Embolsao.db.tabSort[tabID]
    local groupByClass, groupBySubClass = Embolsao.db.groupByClass, Embolsao.db.groupBySubClass
    if saved and saved.groupByClass ~= nil then groupByClass = saved.groupByClass end
    if saved and saved.groupBySubClass ~= nil then groupBySubClass = saved.groupBySubClass end
    return groupByClass == true, groupBySubClass == true
end

-- key: "groupByClass" or "groupBySubClass". The entry may have no sort mode of
-- its own yet -- GetTabSort falls back per field.
local function SetTabGrouping(tabID, key, value)
    local saved = Embolsao.db.tabSort[tabID] or {}
    saved[key] = value
    Embolsao.db.tabSort[tabID] = saved
end

-- Whether the pinned Recent and Junk groups show on the tab. Per tab too, in
-- the same entry; Preferences' "Show Recent / Junk category" is the default
-- for tabs that haven't chosen.
local function GetTabPinnedGroups(tabID)
    local saved = Embolsao.db.tabSort[tabID]
    local showRecent = Embolsao.db.showRecentCategory ~= false
    local showJunk = Embolsao.db.showJunkCategory ~= false
    if saved and saved.showRecent ~= nil then showRecent = saved.showRecent end
    if saved and saved.showJunk ~= nil then showJunk = saved.showJunk end
    return showRecent == true, showJunk == true
end

local function SetTabPinnedGroups(tabID, showRecent, showJunk)
    local saved = Embolsao.db.tabSort[tabID] or {}
    saved.showRecent = showRecent
    saved.showJunk = showJunk
    Embolsao.db.tabSort[tabID] = saved
end

local function NaturalCompare(a, b, mode)
    if mode == "QUANTITY" then
        if a.count ~= b.count then
            return a.count < b.count and -1 or 1
        end
    elseif mode == "QUALITY" then
        local qualityA, qualityB = a.quality or 0, b.quality or 0
        if qualityA ~= qualityB then
            return qualityA < qualityB and -1 or 1
        end
    elseif mode == "TYPE" then
        -- Compare by the localized class/subclass NAME, not the raw
        -- numeric classID -- Enum.ItemClass IDs don't run in alphabetical
        -- order (e.g. Consumable=0, Weapon=2, Armor=4), so sorting by ID
        -- produced a grouping order that looked arbitrary.
        local _, _, _, _, _, classA, subA = Embolsao.GetItemInfoInstant(a.itemID)
        local _, _, _, _, _, classB, subB = Embolsao.GetItemInfoInstant(b.itemID)
        local classNameA = classA and C_Item.GetItemClassInfo(classA) or ""
        local classNameB = classB and C_Item.GetItemClassInfo(classB) or ""
        if classNameA ~= classNameB then
            return classNameA < classNameB and -1 or 1
        end
        local subNameA = (classA and subA) and C_Item.GetItemSubClassInfo(classA, subA) or ""
        local subNameB = (classB and subB) and C_Item.GetItemSubClassInfo(classB, subB) or ""
        if subNameA ~= subNameB then
            return subNameA < subNameB and -1 or 1
        end
    else -- NAME (default)
        local nameA, nameB = Embolsao.GetItemInfo(a.itemID), Embolsao.GetItemInfo(b.itemID)
        if nameA and nameB and nameA ~= nameB then
            return nameA < nameB and -1 or 1
        end
    end

    return 0
end

-- itemID is always the tiebreaker (ascending, regardless of sort direction),
-- both for stability and as the fallback when the "real" sort data (name,
-- category) isn't available yet -- e.g. an item whose info hasn't been
-- cached client-side just falls back to itemID order until a later refresh.
local function MakeComparator(mode, ascending)
    return function(a, b)
        local natural = NaturalCompare(a, b, mode)
        if natural ~= 0 then
            if ascending then
                return natural < 0
            else
                return natural > 0
            end
        end
        return a.itemID < b.itemID
    end
end

-- Category order for grouping: by localized class name, and by subclass name
-- too when subcategories are grouped. Names, not IDs (see NaturalCompare).
local function CompareCategory(a, b, includeSubClass)
    local _, _, _, _, _, classA, subA = Embolsao.GetItemInfoInstant(a.itemID)
    local _, _, _, _, _, classB, subB = Embolsao.GetItemInfoInstant(b.itemID)
    local classNameA = classA and C_Item.GetItemClassInfo(classA) or ""
    local classNameB = classB and C_Item.GetItemClassInfo(classB) or ""
    if classNameA ~= classNameB then
        return classNameA < classNameB and -1 or 1
    end
    if includeSubClass then
        local subNameA = (classA and subA) and C_Item.GetItemSubClassInfo(classA, subA) or ""
        local subNameB = (classB and subB) and C_Item.GetItemSubClassInfo(classB, subB) or ""
        if subNameA ~= subNameB then
            return subNameA < subNameB and -1 or 1
        end
    end
    return 0
end

-- With grouping on, the groups come first: items are ordered by category (and
-- subcategory when those are grouped too), always A to Z so each group is one
-- contiguous run, and the tab's sort mode and direction only order the items
-- inside a group. Sorting BY category is already that order (its direction
-- then applies to the groups too), so it needs nothing extra.
local function MakeGroupedComparator(groupByClass, groupBySubClass, mode, ascending)
    local grouped = groupByClass or groupBySubClass
    if mode == "TYPE" then
        return function(a, b)
            local natural = NaturalCompare(a, b, "TYPE")
            if natural ~= 0 then
                return ascending and natural < 0 or (not ascending and natural > 0)
            end
            -- Same category: by name, so a category reads alphabetically
            -- rather than in itemID order.
            natural = NaturalCompare(a, b, "NAME")
            if natural ~= 0 then return natural < 0 end
            return a.itemID < b.itemID
        end
    end

    local within = MakeComparator(mode, ascending)
    if not grouped then return within end

    return function(a, b)
        -- Grouping by subcategory alone still nests under the class (its
        -- headers key off both), so the class is always compared first.
        local natural = CompareCategory(a, b, groupBySubClass)
        if natural ~= 0 then return natural < 0 end
        return within(a, b)
    end
end

-- Sort By Type collapse state, saved so it survives a reload instead of
-- resetting every time the bag opens. Preferences -> "Synchronize Category
-- Visibility" (default on) picks between one shared collapse state for
-- every tab, or a separate one remembered per tab. Shared between both
-- windows -- tabs themselves are shared, so their collapse state is too.
-- tabID: the calling window's own active tab (the two windows track theirs
-- independently).
local function GetCollapsedHeaders(tabID)
    if Embolsao.db.syncCategoryVisibility then
        return Embolsao.db.collapsedHeadersGlobal
    end

    local perTab = Embolsao.db.collapsedHeaders[tabID]
    if not perTab then
        perTab = {}
        Embolsao.db.collapsedHeaders[tabID] = perTab
    end
    return perTab
end

-- entries: whichever window's own UI:GetFilteredEntries() result invoked
-- this from its menu -- the collapse keys themselves are shared, but which
-- classes/subclasses actually exist to collapse depends on what that window
-- is currently looking at (bags vs. bank contents).
local function CollapseAllHeaders(entries, win)
    local collapsed = GetCollapsedHeaders(win.StateID(win.GetActiveTab()))
    for _, entry in ipairs(entries) do
        local _, _, _, _, _, classID, subClassID = Embolsao.GetItemInfoInstant(entry.itemID)
        collapsed["class:" .. classID] = true
        collapsed["sub:" .. classID .. ":" .. subClassID] = true
    end
    collapsed["emptyslots"] = true
    Embolsao.UI:Refresh()
end

local function ExpandAllHeaders(win)
    wipe(GetCollapsedHeaders(win.StateID(win.GetActiveTab())))
    Embolsao.UI:Refresh()
end

-- Builds a flat sequence of {kind="header", level=, text=} and
-- {kind="item", entry=} rows to lay out, only when sorted by Type and at
-- least one grouping preference is on. Headers only ever appear when the
-- class/subclass actually changes between two consecutive (already sorted)
-- entries -- since we never invent a header for a class/subclass with no
-- entries in the list, an empty one simply never gets one, in either
-- sort direction (ascending/descending just changes the order we walk in,
-- not how boundaries are detected). emptySlotGroups is passed in rather
-- than read from a single shared place -- bags and bank each have their own.
-- entries: what the active tab shows. pinnedSource: every bag item passing
-- the search box regardless of tab, which the pinned Recent/Junk groups draw from.
local function BuildLayoutRows(entries, pinnedSource, emptySlotGroups, tabID, tabName)
    local groupByClass, groupBySubClass = GetTabGrouping(tabID)
    local sortMode = GetTabSort(tabID)
    -- Grouping is independent of the sort mode: the entries arrive already
    -- ordered by category first (see win.GetFilteredEntries).
    local grouping = groupByClass or groupBySubClass
    local collapsed = GetCollapsedHeaders(tabID)

    local rows = {}

    -- "Recent" and then "Junk" are pinned first, regardless of sort mode AND
    -- of which tab is active: they draw from pinnedSource (every bag item
    -- that passes the search box), not from `entries` (what the active tab's
    -- own filter lets through) -- so a recent item shows up on a custom tab
    -- with strict category rules too, and Sell Junk always covers all the
    -- junk in the group. An item shows in a pinned group INSTEAD of its usual
    -- category, not in addition to it: Recent until dismissed (the small
    -- button on the item, see CreateRecentDismissButton), and an item that's
    -- both recent and grey belongs to Recent.
    local recentEntries, junkEntries, pinned = {}, {}, {}
    local showRecent, showJunk = GetTabPinnedGroups(tabID)
    if showRecent then
        for _, entry in ipairs(pinnedSource) do
            if Embolsao.Filters:IsEntryRecent(entry) then
                table.insert(recentEntries, entry)
                pinned[entry] = true
            end
        end
    end
    if showJunk then
        for _, entry in ipairs(pinnedSource) do
            if not pinned[entry] and Embolsao.Filters:IsEntryJunk(entry) then
                table.insert(junkEntries, entry)
                pinned[entry] = true
            end
        end
    end

    local remainingEntries = entries
    if next(pinned) ~= nil then
        remainingEntries = {}
        for _, entry in ipairs(entries) do
            if not pinned[entry] then
                table.insert(remainingEntries, entry)
            end
        end
    end
    local hasEmptySlots = emptySlotGroups and #emptySlotGroups > 0

    -- Without a break after a pinned group, whatever follows would either
    -- continue its last (partially filled) row -- when nothing is grouped --
    -- or sit flush against it, reading as part of the group either way.
    if #recentEntries > 0 then
        local key = "recentitems"
        local recentCollapsed = collapsed[key] == true
        table.insert(rows, {
            kind = "header", level = 0, key = key, collapsed = recentCollapsed,
            text = L.RECENT_ITEMS,
        })
        if not recentCollapsed then
            for _, entry in ipairs(recentEntries) do
                table.insert(rows, { kind = "item", entry = entry, isRecent = true })
            end
        end

        if #junkEntries > 0 or #remainingEntries > 0 or hasEmptySlots then
            table.insert(rows, { kind = "gap" })
        end
    end

    -- The Junk header carries the sell-all button (see GetOrCreateHeaderRow).
    if #junkEntries > 0 then
        local key = "junkitems"
        local junkCollapsed = collapsed[key] == true
        table.insert(rows, {
            kind = "header", level = 0, key = key, collapsed = junkCollapsed,
            text = L.JUNK_ITEMS,
        })
        if not junkCollapsed then
            for _, entry in ipairs(junkEntries) do
                table.insert(rows, { kind = "item", entry = entry })
            end
        end

        if #remainingEntries > 0 or hasEmptySlots then
            table.insert(rows, { kind = "gap" })
        end
    end

    if not grouping then
        -- Not grouped by category: everything that's left is one group named
        -- after the tab itself, so it reads as a section of its own under
        -- the pinned Recent/Junk groups instead of running on from them.
        -- Skipped only when there is nothing left to show (or no name).
        if tabName and #remainingEntries > 0 then
            local key = "tabitems"
            local tabCollapsed = collapsed[key] == true
            table.insert(rows, {
                kind = "header", level = 0, key = key, collapsed = tabCollapsed,
                text = tabName,
            })
            if not tabCollapsed then
                for _, entry in ipairs(remainingEntries) do
                    table.insert(rows, { kind = "item", entry = entry })
                end
            end
        else
            for _, entry in ipairs(remainingEntries) do
                table.insert(rows, { kind = "item", entry = entry })
            end
        end
    else
        local lastClassID, lastSubClassID = nil, nil
        local classCollapsed, subClassCollapsed = false, false
        for _, entry in ipairs(remainingEntries) do
            local _, _, _, _, _, classID, subClassID = Embolsao.GetItemInfoInstant(entry.itemID)

            if groupByClass and classID ~= lastClassID then
                local key = "class:" .. classID
                classCollapsed = collapsed[key] == true
                table.insert(rows, {
                    kind = "header", level = 0, key = key, collapsed = classCollapsed,
                    text = C_Item.GetItemClassInfo(classID) or "?",
                })
                lastSubClassID = nil -- force the subclass header to repeat under the new class
            end

            if groupBySubClass and (classID ~= lastClassID or subClassID ~= lastSubClassID) then
                local key = "sub:" .. classID .. ":" .. subClassID
                subClassCollapsed = collapsed[key] == true
                -- A collapsed class already hides everything under it -- no
                -- point also showing (or tracking clicks on) the subclass
                -- header it would otherwise contain.
                if not classCollapsed then
                    table.insert(rows, {
                        kind = "header", level = 1, key = key, collapsed = subClassCollapsed,
                        text = C_Item.GetItemSubClassInfo(classID, subClassID) or "?",
                    })
                end
            end

            if not classCollapsed and not subClassCollapsed then
                table.insert(rows, { kind = "item", entry = entry })
            end
            lastClassID, lastSubClassID = classID, subClassID
        end
    end

    -- Empty slots always come last -- one per emptySlotGroups entry (built
    -- in Core.lua: the shared "general" bucket plus one per special bag
    -- currently equipped), not tied to the active tab or to filtering, just
    -- "the place to drop new stacks". Sorted by Category gets them a header
    -- of their own so they don't read as part of whatever real category
    -- happened to sort last. Same treatment in every mode now, mirroring
    -- Recent at the top: a collapsible header of its own, set off from
    -- whatever comes before it by a gap (unless one is already there).
    if hasEmptySlots then
        if #rows > 0 and rows[#rows].kind ~= "gap" then
            table.insert(rows, { kind = "gap" })
        end

        local key = "emptyslots"
        local emptyCollapsed = collapsed[key] == true
        table.insert(rows, {
            kind = "header", level = 0, key = key, collapsed = emptyCollapsed,
            text = L.EMPTY_SLOTS_CATEGORY,
        })
        if not emptyCollapsed then
            for _, group in ipairs(emptySlotGroups) do
                table.insert(rows, { kind = "emptyslot", group = group })
            end
        end
    end

    return rows
end

-- Height BuildLayoutRows' rows take up at a given column count -- the same
-- running offset win.Refresh places the buttons by, minus the placing. It lets
-- Refresh find out whether the item grid overflows (and so needs its scrollbar,
-- which narrows the grid) before committing to a column count.
local function MeasureLayoutHeight(rows, itemsPerRow)
    local cell = ITEM_SIZE + ITEM_PADDING
    local yOffset, col = 0, 0
    for _, row in ipairs(rows) do
        if row.kind == "gap" or row.kind == "header" then
            if col > 0 then
                yOffset = yOffset + cell
                col = 0
            end
            yOffset = yOffset + (row.kind == "gap" and GROUP_GAP_HEIGHT or HEADER_ROW_HEIGHT)
        else
            col = col + 1
            if col >= itemsPerRow then
                col = 0
                yOffset = yOffset + cell
            end
        end
    end
    return yOffset + cell
end

Layout.SORT_MODES = SORT_MODES
Layout.GetTabSort = GetTabSort
Layout.SetTabSort = SetTabSort
Layout.GetTabGrouping = GetTabGrouping
Layout.SetTabGrouping = SetTabGrouping
Layout.GetTabPinnedGroups = GetTabPinnedGroups
Layout.SetTabPinnedGroups = SetTabPinnedGroups
Layout.MakeComparator = MakeComparator
Layout.MakeGroupedComparator = MakeGroupedComparator
Layout.GetCollapsedHeaders = GetCollapsedHeaders
Layout.CollapseAllHeaders = CollapseAllHeaders
Layout.ExpandAllHeaders = ExpandAllHeaders
Layout.BuildLayoutRows = BuildLayoutRows
Layout.MeasureLayoutHeight = MeasureLayoutHeight
