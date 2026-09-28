local ADDON_NAME, Embolsao = ...
local L = Embolsao.L

Embolsao.Minimap = {}

local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\icons\\embolsao-icon.png"
local BUTTON_SIZE = 31

local button

-- Simple hand-rolled minimap button (no LibDBIcon) -- one draggable frame,
-- angle around the ring saved to db, no external library to bundle across
-- three client flavors.
local function UpdatePosition()
    local angle = math.rad(Embolsao.db.minimapAngle or 225)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    Embolsao.db.minimapAngle = math.deg(math.atan2(py - my, px - mx))
    UpdatePosition()
end

local function ShowContextMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        rootDescription:CreateTitle("Embolsao!!")

        rootDescription:CreateButton(L.MINIMAP_OPEN, function()
            ToggleAllBags()
        end)

        rootDescription:CreateButton(L.PREFERENCES, function()
            Embolsao.UI:ShowPreferences()
        end)

        rootDescription:CreateButton(L.MINIMAP_OPEN_NATIVE_BAGS, function()
            Embolsao.UI:OpenNativeBags()
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateCheckbox(L.MINIMAP_DISABLE, function()
            return Embolsao.db.disabled == true
        end, function()
            Embolsao.UI:SetDisabled(not Embolsao.db.disabled)
        end)
    end)
end

local function CreateMinimapButton()
    if button then return button end

    button = CreateFrame("Button", "EmbolsaoMinimapButton", Minimap)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", 0, 1)
    button.icon:SetTexture(ICON)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetSize(53, 53)
    button.border:SetPoint("TOPLEFT")
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ShowContextMenu(self)
        else
            ToggleAllBags()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Embolsao!!")
        GameTooltip:AddLine(L.MINIMAP_TOOLTIP_HINT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    UpdatePosition()
    button:SetShown(Embolsao.db.showMinimapButton ~= false)
    return button
end

-- Preferences -> "Enable Minimap Button". Creates the button on first
-- enable if it doesn't exist yet (e.g. the player had it off at login).
function Embolsao.Minimap:SetShown(shown)
    Embolsao.db.showMinimapButton = shown and true or false
    if shown then
        CreateMinimapButton()
        button:Show()
    elseif button then
        button:Hide()
    end
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", CreateMinimapButton)
