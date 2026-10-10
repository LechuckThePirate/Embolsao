-- A stand-in for the WoW client API, just enough for the addon's files to load
-- and for their logic to be exercised outside the game. Every test starts from
-- a fresh copy (TestUtils.resetEnvironment), so nothing leaks between tests.
--
-- Game state the tests control lives on the returned `state` table:
--   state.items[itemID]   = { name, quality, equipLoc, classID, subClassID, icon, itemLevel }
--   state.bags[bagID]     = { size = n, family = 0, slots = { [slot] = { itemID, stackCount, quality, isNew, isLocked, questInfo } } }
--   state.equipped[slot]  = itemID
--   state.modifiers       = { ALT = bool, CTRL = bool, SHIFT = bool }
--   state.timers          = pending C_Timer.After callbacks (run with TestUtils.runTimers)
WowApiMock = {}

local ITEM_CLASS_NAMES = {
    [0] = "Consumable", [1] = "Container", [2] = "Weapon", [4] = "Armor",
    [5] = "Reagent", [7] = "Tradeskill", [12] = "Quest", [15] = "Miscellaneous",
}

local ITEM_SUBCLASS_NAMES = {
    [2] = { [0] = "One-Handed Axes", [1] = "Two-Handed Axes", [7] = "One-Handed Swords", [15] = "Daggers" },
    [4] = { [0] = "Miscellaneous", [1] = "Cloth", [2] = "Leather", [6] = "Shields" },
    [0] = { [0] = "Explosives and Devices", [1] = "Potion" },
}

