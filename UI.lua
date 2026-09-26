local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

Embolsao.UI = {}
local UI = Embolsao.UI
local Layout = Embolsao.Layout
local Bindings = Embolsao.Bindings

local TAB_ICON_SIZE = 30
local TAB_PADDING = 16
local TAB_PANEL_PADDING = 12
local TAB_GLOW_MARGIN = 6 -- extra room either side of each tab icon, so the Gearset "worn" border can sit outside it instead of clipping against the scroll column's own width
local TAB_TO_ITEMS_GAP = 18
local ITEM_SIZE = Embolsao.UIConst.ITEM_SIZE
local ITEM_PADDING = Embolsao.UIConst.ITEM_PADDING
local ITEMS_PER_ROW = 8 -- default/minimum; grows as the window is resized wider
local HEADER_ROW_HEIGHT = Embolsao.UIConst.HEADER_ROW_HEIGHT -- Sort By Type class/subclass separators
local HEADER_INDENT_STEP = 14 -- per nesting level, so subclass headers read as nested under their class
local GROUP_GAP_HEIGHT = Embolsao.UIConst.GROUP_GAP_HEIGHT -- vertical space closing off the pinned "Recent" group
local CONTENT_TOP_OFFSET = 70
local TOOLBAR_Y = -34 -- search box / menu button row, a bit above the item grid
local GEARSET_BAR_HEIGHT = 26 -- extra room reserved above the item grid for the Equip/Unequip button, Gearset tabs only
local FOOTER_HEIGHT = 24 -- money + XP strip, pinned below the scroll areas
local FOOTER_GAP = 6 -- breathing room between the item grid and the footer
UI.MEMORY_REFRESH_SECONDS = 5 -- how often the footer re-reads the addon's memory use
local BOTTOM_MARGIN = 4 -- from the tab panel/footer down to the window's own edge
-- UIPanelScrollFrameTemplate's scrollbar sits outside the scroll frame's own
-- right edge (anchored TOPRIGHT x=6, width 16) -- reserve that much space so
-- it doesn't overlap the last column of icons/tabs.
local SCROLLBAR_CLEARANCE = Embolsao.UIConst.SCROLLBAR_CLEARANCE
local PORTRAIT_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icons\\embolsao-icon.png"

-- All the native frames we take over display duty from, across BOTH windows
-- (bags and bank) -- GetOwningWindow (further down) sorts out which window,
-- if either, actually owns a given one. Combined bags is one frame; legacy
-- (non-combined) mode can have the backpack plus up to 5 more bag frames
-- open side by side, so we cover the full set either way. BankFrame is
-- the bank's storage window -- see IsBankStorageFrame below.
local NATIVE_BAG_FRAME_NAMES = {
    "ContainerFrameCombinedBags",
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
    "BankFrame",
}

-- Small icon that follows the cursor while dragging a tab to reorder it --
-- without this, dragging looked like it did nothing until you let go.
-- Smaller than the real tab icon on purpose -- at full size the ghost sat
-- right on top of the drop-line indicator and hid it. Shared across both
-- windows -- only one tab drag can ever be in progress at a time.
local DRAG_GHOST_SIZE = TAB_ICON_SIZE * 0.5

local dragGhost

local function EnsureDragGhost()
    if dragGhost then return dragGhost end

    dragGhost = CreateFrame("Frame", nil, UIParent)
    dragGhost:SetSize(DRAG_GHOST_SIZE, DRAG_GHOST_SIZE)
    dragGhost:SetFrameStrata("TOOLTIP")
    dragGhost:EnableMouse(false)
    dragGhost:Hide()

    dragGhost.icon = dragGhost:CreateTexture(nil, "OVERLAY")
    dragGhost.icon:SetAllPoints()
    dragGhost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dragGhost.icon:SetAlpha(0.9)

    return dragGhost
end

local function UpdateDragGhostPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    dragGhost:ClearAllPoints()
    dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale + TAB_ICON_SIZE)
end

-- Reads the identity of whatever item is on the cursor (without consuming
-- it -- handed right back to its own slot) and, if there is one, asks for
-- confirmation to hide it on the given tab. Used when an item from the bag
-- grid gets dropped straight onto a tab button. Shared -- doesn't touch any
-- per-window state, just the cursor and Filters/TabEditor.
local function TryHideCursorItemOnTab(tabData, domain)
    local cursorItem = C_Cursor.GetCursorItem()
    if not cursorItem then return end
    local bagID, slot = cursorItem:GetBagAndSlot()
    if not bagID then return end

    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if info and info.itemID then
        Embolsao.TabEditor:ConfirmHideItemOnTab(info.itemID, tabData, domain)
    end

    C_Container.PickupContainerItem(bagID, slot)
end

-- Right-click on empty space in the tab sidebar (not on a tab button itself
-- -- those already have their own right-click menu) lists every currently
-- hidden tab, one click each to bring it back, instead of having to go into
-- Preferences just to re-show something. Generic over `owner` -- works
-- identically for either window's tab sidebar.
local function ShowHiddenTabsMenu(owner, domain)
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        local hasHidden = false
        local filters = Embolsao:GetFilters(domain)
        for _, tabData in ipairs(filters:GetAllTabs()) do
            if tabData.hidden then
                hasHidden = true
                rootDescription:CreateButton(tabData.name, function()
                    filters:SetTabHidden(tabData.id, false)
                    UI:BuildTabs()
                    UI:Refresh()
                end)
            end
        end
        if not hasHidden then
            rootDescription:CreateTitle(L.NO_HIDDEN_TABS)
        end
    end)
end

--------------------------------------------------------------------------
-- Pawn ("bag upgrade advisor") integration. Optional -- everything here is
-- a no-op if Pawn isn't installed. Our item buttons are plain ItemButtons,
-- not Blizzard's ContainerFrameItemButtonTemplate, so Pawn's own bag hook
-- (PawnBags.lua, hooksecurefunc on ContainerFrameN's UpdateItems) never
-- sees them -- this reimplements the green-arrow overlay via Pawn's own
-- documented third-party-bag integration contract instead (see the header
-- comment in Pawn's PawnBags.lua, or its GitHub source):
--   1. Call PawnShouldItemLinkHaveUpgradeArrow(link, true) per item.
--   2. nil means "ask again shortly" (Pawn throttles itself); true/false
--      is the real answer.
--   3. Call PawnRegisterThirdPartyBag(name, {RefreshAll=...}) once, so Pawn
--      knows we're handling this ourselves (and disables its own native-bag
--      hook, which would never have found our buttons anyway).
-- Shared across both windows: RefreshAllPawnIcons (below, after both windows
-- exist) walks every registered window's buttons.
--------------------------------------------------------------------------

-- Same atlas/anchor Blizzard's own ContainerFrameItemButtonTemplate uses for
-- this (confirmed against Classic and retail ContainerFrame.xml -- identical
-- in both) -- our buttons don't inherit that template, so it has to be
-- created by hand.
local function CreateUpgradeIcon(btn)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetAtlas("bags-greenarrow", true)
    icon:SetPoint("TOPLEFT", 0, 0)
    icon:Hide()
    return icon
end

-- Same reasoning as CreateUpgradeIcon above: the yellow "!" (quest not yet
-- picked up) / plain border (item tied to an in-progress quest) that native
-- bags show is a ContainerFrameItemButtonTemplate region (IconQuestTexture)
-- our bare ItemButtons don't have, so it's built by hand. TEXTURE_ITEM_QUEST_BANG
-- and TEXTURE_ITEM_QUEST_BORDER are the same globals FrameXML's own
-- ContainerFrame/quest log/vendor item buttons have used for this since
-- Classic -- not atlas-based, and present on every flavor this addon
-- supports, unlike some of the newer atlas names retail has moved to.
local function CreateQuestTexture(btn)
    local texture = btn:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:Hide()
    return texture
end

-- Same reasoning again: native bags show a small gold coin on a Junk item's
-- icon (ContainerFrameItemButtonTemplate's JunkIcon region), which our bare
-- ItemButtons don't have. Couldn't pin down Blizzard's own texture/atlas for
-- that exact region from documentation -- UI-GoldIcon is a plain, stable,
-- always-available "coin" asset (used in currency frames since Classic) used
-- here instead; swap for the exact native one if it's ever tracked down.
local function CreateJunkIcon(btn)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    icon:SetSize(12, 12)
    icon:SetPoint("BOTTOMLEFT", 1, 1)
    icon:Hide()
    return icon
end

-- Small red "no" mark in the corner of a Gearset tab's Unavailable rows (an
-- item in the set that isn't in the bags or on the character), same spot
-- and size class as the Junk coin -- on top of the desaturated icon. The
-- ready-check "not ready" X is the stable, always-present red glyph (the
-- green check below is its counterpart); a true circle-slash would need an
-- asset that isn't guaranteed on every client flavor.
local function CreateGearsetUnavailableIcon(btn)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    icon:SetSize(14, 14)
    icon:SetPoint("BOTTOMLEFT", 1, 1)
    icon:Hide()
    return icon
end

-- Green checkmark on a Gearset tab's Equipped/Previously Equipped rows
-- (Layout.lua) -- "the ones you're currently wearing keep showing in the
-- list, just marked" rather than disappearing, per the plan. The ready-check
-- atlas is a common, stable "yes/done" glyph, not literal ready-check UI.
local function CreateGearsetEquippedCheck(btn)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    icon:SetSize(14, 14)
    icon:SetPoint("TOPRIGHT", 1, 1)
    icon:Hide()
    return icon
end

-- Small "X" in the opposite corner from the Pawn upgrade arrow -- only
-- shown on items currently sitting in the "Recent" group (Layout.BuildLayoutRows).
-- Forgets the item in Embolsao's own recent set (and clears Blizzard's flag
-- on each merged location so the next scan doesn't re-adopt it), then
-- rescans -- the item then shows up wherever it actually belongs instead.
local function CreateRecentDismissButton(btn)
    local dismiss = CreateFrame("Button", nil, btn)
    dismiss:SetSize(14, 14)
    dismiss:SetPoint("TOPRIGHT", 1, 1)
    -- Above the secure right-click overlay (CreateUseOverlay, btn level + 2),
    -- which otherwise covers the whole button and would swallow this click.
    dismiss:SetFrameLevel(btn:GetFrameLevel() + 3)
    dismiss:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    dismiss:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up", "ADD")
    dismiss:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.DISMISS_RECENT_HINT)
        GameTooltip:Show()
    end)
    dismiss:SetScript("OnLeave", GameTooltip_Hide)
    dismiss:SetScript("OnClick", function(self)
        local owner = self:GetParent()
        if owner.itemID then
            Embolsao:DismissRecentItem(owner.itemID, owner.locations)
            Embolsao:ScanBags()
            UI:Refresh()
        end
    end)
    dismiss:Hide()
    return dismiss
end

-- Right-click "use" needs a secure path. C_Container.UseContainerItem is
-- protected for anything that casts a spell or has an on-use effect
-- (hearthstone, scrolls, quest items...), so calling it from our own click
-- handler makes the client raise "Embolsao has been blocked from an action
-- only available to the Blizzard UI". Blizzard's own bag buttons get away
-- with it because their handler is Blizzard code. The standard fix for an
-- addon: an invisible SecureActionButtonTemplate laid over each item button
-- that runs "/use <bagID> <slot>" on right-click, while
-- everything else (tooltip, left click, drag, split) is forwarded to the
-- visible button's own handlers.
--
-- The overlay is a child of the item button and anchored to it once, so the
-- (unprotected) button can still be moved, shown and hidden during combat.
-- Only its attributes are locked in combat -- they are refreshed in
-- UpdateUseOverlay and again when combat ends (PLAYER_REGEN_ENABLED below).
--
-- Negative bagIDs (Classic's main bank container, the keyring) can't be
-- expressed in the "<bag> <slot>" form, so those keep the old direct call;
-- they only ever move items to/from the bank, which isn't protected.
local function IsModernBankOpen()
    return Embolsao.AtBank == true and Embolsao:UsesModernBank()
end

-- Right-click at a banker means "move it to the other side" (deposit from the
-- bags, withdraw from the bank). A merged super-stack is several real stacks
-- shown as one, so that has to move ALL of them, not just the first: one every
-- MOVE_INTERVAL seconds rather than all in the same instant -- each move picks
-- its own free destination slot, and asking for several before the first has
-- landed can make the game hand two of them the same one. The first goes right
-- away, so a click still feels immediate. Moving items isn't a protected
-- action (unlike using them), so this runs from plain code.
--   locations: the real (bagID, slot) stacks; bankType: which bank the modern
--   bank should be told (nil on the classic bank, which takes no such argument)
local MOVE_INTERVAL = 0.12
local movingStacks = false

local function MoveStacksAcrossBank(locations, bankType)
    if movingStacks then return end

    -- Snapshot now: the item buttons re-lay themselves out as stacks leave.
    local queue = {}
    for _, location in ipairs(locations) do
        local info = C_Container.GetContainerItemInfo(location.bagID, location.slot)
        if info then
            table.insert(queue, { bagID = location.bagID, slot = location.slot, itemID = info.itemID })
        end
    end
    if #queue == 0 then return end

    local index = 0
    -- Returns true when there's nothing left to move.
    local function MoveNext()
        index = index + 1
        local item = queue[index]
        -- Skipped if it already moved, changed, or is still in flight.
        local info = item and C_Container.GetContainerItemInfo(item.bagID, item.slot)
        if info and info.itemID == item.itemID and not info.isLocked then
            if bankType then
                C_Container.UseContainerItem(item.bagID, item.slot, nil, bankType)
            else
                C_Container.UseContainerItem(item.bagID, item.slot)
            end
        end
        return index >= #queue
    end

    if MoveNext() then return end

    movingStacks = true
    C_Timer.NewTicker(MOVE_INTERVAL, function(ticker)
        -- Stop if the banker window closed on us.
        if not Embolsao.AtBank or MoveNext() then
            ticker:Cancel()
            movingStacks = false
        end
    end)
end

-- Right-click on an item while the mailbox's Send tab is open attaches it --
-- via the secure overlay's "/use <bag> <slot>", which only ever knows the
-- first real stack behind a merged super-stack (a 5-stack pile of Peacebloom
-- attached one 20 and stopped). The remaining stacks are attached here, one
-- every MOVE_INTERVAL like MoveStacksAcrossBank above, but only as many as
-- the mail has room left for (ATTACHMENTS_MAX_SEND, 12 by default). Attaching
-- is not a protected action while the mail window is open, same as moving
-- items at the bank.
local function IsSendingMail()
    return _G.SendMailFrame ~= nil and _G.SendMailFrame:IsVisible()
end

local function CountFreeMailAttachmentSlots()
    local max = _G.ATTACHMENTS_MAX_SEND or 12
    local getItem = (C_SendMail and C_SendMail.GetSendMailItem) or _G.GetSendMailItem
    if not getItem then return max end

    local used = 0
    for slot = 1, max do
        local name = getItem(slot)
        if name and name ~= "" then
            used = used + 1
        end
    end
    return max - used
end

local attachingToMail = false

-- skipFirst: the secure overlay already attached the first stack for this
-- very click (see CreateUseOverlay), so only the rest are queued here.
local function AttachStacksToMail(locations, skipFirst)
    if attachingToMail then return end

    -- Snapshot now: the item buttons re-lay themselves out as stacks leave.
    local queue = {}
    for index, location in ipairs(locations) do
        if not (skipFirst and index == 1) then
            local info = C_Container.GetContainerItemInfo(location.bagID, location.slot)
            if info then
                table.insert(queue, { bagID = location.bagID, slot = location.slot, itemID = info.itemID })
            end
        end
    end
    if #queue == 0 then return end

    local index = 0
    -- Returns true when there's nothing left to attach (or no room left).
    local function AttachNext()
        index = index + 1
        local item = queue[index]
        if not item or CountFreeMailAttachmentSlots() <= 0 then return true end

        -- Skipped if it already moved, changed, or is still in flight.
        local info = C_Container.GetContainerItemInfo(item.bagID, item.slot)
        if info and info.itemID == item.itemID and not info.isLocked then
            C_Container.UseContainerItem(item.bagID, item.slot)
        end
        return index >= #queue
    end

    attachingToMail = true
    C_Timer.NewTicker(MOVE_INTERVAL, function(ticker)
        -- Stop if the Send tab closed on us.
        if not IsSendingMail() or AttachNext() then
            ticker:Cancel()
            attachingToMail = false
        end
    end)
end

local MODIFIED_CLICK_PREFIXES = {
    "shift-", "ctrl-", "alt-", "ctrl-shift-", "alt-shift-", "alt-ctrl-", "alt-ctrl-shift-",
}

-- True while a spell is waiting for an item to be picked as its target.
local function IsSpellTargetingItem()
    return (SpellCanTargetItem and SpellCanTargetItem())
        or (SpellCanTargetItemID and SpellCanTargetItemID())
        or false
end

local function CreateUseOverlay(btn)
    local overlay = CreateFrame("Button", nil, btn, "SecureActionButtonTemplate")
    overlay:SetAllPoints(btn)
    overlay:SetFrameLevel(btn:GetFrameLevel() + 2)
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:RegisterForDrag("LeftButton")

    -- Secure buttons fire on key/mouse DOWN when the ActionButtonUseKeyDown
    -- CVar is on (its default), but we only register for the UP click above --
    -- without this SecureActionButton_OnClick sees the "wrong" half of the
    -- click and silently does nothing, no error.
    overlay:SetAttribute("useOnKeyDown", false)

    -- A "/use <bag> <slot>" macro rather than the "item" action: the latter
    -- ends in EquipItemByName for anything equippable, so at a mailbox or
    -- vendor right-click would equip the item instead of attaching/selling it.
    -- /use goes through C_Container.UseContainerItem, which is contextual
    -- (attach at the mailbox, sell at a vendor, equip otherwise), exactly like
    -- Blizzard's own bag buttons.
    overlay:SetAttribute("type2", "macro")
    -- Modified right-clicks aren't "use" (the visible button's handler
    -- ignores them too); an empty string is Blizzard's explicit "no action".
    for _, prefix in ipairs(MODIFIED_CLICK_PREFIXES) do
        overlay:SetAttribute(prefix .. "type2", "")
        overlay:SetAttribute(prefix .. "type1", "")
    end

    -- Left-click is normally ours (pick up, drag, split...), except while a
    -- spell is waiting for an item to be aimed at (Disenchant, Prospecting,
    -- enchant scrolls...): then the click has to hand the item to that spell,
    -- which Blizzard's bag buttons do with UseContainerItem -- protected for
    -- us for the same reason as the right-click use, so it goes through the
    -- overlay too, with its left-click action switched on for just this click.
    -- Attributes can't change in combat; there the plain call is the fallback.
    overlay:SetScript("PreClick", function(self, mouseButton)
        self.spellTargeting, self.secureTarget = nil, nil
        if btn.embolsaoReadOnly then return end
        if mouseButton ~= "LeftButton" or not IsSpellTargetingItem() then return end

        self.spellTargeting = true
        if not InCombatLockdown() and btn.useOverlayAction then
            self:SetAttribute("type1", "macro")
            self:SetAttribute("macrotext1", "/use " .. btn.useOverlayAction)
            self.secureTarget = true
        end
    end)

    local function Forward(scriptName, ...)
        local handler = btn:GetScript(scriptName)
        if handler then handler(btn, ...) end
    end
    overlay:SetScript("OnEnter", function()
        btn:LockHighlight()
        Forward("OnEnter")
    end)
    overlay:SetScript("OnLeave", function()
        btn:UnlockHighlight()
        Forward("OnLeave")
    end)
    overlay:SetScript("OnDragStart", function() Forward("OnDragStart") end)
    overlay:SetScript("OnReceiveDrag", function() Forward("OnReceiveDrag") end)
    overlay:SetScript("PostClick", function(self, mouseButton)
        if self.spellTargeting then
            -- The click belonged to the waiting spell, not to the button's
            -- own handler (which would pick the item up).
            self.spellTargeting = nil
            if not self.secureTarget then
                C_Container.UseContainerItem(btn:GetBagID(), btn:GetID())
            end
            -- Back to no left-click action for the next ordinary click.
            if self.secureTarget and not InCombatLockdown() then
                self:SetAttribute("type1", nil)
            end
            self.secureTarget = nil
            return
        end
        Forward("OnClick", mouseButton)
    end)
    return overlay
end

