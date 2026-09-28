dofile("setupTests.lua")

local function LoadLocales(locale)
    TestUtils.resetEnvironment({ locale = locale })
    local ns = {}
    TestUtils.loadFile(ns, "Locales/Locales.lua")
    TestUtils.loadFile(ns, "Locales/enUS.lua")
    TestUtils.loadFile(ns, "Locales/esES.lua")
    return ns.L
end

-- Every key a locale file defines, read straight from its `strings` table.
local function KeysOf(path)
    local keys = {}
    for line in io.lines(path) do
        local key = line:match("^%s+([%u%d_]+)%s*=")
        if key then keys[key] = true end
    end
    return keys
end

describe("Locales", function()
    it("an untranslated key falls back to the key itself", function()
        local L = LoadLocales("enUS")
        assert.are.equal("SOME_MISSING_KEY", L.SOME_MISSING_KEY)
    end)

    it("enUS strings are used on an English client", function()
        local L = LoadLocales("enUS")
        assert.are.equal("All", L.ALL)
        assert.are.equal("Unbound", L.BINDING_UNBOUND)
    end)

    it("esES strings override enUS on a Spanish client", function()
        local L = LoadLocales("esES")
        assert.are.equal("Todo", L.ALL)
    end)

    it("esMX uses the Spanish strings too", function()
        local L = LoadLocales("esMX")
        assert.are.equal("Todo", L.ALL)
    end)

    it("an unsupported client locale gets the English strings", function()
        local L = LoadLocales("deDE")
        assert.are.equal("All", L.ALL)
    end)

    it("esES translates every enUS key", function()
        local missing = TestUtils.missingKeys(KeysOf("Locales/enUS.lua"), KeysOf("Locales/esES.lua"))
        assert.are.same({}, missing)
    end)

    it("esES defines no key enUS lacks", function()
        local extra = TestUtils.missingKeys(KeysOf("Locales/esES.lua"), KeysOf("Locales/enUS.lua"))
        assert.are.same({}, extra)
    end)

    it("format placeholders match between enUS and esES", function()
        local en, es = LoadLocales("enUS"), nil
        local enStrings = {}
        for key in pairs(KeysOf("Locales/enUS.lua")) do enStrings[key] = en[key] end
        es = LoadLocales("esES")
        for key, text in pairs(enStrings) do
            local function Placeholders(s)
                local list = {}
                for p in tostring(s):gmatch("%%[%d%.]*[sdf]") do table.insert(list, p) end
                return table.concat(list, " ")
            end
            assert.are.equal(Placeholders(text), Placeholders(es[key]), key)
        end
    end)
end)
