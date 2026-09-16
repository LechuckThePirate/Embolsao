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
    MENU_TOOLTIP = "Menú",
    SORT_BY = "Ordenar por",
    SORT_NAME = "Nombre",
    SORT_QUANTITY = "Cantidad",
    SORT_QUALITY = "Calidad",
    SORT_TYPE = "Tipo",
    SORT_ASCENDING = "Ascendente",
    SORT_DESCENDING = "Descendente",
    PREFERENCES = "Preferencias",
    DEFAULT_TAB = "Pestaña por defecto",
    LAST_SELECTED = "Última seleccionada",
    CONSOLIDATE_STACKS = "Consolidar stacks",
    REMEMBER_POSITION = "Recordar posición de la ventana",
    ABOUT = "Acerca de",
    ABOUT_URL_LABEL = "Consíguelo en CurseForge (clic para seleccionar, luego Ctrl+C):",
}

for key, value in pairs(strings) do
    L[key] = value
end
