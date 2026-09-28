dofile("setupTests.lua")

describe("Minimap", function()
    local ns, button

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.startAddon()
        button = _G.EmbolsaoMinimapButton
    end)

    it("is created at login, visible", function()
        assert.is_not_nil(button)
        assert.is_true(button:IsShown())
    end)

    it("left-click toggles the bags", function()
        button:Click("LeftButton")
        assert.are.equal(1, #TestUtils.calls("ToggleAllBags"))
    end)

    it("right-click opens its menu", function()
        button:Click("RightButton")
        local find = TestUtils.state.findMenuEntry
        assert.is_not_nil(find(ns.L.MINIMAP_OPEN))
        assert.is_not_nil(find(ns.L.PREFERENCES))
        assert.is_not_nil(find(ns.L.MINIMAP_DISABLE))
    end)

    it("the menu's Disable toggles Embolsao off and on", function()
        button:Click("RightButton")
        local disable = TestUtils.state.findMenuEntry(ns.L.MINIMAP_DISABLE)
        assert.is_false(disable.a())
        disable.b()
        assert.is_true(ns.db.disabled)
        disable.b()
        assert.is_false(ns.db.disabled)
    end)

    it("dragging moves it around the minimap and remembers the angle", function()
        TestUtils.state.cursorX, TestUtils.state.cursorY = 0, 100 -- straight above the centre
        _G.GetCursorPosition = function() return TestUtils.state.cursorX, TestUtils.state.cursorY end
        button:GetScript("OnDragStart")(button)
        button:GetScript("OnUpdate")(button)
        button:GetScript("OnDragStop")(button)
        assert.near(90, ns.db.minimapAngle, 0.001)
    end)

    it("Preferences can hide it and bring it back", function()
        ns.Minimap:SetShown(false)
        assert.is_false(button:IsShown())
        assert.is_false(ns.db.showMinimapButton)
        ns.Minimap:SetShown(true)
        assert.is_true(button:IsShown())
    end)

    it("stays hidden at login when it was turned off", function()
        TestUtils.resetEnvironment()
        local fresh = TestUtils.loadAddon()
        TestUtils.initDB()
        fresh.db.showMinimapButton = false
        TestUtils.fireEvent("PLAYER_LOGIN")
        assert.is_false(EmbolsaoMinimapButton:IsShown())
    end)
end)
