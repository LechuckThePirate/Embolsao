dofile("setupTests.lua")

describe("Bindings", function()
    local ns, Bindings

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.loadAddon("Modules/Bindings/Bindings.lua")
        TestUtils.initDB()
        Bindings = ns.Bindings
    end)

    local function Hold(...)
        for _, key in ipairs({ ... }) do TestUtils.state.modifiers[key] = true end
    end

    -- A stand-in item button: an item at bagID/slot, made of `locations`.
    local function Button(bagID, slot, locations)
        return {
            itemID = 1,
            locations = locations,
            GetBagID = function() return bagID end,
            GetID = function() return slot end,
        }
    end

    describe("CurrentModifierCombo", function()
        it("is empty with nothing held", function()
            assert.are.equal("", Bindings.CurrentModifierCombo())
        end)

        it("lists held modifiers in the fixed ALT, CTRL, SHIFT order", function()
            Hold("SHIFT", "ALT")
            assert.are.equal("ALT-SHIFT", Bindings.CurrentModifierCombo())
        end)
    end)

    describe("ActionForCurrentClick", function()
        it("defaults: Ctrl = stacks, Shift = split, Alt = menu", function()
            Hold("CTRL")
            assert.are.equal("STACKS", Bindings.ActionForCurrentClick())
            TestUtils.state.modifiers.CTRL = false
            Hold("SHIFT")
            assert.are.equal("SPLIT", Bindings.ActionForCurrentClick())
            TestUtils.state.modifiers.SHIFT = false
            Hold("ALT")
            assert.are.equal("MENU", Bindings.ActionForCurrentClick())
        end)

        it("a plain click is never an action", function()
            assert.is_nil(Bindings.ActionForCurrentClick())
        end)

        it("an unbound combo does nothing", function()
            Hold("ALT", "CTRL")
            assert.is_nil(Bindings.ActionForCurrentClick())
        end)

        it("a saved binding that's no longer a valid choice falls back to the default", function()
            ns.db.bindings.STACKS = "HYPER"
            Hold("CTRL")
            assert.are.equal("STACKS", Bindings.ActionForCurrentClick())
        end)

        it("follows a custom binding", function()
            ns.db.bindings.MENU = "CTRL-SHIFT"
            Hold("CTRL", "SHIFT")
            assert.are.equal("MENU", Bindings.ActionForCurrentClick())
        end)
    end)

    describe("BindingApplies", function()
        it("stacks only for an entry made of several real stacks", function()
            assert.is_false(Bindings.BindingApplies("STACKS", Button(0, 1, { {} })))
            assert.is_true(Bindings.BindingApplies("STACKS", Button(0, 1, { {}, {} })))
        end)

        it("split only for an unlocked stack of more than one", function()
            TestUtils.setBag(0, 3, {
                [1] = { itemID = 1, stackCount = 1 },
                [2] = { itemID = 1, stackCount = 5 },
                [3] = { itemID = 1, stackCount = 5, isLocked = true },
            })
            assert.is_false(Bindings.BindingApplies("SPLIT", Button(0, 1)))
            assert.is_true(Bindings.BindingApplies("SPLIT", Button(0, 2)))
            assert.is_false(Bindings.BindingApplies("SPLIT", Button(0, 3)))
        end)

        it("never split a virtual (gearset) row with no bag behind it", function()
            assert.is_false(Bindings.BindingApplies("SPLIT", Button(nil, 0)))
        end)

        it("nothing applies to an empty button", function()
            assert.is_false(Bindings.BindingApplies("MENU", { GetBagID = function() end }))
        end)
    end)

    describe("StartSplit", function()
        it("opens the split frame for a stack of more than one", function()
            local opened
            ns.OpenStackSplitFrame = function(_, maxStack) opened = maxStack end
            TestUtils.setBag(0, 1, { [1] = { itemID = 1, stackCount = 7 } })
            local btn = Button(0, 1)
            Bindings.StartSplit(btn)
            assert.are.equal(7, opened)
            btn:SplitStack(3)
            assert.are.same({ 0, 1, 3 }, TestUtils.calls("SplitContainerItem")[1])
        end)
    end)

    describe("the Bindings window", function()
        it("builds and shows without errors", function()
            assert.has_no.errors(function() Bindings.ShowBindingsFrame() end)
            assert.is_true(EmbolsaoBindingsFrame:IsShown())
        end)
    end)
end)
