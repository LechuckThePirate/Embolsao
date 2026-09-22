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

-- Search. The catalog has no icon names as such, but every icon has a file
-- name ("inv_misc_bag_08", "spell_nature_healingtouch", "inv_pick_02"...)
-- that says what it depicts, so the search box matches words against those
-- (English -- they're file names, not localized). Looking every name up is
-- thousands of C_Texture calls, so it happens once, on the first search of
-- the session, and the lower-cased names are cached.
local iconNames -- [provider index] = lower-case file name

-- Whether the client can turn an icon's fileDataID into a real file name.
-- Having the function isn't enough: the Classic "Forever" client (verified)
-- has it but answers "FileData ID 134400" -- a placeholder, not a name -- so
-- there is nothing to search. Probe it with the well-known question-mark icon.
local function CanSearchIcons()
    if not (C_Texture and C_Texture.GetFilenameFromFileDataID) then return false end
    local name = C_Texture.GetFilenameFromFileDataID(134400)
    return type(name) == "string" and name ~= "" and not name:find("^FileData ID")
end

local function GetIconFileName(icon)
    local name = icon
    if type(icon) == "number" then
        name = C_Texture.GetFilenameFromFileDataID(icon)
    end
    -- "FileData ID 123" is the client's placeholder for a file it has no name
    -- for -- treat it as nameless, or the words in it would match everything.
    if type(name) ~= "string" or name:find("^FileData ID") then return "" end
    return name:lower():match("([^\\/]+)$") or ""
end

local function EnsureIconNames(provider)
    if iconNames then return iconNames end
    iconNames = {}
    for i = 1, provider:GetNumIcons() do
        iconNames[i] = GetIconFileName(provider:GetIconByIndex(i))
    end
    return iconNames
end

local RenderIconPage

-- Every word typed has to appear in the file name. An empty query clears the
-- filter (iconPicker.filtered = nil means "the whole catalog"); otherwise it
-- holds the matching provider indices. Returns how many matched.
local function ApplyIconSearch(query)
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if query == "" or not CanSearchIcons() then
        iconPicker.filtered = nil
    else
        local names = EnsureIconNames(iconPicker.iconProvider)
        local words = {}
        for word in query:gmatch("%S+") do
            table.insert(words, word)
        end

        local results = {}
        for index = 1, #names do
            local name = names[index]
            local matchesAll = true
            for _, word in ipairs(words) do
                if not name:find(word, 1, true) then
                    matchesAll = false
                    break
                end
            end
            if matchesAll then
                table.insert(results, index)
            end
        end
        iconPicker.filtered = results
    end

    iconPicker.page = 1
    RenderIconPage()
    return iconPicker.filtered and #iconPicker.filtered or iconPicker.iconProvider:GetNumIcons()
end

function RenderIconPage()
    local filtered = iconPicker.filtered
    local numIcons = filtered and #filtered or iconPicker.iconProvider:GetNumIcons()
    local maxPage = math.max(1, math.ceil(numIcons / ICONS_PER_PAGE))
    iconPicker.page = math.min(math.max(iconPicker.page, 1), maxPage)
    iconPicker.noResults:SetShown(numIcons == 0)

    local startIndex = (iconPicker.page - 1) * ICONS_PER_PAGE
    for i = 1, ICONS_PER_PAGE do
        local iconIndex = startIndex + i
        local btn = iconPicker.buttons[i]
        if iconIndex <= numIcons then
            local icon = iconPicker.iconProvider:GetIconByIndex(filtered and filtered[iconIndex] or iconIndex)
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
    iconPicker:SetSize(gridWidth + 40, gridHeight + 140)
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

    -- Search box under the title; typing filters after a short pause instead
    -- of on every keystroke (a search walks the whole catalog).
    iconPicker.searchBox = CreateFrame("EditBox", nil, iconPicker, "InputBoxTemplate")
    iconPicker.searchBox:SetSize(gridWidth - 20, 20)
    iconPicker.searchBox:SetPoint("TOP", 0, -46)
    iconPicker.searchBox:SetAutoFocus(false)
    iconPicker.searchBox:SetMaxLetters(60)

    iconPicker.searchHint = iconPicker.searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    iconPicker.searchHint:SetPoint("LEFT", 2, 0)
    iconPicker.searchHint:SetText(L.SEARCH_ICONS_HINT)

    local searchToken = 0
    iconPicker.searchBox:SetScript("OnTextChanged", function(self, userInput)
        iconPicker.searchHint:SetShown(self:GetText() == "")
        if not userInput then return end
        searchToken = searchToken + 1
        local token = searchToken
        C_Timer.After(0.25, function()
            if token == searchToken then
                ApplyIconSearch(self:GetText())
            end
        end)
    end)
    iconPicker.searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    iconPicker.searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    iconPicker.grid = CreateFrame("Frame", nil, iconPicker)
    iconPicker.grid:SetSize(gridWidth, gridHeight)
    iconPicker.grid:SetPoint("TOP", 0, -76)

    iconPicker.noResults = iconPicker.grid:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    iconPicker.noResults:SetPoint("CENTER")
    iconPicker.noResults:SetText(L.NO_ICONS_FOUND)
    iconPicker.noResults:Hide()

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
--
-- suggestedName (optional): the tab's own name. If any icon's file name
-- matches it ("Potions" -> the potion icons), the picker opens already
-- filtered to those, saving the scroll through the whole catalog; if nothing
-- matches (or the name isn't English) it just opens on everything.
function TabEditor:ShowIconPicker(onSelect, suggestedName)
    local popup = EnsureIconPicker()

    if not popup.iconProvider then
        popup.iconProvider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.None)
    end

    popup.onSelect = onSelect
    popup.page = 1
    popup.filtered = nil
    popup.searchBox:SetText("")
    popup.searchBox:SetShown(CanSearchIcons())

    local suggestion = (suggestedName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if suggestion ~= "" and CanSearchIcons() and ApplyIconSearch(suggestion) > 0 then
        popup.searchBox:SetText(suggestion)
    else
        ApplyIconSearch("")
    end
    popup:Show()
end

--------------------------------------------------------------------------
-- Create/Edit Tab window
--------------------------------------------------------------------------

local ITEM_ROW_HEIGHT = 26
local ITEM_CELL_WIDTH = 50 -- icon (22) + remove button (18) + breathing room
local ITEM_LIST_FALLBACK_WIDTH = 358 -- scroll area width, used before the frame has been laid out
local RULE_ROW_HEIGHT = 20

local tabEditor
-- { id (nil if creating), name, icon, hiddenItemIDs = {[itemID]=true}, categoryRules = {}, advancedFilters = {} }
-- Must be a real table from file load, not just set lazily in ResetEditorState:
-- creating the dropdowns below evaluates their menu generator once immediately
-- (to resolve initial display text), which reads editorState before Show()
-- ever gets a chance to call ResetEditorState for the first time.
local editorState = {
    hiddenItemIDs = {},
    categoryRules = {},
    advancedFilters = {},
    pendingMode = "show",
}

-- Common stat keys covered by the Advanced Filters "Stat" condition -- these
-- string constants double as both the key GetItemStats returns them under
-- AND, looked up as globals, their own localized display name (Blizzard's
-- own convention -- not something we need to localize ourselves). Spirit
-- only ever appears on pre-Legion-content items, Versatility/Mastery only on
-- retail-era ones; a client/flavor that never generates a given stat on any
-- item just never has it show up as meaningful, the dropdown itself doesn't
-- need to know which flavor it's running on.
local ADVANCED_FILTER_STAT_KEYS = {
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT",
    "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HASTE_RATING_SHORT",
    "ITEM_MOD_MASTERY_RATING_SHORT", "ITEM_MOD_VERSATILITY", "ITEM_MOD_ARMOR_SHORT",
}

local ADVANCED_FILTER_OPERATORS = { ">", ">=", "<", "<=", "==", "~=" }

-- Same convention as the stat keys above: ITEM_QUALITY0_DESC.."8_DESC" are
-- Blizzard's own globals for each quality tier's name. Stops at Legendary
-- (5) -- Artifact/Heirloom/WoW Token (6-8) aren't meaningful filter targets.
local ADVANCED_FILTER_MAX_QUALITY = 5

-- Broader rules first: All Categories, then class-only, then class+subclass.
-- Keeps the rules list reading top-to-bottom as "widest reach to narrowest",
-- which also happens to match the specificity order Filters:MatchesCustomTab
-- resolves ties with.
local function RuleSpecificity(rule)
    if rule.classID == Embolsao.Filters.ALL_CATEGORIES then return 0 end
    if not rule.subClassID then return 1 end
    return 2
end

local function SortCategoryRules(rules)
    table.sort(rules, function(a, b)
        return RuleSpecificity(a) < RuleSpecificity(b)
    end)
end

local function CopyHiddenItemIDs(source)
    local copy = {}
    for itemID in pairs(source or {}) do
        copy[itemID] = true
    end
    return copy
end

local function CopyCategoryRules(source)
    local copy = {}
    for _, rule in ipairs(source or {}) do
        table.insert(copy, { classID = rule.classID, subClassID = rule.subClassID, mode = rule.mode })
    end
    SortCategoryRules(copy)
    return copy
end

local function CopyAdvancedFilters(source)
    local copy = {}
    for _, condition in ipairs(source or {}) do
        table.insert(copy, {
            type = condition.type, statKey = condition.statKey,
            operator = condition.operator, value = condition.value,
        })
    end
    return copy
end

-- `id` is nil when creating a new custom tab. A built-in tab's name/icon
-- always come from its factory definition (not editable -- only its
-- hidden items and category rules, layered on top as an override), while a
-- custom tab's come from the saved tab itself.
--
-- `domain` ("bags" or "bank") says which pane's set of tabs this edits: each
-- pane can have its own (see Embolsao:GetFilters), and every save, delete and
-- reset in the editor goes to that set.
local function ResetEditorState(id, domain)
    local filters = Embolsao:GetFilters(domain)
    local isBuiltIn = id ~= nil and filters:IsBuiltIn(id)

    if isBuiltIn then
        local def = filters:GetBuiltInDefinition(id)
        local override = filters:GetBuiltInOverride(id)
        editorState = {
            domain = domain,
            id = id,
            isBuiltIn = true,
            name = def.name,
            icon = def.icon,
            hiddenItemIDs = CopyHiddenItemIDs(override and override.hiddenItemIDs),
            categoryRules = CopyCategoryRules(override and override.categoryRules),
            advancedFilters = CopyAdvancedFilters(override and override.advancedFilters),
        }
    elseif id then
        local existingTab = filters:GetCustomTab(id)
        editorState = {
            domain = domain,
            id = existingTab.id,
            isBuiltIn = false,
            name = existingTab.name,
            icon = existingTab.icon,
            hiddenItemIDs = CopyHiddenItemIDs(existingTab.hiddenItemIDs),
            categoryRules = CopyCategoryRules(existingTab.categoryRules),
            advancedFilters = CopyAdvancedFilters(existingTab.advancedFilters),
        }
    else
        editorState = {
            domain = domain,
            id = nil,
            isBuiltIn = false,
            name = "",
            icon = "Interface\\Icons\\INV_Misc_Bag_10",
            hiddenItemIDs = {},
            categoryRules = {},
            advancedFilters = {},
        }
    end

    -- The "add a rule" pending selection is independent of create-vs-edit --
    -- always start it fresh (this was missing for the edit path entirely,
    -- which left Add Rule silently unusable when editing an existing tab).
    editorState.pendingClassID = nil
    editorState.pendingSubClassID = nil
    editorState.pendingMode = "show"
    editorState.pendingFilterType = "quality"
    editorState.pendingFilterStatKey = ADVANCED_FILTER_STAT_KEYS[1]
    editorState.pendingFilterOperator = ">="
    editorState.pendingFilterQuality = 1
    editorState.pendingFilterValue = 0

    -- Whether the tab groups by category / subcategory while sorted by
    -- category. Kept per tab but outside the tab's own data (with its sort
    -- state, see UI:GetTabGrouping); a new tab starts from the global default.
    -- The tab's sort works the same way (mode + direction).
    if editorState.id then
        local stateID = Embolsao:GetTabStatePrefix(domain) .. editorState.id
        editorState.groupByClass, editorState.groupBySubClass = Embolsao.UI:GetTabGrouping(stateID)
        editorState.sortMode, editorState.sortAscending = Embolsao.UI:GetTabSort(stateID)
        editorState.showRecent, editorState.showJunk, editorState.showQuest = Embolsao.UI:GetTabPinnedGroups(stateID)
    else
        editorState.showRecent = Embolsao.db.showRecentCategory ~= false
        editorState.showJunk = Embolsao.db.showJunkCategory ~= false
        editorState.showQuest = Embolsao.db.showQuestCategory ~= false
        editorState.groupByClass = Embolsao.db.groupByClass == true
        editorState.groupBySubClass = Embolsao.db.groupBySubClass == true
        editorState.sortMode = Embolsao.db.sortMode
        editorState.sortAscending = Embolsao.db.sortAscending
    end
end

local function GetItemIconTexture(itemID)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
        or select(10, Embolsao.GetItemInfo(itemID))
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

    -- A grid, not one item per line: each cell is an icon plus its remove
    -- button, and as many cells fit per row as the list is wide (the list is
    -- otherwise mostly empty space to the right of each icon).
    local listWidth = tabEditor.itemsScrollFrame:GetWidth()
    if not listWidth or listWidth <= 1 then
        listWidth = ITEM_LIST_FALLBACK_WIDTH
    end
    local columns = math.max(1, math.floor(listWidth / ITEM_CELL_WIDTH))

    for i, itemID in ipairs(itemIDs) do
        local row = tabEditor.itemRows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetSize(ITEM_CELL_WIDTH, ITEM_ROW_HEIGHT)

            row.icon = CreateFrame("ItemButton", nil, row)
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT")

            row.removeButton = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
            row.removeButton:SetSize(18, 18)
            row.removeButton:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)

            tabEditor.itemRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ((i - 1) % columns) * ITEM_CELL_WIDTH, -math.floor((i - 1) / columns) * ITEM_ROW_HEIGHT)
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

    content:SetSize(columns * ITEM_CELL_WIDTH, math.max(math.ceil(#itemIDs / columns), 1) * ITEM_ROW_HEIGHT)
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

-- Dropping a bag item onto the tab's icon button makes its icon the tab's
-- icon -- a shortcut past paging the whole icon catalog. Same handshake as
-- the hidden-items drop zone above: read what's on the cursor, then give it
-- straight back to the slot it came from, since only its identity matters.
-- Returns true when the cursor held an item (used or not), so the caller
-- doesn't ALSO open the icon picker for that click.
local function TryUseCursorItemAsIcon()
    local cursorItem = C_Cursor.GetCursorItem()
    if not cursorItem then return false end
    local bagID, slot = cursorItem:GetBagAndSlot()
    if not bagID then return false end

    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if info and info.iconFileID then
        editorState.icon = info.iconFileID
        SetItemButtonTexture(tabEditor.iconButton, info.iconFileID)
    end

    C_Container.PickupContainerItem(bagID, slot)
    return true
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

    -- The scroll child starts at a nominal 1x1 size (standard for a
    -- UIPanelScrollFrameTemplate child), so a row can't get its width by
    -- anchoring to the content's own RIGHT edge -- that resolves to ~1px and
    -- silently squashes the remove button into the label, making it
    -- unclickable. Give both the content and each row an explicit width
    -- matching the scroll frame instead.
    local rowWidth = tabEditor.rulesScrollFrame:GetWidth()
    content:SetWidth(rowWidth)

    for i, rule in ipairs(editorState.categoryRules) do
        local row = tabEditor.ruleRows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)

            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetJustifyH("LEFT")

            row.removeButton = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
            row.removeButton:SetSize(16, 16)
            row.removeButton:SetPoint("RIGHT")

            tabEditor.ruleRows[i] = row
        end

        row:ClearAllPoints()
        row:SetSize(rowWidth, RULE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * RULE_ROW_HEIGHT)
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

local function DescribeAdvancedFilter(condition)
    if condition.type == "quality" then
        local qualityName = _G["ITEM_QUALITY" .. (condition.value or 0) .. "_DESC"] or tostring(condition.value)
        return string.format("%s %s %s", L.ADVANCED_FILTER_QUALITY, condition.operator, qualityName)
    end
    if condition.type == "itemLevel" then
        return string.format("%s %s %s", L.ADVANCED_FILTER_ITEM_LEVEL, condition.operator, tostring(condition.value))
    end
    local statName = _G[condition.statKey] or condition.statKey
    return string.format("%s %s %s", statName, condition.operator, tostring(condition.value))
end

local function RefreshAdvancedFilterInputs()
    local isQuality = editorState.pendingFilterType == "quality"
    local isStat = editorState.pendingFilterType == "stat"
    tabEditor.filterStatDropdown:SetShown(isStat)
    tabEditor.filterQualityDropdown:SetShown(isQuality)
    tabEditor.filterValueBox:SetShown(not isQuality)
end

local function RefreshAdvancedFiltersList()
    local content = tabEditor.advancedFiltersContent
    tabEditor.advancedFilterRows = tabEditor.advancedFilterRows or {}

    local rowWidth = tabEditor.advancedFiltersScrollFrame:GetWidth()
    content:SetWidth(rowWidth)

    for i, condition in ipairs(editorState.advancedFilters) do
        local row = tabEditor.advancedFilterRows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)

            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetJustifyH("LEFT")

            row.removeButton = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
            row.removeButton:SetSize(16, 16)
            row.removeButton:SetPoint("RIGHT")

            tabEditor.advancedFilterRows[i] = row
        end

        row:ClearAllPoints()
        row:SetSize(rowWidth, RULE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * RULE_ROW_HEIGHT)
        row.text:SetText(DescribeAdvancedFilter(condition))
        row.removeButton:SetScript("OnClick", function()
            table.remove(editorState.advancedFilters, i)
            RefreshAdvancedFiltersList()
        end)
        row:Show()
    end

    for i = #editorState.advancedFilters + 1, #tabEditor.advancedFilterRows do
        tabEditor.advancedFilterRows[i]:Hide()
    end

    content:SetHeight(math.max(#editorState.advancedFilters, 1) * RULE_ROW_HEIGHT)
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
    tabEditor:SetSize(420, 760)
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
    tabEditor.iconButton:RegisterForClicks("LeftButtonUp")
    local lastIconDropTime = 0
    tabEditor.iconButton:SetScript("OnClick", function(self)
        -- Right after a drop (OnReceiveDrag below) the item has already been
        -- handed back to its slot, so the cursor looks empty here: without
        -- this the same release could also open the picker.
        if GetTime() - lastIconDropTime < 0.3 then return end

        -- Carrying an item (picked up, or mid-drag and released here) uses
        -- its icon; an empty cursor opens the picker.
        if CursorHasItem() then
            if self:IsEnabled() then
                TryUseCursorItemAsIcon()
            end
            return
        end
        TabEditor:ShowIconPicker(function(icon)
            editorState.icon = icon
            SetItemButtonTexture(tabEditor.iconButton, icon)
        end, editorState.name)
    end)
    tabEditor.iconButton:SetScript("OnReceiveDrag", function(self)
        lastIconDropTime = GetTime()
        if self:IsEnabled() then
            TryUseCursorItemAsIcon()
        end
    end)
    tabEditor.iconButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TAB_ICON)
        GameTooltip:AddLine(L.TAB_ICON_DROP_HINT, 1, 1, 1, true)
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

        for _, rule in ipairs(editorState.categoryRules) do
            if rule.classID == editorState.pendingClassID and rule.subClassID == editorState.pendingSubClassID then
                UIErrorsFrame:AddMessage(L.RULE_DUPLICATE, 1, 0.2, 0.2)
                return
            end
        end

        table.insert(editorState.categoryRules, {
            classID = editorState.pendingClassID,
            subClassID = editorState.pendingSubClassID,
            mode = editorState.pendingMode,
        })
        SortCategoryRules(editorState.categoryRules)
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

    --------------------------------------------------------------------------
    -- Advanced Filters: quality / item level / stat conditions, AND-ed with
    -- each other and with whatever the category rules above already decided
    -- (see Filters:MatchesAdvancedFilters). A separate section rather than
    -- one more kind of category rule, since these aren't a classification --
    -- see the comment on that function for why.
    --------------------------------------------------------------------------
    tabEditor.advancedFiltersLabel = tabEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tabEditor.advancedFiltersLabel:SetPoint("TOPLEFT", tabEditor.rulesScrollFrame, "BOTTOMLEFT", 4, -14)
    tabEditor.advancedFiltersLabel:SetText(L.ADVANCED_FILTERS)

    tabEditor.filterTypeDropdown = CreateFrame("DropdownButton", nil, tabEditor, "WowStyle1DropdownTemplate")
    tabEditor.filterTypeDropdown:SetPoint("TOPLEFT", tabEditor.advancedFiltersLabel, "BOTTOMLEFT", -4, -6)
    tabEditor.filterTypeDropdown:SetWidth(140)
    tabEditor.filterTypeDropdown:SetDefaultText(L.ADVANCED_FILTER_QUALITY)
    tabEditor.filterTypeDropdown:SetupMenu(function(_, rootDescription)
        local function IsSelected(filterType) return editorState.pendingFilterType == filterType end
        local function SetSelected(filterType)
            editorState.pendingFilterType = filterType
            RefreshAdvancedFilterInputs()
        end
        rootDescription:CreateRadio(L.ADVANCED_FILTER_QUALITY, IsSelected, SetSelected, "quality")
        rootDescription:CreateRadio(L.ADVANCED_FILTER_ITEM_LEVEL, IsSelected, SetSelected, "itemLevel")
        rootDescription:CreateRadio(L.ADVANCED_FILTER_STAT, IsSelected, SetSelected, "stat")
    end)

    tabEditor.filterStatDropdown = CreateFrame("DropdownButton", nil, tabEditor, "WowStyle1DropdownTemplate")
    tabEditor.filterStatDropdown:SetPoint("LEFT", tabEditor.filterTypeDropdown, "RIGHT", 8, 0)
    tabEditor.filterStatDropdown:SetWidth(140)
    tabEditor.filterStatDropdown:SetDefaultText(_G[ADVANCED_FILTER_STAT_KEYS[1]] or ADVANCED_FILTER_STAT_KEYS[1])
    tabEditor.filterStatDropdown:SetupMenu(function(_, rootDescription)
        local function IsSelected(statKey) return editorState.pendingFilterStatKey == statKey end
        local function SetSelected(statKey) editorState.pendingFilterStatKey = statKey end
        for _, statKey in ipairs(ADVANCED_FILTER_STAT_KEYS) do
            rootDescription:CreateRadio(_G[statKey] or statKey, IsSelected, SetSelected, statKey)
        end
    end)

    tabEditor.filterOperatorDropdown = CreateFrame("DropdownButton", nil, tabEditor, "WowStyle1DropdownTemplate")
    tabEditor.filterOperatorDropdown:SetPoint("TOPLEFT", tabEditor.filterTypeDropdown, "BOTTOMLEFT", 0, -8)
    tabEditor.filterOperatorDropdown:SetWidth(70)
    tabEditor.filterOperatorDropdown:SetDefaultText(ADVANCED_FILTER_OPERATORS[2])
    tabEditor.filterOperatorDropdown:SetupMenu(function(_, rootDescription)
        local function IsSelected(operator) return editorState.pendingFilterOperator == operator end
        local function SetSelected(operator) editorState.pendingFilterOperator = operator end
        for _, operator in ipairs(ADVANCED_FILTER_OPERATORS) do
            rootDescription:CreateRadio(operator, IsSelected, SetSelected, operator)
        end
    end)

    -- Quality's "value" is itself a tier picker, not a free-typed number --
    -- shown instead of filterValueBox (same slot) when the type is Quality.
    tabEditor.filterQualityDropdown = CreateFrame("DropdownButton", nil, tabEditor, "WowStyle1DropdownTemplate")
    tabEditor.filterQualityDropdown:SetPoint("LEFT", tabEditor.filterOperatorDropdown, "RIGHT", 8, 0)
    tabEditor.filterQualityDropdown:SetWidth(120)
    tabEditor.filterQualityDropdown:SetDefaultText(_G["ITEM_QUALITY1_DESC"] or "")
    tabEditor.filterQualityDropdown:SetupMenu(function(_, rootDescription)
        local function IsSelected(quality) return editorState.pendingFilterQuality == quality end
        local function SetSelected(quality) editorState.pendingFilterQuality = quality end
        for quality = 0, ADVANCED_FILTER_MAX_QUALITY do
            rootDescription:CreateRadio(_G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality),
                IsSelected, SetSelected, quality)
        end
    end)

    tabEditor.filterValueBox = CreateFrame("EditBox", nil, tabEditor, "InputBoxTemplate")
    tabEditor.filterValueBox:SetSize(90, 20)
    tabEditor.filterValueBox:SetAutoFocus(false)
    tabEditor.filterValueBox:SetNumeric(false) -- allow a leading "-" for stat conditions
    tabEditor.filterValueBox:SetPoint("LEFT", tabEditor.filterOperatorDropdown, "RIGHT", 10, 0)
    tabEditor.filterValueBox:SetScript("OnTextChanged", function(self)
        editorState.pendingFilterValue = tonumber(self:GetText()) or 0
    end)

    tabEditor.addFilterButton = CreateFrame("Button", nil, tabEditor, "UIPanelButtonTemplate")
    tabEditor.addFilterButton:SetSize(70, 22)
    tabEditor.addFilterButton:SetPoint("LEFT", tabEditor.filterOperatorDropdown, "RIGHT", 158, 0)
    tabEditor.addFilterButton:SetText(L.ADD)
    tabEditor.addFilterButton:SetScript("OnClick", function()
        local filterType = editorState.pendingFilterType
        local condition = { type = filterType, operator = editorState.pendingFilterOperator }
        if filterType == "quality" then
            condition.value = editorState.pendingFilterQuality
        elseif filterType == "stat" then
            condition.statKey = editorState.pendingFilterStatKey
            condition.value = editorState.pendingFilterValue
        else -- itemLevel
            condition.value = editorState.pendingFilterValue
        end

        table.insert(editorState.advancedFilters, condition)
        RefreshAdvancedFiltersList()
    end)

    tabEditor.advancedFiltersScrollFrame = CreateFrame("ScrollFrame", nil, tabEditor, "UIPanelScrollFrameTemplate")
    tabEditor.advancedFiltersScrollFrame:SetPoint("TOPLEFT", tabEditor.filterOperatorDropdown, "BOTTOMLEFT", -4, -14)
    tabEditor.advancedFiltersScrollFrame:SetPoint("RIGHT", -20 - 22, 0)
    tabEditor.advancedFiltersScrollFrame:SetHeight(70)

    tabEditor.advancedFiltersContent = CreateFrame("Frame", nil, tabEditor.advancedFiltersScrollFrame)
    tabEditor.advancedFiltersContent:SetPoint("TOPLEFT")
    tabEditor.advancedFiltersContent:SetSize(1, 1)
    tabEditor.advancedFiltersScrollFrame:SetScrollChild(tabEditor.advancedFiltersContent)

    RefreshAdvancedFilterInputs()

    -- Category / subcategory grouping: the groups come first (A to Z) and the
    -- sort below orders the items inside each one.
    local function CreateGroupingCheckbox(label, stateKey, anchor)
        local check = CreateFrame("CheckButton", nil, tabEditor, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == tabEditor.advancedFiltersScrollFrame and -4 or 0,
            anchor == tabEditor.advancedFiltersScrollFrame and -8 or 0)
        check:SetScript("OnClick", function(self)
            editorState[stateKey] = self:GetChecked() and true or false
        end)
        local text = tabEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 4, 0)
        text:SetText(label)
        return check
    end
    tabEditor.groupByClassCheck = CreateGroupingCheckbox(L.MENU_GROUP_BY_CATEGORY, "groupByClass", tabEditor.advancedFiltersScrollFrame)
    tabEditor.groupBySubClassCheck = CreateGroupingCheckbox(L.MENU_GROUP_BY_SUBCATEGORY, "groupBySubClass", tabEditor.groupByClassCheck)

    -- Whether this tab pins the Recent and Junk groups on top (the second
    -- column, beside the grouping options).
    tabEditor.showRecentCheck = CreateGroupingCheckbox(L.SHOW_RECENT_SHORT, "showRecent", tabEditor.groupByClassCheck)
    tabEditor.showRecentCheck:ClearAllPoints()
    tabEditor.showRecentCheck:SetPoint("TOPLEFT", tabEditor.groupByClassCheck, "TOPLEFT", 190, 0)
    tabEditor.showJunkCheck = CreateGroupingCheckbox(L.SHOW_JUNK_SHORT, "showJunk", tabEditor.showRecentCheck)
    tabEditor.showQuestCheck = CreateGroupingCheckbox(L.SHOW_QUEST_ITEMS_SHORT, "showQuest", tabEditor.showJunkCheck)

    -- Sort: mode and direction, the same two choices as the Sort By menu.
    tabEditor.sortLabel = tabEditor:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tabEditor.sortLabel:SetPoint("TOPLEFT", tabEditor.groupBySubClassCheck, "BOTTOMLEFT", 4, -12)
    tabEditor.sortLabel:SetText(L.SORT_BY)

    tabEditor.sortModeDropdown = CreateFrame("DropdownButton", nil, tabEditor, "WowStyle1DropdownTemplate")
    tabEditor.sortModeDropdown:SetPoint("LEFT", tabEditor.sortLabel, "RIGHT", 10, 0)
    tabEditor.sortModeDropdown:SetWidth(130)
    tabEditor.sortModeDropdown:SetupMenu(function(_, rootDescription)
        local function IsSelected(mode) return editorState.sortMode == mode end
        local function SetSelected(mode) editorState.sortMode = mode end
        for _, option in ipairs(Embolsao.UI:GetSortModes()) do
            rootDescription:CreateRadio(option.label, IsSelected, SetSelected, option.id)
        end
    end)

    tabEditor.sortDirectionDropdown = CreateFrame("DropdownButton", nil, tabEditor, "WowStyle1DropdownTemplate")
    tabEditor.sortDirectionDropdown:SetPoint("LEFT", tabEditor.sortModeDropdown, "RIGHT", 6, 0)
    tabEditor.sortDirectionDropdown:SetWidth(120)
    tabEditor.sortDirectionDropdown:SetupMenu(function(_, rootDescription)
        local function IsSelected(ascending) return editorState.sortAscending == ascending end
        local function SetSelected(ascending) editorState.sortAscending = ascending end
        rootDescription:CreateRadio(L.SORT_ASCENDING, IsSelected, SetSelected, true)
        rootDescription:CreateRadio(L.SORT_DESCENDING, IsSelected, SetSelected, false)
    end)

    -- Footer buttons. Reset (built-in tabs only) sits on the opposite side
    -- from Save/Cancel so it doesn't get mistaken for one of them.
    tabEditor.resetButton = CreateFrame("Button", nil, tabEditor, "UIPanelButtonTemplate")
    tabEditor.resetButton:SetSize(100, 22)
    tabEditor.resetButton:SetPoint("BOTTOMLEFT", 20, 16)
    tabEditor.resetButton:SetText(L.RESET)
    tabEditor.resetButton:SetScript("OnClick", function()
        StaticPopup_Show("EMBOLSAO_RESET_BUILTIN_TAB", editorState.name, nil,
            { tabID = editorState.id, domain = editorState.domain })
    end)

    tabEditor.cancelButton = CreateFrame("Button", nil, tabEditor, "UIPanelButtonTemplate")
    tabEditor.cancelButton:SetSize(100, 22)
    tabEditor.cancelButton:SetPoint("BOTTOMRIGHT", -20, 16)
    tabEditor.cancelButton:SetText(L.CANCEL)
    tabEditor.cancelButton:SetScript("OnClick", function() tabEditor:Hide() end)

    tabEditor.saveButton = CreateFrame("Button", nil, tabEditor, "UIPanelButtonTemplate")
    tabEditor.saveButton:SetSize(100, 22)
    tabEditor.saveButton:SetPoint("RIGHT", tabEditor.cancelButton, "LEFT", -8, 0)
    tabEditor.saveButton:SetScript("OnClick", function()
        -- Built-in tabs only ever save the hidden items / category rules
        -- overlay -- name and icon are fixed, so there's nothing to
        -- validate or pass along for them.
        local filters = Embolsao:GetFilters(editorState.domain)
        local statePrefix = Embolsao:GetTabStatePrefix(editorState.domain)
        if editorState.isBuiltIn then
            filters:UpdateBuiltInOverride(editorState.id, {
                hiddenItemIDs = editorState.hiddenItemIDs,
                categoryRules = editorState.categoryRules,
                advancedFilters = editorState.advancedFilters,
            })
            Embolsao.UI:SetTabGrouping(statePrefix .. editorState.id,
                editorState.groupByClass, editorState.groupBySubClass)
            Embolsao.UI:SetTabSort(statePrefix .. editorState.id,
                editorState.sortMode, editorState.sortAscending)
            Embolsao.UI:SetTabPinnedGroups(statePrefix .. editorState.id,
                editorState.showRecent, editorState.showJunk, editorState.showQuest)
        else
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
                advancedFilters = editorState.advancedFilters,
            }

            local tabID = editorState.id
            if tabID then
                filters:UpdateCustomTab(tabID, data)
            else
                tabID = filters:CreateCustomTab(data).id
            end
            Embolsao.UI:SetTabGrouping(statePrefix .. tabID,
                editorState.groupByClass, editorState.groupBySubClass)
            Embolsao.UI:SetTabSort(statePrefix .. tabID,
                editorState.sortMode, editorState.sortAscending)
            Embolsao.UI:SetTabPinnedGroups(statePrefix .. tabID,
                editorState.showRecent, editorState.showJunk, editorState.showQuest)
        end

        Embolsao.UI:BuildTabs()
        Embolsao.UI:Refresh()
        tabEditor:Hide()
    end)

    return tabEditor
