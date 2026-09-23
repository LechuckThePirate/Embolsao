local ADDON_NAME, Embolsao = ...

-- WOW_PROJECT_ID is Blizzard's own global for exactly this: set once at
-- client startup, never changes, so this only needs to run once here rather
-- than being checked ad hoc all over the codebase.
Embolsao.IsClassic = WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE

-- The "flat" portrait template is retail-only -- Classic (Era and every
-- progression flavor alike) only ships the older textured PortraitFrameTemplate.
-- Both inherit the same PortraitFrameMixin underneath (SetPortraitToAsset,
-- SetTitle, etc. all work identically either way), so this is the only
-- thing that actually needs to branch to create the right kind of window.
Embolsao.PORTRAIT_FRAME_TEMPLATE = Embolsao.IsClassic and "PortraitFrameTemplate" or "PortraitFrameFlatTemplate"

-- The bare GetItemInfo global isn't guaranteed to exist anymore on every
-- client build -- confirmed missing entirely on the "Forever" Classic beta
-- (interface 16001), crashing bag sorting/searching outright with "attempt
-- to call a nil value" the moment it tried to use it. C_Item.GetItemInfo is
-- the same call (same return values), just namespaced -- the same
-- migration retail already went through a while back.
Embolsao.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
-- Same story as GetItemInfo above -- category filtering (Filters.lua) and
-- sort-by-type both depend on this one too.
Embolsao.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
-- Same migration again, confirmed by Gearset.lua's own equip crashing on
-- Forever with "attempt to call a nil value": the bare EquipItemByName
-- global is missing there too. C_Item.EquipItemByName is the same call.
Embolsao.EquipItemByName = (C_Item and C_Item.EquipItemByName) or EquipItemByName

