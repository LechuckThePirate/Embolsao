local ADDON_NAME, Embolsao = ...

local locale = GetLocale()
if locale ~= "esES" and locale ~= "esMX" then return end

local L = Embolsao.L

local strings = {
    ALL = "Todo",
    WEAPONS = "Armas",
    GEAR = "Equipo",
    CONSUMABLES = "Consumibles",
    TRADEGOODS = "Comercio",
    QUESTITEMS = "Misión",
    MISC = "Miscelánea",
}

for key, value in pairs(strings) do
    L[key] = value
end
