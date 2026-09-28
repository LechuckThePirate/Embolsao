dofile("setupTests.lua")

local function LoadCompat(options, tweak)
    TestUtils.resetEnvironment(options)
    if tweak then tweak() end
    local ns = {}
    TestUtils.loadFile(ns, "Modules/Core/Compat.lua")
    return ns
end

describe("Compat", function()
    describe("client flavor", function()
        it("retail is neither Classic nor Forever", function()
            local ns = LoadCompat({ projectID = 1, interfaceVersion = 120100 })
            assert.is_false(ns.IsClassic)
            assert.is_false(ns.IsForever)
            assert.are.equal("PortraitFrameFlatTemplate", ns.PORTRAIT_FRAME_TEMPLATE)
        end)

        it("Classic Era is Classic and uses the textured portrait frame", function()
            local ns = LoadCompat({ projectID = 2, interfaceVersion = 11509 })
            assert.is_true(ns.IsClassic)
            assert.is_false(ns.IsForever)
            assert.are.equal("PortraitFrameTemplate", ns.PORTRAIT_FRAME_TEMPLATE)
        end)

        it("Forever is told apart by its 1.6x build number", function()
            local ns = LoadCompat({ projectID = 1, interfaceVersion = 16001 })
            assert.is_true(ns.IsForever)
        end)
    end)

    describe("API fallbacks", function()
        it("prefers the namespaced C_Item functions", function()
            local ns = LoadCompat()
            assert.are.equal(C_Item.GetItemInfo, ns.GetItemInfo)
            assert.are.equal(C_Item.EquipItemByName, ns.EquipItemByName)
        end)

        it("falls back to the bare globals when C_Item lacks them", function()
            local legacy = function() end
            local ns = LoadCompat(nil, function()
                C_Item.GetItemInfo = nil
                _G.GetItemInfo = legacy
            end)
            assert.are.equal(legacy, ns.GetItemInfo)
        end)

        it("formats money as plain text when no coin API exists", function()
            local ns = LoadCompat(nil, function()
                _G.C_CurrencyInfo = nil
                _G.GetCoinTextureString = nil
            end)
            assert.are.equal("12g 3s 4c", ns.GetCoinTextureString(120304))
        end)
    end)

    describe("GetItemQualityColor", function()
        it("returns nil for no quality", function()
            local ns = LoadCompat()
            assert.is_nil(ns:GetItemQualityColor(nil))
        end)

        it("uses C_Item.GetItemQualityColor", function()
            local ns = LoadCompat()
            local r = ns:GetItemQualityColor(4)
            assert.near(0.4, r, 0.0001)
        end)

        it("falls back to ITEM_QUALITY_COLORS", function()
            local ns = LoadCompat(nil, function()
                C_Item.GetItemQualityColor = nil
                ITEM_QUALITY_COLORS[3] = { r = 0, g = 0.44, b = 0.87 }
            end)
            local r, g, b = ns:GetItemQualityColor(3)
            assert.are.same({ 0, 0.44, 0.87 }, { r, g, b })
        end)
    end)

    describe("GetEffectiveItemLevel", function()
        it("uses the detailed (scaled) item level", function()
            local ns = LoadCompat()
            TestUtils.addItem(100, { itemLevel = 250 })
            assert.are.equal(250, ns:GetEffectiveItemLevel(100))
        end)

        it("falls back to GetItemInfo when the detailed call errors", function()
            local ns = LoadCompat()
            C_Item.GetDetailedItemLevelInfo = function() error("boom") end
            TestUtils.addItem(100, { itemLevel = 42 })
            assert.are.equal(42, ns:GetEffectiveItemLevel(100))
        end)
    end)

    describe("GetItemStatsTable", function()
        it("is empty without a hyperlink", function()
            local ns = LoadCompat()
            assert.are.same({}, ns:GetItemStatsTable(nil))
        end)

        it("is empty when the API errors", function()
            local ns = LoadCompat()
            C_Item.GetItemStats = function() error("boom") end
            assert.are.same({}, ns:GetItemStatsTable("item:1"))
        end)
    end)

    describe("bank", function()
        it("Classic's personal bank is BANK_CONTAINER plus the bank bag slots", function()
            local ns = LoadCompat({ projectID = 2, interfaceVersion = 11509 }, function()
                _G.NUM_BANKBAGSLOTS = 2
            end)
            ns:InitBankBagIDs()
            assert.are.same({ BANK_CONTAINER, 5, 6 }, ns.PersonalBankBagIDs)
            assert.are.same({}, ns.WarbandBankBagIDs)
        end)

        it("the modern bank reads its purchased tabs from C_Bank", function()
            local ns = LoadCompat(nil, function()
                Enum.BankType = { Character = 0, Account = 2 }
                _G.C_Bank = {
                    FetchPurchasedBankTabIDs = function(bankType)
                        return bankType == 0 and { 6, 7 } or { 12 }
                    end,
                }
            end)
            assert.is_true(ns:UsesModernBank())
            ns:InitBankBagIDs()
            assert.are.same({ 6, 7 }, ns.PersonalBankBagIDs)
            assert.are.same({ 12 }, ns.WarbandBankBagIDs)
        end)

        it("offers nothing to buy away from a banker", function()
            local ns = LoadCompat()
            ns.AtBank = false
            assert.is_nil(ns:GetNextBankPurchase())
        end)

        it("offers Classic's next bank slot and whether it's affordable", function()
            local ns = LoadCompat({ projectID = 2, interfaceVersion = 11509 }, function()
                _G.GetNumBankSlots = function() return 1, false end
                _G.GetBankSlotCost = function() return 1000 end
            end)
            ns.AtBank = true
            TestUtils.state.money = 500
            assert.are.same({ kind = "slot", cost = 1000, canAfford = false }, ns:GetNextBankPurchase())
        end)

        it("does not open the purchase popup when it can't be afforded", function()
            local ns = LoadCompat({ projectID = 2, interfaceVersion = 11509 }, function()
                _G.GetNumBankSlots = function() return 1, false end
                _G.GetBankSlotCost = function() return 1000 end
            end)
            ns.AtBank = true
            ns:RequestBankPurchase()
            assert.are.equal(0, #TestUtils.calls("StaticPopup_Show"))
            TestUtils.state.money = 5000
            ns:RequestBankPurchase()
            assert.are.equal("CONFIRM_BUY_BANK_SLOT", TestUtils.calls("StaticPopup_Show")[1][1])
        end)
    end)
end)