-- Copper amount -> "12g 3s 4c" with coin icons, for the Junk sell tooltip.
-- Same migration as the two above: the bare GetCoinTextureString global is
-- gone on the newest clients (retail, Classic "Forever" -- calling it there
-- was a nil-call error on mouseover) and only exists as
-- C_CurrencyInfo.GetCoinTextureString. Plain text as a last resort so a
-- client with neither still shows an amount instead of erroring.
Embolsao.GetCoinTextureString = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
    or _G.GetCoinTextureString
    or function(amount)
        return string.format("%dg %ds %dc", math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
    end

-- Quality tier -> color (r, g, b), for the always-on quality border (UI.lua).
-- C_Item.GetItemQualityColor is the modern namespaced call; the bare
-- ITEM_QUALITY_COLORS table is the long-standing fallback, same migration
-- story as GetItemInfo above -- keyed by quality, each entry has r/g/b.
function Embolsao:GetItemQualityColor(quality)
    if quality == nil then return nil end
    if C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
        if ok and r then return r, g, b end
    end
    local color = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return nil
end

-- Item level and stat table for advanced tab filters (Filters.lua's
-- quality/itemLevel/stat conditions). GetDetailedItemLevelInfo accounts for
-- scaling (azerite, corruption, etc.) a plain GetItemInfo ilvl doesn't, but
-- isn't guaranteed to exist on every flavor -- GetItemInfo's own itemLevel
-- (4th return) is a safe, universal fallback, just unscaled.
function Embolsao:GetEffectiveItemLevel(itemID, hyperlink)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, effective = pcall(C_Item.GetDetailedItemLevelInfo, hyperlink or itemID)
        if ok and type(effective) == "number" and effective > 0 then return effective end
    end
    local ok, _, _, _, itemLevel = pcall(Embolsao.GetItemInfo, hyperlink or itemID)
    return (ok and itemLevel) or nil
end

-- Needs the hyperlink, not just the itemID, so random enchants/bonuses on the
-- actual item count -- a bare itemID would only ever see the item's base
-- stats. An item with genuinely no stats (reagents, quest items) legitimately
-- returns an empty table, same as one the API call itself failed on.
function Embolsao:GetItemStatsTable(hyperlink)
    if not (hyperlink and C_Item and C_Item.GetItemStats) then return {} end
    local ok, stats = pcall(C_Item.GetItemStats, hyperlink)
    return (ok and type(stats) == "table") and stats or {}
end

-- Classic never got the Mixin-based StackSplitFrame:OpenStackSplitFrame()
-- retail has -- its StackSplitFrame.xml doesn't carry the mixin attribute
-- at all, and split-stack is still driven by the original pre-Mixin global
-- function OpenStackSplitFrame(...) instead (confirmed against Blizzard's
-- own Classic/StackSplitFrame.lua). Calling the method form there doesn't
-- error immediately -- StackSplitFrame.OpenStackSplitFrame is just silently
-- nil -- so it fails with "attempt to call a nil value" the moment it's
-- used. This wraps both calling conventions behind one function.
function Embolsao:OpenStackSplitFrame(maxStack, parent, anchor, anchorTo, stackCount)
    if Embolsao.IsClassic then
        OpenStackSplitFrame(maxStack, parent, anchor, anchorTo, stackCount)
    else
        StackSplitFrame:OpenStackSplitFrame(maxStack, parent, anchor, anchorTo, stackCount)
    end
end

-- Personal bank storage is a completely different shape depending on flavor.
-- Classic/TBC never got the modern redesign: it's still the original single
-- BANK_CONTAINER plus however many bank bag slots the player has purchased
-- (bagIDs NUM_BAG_SLOTS+1..+NUM_BANKBAGSLOTS -- confirmed against Blizzard's
-- own Classic/BankFrame.lua). Retail replaced all of that with six
-- always-present "tabs", each its own bagID (Enum.BagIndex.CharacterBankTab_1
-- .._6) -- there's no single BANK_CONTAINER equivalent there anymore.
-- Both still render through ordinary ContainerFrameN frames with their own
-- :GetID() either way, which is the only thing UI.lua actually needs.
--
-- Retail also has the account-wide Warband Bank (Enum.BagIndex.AccountBankTab_1
-- .._5) -- shared across every character on the account, not "yours" the same
-- way personal storage is, so it's kept as a separate list rather than folded
-- into the same pool. Classic/TBC has no account-wide bank at all.
--
-- NUM_BANKBAGSLOTS (Classic/TBC) lives inside Blizzard_UIPanels_Game, the
-- same load-on-demand module ContainerFrame1/BankFrame come from (see
-- UI.lua's InstallBagFrameHooks) -- it doesn't exist yet this early at this
-- file's own load time, so building these lists has to wait until that
-- module is confirmed loaded. Safe empty defaults here in the meantime so
-- nothing ever iterates a nil table before InitBankBagIDs below runs.
Embolsao.PersonalBankBagIDs = {}
Embolsao.WarbandBankBagIDs = {}

-- The "modern" bank: tabs (personal, plus the account-wide Warband bank),
-- driven by the C_Bank API. Retail has it, and so does the Classic "Forever"
-- client -- which is why Embolsao.IsClassic (used above for the old-style bank)
-- can NOT tell the two Classic banks apart: Forever reports as Classic yet has
-- the modern one (Blizzard's Camelot/BankFrame.lua). What decides it is
-- whether the API is there, not the flavor.
function Embolsao:UsesModernBank()
    return C_Bank ~= nil and C_Bank.FetchPurchasedBankTabIDs ~= nil
        and Enum ~= nil and Enum.BankType ~= nil
end

-- The bag IDs of the tabs actually purchased, straight from the client: they
-- differ per flavor (Forever numbers them from ITEM_INVENTORY_BANK_BAG_OFFSET,
-- retail uses Enum.BagIndex.CharacterBankTab_N) and per character (tabs are
-- bought one at a time), so nothing is hardcoded. Only meaningful while at a
-- banker, so it's re-read each time the bank opens.
function Embolsao:RefreshModernBankBagIDs()
    if not self:UsesModernBank() then return end

    local function FetchIDs(bankType)
        local copy = {}
        local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, bankType)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do
                table.insert(copy, id)
            end
        end
        return copy
    end

    self.PersonalBankBagIDs = FetchIDs(Enum.BankType.Character)
    self.WarbandBankBagIDs = FetchIDs(Enum.BankType.Account)
end

local bankBagIDsInitialized = false
function Embolsao:InitBankBagIDs()
    if bankBagIDsInitialized then return end
    bankBagIDsInitialized = true

    if Embolsao:UsesModernBank() then
        Embolsao:RefreshModernBankBagIDs()
    elseif Embolsao.IsClassic then
        Embolsao.PersonalBankBagIDs = { BANK_CONTAINER }
        for i = 1, (NUM_BANKBAGSLOTS or 0) do
            table.insert(Embolsao.PersonalBankBagIDs, NUM_BAG_SLOTS + i)
        end
    else
        Embolsao.PersonalBankBagIDs = {
            Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_2,
            Enum.BagIndex.CharacterBankTab_3, Enum.BagIndex.CharacterBankTab_4,
            Enum.BagIndex.CharacterBankTab_5, Enum.BagIndex.CharacterBankTab_6,
        }
        Embolsao.WarbandBankBagIDs = {
            Enum.BagIndex.AccountBankTab_1, Enum.BagIndex.AccountBankTab_2,
            Enum.BagIndex.AccountBankTab_3, Enum.BagIndex.AccountBankTab_4,
            Enum.BagIndex.AccountBankTab_5,
        }
    end
end

-- Whether the account can even see the Warband Bank at all (trial accounts,
-- or simply a game version that never got it) -- mirrors the exact check
-- Blizzard's own BankFrame.lua uses to decide whether to show that tab.
function Embolsao:CanUseWarbandBank()
    if not (C_Bank and C_Bank.CanViewBank and Enum and Enum.BankType) then return false end
    -- On the modern bank tabs are bought one at a time, so an account that
    -- has bought none yet still has a Warband Bank to buy into (its first
    -- tab is bought from the bank window's footer) -- an empty tab list can't
    -- mean "no Warband Bank" there.
    if not self:UsesModernBank() and #Embolsao.WarbandBankBagIDs == 0 then return false end
    return C_Bank.CanViewBank(Enum.BankType.Account)
end

-- What the bank window's footer can offer to buy right now, or nil when
-- there's nothing (not at a banker, or everything already bought):
--   { kind = "tab",  bankType = Enum.BankType.*, cost = copper, canAfford = bool }
--       the modern bank's next tab, for whichever bank the window is showing
--       (personal, or Warband)
--   { kind = "slot", cost = copper, canAfford = bool }
--       Classic/TBC's next bank bag slot
function Embolsao:GetNextBankPurchase()
    if not self.AtBank then return nil end

    if self:UsesModernBank() then
        local bankType = (self.BankViewMode == "WARBAND") and Enum.BankType.Account or Enum.BankType.Character
        local ok, tabData = pcall(C_Bank.FetchNextPurchasableBankTabData, bankType)
        if not ok or not tabData then return nil end
        return { kind = "tab", bankType = bankType, cost = tabData.tabCost or 0, canAfford = tabData.canAfford ~= false }
    end

    if GetNumBankSlots and GetBankSlotCost then
        local numSlots, full = GetNumBankSlots()
        if full then return nil end
        local cost = GetBankSlotCost(numSlots) or 0
        return { kind = "slot", cost = cost, canAfford = GetMoney() >= cost }
    end

    return nil
end

-- Opens Blizzard's own confirmation dialog for that purchase; the purchase
-- itself happens in Blizzard's dialog code when the player accepts, never in
-- ours. (Classic's dialog reads the cost from BankFrame.nextSlotCost, which
-- Blizzard's own BankFrame keeps current -- it stays alive, just off-screen,
-- while our bank window is up.)
function Embolsao:RequestBankPurchase()
    local purchase = self:GetNextBankPurchase()
    if not purchase or not purchase.canAfford then return end

    if purchase.kind == "tab" then
        StaticPopup_Show("CONFIRM_BUY_BANK_TAB", nil, nil, { bankType = purchase.bankType })
    else
        StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
    end
end
