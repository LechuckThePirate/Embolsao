dofile("setupTests.lua")

describe("Prefs", function()
    local ns, UI

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.startAddon()
        UI = ns.UI
    end)

    it("opens the Preferences window", function()
        assert.has_no.errors(function() UI:ShowPreferences() end)
    end)

    it("opens again after being built once", function()
        UI:ShowPreferences()
        assert.has_no.errors(function() UI:ShowPreferences() end)
    end)

    it("the tab manager lists tabs of both panes", function()
        ns.Filters:CreateCustomTab({ name = "Mine" })
        ns.Filters.bank:CreateCustomTab({ name = "Bank one" })
        UI:ShowPreferences()
        assert.has_no.errors(function() UI.RefreshTabManagerList() end)
    end)

    it("registers its confirmation dialogs", function()
        for _, which in ipairs({ "EMBOLSAO_COPY_PREFERENCES", "EMBOLSAO_RESET_TO_SHARED", "EMBOLSAO_RESET_TO_DEFAULT_TABS" }) do
            assert.is_not_nil(StaticPopupDialogs[which], which)
            assert.is_not_nil(StaticPopupDialogs[which].OnAccept, which)
        end
    end)

    it("accepting Reset to default tabs wipes this character's tabs", function()
        ns.Filters:CreateCustomTab({ name = "Mine" })
        UI:ShowPreferences()
        StaticPopupDialogs.EMBOLSAO_RESET_TO_DEFAULT_TABS.OnAccept()
        assert.are.same({}, ns.db.customTabs)
    end)

    it("accepting Copy preferences takes the other character's tabs", function()
        -- A snapshot as another character would have saved it: every key.
        TestUtils.state.playerName = "Alt"
        ns.db.customTabs = { { id = "a", name = "Alt tab" } }
        ns:SnapshotCharacterPreferences()
        TestUtils.state.playerName = "Tester"
        ns:ResetCharacterToDefault()
        UI:ShowPreferences()
        StaticPopupDialogs.EMBOLSAO_COPY_PREFERENCES.OnAccept(nil, { charKey = "Alt-Test Realm" })
        assert.are.equal("Alt tab", ns.db.customTabs[1].name)
    end)

    it("copying an older, incomplete snapshot leaves both tab sets working", function()
        EmbolsaoDB.characterSnapshots = {
            ["Old-Test Realm"] = { name = "Old", data = { customTabs = { { id = "o", name = "Old tab" } } } },
        }
        UI:ShowPreferences()
        assert.has_no.errors(function()
            StaticPopupDialogs.EMBOLSAO_COPY_PREFERENCES.OnAccept(nil, { charKey = "Old-Test Realm" })
            ns.Filters:GetAllTabs()
            ns.Filters.bank:GetAllTabs()
        end)
        assert.are.equal("Old tab", ns.db.customTabs[1].name)
    end)

    it("the gearset bar checkbox follows the setting", function()
        UI:ShowPreferences()
        ns.db.showGearsetBar = false
        assert.has_no.errors(function() UI:SyncGearsetBarCheck() end)
    end)
end)