-- Points the overlay at whatever (bagID, slot) the button now shows. Skipped
-- entirely in combat (creating or changing a protected frame is locked out);
-- the refresh that follows PLAYER_REGEN_ENABLED catches up.
local function UpdateUseOverlay(btn, bagID, slot)
    if InCombatLockdown() then return end

    local overlay = btn.UseOverlay
    if not overlay then
        overlay = CreateUseOverlay(btn)
        btn.UseOverlay = overlay
    end

    -- At a modern bank, right-click means deposit/withdraw, which needs the
    -- bank type passed along (Blizzard's own item buttons do the same) -- the
    -- secure "use item" action has no way to say that, so it's switched off
    -- there and the click handler moves the item itself.
    local action
    if bagID and bagID >= 0 and slot and slot > 0 and not Embolsao.AtBank then
        action = bagID .. " " .. slot
    end
    if btn.useOverlayAction ~= action then
        overlay:SetAttribute("macrotext2", action and ("/use " .. action) or nil)
        btn.useOverlayAction = action
    end
end

-- Vendor state for the Junk group's sell button. Tracked from
-- MERCHANT_SHOW/CLOSED (bottom of file) rather than only asking MerchantFrame,
-- which may not be shown yet at the moment the event reaches us; the frame
-- check still covers a /reload done while standing at a vendor.
local merchantOpen = false
local function IsAtMerchant()
    return merchantOpen or (_G.MerchantFrame ~= nil and _G.MerchantFrame:IsShown())
end

-- Sells every grey stack in `entries` (the Junk group as currently listed),
-- one item every SELL_INTERVAL seconds instead of all in the same frame --
-- a burst of dozens of sell calls at once is the kind of thing servers
-- throttle, and this way it also stops the moment the vendor window closes.
-- Plain C_Container.UseContainerItem is fine here: selling is not a
-- protected action (only spell-casting/on-use items are, see CreateUseOverlay).
local SELL_INTERVAL = 0.08
local sellingJunk = false

local function SellJunkEntries(entries)
    if sellingJunk or not IsAtMerchant() then return end

    local queue = {}
    local total = 0
    for _, entry in ipairs(entries) do
        if entry.isJunk then
            local sellPrice = select(11, Embolsao.GetItemInfo(entry.itemID))
            total = total + (sellPrice or 0) * entry.count
            for _, location in ipairs(entry.locations) do
                table.insert(queue, location)
            end
        end
    end
    if #queue == 0 then return end

    -- Always says so when it starts: this is the only place Embolsao ever
    -- sells anything, so no message means the sale wasn't ours.
    print(string.format(L.SELLING_JUNK, #queue, Embolsao.GetCoinTextureString(total)))

    sellingJunk = true
    local index = 0
    C_Timer.NewTicker(SELL_INTERVAL, function(ticker)
        if not IsAtMerchant() then
            ticker:Cancel()
            sellingJunk = false
            return
        end

        index = index + 1
        local location = queue[index]
        local info = location and C_Container.GetContainerItemInfo(location.bagID, location.slot)
        -- Re-checked per slot: things may have moved since the list was
        -- built, and some grey items have no vendor value at all. "Junk" is
        -- grey quality OR something the player marked as junk by hand.
        local userJunk = Embolsao.db and Embolsao.db.junkItemIDs
        local isJunk = info and (info.quality == 0 or (userJunk and userJunk[info.itemID]))
        if isJunk and not info.hasNoValue then
            C_Container.UseContainerItem(location.bagID, location.slot)
        end

        if index >= #queue then
            ticker:Cancel()
            sellingJunk = false
        end
    end)
end

local pawnRegistered = false
local pawnWindows = {} -- populated once both windows exist, see bottom of file

local function EnsurePawnRegistered()
    if pawnRegistered or not PawnRegisterThirdPartyBag then return end
    pawnRegistered = true
    PawnRegisterThirdPartyBag(ADDON_NAME, { RefreshAll = function()
        for _, win in ipairs(pawnWindows) do
            win.RefreshPawnIcons()
        end
    end })
end

local function UpdatePawnUpgradeIcon(btn, hyperlink)
    if not btn.UpgradeIcon then return end
    if not hyperlink or not PawnShouldItemLinkHaveUpgradeArrow then
        btn.pawnHyperlink = nil
        btn.UpgradeIcon:Hide()
        return
    end

    EnsurePawnRegistered()
    btn.pawnHyperlink = hyperlink
    local isUpgrade = PawnShouldItemLinkHaveUpgradeArrow(hyperlink, true)
    if isUpgrade == nil then
        -- Pawn isn't ready to answer yet (throttled) -- retry next frame,
        -- same pattern Pawn's own bag hook uses internally. Bails if this
        -- button has since been reused for a different item/hyperlink.
        C_Timer.After(0, function()
            if btn.pawnHyperlink == hyperlink then
                UpdatePawnUpgradeIcon(btn, hyperlink)
            end
        end)
        return
    end
    btn.UpgradeIcon:SetShown(isUpgrade)
end

-- Blizzard's own SetItemButtonQuality only shows/colors the border from
-- Uncommon and up -- Poor and Common items get none, same as native bags.
-- Called right after it (keeping whatever else that native call does),
-- this overrides just the border so every item's quality shows, including
-- Poor (grey) and Common (white).
local function ShowQualityBorder(btn, quality)
    local border = btn.IconBorder
    if not border then return end
    local r, g, b = Embolsao:GetItemQualityColor(quality)
    if not r then
        border:Hide()
        return
    end
    border:SetVertexColor(r, g, b, 1)
    border:Show()
end

-- Quest-starter items get the yellow "!" native bags show (haven't picked up
-- that quest yet); items already tied to an in-progress quest get a plain
-- border instead. Reads Core.lua's ScanBags cache (entry.questID/
-- isQuestActive/isQuestItem) rather than querying live here -- same
-- scan-time-cache reasoning as quality/itemLevel/stats -- bank entries never
-- have these stamped, so this is always a no-op there.
local function UpdateQuestTexture(btn, entry)
    local texture = btn.IconQuestTexture
    if not texture then return end

    local questID = entry and entry.questID
    if questID and not entry.isQuestActive then
        texture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
        texture:Show()
    elseif questID or (entry and entry.isQuestItem) then
        texture:SetTexture(TEXTURE_ITEM_QUEST_BORDER)
        texture:Show()
    else
        texture:Hide()
    end
end

-- What a special-bag family (the bitmask C_Container.GetContainerNumFreeSlots
-- reports as "bagFamily", stored on the empty-slot group by Core.lua) is
-- called on its button's tooltip: the profession/kind, not the name of one
-- particular bag -- two different mining bags are both just "Mining".
-- Anything not listed falls back to the bag's own name.
local BAG_FAMILY_LABEL_KEYS = {
    [1] = "BAG_FAMILY_QUIVER",
    [2] = "BAG_FAMILY_AMMO",
    [4] = "BAG_FAMILY_SOUL",
    [8] = "BAG_FAMILY_LEATHERWORKING",
    [16] = "BAG_FAMILY_INSCRIPTION",
    [32] = "BAG_FAMILY_HERBALISM",
    [64] = "BAG_FAMILY_ENCHANTING",
    [128] = "BAG_FAMILY_ENGINEERING",
    [512] = "BAG_FAMILY_JEWELCRAFTING",
    [1024] = "BAG_FAMILY_MINING",
}

-- The two windows (created below, once CreateWindow exists) and the single
-- frame they both live in -- declared up here because the menu and the frame's
-- layout code need to see them.
local bagsWindow, bankWindow

-- NOTE: Lua 5.1 (the game's) lets a function capture at most 60 outer locals,
-- and CreateWindow is close to it -- helpers it needs that are not already
-- captured hang off UI (UI.SetupSecureToggle, UI.ToggleOfflineBank, ...) rather
-- than being new module-level locals.
local host
function UI.GetHost() return host end -- for the files split out of this one

-- Ends the banking interaction with the NPC, the way closing Blizzard's own
-- bank window does (the banker says goodbye, the bank stops being open).
-- Hiding OUR window is not enough: it never closes anything on the game's side,
-- so the bank stayed open behind it and reopened with the bags key. The modern
-- bank has it under C_Bank; the classic one as a global.
local function EndBankInteraction()
    if not Embolsao.AtBank then return end
    if C_Bank and C_Bank.CloseBankFrame then
        C_Bank.CloseBankFrame()
    elseif CloseBankFrame then
        CloseBankFrame()
    end
end

-- The offline bank: away from any banker, the bank pane can show the copy that
-- was saved on the last visit (Core.lua's snapshots), read only -- nothing can
-- be picked up, dropped, used or moved, there is nobody to talk to. Leaving it
-- is closing the pane (or the window), or opening the real bank.
local function EndOfflineBank()
    if not Embolsao.BankOffline then return end
    Embolsao.BankOffline = false
    Embolsao.BankViewMode = "PERSONAL"
    bagsWindow.UpdateOfflineButton()
end

-- Which bank the offline view opens on: the personal one, or the Warband's
-- when that's the only one ever seen. nil when nothing has been saved yet.
local function GetOfflineStartView()
    if Embolsao:GetDisplayedBankSnapshot("PERSONAL") then return "PERSONAL" end
    if Embolsao:GetDisplayedBankSnapshot("WARBAND") then return "WARBAND" end
    return nil
end

local function ToggleOfflineBank()
    if Embolsao.AtBank then return end

    if Embolsao.BankOffline then
        bankWindow.Hide()
        EndOfflineBank()
        return
    end

    local view = GetOfflineStartView()
    if not view then return end
    Embolsao.BankOffline = true
    Embolsao.BankViewMode = view
    Embolsao:ScanBank()
    bankWindow.ShowOffline()
    bagsWindow.UpdateOfflineButton()
end

UI.GetOfflineStartView = GetOfflineStartView
UI.ToggleOfflineBank = ToggleOfflineBank

-- The alt viewer (Embolsao.ViewChar, Core.lua): the window's menu picks another
-- character, whose saved bags and bank then show read only -- with the
-- window's background tinted and the character named in the title, so it can't
-- be taken for your own bags. Closing the window (or visiting a banker) puts
-- your own items back.
local function ApplyViewedCharacterLook()
    if not host then return end
    local info = Embolsao:GetViewedCharacterInfo()

    if not host.viewTint then
        local tint = host:CreateTexture(nil, "BACKGROUND", nil, 1)
        tint:SetPoint("TOPLEFT", 4, -22)
        tint:SetPoint("BOTTOMRIGHT", -4, 4)
        tint:SetColorTexture(0.15, 0.35, 0.9, 0.3)
        tint:Hide()
        host.viewTint = tint
    end
    host.viewTint:SetShown(info ~= nil)
    local bg = host.Bg or (host.NineSlice and host.NineSlice.Bg)
    if bg and bg.SetVertexColor then
        if info then bg:SetVertexColor(0.55, 0.7, 1) else bg:SetVertexColor(1, 1, 1) end
    end

    local title = string.format("Embolsao!! v%s", UI.GetAddonVersion())
    if info then
        title = title .. " - " .. Embolsao:GetCharacterDisplayName(Embolsao.ViewChar, info)
    end
    if host.TitleContainer and host.TitleContainer.TitleText then
        host.TitleContainer.TitleText:SetText(title)
    elseif host.TitleText then
        host.TitleText:SetText(title)
    end
end
UI.ApplyViewedCharacterLook = ApplyViewedCharacterLook

-- The eye button: show / hide the items Hidden Items keeps out of the tabs.
function UI.ToggleShowHidden()
    Embolsao.ShowHiddenItems = not Embolsao.ShowHiddenItems
    UI:Refresh()
end

-- Back to your own items. Refreshing is left to the caller (the window is
-- closing, or a banker's window is about to refresh anyway).
function UI.ResetViewedCharacter()
    if not Embolsao.ViewChar then return end
    Embolsao.ViewChar = nil
    EndOfflineBank()
    Embolsao:ScanBags()
    ApplyViewedCharacterLook()
end

-- key: another character's key, or nil for your own.
function UI.ViewCharacter(key)
    if InCombatLockdown() or Embolsao.AtBank or key == Embolsao.ViewChar then return end
    -- Whatever bank copy is up belongs to the character being left.
    if Embolsao.BankOffline then
        bankWindow.Hide()
        EndOfflineBank()
    end
    Embolsao.ViewChar = key
    if key then
        Embolsao:ScanAltBags()
    else
        Embolsao:ScanBags()
    end
    ApplyViewedCharacterLook()
    UI:Refresh()
end

-- The "View character" submenu of the window's menu; nothing to offer in
-- combat, at a banker, or before any other character has saved its items.
function UI.BuildViewCharacterMenu(rootDescription)
    if InCombatLockdown() or Embolsao.AtBank then return end
    local alts = Embolsao:GetViewableCharacters()
    if #alts == 0 then return end

    local submenu = rootDescription:CreateButton(L.VIEW_CHARACTER)
    submenu:CreateRadio(L.VIEW_MYSELF,
        function() return Embolsao.ViewChar == nil end,
        function() UI.ViewCharacter(nil) end)
    submenu:CreateDivider()
    for _, alt in ipairs(alts) do
        local color = alt.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[alt.class]
        local label = color and ("|c" .. (color.colorStr or "ffffffff") .. alt.name .. "|r") or alt.name
        submenu:CreateRadio(label,
            function() return Embolsao.ViewChar == alt.key end,
            function() UI.ViewCharacter(alt.key) end)
    end
end

-- Retail's bank can move everything that belongs there in one go ("Deposit All
-- Reagents" on the personal bank, "Deposit All Warbound Items" on the Warband
-- one -- the button on Blizzard's own bank panel). Returns the bank type the
-- deposit would go to, or nil where there is no such thing: any other client
-- (Forever's bank has no such button), or no banker in reach.
local function GetDepositBankType()
    if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE or not Embolsao.AtBank then return nil end
    if not (C_Bank and C_Bank.AutoDepositItemsIntoBank and Enum and Enum.BankType) then return nil end
    -- Forever reports itself as the retail project and has the same API, but
    -- its bank has no deposit button: only offer one where the game's own bank
    -- panel has it.
    local panel = _G.BankFrame and _G.BankFrame.BankPanel
    if not (panel and panel.AutoDepositFrame) then return nil end

    local bankType = Embolsao.BankViewMode == "WARBAND" and Enum.BankType.Account or Enum.BankType.Character
    if C_Bank.DoesBankTypeSupportAutoDeposit and not C_Bank.DoesBankTypeSupportAutoDeposit(bankType) then
        return nil
    end
    if C_Bank.CanUseBank and not C_Bank.CanUseBank(bankType) then return nil end
    return bankType
end

local function DepositLabel(bankType)
    return bankType == Enum.BankType.Account and L.DEPOSIT_WARBOUND or L.DEPOSIT_REAGENTS
end

-- Same as Blizzard's button, refund-warning popup included: Warband storage
-- can't give an item back to the vendor, so the game asks first when any of
-- what would move is still refundable.
local function DepositAllIntoBank(bankType)
    if bankType == Enum.BankType.Account and ItemUtil and ItemUtil.IteratePlayerInventory
        and C_Bank.IsItemAllowedInBankType and C_Item and C_Item.CanBeRefunded then
        local hasRefundable = ItemUtil.IteratePlayerInventory(function(itemLocation)
            return C_Bank.IsItemAllowedInBankType(bankType, itemLocation) and C_Item.CanBeRefunded(itemLocation)
        end)
        if hasRefundable then
            StaticPopup_Show("ACCOUNT_BANK_DEPOSIT_ALL_NO_REFUND_CONFIRM", nil, nil, { bankType = bankType })
            return
        end
    end
    C_Bank.AutoDepositItemsIntoBank(bankType)
end

UI.GetDepositBankType = GetDepositBankType
UI.DepositLabel = DepositLabel
UI.DepositAllIntoBank = DepositAllIntoBank

-- Sizes of the ONE window. It holds up to two "panes" side by side (bank on
-- the left, bags on the right), each as wide as the plain single window has
-- always been; a bank visit doubles the window and splits the space evenly
-- between them, with a separator in the middle.
local PANE_DEFAULT_WIDTH = TAB_ICON_SIZE + TAB_GLOW_MARGIN * 2 + TAB_PANEL_PADDING * 2 + SCROLLBAR_CLEARANCE
    + TAB_TO_ITEMS_GAP
    + ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING) + SCROLLBAR_CLEARANCE + 20
local PANE_DEFAULT_HEIGHT = 420
local PANE_SEPARATOR_WIDTH = 8
-- Extra vertical room under the toolbar for a pane's name, when two panes
-- share the window.
local PANE_LABEL_EXTRA = 22

-- Sort By / Collapse All / Expand All belong to a pane (they act on the tab
-- it's showing); the rest of the menu is shared.
local function BuildPaneMenu(win, parent)
    -- Sort mode/direction apply to (and are remembered by) whichever tab
    -- this pane is currently showing, not to every tab at once.
    local tabID = win.StateID(win.GetActiveTab())

    local sortSubmenu = parent:CreateButton(L.SORT_AND_GROUP)

    local function IsSortSelected(mode)
        return (Layout.GetTabSort(tabID)) == mode
    end
    local function SetSort(mode)
        Layout.SetTabSort(tabID, mode, nil)
        UI:Refresh()
    end

    for _, sortOption in ipairs(Layout.SORT_MODES) do
        sortSubmenu:CreateRadio(sortOption.label, IsSortSelected, SetSort, sortOption.id)
    end

    sortSubmenu:CreateDivider()

    local function IsDirectionSelected(ascending)
        local _, currentAscending = Layout.GetTabSort(tabID)
        return currentAscending == ascending
    end
    local function SetDirection(ascending)
        Layout.SetTabSort(tabID, nil, ascending)
        UI:Refresh()
    end
    sortSubmenu:CreateRadio(L.SORT_ASCENDING, IsDirectionSelected, SetDirection, true)
    sortSubmenu:CreateRadio(L.SORT_DESCENDING, IsDirectionSelected, SetDirection, false)

    -- Grouping comes before the sort: groups are ordered by category, and the
    -- sort orders what's inside each. Like the sort itself it belongs to the
    -- tab being shown, and it is always on offer.
    sortSubmenu:CreateDivider()

    local function CreateGroupingCheckbox(label, key, index)
        sortSubmenu:CreateCheckbox(label,
            function() return select(index, Layout.GetTabGrouping(tabID)) == true end,
            function()
                Layout.SetTabGrouping(tabID, key, not select(index, Layout.GetTabGrouping(tabID)))
                UI:Refresh()
            end)
    end
    CreateGroupingCheckbox(L.MENU_GROUP_BY_CATEGORY, "groupByClass", 1)
    CreateGroupingCheckbox(L.MENU_GROUP_BY_SUBCATEGORY, "groupBySubClass", 2)

    -- The pinned Recent, Junk and Quest Items groups, for the tab being shown
    -- -- bags only: the bank never has any of them.
    if win == bagsWindow then
        local function CreatePinnedCheckbox(label, index)
            parent:CreateCheckbox(label,
                function() return select(index, Layout.GetTabPinnedGroups(tabID)) == true end,
                function()
                    local showRecent, showJunk, showQuest = Layout.GetTabPinnedGroups(tabID)
                    if index == 1 then showRecent = not showRecent
                    elseif index == 2 then showJunk = not showJunk
                    else showQuest = not showQuest end
                    Layout.SetTabPinnedGroups(tabID, showRecent, showJunk, showQuest)
                    UI:Refresh()
                end)
        end
        CreatePinnedCheckbox(L.SHOW_RECENT_SHORT, 1)
        CreatePinnedCheckbox(L.SHOW_JUNK_SHORT, 2)
        CreatePinnedCheckbox(L.SHOW_QUEST_ITEMS_SHORT, 3)
    end

    -- Only meaningful while the tab is actually grouped -- collapsing
    -- headers that aren't even shown wouldn't do anything.
    local groupByClass, groupBySubClass = Layout.GetTabGrouping(tabID)
    if groupByClass or groupBySubClass then
        parent:CreateButton(L.COLLAPSE_ALL_CATEGORIES, function()
            Layout.CollapseAllHeaders(win.GetFilteredEntries(), win)
        end)
        parent:CreateButton(L.EXPAND_ALL_CATEGORIES, function()
            Layout.ExpandAllHeaders(win)
        end)
    end
end

-- The window's one menu. With a single pane showing it is what it always was;
-- with two (bank + bags), the per-pane entries move into a submenu each, named
-- after the pane, so it's clear which one they'll act on.
local function BuildEmbolsaoMenu(rootDescription)
    local panes = {}
    if bankWindow.IsShown() then
        table.insert(panes, { win = bankWindow, label = L.PANE_BANK })
    end
    if bagsWindow.IsShown() then
        table.insert(panes, { win = bagsWindow, label = L.PANE_BAGS })
    end
    if #panes == 0 then
        panes[1] = { win = bagsWindow, label = L.PANE_BAGS }
    end

    if #panes == 1 then
        BuildPaneMenu(panes[1].win, rootDescription)
    else
        for _, pane in ipairs(panes) do
            BuildPaneMenu(pane.win, rootDescription:CreateButton(pane.label))
        end
    end

    rootDescription:CreateDivider()

    UI.BuildViewCharacterMenu(rootDescription)

    rootDescription:CreateButton(L.PREFERENCES, function() UI.ShowPreferencesFrame() end)

    rootDescription:CreateButton(L.BINDINGS, Bindings.ShowBindingsFrame)

    rootDescription:CreateButton(L.ABOUT, function() UI.ShowAboutFrame() end)
end

-- Sizes and places the window for whichever panes are showing right now: none
-- (hide it), one (that pane fills it), or two (bank left, bags right, half
-- each, separator between). Called every time a pane is shown or hidden. The
-- window's right edge stays put while its width changes, so opening the bank
-- grows it to the left and the bags don't move under the player's cursor.
local function LayoutHost()
    if not host then return end

    local bankShown = bankWindow.IsShown()
    local bagsShown = bagsWindow.IsShown()
    if not bankShown and not bagsShown then
        -- (Same combat restriction as the panes' Show/Hide, see ShowPane.)
        if not (InCombatLockdown() and host:IsProtected()) then
            host:Hide()
        else
            host.layoutPending = true
        end
        return
    end

    local count = (bankShown and 1 or 0) + (bagsShown and 1 or 0)
    local merged = count == 2
    local separator = merged and PANE_SEPARATOR_WIDTH or 0

    -- In combat nothing the item buttons' secure overlays hang from may be
    -- moved or resized (see the host's drag handler): panes just show and
    -- hide where they are, and the layout is redone when combat ends.
    -- (A pane that was never laid out has no overlays yet, so it can be.)
    if InCombatLockdown() then
        local laidOut = true
        for _, pane in ipairs({ bankWindow, bagsWindow }) do
            local paneFrame = pane.IsShown() and pane.GetFrame()
            if paneFrame and paneFrame:GetNumPoints() == 0 then laidOut = false end
        end
        if laidOut then
            host.layoutPending = true
            if not host:IsShown() and not host:IsProtected() then
                host:Show()
            end
            return
        end
    end
    host.layoutPending = nil
    host.paneCount = count

    -- Resize limits scale with the number of panes (the resize button reads
    -- these fields each time it enforces them).
    local resizeButton = host.resizeButton
    resizeButton.minWidth = PANE_DEFAULT_WIDTH * count + separator
    resizeButton.maxWidth = PANE_DEFAULT_WIDTH * 2 * count + separator

    local newWidth = host.paneWidth * count + separator
    if math.abs(host:GetWidth() - newWidth) > 0.5 then
        local right, top = host:GetRight(), host:GetTop()
        if right and top then
            host:ClearAllPoints()
            host:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
        end
        host:SetWidth(newWidth)
    end

    if merged then
        local bankFrame, bagsFrame = bankWindow.GetFrame(), bagsWindow.GetFrame()
        bankFrame:ClearAllPoints()
        bankFrame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        bankFrame:SetPoint("BOTTOMRIGHT", host, "BOTTOM", -separator / 2, 0)
        bagsFrame:ClearAllPoints()
        bagsFrame:SetPoint("TOPLEFT", host, "TOP", separator / 2, 0)
        bagsFrame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    else
        local only = (bankShown and bankWindow or bagsWindow).GetFrame()
        only:ClearAllPoints()
        only:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        only:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    end

    bankWindow.SetMergedLayout(merged)
    bagsWindow.SetMergedLayout(merged)
    host.separator:SetShown(merged)
    host:Show()

    -- Growing to the left can push the bank part past the screen's left edge
    -- when the window was parked near it: slide the whole window back on
    -- screen (once the new size has taken effect, next frame).
    if merged then
        C_Timer.After(0, function()
            if not host:IsShown() or InCombatLockdown() then return end
            local left = host:GetLeft()
            if left and left < 0 then
                local point, relativeTo, relativePoint, x, y = host:GetPoint()
                host:ClearAllPoints()
                host:SetPoint(point, relativeTo, relativePoint, x - left, y)
            end
        end)
    end
end

local function CreateHostMenuButton()
    local btn = CreateFrame("Button", nil, host)
    btn:SetSize(70, 24)
    btn:SetPoint("TOPRIGHT", -16, TOOLBAR_Y)

    -- The exact arrow atlas Blizzard's own WowStyle2DropdownTemplate uses
    -- for its chevron (confirmed in MenuTemplates.xml) -- a Unicode
    -- triangle glyph turned out invisible, the default UI fonts don't
    -- cover it.
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("RIGHT", -2, 0)
    btn.icon:SetAtlas("common-dropdown-c-button-hover-arrow", true)

    btn.label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    btn.label:SetPoint("RIGHT", btn.icon, "LEFT", -4, 1)
    btn.label:SetText(L.MENU_TOOLTIP)

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.MENU_TOOLTIP)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    btn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            BuildEmbolsaoMenu(rootDescription)
        end)
    end)

    return btn
end

-- Preferences -> "Opacity While Moving": like the world map, the window goes
-- (by default) mostly transparent while the character is walking so it
-- doesn't hide what is ahead, and comes back when they stop -- or whenever
-- the cursor is over it, so it can still be used on the move. Eased rather
-- than switched. Always on, no separate toggle: the slider itself is the
-- toggle -- set it to 100% for no fade at all, same effect a checkbox would
-- have had, one control instead of two. Only transparency changes, which
-- the game allows even in combat.
local DEFAULT_FADE_ALPHA = 0.5 -- opacity while moving, when Preferences hasn't set one
local function HostFadeOnUpdate(self, elapsed)
    local target = 1
    -- Retail hides some values from addons ("secret" values, e.g. in combat):
    -- comparing one is an error, so when the speed is one the window is simply
    -- left opaque instead of guessing.
    local speed = GetUnitSpeed("player")
    local known = speed ~= nil and not (issecretvalue and issecretvalue(speed))
    if known and speed > 0 and not self:IsMouseOver() then
        target = Embolsao.db.fadeAlpha or DEFAULT_FADE_ALPHA
    end
    local current = self:GetAlpha()
    if math.abs(current - target) < 0.01 then
        if current ~= target then self:SetAlpha(target) end
        return
    end
    self:SetAlpha(current + (target - current) * math.min(1, elapsed * 8))
end

-- Preferences -> "Background Opacity": a persistent baseline for the window's
-- background fill, independent of the walking fade above (which only dips
-- opacity temporarily, and dims the whole frame -- text and icons included
-- -- via SetAlpha, not just the background). This targets the background region
-- specifically, same reasoning as host.TitleContainer/TitleText below (the
-- exact regions PortraitFrameTemplate vs. PortraitFrameFlatTemplate expose
-- differ, so both are checked rather than assumed) -- if the flat "Bg"
-- texture doesn't exist on a given client, this becomes a silent no-op
-- rather than an error.
local function ApplyBackgroundOpacity()
    if not host then return end
    local alpha = Embolsao.db.backgroundOpacity or 1
    local bg = host.Bg or (host.NineSlice and host.NineSlice.Bg)
    if bg and bg.SetAlpha then
        bg:SetAlpha(alpha)
    end
end

-- The ONE window frame both panes live in: Blizzard's portrait-style panel
-- (border, portrait, title, close button for free), the drag, the resize
-- grip, the position and size that are remembered between sessions, the
-- menu, and the separator between the panes. The window size is stored as
-- the width of ONE pane, so it means the same whether the bank is showing
-- or not, and resizing it resizes both panes together.
local function EnsureHost()
    if host then return host end

    host = CreateFrame("Frame", "EmbolsaoWindowFrame", UIParent, Embolsao.PORTRAIT_FRAME_TEMPLATE)

    local savedSize = Embolsao.db.rememberPosition and Embolsao.db.windowSize
    host.paneWidth = savedSize and savedSize.width or PANE_DEFAULT_WIDTH
    host.paneCount = 1
    host:SetSize(host.paneWidth, savedSize and savedSize.height or PANE_DEFAULT_HEIGHT)

    local savedPosition = Embolsao.db.rememberPosition and Embolsao.db.windowPosition
    if savedPosition then
        host:SetPoint(savedPosition.point, UIParent, savedPosition.relativePoint or savedPosition.point,
            savedPosition.x, savedPosition.y)
    else
        host:SetPoint("CENTER")
    end

    host:SetFrameStrata("HIGH")
    host:SetClampedToScreen(true)
    host:SetMovable(true)
    host:EnableMouse(true)
    host:RegisterForDrag("LeftButton")
    -- The item buttons carry secure overlays anchored (through their parents)
    -- to this frame, and the game won't let anything a secure frame hangs from
    -- be moved or resized in combat -- so neither can the window.
    host:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(L.CANT_MOVE_IN_COMBAT, 1, 0.2, 0.2)
            return
        end
        self:StartMoving()
    end)
    host:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if Embolsao.db.rememberPosition then
            local point, _, relativePoint, x, y = self:GetPoint()
            Embolsao.db.windowPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
        end
    end)

    -- Remember the width of one pane (see above), whichever way the window
    -- got resized. Must be set BEFORE the resize button's Init below, which
    -- wraps whatever OnSizeChanged script is there.
    host:SetResizable(true)
    host:SetScript("OnSizeChanged", function(self, width, height)
        local separator = self.paneCount == 2 and PANE_SEPARATOR_WIDTH or 0
        self.paneWidth = (width - separator) / self.paneCount
        if Embolsao.db.rememberPosition then
            Embolsao.db.windowSize = { width = self.paneWidth, height = height }
        end
    end)

    local resizeButton = CreateFrame("Button", nil, host, "PanelResizeButtonTemplate")
    resizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeButton:Init(host, PANE_DEFAULT_WIDTH, PANE_DEFAULT_HEIGHT, PANE_DEFAULT_WIDTH * 2, PANE_DEFAULT_HEIGHT * 2)
    host.resizeButton = resizeButton

    host:SetScript("OnUpdate", HostFadeOnUpdate)

    host:Hide()
    -- Closing the window (its own X, Escape...) closes both parts -- and, if
    -- the bank part was up, the banking interaction itself. (Read before the
    -- panes are hidden: when the bank closes on its own, its pane is already
    -- hidden by the time this runs, so this doesn't fire twice.)
    host:HookScript("OnHide", function(self)
        self:SetAlpha(1) -- the next opening starts fully opaque
        local bankWasShown = bankWindow.IsShown()
        bagsWindow.Hide()
        bankWindow.Hide()
        if bankWasShown then
            EndBankInteraction()
        end
        EndOfflineBank()
        -- Closing the bags always brings your own items back, and hides
        -- what is hidden again.
        UI.ResetViewedCharacter()
        Embolsao.ShowHiddenItems = false
    end)

    -- Let Escape close us too, same as any other native panel.
    tinsert(UISpecialFrames, "EmbolsaoWindowFrame")

    host:SetPortraitToAsset(PORTRAIT_ICON)
    local title = string.format("Embolsao!! v%s", UI.GetAddonVersion())
    if host.TitleContainer and host.TitleContainer.TitleText then
        host.TitleContainer.TitleText:SetText(title)
    elseif host.TitleText then
        host.TitleText:SetText(title)
    end

    ApplyBackgroundOpacity()

    host.menuButton = CreateHostMenuButton()

    -- The divider between the two panes; only there while both are.
    host.separator = host:CreateTexture(nil, "ARTWORK")
    host.separator:SetColorTexture(1, 1, 1, 0.25)
    host.separator:SetWidth(2)
    host.separator:SetPoint("TOP", host, "TOP", 0, -(CONTENT_TOP_OFFSET - 6))
    host.separator:SetPoint("BOTTOM", host, "BOTTOM", 0, BOTTOM_MARGIN + 2)
    host.separator:Hide()

    return host
end

--------------------------------------------------------------------------
-- Pane factory: everything that's genuinely tied to ONE pane of the Embolsao
-- window (its tab panel, search box, item grid, footer, drag state, stack
-- popout) lives here as a local instead of a module-level singleton, so each
-- call produces one independent, fully-featured pane. Called once for the
-- bags pane and once for the bank pane (further down) -- both get tabs,
-- search, sort, collapsible categories, empty-slot groups and stack popouts
-- identically, since it's the exact same code either way. The two panes share
-- ONE window frame (EnsureHost); the internal names still say "window".
--
-- config fields:
--   id                 -- "Bags" | "Bank", used for frame/global names
--   paneLabel()        -- the pane's name, shown above it when two panes share the window
--   closablePane       -- give the pane its own X, closing just that pane (bank)
--   OnShown()          -- optional; runs right after the pane is shown from a native frame
--   hasFooter          -- money/XP strip (bags) or bank purchase strip (bank)
--   hasBankPurchase    -- footer offers to buy more bank space (bank only)
--   hasBankModeToggle  -- Bank/Warband Bank toggle (bank only)
--   applyDefaultTab    -- honor the "Default Tab" preference on open (bags only)
--   GetInventory()          -> the merged {[itemID]=entry} table to show
--   GetEmptySlotGroups()    -> that pool's empty-slot groups (Core.lua)
--   GetActiveTab() / SetActiveTab(id)
--   Rescan()           -- (re)populate GetInventory()'s backing data
--   IsManagedFrame(bagFrame) -- which native frames this window takes over
--------------------------------------------------------------------------

-- Every native frame either window has hooked OnShow/OnHide for -- shared,
-- since a frame belongs to at most one window's domain and both windows'
-- HandleNativeShow/Hide filter this same list via their own IsManagedFrame.
-- Declared here (not down by InstallBagFrameHooks, where it conceptually
-- lives) so CreateWindow's closures below can see it as an upvalue.
local nativeBagFrames = {}

-- Guards against a window's own SuppressNativeFrames() (below) hiding a
-- native frame and having that immediately fire OnBagFrameHide right back
-- at us, undoing the takeover it was just doing. Shared: only one
-- suppression pass across either window is ever in flight at a time.
local suppressingNativeHide = false

local function CreateWindow(config)
    local win = {}
    win.searchText = ""
    win.stackPopoutItemID = nil
    win.dropTarget, win.dropAfter = nil, nil
    win.suppressTakeoverOnce = nil
    win.keepOpenDuringPeek = nil

    -- True for the bank pane while it shows the saved copy (the offline bank):
    -- its buttons then only show and describe, never act (see EndOfflineBank).
    -- Both panes are read only while another character's items are shown.
    function win.IsReadOnly()
        if Embolsao.ViewChar then return true end
        return Embolsao.BankOffline == true and config.id == "Bank"
    end

    local frame
    local tabButtons = {}
    local itemButtons = {}
    local headerRows = {}
    local emptySlotButtons = {}
    local dropIndicator
    local stackPopout
    local stackPopoutButtons = {}

    -- Showing or hiding a pane has to lay the window out EXPLICITLY. A pane
    -- is a child of the window frame, which starts hidden -- and a child of a
    -- hidden frame never gets its OnShow when Show() is called (it isn't
    -- visible yet), so waiting on that event would leave the window hidden
    -- forever: the native bag sound plays, nothing appears, no error.
    --
    -- In combat the game won't show or hide a frame that has a secure frame
    -- anywhere below it (IsProtected() is true for those too, not just for the
    -- secure frame itself), and the item buttons' overlays are such frames:
    -- the attempt is refused with an "action blocked" message. So a pane that
    -- has them waits: ShowPane returns false (the caller then leaves Blizzard's
    -- own bags on screen), HidePane says so, and win.RunPending does what was
    -- asked once combat ends.
    local function ShowPane()
        if InCombatLockdown() and frame:IsProtected() and not frame:IsShown() then
            win.pendingShow = true
            return false
        end
        win.pendingShow = nil
        if not frame:IsShown() then
            frame:Show()
        end
        LayoutHost()
        return true
    end

    local function HidePane()
        if frame and InCombatLockdown() and frame:IsProtected() and frame:IsShown() then
            -- (Closed through the window's own X or Escape, which the game
            -- does allow: the pane's flag catches up when combat ends.)
            win.pendingHide = true
            if host and host:IsShown() then
                UIErrorsFrame:AddMessage(L.CANT_CLOSE_IN_COMBAT, 1, 0.2, 0.2)
            end
            return false
        end
        win.pendingHide = nil
        -- (Only what is actually up: hiding what is hidden is still a call the
        -- game refuses in combat.)
        if frame and frame:IsShown() then frame:Hide() end
        -- Same reason as above: the pane's own OnHide won't fire if the whole
        -- window is already hidden, but its stack popout still has to go.
        if stackPopout and stackPopout:IsShown() then
            win.ToggleStackExpansion(nil)
        end
        LayoutHost()
        return true
    end

    -- Combat is over: whatever ShowPane / HidePane had to refuse.
    function win.RunPending()
        if win.pendingHide then
            HidePane()
        elseif win.pendingShow then
            win.pendingShow = nil
            -- The native bags were left up meanwhile: take them over now.
            for _, bagFrame in ipairs(nativeBagFrames) do
                if bagFrame:IsShown() and config.IsManagedFrame(bagFrame) then
                    win.HandleNativeShow(bagFrame)
                    break
                end
            end
        end
    end

    -- The tab this window is actually showing: config.GetActiveTab() can name
    -- a tab that has since been hidden/deleted, in which case the window falls
    -- back to its first tab -- per-tab state (sort, collapsed headers) has to
    -- key off that same effective tab, not the stale saved ID.
    function win.GetActiveTab()
        local activeTab = config.GetActiveTab()
        local tabs = frame and frame.currentTabs
        if not tabs then return activeTab end
        for _, tab in ipairs(tabs) do
            if tab.id == activeTab then return activeTab end
        end
        return tabs[1] and tabs[1].id or activeTab
    end

    -- A tab's ID as its saved per-tab state (sort, collapsed categories) is
    -- keyed: prefixed for the bank's own set of tabs, since "All" exists in both
    -- sets and would otherwise share that state (see Filters.keys.statePrefix).
    function win.StateID(tabID)
        return Embolsao:GetTabStatePrefix(config.domain) .. tabID
    end

    -- Called by LayoutHost whenever the window switches between one pane and
    -- two. With two, each pane gets its name above its tabs and items (which
    -- pushes them down a row) and, for a pane that can close on its own, an X;
    -- alone, it looks exactly like the plain single window always did.
    -- Lays out the Gearset action row (Equip, Move to Bank, Get from Bank):
    -- only the ones actually showing, each chained to the one before, so a
    -- hidden button never leaves a gap -- the first showing one takes the
    -- start of the row. Alone the row sits above "Sorted by ..."; with two
    -- panes that label moves up to the pane-name row, so it hangs off the
    -- item grid's own top instead (where win.SetItemBar reserves its space
    -- either way). `merged` defaults to the current layout.
    function win.LayoutGearsetButtons(merged)
        if not frame or not frame.gearsetActionButton then return end
        if merged == nil then merged = win.mergedLayout end

        local previous
        for _, button in ipairs({
            frame.gearsetActionButton, frame.gearsetDepositButton, frame.gearsetWithdrawButton,
        }) do
            if button:IsShown() then
                button:ClearAllPoints()
                if previous then
                    button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
                elseif merged then
                    button:SetPoint("BOTTOMLEFT", frame.itemScrollFrame, "TOPLEFT", 0, 3)
                else
                    button:SetPoint("BOTTOMLEFT", frame.sortLabel, "TOPLEFT", 0, 4)
                end
                previous = button
            end
        end
    end

    function win.SetMergedLayout(merged)
        if not frame or not frame.tabPanel then return end
        -- Re-anchors things the secure overlays hang from: not in combat
        -- (LayoutHost calls again once it ends) -- except the very first
        -- time, when there are no overlays yet.
        if InCombatLockdown() and frame.tabPanel:GetNumPoints() > 0 then return end

        local extra = merged and PANE_LABEL_EXTRA or 0
        frame.tabPanel:ClearAllPoints()
        frame.tabPanel:SetPoint("TOPLEFT", 10, -(CONTENT_TOP_OFFSET + extra))
        frame.tabPanel:SetPoint("BOTTOMLEFT", 10, BOTTOM_MARGIN)

        -- The search box stays on the toolbar row whatever the tab panel
        -- does, so its offset from the panel's top grows by the same amount.
        frame.searchBox:ClearAllPoints()
        frame.searchBox:SetPoint("TOPLEFT", frame.tabPanel, "TOPRIGHT", TAB_TO_ITEMS_GAP, CONTENT_TOP_OFFSET + extra + TOOLBAR_Y)

        frame.paneLabel:SetShown(merged)
        if frame.closePaneButton then
            frame.closePaneButton:SetShown(merged)
        end

        -- The "Sorted by ..." line: with two panes it goes on the pane name's
        -- own row, right after it (one row of heading: "Bank  Sorted by Name
        -- (Ascending)"), so the two can't overlap; alone it sits above the
        -- item grid, under the search box, as it always did.
        if frame.sortLabel then
            frame.sortLabel:ClearAllPoints()
            if merged then
                frame.sortLabel:SetPoint("BOTTOMLEFT", frame.paneLabel, "BOTTOMRIGHT", 14, 2)
                frame.sortLabel:SetPoint("RIGHT", frame, "RIGHT", frame.closePaneButton and -40 or -16, 0)
            else
                frame.sortLabel:SetPoint("BOTTOMLEFT", frame.itemScrollFrame, "TOPLEFT", 2, 3)
                frame.sortLabel:SetPoint("RIGHT", frame.itemScrollFrame, "RIGHT")
            end
        end
        win.LayoutGearsetButtons(merged)

        -- The name row changes how tall the lists are without changing the
        -- pane's own size (so no OnSizeChanged): whether they still need
        -- their scrollbars has to be checked once the new layout is in.
        if win.mergedLayout ~= merged then
            win.mergedLayout = merged
            C_Timer.After(0, function()
                if frame:IsShown() then win.Refresh() end
            end)
        end
    end

    local function EnsureDropIndicator()
        if dropIndicator then return dropIndicator end
        dropIndicator = frame.tabColumn:CreateTexture(nil, "OVERLAY")
        dropIndicator:SetHeight(4)
        dropIndicator:SetColorTexture(0.3, 1, 1, 1)
        dropIndicator:Hide()
        return dropIndicator
    end

    -- Returns the tab button the drag should insert before (or, for the
    -- very last slot, the one to insert after) plus that placeAfter flag.
    -- See the original comment history for why this walks by Y position
    -- rather than "whichever button is under the cursor".
    local function GetDropTarget(draggedButton)
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / UIParent:GetEffectiveScale()

        for _, btn in ipairs(tabButtons) do
            if btn ~= draggedButton and btn.tabData then
                local _, centerY = btn:GetCenter()
                if centerY and cursorY > centerY then
                    return btn, false
                end
            end
        end

        for i = #tabButtons, 1, -1 do
            local btn = tabButtons[i]
            if btn ~= draggedButton and btn.tabData then
                return btn, true
            end
        end

        return nil
    end

    local function CreateTabButton(index, tabData)
        local btn = CreateFrame("Button", nil, frame.tabColumn)
        btn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
        btn:SetPoint("TOP", 0, -(index - 1) * (TAB_ICON_SIZE + TAB_PADDING))

        -- A background plate (plus the selection highlight below) makes
        -- these read as buttons rather than item slots.
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetPoint("TOPLEFT", -4, 4)
        btn.bg:SetPoint("BOTTOMRIGHT", 4, -4)
        btn.bg:SetColorTexture(0, 0, 0, 0.5)

        btn.selectedBg = btn:CreateTexture(nil, "BORDER")
        btn.selectedBg:SetAllPoints(btn.bg)
        btn.selectedBg:SetColorTexture(1, 0.82, 0, 0.35)
        btn.selectedBg:Hide()

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints()
        btn.icon:SetTexture(tabData.icon)
        -- Trim the icon's built-in border so square icons stack cleanly.
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- A Gearset tab currently being worn gets a green ring around its
        -- icon -- same trick as selectedBg above (a solid-color texture a
        -- few px larger than the icon, peeking out as a border), just an
        -- outer ring so it can still show alongside the yellow "selected"
        -- one instead of fighting it for the same pixels.
        local isGearsetEquipped = false
        if tabData.tabType == "gearset" then
            local tab = Embolsao:GetFilters(config.domain):GetCustomTab(tabData.id)
            isGearsetEquipped = tab ~= nil and Embolsao.Gearset:IsEquipped(tab)
        end
        if isGearsetEquipped then
            -- A solid-color texture peeking out around the icon (the first
            -- attempt) read as a big green block, not a border. A second
            -- attempt (a BackdropTemplate border frame) mostly hid behind
            -- the button's own bg/icon textures -- a child FRAME's regions
            -- don't reliably draw above a parent's own texture layers here.
            -- Four thin OVERLAY-layer texture strips instead (same draw
            -- layer the icon itself uses, so they're guaranteed on top),
            -- one per edge, tracing the icon's outline.
            local GLOW_THICKNESS = 2
            local function CreateGlowEdge()
                local edge = btn:CreateTexture(nil, "OVERLAY")
                edge:SetColorTexture(0.1, 1, 0.2, 1)
                return edge
            end
            -- Outside the icon (preferred look) -- needs actual room to its
            -- sides, not just top/bottom (which had the gap between stacked
            -- icons to spill into already): the tab column is now widened
            -- by TAB_GLOW_MARGIN on each side specifically for this,
            -- instead of clipping against the icon's own width like before.
            local OUTSET = 3
            local top, bottom, left, right = CreateGlowEdge(), CreateGlowEdge(), CreateGlowEdge(), CreateGlowEdge()
            top:SetPoint("TOPLEFT", -OUTSET, OUTSET)
            top:SetPoint("TOPRIGHT", OUTSET, OUTSET)
            top:SetHeight(GLOW_THICKNESS)
            bottom:SetPoint("BOTTOMLEFT", -OUTSET, -OUTSET)
            bottom:SetPoint("BOTTOMRIGHT", OUTSET, -OUTSET)
            bottom:SetHeight(GLOW_THICKNESS)
            left:SetPoint("TOPLEFT", -OUTSET, OUTSET)
            left:SetPoint("BOTTOMLEFT", -OUTSET, -OUTSET)
            left:SetWidth(GLOW_THICKNESS)
            right:SetPoint("TOPRIGHT", OUTSET, OUTSET)
            right:SetPoint("BOTTOMRIGHT", OUTSET, -OUTSET)
            right:SetWidth(GLOW_THICKNESS)
            btn.equippedGlowEdges = { top, bottom, left, right }
        end

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tabData.name)
            if isGearsetEquipped then
                GameTooltip:AddLine(L.GEARSET_EQUIPPED_HINT, 0, 1, 0)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)

        -- Right-click now always has at least Edit to offer, "All" included
        -- -- built-in tabs (All among them) can have hidden items/category
        -- rules layered on top since Filters:UpdateBuiltInOverride.
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                Embolsao.TabEditor:ShowTabContextMenu(self, tabData, config.domain)
                return
            end
            config.SetActiveTab(tabData.id)
            win.Refresh()
        end)

        -- Drag an item from the bag grid straight onto this tab to hide it
        -- there (with confirmation) -- OnReceiveDrag covers releasing the
        -- drag directly over the button; OnMouseUp covers picking the item
        -- up with a click first and then clicking the tab.
        btn:SetScript("OnReceiveDrag", function()
            TryHideCursorItemOnTab(tabData, config.domain)
        end)
        btn:SetScript("OnMouseUp", function()
            if CursorHasItem() then
                TryHideCursorItemOnTab(tabData, config.domain)
            end
        end)

        -- Drag-to-reorder: OnDragStart fires on this button, but OnDragStop
        -- also always fires here (not on whatever's under the cursor when
        -- you let go) -- so the drop target has to be computed explicitly
        -- via GetDropTarget() rather than relied on to fire its own handler.
        -- "All" (tabData.id == "ALL") is exempt: it can't move.
        btn.tabData = tabData
        if tabData.id ~= "ALL" then
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                self:SetAlpha(0.4)

                local ghost = EnsureDragGhost()
                ghost.icon:SetTexture(tabData.icon)
                UpdateDragGhostPosition()
                ghost:Show()

                self:SetScript("OnUpdate", function(dragged)
                    UpdateDragGhostPosition()

                    local target, placeAfter = GetDropTarget(dragged)
                    win.dropTarget, win.dropAfter = target, placeAfter

                    local indicator = EnsureDropIndicator()
                    if target then
                        indicator:ClearAllPoints()
                        if placeAfter then
                            indicator:SetPoint("TOPLEFT", target, "BOTTOMLEFT", -4, 2)
                            indicator:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 4, 2)
                        else
                            indicator:SetPoint("BOTTOMLEFT", target, "TOPLEFT", -4, -2)
                            indicator:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", 4, -2)
                        end
                        indicator:Show()
                    else
                        indicator:Hide()
                    end
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                self:SetAlpha(1)
                self:SetScript("OnUpdate", nil)
                dragGhost:Hide()
                if dropIndicator then
                    dropIndicator:Hide()
                end

                local target, placeAfter = win.dropTarget, win.dropAfter
                win.dropTarget, win.dropAfter = nil, nil
                if target then
                    Embolsao:GetFilters(config.domain):MoveTabRelative(self.tabData.id, target.tabData.id, placeAfter)
                    win.BuildTabs()
                    win.Refresh()
                end
            end)
        end

        return btn
    end

    -- Always the last button in the tab column, regardless of how many real
    -- tabs exist -- opens the create-tab form.
    local function CreateNewTabButton()
        local btn = CreateFrame("Button", nil, frame.tabColumn)
        btn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetPoint("TOPLEFT", -4, 4)
        btn.bg:SetPoint("BOTTOMRIGHT", 4, -4)
        btn.bg:SetColorTexture(0, 0, 0, 0.5)

        btn.label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        btn.label:SetAllPoints()
        btn.label:SetText("+")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.NEW_TAB_TOOLTIP)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)
        btn:SetScript("OnClick", function()
            Embolsao.TabEditor:ShowTypeChooser(config.domain)
        end)

        return btn
    end

    -- One PANE: everything that used to make up a whole window (tab panel,
    -- search box, item grid, footer). It's now a child of the single shared
    -- window frame (EnsureHost above), which supplies the border, portrait,
    -- title, menu, dragging and resizing; LayoutHost decides where in that
    -- frame each pane sits and how wide the frame is.
    local function EnsureFrame()
        if frame then return frame end

        EnsureHost()
        frame = CreateFrame("Frame", "Embolsao" .. config.id .. "Pane", host)
        frame:SetAllPoints(host)
        frame:Hide()

        -- The item grid's column count depends on the pane's current width:
        -- reflow whenever it changes (window resized, bank part opened...).
        frame:SetScript("OnSizeChanged", function() win.Refresh() end)
        -- The window is laid out by ShowPane/HidePane, deliberately NOT from
        -- here: when the whole window closes, every pane gets an OnHide too
        -- while still flagged as shown, and re-laying out from that would
        -- open the window right back.
        frame:HookScript("OnHide", function()
            win.ToggleStackExpansion(nil)
        end)

        -- Recessed side panel for the filter tabs, visually distinct from
        -- the item grid so tabs don't read as just more bag slots. Its real
        -- anchors are set by win.SetMergedLayout (below), which also makes room
        -- for the pane's name label when two panes share the window.
        frame.tabPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.tabPanel:SetWidth(TAB_ICON_SIZE + TAB_GLOW_MARGIN * 2 + TAB_PANEL_PADDING * 2)
        frame.tabPanel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame.tabPanel:SetBackdropColor(0, 0, 0, 0.35)
        frame.tabPanel:SetBackdropBorderColor(1, 1, 1, 0.25)

        -- Own search box, not Blizzard's native bag one -- filters our own
        -- list by item name instead. Aligned with the item grid's left edge,
        -- not the pane's, so it doesn't sit under the portrait icon.
        frame.searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
        frame.searchBox:SetSize(150, 20)
        frame.searchBox:HookScript("OnTextChanged", function(self)
            win.searchText = self:GetText() or ""
            win.Refresh()
        end)

        -- The eye: show the items that Hidden Items / gearset "Hide from bags"
        -- keep out of the tabs (one setting for every tab and both panes, off
        -- again whenever the window closes). Struck through = still hidden.
        -- The buttons after the search box hang from it.
        local eye = CreateFrame("Button", nil, frame)
        eye:SetSize(26, 26)
        eye:SetPoint("LEFT", frame.searchBox, "RIGHT", 6, 0)
        eye.icon = eye:CreateTexture(nil, "ARTWORK")
        eye.icon:SetAllPoints()
        eye.icon:SetTexture("Interface\\AddOns\\Embolsao\\icons\\eye.tga")
        eye.strike = eye:CreateTexture(nil, "OVERLAY")
        eye.strike:SetSize(30, 3)
        eye.strike:SetPoint("CENTER")
        eye.strike:SetRotation(math.rad(45))
        eye.strike:SetColorTexture(0.9, 0.1, 0.1, 1)
        eye:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        eye:SetScript("OnClick", function() UI.ToggleShowHidden() end)
        eye:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Embolsao.ShowHiddenItems and L.EYE_SHOWN or L.EYE_HIDDEN)
            GameTooltip:AddLine(L.EYE_DESC, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        eye:SetScript("OnLeave", GameTooltip_Hide)
        frame.eyeButton = eye

        -- The pane's name ("Bags" / "Bank"), a size up from the rest of the
        -- text, just above its tabs and items -- only shown while two panes
        -- share the window and it matters which is which.
        frame.paneLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        frame.paneLabel:SetPoint("TOPLEFT", 14, -CONTENT_TOP_OFFSET)
        frame.paneLabel:SetText(config.paneLabel())
        frame.paneLabel:Hide()

        -- Closes just this pane (the window's own X closes everything). Only
        -- panes that can come and go on their own have one -- the bank part.
        if config.closablePane then
            local closePane = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
            closePane:SetSize(22, 22)
            closePane:SetPoint("TOPRIGHT", -12, -(CONTENT_TOP_OFFSET - 4))
            closePane:SetScript("OnClick", function()
                win.Hide()
                if config.OnClosePane then config.OnClosePane() end
            end)
            closePane:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L.CLOSE_PANE_TOOLTIP)
                GameTooltip:Show()
            end)
            closePane:SetScript("OnLeave", GameTooltip_Hide)
            closePane:Hide()
            frame.closePaneButton = closePane
        end

        -- Both the tab column and the item grid are wrapped in a real
        -- UIPanelScrollFrameTemplate (mouse wheel + scrollbar included for
        -- free) since both lists can outgrow the visible area.
        frame.tabScrollFrame = CreateFrame("ScrollFrame", nil, frame.tabPanel, "UIPanelScrollFrameTemplate")
        -- The scrollbars only take room while their list overflows (the
        -- template hides its bar when there is nothing to scroll); the
        -- anchors below are the bar-less geometry, and win.SetTabBar /
        -- win.SetItemBar widen the reserved strip when Refresh finds a list
        -- that does overflow.
        frame.tabScrollFrame.scrollBarHideable = true
        frame.tabScrollFrame:SetPoint("TOPLEFT", TAB_PANEL_PADDING, -TAB_PANEL_PADDING)
        frame.tabScrollFrame:SetPoint("BOTTOMRIGHT", -TAB_PANEL_PADDING, TAB_PANEL_PADDING)
        frame.tabBarShown = false
        -- Right-click anywhere in here that isn't a tab button falls
        -- through to this -- covers the thin margin around the column and
        -- any empty space below the last tab.
        frame.tabScrollFrame:HookScript("OnMouseUp", function(self, mouseButton)
            if mouseButton == "RightButton" then
                ShowHiddenTabsMenu(self, config.domain)
            end
        end)

        -- Anchored on TOPLEFT only, with an explicit width and a height kept
        -- up to date in Refresh -- a scroll child's rect must always be
        -- fully resolved.
        frame.tabColumn = CreateFrame("Frame", nil, frame.tabScrollFrame)
        frame.tabColumn:SetPoint("TOPLEFT")
        frame.tabColumn:SetSize(TAB_ICON_SIZE + TAB_GLOW_MARGIN * 2, TAB_ICON_SIZE)
        frame.tabScrollFrame:SetScrollChild(frame.tabColumn)

        -- Item grid, well clear of the tab panel, using real ItemButton
        -- widgets so icons/borders/counts render like Blizzard's own bag
        -- slots.
        frame.itemScrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.itemScrollFrame:SetPoint("TOPLEFT", frame.tabPanel, "TOPRIGHT", TAB_TO_ITEMS_GAP, 0)
        local footerClearance = config.hasFooter and (BOTTOM_MARGIN + FOOTER_HEIGHT + FOOTER_GAP) or BOTTOM_MARGIN
        frame.itemScrollFrame.scrollBarHideable = true
        frame.itemScrollFrame:SetPoint("BOTTOMRIGHT", -10, footerClearance)
        frame.itemBarShown = false
        win.itemBottomInset = footerClearance

        frame.itemContainer = CreateFrame("Frame", nil, frame.itemScrollFrame)
        frame.itemContainer:SetPoint("TOPLEFT")
        frame.itemContainer:SetSize(ITEMS_PER_ROW * (ITEM_SIZE + ITEM_PADDING), ITEM_SIZE)
        frame.itemScrollFrame:SetScrollChild(frame.itemContainer)

        -- Anchors for the tab panel and search box (see SetMergedLayout).
        win.SetMergedLayout(false)

        -- What the tab is sorted by, always in view under the search box
        -- ("Sorted by Category (Ascending)"); set in Refresh.
        frame.sortLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        frame.sortLabel:SetPoint("BOTTOMLEFT", frame.itemScrollFrame, "TOPLEFT", 2, 3)
        frame.sortLabel:SetPoint("RIGHT", frame.itemScrollFrame, "RIGHT")
        frame.sortLabel:SetJustifyH("LEFT")
        frame.sortLabel:SetWordWrap(false)

        -- Equip/Unequip for a Gearset tab -- its own row above Sorted By
        -- (win.SetItemBar pushes frame.itemScrollFrame, and sortLabel right
        -- along with it since it's anchored off itemScrollFrame's own
        -- TOPLEFT, down by GEARSET_BAR_HEIGHT whenever this is shown) rather
        -- than squeezed into an existing row -- the first attempt (sharing
        -- the Sorted By row) overlapped the Menu dropdown. Refresh sets its
        -- text/visibility; ShowTabContextMenu has the equivalent menu entry.
        frame.gearsetActionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.gearsetActionButton:SetSize(120, 20)
        frame.gearsetActionButton:Hide()
        frame.gearsetActionButton:SetScript("OnClick", function()
            local tab = Embolsao:GetFilters(config.domain):GetCustomTab(win.GetActiveTab())
            if not tab then return end
            if Embolsao.Gearset:IsEquipped(tab) then
                Embolsao.Gearset:Unequip(tab)
            else
                Embolsao.Gearset:Equip(tab)
            end
            win.BuildTabs()
            win.Refresh()
        end)

        -- At a banker, on a Gearset tab (bags window only): stash the set's
        -- items in the bank / fetch the ones that are missing from it. Both
        -- ride MoveStacksAcrossBank -- the same "right-click at the bank"
        -- move (UseContainerItem), staggered so each move gets its own free
        -- destination slot. Refresh decides when each shows.
        local function GearsetBankType()
            if IsModernBankOpen() then
                return Embolsao.BankViewMode == "WARBAND" and Enum.BankType.Account or Enum.BankType.Character
            end
        end

        frame.gearsetDepositButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.gearsetDepositButton:SetSize(100, 20)
        frame.gearsetDepositButton:SetText(L.GEARSET_MOVE_TO_BANK)
        frame.gearsetDepositButton:Hide()
        frame.gearsetDepositButton:SetScript("OnClick", function()
            -- The tab's own entries are exactly the set's items sitting in
            -- the bags (equipped/unavailable rows aren't entries).
            local locations = {}
            for _, entry in ipairs(win.GetFilteredEntries()) do
                for _, location in ipairs(entry.locations or {}) do
                    table.insert(locations, location)
                end
            end
            if #locations > 0 then
                MoveStacksAcrossBank(locations, GearsetBankType())
            end
        end)

        frame.gearsetWithdrawButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.gearsetWithdrawButton:SetSize(100, 20)
        frame.gearsetWithdrawButton:SetText(L.GEARSET_GET_FROM_BANK)
        frame.gearsetWithdrawButton:Hide()
        frame.gearsetWithdrawButton:SetScript("OnClick", function()
            local tab = Embolsao:GetFilters(config.domain):GetCustomTab(win.GetActiveTab())
            if not tab then return end

            local groups = Embolsao.Gearset:BuildGroups(tab, win.GetFilteredEntries(), win.GetFilteredEntries(true))
            Embolsao:ScanBank() -- what's in the bank right now, not whenever it was last scanned

            -- One stack per missing item: a piece of gear, not a pile.
            local locations = {}
            for _, missing in ipairs(groups.unavailable) do
                for _, bankEntry in pairs(Embolsao.BankVirtualInventory) do
                    if bankEntry.itemID == missing.itemID and bankEntry.locations and bankEntry.locations[1] then
                        table.insert(locations, bankEntry.locations[1])
                        break
                    end
                end
            end

            if #locations == 0 then
                UIErrorsFrame:AddMessage(L.GEARSET_NOTHING_IN_BANK, 1, 0.2, 0.2)
                return
            end
            MoveStacksAcrossBank(locations, GearsetBankType())
        end)

        -- Retail only: "deposit everything that belongs in the bank" (the
        -- reagents, or the Warband items), beside the search box. Only there
        -- while at a banker -- see win.UpdateDepositButton.
        if config.id == "Bags" and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
            and C_Bank and C_Bank.AutoDepositItemsIntoBank then
            -- The plain red panel button, like Blizzard's own on the bank.
            local deposit = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            deposit:SetHeight(22)
            deposit:SetPoint("LEFT", frame.eyeButton, "RIGHT", 6, 0)
            deposit:SetScript("OnClick", function(self)
                if self.bankType then
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
                    UI.DepositAllIntoBank(self.bankType)
                end
            end)
            deposit:Hide()
            frame.depositButton = deposit
        end

        -- Every client: look at the bank away from a banker, from the copy
        -- saved on the last visit. Takes the same spot as the deposit button
        -- (only there at a banker), so the two never meet.
        if config.id == "Bags" then
            local offline = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            offline:SetHeight(22)
            offline:SetPoint("LEFT", frame.eyeButton, "RIGHT", 6, 0)
            offline:SetText(L.OFFLINE_BANK)
            offline:SetWidth(offline:GetTextWidth() + 28)
            offline:SetScript("OnClick", function() UI.ToggleOfflineBank() end)
            offline:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L.OFFLINE_BANK)
                GameTooltip:AddLine(L.OFFLINE_BANK_DESC, 1, 1, 1, true)
                local view = UI.GetOfflineStartView()
                local snapshot = view and Embolsao:GetDisplayedBankSnapshot(view)
                if snapshot then
                    GameTooltip:AddLine(string.format(L.OFFLINE_SNAPSHOT_TIME,
                        date("%Y-%m-%d %H:%M", snapshot.time or 0)), 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end)
            offline:SetScript("OnLeave", GameTooltip_Hide)
            offline:Hide()
            frame.offlineButton = offline
        end

        if config.hasBankModeToggle then
            -- "Bank" / "Warband Bank" toggle -- switches which pool this
            -- window shows; the tabs, search box and sort options
            -- underneath stay exactly the same either way.
            frame.bankModeToggle = CreateFrame("Frame", nil, frame)
            frame.bankModeToggle:SetSize(1, 22)
            -- Right after the search box, where the bags pane's deposit
            -- button sits too, so both panes' toolbars read the same.
            frame.bankModeToggle:SetPoint("LEFT", frame.eyeButton, "RIGHT", 6, 0)
            frame.bankModeToggle:Hide()

            local function CreateBankModeButton(text)
                local btn = CreateFrame("Button", nil, frame.bankModeToggle, "UIPanelButtonTemplate")
                btn:SetSize(90, 22)
                btn:SetText(text)
                return btn
            end

            frame.bankModeToggle.personalButton = CreateBankModeButton(L.BANK_VIEW_PERSONAL)
            frame.bankModeToggle.personalButton:SetPoint("LEFT", 0, 0)
            frame.bankModeToggle.personalButton:SetScript("OnClick", function()
                Embolsao.BankViewMode = "PERSONAL"
                Embolsao:ScanBank()
                win.Refresh()
                win.UpdateBankModeToggle()
                bagsWindow.UpdateDepositButton()
            end)

            frame.bankModeToggle.warbandButton = CreateBankModeButton(L.BANK_VIEW_WARBAND)
            frame.bankModeToggle.warbandButton:SetPoint("LEFT", frame.bankModeToggle.personalButton, "RIGHT", 4, 0)
            frame.bankModeToggle.warbandButton:SetScript("OnClick", function()
                Embolsao.BankViewMode = "WARBAND"
                Embolsao:ScanBank()
                win.Refresh()
                win.UpdateBankModeToggle()
                bagsWindow.UpdateDepositButton()
            end)
        end

        if config.hasFooter then
            -- Money + XP strip, pinned to the bottom of the window itself
            -- (not the scroll areas) so it never moves as the item grid
            -- scrolls -- same fixed footer Blizzard's own bag window has.
            frame.footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            frame.footer:SetHeight(FOOTER_HEIGHT)
            frame.footer:SetPoint("TOPLEFT", frame.itemScrollFrame, "BOTTOMLEFT", 0, -FOOTER_GAP)
            -- Pinned to the pane rather than to the item area: that one's
            -- right edge moves with its scrollbar, the footer's shouldn't.
            frame.footer:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -10, footerClearance - FOOTER_GAP)
            frame.footer:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            frame.footer:SetBackdropColor(0, 0, 0, 0.35)
            frame.footer:SetBackdropBorderColor(1, 1, 1, 0.25)

            -- XP and money belong to the bags' footer. The bank's has neither: the
            -- bags pane -- with the player's money -- sits right next to it.
            if not config.hasBankPurchase then
                frame.footer.xpText = frame.footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                frame.footer.xpText:SetPoint("LEFT", 8, 0)

                frame.footer.moneyFrame = CreateFrame("Frame", nil, frame.footer, "SmallMoneyFrameTemplate")
                frame.footer.moneyFrame:SetPoint("RIGHT", -8, 0)
                SmallMoneyFrame_OnLoad(frame.footer.moneyFrame)
                MoneyFrame_SetType(frame.footer.moneyFrame, "PLAYER")

                -- The addon's own memory use, between the XP and the money --
                -- only while there's room for it (win.FitFooter).
                frame.footer.memText = frame.footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                frame.footer.memText:SetPoint("RIGHT", frame.footer.moneyFrame, "LEFT", -12, 0)
                frame.footer.memText:SetJustifyH("RIGHT")

                -- The XP text (now longer, with rested XP) stops short of the
                -- money instead of running underneath it on a narrow window.
                frame.footer.xpText:SetPoint("RIGHT", frame.footer.memText, "LEFT", -6, 0)
                frame.footer.xpText:SetJustifyH("LEFT")
                frame.footer.xpText:SetWordWrap(false)

                -- Memory is re-read every few seconds while the footer is on
                -- screen (OnUpdate only runs then). Reading it is not free --
                -- the game re-measures every addon -- hence not every frame.
                frame.footer.memElapsed = UI.MEMORY_REFRESH_SECONDS
                frame.footer:SetScript("OnUpdate", function(self, elapsed)
                    self.memElapsed = self.memElapsed + elapsed
                    if self.memElapsed >= UI.MEMORY_REFRESH_SECONDS then
                        self.memElapsed = 0
                        win.UpdateFooterMemory()
                    end
                end)
                frame.footer:SetScript("OnSizeChanged", function() win.FitFooter() end)
            end

            if config.hasBankPurchase then
                -- Bank footer: just the "Buy ..." button and what the next
                -- purchase costs. Shown only while there is something to buy
                -- (UpdateBankFooter).
                local buy = CreateFrame("Button", nil, frame.footer, "UIPanelButtonTemplate")
                buy:SetHeight(20)
                buy:SetPoint("LEFT", 6, 0)
                buy:SetScript("OnClick", function()
                    Embolsao:RequestBankPurchase()
                end)
                buy:SetScript("OnEnter", function(self)
                    local purchase = frame.footer.purchase
                    if not purchase then return end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(self:GetText())
                    if not purchase.canAfford then
                        GameTooltip:AddLine(L.BUY_BANK_NOT_ENOUGH_MONEY, 1, 0.2, 0.2)
                    end
                    GameTooltip:Show()
                end)
                buy:SetScript("OnLeave", GameTooltip_Hide)
                frame.footer.purchaseButton = buy

                local cost = CreateFrame("Frame", nil, frame.footer, "SmallMoneyFrameTemplate")
                cost:SetPoint("LEFT", buy, "RIGHT", 8, 0)
                SmallMoneyFrame_OnLoad(cost)
                MoneyFrame_SetType(cost, "STATIC")
                frame.footer.purchaseCost = cost

                buy:Hide()
                cost:Hide()

                -- Offline bank: when the copy on show was saved.
                local offlineText = frame.footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                offlineText:SetPoint("LEFT", 8, 0)
                offlineText:SetPoint("RIGHT", -8, 0)
                offlineText:SetJustifyH("LEFT")
                offlineText:SetWordWrap(false)
                offlineText:Hide()
                frame.footer.offlineText = offlineText
            end
        end

        return frame
    end

    -- Retail moved this one behind the GameRulesUtil namespace; Classic
    -- still has it as a bare global.
    local function IsAtEffectiveMaxLevel()
        if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
            return GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
        end
        return IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() or false
    end

    -- XP counts in thousands, 5230 -> "5.23k" (with the locale's own decimal
    -- mark), trailing zeros dropped (5400 -> "5.4k", 5000 -> "5k"); under a
    -- thousand they stay whole numbers.
    local function FormatThousands(value)
        if value < 1000 then return tostring(math.floor(value)) end
        local text = string.format("%.2f", value / 1000):gsub("%.?0+$", "")
        return (text:gsub("%.", _G.DECIMAL_SEPERATOR or ".")) .. "k"
    end

    -- Memory the addon uses, "3.2 MB" (or KB under a megabyte). Measured, not
    -- estimated: the game's own per-addon figure, which lags a little.
    local function FormatMemory(kb)
        if kb < 1024 then return string.format("%d KB", kb) end
        return (string.format("%.1f MB", kb / 1024):gsub("%.", _G.DECIMAL_SEPERATOR or "."))
    end

    -- The memory readout sits between XP and money and gives way first: it
    -- only shows if the XP text still fits beside it.
    function win.FitFooter()
        local footer = frame and frame.footer
        if not footer or not footer.memText then return end

        local room = footer:GetWidth() - 16 - footer.moneyFrame:GetWidth() - 12
            - footer.memText:GetStringWidth() - 6
        local showMemory = footer.memText:GetText() ~= nil and footer.xpText:GetStringWidth() <= room
        footer.memText:SetShown(showMemory)

        footer.xpText:ClearAllPoints()
        footer.xpText:SetPoint("LEFT", 8, 0)
        if showMemory then
            footer.xpText:SetPoint("RIGHT", footer.memText, "LEFT", -6, 0)
        else
            footer.xpText:SetPoint("RIGHT", footer.moneyFrame, "LEFT", -6, 0)
        end
    end

    function win.UpdateFooterMemory()
        local footer = frame and frame.footer
        if not footer or not footer.memText then return end

        local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
        local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
        if not get then return end
        if update then update() end

        footer.memText:SetText(string.format(L.FOOTER_MEMORY, FormatMemory(get("Embolsao") or 0)))
        win.FitFooter()
    end

    -- Not max level -> "5.23k / 12.40k (42%)"; at max level (or XP gain is
    -- otherwise disabled) there's no next-level total to show, so it goes blank.
    local function UpdateFooterXP()
        if not config.hasFooter or config.hasBankPurchase or not frame then return end
        if IsAtEffectiveMaxLevel() or IsXPUserDisabled() then
            frame.footer.xpText:SetText("")
            win.FitFooter()
            return
        end

        local currXP, maxXP = UnitXP("player"), UnitXPMax("player")
        local percent = maxXP > 0 and math.floor((currXP / maxXP) * 100 + 0.5) or 0
        local text = string.format("%s / %s (%d%%)", FormatThousands(currXP), FormatThousands(maxXP), percent)

        -- Rested XP, only when there is any: in Blizzard's own rested-bar blue,
        -- as an amount and as a share of the current level (it can exceed 100%
        -- -- rested XP can bank up to a level and a half).
        local rested = GetXPExhaustion and GetXPExhaustion()
        if rested and rested > 0 then
            local restedPercent = maxXP > 0 and math.floor((rested / maxXP) * 100 + 0.5) or 0
            text = text .. "  |cff4d9bff" .. string.format(L.RESTED_XP, FormatThousands(rested), restedPercent) .. "|r"
        end

        frame.footer.xpText:SetText(text)
        win.FitFooter()
    end
    win.UpdateFooterXP = UpdateFooterXP

    -- Shows/hides the Bank/Warband Bank toggle and reflects which one is
    -- currently selected (the active one disabled, reading as "you're here").
    -- The bank footer's "Buy ..." button: what the next purchase is (a bank
    -- tab for whichever bank is being viewed, or Classic's next bag slot) and
    -- what it costs; hidden when there's nothing to buy or no banker.
    function win.UpdateBankFooter()
        if not config.hasBankPurchase or not frame or not frame.footer or not frame.footer.purchaseButton then return end

        local footer = frame.footer

        -- The offline bank says how old the copy it shows is.
        if footer.offlineText then
            local snapshot = Embolsao.BankOffline and Embolsao:GetDisplayedBankSnapshot(Embolsao.BankViewMode) or nil
            footer.offlineText:SetShown(snapshot ~= nil)
            if snapshot then
                footer.offlineText:SetText(string.format(L.OFFLINE_SNAPSHOT_TIME,
                    date("%Y-%m-%d %H:%M", snapshot.time or 0)))
            end
        end

        local purchase = Embolsao:GetNextBankPurchase()
        footer.purchase = purchase
        footer.purchaseButton:SetShown(purchase ~= nil)
        footer.purchaseCost:SetShown(purchase ~= nil)
        if not purchase then return end

        local label = L.BUY_BANK_SLOT
        if purchase.kind == "tab" then
            label = (purchase.bankType == Enum.BankType.Account) and L.BUY_WARBAND_TAB or L.BUY_BANK_TAB
        end
        footer.purchaseButton:SetText(label)
        footer.purchaseButton:SetWidth(footer.purchaseButton:GetFontString():GetStringWidth() + 28)
        footer.purchaseButton:SetEnabled(purchase.canAfford)

        MoneyFrame_Update(footer.purchaseCost, purchase.cost)
        if SetMoneyFrameColorByFrame then
            SetMoneyFrameColorByFrame(footer.purchaseCost, purchase.canAfford and "white" or "red")
        end
    end

    function win.UpdateBankModeToggle()
        if not config.hasBankModeToggle or not frame or not frame.bankModeToggle then return end

        -- Switching between the personal and Warband banks changes what
        -- there is to buy, and this runs on every bank refresh anyway.
        win.UpdateBankFooter()

        local showToggle
        if Embolsao.BankOffline then
            -- Offline, only when both banks have been seen there is a choice.
            showToggle = Embolsao:GetDisplayedBankSnapshot("PERSONAL") ~= nil and Embolsao:GetDisplayedBankSnapshot("WARBAND") ~= nil
        else
            showToggle = Embolsao:CanUseWarbandBank()
        end
        frame.bankModeToggle:SetShown(showToggle)
        if not showToggle then return end

        local isWarband = Embolsao.BankViewMode == "WARBAND"
        frame.bankModeToggle.personalButton:SetEnabled(isWarband)
        frame.bankModeToggle.warbandButton:SetEnabled(not isWarband)
    end

    -- The "item actions" menu: what the MENU binding (Alt+Click by default)
    -- opens on an item. Entries only appear when they make sense for that
    -- item; the junk/recent/sell ones belong to the bags window alone (the
    -- bank has no such groups, and nothing is sold from there).
    local function ShowItemActionsMenu(btn)
        local itemID = btn.itemID
        if not itemID then return end

        local bagID, slot = btn:GetBagID(), btn:GetID()
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        local name = Embolsao.GetItemInfo(itemID) or tostring(itemID)
        local link = info and info.hyperlink
        local isBagsWindow = config.id == "Bags"
        local isRecent = btn.RecentDismiss ~= nil and btn.RecentDismiss:IsShown()

        -- The tab this window is showing, for "Hide on <tab>".
        local activeTabID = win.GetActiveTab()
        local tabData
        for _, tab in ipairs(frame.currentTabs or {}) do
            if tab.id == activeTabID then
                tabData = tab
                break
            end
        end

        MenuUtil.CreateContextMenu(btn, function(_, root)
            root:CreateTitle(name)

            -- A merged super-stack (several real stacks shown as one): open
            -- them individually in the popout -- the same action as the
            -- STACKS binding, and closing it again when it's already open.
            if btn.locations and #btn.locations > 1 then
                root:CreateButton(
                    win.stackPopoutItemID == itemID and L.MENU_STACKS_HIDE or L.MENU_STACKS_SHOW,
                    function() win.ToggleStackExpansion(itemID, btn) end
                )
            end

            if info and (info.stackCount or 1) > 1 and not info.isLocked then
                root:CreateButton(L.MENU_SPLIT, function() Bindings.StartSplit(btn) end)
            end

            if link then
                root:CreateButton(L.MENU_LINK, function()
                    if not ChatEdit_InsertLink(link) then
                        ChatFrame_OpenChat(link)
                    end
                end)
            end

            if tabData and Embolsao.TabEditor then
                root:CreateButton(string.format(L.MENU_HIDE_ON_TAB, tabData.name), function()
                    Embolsao.TabEditor:ConfirmHideItemOnTab(itemID, tabData, config.domain)
                end)
            end

            if isBagsWindow then
                -- Grey items are junk by quality and stay that way; anything
                -- else can be put on (or taken off) the player's own junk list.
                if info and info.quality ~= 0 then
                    local junkList = Embolsao.db.junkItemIDs
                    local function ToggleJunk()
                        junkList[itemID] = (not junkList[itemID]) or nil
                        Embolsao:ScanBags()
                        UI:Refresh()
                    end
                    root:CreateButton(junkList[itemID] and L.MENU_UNMARK_JUNK or L.MENU_MARK_JUNK, ToggleJunk)
                end

                if isRecent then
                    root:CreateButton(L.MENU_DISMISS_RECENT, function()
                        Embolsao:DismissRecentItem(itemID, btn.locations)
                        Embolsao:ScanBags()
                        UI:Refresh()
                    end)
                end

                if IsAtMerchant() and info and not info.hasNoValue then
                    root:CreateButton(L.MENU_SELL, function()
                        C_Container.UseContainerItem(bagID, slot)
                    end)
                end
            end
        end)
    end

    -- Bare "ItemButton" is Blizzard's own intrinsic widget type (icon +
    -- count + quality border). We don't pull in
    -- ContainerFrameItemButtonTemplate itself, since that hard-requires a
    -- real container-frame parent. Shared between the main grid and the
    -- stack-expansion popout below: both are real ItemButtons bound to a
    -- real (bagID, slot) via SetBagID/SetID.
    local function SetupItemButtonInteractions(btn)
        btn.UpgradeIcon = CreateUpgradeIcon(btn)
        btn.IconQuestTexture = CreateQuestTexture(btn)
        btn.JunkIcon = CreateJunkIcon(btn)
        btn.RecentDismiss = CreateRecentDismissButton(btn)
        btn.GearsetEquippedCheck = CreateGearsetEquippedCheck(btn)
        btn.GearsetUnavailableIcon = CreateGearsetUnavailableIcon(btn)

        -- Flagged so the modifier-key refresh at the bottom of the file knows
        -- this tooltip is ours and can be rebuilt when Ctrl/Shift/Alt changes.
        btn.isEmbolsaoItemButton = true
        btn:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            -- Bag slot first: only that tooltip carries the enchant, gems and
            -- random suffix of this exact item. Without a live slot (virtual
            -- gearset rows, offline bank) the saved link is the next best,
            -- and the bare item ID the last resort.
            local bagID, slotID = self:GetBagID(), self:GetID()
            if not self.embolsaoVirtual and not self.embolsaoReadOnly and bagID and slotID and slotID > 0 then
                GameTooltip:SetBagItem(bagID, slotID)
            elseif self.hyperlink then
                GameTooltip:SetHyperlink(self.hyperlink)
            else
                GameTooltip:SetItemByID(self.itemID)
            end
            Bindings.AddBindingHints(self)
            GameTooltip:Show()

            -- At a vendor, the pointer turns into the bag that says "click to
            -- sell", as over Blizzard's own bag slots (which do it every frame
            -- from their OnUpdate).
            if not win.IsReadOnly() and not SpellIsTargeting()
                and _G.MerchantFrame and _G.MerchantFrame:IsShown()
                and (_G.MerchantFrame.selectedTab or 1) == 1 then
                local showSellCursor = (C_Container and C_Container.ShowContainerSellCursor) or _G.ShowContainerSellCursor
                if showSellCursor then
                    showSellCursor(self:GetBagID(), self:GetID())
                end
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip_Hide()
            if not SpellIsTargeting() then
                ResetCursor()
            end
        end)
        btn:SetScript("OnHide", function(self)
            if self.hasStackSplit == 1 then
                StackSplitFrame:Hide()
            end
        end)

        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(self, mouseButton)
            if not self.itemID then return end
            if win.IsReadOnly() then return end
            -- A Gearset tab's Equipped/Unavailable rows (Layout.lua) aren't
            -- backed by any real bag slot -- self:GetBagID()/GetID() would
            -- resolve to nil/0, and every branch below eventually calls a
            -- real C_Container function with that, which is exactly the
            -- kind of nonsense-argument call that's worth bailing out of
            -- before it happens rather than trusting each branch to notice.
            if self.embolsaoVirtual then return end
            local bagID, slot = self:GetBagID(), self:GetID()

            -- A spell waiting for its item (Disenchant...): the click aims it,
            -- as on Blizzard's own bag buttons. The overlay normally handles
            -- this before we get here; this covers buttons without one.
            if mouseButton == "LeftButton" and IsSpellTargetingItem() then
                C_Container.UseContainerItem(bagID, slot)
                return
            end

            -- Modifier + left-click runs whichever action the player bound to
            -- that exact combo in the Bindings window (defaults: Ctrl = show a
            -- merged stack's real stacks in a popout, Shift = split, Alt = the
            -- item actions menu). Read from the raw key state, so Blizzard's
            -- own Modified Click Actions settings can't shadow it.
            if mouseButton == "LeftButton" then
                local action = Bindings.ActionForCurrentClick()
                if action == "STACKS" then
                    if self.locations and #self.locations > 1 then
                        win.ToggleStackExpansion(self.itemID, self)
                    end
                    return
                elseif action and not CursorHasItem() then
                    if action == "SPLIT" then
                        Bindings.StartSplit(self)
                    elseif action == "MENU" then
                        ShowItemActionsMenu(self)
                    end
                    return
                end
            end

            -- Any OTHER modified click is something we don't replicate.
            -- Bail instead of guessing.
            if Bindings.CurrentModifierCombo() ~= "" then
                return
            end

            if mouseButton == "RightButton" then
                -- Normally already done by the secure overlay (see
                -- CreateUseOverlay); only the cases it can't express get here.
                if Embolsao.AtBank then
                    -- Deposit/withdraw. The secure "use item" overlay does
                    -- exactly one stack, so it's switched off at a banker (see
                    -- UpdateUseOverlay) and this moves every stack the button
                    -- stands for. The modern bank must also be told which bank
                    -- (personal or Warband) the click is about.
                    local bankType
                    if IsModernBankOpen() then
                        bankType = Embolsao.BankViewMode == "WARBAND"
                            and Enum.BankType.Account or Enum.BankType.Character
                    end
                    if self.locations and #self.locations > 0 then
                        MoveStacksAcrossBank(self.locations, bankType)
                    else
                        MoveStacksAcrossBank({ { bagID = bagID, slot = slot } }, bankType)
                    end
                elseif IsSendingMail() then
                    -- A merged super-stack is several real stacks: attach all
                    -- of them (up to what the mail has room for), not just
                    -- the first one the secure overlay handles.
                    if self.locations and #self.locations > 0 then
                        AttachStacksToMail(self.locations, self.useOverlayAction ~= nil)
                    elseif not self.useOverlayAction then
                        C_Container.UseContainerItem(bagID, slot)
                    end
                elseif not self.useOverlayAction then
                    C_Container.UseContainerItem(bagID, slot)
                end
            else
                C_Container.PickupContainerItem(bagID, slot)
            end
        end)

        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function(self)
            if not self.itemID or win.IsReadOnly() or self.embolsaoVirtual then return end
            C_Container.PickupContainerItem(self:GetBagID(), self:GetID())
        end)
        btn:SetScript("OnReceiveDrag", function(self)
            if not self.itemID or win.IsReadOnly() or self.embolsaoVirtual then return end
            C_Container.PickupContainerItem(self:GetBagID(), self:GetID())
        end)
    end

    -- Each button acts on entry.locations[1] -- the first real (bagID, slot)
    -- backing that merged stack. Positioning is NOT done here -- it happens
    -- every Refresh (even for reused buttons), since the column count
    -- depends on the window's current width.
    local function GetOrCreateItemButton(index)
        local btn = itemButtons[index]
        if btn then return btn end

        btn = CreateFrame("ItemButton", nil, frame.itemContainer)
        SetupItemButtonInteractions(btn)

        itemButtons[index] = btn
        return btn
    end

    -- The merged/virtual view has no visual "empty square" of its own (one
    -- button per itemID, not per physical slot), so there's normally
    -- nowhere to drop a picked-up or split-off item to start a new stack.
    -- One pooled button per GetEmptySlotGroups() entry.
    local function GetOrCreateEmptySlotButton(index)
        local btn = emptySlotButtons[index]
        if btn then return btn end

        btn = CreateFrame("ItemButton", nil, frame.itemContainer)
        btn.minDisplayCount = 0

        local function PlaceCursorItem()
            if win.IsReadOnly() then return end
            local slotInfo = btn.group and btn.group.slots[1]
            if not slotInfo then return end
            C_Container.PickupContainerItem(slotInfo.bagID, slotInfo.slot)
        end

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local bagName
            if self.group and self.group.bagID then
                local familyKey = self.group.family and BAG_FAMILY_LABEL_KEYS[self.group.family]
                bagName = (familyKey and L[familyKey]) or C_Container.GetBagName(self.group.bagID)
            end
            GameTooltip:SetText(bagName and string.format(L.EMPTY_SLOT_TITLE_BAG, bagName) or L.EMPTY_SLOT_TITLE)
            GameTooltip:AddLine(L.EMPTY_SLOT_DESC, 1, 1, 1, true)
            if self.group and not win.IsReadOnly() then
                local hint = L.EMPTY_SLOT_OPEN_ALL_BAGS_HINT
                if self.group.bagID then
                    -- bagIDs on a special group means several bags of the
                    -- same kind were merged into this one button.
                    hint = self.group.bagIDs and L.EMPTY_SLOT_OPEN_BAGS_HINT or L.EMPTY_SLOT_OPEN_BAG_HINT
                end
                GameTooltip:AddLine(hint, 1, 1, 1, true)
            end
            GameTooltip:Show()

            if CursorHasItem() then
                self.IconBorder:Show()
                self.IconBorder:SetVertexColor(1, 0.82, 0, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip_Hide()
            self.IconBorder:Hide()
        end)

        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(self, mouseButton)
            if win.IsReadOnly() then return end
            -- Nobody left-clicks an empty slot for any other reason, so both
            -- buttons open the bag -- unless an item is held, in which case
            -- a left click drops it here.
            if mouseButton == "LeftButton" and CursorHasItem() then
                PlaceCursorItem()
                return
            end
            if self.group then
                -- A lone special bag maps to one real bagID and opens
                -- just that one; the shared "general" bucket, and any
                -- special group merging several bags of one kind, have
                -- a list of bagIDs to open instead.
                win.OpenNativeBags(self.group.bagIDs or self.group.bagID)
            end
        end)
        btn:SetScript("OnReceiveDrag", PlaceCursorItem)

        emptySlotButtons[index] = btn
        return btn
    end

    local function GetOrCreateHeaderRow(index)
        local header = headerRows[index]
        if header then return header end

        header = CreateFrame("Frame", nil, frame.itemContainer)
        header:SetHeight(HEADER_ROW_HEIGHT)
        header:EnableMouse(true)

        header.toggleIcon = header:CreateTexture(nil, "ARTWORK")
        header.toggleIcon:SetSize(12, 12)
        header.toggleIcon:SetPoint("LEFT")

        header.text = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        header.text:SetPoint("LEFT", header.toggleIcon, "RIGHT", 4, 0)

        header.line = header:CreateTexture(nil, "ARTWORK")
        header.line:SetHeight(1)
        header.line:SetColorTexture(1, 1, 1, 0.25)
        header.line:SetPoint("LEFT", header.text, "RIGHT", 6, 0)
        header.line:SetPoint("RIGHT")

        -- Action button at the right end of the two pinned groups' headers
        -- (see Refresh, which picks its icon per header key):
        --   Recent -> remove everything listed under it from Recent
        --   Junk   -> sell everything listed under it (only at a vendor)
        -- Both are scoped to what this window is showing -- the active tab
        -- and search -- exactly the items visible in the group.
        local action = CreateFrame("Button", nil, header)
        action:SetSize(14, 14)
        action:SetPoint("RIGHT", 0, 0)
        action:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if header.key == "recentitems" then
                GameTooltip:SetText(L.DISMISS_ALL_RECENT_HINT)
            elseif header.key == "junkitems" then
                if IsAtMerchant() then
                    GameTooltip:SetText(L.SELL_JUNK_HINT)
                    local total = 0
                    for _, entry in ipairs(win.GetFilteredEntries(true)) do
                        if entry.isJunk then
                            local sellPrice = select(11, Embolsao.GetItemInfo(entry.itemID))
                            total = total + (sellPrice or 0) * entry.count
                        end
                    end
                    if total > 0 then
                        GameTooltip:AddLine(Embolsao.GetCoinTextureString(total), 1, 1, 1)
                    end
                else
                    GameTooltip:SetText(L.SELL_JUNK_NO_VENDOR)
                end
            elseif header.key == "gearsetpreviousequipped" then
                GameTooltip:SetText(L.GEARSET_DISMISS_PREVIOUS_HINT)
            end
            GameTooltip:Show()
        end)
        action:SetScript("OnLeave", GameTooltip_Hide)
        action:SetScript("OnClick", function()
            if header.key == "recentitems" then
                for _, entry in ipairs(win.GetFilteredEntries(true)) do
                    if entry.isRecent then
                        Embolsao:DismissRecentItem(entry.itemID, entry.locations)
                    end
                end
                Embolsao:ScanBags()
                UI:Refresh()
            elseif header.key == "junkitems" then
                SellJunkEntries(win.GetFilteredEntries(true))
            elseif header.key == "gearsetpreviousequipped" then
                local tab = Embolsao:GetFilters(config.domain):GetCustomTab(win.GetActiveTab())
                if tab then
                    Embolsao.Gearset:DismissPreviousEquipped(tab)
                    UI:Refresh()
                end
            end
        end)
        action:Hide()
        header.actionButton = action

        header:SetScript("OnMouseUp", function(self)
            if not self.key then return end
            local collapsed = Layout.GetCollapsedHeaders(win.StateID(win.GetActiveTab()))
            if collapsed[self.key] then
                collapsed[self.key] = nil
            else
                collapsed[self.key] = true
            end
            win.Refresh()
        end)

        headerRows[index] = header
        return header
    end

    --------------------------------------------------------------------
    -- Stack expansion popout: Ctrl+Click a merged super-stack to see and
    -- interact with the real stacks backing it individually.
    --------------------------------------------------------------------

    local STACK_POPOUT_COLUMNS = 6
    local STACK_POPOUT_PADDING = 10

    local function GetOrCreateStackPopoutButton(index)
        local btn = stackPopoutButtons[index]
        if btn then return btn end

        btn = CreateFrame("ItemButton", nil, stackPopout)
        local col = (index - 1) % STACK_POPOUT_COLUMNS
        local row = math.floor((index - 1) / STACK_POPOUT_COLUMNS)
        btn:SetPoint("TOPLEFT", STACK_POPOUT_PADDING + col * (ITEM_SIZE + ITEM_PADDING),
            -(STACK_POPOUT_PADDING + 20) - row * (ITEM_SIZE + ITEM_PADDING))
        SetupItemButtonInteractions(btn)

        stackPopoutButtons[index] = btn
        return btn
    end

    local function EnsureStackPopout()
        if stackPopout then return stackPopout end

        stackPopout = CreateFrame("Frame", "Embolsao" .. config.id .. "StackPopoutFrame", UIParent, "BackdropTemplate")
        stackPopout:SetFrameStrata("DIALOG")
        stackPopout:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        stackPopout:SetBackdropColor(0, 0, 0, 0.95)
        stackPopout:EnableMouse(true)
        stackPopout:Hide()
        tinsert(UISpecialFrames, "Embolsao" .. config.id .. "StackPopoutFrame")

        local close = CreateFrame("Button", nil, stackPopout, "UIPanelCloseButtonDefaultAnchors")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() win.ToggleStackExpansion(nil) end)

        return stackPopout
    end

    -- Re-resolves the currently-expanded itemID against the live inventory
    -- (called on open and again on every Refresh while it's open) and lays
    -- out one real button per real (bagID, slot) location. Closes itself
    -- automatically once the item no longer resolves to a super-stack.
    local function RefreshStackPopout()
        local entry = config.GetInventory()[win.stackPopoutItemID]
        if not entry or not entry.locations or #entry.locations < 2 then
            win.ToggleStackExpansion(nil)
            return
        end

        local popout = EnsureStackPopout()
        local numLocations = #entry.locations
        local columns = math.min(STACK_POPOUT_COLUMNS, numLocations)
        local rows = math.ceil(numLocations / STACK_POPOUT_COLUMNS)

        for i, location in ipairs(entry.locations) do
            local btn = GetOrCreateStackPopoutButton(i)
            -- Each real stack's own count/quality, read fresh per slot --
            -- NOT the merged entry's aggregate count.
            local info = C_Container.GetContainerItemInfo(location.bagID, location.slot)
            btn.itemID = entry.itemID
            btn.hyperlink = info and info.hyperlink
            btn.locations = nil -- a real single stack, not itself expandable
            btn:SetBagID(location.bagID)
            btn:SetID(location.slot)
            UpdateUseOverlay(btn, location.bagID, location.slot)
            if info then
                SetItemButtonTexture(btn, info.iconFileID)
                SetItemButtonCount(btn, info.stackCount)
                SetItemButtonQuality(btn, info.quality, entry.itemID)
                ShowQualityBorder(btn, info.quality)
            end
            UpdateQuestTexture(btn, entry)
            btn.JunkIcon:SetShown(entry.isJunk == true)
            UpdatePawnUpgradeIcon(btn, info and info.hyperlink)
            btn:Show()
        end

        for i = numLocations + 1, #stackPopoutButtons do
            stackPopoutButtons[i].itemID = nil
            stackPopoutButtons[i]:Hide()
        end

        popout:SetSize(
            columns * (ITEM_SIZE + ITEM_PADDING) + STACK_POPOUT_PADDING * 2,
            rows * (ITEM_SIZE + ITEM_PADDING) + STACK_POPOUT_PADDING * 2 + 20
        )
    end

    -- Pass itemID = nil (or omit it) to close. Ctrl+Clicking the
    -- already-expanded stack closes it (toggle); Ctrl+Clicking a different
    -- one switches straight to that one.
    function win.ToggleStackExpansion(itemID, anchorButton)
        if not itemID or itemID == win.stackPopoutItemID then
            win.stackPopoutItemID = nil
            if stackPopout then stackPopout:Hide() end
            return
        end

        win.stackPopoutItemID = itemID
        local popout = EnsureStackPopout()
        if anchorButton then
            popout:ClearAllPoints()
            popout:SetPoint("TOP", anchorButton, "BOTTOM", 0, -6)
        end
        popout:Show()
        RefreshStackPopout()
        win.ApplyModifierDimming(Bindings.ActionForCurrentClick())
    end

    -- While the modifier bound to STACKS or SPLIT is held, the items that
    -- action can't do anything with fade out, so what the click will work on
    -- stands out at a glance. actionID is what Bindings.ActionForCurrentClick() says
    -- (nil = no bound modifier held: everything back to full strength). Menu
    -- applies to every item, so it fades nothing. The popout's own stacks
    -- never fade for STACKS -- they're the result of that very action.
    local DIMMED_ITEM_ALPHA = 0.3
    function win.ApplyModifierDimming(actionID)
        local function Apply(btn, isPopout)
            local dim = false
            if actionID and btn:IsShown() and btn.itemID and not win.IsReadOnly()
                and not (isPopout and actionID == "STACKS") then
                dim = not Bindings.BindingApplies(actionID, btn)
            end
            btn:SetAlpha(dim and DIMMED_ITEM_ALPHA or 1)
        end
        for _, btn in pairs(itemButtons) do Apply(btn, false) end
        for _, btn in pairs(stackPopoutButtons) do Apply(btn, true) end
    end

    function win.RefreshPawnIcons()
        for _, btn in pairs(itemButtons) do
            if btn.itemID then UpdatePawnUpgradeIcon(btn, btn.pawnHyperlink) end
        end
        for _, btn in pairs(stackPopoutButtons) do
            if btn.itemID then UpdatePawnUpgradeIcon(btn, btn.pawnHyperlink) end
        end
    end

    function win.BuildTabs()
        if not frame then return end
        for _, btn in ipairs(tabButtons) do
            btn:Hide()
        end
        wipe(tabButtons)

        -- Only visible tabs get a clickable button; hidden ones still exist
        -- for Preferences' tab manager and for GetFilteredEntries' lookup.
        frame.currentTabs = Embolsao:GetFilters(config.domain):GetVisibleTabs()
        for index, tabData in ipairs(frame.currentTabs) do
            tabButtons[index] = CreateTabButton(index, tabData)
        end

        if not frame.newTabButton then
            frame.newTabButton = CreateNewTabButton()
        end
        local tabCount = #frame.currentTabs
        frame.newTabButton:SetPoint("TOP", 0, -tabCount * (TAB_ICON_SIZE + TAB_PADDING))
        frame.newTabButton:Show()

        frame.tabColumn:SetHeight((tabCount + 1) * (TAB_ICON_SIZE + TAB_PADDING))
    end

    -- Whether the deposit-everything button is on show: only at a banker, and
    -- only where the client has one (see GetDepositBankType). Follows the bank
    -- pane's Personal / Warband switch.
    function win.UpdateDepositButton()
        local button = frame and frame.depositButton
        if not button then return end
        local bankType = UI.GetDepositBankType()
        button.bankType = bankType
        if bankType then
            button:SetText(UI.DepositLabel(bankType))
            button:SetWidth(button:GetTextWidth() + 28)
        end
        button:SetShown(bankType ~= nil)
    end

    -- The "Offline Bank" button (bags pane): there while away from a banker,
    -- with something saved to look at, and the bank part enabled at all.
    function win.UpdateOfflineButton()
        local button = frame and frame.offlineButton
        if not button then return end
        local show = not Embolsao.AtBank and Embolsao.db.mergeBankStorage and not Embolsao.db.disabled
            and Embolsao.db.offlineBank ~= false and UI.GetOfflineStartView() ~= nil
        button:SetShown(show and true or false)
        if Embolsao.BankOffline then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end

    -- Opens the pane the way the bags key does (the window itself was shown by
    -- the secure toggle -- see UI:SetupSecureToggle), doing what the takeover of
    -- a native bag frame does apart from the native frames, of which there are
    -- none here. (Defined here, after EnsureFrame: a local function is only
    -- visible to what comes after it.)
    function win.OpenDirect()
        EnsureFrame()
        if not frame.currentTabs then
            win.BuildTabs()
        end
        if config.applyDefaultTab and Embolsao.db.defaultTab and Embolsao.db.defaultTab ~= "LAST" then
            config.SetActiveTab(Embolsao.db.defaultTab)
        end
        if not ShowPane() then return end
        if config.OnShown then config.OnShown() end
        config.Rescan()
        win.Refresh()
        win.UpdateFooterXP()
        win.UpdateBankModeToggle()
    end

    -- Shows the bank pane on the saved copy (ToggleOfflineBank has already
    -- filled the bank's tables from it).
    function win.ShowOffline()
        EnsureFrame()
        if not frame.currentTabs then
            win.BuildTabs()
        end
        if not ShowPane() then return end
        win.Refresh()
        win.UpdateBankModeToggle()
    end

    -- The scrollbars only take room while their list overflows. Each pair
    -- below switches its geometry between "bar" and "no bar": the tab panel
    -- itself narrows (the item area, anchored to it, takes the room), the item
    -- area's right edge moves. Refresh decides when.
    function win.SetTabBar(needed)
        if frame.tabBarShown == needed then return end
        frame.tabBarShown = needed
        local reserved = needed and SCROLLBAR_CLEARANCE or 0
        frame.tabPanel:SetWidth(TAB_ICON_SIZE + TAB_GLOW_MARGIN * 2 + TAB_PANEL_PADDING * 2 + reserved)
        frame.tabScrollFrame:ClearAllPoints()
        frame.tabScrollFrame:SetPoint("TOPLEFT", TAB_PANEL_PADDING, -TAB_PANEL_PADDING)
        frame.tabScrollFrame:SetPoint("BOTTOMRIGHT", -TAB_PANEL_PADDING - reserved, TAB_PANEL_PADDING)
    end

    function win.SetItemBar(needed)
        -- frame.gearsetBarShown (set in Refresh) also drives the TOPLEFT
        -- offset here, not just `needed` -- both have to be in the change
        -- check, or switching to/from a Gearset tab without also changing
        -- the scrollbar state would leave this call short-circuited and
        -- the reserved row wouldn't actually appear/disappear.
        local gearsetBar = frame.gearsetBarShown or false
        if frame.itemBarShown == needed and frame.itemBarShownGearset == gearsetBar then return end
        frame.itemBarShown = needed
        frame.itemBarShownGearset = gearsetBar
        frame.itemScrollFrame:ClearAllPoints()
        frame.itemScrollFrame:SetPoint("TOPLEFT", frame.tabPanel, "TOPRIGHT", TAB_TO_ITEMS_GAP,
            gearsetBar and -GEARSET_BAR_HEIGHT or 0)
        frame.itemScrollFrame:SetPoint("BOTTOMRIGHT", -10 - (needed and SCROLLBAR_CLEARANCE or 0), win.itemBottomInset)
    end

    function win.UpdateSelectedTab()
        local activeTab = config.GetActiveTab()
        for index, tabData in ipairs(frame.currentTabs or {}) do
            local btn = tabButtons[index]
            local isActive = tabData.id == activeTab
            btn.icon:SetDesaturated(not isActive)
            btn.icon:SetAlpha(isActive and 1 or 0.55)
            btn.selectedBg:SetShown(isActive)
        end
    end

    -- ignoreTab: skip the active tab's own filter (search still applies) --
    -- the set the pinned Recent/Junk groups are built from, which are the
    -- same on every tab.
    function win.GetFilteredEntries(ignoreTab)
        local tabs = frame.currentTabs or Embolsao:GetFilters(config.domain):GetAllTabs()
        local activeTab = config.GetActiveTab()

        local activeFilter
        for _, tab in ipairs(tabs) do
            if tab.id == activeTab then
                activeFilter = tab
                break
            end
        end
        activeFilter = activeFilter or tabs[1]

        local search = (win.searchText or ""):lower()

        -- Items of a gearset flagged "Hide from bags" show only on gearset
        -- tabs, whatever any other tab's filters say.
        local gearsetHidden = activeFilter.tabType ~= "gearset"
            and not Embolsao.ShowHiddenItems
            and Embolsao:GetFilters(config.domain):GetGearsetHiddenItemIDs() or nil

        local results = {}
        for _, entry in pairs(config.GetInventory()) do
            if not (gearsetHidden and gearsetHidden[entry.itemID])
                and (ignoreTab or activeFilter.predicate(entry)) then
                local matchesSearch = true
                if search ~= "" then
                    local name = Embolsao.GetItemInfo(entry.itemID)
                    matchesSearch = name ~= nil and name:lower():find(search, 1, true) ~= nil
                end
                if matchesSearch then
                    table.insert(results, entry)
                end
            end
        end
        local stateID = win.StateID(activeFilter.id)
        local sortMode, sortAscending = Layout.GetTabSort(stateID)
        local groupByClass, groupBySubClass = Layout.GetTabGrouping(stateID)
        table.sort(results, Layout.MakeGroupedComparator(groupByClass, groupBySubClass, sortMode, sortAscending))
        return results
    end

    function win.Refresh()
        if not frame or not frame:IsShown() then return end
        -- Laying the grid out moves buttons the secure overlays are anchored
        -- to, which the game forbids in combat: it waits for combat to end
        -- (PLAYER_REGEN_ENABLED refreshes everything). Until an overlay
        -- exists (a window first opened in combat) there is nothing to protect.
        if InCombatLockdown() then
            for _, button in pairs(itemButtons) do
                if button.UseOverlay then
                    win.refreshPending = true
                    return
                end
            end
        end
        if not frame.currentTabs then
            win.BuildTabs()
        end
        win.UpdateSelectedTab()

        local entries = win.GetFilteredEntries()
        local activeTabID = win.GetActiveTab()
        local activeTabName, activeTabType
        for _, tab in ipairs(frame.currentTabs or {}) do
            if tab.id == activeTabID then
                activeTabName = tab.name
                activeTabType = tab.tabType
                break
            end
        end
        local activeHiddenItemIDs = (not Embolsao.ShowHiddenItems)
            and Embolsao:GetFilters(config.domain):GetTabHiddenItemIDs(activeTabID) or nil
        local pinnedSource = win.GetFilteredEntries(true)
        local gearsetGroups
        local activeGearsetTab
        if activeTabType == "gearset" then
            activeGearsetTab = Embolsao:GetFilters(config.domain):GetCustomTab(activeTabID)
            if activeGearsetTab then
                gearsetGroups = Embolsao.Gearset:BuildGroups(activeGearsetTab, entries, pinnedSource)
            end
        end
        -- The Gearset action row: each button only when it has something to
        -- do -- Equip/Unequip when part of the set is in the bags or all of
        -- it is worn (none of it available -> nothing to equip), Move to
        -- Bank when part of it is in the bags, Get from Bank when part of it
        -- is missing. The row's reserved strip above the item grid exists
        -- only while at least one of them shows.
        local showEquip, showDeposit, showWithdraw = false, false, false
        if activeGearsetTab then
            showEquip = Embolsao.Gearset:CanToggle(activeGearsetTab)
            local atBank = Embolsao.AtBank and config.id == "Bags"
            showDeposit = atBank and #entries > 0
            showWithdraw = atBank and gearsetGroups ~= nil and #gearsetGroups.unavailable > 0
        end
        frame.gearsetBarShown = (showEquip or showDeposit or showWithdraw) and true or false
        if frame.gearsetActionButton then
            frame.gearsetActionButton:SetShown(showEquip)
            if showEquip then
                frame.gearsetActionButton:SetText(Embolsao.Gearset:IsEquipped(activeGearsetTab)
                    and L.GEARSET_UNEQUIP or L.GEARSET_EQUIP)
            end
            frame.gearsetDepositButton:SetShown(showDeposit and true or false)
            frame.gearsetWithdrawButton:SetShown(showWithdraw and true or false)
            win.LayoutGearsetButtons()
        end
        -- Another character's worn gear (alt viewer), through the search box.
        local viewedEquipment
        if config.id == "Bags" and Embolsao.ViewChar and Embolsao.AltEquipment then
            local search = (win.searchText or ""):lower()
            viewedEquipment = {}
            for _, entry in ipairs(Embolsao.AltEquipment) do
                local name = search ~= "" and Embolsao.GetItemInfo(entry.itemID) or nil
                if search == "" or (name and name:lower():find(search, 1, true)) then
                    table.insert(viewedEquipment, entry)
                end
            end
        end
        local rows = Layout.BuildLayoutRows(entries, pinnedSource, config.GetEmptySlotGroups(), win.StateID(activeTabID), activeTabName, activeHiddenItemIDs, gearsetGroups, viewedEquipment)

        local readOnly = win.IsReadOnly()
        frame.paneLabel:SetText(config.paneLabel())
        frame.eyeButton.strike:SetShown(not Embolsao.ShowHiddenItems)
        local eyeShade = Embolsao.ShowHiddenItems and 1 or 0.6
        frame.eyeButton.icon:SetVertexColor(eyeShade, eyeShade, eyeShade)

        local sortMode, sortAscending = Layout.GetTabSort(win.StateID(activeTabID))
        for _, option in ipairs(Layout.SORT_MODES) do
            if option.id == sortMode then
                frame.sortLabel:SetText(string.format(L.SORTED_BY_STATUS, option.label,
                    sortAscending and L.SORT_ASCENDING or L.SORT_DESCENDING))
                break
            end
        end

        -- Scrollbars take room only when their list overflows. The tab
        -- column's is simple; the item grid's has a catch -- the bar narrows
        -- the grid, which can mean fewer columns and so more rows -- so it's
        -- judged at the wider (bar-less) width: if the content doesn't fit
        -- even there, it needs the bar.
        win.SetTabBar(frame.tabColumn:GetHeight() > frame.tabScrollFrame:GetHeight())

        -- Column count tracks the item area's width, so widening the window
        -- adds columns instead of just revealing empty space. The width is
        -- worked out from the pane rather than read back from the scroll
        -- frame, whose own size is what's about to change.
        local cell = ITEM_SIZE + ITEM_PADDING
        local available = frame:GetWidth() - 10 - frame.tabPanel:GetWidth() - TAB_TO_ITEMS_GAP - 10
        local wideColumns = math.max(ITEMS_PER_ROW, math.floor(available / cell))
        local needItemBar = Layout.MeasureLayoutHeight(rows, wideColumns) > frame.itemScrollFrame:GetHeight()
        win.SetItemBar(needItemBar)
        local itemsPerRow = needItemBar
            and math.max(ITEMS_PER_ROW, math.floor((available - SCROLLBAR_CLEARANCE) / cell))
            or wideColumns
        frame.itemContainer:SetWidth(itemsPerRow * cell)

        -- Headers and item cells have different row heights, so position is
        -- tracked as a running pixel offset rather than a uniform row index.
        local yOffset, col = 0, 0
        local itemIndex, headerIndex, emptySlotIndex = 0, 0, 0

        for _, row in ipairs(rows) do
            if row.kind == "gap" then
                if col > 0 then
                    yOffset = yOffset + (ITEM_SIZE + ITEM_PADDING)
                    col = 0
                end
                yOffset = yOffset + GROUP_GAP_HEIGHT
            elseif row.kind == "header" then
                if col > 0 then
                    yOffset = yOffset + (ITEM_SIZE + ITEM_PADDING)
                    col = 0
                end

                headerIndex = headerIndex + 1
                local header = GetOrCreateHeaderRow(headerIndex)
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", row.level * HEADER_INDENT_STEP, -yOffset)
                header:SetPoint("TOPRIGHT", 0, -yOffset)
                header.text:SetFontObject(row.level == 0 and GameFontNormalSmall or GameFontDisableSmall)
                header.text:SetText(row.text)
                header.key = row.key
                -- Only the Recent and Junk headers carry an action button;
                -- the rule stops short of it there, and runs edge to edge on
                -- every other header.
                local actionIcon
                if row.key == "recentitems" or row.key == "gearsetpreviousequipped" then
                    actionIcon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
                elseif row.key == "junkitems" then
                    actionIcon = "Interface\\Icons\\INV_Misc_Coin_01"
                end
                local action = header.actionButton
                header.line:ClearAllPoints()
                header.line:SetPoint("LEFT", header.text, "RIGHT", 6, 0)
                if actionIcon then
                    action:SetNormalTexture(actionIcon)
                    action:SetHighlightTexture(actionIcon, "ADD")
                    -- Selling only works with a vendor window open; grey the
                    -- coin out otherwise so it reads as unavailable.
                    action:GetNormalTexture():SetDesaturated(row.key == "junkitems" and not IsAtMerchant())
                    action:Show()
                    header.line:SetPoint("RIGHT", action, "LEFT", -4, 0)
                else
                    action:Hide()
                    header.line:SetPoint("RIGHT")
                end
                header.toggleIcon:SetTexture(row.collapsed
                    and "Interface\\Buttons\\UI-PlusButton-Up"
                    or "Interface\\Buttons\\UI-MinusButton-Up")
                header:Show()

                yOffset = yOffset + HEADER_ROW_HEIGHT
            elseif row.kind == "emptyslot" then
                local group = row.group
                emptySlotIndex = emptySlotIndex + 1
                local btn = GetOrCreateEmptySlotButton(emptySlotIndex)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", col * (ITEM_SIZE + ITEM_PADDING), -yOffset)
                btn.group = group
                if Embolsao.IsClassic and group.bagID == KEYRING_CONTAINER then
                    -- Blizzard's own code hardcodes this rather than
                    -- resolving it through SetBagPortraitTexture too.
                    btn.icon:SetTexture("Interface\\ContainerFrame\\KeyRing-Bag-Icon")
                elseif group.bagID then
                    C_Container.SetBagPortraitTexture(btn.icon, group.bagID)
                else
                    btn.icon:SetAtlas("bags-item-slot64")
                end
                btn.icon:SetDesaturated(true)
                btn.icon:SetAlpha(0.5)
                btn.Count:SetText(tostring(#group.slots))
                btn.Count:Show()
                btn:Show()

                col = col + 1
                if col >= itemsPerRow then
                    col = 0
                    yOffset = yOffset + (ITEM_SIZE + ITEM_PADDING)
                end
            else
                local entry = row.entry
                itemIndex = itemIndex + 1
                local btn = GetOrCreateItemButton(itemIndex)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", col * (ITEM_SIZE + ITEM_PADDING), -yOffset)
                btn.itemID = entry.itemID
                btn.hyperlink = entry.hyperlink
                btn.locations = entry.locations
                -- A Gearset tab's Equipped/Unavailable rows (Layout.lua)
                -- aren't backed by any real bag slot -- see the OnClick/
                -- OnDragStart/OnReceiveDrag guards above.
                btn.embolsaoVirtual = entry.isVirtual == true
                local location = entry.locations and entry.locations[1]
                btn:SetBagID(location and location.bagID)
                btn:SetID(location and location.slot or 0)
                -- The offline bank's slots aren't real: no use action at all
                -- (a nil bag switches the overlay's off).
                btn.embolsaoReadOnly = readOnly
                UpdateUseOverlay(btn, (not readOnly) and location and location.bagID or nil,
                    location and location.slot)
                SetItemButtonTexture(btn, entry.icon)
                SetItemButtonCount(btn, entry.count)
                SetItemButtonQuality(btn, entry.quality, entry.itemID)
                ShowQualityBorder(btn, entry.quality)
                UpdateQuestTexture(btn, entry)
                btn.JunkIcon:SetShown(entry.isJunk == true)
                UpdatePawnUpgradeIcon(btn, entry.hyperlink)
                btn.RecentDismiss:SetShown(row.isRecent == true)
                btn.GearsetEquippedCheck:SetShown(entry.isGearsetEquipped == true)
                btn.GearsetUnavailableIcon:SetShown(entry.isUnavailable == true)
                if entry.isUnavailable then
                    btn.icon:SetDesaturated(true)
                    btn.icon:SetAlpha(0.5)
                else
                    btn.icon:SetDesaturated(false)
                    btn.icon:SetAlpha(1)
                end
                btn:Show()

                col = col + 1
                if col >= itemsPerRow then
                    col = 0
                    yOffset = yOffset + (ITEM_SIZE + ITEM_PADDING)
                end
            end
        end

        for index = itemIndex + 1, #itemButtons do
            itemButtons[index].itemID = nil
            itemButtons[index].locations = nil
            itemButtons[index].embolsaoVirtual = nil
            itemButtons[index]:Hide()
        end
        for index = headerIndex + 1, #headerRows do
            headerRows[index]:Hide()
        end
        for index = emptySlotIndex + 1, #emptySlotButtons do
            emptySlotButtons[index].group = nil
            emptySlotButtons[index]:Hide()
        end

        -- Whatever row the last button landed on, that row's height still
        -- counts toward the total scrollable content height.
        frame.itemContainer:SetHeight(yOffset + (ITEM_SIZE + ITEM_PADDING))

        -- Keep an open stack-expansion popout in sync with whatever just
        -- changed (or close it if its super-stack doesn't exist anymore).
        if win.stackPopoutItemID then
            RefreshStackPopout()
        end

        -- Buttons are reused for different items on every refresh -- redo
        -- the fade for a modifier that's being held right now.
        win.ApplyModifierDimming(Bindings.ActionForCurrentClick())

        -- The same reuse leaves the tooltip stale: sell the item under the
        -- cursor and the next one slides into that very button, so the mouse
        -- never leaves or enters anything and OnEnter doesn't fire again.
        -- Rebuild it for whatever the button shows now, or drop it if the
        -- button emptied out.
        if GameTooltip:IsShown() then
            local owner = GameTooltip:GetOwner()
            if owner and owner.isEmbolsaoItemButton then
                if not owner:IsShown() or not owner.itemID then
                    GameTooltip:Hide()
                elseif owner:IsMouseOver() then
                    local onEnter = owner:GetScript("OnEnter")
                    if onEnter then onEnter(owner) end
                end
            end
        end

        win.UpdateDepositButton()
        win.UpdateOfflineButton()
        win.UpdateBankFooter()
        UI:SetupSecureToggle()
    end

    -- One-off peek at Blizzard's own bag window, without touching the
    -- persistent "disabled" setting.
    --
    -- With a single bagID, opens just that one bag via ToggleBag alongside
    -- this window, which stays open. With a list of bagIDs or no bagID at
    -- all, it's a full swap instead: closes this window first so the two
    -- don't end up stacked on top of each other.
    function win.OpenNativeBags(bagID)
        -- Modern clients (retail, the Classic "Forever" beta) default to
        -- Blizzard's "Combine all bags" mode, where there is no per-bag
        -- window at all: ToggleBag(id) just toggles the one combined frame
        -- (ContainerFrame.lua -> ToggleBag_Combined), whose frame ID never
        -- matches the bag we asked for. That made the single-bag peek below
        -- get suppressed straight away, and a list of bags toggle the
        -- combined frame open, closed, open... So in that mode the peek is
        -- always the full swap: this window closes, the combined native
        -- frame opens, untouched.
        local settings = _G.ContainerFrameSettingsManager
        local combinedID = type(bagID) == "number" and bagID or nil
        if settings and settings.IsUsingCombinedBags and settings:IsUsingCombinedBags(combinedID)
            and _G.OpenBackpack then
            if frame and frame:IsShown() then
                HidePane()
            end
            win.suppressTakeoverOnce = true
            _G.OpenBackpack()
            return
        end

        local isSinglePeek = type(bagID) == "number"

        if isSinglePeek then
            -- Scoped to this exact bagID -- a blanket exemption would let
            -- OTHER native frames slip past untouched too in the same tick.
            win.keepOpenDuringPeek = bagID
            win.suppressTakeoverOnce = bagID
        else
            if frame and frame:IsShown() then
                HidePane()
            end
            win.suppressTakeoverOnce = true
        end

        if isSinglePeek then
            ToggleBag(bagID)
        elseif type(bagID) == "table" then
            for _, id in ipairs(bagID) do
                ToggleBag(id)
            end
        else
            ToggleAllBags()
        end
    end

    -- We take over display duty for bags entirely: this window shows, the
    -- native frame(s) it manages get hidden. Called by the shared
    -- OnBagFrameShow dispatcher once it's determined this window owns the
    -- frame that just showed.
    function win.HandleNativeShow(nativeFrame)
        -- "Disabled" via the minimap button's menu, or a one-shot bypass
        -- from OpenNativeBags -- either way, leave native alone.
        --
        -- win.suppressTakeoverOnce is either `true` (blanket) or a specific
        -- bagID (a single-bag peek), scoped the same way as before.
        local suppressThis = Embolsao.db.disabled
            or win.suppressTakeoverOnce == true
            or (type(win.suppressTakeoverOnce) == "number" and nativeFrame:GetID() == win.suppressTakeoverOnce)

        if suppressThis then
            C_Timer.After(0, function()
                win.suppressTakeoverOnce = nil
            end)
            return
        end

        EnsureFrame()
        if not frame.currentTabs then
            win.BuildTabs()
        end
        if config.applyDefaultTab and Embolsao.db.defaultTab and Embolsao.db.defaultTab ~= "LAST" then
            config.SetActiveTab(Embolsao.db.defaultTab)
        end
        -- In combat a window that has item buttons can't be shown (see
        -- ShowPane): Blizzard's own bags then stay up, and get taken over
        -- when combat ends (win.RunPending).
        if not ShowPane() then return end
        if config.OnShown then config.OnShown() end

        local function ScanAndSuppress()
            config.Rescan()
            win.Refresh()
            UpdateFooterXP()
            win.UpdateBankModeToggle()
            win.SuppressNativeFrames()
        end

        -- The bank's own item data turns out not to be queryable via
        -- C_Container.GetContainerItemInfo until Blizzard's native bank
        -- frame has actually been visible/processing for a moment --
        -- confirmed live: hiding it immediately left every slot reading as
        -- empty, even on repeated manual rescans, while it worked instantly
        -- with the native frame left alone. config.rescanDelay (bank only)
        -- gives it that moment before we scan and take over display duty;
        -- bags has no such delay -- carried bag contents are always live.
        if config.rescanDelay then
            -- Only the SCAN waits. The native frame itself is taken out of
            -- sight right now (transparent and off-screen -- see
            -- SuppressNativeFrames; it stays "shown", so the data keeps
            -- loading): waiting to do that as well left Blizzard's bank
            -- window visible for that whole delay before ours took over.
            win.SuppressNativeFrames(true)
            C_Timer.After(config.rescanDelay, ScanAndSuppress)
        else
            ScanAndSuppress()
        end
    end

    function win.HandleNativeHide(nativeFrame)
        -- One-shot: a single-bag peek leaves this window open on purpose,
        -- so the native frame it opened closing again shouldn't take this
        -- window down with it.
        if win.keepOpenDuringPeek and nativeFrame:GetID() == win.keepOpenDuringPeek then
            win.keepOpenDuringPeek = nil
            return
        end
        if frame and not win.IsAnyManagedFrameShown() then
            HidePane()
        end
    end

    -- nativeBagFrames is the single shared list of every hooked native
    -- frame (both windows' domains) -- declared once near the top of the
    -- file, before either window is created.
    -- onlyBankFrame: just move the bank's own frame away, leaving any other
    -- native frame this window manages alone for now -- they are actually hidden,
    -- which is what can starve the bank data loading (see the rescanDelay
    -- comment in HandleNativeShow), so those wait for the delayed pass.
    function win.SuppressNativeFrames(onlyBankFrame)
        suppressingNativeHide = true
        for _, bagFrame in ipairs(nativeBagFrames) do
            if config.IsManagedFrame(bagFrame) then
                if bagFrame == _G.BankFrame then
                    -- BankFrame's own OnHide handler calls CloseBankFrame()
                    -- directly (confirmed against Blizzard's own
                    -- Classic/BankFrame.lua, and BankFrameBaseMixin:OnHide on
                    -- the modern bank -- retail and Forever) -- actually hiding it would
                    -- end the whole banking interaction with the server,
                    -- taking this window down with it, and also unregisters
                    -- the PLAYERBANKSLOTS_CHANGED listener that's what
                    -- actually populates bank item data in the first place.
                    -- Moved off-screen instead of hidden, so it stays
                    -- "shown" (IsShown() true) and keeps working normally
                    -- from the game's perspective -- just nowhere the
                    -- player can see or click it.
                    bagFrame:SetClampedToScreen(false)
                    bagFrame:EnableMouse(false)
                    bagFrame:EnableKeyboard(false)
                    bagFrame:SetAlpha(0)
                    bagFrame:ClearAllPoints()
                    bagFrame:SetPoint("CENTER", UIParent, "CENTER", -10000, -10000)
                    -- Its children (the modern bank's item buttons) keep
                    -- their own mouse handling. Sent to the back so that if
                    -- the UI panel manager ever pulls the frame back on
                    -- screen, whatever invisible buttons that brings can't sit
                    -- on top of our windows and eat their clicks.
                    if not bagFrame.embolsaoOldStrata then
                        bagFrame.embolsaoOldStrata = bagFrame:GetFrameStrata()
                    end
                    bagFrame:SetFrameStrata("BACKGROUND")
                elseif not onlyBankFrame then
                    bagFrame:Hide()
                end
            end
        end
        C_Timer.After(0, function()
            suppressingNativeHide = false
        end)
    end

    function win.IsAnyManagedFrameShown()
        for _, bagFrame in ipairs(nativeBagFrames) do
            if bagFrame:IsShown() and config.IsManagedFrame(bagFrame) then
                return true
            end
        end
        return false
    end

    win.IsManagedFrame = config.IsManagedFrame

    win.EnsureFrame = EnsureFrame
    win.GetFrame = function() return frame end
    win.IsShown = function() return frame and frame:IsShown() end
    win.Hide = HidePane

    return win
end

--------------------------------------------------------------------------
-- The two windows. Bags is the original window, unchanged in behavior;
-- Bank is the new one, sharing every bit of chrome/interaction the factory
-- above provides but scanning/showing bank storage instead.
--------------------------------------------------------------------------

-- ContainerFrameCombinedBags (retail only) shows several bags in one window
-- at once, so it can't be selectively split into "ours" vs "the bank's" the
-- way each individual ContainerFrameN can via its own :GetID() -- it's an
-- all-or-nothing frame, and it's always bags-domain (the bank's own tabs
-- render through individual ContainerFrameN, never combined).
local function IsCombinedBagsFrame(bagFrame)
    return bagFrame and bagFrame.GetName and bagFrame:GetName() == "ContainerFrameCombinedBags"
end

-- Classic/TBC's bank "Item Slots" grid isn't a ContainerFrameN at all --
-- it's BankFrame itself, permanently carrying :GetID() == BANK_CONTAINER
-- (set once by Blizzard's own code, confirmed against Classic/BankFrame.lua)
-- rather than being reassigned per-bag the way ContainerFrameN is. Retail's
-- BankFrame is a completely different beast: just the modern Bank Panel's
-- outer chrome (title bar, tab strip, purchase/deposit buttons) -- actual
-- bank tab contents (Enum.BagIndex.CharacterBankTab_*) render through their
-- own separate ContainerFrameN frames, covered by IsBankManagedBagID below.
-- Checked by identity, not GetID(): an untouched frame defaults to GetID()
-- 0, which would otherwise be mistaken for the backpack on retail.
--
-- Update: the modern bank's BankFrame (retail, and Classic "Forever" -- see
-- Embolsao:UsesModernBank) is the same story in the one way that matters
-- here: its OnHide calls C_Bank.CloseBankFrame() (Blizzard's
-- BankFrameBaseMixin), so it too must never be hidden, only moved away --
-- and it too must never be mistaken for the backpack by its default ID of 0.
-- So it's claimed by identity on every flavor.
local function IsBankStorageFrame(bagFrame)
    return _G.BankFrame ~= nil and bagFrame == _G.BankFrame
end

-- Bag 5 is the reagent bag on retail; Classic/TBC have no reagent bag at
-- all, so that same bagID is just the first bank bag slot there instead --
-- REAGENT_BAG_ID and IsBankManagedBagID are mutually exclusive per flavor
-- rather than both claiming "bagID 5 and up" (that collision is exactly
-- what hijacked Classic's first bank bag slot earlier this cycle).
local REAGENT_BAG_ID = (not Embolsao.IsClassic) and 5 or nil

local function IsBagsManagedBagID(bagID)
    if bagID == nil then return false end
    if bagID >= BACKPACK_CONTAINER and bagID <= NUM_BAG_SLOTS then return true end
    if REAGENT_BAG_ID and bagID == REAGENT_BAG_ID then return true end
    -- Retail leaves IsKeyRingEnabled/KEYRING_CONTAINER as stale globals even
    -- though the keyring was removed there -- Embolsao.IsClassic is what
    -- actually tells the two apart.
    if Embolsao.IsClassic and bagID == KEYRING_CONTAINER and IsKeyRingEnabled and IsKeyRingEnabled() then return true end
    return false
end

local function IsBankManagedBagID(bagID)
    if bagID == nil or not Embolsao.db.mergeBankStorage then return false end
    for _, id in ipairs(Embolsao.PersonalBankBagIDs) do
        if bagID == id then return true end
    end
    for _, id in ipairs(Embolsao.WarbandBankBagIDs) do
        if bagID == id then return true end
    end
    return false
end

bagsWindow = CreateWindow({
    id = "Bags",
    domain = "bags", -- which set of tabs this pane uses (Embolsao:GetFilters)
    paneLabel = function()
        local info = Embolsao:GetViewedCharacterInfo()
        return info and (L.PANE_BAGS .. " - " .. Embolsao:GetCharacterDisplayName(Embolsao.ViewChar, info)) or L.PANE_BAGS
    end,
    hasFooter = true,
    hasBankModeToggle = false,
    applyDefaultTab = true,
    -- Opening the bags while standing at a banker also brings the bank part
    -- back if it was closed on its own (its X) -- the way to reopen it
    -- without walking away and back.
    OnShown = function()
        if Embolsao.AtBank and Embolsao.db.mergeBankStorage
            and _G.BankFrame and _G.BankFrame:IsShown() and not bankWindow.IsShown() then
            bankWindow.HandleNativeShow(_G.BankFrame)
        end
    end,
    -- Another character's saved bags live in a pool of their own (see
    -- Embolsao.ViewChar in Core.lua): the live one stays what selling and
    -- gearsets read.
    GetInventory = function()
        if Embolsao.ViewChar then return Embolsao.AltInventory or {} end
        return Embolsao.VirtualInventory
    end,
    GetEmptySlotGroups = function()
        if Embolsao.ViewChar then return Embolsao.AltEmptySlotGroups end
        return Embolsao.EmptySlotGroups
    end,
    GetActiveTab = function() return Embolsao.db.activeTab end,
    SetActiveTab = function(id) Embolsao.db.activeTab = id end,
    Rescan = function()
        if Embolsao.ViewChar then
            Embolsao:ScanAltBags()
        else
            Embolsao:ScanBags()
        end
    end,
    IsManagedFrame = function(bagFrame)
        if IsCombinedBagsFrame(bagFrame) then return true end
        -- The bank frame's default ID is 0 -- the backpack's -- which made
        -- this window claim (and hide) it instead of the bank window.
        if IsBankStorageFrame(bagFrame) then return false end
        return IsBagsManagedBagID(bagFrame and bagFrame:GetID())
    end,
})

-- With Preferences -> "Separate tabs for Bank and Bags" on, the bank's
-- selected tab is remembered like the bags' (Embolsao.db.bankActiveTab);
-- sharing the bags' tabs, it isn't persisted and just starts on "All".
local bankActiveTab = "ALL"

bankWindow = CreateWindow({
    id = "Bank",
    domain = "bank",
    paneLabel = function()
        return Embolsao.BankOffline and L.PANE_BANK_OFFLINE or L.PANE_BANK
    end,
    -- Can be closed on its own with the X on its pane, leaving the bags --
    -- and closing the bank also ends the banking interaction, like closing
    -- Blizzard's own bank window does.
    closablePane = true,
    OnClosePane = function()
        EndBankInteraction()
        EndOfflineBank()
    end,
    -- The bank has no XP line, but its footer has a better use: buying more
    -- bank space (see UpdateBankFooter) next to the player's money.
    hasFooter = true,
    hasBankPurchase = true,
    hasBankModeToggle = true,
    applyDefaultTab = false,
    -- See the comment on ScanAndSuppress in HandleNativeShow -- the bank's
    -- own item data needs Blizzard's native frame left alone for a moment
    -- before it's actually queryable.
    rescanDelay = 0.5,
    GetInventory = function() return Embolsao.BankVirtualInventory end,
    GetEmptySlotGroups = function() return Embolsao.BankEmptySlotGroups end,
    GetActiveTab = function()
        if Embolsao.db.separateBankTabs then return Embolsao.db.bankActiveTab end
        return bankActiveTab
    end,
    SetActiveTab = function(id)
        if Embolsao.db.separateBankTabs then
            Embolsao.db.bankActiveTab = id
        else
            bankActiveTab = id
        end
    end,
    Rescan = function()
        -- Reached from the delayed scan after the bank opens: what the bank
        -- shows is real from here on, so it is worth saving (see ScanBank).
        Embolsao.bankSettled = Embolsao.AtBank
        Embolsao:ScanBank()
    end,
    IsManagedFrame = function(bagFrame)
        if not Embolsao.db.mergeBankStorage then return false end
        -- By identity, never the GetID()-based check below: an untouched
        -- frame's ID is 0, which is the backpack.
        if IsBankStorageFrame(bagFrame) then return true end
        return IsBankManagedBagID(bagFrame and bagFrame:GetID())
    end,
})

pawnWindows[1], pawnWindows[2] = bagsWindow, bankWindow
UI.bagsWindow, UI.bankWindow = bagsWindow, bankWindow -- for the files split out of this one

-- The footer's XP line used to refresh only when the window opened; keep it
-- current while it's up (XP gained, rested XP changing, a level-up). Not every
-- flavor has every one of these events, so registration mustn't be fatal.
local xpEventFrame = CreateFrame("Frame")
for _, xpEvent in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP" }) do
    pcall(xpEventFrame.RegisterEvent, xpEventFrame, xpEvent)
end
xpEventFrame:SetScript("OnEvent", function()
    bagsWindow.UpdateFooterXP()
end)

-- Holding or releasing Ctrl/Shift/Alt while the cursor is on one of our item
-- buttons rebuilds its tooltip, so the binding hint for the combo being held
-- lights up (Bindings.AddBindingHints) -- the tooltip otherwise only builds on entry.
local modifierFrame = CreateFrame("Frame")
modifierFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
modifierFrame:SetScript("OnEvent", function()
    -- Fade out (or restore) the items the action bound to the held modifier
    -- can't act on, in both windows.
    local action = Bindings.ActionForCurrentClick()
    bagsWindow.ApplyModifierDimming(action)
    bankWindow.ApplyModifierDimming(action)

    if not GameTooltip:IsShown() then return end
    local owner = GameTooltip:GetOwner()
    if owner and owner.isEmbolsaoItemButton then
        local onEnter = owner:GetScript("OnEnter")
        if onEnter then onEnter(owner) end
    end
end)

-- The bank footer's purchase button follows what's affordable and what's left
-- to buy: after a purchase (a new tab / bag slot appears), and as money
-- changes. Nothing to do away from a banker. The event names differ by bank
-- (Classic: PLAYERBANKBAGSLOTS_CHANGED; modern: BANK_TABS_CHANGED), and an
-- unknown one must not be fatal.
local bankPurchaseEventFrame = CreateFrame("Frame")
for _, purchaseEvent in ipairs({ "PLAYER_MONEY", "BANK_TABS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED" }) do
    pcall(bankPurchaseEventFrame.RegisterEvent, bankPurchaseEventFrame, purchaseEvent)
end
bankPurchaseEventFrame:SetScript("OnEvent", function()
    if not Embolsao.AtBank then return end
    Embolsao:ScanBank()
    bankWindow.Refresh()
    bankWindow.UpdateBankModeToggle()
end)

local function GetOwningWindow(bagFrame)
    if bagsWindow.IsManagedFrame(bagFrame) then return bagsWindow end
    if bankWindow.IsManagedFrame(bagFrame) then return bankWindow end
    return nil
end

-- We take over display duty for bags/bank entirely: the owning window
-- shows, the native frame(s) it manages get hidden (not just dimmed). The
-- suppressingNativeHide flag matters because HIDING the native frame
-- ourselves fires its own OnHide script (hooked below too) -- without it,
-- that would immediately hide our just-opened window right back.
-- Defined further down (they need RestoreBankFrameAppearance and the bank
-- window). The BankFrame's own show/hide is the one bank signal that exists on
-- every flavor: the modern bank may never fire BANKFRAME_OPENED/CLOSED
-- (Blizzard opens it through BankFrame_Open() now), so the state can't hang
-- on those events alone.
local HandleBankOpened, HandleBankClosed

-- Closes the whole window (both parts, and the banker interaction if the bank
-- part was up) the way the bags key does when our window is what's open.
local function CloseWindowFromToggle()
    local bankWasShown = bankWindow.IsShown()
    bagsWindow.Hide()
    -- It's one window: closing it with the bags key closes the bank part too,
    -- and ends the banking interaction like closing the bank would.
    bankWindow.Hide()
    if bankWasShown then
        EndBankInteraction()
    end
    EndOfflineBank()
end

-- Modern clients (Retail, Forever) don't get the toggle functions replaced --
-- see WrapBagToggleFunctions -- so "the player pressed the bags key while our
-- window is up" has to be recognised from the native frame showing: pressing
-- it opens Blizzard's bags (which think they are closed, we only ever hide
-- them), and if that show came from ToggleBackpack / ToggleAllBags rather than
-- from Blizzard opening bags for something else (OpenBackpack and the like:
-- the bank, a vendor, the mailbox), it means "close".
local function IsPlayerBagToggle()
    if not debugstack then
        return not (_G.BankFrame and _G.BankFrame:IsShown())
    end
    local stack = debugstack(1, 14, 0) or ""
    if stack:find("'OpenBackpack'", 1, true) or stack:find("'OpenAllBags'", 1, true)
        or stack:find("'OpenBag'", 1, true) then
        return false
    end
    return stack:find("'ToggleBackpack'", 1, true) ~= nil or stack:find("'ToggleAllBags'", 1, true) ~= nil
end

-- True from the moment the bags key closed our window until the frame ends:
-- ToggleAllBags can show several native frames one after the other, and each
-- of them must be put away instead of being taken for a fresh open.
local closedByToggle = false

local function OnBagFrameShow(self)
    if self == _G.BankFrame then HandleBankOpened() end
    local win = GetOwningWindow(self)
    if not win then return end

    if win == bagsWindow and Embolsao:UsesModernBank() then
        if closedByToggle then
            bagsWindow.SuppressNativeFrames()
            return
        end
        if bagsWindow.IsShown() and IsPlayerBagToggle() then
            closedByToggle = true
            C_Timer.After(0, function() closedByToggle = false end)
            CloseWindowFromToggle()
            bagsWindow.SuppressNativeFrames()
            return
        end
    end

    win.HandleNativeShow(self)
end

local function OnBagFrameHide(self)
    if suppressingNativeHide then return end
    if self == _G.BankFrame then HandleBankClosed() end
    local win = GetOwningWindow(self)
    if win then win.HandleNativeHide(self) end
end

local function IsAnyNativeBagFrameShown()
    for _, bagFrame in ipairs(nativeBagFrames) do
        if bagFrame:IsShown() then
            return true
        end
    end
    return false
end

-- Undoes the off-screen trick from win.SuppressNativeFrames above -- called
-- whenever BankFrame should go back to behaving completely normally: on
-- leaving the bank (so the next visit starts from a clean, correctly
-- positioned frame rather than compounding leftover state) and when "Use
-- Embolsao for Bank" gets turned off (UI:RefreshBankAvailability), so
-- native bank display isn't left permanently broken by our own hack.
local function RestoreBankFrameAppearance()
    local bankFrame = _G.BankFrame
    if bankFrame then
        bankFrame:SetClampedToScreen(true)
        bankFrame:EnableMouse(true)
        bankFrame:EnableKeyboard(true)
        bankFrame:SetAlpha(1)
        if bankFrame.embolsaoOldStrata then
            bankFrame:SetFrameStrata(bankFrame.embolsaoOldStrata)
            bankFrame.embolsaoOldStrata = nil
        end
    end
end

-- Visiting a banker shows the bank's native frame(s) -- BankFrame itself on
-- Classic/TBC, individual ContainerFrameN's on retail (already covered by
-- the general hook list). This handler exists for three things the generic
-- OnShow/OnHide dispatch above can't do on its own:
--   1. Classic/TBC's BankFrame doesn't reliably exist yet the one time
--      InstallBagFrameHooks scans for native frames right after
--      login/reload -- confirmed live. Hooking it here too, the first time
--      it's actually needed, doesn't depend on that startup timing at all.
--   2. Resetting BankViewMode back to "PERSONAL" once the bank closes --
--      there's no "Warband Bank" to speak of once you've walked away.
--   3. Undoing the off-screen suppression trick each time the bank closes,
--      so the next visit starts clean.
--   4. On the modern bank, re-reading which bank tabs exist (their bag IDs
--      depend on the flavor and on which tabs this character has bought).
-- Both handlers are safe to run more than once for the same visit -- they're
-- reached from the BankFrame's own OnShow/OnHide hooks AND from the events.
HandleBankOpened = function()
    -- The real bank takes over from the saved copy; what it shows is only
    -- worth saving once it has settled (see Rescan in the bank's config).
    Embolsao.BankOffline = false
    -- (Reached more than once per visit; only a fresh visit starts unsettled.)
    if not Embolsao.AtBank then
        Embolsao.bankSettled = false
    end
    Embolsao.AtBank = true
    -- A banker's window is the real bank: no other character's items in it.
    UI.ResetViewedCharacter()
    Embolsao:RefreshModernBankBagIDs()
    -- Right-click on a bag item means "deposit" now, not "use" (see
    -- UpdateUseOverlay) -- re-point the overlays.
    UI:Refresh()
end

HandleBankClosed = function()
    Embolsao.AtBank = false
    Embolsao.bankSettled = false
    Embolsao.BankViewMode = "PERSONAL"
    bankWindow.Hide()
    RestoreBankFrameAppearance()
    UI:Refresh()
end

local bankEventFrame = CreateFrame("Frame")
bankEventFrame:RegisterEvent("BANKFRAME_OPENED")
bankEventFrame:RegisterEvent("BANKFRAME_CLOSED")
bankEventFrame:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_CLOSED" then
        HandleBankClosed()
        return
    end

    HandleBankOpened()

    local justHooked = false
    if _G.BankFrame and not tContains(nativeBagFrames, _G.BankFrame) then
        table.insert(nativeBagFrames, _G.BankFrame)
        _G.BankFrame:HookScript("OnShow", OnBagFrameShow)
        _G.BankFrame:HookScript("OnHide", OnBagFrameHide)
        justHooked = true
    end

    -- BankFrame is already shown by the time this event fires -- the hook
    -- just added above only fires on the NEXT show, so this one has to be
    -- driven by hand right now instead of waiting for that. Classic/TBC does
    -- it on every visit (long-standing behavior there); the modern bank has
    -- its OnShow hook installed with the other native frames, so only the
    -- first-ever, just-hooked case needs it.
    if _G.BankFrame and _G.BankFrame:IsShown() and (justHooked or not Embolsao:UsesModernBank()) then
        OnBagFrameShow(_G.BankFrame)
    end
end)

function UI:ShowPreferences()
    UI.ShowPreferencesFrame()
end

-- The tab editor's view of a tab's category grouping (see Layout.GetTabGrouping).
-- `tabID` is the state ID: the tab's ID with its set's prefix.
function UI:GetTabGrouping(tabID)
    return Layout.GetTabGrouping(tabID)
end

function UI:SetTabGrouping(tabID, groupByClass, groupBySubClass)
    Layout.SetTabGrouping(tabID, "groupByClass", groupByClass)
    Layout.SetTabGrouping(tabID, "groupBySubClass", groupBySubClass)
end

function UI:GetTabPinnedGroups(tabID)
    return Layout.GetTabPinnedGroups(tabID)
end

function UI:SetTabPinnedGroups(tabID, showRecent, showJunk, showQuest)
    Layout.SetTabPinnedGroups(tabID, showRecent, showJunk, showQuest)
end

-- Same idea for a tab's sort, for the tab editor: returns mode, ascending
-- (Layout.SORT_MODES has the modes' IDs and labels, in menu order).
function UI:GetTabSort(tabID)
    return Layout.GetTabSort(tabID)
end

function UI:SetTabSort(tabID, mode, ascending)
    Layout.SetTabSort(tabID, mode, ascending)
end

function UI:GetSortModes()
    return Layout.SORT_MODES
end

-- Bags-window peek: right-click on a special bag's empty-slot button, or
-- the minimap menu's "Open Default Bags". The bank window has its own
-- OpenNativeBags for its own empty-slot buttons (win.OpenNativeBags,
-- called directly there, never through here).
function UI:OpenNativeBags(bagID)
    bagsWindow.OpenNativeBags(bagID)
end

-- Minimap button's "Disable Embolsao" toggle: leaves native bags/bank alone
-- entirely from here on -- OnBagFrameShow bails immediately instead of
-- taking over, for both windows. Just closes whichever window(s) are
-- currently open on the way through.
function UI:SetDisabled(disabled)
    Embolsao.db.disabled = disabled and true or false
    UI:RefreshSecureToggle()

    if disabled then
        bagsWindow.Hide()
        bankWindow.Hide()
    elseif IsAnyNativeBagFrameShown() then
        for _, bagFrame in ipairs(nativeBagFrames) do
            bagFrame:Hide()
        end
    end
end

-- Preferences -> "Offline Bank" changed. Off: the saved copies are dropped and
-- an offline view that is open closes; on: copies start again at the next
-- visit to a banker.
function UI:RefreshOfflineBank()
    if Embolsao.db.offlineBank == false then
        if Embolsao.BankOffline then
            bankWindow.Hide()
            EndOfflineBank()
        end
        if EmbolsaoCharDB then EmbolsaoCharDB.bankSnapshot = nil end
        if EmbolsaoDB then EmbolsaoDB.warbandBankSnapshot = nil end
    end
    bagsWindow.UpdateOfflineButton()
end

-- Preferences -> "Use Embolsao for Bank" toggled off while at the bank:
-- hide our bank window and let native take back over from here. Toggled
-- on: nothing to do until the next bank interaction naturally re-triggers
-- HandleNativeShow for whatever bank frame shows next.
function UI:RefreshBankAvailability()
    if not Embolsao.db.mergeBankStorage then
        bankWindow.Hide()
        RestoreBankFrameAppearance()
    end
end

-- Preferences -> "Background Opacity" changed.
function UI:RefreshBackgroundOpacity()
    ApplyBackgroundOpacity()
end

function UI:Refresh()
    bagsWindow.Refresh()
    bankWindow.Refresh()
end

function UI:BuildTabs()
    bagsWindow.BuildTabs()
    bankWindow.BuildTabs()
    -- Rebuilding tabs can change what the currently active tab even is
    -- (e.g. it was just deleted) -- Refresh re-derives everything
    -- downstream of that.
    bagsWindow.Refresh()
    bankWindow.Refresh()
end

-- Blizzard's own "is the bag open" tracking thinks bags are closed once we
-- hide the native frame(s) (we only ever hide them, never truly close
-- them), so pressing the bag keybind again just re-runs "open" and does
-- nothing visible. Wrapping the keybind's own functions instead of
-- touching the keybind itself: if the bags window is currently up, close
-- IT and skip calling the real toggle at all; otherwise fall through to
-- Blizzard's original behavior untouched. Bags-only -- there's no keybind
-- for the bank window, it opens/closes only via BANKFRAME_OPENED/CLOSED.
-- Non-zero while one of Blizzard's own "open the bags" functions is running.
-- Classic's OpenBackpack() -- which the bank calls the moment it opens -- runs
-- ToggleBackpack() by its global name, i.e. the wrapper below; taking that for
-- the player pressing the bags key made it close our window (and the bank part
-- with it) whenever the bags were already up as the bank opened. While this is
-- set the wrapper just lets the original run.
local openingBags = 0

local function WrapBagToggle(original)
    return function(...)
        if openingBags == 0 and bagsWindow.IsShown() then
            local bankWasShown = bankWindow.IsShown()
            bagsWindow.Hide()
            -- It's one window: closing it with the bags key closes the bank
            -- part too, and ends the banking interaction like closing the
            -- bank would.
            bankWindow.Hide()
            if bankWasShown then
                EndBankInteraction()
            end
            EndOfflineBank()
            return
        end
        return original(...)
    end
end

-- Marks the call as "Blizzard is opening bags", for openingBags above.
local function WrapOpenFunction(name)
    local original = _G[name]
    if type(original) ~= "function" then return end

    _G[name] = function(...)
        openingBags = openingBags + 1
        local ok, a, b, c = pcall(original, ...)
        openingBags = openingBags - 1
        if not ok then error(a, 0) end
        return a, b, c
    end
end

local bagToggleFunctionsWrapped = false
local function WrapBagToggleFunctions()
    if bagToggleFunctionsWrapped then return end
    if not (ToggleBackpack and ToggleAllBags) then return end

    -- Not on the modern clients (Retail, Forever): with individual bags
    -- (not "Combine all bags") Blizzard's own OpenBackpack() calls
    -- ToggleBackpack() by its global name, and while that global is our
    -- function every such call -- for instance while the bank opens -- runs
    -- tainted, which made the game refuse the free first bank tab purchase
    -- ("blocked from an action only available to the Blizzard UI"; the taint
    -- log named exactly this read). They recognise the bags key from the
    -- native frame showing instead (OnBagFrameShow), leaving the globals alone.
    if Embolsao:UsesModernBank() then
        bagToggleFunctionsWrapped = true
        return
    end

    ToggleBackpack = WrapBagToggle(ToggleBackpack)
    ToggleAllBags = WrapBagToggle(ToggleAllBags)
    -- Classic Era / TBC: OpenBackpack() really does call ToggleBackpack()
    -- there, so those are marked (openingBags) to tell them from the key.
    WrapOpenFunction("OpenBackpack")
    WrapOpenFunction("OpenBag")
    WrapOpenFunction("OpenAllBags")
    bagToggleFunctionsWrapped = true
end

-- ContainerFrameCombinedBags/ContainerFrame1..6/BankFrame belong to
-- Blizzard_UIPanels_Game, a load-on-demand module that only loads the first
-- time the player opens a bag. It's almost never loaded yet at
-- PLAYER_LOGIN, so we wait for its ADDON_LOADED (and still check at
-- PLAYER_LOGIN in case some other addon forced it earlier).
local hooksInstalled = false
local function InstallBagFrameHooks()
    if hooksInstalled then return end

    local foundAny = false
    for _, name in ipairs(NATIVE_BAG_FRAME_NAMES) do
        local bagFrame = _G[name]
        if bagFrame then
            foundAny = true
            table.insert(nativeBagFrames, bagFrame)
            bagFrame:HookScript("OnShow", OnBagFrameShow)
            bagFrame:HookScript("OnHide", OnBagFrameHide)
        end
    end

    if foundAny then
        hooksInstalled = true
        Embolsao:InitBankBagIDs()
        WrapBagToggleFunctions()
    end
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon ~= "Blizzard_UIPanels_Game" then
        return
    end
    InstallBagFrameHooks()
end)

-- The secure right-click overlays on item buttons can't be re-pointed while
-- in combat (UpdateUseOverlay skips them), so whatever changed meanwhile is
-- applied by a refresh the moment combat ends.
local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
local reopenBagsAfterCombat = false
regenFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- The resize grip would start sizing the window, which can't be done
        -- in combat (see the host's drag handler).
        if host and host.resizeButton then
            host.resizeButton:EnableMouse(false)
        end

        -- Preferences -> "Close bags in combat". Hiding the window takes the
        -- bank part (and the banker interaction) with it; the bags come back
        -- when combat ends.
        if Embolsao.db.closeOnCombat and host and host:IsShown() then
            reopenBagsAfterCombat = bagsWindow.IsShown() == true
            -- (Skipped if combat's restrictions are already on: the game
            -- would refuse it, see ShowPane.)
            if not (InCombatLockdown() and host:IsProtected()) then
                host:Hide()
            end
        end
        return
    end

    -- Combat over: what had to wait (window layout, the grid's contents) is
    -- done now, and the bags reopen if the preference closed them.
    if host and host.resizeButton then
        host.resizeButton:EnableMouse(true)
    end
    bagsWindow.RunPending()
    bankWindow.RunPending()
    if host and host.layoutPending then
        LayoutHost()
    end
    if reopenBagsAfterCombat then
        reopenBagsAfterCombat = false
        if not bagsWindow.IsShown() and not Embolsao.db.disabled then
            ToggleAllBags()
        end
    end
    UI:Refresh()
end)

-- Vendor open/close: drives the Junk group's sell button (enabled look, tooltip)
-- and stops an in-progress sell if the window is closed on us. With
-- Preferences -> "Auto-sell Junk" on, opening a vendor also sells every grey
-- item in the bags right away: straight from the bag scan, not from the
-- Junk group as displayed, so it doesn't depend on the group being shown, on
-- the active tab or on the search box. Same sell routine (and the same chat
-- message) as the button.
local function AutoSellJunk()
    Embolsao:ScanBags()
    local entries = {}
    for _, entry in pairs(Embolsao.VirtualInventory) do
        table.insert(entries, entry)
    end
    SellJunkEntries(entries)
end

local merchantFrame = CreateFrame("Frame")
merchantFrame:RegisterEvent("MERCHANT_SHOW")
merchantFrame:RegisterEvent("MERCHANT_CLOSED")
merchantFrame:SetScript("OnEvent", function(_, event)
    merchantOpen = event == "MERCHANT_SHOW"
    if merchantOpen and Embolsao.db and Embolsao.db.autoSellJunk then
        AutoSellJunk()
    end
    UI:Refresh()
end)
