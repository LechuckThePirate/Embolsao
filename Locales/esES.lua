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

    MANAGE_TABS = "Gestionar pestañas",
    NEW_TAB_TOOLTIP = "Nueva pestaña personalizada",
    TAB_EDIT = "Editar",
    TAB_HIDE = "Ocultar",
    TAB_SHOW = "Mostrar",
    TAB_DELETE = "Borrar",
    TAB_DELETE_CONFIRM = "¿Borrar la pestaña \"%s\"? No se puede deshacer.",
    CREATE_TAB_TITLE = "Crear pestaña personalizada",
    EDIT_TAB_TITLE = "Editar pestaña personalizada",
    TAB_NAME = "Nombre",
    TAB_ICON = "Icono",
    SELECT_ICON = "Seleccionar icono",
    HIDDEN_ITEMS = "Ítems ocultos",
    HIDDEN_ITEMS_DESC = "Arrastra ítems desde la bolsa aquí para ocultarlos en esta pestaña.",
    CATEGORIES = "Categorías",
    CATEGORY = "Categoría",
    SUBCATEGORY = "Subcategoría (opcional)",
    ANY_SUBCATEGORY = "Cualquiera",
    RULE_MODE_SHOW = "Mostrar",
    RULE_MODE_HIDE = "Ocultar",
    ADD = "Añadir",
    CREATE = "Crear",
    UPDATE = "Actualizar",
    CANCEL = "Cancelar",
    TAB_NAME_REQUIRED = "Ponle antes un nombre a la pestaña.",
}

for key, value in pairs(strings) do
    L[key] = value
end
