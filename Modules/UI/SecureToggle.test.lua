dofile("setupTests.lua")

describe("SecureToggle", function()
    local ns, UI, toggle, host, bags, overrides

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.startAddon()
        UI = ns.UI
        toggle = EmbolsaoSecureToggle

        -- Protected panes, as they are once their item buttons have secure overlays.
        host = CreateFrame("Frame")
        bags = CreateFrame("Frame")
        host.IsProtected = function() return true end
        bags.IsProtected = function() return true end
        UI.GetHost = function() return host end
        UI.bagsWindow.GetFrame = function() return bags end
        UI.bankWindow.GetFrame = function() return nil end

        overrides = {}
        _G.GetBindingKey = function(action) if action == "TOGGLEBACKPACK" then return "B" end end
        _G.SetOverrideBindingClick = function(_, _, key) overrides[key] = true end
        _G.ClearOverrideBindings = function() overrides = {} end
    end)

    local function SelfTestPasses()
        toggle.Execute = function(self) self:SetAttribute("selftest", "host:SHI;bags:SHI;") end
    end

    it("is a secure click button bound to the combat state", function()
        assert.is_not_nil(toggle)
        assert.is_not_nil(toggle:GetAttribute("_onclick"))
    end)

    it("takes the bags key once the panes are protected and the dry run passes", function()
        SelfTestPasses()
        UI:SetupSecureToggle()
        assert.is_true(overrides.B)
        assert.are.equal("host:SHI;bags:SHI;", EmbolsaoDB.secureToggleSelfTest)
    end)

    it("leaves the key to Blizzard when the dry run fails", function()
        toggle.Execute = function() error("can't compile snippets here") end
        UI:SetupSecureToggle()
        assert.is_nil(overrides.B)
        assert.are.equal("error", EmbolsaoDB.secureToggleSelfTest)
    end)

    it("leaves the key alone while Embolsao is disabled", function()
        SelfTestPasses()
        ns.db.disabled = true
        UI:SetupSecureToggle()
        assert.is_nil(overrides.B)
    end)

    it("tells the snippet whether opening in combat is blocked", function()
        SelfTestPasses()
        ns.db.closeOnCombat = true
        UI:SetupSecureToggle()
        assert.is_true(toggle:GetAttribute("blockopen"))
    end)

    it("waits for combat to end before changing bindings", function()
        SelfTestPasses()
        _G.InCombatLockdown = function() return true end
        UI:RefreshSecureToggle()
        assert.is_nil(overrides.B)
        _G.InCombatLockdown = function() return false end
        TestUtils.fireEvent("PLAYER_REGEN_ENABLED")
        assert.is_true(overrides.B)
    end)
end)
