dofile("setupTests.lua")

describe("UI", function()
    local ns, UI

    before_each(function()
        TestUtils.resetEnvironment()
        TestUtils.addItem(10, { name = "Sword", quality = 3, classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON" })
        TestUtils.addItem(20, { name = "Rag", quality = 0, classID = 15, subClassID = 0 })
        TestUtils.setBag(0, 16, {
            [1] = { itemID = 10 },
            [2] = { itemID = 20, stackCount = 3 },
            [3] = { itemID = 20, stackCount = 2, isNew = true },
        })
        ns = TestUtils.startAddon()
        UI = ns.UI
        ns:ScanBags()
    end)

    it("builds both windows at load", function()
        assert.is_not_nil(UI.bagsWindow)
        assert.is_not_nil(UI.bankWindow)
    end)

    it("opens the bags and lays out the items without errors", function()
        assert.has_no.errors(function()
            UI.bagsWindow.OpenDirect()
            UI:BuildTabs()
            UI:Refresh()
        end)
        assert.is_true(UI.bagsWindow.IsShown())
        -- One item button per entry got its icon.
        local textured = 0
        for _, frame in ipairs(TestUtils.state.frames) do
            if frame.__frameType == "ItemButton" and frame.__texture then textured = textured + 1 end
        end
        assert.is_true(textured >= 2, "item buttons drawn: " .. textured)
    end)

    it("lays out every sort mode, grouped and not", function()
        UI.bagsWindow.OpenDirect()
        for _, mode in ipairs(UI:GetSortModes()) do
            UI:SetTabSort("ALL", mode.id, true)
            UI:SetTabGrouping("ALL", true, true)
            assert.has_no.errors(function() UI:Refresh() end, mode.id)
            UI:SetTabGrouping("ALL", false, false)
            assert.has_no.errors(function() UI:Refresh() end, mode.id)
        end
    end)

    it("lays out a gearset tab", function()
        ns.Filters:CreateCustomTab({ name = "Set", tabType = "gearset", forcedItemIDs = { [10] = true, [99] = true } })
        UI.bagsWindow.OpenDirect()
        assert.has_no.errors(function() UI:BuildTabs() end)
    end)

    it("the tab-editor accessors go through Layout", function()
        UI:SetTabSort("t1", "NAME", false)
        assert.are.same({ "NAME", false }, { UI:GetTabSort("t1") })
        UI:SetTabPinnedGroups("t1", false, false, true)
        assert.are.same({ false, false, true }, { UI:GetTabPinnedGroups("t1") })
    end)

    it("the eye button toggles showing hidden items", function()
        assert.is_falsy(ns.ShowHiddenItems)
        UI.ToggleShowHidden()
        assert.is_true(ns.ShowHiddenItems)
        UI.ToggleShowHidden()
        assert.is_false(ns.ShowHiddenItems)
    end)

    it("disabling saves the choice and closes the windows", function()
        UI.bagsWindow.OpenDirect()
        UI:SetDisabled(true)
        assert.is_true(ns.db.disabled)
        UI:SetDisabled(false)
        assert.is_false(ns.db.disabled)
    end)

    describe("offline bank", function()
        it("has nothing to show before any visit to a banker", function()
            assert.is_nil(UI.GetOfflineStartView())
        end)

        it("opens on the personal bank, or the Warband one if that's all there is", function()
            ns:SaveBankSnapshot("WARBAND", { 12 }, {})
            assert.are.equal("WARBAND", UI.GetOfflineStartView())
            ns:SaveBankSnapshot("PERSONAL", { 6 }, {})
            assert.are.equal("PERSONAL", UI.GetOfflineStartView())
        end)

        it("toggles the saved copy on and off", function()
            ns:SaveBankSnapshot("PERSONAL", { 6 }, { [6] = { n = 4, slots = { [1] = { i = 10, c = 1 } } } })
            UI.ToggleOfflineBank()
            assert.is_true(ns.BankOffline)
            assert.are.equal(1, ns.BankVirtualInventory[10].count)
            UI.ToggleOfflineBank()
            assert.is_false(ns.BankOffline)
        end)

        it("turning Offline Bank off drops the saved copies", function()
            ns:SaveBankSnapshot("PERSONAL", { 6 }, {})
            ns:SaveBankSnapshot("WARBAND", { 12 }, {})
            ns.db.offlineBank = false
            UI:RefreshOfflineBank()
            assert.is_nil(EmbolsaoCharDB.bankSnapshot)
            assert.is_nil(EmbolsaoDB.warbandBankSnapshot)
        end)
    end)

    describe("at the banker", function()
        it("opening and closing the bank tracks where the player is", function()
            TestUtils.fireEvent("BANKFRAME_OPENED")
            assert.is_true(ns.AtBank)
            TestUtils.fireEvent("BANKFRAME_CLOSED")
            assert.is_false(ns.AtBank)
            assert.are.equal("PERSONAL", ns.BankViewMode)
        end)

        it("a banker ends the offline view", function()
            ns:SaveBankSnapshot("PERSONAL", { 6 }, {})
            UI.ToggleOfflineBank()
            TestUtils.fireEvent("BANKFRAME_OPENED")
            assert.is_false(ns.BankOffline)
        end)

        it("offers no deposit-all away from a retail banker", function()
            assert.is_nil(UI.GetDepositBankType())
        end)
    end)

    describe("alt viewer", function()
        before_each(function()
            TestUtils.addItem(30, { name = "Alt's thing" })
            EmbolsaoDB.characterItems = {
                ["Alt-TestRealm"] = {
                    name = "Alt", class = "MAGE", time = 1,
                    bagsSnapshot = { bagIDs = { 0 }, bags = { [0] = { n = 2, slots = { [1] = { i = 30, c = 2 } } } } },
                },
            }
        end)

        it("offers the other characters in the window's menu", function()
            MenuUtil.CreateContextMenu(nil, function(_, root) UI.BuildViewCharacterMenu(root) end)
            assert.is_not_nil(TestUtils.state.findMenuEntry(ns.L.VIEW_CHARACTER))
        end)

        it("shows another character's bags, then your own again", function()
            UI.bagsWindow.OpenDirect()
            UI.ViewCharacter("Alt-TestRealm")
            assert.are.equal("Alt-TestRealm", ns.ViewChar)
            assert.are.equal(2, ns.AltInventory[30].count)
            UI.ViewCharacter(nil)
            assert.is_nil(ns.ViewChar)
        end)

        it("can't switch characters at a banker", function()
            TestUtils.fireEvent("BANKFRAME_OPENED")
            UI.ViewCharacter("Alt-TestRealm")
            assert.is_nil(ns.ViewChar)
        end)
    end)
end)
