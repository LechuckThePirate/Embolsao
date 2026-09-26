-- The bags key, done securely: an override binding for TOGGLEBACKPACK /
-- OPENALLBAGS that goes through a secure click button whose snippet shows or
-- hides the window, so the key works in combat too. Split out of UI.lua (see the
-- file-size and Lua 5.1 limits notes there); loads AFTER it and reaches the
-- windows through the UI table (UI.GetHost(), UI.bagsWindow, UI.bankWindow).
local _, Embolsao = ...
local UI = Embolsao.UI

--------------------------------------------------------------------------
-- The bags key, done securely.
--
-- In combat the game refuses to show or hide a window that has secure frames
-- below it -- from insecure code. Its own secure code may, and so may a secure
-- handler's snippet. So the bags key (TOGGLEBACKPACK / OPENALLBAGS) is bound,
-- with an override binding, to a secure click button whose snippet shows or
-- hides the window itself: that way the window can always be closed in combat
-- (and opened, unless "Close bags in combat" is on, which is what the
-- "blockopen" attribute says). Out of combat the click's PostClick then does
-- the ordinary bookkeeping (scan, layout, refresh) that the takeover of a native
-- bag frame normally does.
--
-- It needs the panes to be protected already (they are once their item buttons
-- have secure overlays) for the snippet to be given them, so it is set up from a
-- window's Refresh, once, and again whenever a pane newly qualifies. Until then
-- the key works the old way.
--------------------------------------------------------------------------
local TOGGLE_BINDING_ACTIONS = { "TOGGLEBACKPACK", "OPENALLBAGS" }

local TOGGLE_SNIPPET = [[
    local host = self:GetFrameRef("host")
    local bags = self:GetFrameRef("bags")
    local bank = self:GetFrameRef("bank")
    if not host or not bags then return end

    if host:IsShown() then
        if bank then bank:Hide() end
        bags:Hide()
        host:Hide()
    else
        if self:GetAttribute("blockopen") and self:GetAttribute("state-combat") == "1" then
            return
        end
        bags:Show()
        host:Show()
    end
]]

local secureToggle = CreateFrame("Button", "EmbolsaoSecureToggle", UIParent, "SecureHandlerClickTemplate")
secureToggle:RegisterForClicks("AnyUp")
secureToggle:SetAttribute("_onclick", TOGGLE_SNIPPET)
-- The snippet can't ask whether the player is in combat, but a state driver
-- keeps this attribute current in combat too.
pcall(RegisterStateDriver, secureToggle, "combat", "[combat] 1; 0")

local secureToggleRefs = {} -- which frames the snippet has been given so far
local secureToggleBindingsDirty = true
local secureToggleWorks = false -- the self-test below passed: safe to take the key

-- The snippet only works if the restricted environment hands it frame handles
-- that can show and hide the panes. That is decided by the game (a handle for a
-- frame that is only protected because of what hangs below it can be more
-- limited than one for a secure-template frame), so it is checked once with a
-- dry run before the key is taken over; if it fails the key stays Blizzard's
-- (the window then just can't be opened or closed with it in combat). What the
-- handles offered is also kept, for bug reports.
-- (Snippets may not contain the word "function" or any braces -- the game
-- refuses to compile them -- hence the repetition instead of a helper.)
local TOGGLE_SELFTEST = [[
    local h = self:GetFrameRef("host")
    local b = self:GetFrameRef("bags")
    local r = "host:"
    if h then r = r .. (h.Show and "S" or "-") .. (h.Hide and "H" or "-") .. (h.IsShown and "I" or "-") else r = r .. "nil" end
    r = r .. ";bags:"
    if b then r = r .. (b.Show and "S" or "-") .. (b.Hide and "H" or "-") .. (b.IsShown and "I" or "-") else r = r .. "nil" end
    self:SetAttribute("selftest", r .. ";")
]]

local function RunToggleSelfTest()
    secureToggle:SetAttribute("selftest", nil)
    -- A snippet that fails to run is reported by the game through the error
    -- handler even when pcall'd (that is what put the error dialog on screen
    -- on Forever, whose restricted environment can't compile snippets at all
    -- yet): swallow it for the length of the dry run.
    local failed = false
    local previousHandler = geterrorhandler()
    seterrorhandler(function() failed = true end)
    local ok = pcall(secureToggle.Execute, secureToggle, TOGGLE_SELFTEST)
    seterrorhandler(previousHandler)
    local result = (ok and not failed) and secureToggle:GetAttribute("selftest") or "error"
    secureToggleWorks = result == "host:SHI;bags:SHI;"
    if EmbolsaoDB then EmbolsaoDB.secureToggleSelfTest = tostring(result) end
