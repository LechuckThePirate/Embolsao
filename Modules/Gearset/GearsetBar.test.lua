dofile("setupTests.lua")

describe("GearsetBar", function()
    local ns, Bar

    before_each(function()
        TestUtils.resetEnvironment()
        TestUtils.addItem(10, { equipLoc = "INVTYPE_HEAD" })
        TestUtils.setBag(0, 4, { [1] = { itemID = 10 } })
        ns = TestUtils.startAddon()
        ns:ScanBags()
        Bar = ns.GearsetBar
    end)

    local function Gearset(items)
        return ns.Filters:CreateCustomTab({ name = "Set", tabType = "gearset", forcedItemIDs = items })
    end

    it("doesn't appear while there is no gearset", function()
        Bar:Refresh()
        assert.is_nil(_G.EmbolsaoGearsetBar)
    end)

    it("appears once a gearset exists", function()
        Gearset({ [10] = true })
        Bar:Refresh()
        assert.is_true(EmbolsaoGearsetBar:IsShown())
    end)

    it("hides when turned off in Preferences", function()
        Gearset({ [10] = true })
        Bar:Refresh()
        ns.db.showGearsetBar = false
        Bar:Refresh()
        assert.is_false(EmbolsaoGearsetBar:IsShown())
    end)

    it("its own close button turns the preference off", function()
        Gearset({ [10] = true })
        Bar:Refresh()
        EmbolsaoGearsetBar.closeButton:Click()
        assert.is_false(ns.db.showGearsetBar)
        assert.is_false(EmbolsaoGearsetBar:IsShown())
    end)

    it("coalesces bursts of refresh requests into one", function()
        Bar:RefreshSoon()
        Bar:RefreshSoon()
        Bar:RefreshSoon()
        assert.are.equal(1, #TestUtils.state.timers)
    end)

    it("refreshes when the windows rebuild their tabs", function()
        Gearset({ [10] = true })
        ns.UI:BuildTabs()
        TestUtils.runTimers()
        assert.is_true(EmbolsaoGearsetBar:IsShown())
    end)

    it("clicking a set's button equips it", function()
        local tab = Gearset({ [10] = true })
        Bar:Refresh()
        local button
        for _, frame in ipairs(TestUtils.state.frames) do
            if frame.tab == tab then button = frame end
        end
        assert.is_not_nil(button)
        button:Click("LeftButton")
        assert.are.equal(10, TestUtils.calls("EquipItemByName")[1][1])
    end)
end)
