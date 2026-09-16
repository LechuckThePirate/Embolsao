local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

Embolsao.TabEditor = {}
local TabEditor = Embolsao.TabEditor

--------------------------------------------------------------------------
-- Icon picker: reuses Blizzard's own icon catalog data (the exact list the
-- macro UI picks from) via IconDataProviderMixin (Blizzard_FrameXMLBase,
-- always loaded -- unlike the actual macro icon-picker WIDGET, which lives
-- in the load-on-demand Blizzard_MacroUI and is tightly coupled to editing
-- macros specifically). We just want the data, not that widget.
--
-- Paged instead of scrolled: the catalog is 1000+ icons, and creating one
-- button per icon up front (our first attempt) froze the game for several
-- seconds creating that many frames in one tick. A fixed page of buttons,
-- reused and re-textured per page, never creates more than ICONS_PER_PAGE
-- frames total.
--------------------------------------------------------------------------

local ICON_PICKER_BUTTON_SIZE = 36
local ICON_PICKER_PADDING = 4
local ICON_PICKER_COLUMNS = 10
local ICON_PICKER_ROWS = 8
local ICONS_PER_PAGE = ICON_PICKER_COLUMNS * ICON_PICKER_ROWS

local iconPicker

local function RenderIconPage()
    local numIcons = iconPicker.iconProvider:GetNumIcons()
    local maxPage = math.max(1, math.ceil(numIcons / ICONS_PER_PAGE))
    iconPicker.page = math.min(math.max(iconPicker.page, 1), maxPage)

    local startIndex = (iconPicker.page - 1) * ICONS_PER_PAGE
    for i = 1, ICONS_PER_PAGE do
        local iconIndex = startIndex + i
        local btn = iconPicker.buttons[i]
        if iconIndex <= numIcons then
            local icon = iconPicker.iconProvider:GetIconByIndex(iconIndex)
            SetItemButtonTexture(btn, icon)
            btn:SetScript("OnClick", function()
                iconPicker.onSelect(icon)
                iconPicker:Hide()
            end)
            btn:Show()
        else
            btn:Hide()
        end
    end

    iconPicker.pageLabel:SetText(string.format("%d / %d", iconPicker.page, maxPage))
    iconPicker.prevButton:SetEnabled(iconPicker.page > 1)
    iconPicker.nextButton:SetEnabled(iconPicker.page < maxPage)
end

local function EnsureIconPicker()
    if iconPicker then return iconPicker end

    local gridWidth = ICON_PICKER_COLUMNS * (ICON_PICKER_BUTTON_SIZE + ICON_PICKER_PADDING)
    local gridHeight = ICON_PICKER_ROWS * (ICON_PICKER_BUTTON_SIZE + ICON_PICKER_PADDING)

    iconPicker = CreateFrame("Frame", "EmbolsaoIconPickerFrame", UIParent, "BackdropTemplate")
    iconPicker:SetSize(gridWidth + 40, gridHeight + 110)
    iconPicker:SetPoint("CENTER")
    iconPicker:SetFrameStrata("FULLSCREEN_DIALOG")
    iconPicker:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    iconPicker:SetBackdropColor(0, 0, 0, 0.95)
    iconPicker:SetMovable(true)
    iconPicker:EnableMouse(true)
    iconPicker:RegisterForDrag("LeftButton")
    iconPicker:SetScript("OnDragStart", iconPicker.StartMoving)
    iconPicker:SetScript("OnDragStop", iconPicker.StopMovingOrSizing)
    tinsert(UISpecialFrames, "EmbolsaoIconPickerFrame")

    local close = CreateFrame("Button", nil, iconPicker, "UIPanelCloseButtonDefaultAnchors")
    close:SetPoint("TOPRIGHT", -2, -2)

    iconPicker.title = iconPicker:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    iconPicker.title:SetPoint("TOP", 0, -16)
    iconPicker.title:SetText(L.SELECT_ICON)

    iconPicker.grid = CreateFrame("Frame", nil, iconPicker)
    iconPicker.grid:SetSize(gridWidth, gridHeight)
    iconPicker.grid:SetPoint("TOP", 0, -46)

    iconPicker.buttons = {}
    for i = 1, ICONS_PER_PAGE do
        local btn = CreateFrame("ItemButton", nil, iconPicker.grid)
        local col = (i - 1) % ICON_PICKER_COLUMNS
        local row = math.floor((i - 1) / ICON_PICKER_COLUMNS)
        btn:SetPoint("TOPLEFT", col * (ICON_PICKER_BUTTON_SIZE + ICON_PICKER_PADDING), -row * (ICON_PICKER_BUTTON_SIZE + ICON_PICKER_PADDING))
        btn:SetSize(ICON_PICKER_BUTTON_SIZE, ICON_PICKER_BUTTON_SIZE)
        btn:RegisterForClicks("LeftButtonUp")
        iconPicker.buttons[i] = btn
    end

    iconPicker.prevButton = CreateFrame("Button", nil, iconPicker, "UIPanelButtonTemplate")
    iconPicker.prevButton:SetSize(80, 22)
    iconPicker.prevButton:SetPoint("BOTTOMLEFT", 16, 16)
    iconPicker.prevButton:SetText(PREVIOUS or "<")
    iconPicker.prevButton:SetScript("OnClick", function()
        iconPicker.page = iconPicker.page - 1
        RenderIconPage()
    end)

    iconPicker.nextButton = CreateFrame("Button", nil, iconPicker, "UIPanelButtonTemplate")
    iconPicker.nextButton:SetSize(80, 22)
    iconPicker.nextButton:SetPoint("BOTTOMRIGHT", -16, 16)
    iconPicker.nextButton:SetText(NEXT or ">")
    iconPicker.nextButton:SetScript("OnClick", function()
        iconPicker.page = iconPicker.page + 1
        RenderIconPage()
    end)

    iconPicker.pageLabel = iconPicker:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    iconPicker.pageLabel:SetPoint("BOTTOM", 0, 22)

    return iconPicker
