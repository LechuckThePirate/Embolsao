-- The About window, the welcome / "What's new" window with its version notices,
-- and the changelog text they show. Split out of UI.lua (see the file-size and
-- Lua 5.1 limits notes there); loads after it, since it hangs its entry points
-- off the UI table (UI.ShowAboutFrame, UI.GetAddonVersion, UI:ShowBetaNotice).
local ADDON_NAME, Embolsao = ...
local L = Embolsao.L
local UI = Embolsao.UI

local SCROLLBAR_CLEARANCE = Embolsao.UIConst.SCROLLBAR_CLEARANCE

local PORTRAIT_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icons\\embolsao-icon.png"

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/embolsao"
local FEEDBACK_EMAIL = "lechuckthepirate@gmail.com"

-- Mirrors the latest entry in CHANGELOG.md -- update this alongside it (and
-- the version bump) on every release, it's shown as-is in the beta notice
-- popup's changelog box.
local LATEST_CHANGELOG_TEXT = [[
- The Classic "Forever" beta client has fixed its saved-settings problem, so the workaround for it is gone. Nothing changes for you: settings and tabs persist as before.]]

-- Notices for the welcome window, shown ABOVE the changelog -- for things a
-- player should know about this version that aren't a feature (a known
-- client bug, a temporary limitation...). Edit this list on each release:
-- add an entry, or delete the ones that no longer apply. Each entry is
--   key     -- the locale string holding its text (enUS.lua / esES.lua)
--   applies -- optional; the notice only shows when it returns true, so one
--              meant for a single game client doesn't bother everyone else
-- With nothing applicable the window looks exactly as before.
local VERSION_NOTICES = {
}

-- All the applicable notices as one block of text (blank line between them),
-- or "" when there are none.
local function BuildVersionNoticeText()
    local parts = {}
    for _, notice in ipairs(VERSION_NOTICES) do
        if not notice.applies or notice.applies() then
            table.insert(parts, L[notice.key])
        end
    end
    if #parts == 0 then return "" end
    return "|cffff8800" .. L.NOTICE_HEADER .. "|r\n" .. table.concat(parts, "\n\n")
end

local function GetAddonVersion()
    local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return GetMeta(ADDON_NAME, "Version") or "?"
end

local aboutFrame

