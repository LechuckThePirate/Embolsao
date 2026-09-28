-- Shared helpers for the *.test.lua specs: a fresh fake client per test, and
-- loading the addon's own files the way the game does (in .toc order, each
-- one called with the addon name and the shared namespace table as `...`).
TestUtils = {}

TestUtils.ADDON_NAME = "Embolsao"
TestUtils.TOC_PATH = "Embolsao.toc"

-- The files the .toc loads, in order, with forward slashes.
function TestUtils.getTocFiles()
    local files = {}
    for line in io.lines(TestUtils.TOC_PATH) do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") then
            table.insert(files, (line:gsub("\\", "/")))
        end
    end
    return files
end

-- Installs a brand new fake client and clears the saved variables. Returns
-- the mock's state table (items, bags, equipped, timers...).
function TestUtils.resetEnvironment(options)
    _G.EmbolsaoDB = nil
    _G.EmbolsaoCharDB = nil
    TestUtils.state = WowApiMock.install(options)
    return TestUtils.state
end

function TestUtils.loadFile(ns, path)
    local chunk = assert(loadfile(path))
    chunk(TestUtils.ADDON_NAME, ns)
end

-- Loads every .toc file up to and including `lastPath` (or all of them) into a
-- new namespace, and returns it -- the same table the addon's files share as
-- `local _, Embolsao = ...` in game.
function TestUtils.loadAddon(lastPath)
    local ns = {}
    local found = lastPath == nil
    for _, path in ipairs(TestUtils.getTocFiles()) do
        TestUtils.loadFile(ns, path)
        if path == lastPath then
            found = true
            break
        end
    end
    assert(found, "not in the .toc: " .. tostring(lastPath))
    return ns
end

-- Every frame that registered `event` gets its OnEvent script run, like the
-- client would.
function TestUtils.fireEvent(event, ...)
    for _, frame in ipairs(TestUtils.state.frames) do
        if frame.__events[event] and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

-- ADDON_LOADED for this addon: builds Embolsao.db from the saved variables.
function TestUtils.initDB()
    TestUtils.fireEvent("ADDON_LOADED", TestUtils.ADDON_NAME)
end

-- The whole addon, loaded and logged in (saved variables built, PLAYER_LOGIN
-- fired). Returns the namespace.
function TestUtils.startAddon()
    local ns = TestUtils.loadAddon()
    TestUtils.initDB()
    TestUtils.fireEvent("PLAYER_LOGIN")
    return ns
end

-- Runs every queued C_Timer callback, including ones queued while running.
function TestUtils.runTimers()
    local timers = TestUtils.state.timers
    local guard = 0
    while #timers > 0 do
        guard = guard + 1
        assert(guard < 1000, "timers keep rescheduling themselves")
        local timer = table.remove(timers, 1)
        timer.fn()
    end
end

-- Recorded calls to a mocked API (see WowApiMock's Record), or {}.
function TestUtils.calls(name)
    return TestUtils.state.calls[name] or {}
end

-- Declares an item the fake client knows about.
function TestUtils.addItem(itemID, data)
    data.name = data.name or ("Item " .. itemID)
    TestUtils.state.items[itemID] = data
end

-- Puts a bag of `size` slots at bagID with the given { [slot] = {...} }.
function TestUtils.setBag(bagID, size, slots, family)
    TestUtils.state.bags[bagID] = { size = size, slots = slots or {}, family = family or 0 }
end

-- Keys absent from a table, for asserting two locale tables line up.
function TestUtils.missingKeys(expected, actual)
    local missing = {}
    for key in pairs(expected) do
        if rawget(actual, key) == nil then
            table.insert(missing, key)
        end
    end
    table.sort(missing)
    return missing
end


