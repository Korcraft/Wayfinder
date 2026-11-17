-- Wayfinder: Settings.lua
-- Real settings panel under Options > AddOns > Wayfinder, built with
-- Blizzard's own checkbox template (UICheckButtonTemplate) and registered
-- through the modern Settings API -- Settings.RegisterCanvasLayoutCategory
-- / Settings.RegisterAddOnCategory / Settings.OpenToCategory are confirmed
-- real and in active use on this client (Auctionator, Baganator,
-- ProfitCraft, Syndicator). The older InterfaceOptions_AddCategory is
-- deprecated and intentionally not used here.

local PC = Wayfinder
PC.Settings = PC.Settings or {}
local ModuleSettings = PC.Settings

local OPTIONS = {
	{ key = "compassEnabled", label = "Show the compass HUD",
		help = "Shows or hides the compass strip at the top of the screen." },
	{ key = "showParty", label = "Show party members",
		help = "Shows party members as bearing icons on the compass and as pins on the map." },
	{ key = "showQuests", label = "Show quest objectives on the compass",
		help = "Shows a bearing icon for quests in your quest log whose objective is in your current zone. "
			.. "Only quests Blizzard attached waypoint data to can show up -- some quests never will." },
	{ key = "partyIconDots", label = "Use class-color dots instead of portraits",
		help = "Shows party members as a flat class-color dot instead of their real portrait, "
			.. "on both the compass and the map." },
}

local COLORS = {
	{ key = "centerLineColor", label = "Compass center line color" },
	{ key = "tickColor", label = "Compass tick color" },
	{ key = "letterColor", label = "Compass letter color" },
	{ key = "hudColor", label = "Compass HUD background color" },
}

local SLIDERS = {
	{ key = "hudOpacity", label = "Compass HUD background opacity", min = 0, max = 1, steps = 20 },
	{ key = "compassWidth", label = "Compass width", min = 250, max = 700, steps = 45, round = true },
	{ key = "compassHeight", label = "Compass height", min = 48, max = 120, steps = 18, round = true },
	-- The compass HUD and the world map each get their own waypoint icon
	-- size slider now, instead of a shared small/medium/large pick.
	{ key = "compassIconSize", label = "Compass waypoint icon size", min = 10, max = 40, steps = 30, round = true },
	{ key = "mapIconSize", label = "Map waypoint icon size", min = 10, max = 40, steps = 30, round = true },
}

local ROW_SPACING = 30
local checkboxes = {}
local colorSwatches = {}
local sliderSyncs = {}
local category

local function GetValue(option)
	return PC.db.options[option.key] and true or false
end

local function SetValue(option, value)
	PC.db.options[option.key] = value
	if PC.Compass and PC.Compass.Refresh then PC.Compass.Refresh() end
	if PC.MapPins and PC.MapPins.Refresh then PC.MapPins.Refresh() end
end

local function ShowHelp(owner, option)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(option.label, 1, 1, 1)
	GameTooltip:AddLine(option.help, nil, nil, nil, true)
	GameTooltip:Show()
end

-- Blizzard's own color-swatch-plus-picker pattern (ColorSwatchTemplate +
-- ColorPickerFrame:SetupColorPickerAndShow) -- confirmed real and used this
-- exact way, including the closure-captured cancelFunc, by Baganator on
-- this client, so this isn't guessed from memory.
local function BuildColorSwatch(canvas, option, x, y)
	local label = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", x, y)
	label:SetText(option.label)

	local swatch = CreateFrame("Button", nil, canvas, "ColorSwatchTemplate")
	swatch:SetPoint("LEFT", label, "RIGHT", 10, 0)

	local function applyCurrent()
		local c = PC.db.options[option.key]
		swatch:SetColorRGB(c[1], c[2], c[3])
	end
	applyCurrent()

	swatch:SetScript("OnClick", function()
		local before = PC.db.options[option.key]
		local beforeR, beforeG, beforeB = before[1], before[2], before[3]
		local info = {}
		info.r, info.g, info.b = beforeR, beforeG, beforeB
		info.swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			PC.db.options[option.key] = { r, g, b }
			swatch:SetColorRGB(r, g, b)
			if PC.Compass and PC.Compass.Refresh then PC.Compass.Refresh() end
		end
		info.cancelFunc = function()
			PC.db.options[option.key] = { beforeR, beforeG, beforeB }
			swatch:SetColorRGB(beforeR, beforeG, beforeB)
			if PC.Compass and PC.Compass.Refresh then PC.Compass.Refresh() end
		end
		ColorPickerFrame:SetupColorPickerAndShow(info)
	end)

	colorSwatches[option] = applyCurrent
	return swatch