end

-- onSelect(iconTexture) is called with either a numeric fileID or a full
-- "Interface\Icons\..." path (IconDataProviderMixin can hand back either);
-- both work directly with SetTexture/SetItemButtonTexture.
function TabEditor:ShowIconPicker(onSelect)
    local popup = EnsureIconPicker()

    if not popup.iconProvider then
        popup.iconProvider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.None)
    end

    popup.onSelect = onSelect
    popup.page = 1
    RenderIconPage()
    popup:Show()
end

--------------------------------------------------------------------------
-- Create/Edit Tab window
--------------------------------------------------------------------------

local ITEM_ROW_HEIGHT = 26
local RULE_ROW_HEIGHT = 20

local tabEditor
-- { id (nil if creating), name, icon, hiddenItemIDs = {[itemID]=true}, categoryRules = {} }
-- Must be a real table from file load, not just set lazily in ResetEditorState:
-- creating the dropdowns below evaluates their menu generator once immediately
-- (to resolve initial display text), which reads editorState before Show()
-- ever gets a chance to call ResetEditorState for the first time.
local editorState = {
    hiddenItemIDs = {},
    categoryRules = {},
    pendingMode = "show",
}

local function ResetEditorState(existingTab)
    if existingTab then
        local hiddenItemIDs = {}
        for itemID in pairs(existingTab.hiddenItemIDs or {}) do
            hiddenItemIDs[itemID] = true
        end
        local categoryRules = {}
        for _, rule in ipairs(existingTab.categoryRules or {}) do
            table.insert(categoryRules, { classID = rule.classID, subClassID = rule.subClassID, mode = rule.mode })
        end

        editorState = {
            id = existingTab.id,
            name = existingTab.name,
            icon = existingTab.icon,
            hiddenItemIDs = hiddenItemIDs,
            categoryRules = categoryRules,
        }
    else
        editorState = {
            id = nil,
            name = "",
            icon = "Interface\\Icons\\INV_Misc_Bag_10",
            hiddenItemIDs = {},
            categoryRules = {},
        }
    end

    -- The "add a rule" pending selection is independent of create-vs-edit --
    -- always start it fresh (this was missing for the edit path entirely,
    -- which left Add Rule silently unusable when editing an existing tab).
    editorState.pendingClassID = nil
    editorState.pendingSubClassID = nil
    editorState.pendingMode = "show"
end

