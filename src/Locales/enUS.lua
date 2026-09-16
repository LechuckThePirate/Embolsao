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
}

for key, value in pairs(strings) do
    L[key] = value
end