end

function TabEditor:Show(tabID, domain)
    local editor = EnsureTabEditor()

    ResetEditorState(tabID, domain)

    local isBuiltIn = editorState.isBuiltIn
    local isEditing = tabID ~= nil

    if isEditing then
        editor.title:SetText(isBuiltIn and L.EDIT_BUILTIN_TAB_TITLE or L.EDIT_TAB_TITLE)
    else
        editor.title:SetText(L.CREATE_TAB_TITLE)
    end

    editor.nameBox:SetText(editorState.name)
    editor.nameBox:EnableMouse(not isBuiltIn)
    SetItemButtonTexture(editor.iconButton, editorState.icon)
    editor.iconButton:SetEnabled(not isBuiltIn)
    editor.saveButton:SetText(isEditing and L.UPDATE or L.CREATE)
    editor.resetButton:SetShown(isBuiltIn)
    editor.showToggle:SetChecked(true)
    editor.hideToggle:SetChecked(false)
    editor.classDropdown:GenerateMenu()
    editor.subClassDropdown:GenerateMenu()
    editor.groupByClassCheck:SetChecked(editorState.groupByClass)
    editor.groupBySubClassCheck:SetChecked(editorState.groupBySubClass)
    editor.showRecentCheck:SetChecked(editorState.showRecent)
    editor.showJunkCheck:SetChecked(editorState.showJunk)
    editor.showQuestCheck:SetChecked(editorState.showQuest)
    editor.sortModeDropdown:GenerateMenu()
    editor.sortDirectionDropdown:GenerateMenu()

    editor.filterTypeDropdown:GenerateMenu()
    editor.filterStatDropdown:GenerateMenu()
    editor.filterOperatorDropdown:GenerateMenu()
    editor.filterQualityDropdown:GenerateMenu()
    editor.filterValueBox:SetText("")
    RefreshAdvancedFilterInputs()

    RefreshHiddenItemsList()
    RefreshCategoryRulesList()
    RefreshAdvancedFiltersList()

    editor:Show()
