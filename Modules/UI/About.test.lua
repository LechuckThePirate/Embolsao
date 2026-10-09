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

    describe("the welcome window's links to the other addons", function()
        local function welcome()
            UI:ShowBetaNotice()
            return EmbolsaoBetaNoticeFrame
        end

        it("has one for each of the other three addons, and none to itself", function()
            local urls = {}
            for _, box in ipairs(welcome().siblingBoxes) do urls[#urls + 1] = box:GetText() end
            assert.are.equal(3, #urls)
            local all = table.concat(urls, " ")
            assert.is_truthy(all:find("completao", 1, true))
            assert.is_truthy(all:find("aggreao", 1, true))
            assert.is_truthy(all:find("1733457", 1, true)) -- Fabrikao, by its CurseForge project id
            assert.is_nil(all:find("addons/embolsao", 1, true))
        end)

        it("are CurseForge pages, with a label above them", function()
            local frame = welcome()
            for _, box in ipairs(frame.siblingBoxes) do
                assert.matches("^https://www%.curseforge%.com/", box:GetText())
            end
            assert.matches("More addons by the same author", frame.siblingsLabel:GetText())
        end)

        it("select their link when clicked, so it can be copied", function()
            local box = welcome().siblingBoxes[1]
            local highlighted = false
            box.HighlightText = function() highlighted = true end
            box:GetScript("OnEditFocusGained")(box)
            assert.is_true(highlighted)
        end)
    end)
end)
