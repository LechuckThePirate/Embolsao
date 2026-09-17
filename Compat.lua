local ADDON_NAME, Embolsao = ...

-- WOW_PROJECT_ID is Blizzard's own global for exactly this: set once at
-- client startup, never changes, so this only needs to run once here rather
-- than being checked ad hoc all over the codebase.
Embolsao.IsClassic = WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE

-- The "flat" portrait template is retail-only -- Classic (Era and every
-- progression flavor alike) only ships the older textured PortraitFrameTemplate.
-- Both inherit the same PortraitFrameMixin underneath (SetPortraitToAsset,
-- SetTitle, etc. all work identically either way), so this is the only
-- thing that actually needs to branch to create the right kind of window.
Embolsao.PORTRAIT_FRAME_TEMPLATE = Embolsao.IsClassic and "PortraitFrameTemplate" or "PortraitFrameFlatTemplate"
