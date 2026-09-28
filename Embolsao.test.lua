dofile("setupTests.lua")

-- The whole addon, loaded the way the game loads it: every file in the .toc, in
-- order, sharing one namespace.
describe("Embolsao", function()
    before_each(function()
        TestUtils.resetEnvironment()
    end)

    it("every file listed in the .toc exists", function()
        for _, path in ipairs(TestUtils.getTocFiles()) do
            local file = io.open(path, "r")
            assert.is_not_nil(file, "missing: " .. path)
            file:close()
        end
    end)

    it("loads every file without errors", function()
        assert.has_no.errors(function() TestUtils.loadAddon() end)
    end)

    it("exposes its modules on the namespace", function()
        local ns = TestUtils.loadAddon()
        for _, name in ipairs({ "L", "Filters", "Gearset", "GearsetBar", "Layout", "Bindings", "UI", "Minimap", "UIConst" }) do
            assert.is_not_nil(ns[name], name)
        end
    end)

    it("initializes its saved variables on ADDON_LOADED", function()
        local ns = TestUtils.loadAddon()
        TestUtils.initDB()
        assert.is_not_nil(EmbolsaoDB)
        assert.is_not_nil(EmbolsaoCharDB)
        assert.are.equal("ALL", ns.db.activeTab)
    end)

    it("survives a login: world entered, bags updated, timers run", function()
        TestUtils.loadAddon()
        TestUtils.initDB()
        assert.has_no.errors(function()
            TestUtils.fireEvent("PLAYER_LOGIN")
            TestUtils.fireEvent("PLAYER_ENTERING_WORLD")
            TestUtils.fireEvent("BAG_UPDATE_DELAYED")
            TestUtils.runTimers()
            TestUtils.fireEvent("PLAYER_LOGOUT")
        end)
    end)
end)
