dofile("setupTests.lua")

describe("EmbolsaoAPI", function()
    local ns

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.loadAddon("Modules/API/API.lua")
        TestUtils.initDB()
        EmbolsaoDB.characterItems = {
            ["Tester-TestRealm"] = { name = "Tester", class = "WARRIOR", time = 5, bags = { [10] = 99 }, bank = {} }, -- this character
            ["Elsa-TestRealm"] = { name = "Elsa", class = "MAGE", time = 10, bags = { [10] = 4 }, bank = { [11] = 6 } },
            ["Bad Yuyu-TestRealm"] = { name = "Bad Yuyu", class = "WARLOCK", time = 20, bags = { [11] = 1, [10] = 2 } },
        }
    end)

    it("is a global with a version", function()
        assert.are.equal("table", type(_G.EmbolsaoAPI))
        assert.are.equal(1, _G.EmbolsaoAPI.version)
    end)

    describe("GetCharacters", function()
        it("lists the other characters by name, with their class and when they were saved", function()
            local characters = _G.EmbolsaoAPI.GetCharacters()
            assert.are.equal(2, #characters)
            assert.are.equal("Bad Yuyu", characters[1].name)
            assert.are.equal("Elsa", characters[2].name)
            assert.are.equal("MAGE", characters[2].class)
            assert.are.equal(10, characters[2].time)
            assert.are.equal("Elsa-TestRealm", characters[2].key)
        end)

        it("gives nothing when no character is saved", function()
            EmbolsaoDB.characterItems = nil
            assert.are.same({}, _G.EmbolsaoAPI.GetCharacters())
        end)

        it("hands out copies, not the addon's own tables", function()
            local characters = _G.EmbolsaoAPI.GetCharacters()
            characters[1].name = "Changed"
            assert.are.equal("Bad Yuyu", _G.EmbolsaoAPI.GetCharacters()[1].name)
            assert.are.equal("Bad Yuyu", EmbolsaoDB.characterItems["Bad Yuyu-TestRealm"].name)
        end)
    end)

    describe("GetOthersItemCount", function()
        it("adds up what the other characters have in their bags and in their banks", function()
            local bags, bank = _G.EmbolsaoAPI.GetOthersItemCount(10)
            assert.are.equal(4 + 2, bags) -- not this character's 99
            assert.are.equal(0, bank)
            bags, bank = _G.EmbolsaoAPI.GetOthersItemCount(11)
            assert.are.equal(1, bags)
            assert.are.equal(6, bank)
        end)

        it("is zero for an item nobody has, or for something that isn't an item id", function()
            assert.are.same({ 0, 0 }, { _G.EmbolsaoAPI.GetOthersItemCount(12345) })
            assert.are.same({ 0, 0 }, { _G.EmbolsaoAPI.GetOthersItemCount(nil) })
            assert.are.same({ 0, 0 }, { _G.EmbolsaoAPI.GetOthersItemCount("10") })
        end)
    end)

    describe("GetItemHolders", function()
        it("lists who has the item, by name, with how many in bags and in bank", function()
            local holders = _G.EmbolsaoAPI.GetItemHolders(10)
            assert.are.equal(2, #holders)
            assert.are.equal("Bad Yuyu", holders[1].name)
            assert.are.equal(2, holders[1].bags)
            assert.are.equal(0, holders[1].bank)
            assert.are.equal("Elsa", holders[2].name)
            assert.are.equal(4, holders[2].bags)
            assert.are.equal("MAGE", holders[2].class)
        end)

        it("leaves out the ones with none, and the character playing", function()
            local holders = _G.EmbolsaoAPI.GetItemHolders(11)
            assert.are.equal(2, #holders)
            assert.are.equal(6, holders[2].bank)
            assert.are.same({}, _G.EmbolsaoAPI.GetItemHolders(12345))
            assert.are.same({}, _G.EmbolsaoAPI.GetItemHolders(nil))
        end)
    end)
end)
