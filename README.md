# Embolsao!!

Addon de World of Warcraft (Retail) que mejora el sistema de bolsa única: pestañas de
filtrado por categoría (Todo, Armas, Equipo, Consumibles, Comercio, Misión, Miscelánea)
y pestañas personalizadas por `itemID` y/o categoría/subcategoría.

Un pequeño guiño a [Apparcao](https://apparcao.com).

## Estructura del repo

- `src/` — código del addon (`Embolsao.toc`, `Core.lua`, `Filters.lua`, `UI.lua`, `icons/`).
  Esta es la carpeta que se empaqueta como `Embolsao/` al instalar o publicar.
- `images/` — arte fuente del icono (sin recortar/procesar).

## Cómo funciona

- `Core.lua` escanea todas las bolsas vía `C_Container` y agrupa los ítems idénticos
  en un inventario virtual (`Embolsao.VirtualInventory`), sumando cantidades entre stacks.
- `Filters.lua` define las pestañas built-in (por `Enum.ItemClass`) y la lógica de
  matching de pestañas personalizadas (`EmbolsaoDB.customTabs`), que pueden combinar
  categorías/subcategorías enteras, overrides por `itemID` y, opcionalmente, la lista
  compartida de ítems ignorados (`useIgnoredList`).
- `UI.lua` crea un marco básico enganchado tanto a `ContainerFrameCombinedBags` (modo
  bolsa única) como a `ContainerFrame1` (modo bolsas legacy), ancla al que esté visible
  en cada momento, y muestra el inventario virtual filtrado por la pestaña activa.

## Instalación (desarrollo)

Copia o enlaza la carpeta `src/` como `Embolsao` dentro de:

```
World of Warcraft/_retail_/Interface/AddOns/Embolsao/
```

## Estado

Estructura base / work in progress. Sin editor in-game todavía para crear pestañas
personalizadas (por ahora se definen a mano en `EmbolsaoDB.customTabs`).
