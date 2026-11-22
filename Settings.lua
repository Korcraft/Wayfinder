-- Wayfinder: Settings.lua
-- Real settings panel under Options > AddOns > Wayfinder, built with
-- Blizzard's own checkbox template (UICheckButtonTemplate) and registered
-- through the modern Settings API -- Settings.RegisterCanvasLayoutCategory
-- / Settings.RegisterAddOnCategory / Settings.OpenToCategory are confirmed
-- real and in active use on this client (Auctionator, Baganator,
-- ProfitCraft, Syndicator). The older InterfaceOptions_AddCategory is
-- deprecated and intentionally not used here.
--
-- Laid out as two fully independent sections, Compass and Map -- anything
-- that applies to both surfaces (showing party members, portraits vs.
-- class-color dots, icon sizes) has its own separate setting per surface,
-- not one shared toggle. See Core.lua's migrateSharedPartySettings for how
-- the old shared settings carry forward for anyone upgrading.

local PC = Wayfinder
PC.Settings = PC.Settings or {}
local ModuleSettings = PC.Settings

local COMPASS_OPTIONS = {
	{ key = "compassEnabled", label = "Show the compass HUD",
		help = "Shows or hides the compass strip at the top of the screen." },
	{ key = "showPartyCompass", label = "Show party members",
		help = "Shows party members as bearing icons on the compass." },
	{ key = "compassPartyIconDots", label = "Use class-color dots instead of portraits",
		help = "Shows party members as a flat class-color dot instead of their real portrait, on the compass." },
	{ key = "showQuests", label = "Show quest objectives",
		help = "Shows a bearing icon for quests in your quest log whose objective is in your current zone. "
			.. "Only quests Blizzard attached waypoint data to can show up -- some quests never will." },
	{ key = "showFlightPathsCompass", label = "Show flight points",
		help = "Shows flight points in your current zone on the compass -- grey boot = already discovered, "
			.. "green boot = not yet discovered." },
	{ key = "showAuctioneerCompass", label = "Show auction houses",
		help = "Shows the auction house on the compass, but only once you're within the location proximity "
			.. "radius (see the slider below) -- unlike other markers, these are permanent fixtures in nearly "
			.. "every zone, so showing them zone-wide would clutter the compass far more than quests/waypoints do." },
	{ key = "showBankCompass", label = "Show banks",
		help = "Shows the bank on the compass, same proximity-radius rule as the auction house." },
	{ key = "showMailboxCompass", label = "Show mailboxes",
		help = "Shows ONLY THE NEAREST mailbox on the compass once you're within the proximity radius -- some "
			.. "cities have several mailboxes, so showing all of them would be worse clutter than any other marker." },
	{ key = "showInnkeeperCompass", label = "Show innkeepers",
		help = "Shows the innkeeper on the compass, same proximity-radius rule as the auction house." },
	{ key = "showCorpseCompass", label = "Show your corpse",
		help = "Shows a bearing icon pointing to your own corpse on the compass while you're a ghost." },
	{ key = "dynamicIconsEnabled", label = "Dynamic icons",
		help = "Icons shrink and fade the further they are from dead-center on the compass, down to the scale/fade "
			.. "floors set by the two sliders below once an icon reaches the exact edge of the field of view." },
}

local MAP_OPTIONS = {
	{ key = "showPartyMap", label = "Show party members",
		help = "Shows party members as pins on the world map." },
	{ key = "mapPartyIconDots", label = "Use class-color dots instead of portraits",
		help = "Shows party members as a flat class-color dot instead of their real portrait, on the map." },
	{ key = "showFlightPathsMap", label = "Show flight points",
		help = "Shows flight points in your current zone on the world map -- grey boot = already discovered, "
			.. "green boot = not yet discovered." },
	{ key = "showAuctioneerMap", label = "Show auction houses",
		help = "Shows the auction house in your current zone on the world map." },
	{ key = "showBankMap", label = "Show banks",
		help = "Shows the bank in your current zone on the world map." },
	{ key = "showMailboxMap", label = "Show mailboxes",
		help = "Shows every mailbox in your current zone on the world map -- unlike the compass, the map has "
			.. "room to show all of them, not just the nearest." },
	{ key = "showInnkeeperMap", label = "Show innkeepers",
		help = "Shows the innkeeper in your current zone on the world map." },
	{ key = "showCorpseMap", label = "Show your corpse",
		help = "Shows a pin for your own corpse on the world map while you're a ghost." },
}

local COMPASS_COLORS = {
	{ key = "centerLineColor", label = "Center line color" },
	{ key = "tickColor", label = "Tick color" },
	{ key = "letterColor", label = "Letter color" },
	{ key = "hudColor", label = "HUD background color" },
}

local COMPASS_SLIDERS = {
	{ key = "hudOpacity", label = "Background opacity", min = 0, max = 1, steps = 20 },
	{ key = "compassWidth", label = "Width", min = 250, max = 700, steps = 45, round = true },
	{ key = "compassHeight", label = "Height", min = 48, max = 120, steps = 18, round = true },
	{ key = "compassPartyIconSize", label = "Player icon size", min = 10, max = 48, steps = 38, round = true },
	{ key = "compassQuestIconSize", label = "Quest icon size", min = 10, max = 48, steps = 38, round = true },
	{ key = "compassFlightIconSize", label = "Flight point icon size", min = 10, max = 40, steps = 30, round = true },
	{ key = "compassLocationIconSize", label = "Auction house/bank/mailbox/innkeeper icon size", min = 10, max = 40, steps = 30, round = true },
	{ key = "compassLocationRadius", label = "Auction house/bank/mailbox/innkeeper show distance", min = 50, max = 1000, steps = 38, round = true, format = YardText },
	{ key = "compassIconSize", label = "Waypoint icon size", min = 10, max = 40, steps = 30, round = true },
	{ key = "compassCorpseIconSize", label = "Corpse icon size", min = 10, max = 40, steps = 30, round = true },
}

