dofile("setupTests.lua")

describe("Filters", function()
    local ns, Filters

    -- classID 2 = Weapon (7 = swords, 15 = daggers), 4 = Armor, 0 = Consumable
    local SWORD, DAGGER, CLOTH, POTION = 1, 2, 3, 4

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.loadAddon("Modules/Filters/Filters.lua")
        TestUtils.initDB()
        Filters = ns.Filters
        TestUtils.addItem(SWORD, { classID = 2, subClassID = 7 })
        TestUtils.addItem(DAGGER, { classID = 2, subClassID = 15 })
        TestUtils.addItem(CLOTH, { classID = 4, subClassID = 1 })
        TestUtils.addItem(POTION, { classID = 0, subClassID = 1 })
    end)

    local function Entry(itemID, extra)
        local entry = { itemID = itemID }
        for k, v in pairs(extra or {}) do entry[k] = v end
        return entry
    end

    describe("MatchesCustomTab", function()
        it("a tab with no rules shows everything", function()
            assert.is_true(Filters:MatchesCustomTab(Entry(SWORD), {}))
        end)

        it("a show rule turns the tab into a whitelist", function()
            local tab = { categoryRules = { { classID = 2, mode = "show" } } }
            assert.is_true(Filters:MatchesCustomTab(Entry(SWORD), tab))
            assert.is_false(Filters:MatchesCustomTab(Entry(CLOTH), tab))
        end)

        it("only hide rules leave it a blocklist", function()
            local tab = { categoryRules = { { classID = 2, mode = "hide" } } }
            assert.is_false(Filters:MatchesCustomTab(Entry(SWORD), tab))
            assert.is_true(Filters:MatchesCustomTab(Entry(CLOTH), tab))
        end)

        it("the most specific rule wins", function()
            local tab = { categoryRules = {
                { classID = 2, subClassID = 15, mode = "hide" },
                { classID = 2, mode = "show" },
            } }
            assert.is_true(Filters:MatchesCustomTab(Entry(SWORD), tab))
            assert.is_false(Filters:MatchesCustomTab(Entry(DAGGER), tab))
        end)

        it("All Categories is the least specific rule", function()
            local tab = { categoryRules = {
                { classID = Filters.ALL_CATEGORIES, mode = "show" },
                { classID = 2, subClassID = 7, mode = "hide" },
            } }
            assert.is_false(Filters:MatchesCustomTab(Entry(SWORD), tab))
            assert.is_true(Filters:MatchesCustomTab(Entry(POTION), tab))
        end)

        it("hidden items beat forced items", function()
            local tab = { hiddenItemIDs = { [SWORD] = true }, forcedItemIDs = { [SWORD] = true } }
            assert.is_false(Filters:MatchesCustomTab(Entry(SWORD), tab))
        end)

        it("the eye button lifts hidden items", function()
            ns.ShowHiddenItems = true
            local tab = { hiddenItemIDs = { [SWORD] = true } }
            assert.is_true(Filters:MatchesCustomTab(Entry(SWORD), tab))
        end)

        it("forced items bypass the category rules", function()
            local tab = { forcedItemIDs = { [CLOTH] = true }, categoryRules = { { classID = 2, mode = "show" } } }
            assert.is_true(Filters:MatchesCustomTab(Entry(CLOTH), tab))
        end)

        it("a gearset tab shows exactly its items", function()
            local tab = { tabType = "gearset", forcedItemIDs = { [SWORD] = true } }
            assert.is_true(Filters:MatchesCustomTab(Entry(SWORD), tab))
            assert.is_false(Filters:MatchesCustomTab(Entry(DAGGER), tab))
        end)
    end)

    describe("MatchesAdvancedFilters", function()
        it("every condition must hold", function()
            local tab = { advancedFilters = {
                { type = "quality", operator = ">=", value = 3 },
                { type = "itemLevel", operator = ">", value = 200 },
            } }
            assert.is_true(Filters:MatchesAdvancedFilters(Entry(SWORD, { quality = 4, itemLevel = 210 }), tab))
            assert.is_false(Filters:MatchesAdvancedFilters(Entry(SWORD, { quality = 4, itemLevel = 190 }), tab))
            assert.is_false(Filters:MatchesAdvancedFilters(Entry(SWORD, { quality = 2, itemLevel = 210 }), tab))
        end)

        it("a stat the item doesn't have reads as 0", function()
            local tab = { advancedFilters = { { type = "stat", statKey = "ITEM_MOD_INTELLECT_SHORT", operator = "==", value = 0 } } }
            assert.is_true(Filters:MatchesAdvancedFilters(Entry(SWORD, { stats = {} }), tab))
            assert.is_false(Filters:MatchesAdvancedFilters(Entry(SWORD, { stats = { ITEM_MOD_INTELLECT_SHORT = 5 } }), tab))
        end)
    end)

    describe("pinned-group flags", function()
        it("reads the stamps Core puts on entries", function()
            assert.is_true(Filters:IsEntryRecent({ isRecent = true }))
            assert.is_true(Filters:IsEntryJunk({ isJunk = true }))
            assert.is_true(Filters:IsEntryQuestItem({ questID = 1 }))
            assert.is_true(Filters:IsEntryQuestItem({ isQuestItem = true }))
            assert.is_false(Filters:IsEntryQuestItem({}))
        end)
    end)

    describe("tabs", function()
        local function IDs(tabs)
            local ids = {}
            for _, tab in ipairs(tabs) do table.insert(ids, tab.id) end
            return ids
        end

        it("starts with just All", function()
            assert.are.same({ "ALL" }, IDs(Filters:GetAllTabs()))
        end)

        it("appends new custom tabs in creation order", function()
            local a = Filters:CreateCustomTab({ name = "A" })
            local b = Filters:CreateCustomTab({ name = "B" })
            assert.are.same({ "ALL", a.id, b.id }, IDs(Filters:GetAllTabs()))
            assert.are.equal("filter", a.tabType)
        end)

        it("All stays first and visible, even against bad saved data", function()
            local a = Filters:CreateCustomTab({ name = "A" })
            ns.db.tabOrder = { a.id, "ALL" }
            ns.db.hiddenTabs.ALL = true
            local tabs = Filters:GetAllTabs()
            assert.are.equal("ALL", tabs[1].id)
            assert.is_false(tabs[1].hidden)
        end)

        it("hidden tabs are listed but not visible", function()
            local a = Filters:CreateCustomTab({ name = "A" })
            Filters:SetTabHidden(a.id, true)
            assert.are.same({ "ALL" }, IDs(Filters:GetVisibleTabs()))
            Filters:SetTabHidden("ALL", true)
            assert.are.same({ "ALL" }, IDs(Filters:GetVisibleTabs()))
        end)

        it("MoveTab swaps neighbours but never moves past All", function()
            local a = Filters:CreateCustomTab({ name = "A" })
            local b = Filters:CreateCustomTab({ name = "B" })
            Filters:MoveTab(b.id, -1)
            assert.are.same({ "ALL", b.id, a.id }, IDs(Filters:GetAllTabs()))
            Filters:MoveTab(b.id, -1)
            assert.are.same({ "ALL", b.id, a.id }, IDs(Filters:GetAllTabs()))
        end)

        it("MoveTabRelative drops before/after a target, never ahead of All", function()
            local a = Filters:CreateCustomTab({ name = "A" })
            local b = Filters:CreateCustomTab({ name = "B" })
            local c = Filters:CreateCustomTab({ name = "C" })
            Filters:MoveTabRelative(c.id, a.id, false)
            assert.are.same({ "ALL", c.id, a.id, b.id }, IDs(Filters:GetAllTabs()))
            Filters:MoveTabRelative(b.id, "ALL", false)
            assert.are.same({ "ALL", b.id, c.id, a.id }, IDs(Filters:GetAllTabs()))
        end)

        it("deleting a tab removes its order, hidden flag and saved state", function()
            local a = Filters:CreateCustomTab({ name = "A" })
            Filters:SetTabHidden(a.id, true)
            ns.db.tabSort[a.id] = { mode = "NAME" }
            Filters:DeleteCustomTab(a.id)
            assert.is_nil(Filters:GetCustomTab(a.id))
            assert.are.same({}, ns.db.tabOrder)
            assert.is_nil(ns.db.hiddenTabs[a.id])
            assert.is_nil(ns.db.tabSort[a.id])
        end)

        it("hiding an item on All creates its override on the spot", function()
            Filters:HideItemOnTab("ALL", SWORD)
            assert.is_true(Filters:IsItemHiddenOnTab("ALL", SWORD))
            local all = Filters:GetAllTabs()[1]
            assert.is_false(all.predicate(Entry(SWORD)))
            assert.is_true(all.predicate(Entry(DAGGER)))
        end)

        it("gearset tabs marked hide-from-bags contribute their items", function()
            assert.is_nil(Filters:GetGearsetHiddenItemIDs())
            Filters:CreateCustomTab({ name = "G", tabType = "gearset", hideFromBags = true, forcedItemIDs = { [SWORD] = true } })
            assert.are.same({ [SWORD] = true }, Filters:GetGearsetHiddenItemIDs())
        end)
    end)

    describe("bank tab set", function()
        it("keeps its own tabs apart from the bags'", function()
            ns.Filters.bank:CreateCustomTab({ name = "Bank" })
            assert.are.equal(1, #ns.db.bankCustomTabs)
            assert.are.equal(0, #ns.db.customTabs)
        end)

        it("is only used while Separate tabs is on", function()
            ns.db.separateBankTabs = true
            assert.are.equal(Filters.bank, ns:GetFilters("bank"))
            assert.are.equal("bank:", ns:GetTabStatePrefix("bank"))
            ns.db.separateBankTabs = false
            assert.are.equal(Filters, ns:GetFilters("bank"))
        end)
    end)

    describe("category pickers", function()
        it("lists item classes sorted by name, without obsolete ones", function()
            local original = C_Item.GetItemClassInfo
            C_Item.GetItemClassInfo = function(classID)
                if classID == 3 then return "Jewelry (OBSOLETE)" end
                return original(classID)
            end
            local names = {}
            for _, class in ipairs(Filters:GetItemClasses()) do table.insert(names, class.name) end
            assert.are.same({ "Armor", "Consumable", "Container", "Miscellaneous", "Quest", "Reagent", "Tradeskill", "Weapon" }, names)
        end)
    end)
end)