--------------------------------------------------------------------------
-- Frames: permissive mocks. Anything the tests don't care about is a no-op;
-- Create* methods hand back child frames so builder code can chain; scripts
-- and registered events are remembered so tests can fire them.
--------------------------------------------------------------------------
local function NewFrame(state, frameType, name)
    local frame = {
        __frameType = frameType,
        __name = name,
        __scripts = {},
        __hooks = {},
        __events = {},
        __attributes = {},
        __shown = true,
        __points = {},
        __width = 0,
        __height = 0,
    }

    local methods = {}
    function methods:GetName() return self.__name end
    function methods:GetObjectType() return self.__frameType end
    function methods:SetScript(scriptName, fn) self.__scripts[scriptName] = fn end
    function methods:GetScript(scriptName) return self.__scripts[scriptName] end
    function methods:HookScript(scriptName, fn)
        self.__hooks[scriptName] = self.__hooks[scriptName] or {}
        table.insert(self.__hooks[scriptName], fn)
    end
    function methods:HasScript() return true end
    function methods:RegisterEvent(event) self.__events[event] = true end
    function methods:UnregisterEvent(event) self.__events[event] = nil end
    function methods:UnregisterAllEvents() self.__events = {} end
    function methods:IsEventRegistered(event) return self.__events[event] == true end
    -- Like the client: OnShow / OnHide (and their hooks) run when visibility
    -- actually changes.
    local function RunScript(self, scriptName, ...)
        if self.__scripts[scriptName] then self.__scripts[scriptName](self, ...) end
        for _, hook in ipairs(self.__hooks[scriptName] or {}) do hook(self, ...) end
    end
    frame.__runScript = RunScript
    -- Visible = shown and every parent shown too; OnShow/OnHide only fire for
    -- a frame whose parent is visible, as in game.
    local function ParentVisible(self)
        local parent = rawget(self, "__parent")
        return parent == nil or type(parent) ~= "table" or not parent.IsVisible or parent:IsVisible()
    end
    function methods:Show()
        if self.__shown then return end
        self.__shown = true
        if ParentVisible(self) then RunScript(self, "OnShow") end
    end
    function methods:Hide()
        if not self.__shown then return end
        self.__shown = false
        if ParentVisible(self) then RunScript(self, "OnHide") end
    end
    function methods:SetShown(shown)
        if shown then self:Show() else self:Hide() end
    end
    function methods:Click(button)
        RunScript(self, "PreClick", button or "LeftButton", false)
        RunScript(self, "OnClick", button or "LeftButton", false)
        RunScript(self, "PostClick", button or "LeftButton", false)
    end
    function methods:IsShown() return self.__shown end
    function methods:IsVisible()
        local parent = rawget(self, "__parent")
        if not self.__shown then return false end
        if type(parent) == "table" and parent.IsVisible then return parent:IsVisible() end
        return true
    end
    function methods:SetAttribute(key, value) self.__attributes[key] = value end
    function methods:GetAttribute(key) return self.__attributes[key] end
    function methods:SetSize(w, h) self.__width, self.__height = w, h end
    function methods:SetToplevel(on) self.__toplevel = on end
    function methods:SetBackdrop(backdrop) self.__backdrop = backdrop end
    function methods:SetBackdropColor(r, g, b, a) self.__backdropColor = { r, g, b, a } end
    function methods:SetWidth(w) self.__width = w end
    function methods:SetHeight(h) self.__height = h end
    function methods:GetWidth() return self.__width end
    function methods:GetHeight() return self.__height end
    function methods:GetSize() return self.__width, self.__height end
    function methods:GetScale() return 1 end
    function methods:GetEffectiveScale() return 1 end
    function methods:GetAlpha() return 1 end
    function methods:GetFrameLevel() return 1 end
    function methods:GetFrameStrata() return "MEDIUM" end
    function methods:GetCenter() return 0, 0 end
    function methods:GetLeft() return 0 end
    function methods:GetRight() return 0 end
    function methods:GetTop() return 0 end
    function methods:GetBottom() return 0 end
    function methods:GetNumPoints() return 0 end
    function methods:GetID() return self.__id or 0 end
    function methods:SetID(id) self.__id = id end
    function methods:GetParent() return self.__parent end
    function methods:SetParent(parent) self.__parent = parent end
    function methods:GetText() return self.__text end
    function methods:SetText(text) self.__text = text end
    function methods:GetStringWidth() return 0 end
    function methods:GetTextWidth() return 0 end
    function methods:GetTextHeight() return 0 end
    function methods:GetStringHeight() return 0 end
    function methods:GetChecked() return self.__checked end
    function methods:SetChecked(checked) self.__checked = checked end
    function methods:GetValue() return self.__value or 0 end
    function methods:SetValue(value) self.__value = value end
    function methods:GetMinMaxValues() return 0, 0 end
    function methods:GetVerticalScroll() return 0 end
    function methods:GetVerticalScrollRange() return 0 end
    function methods:IsMouseOver() return false end
    function methods:IsProtected() return false end
    function methods:IsForbidden() return false end
    function methods:GetChildren() return end
    function methods:GetRegions() return end
    function methods:GetFontString() return self.__fontString end
    function methods:GetNormalTexture() return NewFrame(state, "Texture") end
    function methods:GetHighlightTexture() return NewFrame(state, "Texture") end
    function methods:GetPushedTexture() return NewFrame(state, "Texture") end
    function methods:GetThumbTexture() return NewFrame(state, "Texture") end
    function methods:GetCheckedTexture() return NewFrame(state, "Texture") end
    function methods:GetDisabledTexture() return NewFrame(state, "Texture") end
    function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function methods:NumLines() return 0 end
    function methods:GetOwner() return self.__owner end
    function methods:SetOwner(owner) self.__owner = owner end
    function methods:GetItem() return nil, nil end
    function methods:CreateTexture() return NewFrame(state, "Texture") end
    function methods:CreateFontString()
        local fs = NewFrame(state, "FontString")
        self.__fontString = fs
        return fs
    end
    function methods:CreateAnimationGroup() return NewFrame(state, "AnimationGroup") end
    function methods:CreateAnimation() return NewFrame(state, "Animation") end
    function methods:CreateMaskTexture() return NewFrame(state, "MaskTexture") end
    function methods:CreateLine() return NewFrame(state, "Line") end

    if frameType ~= "Auto" then
        table.insert(state.frames, frame)
    end

    return setmetatable(frame, {
        __index = function(self, key)
            if methods[key] then return methods[key] end
            -- Lowercase fields are the addon's own data on its frames
            -- (frame.currentTabs, btn.itemID...), and __ ones the mock's:
            -- unset is just nil, as in game.
            if type(key) ~= "string" or not key:match("^%u") then return nil end
            -- Anything Capitalized is either a method nobody tests (calling it
            -- does nothing, returns nil) or a child region a template would
            -- have made (TitleContainer, NineSlice, ScrollBar...): one object
            -- that works as both, kept so the same child comes back every time.
            local child = NewFrame(state, "Auto")
            rawset(self, key, child)
            return child
        end,
        __call = function() end,
    })
