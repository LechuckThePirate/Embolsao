-- The bank's bag slots: the row of slots you equip bags into, which is what
-- makes the bank bigger. Blizzard's own row hangs off its BankFrame, which this
-- addon keeps off-screen while its bank window is up, so without a row of our
-- own a bought slot could never be given a bag. Lives in the bank window's
-- footer, next to the "Buy ..." button. Split out of UI.lua (see the file-size
-- and Lua 5.1 limits notes there); loads AFTER it and reaches the bank window
-- through the UI table.
--
-- Two banks have these slots, and they work differently:
--   * Classic Era / TBC: the old bank. Bags go into inventory slots
--     (PutItemInBag / PickupBagFromSlot), one per slot bought with money.
--   * Classic "Forever": the tab-style bank, but a bought "tab" is still a bag
--     slot (Blizzard's Camelot/BankFrame.lua draws a row of bag buttons and
--     picks bags up / puts them down with C_Container.PickupContainerItem on
--     the Characterbanktab / Accountbanktab pseudo-container, slot 1 being the
--     bank itself and slots 2.. the bags). Each of the two banks has its own.
-- Retail's tabs are not bags: nothing to do there.
local _, Embolsao = ...
local UI = Embolsao.UI

local SLOT_SIZE = 22
local SLOT_GAP = 3
local FOOTER_MARGIN = 8
local EMPTY_SLOT_TEXTURE = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local row -- the strip of buttons, built on the first refresh that needs it

--------------------------------------------------------------------------
-- The two banks behind one shape. Every function takes the button's index
-- (1 = the first bag slot, left to right):
--   count()          how many slots are bought
--   texture(index)   icon of the bag in it, and whether it is locked (on the cursor)
--   click(index)     what a click does: a bag on the cursor goes in (swapping
--                    with the one there), otherwise the slot's bag is picked up
--   pickup(index)    pick the slot's bag up (drag)
--   tooltip(index)   fills GameTooltip
--------------------------------------------------------------------------

local classic = {}

function classic.supported()
    return not Embolsao:UsesModernBank()
        and GetNumBankSlots ~= nil and PutItemInBag ~= nil and PickupBagFromSlot ~= nil
end

-- The inventory slot a bank bag slot is equipped into (the numbers a bag on the
-- cursor is put into with PutItemInBag).
local function InventorySlot(index)
    if BankButtonIDToInvSlotID then return BankButtonIDToInvSlotID(index) end
    local toInventoryID = ContainerIDToInventoryID or (C_Container and C_Container.ContainerIDToInventoryID)
    return toInventoryID(NUM_BAG_SLOTS + index)
end

function classic.count()
    return math.min(GetNumBankSlots() or 0, NUM_BANKBAGSLOTS or 0)
end

function classic.texture(index)
    local slot = InventorySlot(index)
    local texture = GetInventoryItemTexture("player", slot)
    local locked = texture ~= nil and IsInventoryItemLocked ~= nil and IsInventoryItemLocked(slot)
    return texture, locked and true or false
end

function classic.click(index)
    local slot = InventorySlot(index)
    if not PutItemInBag(slot) then
        PickupBagFromSlot(slot)
    end
end

function classic.pickup(index)
    PickupBagFromSlot(InventorySlot(index))
end

function classic.tooltip(index)
    local slot = InventorySlot(index)
    if GetInventoryItemID("player", slot) then
        GameTooltip:SetInventoryItem("player", slot)
    else
        GameTooltip:SetText(_G.BANK_BAG or "Bank Bag")
    end
end

local forever = {}

function forever.supported()
    return Embolsao.IsForever and Embolsao:UsesModernBank()
        and C_Bank.FetchPurchasedBankTabData ~= nil
        and C_Container ~= nil and C_Container.PickupContainerItem ~= nil
        and Enum.BagIndex ~= nil
        and Enum.BagIndex.Characterbanktab ~= nil and Enum.BagIndex.Accountbanktab ~= nil
end

-- Whichever of the two banks the window is showing: the bank type, and the
-- pseudo-container whose slots are that bank's bag slots.
local function ForeverBank()
    if Embolsao.BankViewMode == "WARBAND" then
        return Enum.BankType.Account, Enum.BagIndex.Accountbanktab
    end
    return Enum.BankType.Character, Enum.BagIndex.Characterbanktab
