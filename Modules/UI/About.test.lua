dofile("setupTests.lua")

describe("About", function()
    local ns, UI

    before_each(function()
        TestUtils.resetEnvironment()
        ns = TestUtils.startAddon()
        UI = ns.UI
    end)

    it("reads the version from the .toc metadata", function()
        assert.are.equal("1.0.0-test", UI.GetAddonVersion())
    end)

    it("shows the About window", function()
        assert.has_no.errors(function() UI.ShowAboutFrame() end)
    end)

    it("the welcome window shows until this version is dismissed", function()
        UI:ShowBetaNotice(true)
        assert.is_true(EmbolsaoBetaNoticeFrame:IsShown())
    end)

    it("stays closed at login once this version was dismissed", function()
        ns.db.betaNoticeDismissedVersion = UI.GetAddonVersion()
        UI:ShowBetaNotice(true)
        assert.is_nil(_G.EmbolsaoBetaNoticeFrame)
    end)

    it("shows again for a new version", function()
        ns.db.betaNoticeDismissedVersion = "0.0.1"
        UI:ShowBetaNotice(true)
        assert.is_true(EmbolsaoBetaNoticeFrame:IsShown())
    end)

    it("the About window is always available on demand", function()
        ns.db.betaNoticeDismissedVersion = UI.GetAddonVersion()
        UI:ShowBetaNotice()
        assert.is_true(EmbolsaoBetaNoticeFrame:IsShown())
    end)
end)
