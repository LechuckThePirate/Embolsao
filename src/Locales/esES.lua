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
    EMPTY_SLOT_TITLE = "Hueco vacío",
    EMPTY_SLOT_DESC = "Suelta aquí un ítem para colocarlo en un hueco vacío de la bolsa.",
}

for key, value in pairs(strings) do
    L[key] = value
end
