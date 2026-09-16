local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

-- Base locale: always loaded first, defines every string. Locale-specific
-- files only need to override the keys they translate.
local strings = {
    ALL = "All",
    WEAPONS = "Weapons",
    GEAR = "Gear",
    CONSUMABLES = "Consumables",
    TRADEGOODS = "Trade Goods",
    QUESTITEMS = "Quest Items",
    MISC = "Misc",
    EMPTY_SLOT_TITLE = "Empty Slot",
    EMPTY_SLOT_DESC = "Drop an item here to place it in an empty bag slot.",
    MENU_TOOLTIP = "Menu",
    SORT_BY = "Sort By",
    SORT_NAME = "Name",
    SORT_QUANTITY = "Quantity",
    SORT_QUALITY = "Quality",
    SORT_TYPE = "Type",
    SORT_ASCENDING = "Ascending",
    SORT_DESCENDING = "Descending",
    PREFERENCES = "Preferences",
    DEFAULT_TAB = "Default Tab",
    LAST_SELECTED = "Last Selected",
    CONSOLIDATE_STACKS = "Consolidate Stacks",
    REMEMBER_POSITION = "Remember Window Position",
    ABOUT = "About",
    ABOUT_URL_LABEL = "Get it on CurseForge (click to select, then Ctrl+C):",

    MANAGE_TABS = "Manage Tabs",
    NEW_TAB_TOOLTIP = "New custom tab",
    TAB_EDIT = "Edit",
    TAB_HIDE = "Hide",
    TAB_SHOW = "Show",
    TAB_DELETE = "Delete",
    TAB_DELETE_CONFIRM = "Delete the tab \"%s\"? This can't be undone.",
    CREATE_TAB_TITLE = "Create Custom Tab",
    EDIT_TAB_TITLE = "Edit Custom Tab",
    TAB_NAME = "Name",
    TAB_ICON = "Icon",
    SELECT_ICON = "Select Icon",
    HIDDEN_ITEMS = "Hidden Items",
    HIDDEN_ITEMS_DESC = "Drag items from your bag here to hide them on this tab.",
    CATEGORIES = "Categories",
    CATEGORY = "Category",
    ALL_CATEGORIES = "All Categories",
    SUBCATEGORY = "Subcategory (optional)",
    ANY_SUBCATEGORY = "Any",
    RULE_MODE_SHOW = "Show",
    RULE_MODE_HIDE = "Hide",
    ADD = "Add",
    CREATE = "Create",
    UPDATE = "Update",
    CANCEL = "Cancel",
    TAB_NAME_REQUIRED = "Give the tab a name first.",
}

for key, value in pairs(strings) do
    L[key] = value
end
