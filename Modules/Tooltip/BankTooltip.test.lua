dofile("setupTests.lua")

describe("BankTooltip", function()
    local ns

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.loadAddon("Modules/Tooltip/BankTooltip.lua")
        TestUtils.initDB()
    end)

    -- A tooltip that just collects its lines.
    local function Tooltip(owner)
        local lines = {}
        return {
            lines = lines,
            AddLine = function(_, text) table.insert(lines, text) end,
            GetOwner = function() return owner end,
            Show = function() end,
        }
    end

    local function SaveBank(view, slots)
        ns:SaveBankSnapshot(view, { 6 }, { [6] = { n = 10, slots = slots } })
    end

    it("adds the saved personal and Warband bank counts", function()
        SaveBank("PERSONAL", { [1] = { i = 10, c = 3 }, [2] = { i = 10, c = 4 } })
        SaveBank("WARBAND", { [1] = { i = 10, c = 1 } })
        local tooltip = Tooltip()
        ns.AddTooltipBankLines(tooltip, 10)
        assert.are.same({ "In your bank: 7", "In the Warband bank: 1" }, tooltip.lines)
    end)

    it("adds nothing for an item that isn't in any bank", function()
        SaveBank("PERSONAL", { [1] = { i = 10, c = 3 } })
        local tooltip = Tooltip()
        ns.AddTooltipBankLines(tooltip, 99)
        assert.are.same({}, tooltip.lines)
    end)

    it("adds nothing with the offline bank turned off", function()
        SaveBank("PERSONAL", { [1] = { i = 10, c = 3 } })
        ns.db.offlineBank = false
        local tooltip = Tooltip()
        ns.AddTooltipBankLines(tooltip, 10)
        assert.are.same({}, tooltip.lines)
    end)

    it("adds the lines once per item, however many hooks fire", function()
        SaveBank("PERSONAL", { [1] = { i = 10, c = 3 } })
        local tooltip = Tooltip()
        ns.AddTooltipBankLines(tooltip, 10)
        ns.AddTooltipBankLines(tooltip, 10)
        assert.are.equal(1, #tooltip.lines)
    end)

    it("leaves action bar buttons alone", function()
        SaveBank("PERSONAL", { [1] = { i = 10, c = 3 } })
        local tooltip = Tooltip({ action = 1 })
        ns.AddTooltipBankLines(tooltip, 10)
        assert.are.same({}, tooltip.lines)
    end)

    it("the counts follow a newer saved copy", function()
        SaveBank("PERSONAL", { [1] = { i = 10, c = 3 } })
        ns.AddTooltipBankLines(Tooltip(), 10)
        SaveBank("PERSONAL", { [1] = { i = 10, c = 8 } })
        local tooltip = Tooltip()
        ns.AddTooltipBankLines(tooltip, 10)
        assert.are.same({ "In your bank: 8" }, tooltip.lines)
    end)

    it("lists what other characters carry", function()
        EmbolsaoDB.characterItems = {
            ["Alt-TestRealm"] = { name = "Alt", time = 1, bags = { [10] = 2 }, bank = { [10] = 5 } },
        }
        local tooltip = Tooltip()
        ns.AddTooltipBankLines(tooltip, 10)
        assert.are.same({ "Alt: 2 in bags, 5 in bank" }, tooltip.lines)
    end)

    describe("ShowCompareTooltips", function()
        local compared, modified, always

        before_each(function()
            compared, modified, always = 0, false, false
            ns.IsClassic, ns.IsForever = true, false
            _G.GameTooltip_ShowCompareItem = function() compared = compared + 1 end
            _G.IsEquippableItem = function() return true end
            _G.IsModifiedClick = function() return modified end
            _G.GetCVarBool = function() return always end
        end)

        local function ItemTooltip(equipped)
            return {
                GetItem = function() return "Sword", "item:10" end,
                IsEquippedItem = function() return equipped end,
            }
        end

        it("shows the comparison while the compare key is held", function()
            modified = true
            ns.ShowCompareTooltips(ItemTooltip())
            assert.are.equal(1, compared)
        end)

        it("shows it without the key when the compare option is on", function()
            always = true
            ns.ShowCompareTooltips(ItemTooltip())
            assert.are.equal(1, compared)
        end)

        it("waits for the key otherwise", function()
            ns.ShowCompareTooltips(ItemTooltip())
            assert.are.equal(0, compared)
        end)

        it("skips items that can't be worn and the ones already worn", function()
            modified = true
            _G.IsEquippableItem = function() return false end
            ns.ShowCompareTooltips(ItemTooltip())
            _G.IsEquippableItem = function() return true end
            ns.ShowCompareTooltips(ItemTooltip(true))
            assert.are.equal(0, compared)
        end)

        it("leaves Retail and Forever to the client", function()
            modified = true
            ns.IsClassic = false
            ns.ShowCompareTooltips(ItemTooltip())
            ns.IsClassic, ns.IsForever = true, true
            ns.ShowCompareTooltips(ItemTooltip())
            assert.are.equal(0, compared)
        end)
    end)

    describe("GetCharacterKey", function()
        it("is name-realm, with the realm's spaces removed", function()
            assert.are.equal("Tester-TestRealm", ns:GetCharacterKey())
        end)
    end)

    describe("saving this character's items", function()
        it("records bags, bank and equipment for the other characters to read", function()
            TestUtils.addItem(10, {})
            TestUtils.setBag(0, 2, { [1] = { itemID = 10, stackCount = 4 } })
            TestUtils.state.equipped[1] = 10
            SaveBank("PERSONAL", { [1] = { i = 10, c = 3 } })
            TestUtils.fireEvent("PLAYER_LOGOUT")
            local saved = EmbolsaoDB.characterItems["Tester-TestRealm"]
            assert.are.equal(4, saved.bags[10])
            assert.are.equal(3, saved.bank[10])
            assert.are.equal(10, saved.equipped[1].i)
            assert.are.equal("WARRIOR", saved.class)
        end)

        it("does not overwrite a good copy with bags that haven't loaded yet", function()
            EmbolsaoDB.characterItems = { ["Tester-TestRealm"] = { bags = { [10] = 4 } } }
            TestUtils.fireEvent("PLAYER_LOGOUT")
            assert.are.equal(4, EmbolsaoDB.characterItems["Tester-TestRealm"].bags[10])
        end)

        it("saves shortly after bag changes", function()
            TestUtils.fireEvent("BAG_UPDATE_DELAYED")
            assert.is_nil(EmbolsaoDB.characterItems)
            TestUtils.runTimers()
            assert.is_not_nil(EmbolsaoDB.characterItems["Tester-TestRealm"])
        end)
    end)
end)