local function GetItemIconTexture(itemID)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
        or select(10, GetItemInfo(itemID))
        or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function RefreshHiddenItemsList()
    local content = tabEditor.itemsContent
    tabEditor.itemRows = tabEditor.itemRows or {}

    local itemIDs = {}
    for itemID in pairs(editorState.hiddenItemIDs) do
        table.insert(itemIDs, itemID)
    end
    table.sort(itemIDs)

    for i, itemID in ipairs(itemIDs) do
        local row = tabEditor.itemRows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetSize(1, ITEM_ROW_HEIGHT)

            row.icon = CreateFrame("ItemButton", nil, row)
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT")

            row.removeButton = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
            row.removeButton:SetSize(18, 18)
            row.removeButton:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)

            tabEditor.itemRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_ROW_HEIGHT)
        SetItemButtonTexture(row.icon, GetItemIconTexture(itemID))
        row.icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemID)
            GameTooltip:Show()
        end)
        row.icon:SetScript("OnLeave", GameTooltip_Hide)
        row.removeButton:SetScript("OnClick", function()
            editorState.hiddenItemIDs[itemID] = nil
            RefreshHiddenItemsList()
        end)
        row:Show()
    end

    for i = #itemIDs + 1, #tabEditor.itemRows do
        tabEditor.itemRows[i]:Hide()
    end

    content:SetHeight(math.max(#itemIDs, 1) * ITEM_ROW_HEIGHT)
end

local function TryAddCursorItemToHidden()
    local cursorItem = C_Cursor.GetCursorItem()
    if not cursorItem then return end
    local bagID, slot = cursorItem:GetBagAndSlot()
    if not bagID then return end

    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if info and info.itemID then
        editorState.hiddenItemIDs[info.itemID] = true
        RefreshHiddenItemsList()
    end

    -- We're only reading the dragged item's identity, not actually moving
    -- it -- hand it right back to the exact slot it came from.
    C_Container.PickupContainerItem(bagID, slot)
end

local function DescribeRule(rule)
    local modeLabel = rule.mode == "show" and L.RULE_MODE_SHOW or L.RULE_MODE_HIDE

    if rule.classID == Embolsao.Filters.ALL_CATEGORIES then
        return string.format("%s: %s", modeLabel, L.ALL_CATEGORIES)
    end

    local className = C_Item.GetItemClassInfo(rule.classID) or "?"
    if rule.subClassID then
        local subName = C_Item.GetItemSubClassInfo(rule.classID, rule.subClassID) or "?"
        return string.format("%s: %s > %s", modeLabel, className, subName)
    end
    return string.format("%s: %s", modeLabel, className)
end

local function RefreshCategoryRulesList()
    local content = tabEditor.rulesContent
    tabEditor.ruleRows = tabEditor.ruleRows or {}

    for i, rule in ipairs(editorState.categoryRules) do
        local row = tabEditor.ruleRows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetSize(1, RULE_ROW_HEIGHT)

            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetJustifyH("LEFT")

            row.removeButton = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
            row.removeButton:SetSize(16, 16)
            row.removeButton:SetPoint("RIGHT")

            tabEditor.ruleRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * RULE_ROW_HEIGHT)
        row:SetPoint("RIGHT")
        row.text:SetText(DescribeRule(rule))
        row.removeButton:SetScript("OnClick", function()
            table.remove(editorState.categoryRules, i)
            RefreshCategoryRulesList()
        end)
        row:Show()
    end

    for i = #editorState.categoryRules + 1, #tabEditor.ruleRows do
        tabEditor.ruleRows[i]:Hide()
    end

    content:SetHeight(math.max(#editorState.categoryRules, 1) * RULE_ROW_HEIGHT)
end

local function BuildClassMenu(dropdown, rootDescription)
    local function IsSelected(classID)
        return editorState.pendingClassID == classID
    end
    local function SetSelected(classID)
        editorState.pendingClassID = classID
        editorState.pendingSubClassID = nil
        tabEditor.subClassDropdown:GenerateMenu()
    end

    -- "All Categories" (a real, explicit rule target, not just an inferred
    -- default) lets a tab say e.g. Show: All + Hide: Weapon > Sword to mean
    -- "everything except swords".
    rootDescription:CreateRadio(L.ALL_CATEGORIES, IsSelected, SetSelected, Embolsao.Filters.ALL_CATEGORIES)

    for _, class in ipairs(Embolsao.Filters:GetItemClasses()) do
        rootDescription:CreateRadio(class.name, IsSelected, SetSelected, class.classID)
    end
end

local function BuildSubClassMenu(dropdown, rootDescription)
    local function IsSelected(subClassID)
        return editorState.pendingSubClassID == subClassID
    end
    local function SetSelected(subClassID)
        editorState.pendingSubClassID = subClassID
    end

    rootDescription:CreateRadio(L.ANY_SUBCATEGORY, IsSelected, SetSelected, nil)

    -- Subcategories don't make sense under "All Categories".
    if editorState.pendingClassID and editorState.pendingClassID ~= Embolsao.Filters.ALL_CATEGORIES then
        for _, subClass in ipairs(Embolsao.Filters:GetItemSubClasses(editorState.pendingClassID)) do
            rootDescription:CreateRadio(subClass.name, IsSelected, SetSelected, subClass.subClassID)
        end
    end
end

local function CreateModeToggle(parent, label, mode)
    local btn = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    btn.text = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.text:SetPoint("LEFT", btn, "RIGHT", 2, 0)
    btn.text:SetText(label)
    btn:SetScript("OnClick", function()
        editorState.pendingMode = mode
        parent.showToggle:SetChecked(mode == "show")
        parent.hideToggle:SetChecked(mode == "hide")
    end)
    return btn
end

local function EnsureTabEditor()
    if tabEditor then return tabEditor end

    tabEditor = CreateFrame("Frame", "EmbolsaoTabEditorFrame", UIParent, "BackdropTemplate")
    tabEditor:SetSize(420, 560)
    tabEditor:SetPoint("CENTER")
    tabEditor:SetFrameStrata("DIALOG")
    tabEditor:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    tabEditor:SetBackdropColor(0, 0, 0, 0.95)
    tabEditor:SetMovable(true)
    tabEditor:EnableMouse(true)
    tabEditor:RegisterForDrag("LeftButton")
    tabEditor:SetScript("OnDragStart", tabEditor.StartMoving)
    tabEditor:SetScript("OnDragStop", tabEditor.StopMovingOrSizing)
    tinsert(UISpecialFrames, "EmbolsaoTabEditorFrame")

    local close = CreateFrame("Button", nil, tabEditor, "UIPanelCloseButtonDefaultAnchors")
    close:SetPoint("TOPRIGHT", -2, -2)

    tabEditor.title = tabEditor:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    tabEditor.title:SetPoint("TOP", 0, -16)

    -- Name + icon row.
    tabEditor.nameLabel = tabEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tabEditor.nameLabel:SetPoint("TOPLEFT", 20, -46)
    tabEditor.nameLabel:SetText(L.TAB_NAME)

    tabEditor.nameBox = CreateFrame("EditBox", nil, tabEditor, "InputBoxTemplate")
    tabEditor.nameBox:SetSize(260, 20)
    tabEditor.nameBox:SetAutoFocus(false)
    tabEditor.nameBox:SetPoint("TOPLEFT", tabEditor.nameLabel, "BOTTOMLEFT", 6, -6)
    tabEditor.nameBox:SetScript("OnTextChanged", function(self)
        editorState.name = self:GetText()
    end)

    tabEditor.iconButton = CreateFrame("ItemButton", nil, tabEditor)
    tabEditor.iconButton:SetSize(36, 36)
    tabEditor.iconButton:SetPoint("LEFT", tabEditor.nameBox, "RIGHT", 16, 0)
    tabEditor.iconButton:SetScript("OnClick", function()
        TabEditor:ShowIconPicker(function(icon)
            editorState.icon = icon
            SetItemButtonTexture(tabEditor.iconButton, icon)
        end)
    end)
    tabEditor.iconButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TAB_ICON)
        GameTooltip:Show()
    end)
    tabEditor.iconButton:SetScript("OnLeave", GameTooltip_Hide)

    -- Hidden items section.
    tabEditor.itemsLabel = tabEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tabEditor.itemsLabel:SetPoint("TOPLEFT", 20, -96)
    tabEditor.itemsLabel:SetText(L.HIDDEN_ITEMS)

    tabEditor.itemDropZone = CreateFrame("Frame", nil, tabEditor, "BackdropTemplate")
    tabEditor.itemDropZone:SetPoint("TOPLEFT", 20, -114)
    tabEditor.itemDropZone:SetPoint("RIGHT", -20, 0)
    tabEditor.itemDropZone:SetHeight(36)
    tabEditor.itemDropZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })
    tabEditor.itemDropZone:SetBackdropColor(1, 1, 1, 0.05)
    tabEditor.itemDropZone:SetBackdropBorderColor(1, 1, 1, 0.3)
    tabEditor.itemDropZone:EnableMouse(true)
    tabEditor.itemDropZone:SetScript("OnReceiveDrag", TryAddCursorItemToHidden)
    tabEditor.itemDropZone:SetScript("OnMouseUp", function()
        if CursorHasItem() then
            TryAddCursorItemToHidden()
        end
    end)
    tabEditor.itemDropZone.hint = tabEditor.itemDropZone:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tabEditor.itemDropZone.hint:SetPoint("CENTER")
    tabEditor.itemDropZone.hint:SetText(L.HIDDEN_ITEMS_DESC)
    tabEditor.itemDropZone.hint:SetJustifyH("CENTER")
    tabEditor.itemDropZone.hint:SetWidth(340)

    tabEditor.itemsScrollFrame = CreateFrame("ScrollFrame", nil, tabEditor, "UIPanelScrollFrameTemplate")
    tabEditor.itemsScrollFrame:SetPoint("TOPLEFT", tabEditor.itemDropZone, "BOTTOMLEFT", 0, -8)
    tabEditor.itemsScrollFrame:SetPoint("RIGHT", -20 - 22, 0)
    tabEditor.itemsScrollFrame:SetHeight(70)

    tabEditor.itemsContent = CreateFrame("Frame", nil, tabEditor.itemsScrollFrame)
    tabEditor.itemsContent:SetPoint("TOPLEFT")
    tabEditor.itemsContent:SetSize(1, 1)
    tabEditor.itemsScrollFrame:SetScrollChild(tabEditor.itemsContent)

    -- Categories section.
    tabEditor.categoriesLabel = tabEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tabEditor.categoriesLabel:SetPoint("TOPLEFT", tabEditor.itemsScrollFrame, "BOTTOMLEFT", 0, -14)
    tabEditor.categoriesLabel:SetText(L.CATEGORIES)

    tabEditor.classDropdown = CreateFrame("DropdownButton", nil, tabEditor, "WowStyle1DropdownTemplate")
    tabEditor.classDropdown:SetPoint("TOPLEFT", tabEditor.categoriesLabel, "BOTTOMLEFT", -4, -6)
    tabEditor.classDropdown:SetWidth(150)
    tabEditor.classDropdown:SetDefaultText(L.CATEGORY)
    tabEditor.classDropdown:SetupMenu(BuildClassMenu)

    tabEditor.subClassDropdown = CreateFrame("DropdownButton", nil, tabEditor, "WowStyle1DropdownTemplate")
    tabEditor.subClassDropdown:SetPoint("LEFT", tabEditor.classDropdown, "RIGHT", 8, 0)
    tabEditor.subClassDropdown:SetWidth(150)
    tabEditor.subClassDropdown:SetDefaultText(L.SUBCATEGORY)
    tabEditor.subClassDropdown:SetupMenu(BuildSubClassMenu)

    tabEditor.showToggle = CreateModeToggle(tabEditor, L.RULE_MODE_SHOW, "show")
    tabEditor.showToggle:SetPoint("TOPLEFT", tabEditor.classDropdown, "BOTTOMLEFT", 4, -8)
    tabEditor.hideToggle = CreateModeToggle(tabEditor, L.RULE_MODE_HIDE, "hide")
    tabEditor.hideToggle:SetPoint("LEFT", tabEditor.showToggle.text, "RIGHT", 16, 0)

    tabEditor.addRuleButton = CreateFrame("Button", nil, tabEditor, "UIPanelButtonTemplate")
    tabEditor.addRuleButton:SetSize(70, 22)
    tabEditor.addRuleButton:SetPoint("LEFT", tabEditor.hideToggle.text, "RIGHT", 20, 0)
    tabEditor.addRuleButton:SetText(L.ADD)
    tabEditor.addRuleButton:SetScript("OnClick", function()
        if not editorState.pendingClassID then return end
        table.insert(editorState.categoryRules, {
            classID = editorState.pendingClassID,
            subClassID = editorState.pendingSubClassID,
            mode = editorState.pendingMode,
        })
        RefreshCategoryRulesList()
    end)

    tabEditor.rulesScrollFrame = CreateFrame("ScrollFrame", nil, tabEditor, "UIPanelScrollFrameTemplate")
    tabEditor.rulesScrollFrame:SetPoint("TOPLEFT", tabEditor.showToggle, "BOTTOMLEFT", -4, -14)
    tabEditor.rulesScrollFrame:SetPoint("RIGHT", -20 - 22, 0)
    tabEditor.rulesScrollFrame:SetHeight(110)

    tabEditor.rulesContent = CreateFrame("Frame", nil, tabEditor.rulesScrollFrame)
    tabEditor.rulesContent:SetPoint("TOPLEFT")
    tabEditor.rulesContent:SetSize(1, 1)
    tabEditor.rulesScrollFrame:SetScrollChild(tabEditor.rulesContent)

    -- Footer buttons.
    tabEditor.cancelButton = CreateFrame("Button", nil, tabEditor, "UIPanelButtonTemplate")
    tabEditor.cancelButton:SetSize(100, 22)
    tabEditor.cancelButton:SetPoint("BOTTOMRIGHT", -20, 16)
    tabEditor.cancelButton:SetText(L.CANCEL)
    tabEditor.cancelButton:SetScript("OnClick", function() tabEditor:Hide() end)

    tabEditor.saveButton = CreateFrame("Button", nil, tabEditor, "UIPanelButtonTemplate")
    tabEditor.saveButton:SetSize(100, 22)
    tabEditor.saveButton:SetPoint("RIGHT", tabEditor.cancelButton, "LEFT", -8, 0)
    tabEditor.saveButton:SetScript("OnClick", function()
        local name = strtrim(editorState.name or "")
        if name == "" then
            UIErrorsFrame:AddMessage(L.TAB_NAME_REQUIRED, 1, 0.2, 0.2)
            return
        end

        local data = {
            name = name,
            icon = editorState.icon,
            hiddenItemIDs = editorState.hiddenItemIDs,
            categoryRules = editorState.categoryRules,
        }

        if editorState.id then
            Embolsao.Filters:UpdateCustomTab(editorState.id, data)
        else
            Embolsao.Filters:CreateCustomTab(data)
        end

        Embolsao.UI:BuildTabs()
        Embolsao.UI:Refresh()
        tabEditor:Hide()
    end)

    return tabEditor
