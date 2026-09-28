-- Layout constants shared by more than one file (UI.lua and Layout.lua). Loaded
-- before both; anything only UI.lua needs stays a local there.
local _, Embolsao = ...

Embolsao.UIConst = {
    ITEM_SIZE = 37,
    ITEM_PADDING = 4,
    HEADER_ROW_HEIGHT = 20, -- Sort By Type class/subclass separators
    GROUP_GAP_HEIGHT = 10, -- vertical space closing off the pinned "Recent" group
    SCROLLBAR_CLEARANCE = 22, -- UIPanelScrollFrameTemplate's bar sits this far outside the frame
}
