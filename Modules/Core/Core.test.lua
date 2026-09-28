dofile("setupTests.lua")

describe("Core", function()
    local ns

    local function Load(options)
        TestUtils.resetEnvironment(options)
        ns = TestUtils.loadAddon("Modules/Core/Core.lua")
    end

    before_each(function()
        Load()
    end)

    describe("saved variables", function()
        it("a fresh install gets every default", function()
            TestUtils.initDB()
            assert.are.equal("ALL", ns.db.activeTab)
            assert.are.equal("TYPE", ns.db.sortMode)
            assert.is_true(ns.db.consolidateStacks)
            assert.are.same({}, ns.db.customTabs)
        end)

        it("a new character starts character-specific, seeded from the shared data", function()
            _G.EmbolsaoDB = { sharedCharDataMigrated = true, sharedCharData = { customTabs = { { id = "t1" } } } }
            TestUtils.initDB()
            assert.is_true(EmbolsaoCharDB.useCharacterSpecific)
            assert.are.same({ { id = "t1" } }, ns.db.customTabs)
            -- A copy, not the same table: editing it leaves the shared one alone.
            table.insert(ns.db.customTabs, { id = "t2" })
            assert.are.equal(1, #EmbolsaoDB.sharedCharData.customTabs)
        end)

        it("migrates per-character keys the oldest releases kept on EmbolsaoDB", function()
            _G.EmbolsaoDB = { customTabs = { { id = "old" } }, sortMode = "NAME" }
            TestUtils.initDB()
            assert.is_nil(EmbolsaoDB.customTabs)
            assert.are.same({ { id = "old" } }, EmbolsaoDB.sharedCharData.customTabs)
            assert.are.equal("NAME", ns.db.sortMode)
            assert.is_true(EmbolsaoDB.sharedCharDataMigrated)
        end)

        it("account-wide keys read and write EmbolsaoDB", function()
            TestUtils.initDB()
            ns.db.sortMode = "QUALITY"
            assert.are.equal("QUALITY", EmbolsaoDB.sortMode)
        end)

        it("per-character keys follow the active store", function()
            TestUtils.initDB()
            ns.db.activeTab = "mine"
            assert.are.equal("mine", EmbolsaoCharDB.activeTab)

            ns:SetUseCharacterSpecificData(false)
            assert.are.equal("ALL", ns.db.activeTab)
            ns.db.activeTab = "shared"
            assert.are.equal("shared", EmbolsaoDB.sharedCharData.activeTab)
            assert.are.equal("mine", EmbolsaoCharDB.activeTab)
        end)

        it("turning character-specific on copies the shared data in", function()
            TestUtils.initDB()
            ns:SetUseCharacterSpecificData(false)
            ns.db.activeTab = "shared"
            ns:SetUseCharacterSpecificData(true)
            assert.are.equal("shared", ns.db.activeTab)
        end)

        it("ResetCharacterToDefault wipes this character back to factory tabs", function()
            TestUtils.initDB()
            ns.db.customTabs = { { id = "x" } }
            ns.db.activeTab = "x"
            ns:ResetCharacterToDefault()
            assert.are.same({}, ns.db.customTabs)
            assert.are.equal("ALL", ns.db.activeTab)
        end)
    end)

    describe("character snapshots", function()
        it("a snapshot of this character is not offered to itself", function()
            TestUtils.initDB()
            ns:SnapshotCharacterPreferences()
            assert.is_not_nil(EmbolsaoDB.characterSnapshots["Tester-Test Realm"])
            assert.are.same({}, ns:GetCharacterSnapshots())
        end)

        it("copies another character's preferences", function()
            TestUtils.initDB()
            EmbolsaoDB.characterSnapshots = {
                ["Alt-Test Realm"] = { name = "Alt", data = { activeTab = "altTab", customTabs = { { id = "a" } } } },
            }
            assert.is_true(ns:CopyPreferencesFromCharacter("Alt-Test Realm"))
            assert.are.equal("altTab", ns.db.activeTab)
            assert.are.same({ { id = "a" } }, ns.db.customTabs)
            assert.is_false(ns:CopyPreferencesFromCharacter("Nobody-Test Realm"))
        end)

        it("a snapshot from an older version gets defaults for the keys it lacks", function()
            TestUtils.initDB()
            EmbolsaoDB.characterSnapshots = {
                ["Alt-Test Realm"] = { name = "Alt", data = { customTabs = { { id = "a", name = "A" } } } },
            }
            assert.is_true(ns:CopyPreferencesFromCharacter("Alt-Test Realm"))
            assert.are.same({}, ns.db.hiddenTabs)
            assert.are.same({}, ns.db.bankCustomTabs)
            assert.are.equal("ALL", ns.db.bankActiveTab)
        end)
    end)

    describe("ScanBags", function()
        before_each(function()
            TestUtils.addItem(10, { quality = 1 })
            TestUtils.addItem(20, { quality = 0 })
        end)

        it("merges every stack of an item into one entry", function()
            TestUtils.setBag(0, 4, {
                [1] = { itemID = 10, stackCount = 5 },
                [3] = { itemID = 10, stackCount = 2 },
            })
            TestUtils.initDB()
            local inventory = ns:ScanBags()
            assert.are.equal(7, inventory[10].count)
            assert.are.equal(2, #inventory[10].locations)
            assert.are.equal(2, #ns.EmptySlots)
        end)

        it("keeps every stack apart when Consolidate Stacks is off", function()
            TestUtils.setBag(0, 4, {
                [1] = { itemID = 10, stackCount = 5 },
                [3] = { itemID = 10, stackCount = 2 },
            })
            TestUtils.initDB()
            ns.db.consolidateStacks = false
            local inventory = ns:ScanBags()
            assert.are.equal(5, inventory["0:1"].count)
            assert.are.equal(2, inventory["0:3"].count)
        end)

        it("marks grey items and hand-picked ones as junk", function()
            TestUtils.addItem(30, { quality = 2 })
            TestUtils.setBag(0, 4, {
                [1] = { itemID = 10 }, [2] = { itemID = 20 }, [3] = { itemID = 30 },
            })
            TestUtils.initDB()
            ns.db.junkItemIDs[30] = true
            local inventory = ns:ScanBags()
            assert.is_false(inventory[10].isJunk)
            assert.is_true(inventory[20].isJunk)
            assert.is_true(inventory[30].isJunk)
        end)

        it("stamps quest items from their bag slot", function()
            TestUtils.setBag(0, 2, {
                [1] = { itemID = 10, questInfo = { questID = 123, isActive = true } },
            })
            TestUtils.initDB()
            local inventory = ns:ScanBags()
            assert.are.equal(123, inventory[10].questID)
            assert.is_true(inventory[10].isQuestActive)
        end)

        it("puts plain bags in the general empty-slot group and special bags apart", function()
            TestUtils.setBag(0, 2, {})
            TestUtils.setBag(1, 2, {}, 0)
            TestUtils.setBag(2, 3, {}, 8) -- a profession bag
            TestUtils.setBag(3, 1, {}, 8) -- another of the same kind
            TestUtils.initDB()
            ns:ScanBags()
            local groups = ns.EmptySlotGroups
            assert.are.equal("general", groups[1].id)
            assert.are.equal(4, #groups[1].slots)
            assert.are.equal(2, #groups)
            assert.are.equal(4, #groups[2].slots)
            assert.are.same({ 2, 3 }, groups[2].bagIDs)
        end)
    end)

    describe("recent items", function()
        it("remembers an item flagged new until it is dismissed", function()
            TestUtils.addItem(10, {})
            TestUtils.setBag(0, 2, { [1] = { itemID = 10, isNew = true } })
            TestUtils.initDB()
            local inventory = ns:ScanBags()
            assert.is_true(inventory[10].isRecent)

            -- Blizzard clears its own flag; ours stays.
            TestUtils.state.bags[0].slots[1].isNew = false
            assert.is_true(ns:ScanBags()[10].isRecent)

            ns:DismissRecentItem(10, inventory[10].locations)
            assert.is_false(ns:ScanBags()[10].isRecent)
        end)

        it("forgets an item that left the bags, but only once bags have settled", function()
            TestUtils.addItem(10, {})
            TestUtils.addItem(11, {})
            TestUtils.setBag(0, 2, { [1] = { itemID = 10, isNew = true }, [2] = { itemID = 11 } })
            TestUtils.initDB()
            ns:ScanBags()
            TestUtils.state.bags[0].slots[1] = nil

            ns:ScanBags()
            assert.is_true(ns.RecentItemIDs[10])

            ns.bagsSettled = true
            ns:ScanBags()
            assert.is_nil(ns.RecentItemIDs[10])
        end)
    end)

    describe("offline bank", function()
        it("saves the bank while at a settled banker and shows it later offline", function()
            TestUtils.addItem(10, {})
            TestUtils.setBag(6, 4, { [2] = { itemID = 10, stackCount = 3 } })
            TestUtils.initDB()
            ns.PersonalBankBagIDs = { 6 }
            ns.AtBank, ns.bankSettled = true, true
            ns:ScanBank()
            assert.is_not_nil(EmbolsaoCharDB.bankSnapshot)

            -- Away from the banker, the bank itself is gone...
            TestUtils.state.bags[6] = nil
            ns.AtBank, ns.BankOffline = false, true
            local inventory = ns:ScanBank()
            -- ...but the saved copy still shows it.
            assert.are.equal(3, inventory[10].count)
            assert.are.equal(3, #ns.BankEmptySlots)
        end)

        it("does not save while the bank is still loading", function()
            TestUtils.setBag(6, 4, {})
            TestUtils.initDB()
            ns.PersonalBankBagIDs = { 6 }
            ns.AtBank, ns.bankSettled = true, false
            ns:ScanBank()
            assert.is_nil(EmbolsaoCharDB.bankSnapshot)
        end)

        it("keeps the Warband bank account-wide", function()
            TestUtils.initDB()
            ns:SaveBankSnapshot("WARBAND", { 12 }, {})
            assert.is_not_nil(EmbolsaoDB.warbandBankSnapshot)
            assert.are.equal(EmbolsaoDB.warbandBankSnapshot, ns:GetBankSnapshot("WARBAND"))
        end)
    end)

    describe("character names", function()
        it("elsewhere, the realm part of a key stays a realm", function()
            assert.are.equal("Elsa", ns:GetCharacterDisplayName("Elsa-Cacorchos", { name = "Elsa" }))
        end)

        it("on Forever, a cut two-word name gets its second word back", function()
            Load({ interfaceVersion = 16001 })
            assert.are.equal("Elsa Cacorchos", ns:GetCharacterDisplayName("Elsa-Cacorchos", { name = "Elsa" }))
        end)

        it("the same character under two spellings of its key counts once, newest first", function()
            Load({ interfaceVersion = 16001 })
            TestUtils.initDB()
            ns.GetCharacterKey = function() return "Tester-TestRealm" end
            EmbolsaoDB.characterItems = {
                ["Elsa-Cacorchos"] = { name = "Elsa", time = 1 },
                ["Elsa Cacorchos-TestRealm"] = { name = "Elsa Cacorchos", time = 2 },
            }
            local others = ns:GetOtherCharacters()
            assert.are.equal(1, #others)
            assert.are.equal(2, others[1].info.time)
        end)
    end)
end)