end
WowApiMock.NewFrame = NewFrame

--------------------------------------------------------------------------
-- Installs a fresh copy of the client API into _G and returns its state.
--------------------------------------------------------------------------
-- Globals made by CreateFrame(type, "Name") -- dropped on every install, so a
-- window built by one test isn't still there in the next.
WowApiMock.namedFrames = {}

function WowApiMock.install(options)
    options = options or {}
    for name in pairs(WowApiMock.namedFrames) do _G[name] = nil end
    WowApiMock.namedFrames = {}
    local state = {
        items = {},
        bags = {},
        equipped = {},
        modifiers = { ALT = false, CTRL = false, SHIFT = false },
        timers = {},
        frames = {},
        calls = {}, -- name -> list of argument lists, for API calls tests assert on
        interfaceVersion = options.interfaceVersion or 120100,
        projectID = options.projectID or 1,
        playerName = "Tester",
        realmName = "Test Realm",
        money = 0,
    }

    local function Record(name, ...)
        state.calls[name] = state.calls[name] or {}
        table.insert(state.calls[name], { ... })
    end

    -- Lua 5.1 / WoW globals that plain Lua (5.1 through 5.4) lacks.
    _G.unpack = _G.unpack or table.unpack
    _G.wipe = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
    _G.tinsert = table.insert
    _G.tremove = table.remove
    _G.strsplit = function(delimiter, text)
        local parts = {}
        for part in (text .. delimiter):gmatch("(.-)" .. delimiter:gsub("%p", "%%%0")) do
            table.insert(parts, part)
        end
        return unpack(parts)
    end
    _G.strmatch = string.match
    _G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    _G.strcmputf8i = nil
    _G.time = os.time
    _G.date = os.date
    _G.debugstack = function() return "" end
    _G.tContains = function(t, value)
        for _, v in pairs(t) do
            if v == value then return true end
        end
        return false
    end
    local errorHandler = error
    _G.geterrorhandler = function() return errorHandler end
    _G.seterrorhandler = function(handler) errorHandler = handler end
    math.atan2 = math.atan2 or math.atan
    _G.print = function() end -- keep test output clean

    -- Client identity.
    _G.WOW_PROJECT_MAINLINE = 1
    _G.WOW_PROJECT_CLASSIC = 2
    _G.WOW_PROJECT_ID = state.projectID
    _G.GetBuildInfo = function()
        return "12.0.1", "99999", "Jan 1 2026", state.interfaceVersion
    end
    _G.GetLocale = function() return options.locale or "enUS" end
    _G.GetTime = function() return 0 end
    _G.GetServerTime = os.time
    _G.InCombatLockdown = function() return false end

    -- Player.
    _G.UnitName = function() return state.playerName end
    _G.UnitFullName = function() return state.playerName, state.realmName end
    _G.GetUnitName = function() return state.playerName end
    _G.GetRealmName = function() return state.realmName end
    _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    _G.UnitLevel = function() return 80 end
    _G.GetMoney = function() return state.money end
    _G.IsAltKeyDown = function() return state.modifiers.ALT end
    _G.IsControlKeyDown = function() return state.modifiers.CTRL end
    _G.IsShiftKeyDown = function() return state.modifiers.SHIFT end
    _G.IsModifiedClick = function() return false end
    _G.GetCursorPosition = function() return 0, 0 end
    _G.CursorHasItem = function() return state.cursor ~= nil end
    _G.ClearCursor = function()
        Record("ClearCursor")
        state.cursor = nil
    end
    _G.GetCursorInfo = function() return nil end

    -- Items.
    local function ItemLink(itemID)
        return itemID and ("|cffffffff|Hitem:" .. itemID .. "::::::::|h[" .. tostring(itemID) .. "]|h|r")
    end
    state.ItemLink = ItemLink

    local function GetItemInfo(item)
        local itemID = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
        local data = itemID and state.items[itemID]
        if not data then return nil end
        return data.name, ItemLink(itemID), data.quality or 1, data.itemLevel or 1, 1,
            ITEM_CLASS_NAMES[data.classID or 15], "", data.maxStack or 1, data.equipLoc or "",
            data.icon or 134400, data.sellPrice or 0, data.classID or 15, data.subClassID or 0
    end
    local function GetItemInfoInstant(item)
        local itemID = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
        local data = itemID and state.items[itemID]
        if not data then return nil end
        return itemID, ITEM_CLASS_NAMES[data.classID or 15], "", data.equipLoc or "",
            data.icon or 134400, data.classID or 15, data.subClassID or 0
    end
    _G.GetItemInfo = GetItemInfo
    _G.GetItemInfoInstant = GetItemInfoInstant
    _G.C_Item = {
        GetItemInfo = GetItemInfo,
        GetItemInfoInstant = GetItemInfoInstant,
        GetItemClassInfo = function(classID) return ITEM_CLASS_NAMES[classID] end,
        GetItemSubClassInfo = function(classID, subClassID)
            return ITEM_SUBCLASS_NAMES[classID] and ITEM_SUBCLASS_NAMES[classID][subClassID]
        end,
        GetItemQualityColor = function(quality) return quality / 10, quality / 10, quality / 10 end,
        GetDetailedItemLevelInfo = function(item)
            local itemID = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
            return state.items[itemID] and state.items[itemID].itemLevel
        end,
        GetItemStats = function() return {} end,
        EquipItemByName = function(itemID, slot) Record("EquipItemByName", itemID, slot) end,
        -- Takes the worn item onto the cursor (see PickupContainerItem).
        PickupInventoryItem = function(slot)
            Record("PickupInventoryItem", slot)
            if state.cursor == nil and state.equipped[slot] then
                state.cursor = state.equipped[slot]
                state.equipped[slot] = nil
            end
        end,
        PutItemInBackpack = function() Record("PutItemInBackpack") end,
    }
    _G.ITEM_QUALITY_COLORS = {}

    -- Bags.
    _G.BACKPACK_CONTAINER = 0
    _G.NUM_BAG_SLOTS = 4
    _G.KEYRING_CONTAINER = -2
    _G.BANK_CONTAINER = -1
    _G.C_Container = {
        GetContainerNumSlots = function(bagID)
            return state.bags[bagID] and state.bags[bagID].size or 0
        end,
        GetContainerNumFreeSlots = function(bagID)
            local bag = state.bags[bagID]
            if not bag then return 0, 0 end
            local used = 0
            for _ in pairs(bag.slots or {}) do used = used + 1 end
            return bag.size - used, bag.family or 0
        end,
        GetContainerItemInfo = function(bagID, slot)
            local bag = state.bags[bagID]
            local saved = bag and bag.slots and bag.slots[slot]
            if not saved then return nil end
            local item = state.items[saved.itemID] or {}
            return {
                itemID = saved.itemID,
                stackCount = saved.stackCount or 1,
                quality = saved.quality or item.quality,
                iconFileID = item.icon or 134400,
                hyperlink = ItemLink(saved.itemID),
                isLocked = saved.isLocked or false,
            }
        end,
        GetContainerItemQuestInfo = function(bagID, slot)
            local bag = state.bags[bagID]
            local saved = bag and bag.slots and bag.slots[slot]
            return (saved and saved.questInfo) or { isQuestItem = false, isActive = false }
        end,
        -- Drops what the cursor holds into an empty slot of a bag.
        PickupContainerItem = function(bagID, slot)
            Record("PickupContainerItem", bagID, slot)
            local bag = state.bags[bagID]
            if state.cursor and bag and slot <= bag.size and not bag.slots[slot] then
                bag.slots[slot] = { itemID = state.cursor }
                state.cursor = nil
            end
        end,
        SplitContainerItem = function(bagID, slot, amount) Record("SplitContainerItem", bagID, slot, amount) end,
        UseContainerItem = function(bagID, slot) Record("UseContainerItem", bagID, slot) end,
    }
    _G.C_NewItems = {
        IsNewItem = function(bagID, slot)
            local bag = state.bags[bagID]
            local saved = bag and bag.slots and bag.slots[slot]
            return saved ~= nil and saved.isNew == true
        end,
        RemoveNewItem = function(bagID, slot)
            local bag = state.bags[bagID]
            local saved = bag and bag.slots and bag.slots[slot]
            if saved then saved.isNew = false end
        end,
    }

    -- Equipment.
    _G.GetInventoryItemID = function(_, slot) return state.equipped[slot] end
    _G.GetInventoryItemLink = function(_, slot) return ItemLink(state.equipped[slot]) end
    _G.GetInventoryItemTexture = function() return 134400 end
    _G.GetInventoryItemQuality = function(_, slot)
        local itemID = state.equipped[slot]
        return itemID and state.items[itemID] and state.items[itemID].quality
    end

    -- Timers: queued, run explicitly by the test (TestUtils.runTimers).
    _G.C_Timer = {
        After = function(seconds, fn) table.insert(state.timers, { seconds = seconds, fn = fn }) end,
        NewTimer = function(seconds, fn)
            table.insert(state.timers, { seconds = seconds, fn = fn })
            return { Cancel = function() end }
        end,
        NewTicker = function() return { Cancel = function() end } end,
    }

    -- Addon metadata.
    _G.C_AddOns = {
        GetAddOnMetadata = function(_, field) return field == "Version" and "1.0.0-test" or nil end,
        IsAddOnLoaded = function() return false end,
    }
    _G.GetAddOnMetadata = _G.C_AddOns.GetAddOnMetadata

    -- Frames and the handful of global Blizzard frames the addon touches.
    _G.CreateFrame = function(frameType, name, parent, template)
        local frame = NewFrame(state, frameType, name)
        frame.__parent = parent
        -- Item buttons (the frame type, or a template built on it) come with a
        -- few lowercase children.
        if frameType == "ItemButton" or (type(template) == "string" and template:find("ItemButton")) then
            frame.icon = NewFrame(state, "Texture")
            frame.searchOverlay = NewFrame(state, "Texture")
        end
        if name then
            _G[name] = frame
            WowApiMock.namedFrames[name] = true
        end
        return frame
    end
    _G.UIParent = NewFrame(state, "Frame", "UIParent")
    _G.Minimap = NewFrame(state, "Minimap", "Minimap")
    _G.GameTooltip = NewFrame(state, "GameTooltip", "GameTooltip")
    _G.ItemRefTooltip = NewFrame(state, "GameTooltip", "ItemRefTooltip")
    _G.UIErrorsFrame = NewFrame(state, "MessageFrame", "UIErrorsFrame")
    _G.StackSplitFrame = NewFrame(state, "Frame", "StackSplitFrame")
    _G.UISpecialFrames = {}
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(...) Record("StaticPopup_Show", ...) end
    _G.IconDataProviderExtraType = { None = 0, Spellbook = 1, Equipment = 2 }
    _G.RAID_CLASS_COLORS = {}
    _G.GameTooltip_Hide = function() GameTooltip:Hide() end
    _G.UnitXP = function() return 0 end
    _G.UnitXPMax = function() return 1 end
    _G.GetXPExhaustion = function() return nil end
    _G.IsXPUserDisabled = function() return false end
    _G.IsPlayerAtEffectiveMaxLevel = function() return true end
    _G.GetUnitSpeed = function() return 0 end
    _G.SpellIsTargeting = function() return false end
    _G.SpellCanTargetItem = function() return false end
    _G.SpellCanTargetItemID = function() return false end
    _G.ResetCursor = function() end
    _G.SetMoneyFrameColorByFrame = function() end
    _G.CloseBankFrame = function() Record("CloseBankFrame") end
    _G.OpenBackpack = function() Record("OpenBackpack") end
    _G.ToggleBackpack = function() Record("ToggleBackpack") end
    _G.ToggleBag = function(bagID) Record("ToggleBag", bagID) end
    _G.IconDataProviderMixin = {
        Init = function() end,
        GetNumIcons = function() return 0 end,
        GetIconByIndex = function() return nil end,
        Release = function() end,
    }
    _G.CreateAndInitFromMixin = function(mixin, ...)
        local object = setmetatable({}, { __index = mixin })
        if object.Init then object:Init(...) end
        return object
    end
    _G.SetItemButtonTexture =function(button, texture) button.__texture = texture end
    _G.SetItemButtonCount = function(button, count) button.__count = count end
    _G.SetItemButtonQuality = function() end
    _G.SetItemButtonDesaturated = function() end
    _G.SmallMoneyFrame_OnLoad = function() end
    _G.MoneyFrame_SetType = function() end
    _G.MoneyFrame_Update = function() end
    _G.BankFrame_Open = function() end
    _G.ChatEdit_InsertLink = function() return false end
    _G.ChatFrame_OpenChat = function() end
    _G.ToggleAllBags = function() Record("ToggleAllBags") end

    -- Context menus: the menu a generator builds is kept on state.lastMenu as
    -- a flat list of { kind, text, callback... } so tests can read and click it.
    local function NewMenuDescription(entries)
        local description = {}
        local function Add(kind, text, a, b, c)
            local entry = { kind = kind, text = text, a = a, b = b, c = c }
            table.insert(entries, entry)
            return setmetatable({}, { __index = function() return function() end end })
        end
        function description:CreateTitle(text) return Add("title", text) end
        function description:CreateButton(text, callback) return Add("button", text, callback) end
        function description:CreateCheckbox(text, isSelected, setSelected) return Add("checkbox", text, isSelected, setSelected) end
        function description:CreateRadio(text, isSelected, setSelected, data) return Add("radio", text, isSelected, setSelected, data) end
        function description:CreateDivider() return Add("divider") end
        return setmetatable(description, { __index = function() return function() end end })
    end
    _G.MenuUtil = {
        CreateContextMenu = function(owner, generator)
            local entries = {}
            generator(owner, NewMenuDescription(entries))
            state.lastMenu = entries
        end,
    }
    state.findMenuEntry = function(text)
        for _, entry in ipairs(state.lastMenu or {}) do
            if entry.text == text then return entry end
        end
        return nil
    end

    -- Same contract as the client's: runs `hook` after the original, with the
    -- same arguments, and leaves the original's return values alone.
    _G.hooksecurefunc = function(target, name, hook)
        if type(target) == "string" then
            target, name, hook = _G, target, name
        end
        local original = target[name]
        if type(original) ~= "function" then return end
        target[name] = function(...)
            local results = { original(...) }
            hook(...)
            return unpack(results)
        end
    end
    _G.RegisterStateDriver = function() end
    _G.SetOverrideBindingClick = function() end
    _G.ClearOverrideBindings = function() end
    _G.GetBindingKey = function() return nil end
    _G.PlaySound = function() end
    _G.SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
    _G.Enum = {
        BagIndex = setmetatable({ ReagentBag = 5 }, { __index = function() return 0 end }),
        ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4 },
    }
    _G.CLOSE, _G.YES, _G.NO, _G.OKAY, _G.CANCEL = "Close", "Yes", "No", "Okay", "Cancel"
    _G.CONTINUE, _G.PREVIOUS, _G.NEXT = "Continue", "Previous", "Next"

    return state
end


