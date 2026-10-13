dofile("setupTests.lua")

describe("BankBagSlots", function()
    local ns, UI, boughtSlots, cursorHasBag, bagInSlot, picked

    -- Classic's old-style bank: bank bag slots you buy, then equip bags into.
    before_each(function()
        TestUtils.resetEnvironment()
        boughtSlots, cursorHasBag, bagInSlot, picked = 2, false, nil, {}
        _G.NUM_BANKBAGSLOTS = 6
        _G.GetNumBankSlots = function() return boughtSlots, boughtSlots >= 6 end
        _G.GetBankSlotCost = function() return 1000 end
        _G.BankButtonIDToInvSlotID = function(index) return 100 + index end
        _G.PutItemInBag = function(slot)
            if not cursorHasBag then return false end
            cursorHasBag = false
            bagInSlot = slot
            return true
        end
        _G.PickupBagFromSlot = function(slot) table.insert(picked, slot) end
        ns = TestUtils.startAddon()
        UI = ns.UI
        ns.AtBank = true
        UI.bankWindow.OpenDirect()
    end)

    after_each(function()
        _G.NUM_BANKBAGSLOTS, _G.GetNumBankSlots, _G.GetBankSlotCost = nil, nil, nil
        _G.BankButtonIDToInvSlotID, _G.PutItemInBag, _G.PickupBagFromSlot = nil, nil, nil
    end)

    local function Buttons()
        local footer = UI.bankWindow.GetFrame().footer
        local found = {}
        for _, frame in ipairs(TestUtils.state.frames) do
            if frame.__frameType == "Button" and frame.index and frame.__parent
                and frame.__parent.__parent == footer then
                table.insert(found, frame)
            end
        end
        return found
    end

    local function ShownButtons()
        local shown = {}
        for _, button in ipairs(Buttons()) do
            if button:IsShown() then table.insert(shown, button) end
        end
        return shown
    end

    it("shows one slot per bought bank bag slot at a banker", function()
        UI:UpdateBankBagSlots()
        assert.are.equal(2, #ShownButtons())
    end)

    it("grows as slots are bought", function()
        UI:UpdateBankBagSlots()
        boughtSlots = 3
        UI:UpdateBankBagSlots()
        assert.are.equal(3, #ShownButtons())
    end)

    it("is drawn by the bank window's own refresh", function()
        UI.bankWindow.Refresh()
        assert.are.equal(2, #ShownButtons())
    end)

    it("is gone away from a banker and on the offline bank", function()
        UI:UpdateBankBagSlots()
        ns.AtBank = false
        UI:UpdateBankBagSlots()
        assert.are.equal(0, #ShownButtons())

        ns.AtBank = true
        ns.BankOffline = true
        UI:UpdateBankBagSlots()
        assert.are.equal(0, #ShownButtons())
    end)

    it("equips the bag on the cursor into the slot that was clicked", function()
        UI:UpdateBankBagSlots()
        cursorHasBag = true
        ShownButtons()[2]:Click()
        assert.are.equal(102, bagInSlot)
        assert.are.same({}, picked)
    end)

    it("picks the bag up when the cursor is empty", function()
        UI:UpdateBankBagSlots()
        ShownButtons()[1]:Click()
        assert.are.same({ 101 }, picked)
    end)

    it("picks the bag up on drag and equips on receiving one", function()
        UI:UpdateBankBagSlots()
        local button = ShownButtons()[1]
        button:GetScript("OnDragStart")(button)
        assert.are.same({ 101 }, picked)

        cursorHasBag = true
        button:GetScript("OnReceiveDrag")(button)
        assert.are.equal(101, bagInSlot)
    end)

    it("stays out of the way on the modern bank", function()
        TestUtils.resetEnvironment()
        _G.Enum.BankType = { Character = 0, Account = 2 }
        _G.C_Bank = {
            FetchPurchasedBankTabIDs = function() return {} end,
            FetchNextPurchasableBankTabData = function() return nil end,
        }
        _G.GetNumBankSlots = function() return 2, false end
        _G.PutItemInBag = function() return false end
        _G.PickupBagFromSlot = function() end
        ns = TestUtils.startAddon()
        UI = ns.UI
        ns.AtBank = true
        UI.bankWindow.OpenDirect()
        assert.has_no.errors(function() UI:UpdateBankBagSlots() end)
        assert.are.equal(0, #ShownButtons())
    end)
end)