-- Standalone window (not a StaticPopup -- those can't fit an icon or a
-- clickable text field) that always opens screen-centered, independent of
-- wherever the main window happens to be parked.
local function ShowAboutFrame()
    if not aboutFrame then
        aboutFrame = CreateFrame("Frame", "EmbolsaoAboutFrame", UIParent, "BackdropTemplate")
        aboutFrame:SetSize(340, 290)
        aboutFrame:SetPoint("CENTER")
        aboutFrame:SetFrameStrata("DIALOG")
        aboutFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        aboutFrame:SetBackdropColor(0, 0, 0, 0.9)
        aboutFrame:SetMovable(true)
        aboutFrame:EnableMouse(true)
        aboutFrame:RegisterForDrag("LeftButton")
        aboutFrame:SetScript("OnDragStart", aboutFrame.StartMoving)
        aboutFrame:SetScript("OnDragStop", aboutFrame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "EmbolsaoAboutFrame")

        local close = CreateFrame("Button", nil, aboutFrame, "UIPanelCloseButtonDefaultAnchors")
        close:SetPoint("TOPRIGHT", -2, -2)

        aboutFrame.icon = aboutFrame:CreateTexture(nil, "ARTWORK")
        aboutFrame.icon:SetSize(64, 64)
        aboutFrame.icon:SetPoint("TOP", 0, -24)
        aboutFrame.icon:SetTexture(PORTRAIT_ICON)

        aboutFrame.info = aboutFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        aboutFrame.info:SetPoint("TOP", aboutFrame.icon, "BOTTOM", 0, -14)
        aboutFrame.info:SetJustifyH("CENTER")

        aboutFrame.urlLabel = aboutFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        aboutFrame.urlLabel:SetPoint("TOP", aboutFrame.info, "BOTTOM", 0, -20)
        aboutFrame.urlLabel:SetText(L.ABOUT_URL_LABEL)

        -- Read-only, auto-selects its full text on click/focus so the
        -- player can Ctrl+C it -- WoW addons have no API to write to the
        -- system clipboard directly. No template/backdrop on purpose: styled
        -- to read as a plain link (blue, no border/box) rather than an
        -- obvious input field.
        aboutFrame.urlBox = CreateFrame("EditBox", nil, aboutFrame)
        aboutFrame.urlBox:SetSize(300, 20)
        aboutFrame.urlBox:SetPoint("TOP", aboutFrame.urlLabel, "BOTTOM", 0, -6)
        aboutFrame.urlBox:SetAutoFocus(false)
        aboutFrame.urlBox:SetJustifyH("CENTER")
        aboutFrame.urlBox:SetFontObject(GameFontHighlightSmall)
        aboutFrame.urlBox:SetTextColor(0.4, 0.7, 1, 1)
        aboutFrame.urlBox:SetText(CURSEFORGE_URL)
        aboutFrame.urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        aboutFrame.urlBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        aboutFrame.urlBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        aboutFrame.urlBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        aboutFrame.urlBox:SetScript("OnEnter", function(self) self:SetTextColor(0.6, 0.85, 1, 1) end)
        aboutFrame.urlBox:SetScript("OnLeave", function(self) self:SetTextColor(0.4, 0.7, 1, 1) end)

        local closeButton = CreateFrame("Button", nil, aboutFrame, "UIPanelButtonTemplate")
        closeButton:SetSize(100, 22)
        closeButton:SetPoint("BOTTOM", 0, 16)
        closeButton:SetText(CLOSE)
        closeButton:SetScript("OnClick", function() aboutFrame:Hide() end)

        -- Reopens the welcome/changelog window on demand -- otherwise, once
        -- it's been dismissed for a version, the only way back was waiting
        -- for the next release.
        local whatsNewButton = CreateFrame("Button", nil, aboutFrame, "UIPanelButtonTemplate")
        whatsNewButton:SetSize(140, 22)
        whatsNewButton:SetPoint("BOTTOM", closeButton, "TOP", 0, 6)
        whatsNewButton:SetText(L.WHATS_NEW)
        whatsNewButton:SetScript("OnClick", function()
            aboutFrame:Hide()
            UI:ShowBetaNotice()
        end)
    end

    local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local author = GetMeta(ADDON_NAME, "Author") or "?"
    aboutFrame.info:SetText(string.format("Embolsao!! v%s\n|cffffffffby %s|r", GetAddonVersion(), author))

    aboutFrame:Show()
end

local betaNoticeFrame

-- Shown once per login (PLAYER_LOGIN in Core.lua) until dismissed via its
-- own checkbox -- same standalone/screen-centered treatment as the About
-- window, just bigger to fit the changelog box.
local BETA_NOTICE_BASE_HEIGHT = 480