end

local function PercentText(value)
	return string.format("%d%%", math.floor(value * 100 + 0.5))
end

local function PixelText(value)
	return string.format("%dpx", math.floor(value + 0.5))
end

-- Blizzard's own slider-with-arrow-buttons template (MinimalSliderWithSteppersTemplate),
-- confirmed real and used this exact way (Init/RegisterCallback signature,
-- re-syncing with SetValue) by ProfitCraft's own working settings page on
-- this client.
local function BuildSlider(canvas, option, x, y)
	local label = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", x + 4, y - 6)
	label:SetText(option.label)

	local slider = CreateFrame("Frame", nil, canvas, "MinimalSliderWithSteppersTemplate")
	slider:SetWidth(220)
	slider:SetPoint("TOPLEFT", x + 8, y - ROW_SPACING + 4)
	local formatter = option.round and PixelText or PercentText
	slider:Init(PC.db.options[option.key], option.min, option.max, option.steps,
		{ [MinimalSliderWithSteppersMixin.Label.Right] = formatter })
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		PC.db.options[option.key] = option.round and math.floor(value + 0.5) or value
		if PC.Compass and PC.Compass.Refresh then PC.Compass.Refresh() end
	end, canvas)

	sliderSyncs[option] = function() slider:SetValue(PC.db.options[option.key]) end
	return slider
end

local function BuildCheckbox(canvas, option, x, y)
	local box = CreateFrame("CheckButton", nil, canvas, "UICheckButtonTemplate")
	box:SetPoint("TOPLEFT", x, y)
	box.Text:SetText(option.label)
	box.Text:SetFontObject("GameFontHighlight")
	box:SetScript("OnClick", function(self)
		SetValue(option, self:GetChecked() and true or false)
	end)
	box:SetScript("OnEnter", function(self) ShowHelp(self, option) end)
	box:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return box
end

-- The page had grown past the fixed height Blizzard gives a canvas
-- category (no scrollbar, content just ran off the bottom) -- so the
-- title stays fixed on the canvas, and everything else lives in a
-- UIPanelScrollFrameTemplate's scroll child instead. Confirmed real and
-- used this exact way on this client (ForeverDungeonJournal); that same
-- addon's own comment flags that the scrollbar CHILD FIELD NAME
-- (scroll.ScrollBar vs scroll.scrollBar) differs on Forever builds, but
-- that's only needed for restyling the scrollbar, not for scrolling
-- itself to work, so it's not needed here.
local function BuildPage(canvas)
	local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Wayfinder")

	local scroll = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -48)
	scroll:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -27, 0)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetPoint("TOPLEFT")
	content:SetWidth(scroll:GetWidth())
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)

	local y = -8
	for i, option in ipairs(OPTIONS) do
		checkboxes[option] = BuildCheckbox(content, option, 16, y)
		y = y - ROW_SPACING
	end

	y = y - 10
	for i, option in ipairs(COLORS) do
		BuildColorSwatch(content, option, 16, y)
		y = y - ROW_SPACING
	end

	y = y - 10
	for i, option in ipairs(SLIDERS) do
		BuildSlider(content, option, 16, y)
		y = y - ROW_SPACING * 2
	end

	content:SetHeight(-y + 16)

	canvas:SetScript("OnShow", function()
		for option, box in pairs(checkboxes) do box:SetChecked(GetValue(option)) end
		for _, applyCurrent in pairs(colorSwatches) do applyCurrent() end
		for _, applyCurrentSlider in pairs(sliderSyncs) do applyCurrentSlider() end
	end)
end

function ModuleSettings.Init()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	local canvas = CreateFrame("Frame", nil, UIParent)
	canvas:Hide()
	BuildPage(canvas)
	category = Settings.RegisterCanvasLayoutCategory(canvas, "Wayfinder")
	Settings.RegisterAddOnCategory(category)
end

function ModuleSettings.Open()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	else
		print("|cffff4444Wayfinder|r settings panel isn't available on this client.")
	end
end
