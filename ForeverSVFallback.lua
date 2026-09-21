-- TEMPORARY WORKAROUND -- delete this file, its line in Embolsao.toc and the
-- RestoreSavedVariablesFallback() call in Core.lua once Blizzard fixes the
-- Classic "Forever" beta (client 1.60.x) not handing SavedVariables back to
-- addons on load.
--
-- Symptom on that build: the client WRITES EmbolsaoDB/EmbolsaoCharDB to disk
-- normally on logout/reload, but on the next load both globals are nil when
-- ADDON_LOADED fires, so every setting resets. Other addons (Questie,
-- Auctionator) are hit too. CVars registered through C_CVar.RegisterCVar are
-- kept in the client's memory for as long as the process lives, so this
-- mirrors both saved-variable tables into a chunked, encoded set of CVars and
-- restores them when -- and only when -- the client hands us nothing.
--
-- LIMITATION (verified 2026-09-21): that only survives /reload. The CVars
-- are not written to Config.wtf / config-cache.wtf, so quitting the game
-- loses them and the next launch starts from defaults again.
--
-- Inert on every other client: gated on the build number, and on a healthy
-- client the SavedVariables are already populated so nothing is restored.

local ADDON_NAME, Embolsao = ...

local build = select(4, GetBuildInfo())
if not (build >= 16000 and build < 20000) then return end

local PREFIX = "embolsaoSV"
local COUNT_CVAR = PREFIX .. "N"
local CHUNK_SIZE = 240 -- conservative; a CVar's max length isn't documented
local SAVE_INTERVAL = 10 -- seconds; also saved on PLAYER_LOGOUT

local GetCVarValue = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVarValue = (C_CVar and C_CVar.SetCVar) or SetCVar
local RegisterCVarName = (C_CVar and C_CVar.RegisterCVar) or RegisterCVar

local active = false
local charKey
local chars = {} -- [characterKey] = EmbolsaoCharDB, for every character seen so far
local lastSaved
local registered = {}
local warnedTruncation = false

--------------------------------------------------------------------------
-- Serialization: deterministic (sorted keys) so an unchanged table produces
-- an identical string and the periodic save can skip the write.
--------------------------------------------------------------------------

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        local kt = type(k)
        if kt == "string" or kt == "number" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return keys
end

local function Serialize(value, out, depth)
    local t = type(value)
    if t == "table" and depth < 20 then
        out[#out + 1] = "{"
        for _, k in ipairs(SortedKeys(value)) do
            local v = value[k]
            local vt = type(v)
            if vt == "table" or vt == "string" or vt == "number" or vt == "boolean" then
                out[#out + 1] = "["
                Serialize(k, out, depth + 1)
                out[#out + 1] = "]="
                Serialize(v, out, depth + 1)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = string.format("%q", value)
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            out[#out + 1] = "0"
        else
            out[#out + 1] = string.format("%.17g", value)
        end
    elseif t == "boolean" then
        out[#out + 1] = value and "true" or "false"
    else
        out[#out + 1] = "nil"
    end
end

-- Config.wtf stores CVars as SET name "value" lines, so anything that could
-- break that (quotes, backslashes, control characters, non-ASCII bytes) is
-- percent-escaped; the rest of the serialized text passes through unchanged.
local function Encode(raw)
    return (raw:gsub('[%c"%%\\\128-\255]', function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function Decode(encoded)
    return (encoded:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function Deserialize(raw)
    local loader = loadstring or load
    local fn = loader("return " .. raw)
    if not fn then return nil end
    if setfenv then setfenv(fn, {}) end
    local ok, result = pcall(fn)
    if ok and type(result) == "table" then return result end
    return nil
end

--------------------------------------------------------------------------
-- CVar storage
--------------------------------------------------------------------------

local function EnsureRegistered(name)
    if registered[name] then return end
    registered[name] = true
    pcall(RegisterCVarName, name, "")
end

local function ReadBlob()
    local okCount, countValue = pcall(GetCVarValue, COUNT_CVAR)
    local count = okCount and tonumber(countValue)
    if not count or count < 1 then return nil end

    local parts = {}
    for i = 1, count do
        local ok, value = pcall(GetCVarValue, PREFIX .. i)
        if not ok or value == nil then return nil end
        parts[i] = value
    end
    return Deserialize(Decode(table.concat(parts)))
end

local function Save()
    if not active or type(EmbolsaoDB) ~= "table" then return end

    if charKey and type(EmbolsaoCharDB) == "table" then
        chars[charKey] = EmbolsaoCharDB
    end

    local out = {}
    Serialize({ db = EmbolsaoDB, chars = chars }, out, 0)
    local raw = table.concat(out)
    if raw == lastSaved then return end

    local encoded = Encode(raw)
    local count = math.ceil(#encoded / CHUNK_SIZE)
    for i = 1, count do
        local name = PREFIX .. i
        local chunk = encoded:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
        EnsureRegistered(name)
        SetCVarValue(name, chunk)
        if not warnedTruncation and GetCVarValue(name) ~= chunk then
            warnedTruncation = true
            print("|cffff8800[Embolsao]|r Forever fallback storage: a saved chunk didn't read back intact -- settings may not persist across reloads.")
        end
    end
    -- Written last, so a half-finished save is never mistaken for a complete one.
    EnsureRegistered(COUNT_CVAR)
    SetCVarValue(COUNT_CVAR, tostring(count))
    lastSaved = raw
end

--------------------------------------------------------------------------
-- Entry point, called from Core.lua's ADDON_LOADED handler right before
-- InitDB() -- the only moment EmbolsaoDB/EmbolsaoCharDB can still be nil
-- without InitDB having already replaced them with fresh defaults.
--------------------------------------------------------------------------

function Embolsao:RestoreSavedVariablesFallback()
    if EmbolsaoDB ~= nil and EmbolsaoCharDB ~= nil then return end -- client behaved; nothing to do

    active = true

    local playerName, realmName = UnitName("player"), GetRealmName()
    if playerName and realmName then
        charKey = playerName .. "-" .. realmName
    end

    local blob = ReadBlob()
    if not blob then return end
    if type(blob.chars) == "table" then chars = blob.chars end

    local restored = false
    if EmbolsaoDB == nil and type(blob.db) == "table" then
        EmbolsaoDB = blob.db
        restored = true
    end
    if EmbolsaoCharDB == nil and charKey and type(chars[charKey]) == "table" then
        EmbolsaoCharDB = chars[charKey]
        restored = true
    end

    if restored then
        print("|cff00ff00[Embolsao]|r Forever beta workaround: settings restored from fallback storage.")
    end
end

local saveFrame = CreateFrame("Frame")
saveFrame:RegisterEvent("PLAYER_LOGIN")
saveFrame:RegisterEvent("PLAYER_LOGOUT")
saveFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if active then
            C_Timer.NewTicker(SAVE_INTERVAL, Save)
        end
    else
        Save()
    end
end)
