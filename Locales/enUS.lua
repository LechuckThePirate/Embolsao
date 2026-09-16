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
}

for key, value in pairs(strings) do
    L[key] = value
end