end

local function ApplyToggleBindings()
    if InCombatLockdown() then
        secureToggleBindingsDirty = true
        return
    end
    ClearOverrideBindings(secureToggle)
    secureToggleBindingsDirty = false
    -- Minimap menu's "Disable Embolsao": leave the bags key entirely alone.
    if Embolsao.db and Embolsao.db.disabled then return end
    if not (secureToggleRefs.host and secureToggleRefs.bags and secureToggleWorks) then return end

    for _, action in ipairs(TOGGLE_BINDING_ACTIONS) do
        local key1, key2 = GetBindingKey(action)
        for _, key in ipairs({ key1 or false, key2 or false }) do
            if key then
                SetOverrideBindingClick(secureToggle, true, key, "EmbolsaoSecureToggle")
            end
        end
    end
end

function UI:SetupSecureToggle()
    local host = UI.GetHost()
    local bagsWindow, bankWindow = UI.bagsWindow, UI.bankWindow
    if InCombatLockdown() or not host then return end
    -- (The Classic "Forever" beta used to be skipped here: its restricted
    -- environment couldn't compile snippets at all. Blizzard has been fixing
    -- that client's rough edges, so it is no longer special-cased: the dry run
    -- below decides, and if it still fails the key simply stays Blizzard's.)

    local changed = false
    local function GiveFrame(label, frame)
        if secureToggleRefs[label] or not frame or not frame:IsProtected() then return end
        if pcall(secureToggle.SetFrameRef, secureToggle, label, frame) then
            secureToggleRefs[label] = true
            changed = true
        end
    end
    GiveFrame("host", host)
    GiveFrame("bags", bagsWindow.GetFrame())
    GiveFrame("bank", bankWindow.GetFrame())

    -- Once host and bags are both in, and again if either is given anew.
    if changed and secureToggleRefs.host and secureToggleRefs.bags then
        RunToggleSelfTest()
    end

    -- What "Close bags in combat" says about opening in combat.
    local blockOpen = (Embolsao.db and Embolsao.db.closeOnCombat) and true or nil
    if secureToggle:GetAttribute("blockopen") ~= blockOpen then
        secureToggle:SetAttribute("blockopen", blockOpen)
    end

    if changed or secureToggleBindingsDirty then
        ApplyToggleBindings()
    end
end

secureToggle:SetScript("PostClick", function()
    local host = UI.GetHost()
    if not host then return end
    local opened = host:IsShown()
    PlaySound(opened and SOUNDKIT.IG_BACKPACK_OPEN or SOUNDKIT.IG_BACKPACK_CLOSE)

    if InCombatLockdown() then
        -- Nothing can be laid out or refreshed now; both wait for combat's end.
        if opened then host.layoutPending = true end
        return
    end
    if opened then
        UI.bagsWindow.OpenDirect()
    end
    -- (Closing needs nothing more: the window's own OnHide does the rest.)
end)

local secureToggleEvents = CreateFrame("Frame")
secureToggleEvents:RegisterEvent("UPDATE_BINDINGS")
secureToggleEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
secureToggleEvents:SetScript("OnEvent", function()
    if InCombatLockdown() then
        secureToggleBindingsDirty = true
        return
    end
    if secureToggleBindingsDirty then
        ApplyToggleBindings()
    end
    UI:SetupSecureToggle()
end)

-- Preferences (Close bags in combat) or the minimap's Disable toggle changed.
function UI:RefreshSecureToggle()
    secureToggleBindingsDirty = true
    UI:SetupSecureToggle()
    ApplyToggleBindings()
end