end

function TabEditor:Show(tabID)
    local editor = EnsureTabEditor()
    local existingTab = tabID and Embolsao.Filters:GetCustomTab(tabID)

    ResetEditorState(existingTab)

    editor.title:SetText(existingTab and L.EDIT_TAB_TITLE or L.CREATE_TAB_TITLE)
    editor.nameBox:SetText(editorState.name)
    SetItemButtonTexture(editor.iconButton, editorState.icon)
    editor.saveButton:SetText(existingTab and L.UPDATE or L.CREATE)
    editor.showToggle:SetChecked(true)
    editor.hideToggle:SetChecked(false)
    editor.classDropdown:GenerateMenu()
    editor.subClassDropdown:GenerateMenu()

    RefreshHiddenItemsList()
    RefreshCategoryRulesList()

    editor:Show()
end

--------------------------------------------------------------------------
-- Right-click context menu for a tab button (built-in or custom).
--------------------------------------------------------------------------

StaticPopupDialogs["EMBOLSAO_DELETE_TAB"] = {
    text = L.TAB_DELETE_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, tabID)
        Embolsao.Filters:DeleteCustomTab(tabID)
        Embolsao.UI:BuildTabs()
        Embolsao.UI:Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function TabEditor:ShowTabContextMenu(owner, tabData)
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        rootDescription:CreateTitle(tabData.name)

        if not tabData.isBuiltIn then
            rootDescription:CreateButton(L.TAB_EDIT, function()
                TabEditor:Show(tabData.id)
            end)
        end

        -- "All" can't be hidden -- no point offering the toggle for it.
        if tabData.id ~= "ALL" then
            rootDescription:CreateButton(tabData.hidden and L.TAB_SHOW or L.TAB_HIDE, function()
                Embolsao.Filters:SetTabHidden(tabData.id, not tabData.hidden)
                Embolsao.UI:BuildTabs()
                Embolsao.UI:Refresh()
            end)
        end

        if not tabData.isBuiltIn then
            rootDescription:CreateButton(L.TAB_DELETE, function()
                StaticPopup_Show("EMBOLSAO_DELETE_TAB", tabData.name, nil, tabData.id)
            end)
        end
    end)
end
