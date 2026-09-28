dofile("setupTests.lua")

describe("Gearset", function()
    local ns, Gearset

    local HELM, RING_A, RING_B, RING_C, TWO_HANDER, DAGGER_A, DAGGER_B, SHIELD, POTION =
        1, 2, 3, 4, 5, 6, 7, 8, 9

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.loadAddon("Modules/Gearset/Gearset.lua")
        TestUtils.initDB()
        -- Gearset refreshes the windows once a swap settles; not under test here.
        ns.UI = { BuildTabs = function() end, Refresh = function() end }
        Gearset = ns.Gearset
        TestUtils.addItem(HELM, { equipLoc = "INVTYPE_HEAD" })
        TestUtils.addItem(RING_A, { equipLoc = "INVTYPE_FINGER" })
        TestUtils.addItem(RING_B, { equipLoc = "INVTYPE_FINGER" })
        TestUtils.addItem(RING_C, { equipLoc = "INVTYPE_FINGER" })
        TestUtils.addItem(TWO_HANDER, { equipLoc = "INVTYPE_2HWEAPON" })
        TestUtils.addItem(DAGGER_A, { equipLoc = "INVTYPE_WEAPON" })
        TestUtils.addItem(DAGGER_B, { equipLoc = "INVTYPE_WEAPON" })
        TestUtils.addItem(SHIELD, { equipLoc = "INVTYPE_SHIELD" })
        TestUtils.addItem(POTION, { equipLoc = "" })
    end)

    local function Set(...)
        local set = {}
        for _, id in ipairs({ ... }) do set[id] = true end
        return set
    end

    describe("CanAddItem", function()
        it("allows one item per ordinary slot", function()
            assert.is_true(Gearset:CanAddItem(Set(), HELM))
            local ok, reason = Gearset:CanAddItem(Set(HELM), 100)
            assert.is_true(ok, reason)
            TestUtils.addItem(100, { equipLoc = "INVTYPE_HEAD" })
            ok, reason = Gearset:CanAddItem(Set(HELM), 100)
            assert.is_false(ok)
            assert.is_not_nil(reason)
        end)

        it("allows two rings but not three", function()
            assert.is_true(Gearset:CanAddItem(Set(RING_A), RING_B))
            assert.is_false(Gearset:CanAddItem(Set(RING_A, RING_B), RING_C))
        end)

        it("counts hands: a two-hander fills both", function()
            assert.is_true(Gearset:CanAddItem(Set(DAGGER_A), DAGGER_B))
            assert.is_true(Gearset:CanAddItem(Set(DAGGER_A), SHIELD))
            assert.is_false(Gearset:CanAddItem(Set(TWO_HANDER), SHIELD))
            assert.is_false(Gearset:CanAddItem(Set(DAGGER_A, SHIELD), DAGGER_B))
        end)

        it("does not ration things that aren't gear", function()
            assert.is_true(Gearset:CanAddItem(Set(HELM), POTION))
        end)

        it("an item already in the set is fine", function()
            assert.is_true(Gearset:CanAddItem(Set(RING_A, RING_B), RING_A))
        end)
    end)

    describe("state", function()
        it("is equipped when every item is worn somewhere", function()
            local tab = { forcedItemIDs = Set(HELM, RING_A) }
            TestUtils.state.equipped[1] = HELM
            assert.is_false(Gearset:IsEquipped(tab))
            TestUtils.state.equipped[11] = RING_A
            assert.is_true(Gearset:IsEquipped(tab))
        end)

        it("an empty set is never equipped", function()
            assert.is_false(Gearset:IsEquipped({ forcedItemIDs = {} }))
        end)

        it("a recorded swap is a pending revert until dismissed", function()
            local tab = { forcedItemIDs = Set(HELM) }
            assert.is_false(Gearset:HasPendingRevert(tab))
            Gearset:SetPreviousEquipped(tab, { 50 }, { 1 })
            assert.is_true(Gearset:HasPendingRevert(tab))
            assert.is_true(Gearset:ShouldOfferUnequip(tab))
            Gearset:DismissPreviousEquipped(tab)
            assert.is_false(Gearset:HasPendingRevert(tab))
        end)

        it("can toggle only when there's something to do", function()
            local tab = { forcedItemIDs = Set(HELM) }
            ns.VirtualInventory = {}
            assert.is_false(Gearset:CanToggle(tab))
            ns.VirtualInventory = { [HELM] = { itemID = HELM } }
            assert.is_true(Gearset:CanToggle(tab))
        end)
    end)

    describe("Equip", function()
        it("puts fixed-hand items first and the ambiguous ones in whatever hand is left", function()
            local tab = { forcedItemIDs = Set(SHIELD, DAGGER_A, HELM) }
            Gearset:Equip(tab)
            local bySlot = {}
            for _, call in ipairs(TestUtils.calls("EquipItemByName")) do
                bySlot[call[1]] = call[2] or "any"
            end
            assert.are.equal(17, bySlot[SHIELD])
            assert.are.equal(16, bySlot[DAGGER_A])
            assert.are.equal("any", bySlot[HELM])
        end)

        it("dual-wields two one-handers", function()
            Gearset:Equip({ forcedItemIDs = Set(DAGGER_A, DAGGER_B) })
            local slots = {}
            for _, call in ipairs(TestUtils.calls("EquipItemByName")) do table.insert(slots, call[2]) end
            table.sort(slots)
            assert.are.same({ 16, 17 }, slots)
        end)

        it("remembers what it replaced, with its slot, once the swap settles", function()
            TestUtils.state.equipped[1] = 99
            local tab = { forcedItemIDs = Set(HELM) }
            C_Item.EquipItemByName = function(itemID) TestUtils.state.equipped[1] = itemID end
            ns.EquipItemByName = C_Item.EquipItemByName
            Gearset:Equip(tab)
            TestUtils.runTimers()
            assert.are.same({ 99 }, Gearset:GetPreviousEquipped(tab))
            assert.are.same({ 1 }, tab.previousEquipped.slots)
        end)

        it("with Unequip everything else, refuses up front when the bags can't take it", function()
            TestUtils.setBag(0, 1, { [1] = { itemID = POTION } }) -- no free slot
            TestUtils.state.equipped[1] = 99
            TestUtils.state.equipped[2] = 98
            ns:ScanBags()
            Gearset:Equip({ forcedItemIDs = Set(RING_A), unequipEverythingElse = true })
            assert.are.equal(0, #TestUtils.calls("EquipItemByName"))
        end)
    end)

    describe("Unequip", function()
        it("puts every replaced item back in its own slot and forgets the swap", function()
            local tab = { forcedItemIDs = Set(DAGGER_A, DAGGER_B) }
            Gearset:SetPreviousEquipped(tab, { 70, 71 }, { 16, 17 })
            local done = false
            Gearset:Unequip(tab, function() done = true end)
            TestUtils.runTimers()
            local calls = TestUtils.calls("EquipItemByName")
            assert.are.same({ 70, 16 }, calls[1])
            assert.are.same({ 71, 17 }, calls[2])
            assert.is_nil(tab.previousEquipped)
            assert.is_true(done)
        end)
    end)

    describe("BuildGroups", function()
        it("splits the set's items that aren't in the bags into worn and unavailable", function()
            TestUtils.state.equipped[1] = HELM
            local tab = { forcedItemIDs = Set(HELM, RING_A, SHIELD) }
            local groups = Gearset:BuildGroups(tab, { { itemID = SHIELD } }, {})
            assert.are.equal(1, #groups.equipped)
            assert.are.equal(HELM, groups.equipped[1].itemID)
            assert.is_true(groups.equipped[1].isVirtual)
            assert.are.equal(1, #groups.unavailable)
            assert.are.equal(RING_A, groups.unavailable[1].itemID)
        end)

        it("previously equipped items use the real bag entry when there is one", function()
            local tab = { forcedItemIDs = Set(HELM) }
            Gearset:SetPreviousEquipped(tab, { 50, 51 }, { 1, 2 })
            local bagEntry = { itemID = 50 }
            local groups = Gearset:BuildGroups(tab, {}, { bagEntry })
            assert.are.equal(bagEntry, groups.previouslyEquipped[1])
            assert.is_true(groups.previouslyEquipped[2].isUnavailable)
        end)
    end)
end)