end

--------------------------------------------------------------------------
-- Right-click context menu for a tab button (built-in or custom).
--------------------------------------------------------------------------

StaticPopupDialogs["EMBOLSAO_DELETE_TAB"] = {
    text = L.TAB_DELETE_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        Embolsao:GetFilters(data.domain):DeleteCustomTab(data.tabID)
        Embolsao.UI:BuildTabs()
        Embolsao.UI:Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["EMBOLSAO_RESET_BUILTIN_TAB"] = {
    text = L.RESET_TAB_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        Embolsao:GetFilters(data.domain):ResetBuiltInOverride(data.tabID)
        Embolsao.UI:BuildTabs()
        Embolsao.UI:Refresh()
        -- Refresh the still-open editor to reflect the now-empty overlay
        -- instead of leaving it showing the just-cleared state.
        TabEditor:Show(data.tabID, data.domain)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["EMBOLSAO_HIDE_ITEM_ON_TAB"] = {
    text = L.HIDE_ITEM_CONFIRM,
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        Embolsao:GetFilters(data.domain):HideItemOnTab(data.tabID, data.itemID)
        Embolsao.UI:Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Dragging an item straight onto a tab button in the main window (instead
-- of opening the full tab editor) -- a quick shortcut, but still confirmed
-- since it's easy to miss a tab by one pixel while dragging.
function TabEditor:ConfirmHideItemOnTab(itemID, tabData, domain)
    if Embolsao:GetFilters(domain):IsItemHiddenOnTab(tabData.id, itemID) then return end
    local itemName = Embolsao.GetItemInfo(itemID) or tostring(itemID)
    StaticPopup_Show("EMBOLSAO_HIDE_ITEM_ON_TAB", itemName, tabData.name,
        { itemID = itemID, tabID = tabData.id, domain = domain })
end

-- domain: which pane's set of tabs `tabData` belongs to ("bags" or "bank").
function TabEditor:ShowTabContextMenu(owner, tabData, domain)
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        rootDescription:CreateTitle(tabData.name)

        rootDescription:CreateButton(L.TAB_EDIT, function()
            TabEditor:Show(tabData.id, domain)
        end)

        -- "All" can't be hidden -- no point offering the toggle for it.
        if tabData.id ~= "ALL" then
            rootDescription:CreateButton(tabData.hidden and L.TAB_SHOW or L.TAB_HIDE, function()
                Embolsao:GetFilters(domain):SetTabHidden(tabData.id, not tabData.hidden)
                Embolsao.UI:BuildTabs()
                Embolsao.UI:Refresh()
            end)
        end

        if not tabData.isBuiltIn then
            rootDescription:CreateButton(L.TAB_DELETE, function()
                StaticPopup_Show("EMBOLSAO_DELETE_TAB", tabData.name, nil, { tabID = tabData.id, domain = domain })
            end)
        end
    end)
end
