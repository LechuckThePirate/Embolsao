-- Adds "In your bank: N" (and the Warband bank's) to item tooltips anywhere --
-- crafting ingredients, chat links, vendors, the character sheet -- from the
-- offline bank's saved copies (Core.lua's GetBankSnapshot), so it works away
-- from a banker. No offline copy, no line: turning "Offline Bank" off in
-- Preferences also turns this off.
local _, Embolsao = ...
local L = Embolsao.L

-- itemID -> total, rebuilt only when the saved copy itself changes (every save
-- makes a new table, so comparing the reference is enough).
local cache = { PERSONAL = {}, WARBAND = {} }

local function CountsFor(view)
    local snapshot = Embolsao:GetBankSnapshot(view)
    if not snapshot then return nil end
    local entry = cache[view]
    if entry.snapshot ~= snapshot then
        local counts = {}
        for _, bag in pairs(snapshot.bags or {}) do
            for _, saved in pairs(bag.slots or {}) do
                if saved.i then
                    counts[saved.i] = (counts[saved.i] or 0) + (saved.c or 1)
                end
            end
        end
        entry.snapshot, entry.counts = snapshot, counts
    end
    return entry.counts
end

-- The other characters, from the counts each one saved at logout (account-wide,
-- so any character can read them): "Pepito: 5 in bags, 10 in bank".
local function AddOtherCharacterLines(tooltip, itemID)
    local others = Embolsao:GetOtherCharacters()
    table.sort(others, function(a, b) return a.key < b.key end)
    for _, character in ipairs(others) do
        local key, info = character.key, character.info
        local inBags = info.bags and info.bags[itemID]
        local inBank = info.bank and info.bank[itemID]
        if inBags or inBank then
            local parts = {}
            if inBags then parts[#parts + 1] = L.TOOLTIP_CHAR_BAGS:format(inBags) end
            if inBank then parts[#parts + 1] = L.TOOLTIP_CHAR_BANK:format(inBank) end
            local color = info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class]
            local name = color and ("|c" .. (color.colorStr or "ffffffff") .. Embolsao:GetCharacterDisplayName(key, info) .. "|r") or Embolsao:GetCharacterDisplayName(key, info)
            tooltip:AddLine(name .. ": " .. table.concat(parts, ", "), 0.8, 0.8, 0.8)
        end
    end
end

local function AddBankLines(tooltip, itemID)
    if not itemID or not Embolsao.db or Embolsao.db.offlineBank == false then return end
    local personal, warband = CountsFor("PERSONAL"), CountsFor("WARBAND")
    local inBank = personal and personal[itemID]
    local inWarband = warband and warband[itemID]
    if inBank then
        tooltip:AddLine(L.TOOLTIP_IN_BANK:format(inBank), 0.4, 0.8, 1)
    end
    if inWarband then
        tooltip:AddLine(L.TOOLTIP_IN_WARBAND_BANK:format(inWarband), 0.4, 0.8, 1)
    end
    AddOtherCharacterLines(tooltip, itemID)
end

-- The item a tooltip is about: the tooltip data's id, else its hyperlink, else
-- (older clients / reagent tooltips that carry neither) the tooltip's own item.
local function TooltipItemID(tooltip, data)
    local itemID = data and (data.id or (data.hyperlink and tonumber(data.hyperlink:match("item:(%d+)"))))
    if not itemID and tooltip.GetItem then
        local _, link = tooltip:GetItem()
        itemID = link and tonumber(link:match("item:(%d+)"))
    end
    return itemID
end

local hasProcessor = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType

if hasProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        -- (Not the shopping/comparison tooltips: they'd repeat the same line.)
        if not tooltip or tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2 then return end
        AddBankLines(tooltip, TooltipItemID(tooltip, data))
    end)
else
    -- Older clients: the tooltip only knows the item as a link.
    local function OnTooltipSetItem(tooltip)
        local itemID = TooltipItemID(tooltip)
        if itemID then
            AddBankLines(tooltip, itemID)
            tooltip:Show()
        end
    end
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem) end
end

-- What this character carries and has in its bank, saved account-wide at
-- logout/reload so other characters' tooltips can list it. Characters
-- appear once they have logged out with this version of the addon.
function Embolsao:GetCharacterKey()
    -- Two-word names can come back cut to their first word (the second one
    -- passed off as the realm): take the longest name any call gives, and the
    -- realm from GetRealmName, spelled without spaces.
    local name = UnitName("player") or ""
    local fullName = GetUnitName and GetUnitName("player", false)
    if fullName and #fullName > #name then name = fullName end
    local unitFullName = UnitFullName("player")
    if unitFullName and #unitFullName > #name then name = unitFullName end
    return name .. "-" .. ((GetRealmName() or ""):gsub("%s", ""))
end

local function SaveCharacterItems()
    if not EmbolsaoDB or not Embolsao.db or Embolsao.db.offlineBank == false then return end
    local bags = {}
    for _, bagID in ipairs(Embolsao.GetBagsDomainBagIDs()) do
        for slot = 1, C_Container.GetContainerNumSlots(bagID) or 0 do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID then
                bags[info.itemID] = (bags[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    local bank
    local counts = CountsFor("PERSONAL")
    if counts then
        bank = {}
        for id, n in pairs(counts) do bank[id] = n end
    end
    -- The full copies the alt viewer shows (bags as they lie, the personal bank
    -- as last seen at a banker, and what is worn). Bags that read as completely
    -- empty are not trusted over a good earlier copy: right after login they
    -- can simply not have loaded yet.
    EmbolsaoDB.characterItems = EmbolsaoDB.characterItems or {}
    local key = Embolsao:GetCharacterKey()
    local myName = key:match("^(.-)%-") or key
    local previous = EmbolsaoDB.characterItems[key]
    local bagsSnapshot, anyItem = Embolsao:CaptureBagsSnapshot()
    if not anyItem and previous and previous.bagsSnapshot then
        bagsSnapshot = previous.bagsSnapshot
    end
    local equipped = Embolsao:CaptureEquipment()
    if not next(equipped) and previous and previous.equipped then
        equipped = previous.equipped
    end
    -- (An older spelling of this same character's key is dropped.)
    for otherKey in pairs(EmbolsaoDB.characterItems) do
        if otherKey ~= key and Embolsao:GetCharacterIdentity(otherKey, EmbolsaoDB.characterItems[otherKey])
            == Embolsao:GetCharacterIdentity(key, { name = myName }) then
            EmbolsaoDB.characterItems[otherKey] = nil
        end
    end
    EmbolsaoDB.characterItems[key] = {
        name = myName,
        class = select(2, UnitClass("player")),
        time = time(),
        bags = bags,
        bank = bank,
        bagsSnapshot = bagsSnapshot,
        bankSnapshot = EmbolsaoCharDB and EmbolsaoCharDB.bankSnapshot,
        equipped = equipped,
    }
end

-- Saved shortly after every bag change and on entering the world, not just at
-- logout, so the counts are always current whenever EmbolsaoDB is written out.
local pending
local function SaveSoon()
    if pending then return end
    pending = true
    C_Timer.After(3, function()
        pending = false
        pcall(SaveCharacterItems)
    end)
end

local saver = CreateFrame("Frame")
saver:RegisterEvent("PLAYER_LOGOUT")
saver:RegisterEvent("PLAYER_ENTERING_WORLD")
saver:RegisterEvent("BAG_UPDATE_DELAYED")
saver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
saver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        pcall(SaveCharacterItems)
    else
        SaveSoon()
    end
end)