end

function forever.count()
    local bankType = ForeverBank()
    local ok, bought = pcall(C_Bank.FetchPurchasedBankTabData, bankType)
    if not ok or type(bought) ~= "table" then return 0 end
    -- The first one is the bank itself, not a bag.
    return math.max(#bought - 1, 0)
end

local function ForeverSlot(index)
    local _, bagID = ForeverBank()
    return bagID, index + 1
end

function forever.texture(index)
    local bagID, slotID = ForeverSlot(index)
    local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bagID, slotID)
    if not info then return nil, false end
    return info.iconFileID, info.isLocked and true or false
end

function forever.click(index)
    C_Container.PickupContainerItem(ForeverSlot(index))
end

forever.pickup = forever.click

function forever.tooltip(index)
    local bagID, slotID = ForeverSlot(index)
    if not GameTooltip:SetBagItem(bagID, slotID) then
        GameTooltip:SetText(_G.BANK_BAG or "Bank Bag")
    end
end

-- Which one applies on this client, or nil when it has no bank bag slots.
local function Bank()
    if Embolsao.IsForever then
        return forever.supported() and forever or nil
    end
    return classic.supported() and classic or nil
end

--------------------------------------------------------------------------
-- The row
--------------------------------------------------------------------------

local function UpdateButton(button, bank)
    local texture, locked = bank.texture(button.index)
    button.icon:SetTexture(texture or EMPTY_SLOT_TEXTURE)
    button.icon:SetDesaturated(locked)
    button.icon:SetAlpha(texture and 1 or 0.6)
end

local function CreateButton(parent, index)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(SLOT_SIZE, SLOT_SIZE)
    button.index = index

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.5)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- Blizzard's slot buttons take both mouse buttons to the same place.
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(self)
        local bank = Bank()
        if bank then bank.click(self.index) end
    end)
    button:SetScript("OnReceiveDrag", function(self)
        local bank = Bank()
        if bank then bank.click(self.index) end
    end)
    button:SetScript("OnDragStart", function(self)
        local bank = Bank()
        if bank then bank.pickup(self.index) end
    end)

    button:SetScript("OnEnter", function(self)
        local bank = Bank()
        if not bank then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        bank.tooltip(self.index)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    return button
end

-- Builds the row on first use, then shows one button per bought slot (they
-- appear as the slots are bought), only while standing at a banker: that is
-- the only place bags can be moved in and out of the bank.
function UI:UpdateBankBagSlots()
    local bankWindow = UI.bankWindow
    local frame = bankWindow and bankWindow.GetFrame()
    local footer = frame and frame.footer
    local bank = Bank()
    if not footer or not bank then return end

    if not row then
        row = { frame = CreateFrame("Frame", nil, footer), buttons = {} }
        row.frame:SetAllPoints(footer)
        -- Equipping or picking up a bag changes a slot without any scan
        -- needing to run, and the lock follows the bag onto the cursor.
        -- Not every client has every event.
        for _, event in ipairs({
            "PLAYERBANKBAGSLOTS_CHANGED", "BAG_CONTAINER_UPDATE", "BANK_TABS_CHANGED",
            "PLAYERBANKSLOTS_CHANGED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "ITEM_LOCK_CHANGED",
        }) do
            pcall(row.frame.RegisterEvent, row.frame, event)
        end
        row.frame:SetScript("OnEvent", function()
            if row.frame:IsVisible() then UI:UpdateBankBagSlots() end
        end)
    end

    local count = 0
    if Embolsao.AtBank and not Embolsao.BankOffline then
        count = bank.count()
    end

    for index = 1, count do
        local button = row.buttons[index]
        if not button then
            button = CreateButton(row.frame, index)
            row.buttons[index] = button
        end
        button:ClearAllPoints()
        button:SetPoint("RIGHT", footer, "RIGHT",
            -FOOTER_MARGIN - (count - index) * (SLOT_SIZE + SLOT_GAP), 0)
        button:Show()
        UpdateButton(button, bank)
    end
    for index = count + 1, #row.buttons do
        row.buttons[index]:Hide()
    end
end