local function ShowBetaNoticeFrame()
    if not betaNoticeFrame then
        betaNoticeFrame = CreateFrame("Frame", "EmbolsaoBetaNoticeFrame", UIParent, "BackdropTemplate")
        betaNoticeFrame:SetSize(380, BETA_NOTICE_BASE_HEIGHT)
        betaNoticeFrame:SetPoint("CENTER")
        betaNoticeFrame:SetFrameStrata("DIALOG")
        betaNoticeFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        betaNoticeFrame:SetBackdropColor(0, 0, 0, 0.9)
        betaNoticeFrame:SetMovable(true)
        betaNoticeFrame:EnableMouse(true)
        betaNoticeFrame:RegisterForDrag("LeftButton")
        betaNoticeFrame:SetScript("OnDragStart", betaNoticeFrame.StartMoving)
        betaNoticeFrame:SetScript("OnDragStop", betaNoticeFrame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "EmbolsaoBetaNoticeFrame")

        local close = CreateFrame("Button", nil, betaNoticeFrame, "UIPanelCloseButtonDefaultAnchors")
        close:SetPoint("TOPRIGHT", -2, -2)

        betaNoticeFrame.icon = betaNoticeFrame:CreateTexture(nil, "ARTWORK")
        betaNoticeFrame.icon:SetSize(48, 48)
        betaNoticeFrame.icon:SetPoint("TOP", 0, -16)
        betaNoticeFrame.icon:SetTexture(PORTRAIT_ICON)

        betaNoticeFrame.title = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        betaNoticeFrame.title:SetPoint("TOP", 0, -70)
        betaNoticeFrame.title:SetText(L.BETA_NOTICE_TITLE)

        betaNoticeFrame.body = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        betaNoticeFrame.body:SetPoint("TOP", 0, -96)
        betaNoticeFrame.body:SetWidth(340)
        betaNoticeFrame.body:SetJustifyH("CENTER")
        betaNoticeFrame.body:SetText(L.BETA_NOTICE_BODY)

        -- Read-only, auto-selects its full text on click/focus so the player
        -- can Ctrl+C it, same trick as the About window's CurseForge link --
        -- there's no API to write to the system clipboard directly.
        betaNoticeFrame.emailBox = CreateFrame("EditBox", nil, betaNoticeFrame)
        betaNoticeFrame.emailBox:SetSize(300, 20)
        betaNoticeFrame.emailBox:SetPoint("TOP", betaNoticeFrame.body, "BOTTOM", 0, -10)
        betaNoticeFrame.emailBox:SetAutoFocus(false)
        betaNoticeFrame.emailBox:SetJustifyH("CENTER")
        betaNoticeFrame.emailBox:SetFontObject(GameFontHighlightSmall)
        betaNoticeFrame.emailBox:SetTextColor(0.4, 0.7, 1, 1)
        betaNoticeFrame.emailBox:SetText(FEEDBACK_EMAIL)
        betaNoticeFrame.emailBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        betaNoticeFrame.emailBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        betaNoticeFrame.emailBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        betaNoticeFrame.emailBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        betaNoticeFrame.emailBox:SetScript("OnEnter", function(self) self:SetTextColor(0.6, 0.85, 1, 1) end)
        betaNoticeFrame.emailBox:SetScript("OnLeave", function(self) self:SetTextColor(0.4, 0.7, 1, 1) end)

        -- Per-version notices (VERSION_NOTICES); laid out on every show, see
        -- ShowBetaNoticeFrame.
        betaNoticeFrame.noticeText = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        betaNoticeFrame.noticeText:SetPoint("TOP", betaNoticeFrame.emailBox, "BOTTOM", 0, -14)
        betaNoticeFrame.noticeText:SetWidth(340)
        betaNoticeFrame.noticeText:SetJustifyH("LEFT")
        betaNoticeFrame.noticeText:Hide()

        betaNoticeFrame.changelogLabel = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        betaNoticeFrame.changelogLabel:SetPoint("TOPLEFT", 20, -180)

        betaNoticeFrame.changelogScroll = CreateFrame("ScrollFrame", nil, betaNoticeFrame, "UIPanelScrollFrameTemplate")
        betaNoticeFrame.changelogScroll:SetPoint("TOPLEFT", betaNoticeFrame.changelogLabel, "BOTTOMLEFT", 0, -8)
        betaNoticeFrame.changelogScroll:SetPoint("BOTTOMRIGHT", -20 - SCROLLBAR_CLEARANCE, 56)

        betaNoticeFrame.changelogContent = CreateFrame("Frame", nil, betaNoticeFrame.changelogScroll)
        betaNoticeFrame.changelogContent:SetPoint("TOPLEFT")
        betaNoticeFrame.changelogContent:SetSize(1, 1)
        betaNoticeFrame.changelogScroll:SetScrollChild(betaNoticeFrame.changelogContent)

        betaNoticeFrame.changelogText = betaNoticeFrame.changelogContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        betaNoticeFrame.changelogText:SetPoint("TOPLEFT")
        betaNoticeFrame.changelogText:SetJustifyH("LEFT")
        betaNoticeFrame.changelogText:SetText(LATEST_CHANGELOG_TEXT)

        betaNoticeFrame.dontShowAgainCheck = CreateFrame("CheckButton", nil, betaNoticeFrame, "UICheckButtonTemplate")
        betaNoticeFrame.dontShowAgainCheck:SetSize(22, 22)
        betaNoticeFrame.dontShowAgainCheck:SetPoint("BOTTOMLEFT", 16, 16)
        -- Stores the version it was dismissed FOR, not just a bare true/false
        -- -- ticking it only silences this notice until the next release, so
        -- whatever's new (and whoever's still hitting bugs) gets seen again.
        betaNoticeFrame.dontShowAgainCheck:SetScript("OnClick", function(self)
            Embolsao.db.betaNoticeDismissedVersion = self:GetChecked() and GetAddonVersion() or ""
        end)

        betaNoticeFrame.dontShowAgainLabel = betaNoticeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        betaNoticeFrame.dontShowAgainLabel:SetPoint("LEFT", betaNoticeFrame.dontShowAgainCheck, "RIGHT", 2, 0)
        betaNoticeFrame.dontShowAgainLabel:SetText(L.DONT_SHOW_AGAIN)

        local closeButton = CreateFrame("Button", nil, betaNoticeFrame, "UIPanelButtonTemplate")
        closeButton:SetSize(90, 22)
        closeButton:SetPoint("BOTTOMRIGHT", -16, 14)
        closeButton:SetText(CLOSE)
        closeButton:SetScript("OnClick", function() betaNoticeFrame:Hide() end)
    end

    local version = GetAddonVersion()
    betaNoticeFrame.changelogLabel:SetText(string.format(L.BETA_NOTICE_CHANGELOG_LABEL, version))

    -- Notices go between the feedback line and the changelog: when there are
    -- any, the changelog label moves down below them and the window grows by
    -- the height they take (up to the screen), so the changelog box keeps its
    -- size instead of being squeezed. With none, it's laid out as it always was.
    local noticeText = BuildVersionNoticeText()
    betaNoticeFrame.changelogLabel:ClearAllPoints()
    if noticeText ~= "" then
        betaNoticeFrame.noticeText:SetText(noticeText)
        betaNoticeFrame.noticeText:Show()
        betaNoticeFrame.changelogLabel:SetPoint("TOPLEFT", betaNoticeFrame.noticeText, "BOTTOMLEFT", 0, -14)
        local extra = betaNoticeFrame.noticeText:GetStringHeight() + 14
        betaNoticeFrame:SetHeight(math.min(BETA_NOTICE_BASE_HEIGHT + extra, UIParent:GetHeight() - 40))
    else
        betaNoticeFrame.noticeText:Hide()
        betaNoticeFrame.changelogLabel:SetPoint("TOPLEFT", 20, -180)
        betaNoticeFrame:SetHeight(BETA_NOTICE_BASE_HEIGHT)
    end

    -- Wraps at the scroll frame's own width, which is only known once it's
    -- actually laid out -- text width/height has to be (re)computed on every
    -- show rather than once at creation.
    betaNoticeFrame.changelogText:SetWidth(betaNoticeFrame.changelogScroll:GetWidth())
    betaNoticeFrame.changelogContent:SetSize(
        betaNoticeFrame.changelogScroll:GetWidth(),
        betaNoticeFrame.changelogText:GetStringHeight()
    )
    betaNoticeFrame.dontShowAgainCheck:SetChecked(Embolsao.db.betaNoticeDismissedVersion == version)

    betaNoticeFrame:Show()
end

-- onlyIfNotDismissed: used by the PLAYER_LOGIN auto-open (Core.lua) so it's
-- a no-op once this exact version has been dismissed, instead of forcing the
-- window every login. A future manual "show it again" entry point (About
-- menu, etc.) would call this with no argument to always show.
function UI:ShowBetaNotice(onlyIfNotDismissed)
    if onlyIfNotDismissed and Embolsao.db.betaNoticeDismissedVersion == GetAddonVersion() then
        return
    end
    ShowBetaNoticeFrame()
end


UI.GetAddonVersion = GetAddonVersion
UI.ShowAboutFrame = ShowAboutFrame
