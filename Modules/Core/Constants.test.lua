dofile("setupTests.lua")

describe("Constants", function()
    it("exposes the shared layout sizes as positive numbers", function()
        TestUtils.resetEnvironment()
        local ns = {}
        TestUtils.loadFile(ns, "Modules/Core/Constants.lua")
        for _, key in ipairs({ "ITEM_SIZE", "ITEM_PADDING", "HEADER_ROW_HEIGHT", "GROUP_GAP_HEIGHT", "SCROLLBAR_CLEARANCE" }) do
            assert.is_true(type(ns.UIConst[key]) == "number" and ns.UIConst[key] > 0, key)
        end
    end)
end)
