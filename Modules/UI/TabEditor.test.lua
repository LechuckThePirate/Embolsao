dofile("setupTests.lua")

describe("TabEditor", function()
    local ns, TabEditor

    before_each(function()
        TestUtils.resetEnvironment()
        TestUtils.addItem(10, { name = "Sword", classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON" })
        TestUtils.setBag(0, 4, { [1] = { itemID = 10 } })
        ns = TestUtils.startAddon()
        ns:ScanBags()
        TabEditor = ns.TabEditor
    end)

    local function TabData(id)
        for _, tab in ipairs(ns.Filters:GetAllTabs()) do
            if tab.id == id then return tab end
        end
    end

    describe("editor windows", function()
        it("opens the type chooser for a new tab", function()
            assert.has_no.errors(function() TabEditor:ShowTypeChooser("bags") end)
        end)

        it("opens a new filter tab", function()
            assert.has_no.errors(function() TabEditor:Show(nil, "bags", "filter") end)
        end)

        it("opens a new gearset tab", function()
            assert.has_no.errors(function() TabEditor:Show(nil, "bags", "gearset") end)
        end)

        it("opens an existing custom tab, and the built-in All", function()
            local tab = ns.Filters:CreateCustomTab({ name = "Weapons", categoryRules = { { classID = 2, mode = "show" } } })
            assert.has_no.errors(function() TabEditor:Show(tab.id, "bags") end)
            assert.has_no.errors(function() TabEditor:Show("ALL", "bags") end)
        end)

        it("opens the icon picker", function()
            assert.has_no.errors(function() TabEditor:ShowIconPicker(function() end, "Weapons") end)
        end)
    end)

    describe("tab context menu", function()
        it("All can be edited but not hidden or deleted", function()
            TabEditor:ShowTabContextMenu(nil, TabData("ALL"), "bags")
            local find = TestUtils.state.findMenuEntry
            assert.is_not_nil(find(ns.L.TAB_EDIT))
            assert.is_nil(find(ns.L.TAB_HIDE))
            assert.is_nil(find(ns.L.TAB_DELETE))
        end)

        it("a custom tab can be hidden and deleted", function()
            local tab = ns.Filters:CreateCustomTab({ name = "Mine" })
            TabEditor:ShowTabContextMenu(nil, TabData(tab.id), "bags")
            local hide = TestUtils.state.findMenuEntry(ns.L.TAB_HIDE)
            assert.is_not_nil(TestUtils.state.findMenuEntry(ns.L.TAB_DELETE))
            hide.a()
            assert.is_true(ns.db.hiddenTabs[tab.id])
        end)

        it("delete asks for confirmation first", function()
            local tab = ns.Filters:CreateCustomTab({ name = "Mine" })
            TabEditor:ShowTabContextMenu(nil, TabData(tab.id), "bags")
            TestUtils.state.findMenuEntry(ns.L.TAB_DELETE).a()
            assert.are.equal("EMBOLSAO_DELETE_TAB", TestUtils.calls("StaticPopup_Show")[1][1])
            assert.is_not_nil(ns.Filters:GetCustomTab(tab.id))
        end)

        it("a gearset with items in the bags offers Equip", function()
            local tab = ns.Filters:CreateCustomTab({ name = "Set", tabType = "gearset", forcedItemIDs = { [10] = true } })
            TabEditor:ShowTabContextMenu(nil, TabData(tab.id), "bags")
            assert.is_not_nil(TestUtils.state.findMenuEntry(ns.L.GEARSET_EQUIP))
        end)

        it("an empty gearset offers Equip while anything is worn", function()
            TestUtils.state.equipped[1] = 10
            local tab = ns.Filters:CreateCustomTab({ name = "Naked", tabType = "gearset" })
            TabEditor:ShowTabContextMenu(nil, TabData(tab.id), "bags")
            assert.is_not_nil(TestUtils.state.findMenuEntry(ns.L.GEARSET_EQUIP))
        end)

        it("a gearset with nothing available offers neither Equip nor Unequip", function()
            local tab = ns.Filters:CreateCustomTab({ name = "Set", tabType = "gearset", forcedItemIDs = { [99] = true } })
            TabEditor:ShowTabContextMenu(nil, TabData(tab.id), "bags")
            assert.is_nil(TestUtils.state.findMenuEntry(ns.L.GEARSET_EQUIP))
            assert.is_nil(TestUtils.state.findMenuEntry(ns.L.GEARSET_UNEQUIP))
        end)
    end)

    describe("hiding an item by dropping it on a tab", function()
        it("asks before hiding", function()
            TabEditor:ConfirmHideItemOnTab(10, TabData("ALL"), "bags")
            local call = TestUtils.calls("StaticPopup_Show")[1]
            assert.are.equal("EMBOLSAO_HIDE_ITEM_ON_TAB", call[1])
            assert.are.equal("Sword", call[2])
        end)

        it("doesn't ask again for an item already hidden there", function()
            ns.Filters:HideItemOnTab("ALL", 10)
            TabEditor:ConfirmHideItemOnTab(10, TabData("ALL"), "bags")
            assert.are.equal(0, #TestUtils.calls("StaticPopup_Show"))
        end)

        it("accepting the popup hides it", function()
            StaticPopupDialogs.EMBOLSAO_HIDE_ITEM_ON_TAB.OnAccept(nil, { itemID = 10, tabID = "ALL", domain = "bags" })
            assert.is_true(ns.Filters:IsItemHiddenOnTab("ALL", 10))
        end)
    end)
end)
