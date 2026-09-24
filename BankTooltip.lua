-- Adds "In your bank: N" (and the Warband bank's) to item tooltips anywhere --
-- crafting ingredients, chat links, vendors, the character sheet -- from the
-- offline bank's saved copies (Core.lua's GetBankSnapshot), so it works away
-- from a banker. No offline copy, no line: turning "Offline Bank" off in
-- Preferences also turns this off.
local ADDON_NAME, Embolsao = ...
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
    local chars = EmbolsaoDB and EmbolsaoDB.characterItems
    if not chars then return end
    local me = Embolsao:GetCharacterKey()
    local names = {}
    for key in pairs(chars) do
        if key ~= me then names[#names + 1] = key end
    end
    table.sort(names)
    for _, key in ipairs(names) do
        local info = chars[key]
        local inBags = info.bags and info.bags[itemID]
        local inBank = info.bank and info.bank[itemID]
        if inBags or inBank then
            local parts = {}
            if inBags then parts[#parts + 1] = L.TOOLTIP_CHAR_BAGS:format(inBags) end
            if inBank then parts[#parts + 1] = L.TOOLTIP_CHAR_BANK:format(inBank) end
            local color = info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class]
            local name = color and ("|c" .. (color.colorStr or "ffffffff") .. (info.name or key) .. "|r") or (info.name or key)
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
    local name, realm = UnitFullName("player")
    return (name or UnitName("player")) .. "-" .. (realm or GetRealmName() or "")
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
    EmbolsaoDB.characterItems = EmbolsaoDB.characterItems or {}
    EmbolsaoDB.characterItems[Embolsao:GetCharacterKey()] = {
        name = UnitName("player"),
        class = select(2, UnitClass("player")),
        time = time(),
        bags = bags,
        bank = bank,
    }
end

-- Saved shortly after every bag change and on entering the world, not just at
-- logout: on the Forever beta client the fallback storage (ForeverSVFallback.lua)
-- copies EmbolsaoDB every few seconds and at logout BEFORE this file's logout
-- handler runs, so a logout-only save never reached the copy the next
-- character loads -- and that character then overwrote this one's entry.
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
saver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        pcall(SaveCharacterItems)
    else
        SaveSoon()
    end
end)
