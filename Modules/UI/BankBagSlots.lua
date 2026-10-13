-- The old-style bank's bag slots (Classic Era / TBC): the row of slots you equip
-- bags into, which is what makes the bank bigger. Blizzard's own row hangs off
-- its BankFrame, which this addon keeps off-screen while its bank window is up,
-- so without a row of our own a bought slot could never be given a bag. Lives in
-- the bank window's footer, next to the "Buy Bank Bag Slot" button. Split out of
-- UI.lua (see the file-size and Lua 5.1 limits notes there); loads AFTER it and
-- reaches the bank window through the UI table.
--
-- The modern bank (Retail, Classic "Forever") has tabs instead of bag slots, so
-- there is nothing to do there.
local _, Embolsao = ...
local UI = Embolsao.UI

local SLOT_SIZE = 22
local SLOT_GAP = 3
local FOOTER_MARGIN = 8
local EMPTY_SLOT_TEXTURE = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local row -- the strip of buttons, built on the first refresh that needs it

local function IsSupported()
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

-- Same two steps as Blizzard's own bank bag button: a bag on the cursor goes
-- into the slot (swapping with whatever is there), otherwise the slot's bag is
-- picked up.
local function Interact(button, pickup)
    local slot = InventorySlot(button.index)
    if pickup then
        PickupBagFromSlot(slot)
    elseif not PutItemInBag(slot) then
        PickupBagFromSlot(slot)
    end
end

local function UpdateButton(button)
    local slot = InventorySlot(button.index)
    local texture = GetInventoryItemTexture("player", slot)
    button.icon:SetTexture(texture or EMPTY_SLOT_TEXTURE)
    local locked = texture ~= nil and IsInventoryItemLocked ~= nil and IsInventoryItemLocked(slot)
    button.icon:SetDesaturated(locked and true or false)
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

    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(self) Interact(self, false) end)
    button:SetScript("OnReceiveDrag", function(self) Interact(self, false) end)
    button:SetScript("OnDragStart", function(self) Interact(self, true) end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local slot = InventorySlot(self.index)
        if GetInventoryItemID("player", slot) then
            GameTooltip:SetInventoryItem("player", slot)
        else
            GameTooltip:SetText(_G.BANK_BAG or "Bank Bag")
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    return button
end

local function UpdateButtons()
    if not row or not row.frame:IsShown() then return end
    for index = 1, row.shown do
        UpdateButton(row.buttons[index])
    end
end

-- Builds the row on first use, then shows one button per bought slot (they
-- appear as the slots are bought), only while standing at a banker: that is
-- the only place bags can be moved in and out of the bank.
function UI:UpdateBankBagSlots()
    local bankWindow = UI.bankWindow
    local frame = bankWindow and bankWindow.GetFrame()
    local footer = frame and frame.footer
    if not footer or not IsSupported() then return end

    if not row then
        row = { frame = CreateFrame("Frame", nil, footer), buttons = {}, shown = 0 }
        row.frame:SetAllPoints(footer)
        -- Equipping or picking up a bag changes the slot without any scan
        -- needing to run; the lock follows the bag onto the cursor.
        for _, event in ipairs({ "PLAYERBANKBAGSLOTS_CHANGED", "ITEM_LOCK_CHANGED" }) do
            pcall(row.frame.RegisterEvent, row.frame, event)
        end
        row.frame:SetScript("OnEvent", UpdateButtons)
    end

    local count = 0
    if Embolsao.AtBank and not Embolsao.BankOffline then
        count = math.min(GetNumBankSlots() or 0, NUM_BANKBAGSLOTS or 0)
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
    end
    for index = count + 1, #row.buttons do
        row.buttons[index]:Hide()
    end

    row.shown = count
    UpdateButtons()
end