-- Built inline right under the "Dynamic icons" checkbox (see BuildPage),
-- not in the generic COMPASS_SLIDERS list below -- these two only make
-- sense right next to the toggle that controls them, not buried at the
-- bottom of an unrelated slider block.
local DYNAMIC_ICON_SLIDERS = {
	{ key = "dynamicIconsScale", label = "Scale at edge of HUD", min = 0, max = 1, steps = 20 },
	{ key = "dynamicIconsFade", label = "Fade at edge of HUD", min = 0, max = 1, steps = 20 },
}

local MAP_SLIDERS = {
	{ key = "mapPartyIconSize", label = "Player icon size", min = 10, max = 48, steps = 38, round = true },
	{ key = "mapFlightIconSize", label = "Flight point icon size", min = 10, max = 40, steps = 30, round = true },
	{ key = "mapLocationIconSize", label = "Auction house/bank/mailbox/innkeeper icon size", min = 10, max = 40, steps = 30, round = true },
	{ key = "mapIconSize", label = "Waypoint icon size", min = 10, max = 40, steps = 30, round = true },
	{ key = "mapCorpseIconSize", label = "Corpse icon size", min = 10, max = 40, steps = 30, round = true },
}

local ROW_SPACING = 30
local checkboxes = {}
local colorSwatches = {}
local sliderSyncs = {}
local dynamicIconSliders = {} -- the two MinimalSliderWithSteppersTemplate frames under "Dynamic icons"
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

local function YardText(value)
	return string.format("%dy", math.floor(value + 0.5))
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
	local formatter = option.format or (option.round and PixelText or PercentText)
	slider:Init(PC.db.options[option.key], option.min, option.max, option.steps,
		{ [MinimalSliderWithSteppersMixin.Label.Right] = formatter })
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		PC.db.options[option.key] = option.round and math.floor(value + 0.5) or value
		if PC.Compass and PC.Compass.Refresh then PC.Compass.Refresh() end
	end, canvas)

	sliderSyncs[option] = function() slider:SetValue(PC.db.options[option.key]) end
	return slider
end

-- Greys out (rather than hides) the two Dynamic Icon sliders when the
-- toggle above them is off -- this canvas lays out every row at a fixed y
-- computed once in BuildPage, so hiding them would leave either a gap or
-- need a full reflow of everything below; disabling in place is the
-- simpler, consistent-with-the-rest-of-this-file option. .Slider/.Back/
-- .Forward + :SetAlpha() is MinimalSliderWithSteppersTemplate's own real,
-- confirmed disable pattern (QuestTogether's SetAudioSliderEnabled does
-- this exact thing on this client), not guessed.
local function updateDynamicIconSlidersEnabled()
	local enabled = PC.db.options.dynamicIconsEnabled and true or false
	for _, slider in ipairs(dynamicIconSliders) do
		slider.Slider:SetEnabled(enabled)
		slider.Back:SetEnabled(enabled)
		slider.Forward:SetEnabled(enabled)
		slider:SetAlpha(enabled and 1 or 0.5)
	end
end

local function BuildSectionHeader(parent, text, x, y)
	local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", x, y)
	header:SetText(text)
	return header
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

	BuildSectionHeader(content, "Compass", 16, y)
	y = y - 26
	for _, option in ipairs(COMPASS_OPTIONS) do
		local box = BuildCheckbox(content, option, 16, y)
		checkboxes[option] = box
		y = y - ROW_SPACING
		if option.key == "dynamicIconsEnabled" then
			-- Indented under the toggle that controls them, not buried at
			-- the bottom of the unrelated COMPASS_SLIDERS block.
			box:HookScript("OnClick", updateDynamicIconSlidersEnabled)
			for _, sliderOption in ipairs(DYNAMIC_ICON_SLIDERS) do
				local slider = BuildSlider(content, sliderOption, 32, y)
				dynamicIconSliders[#dynamicIconSliders + 1] = slider
				y = y - ROW_SPACING * 2
			end
		end
	end
	y = y - 10
	for _, option in ipairs(COMPASS_COLORS) do
		BuildColorSwatch(content, option, 16, y)
		y = y - ROW_SPACING
	end
	y = y - 10
	for _, option in ipairs(COMPASS_SLIDERS) do
		BuildSlider(content, option, 16, y)
		y = y - ROW_SPACING * 2
	end

	y = y - 18
	BuildSectionHeader(content, "Map", 16, y)
	y = y - 26
	for _, option in ipairs(MAP_OPTIONS) do
		checkboxes[option] = BuildCheckbox(content, option, 16, y)
		y = y - ROW_SPACING
	end
	y = y - 10
	for _, option in ipairs(MAP_SLIDERS) do
		BuildSlider(content, option, 16, y)
		y = y - ROW_SPACING * 2
	end

	content:SetHeight(-y + 16)

	canvas:SetScript("OnShow", function()
		for option, box in pairs(checkboxes) do box:SetChecked(GetValue(option)) end
		for _, applyCurrent in pairs(colorSwatches) do applyCurrent() end
		for _, applyCurrentSlider in pairs(sliderSyncs) do applyCurrentSlider() end
		updateDynamicIconSlidersEnabled()
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
