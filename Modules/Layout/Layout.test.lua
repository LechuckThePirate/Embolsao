dofile("setupTests.lua")

describe("Layout", function()
    local ns, Layout

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.loadAddon("Modules/Layout/Layout.lua")
        TestUtils.initDB()
        Layout = ns.Layout
        TestUtils.addItem(1, { name = "Bravo", quality = 2, classID = 2, subClassID = 7 })
        TestUtils.addItem(2, { name = "Alpha", quality = 4, classID = 4, subClassID = 1 })
        TestUtils.addItem(3, { name = "Charlie", quality = 1, classID = 2, subClassID = 15 })
    end)

    local function Sorted(entries, comparator)
        table.sort(entries, comparator)
        local ids = {}
        for _, entry in ipairs(entries) do table.insert(ids, entry.itemID) end
        return ids
    end

    local function Entries()
        return {
            { itemID = 1, count = 5, quality = 2 },
            { itemID = 2, count = 1, quality = 4 },
            { itemID = 3, count = 9, quality = 1 },
        }
    end

    describe("per-tab sort", function()
        it("a tab nobody touched uses the global sort", function()
            ns.db.sortMode, ns.db.sortAscending = "NAME", false
            local mode, ascending = Layout.GetTabSort("t1")
            assert.are.equal("NAME", mode)
            assert.is_false(ascending)
        end)

        it("remembers each tab's own sort, one field at a time", function()
            Layout.SetTabSort("t1", "QUALITY", nil)
            local mode, ascending = Layout.GetTabSort("t1")
            assert.are.equal("QUALITY", mode)
            assert.are.equal(ns.db.sortAscending, ascending)
            assert.are.equal("TYPE", (Layout.GetTabSort("t2")))
        end)

        it("grouping and pinned groups fall back to the Preferences defaults", function()
            ns.db.groupByClass = true
            assert.are.same({ true, false }, { Layout.GetTabGrouping("t1") })
            Layout.SetTabGrouping("t1", "groupByClass", false)
            assert.are.same({ false, false }, { Layout.GetTabGrouping("t1") })

            assert.are.same({ true, true, true }, { Layout.GetTabPinnedGroups("t1") })
            Layout.SetTabPinnedGroups("t1", false, true, false)
            assert.are.same({ false, true, false }, { Layout.GetTabPinnedGroups("t1") })
        end)
    end)

    describe("comparators", function()
        it("sorts by name", function()
            assert.are.same({ 2, 1, 3 }, Sorted(Entries(), Layout.MakeComparator("NAME", true)))
            assert.are.same({ 3, 1, 2 }, Sorted(Entries(), Layout.MakeComparator("NAME", false)))
        end)

        it("sorts by quantity and by quality", function()
            assert.are.same({ 2, 1, 3 }, Sorted(Entries(), Layout.MakeComparator("QUANTITY", true)))
            assert.are.same({ 2, 1, 3 }, Sorted(Entries(), Layout.MakeComparator("QUALITY", false)))
        end)

        it("sorts by category name, not by class ID", function()
            -- Armor (4) before Weapon (2); within Weapon, Daggers before One-Handed Swords.
            assert.are.same({ 2, 3, 1 }, Sorted(Entries(), Layout.MakeComparator("TYPE", true)))
        end)

        it("falls back to itemID when the items tie", function()
            local entries = { { itemID = 9, count = 1 }, { itemID = 8, count = 1 } }
            assert.are.same({ 8, 9 }, Sorted(entries, Layout.MakeComparator("QUANTITY", false)))
        end)

        it("groups by category first, then sorts within each group", function()
            local comparator = Layout.MakeGroupedComparator(true, false, "QUANTITY", false)
            assert.are.same({ 2, 3, 1 }, Sorted(Entries(), comparator))
        end)
    end)

    describe("BuildLayoutRows", function()
        local function Kinds(rows)
            local kinds = {}
            for _, row in ipairs(rows) do
                table.insert(kinds, row.kind == "header" and ("header:" .. row.key) or row.kind)
            end
            return kinds
        end

        it("without grouping, the tab's items sit under a header named after it", function()
            local rows = Layout.BuildLayoutRows(Entries(), {}, {}, "t1", "My Tab")
            assert.are.same({ "header:tabitems", "item", "item", "item" }, Kinds(rows))
            assert.are.equal("My Tab", rows[1].text)
        end)

        it("pins Recent, then Junk, then Quest Items, each set off by a gap", function()
            local recent = { itemID = 1, isRecent = true }
            local junk = { itemID = 2, isJunk = true }
            local quest = { itemID = 3, questID = 10 }
            local other = { itemID = 4 }
            local all = { recent, junk, quest, other }
            local rows = Layout.BuildLayoutRows(all, all, {}, "t1", "Tab")
            assert.are.same({
                "header:recentitems", "item", "gap",
                "header:junkitems", "item", "gap",
                "header:questitems", "item", "gap",
                "header:tabitems", "item",
            }, Kinds(rows))
        end)

        it("a recent grey item shows once, under Recent", function()
            local both = { itemID = 1, isRecent = true, isJunk = true }
            local rows = Layout.BuildLayoutRows({ both }, { both }, {}, "t1", "Tab")
            assert.are.same({ "header:recentitems", "item" }, Kinds(rows))
        end)

        it("pinned groups still honor the tab's Hidden Items", function()
            local recent = { itemID = 1, isRecent = true }
            local rows = Layout.BuildLayoutRows({}, { recent }, {}, "t1", "Tab", { [1] = true })
            assert.are.same({}, Kinds(rows))
        end)

        it("a collapsed header hides its items", function()
            Layout.GetCollapsedHeaders("t1").tabitems = true
            local rows = Layout.BuildLayoutRows(Entries(), {}, {}, "t1", "Tab")
            assert.are.same({ "header:tabitems" }, Kinds(rows))
            assert.is_true(rows[1].collapsed)
        end)

        it("grouping adds class and subclass headers where they change", function()
            Layout.SetTabGrouping("t1", "groupByClass", true)
            Layout.SetTabGrouping("t1", "groupBySubClass", true)
            local entries = Entries()
            table.sort(entries, Layout.MakeGroupedComparator(true, true, "NAME", true))
            local rows = Layout.BuildLayoutRows(entries, {}, {}, "t1", "Tab")
            assert.are.same({
                "header:class:4", "header:sub:4:1", "item",
                "header:class:2", "header:sub:2:15", "item", "header:sub:2:7", "item",
            }, Kinds(rows))
        end)

        it("empty slots come last under their own header", function()
            local rows = Layout.BuildLayoutRows({ { itemID = 1 } }, {}, { { id = "general" } }, "t1", "Tab")
            assert.are.same({ "header:tabitems", "item", "gap", "header:emptyslots", "emptyslot" }, Kinds(rows))
        end)

        it("a gearset tab shows its status groups and no empty slots", function()
            local groups = { equipped = { { itemID = 5 } }, unavailable = {}, previouslyEquipped = { { itemID = 6 } } }
            local rows = Layout.BuildLayoutRows({ { itemID = 1 } }, {}, { { id = "general" } }, "t1", "Set", nil, groups)
            assert.are.same({
                "header:tabitems", "item", "gap",
                "header:gearsetequipped", "item", "gap",
                "header:gearsetpreviousequipped", "item",
            }, Kinds(rows))
            assert.is_true(rows[#rows - 1].gearsetDismissible)
        end)

        it("another character's gear leads the alt viewer", function()
            local rows = Layout.BuildLayoutRows({ { itemID = 1 } }, {}, {}, "t1", "Tab", nil, nil, { { itemID = 9 } })
            assert.are.same({ "header:viewedequipment", "item", "gap", "header:tabitems", "item" }, Kinds(rows))
        end)
    end)

    describe("collapsed headers", function()
        it("are shared by every tab while Synchronize Category Visibility is on", function()
            ns.db.syncCategoryVisibility = true
            assert.are.equal(Layout.GetCollapsedHeaders("a"), Layout.GetCollapsedHeaders("b"))
        end)

        it("are kept per tab when it's off", function()
            ns.db.syncCategoryVisibility = false
            assert.are_not.equal(Layout.GetCollapsedHeaders("a"), Layout.GetCollapsedHeaders("b"))
        end)
    end)

    describe("MeasureLayoutHeight", function()
        it("wraps items into rows and adds header and gap heights", function()
            local C = ns.UIConst
            local cell = C.ITEM_SIZE + C.ITEM_PADDING
            local rows = {
                { kind = "header" }, { kind = "item" }, { kind = "item" }, { kind = "item" },
                { kind = "gap" }, { kind = "item" },
            }
            -- header, 2 full-width rows at 2 per row (2 + 1 items), gap, one last row.
            local expected = C.HEADER_ROW_HEIGHT + cell + cell + C.GROUP_GAP_HEIGHT + cell
            assert.are.equal(expected, Layout.MeasureLayoutHeight(rows, 2))
        end)
    end)
end)
