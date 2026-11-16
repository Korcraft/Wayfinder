-- Wayfinder: Compass.lua
-- A top-of-screen heading strip, like an FPS compass: cardinal letters scroll
-- past as you turn, and anything relevant on your CURRENT map shows up as an
-- icon at its relative bearing -- your party's shared waypoints, live party
-- member positions, quest objectives, flight masters, and your saved custom
-- POIs (bank/AH/etc). Anything on a different map than the one you're
-- standing on is hidden here (waypoints still show on the world map) --
-- cross-zone "far away" arrows are a good follow-up feature once this works.

local PC = Wayfinder
PC.Compass = PC.Compass or {}
local Compass = PC.Compass

local frame, strip, centerTick, bgTop, bgBottom
local markers = {} -- cardinal letter labels, reused
local ticks = {}   -- minor/major tick marks between the labels, reused

-- Custom waypoint icons (user-provided art), saved as white alpha-masks --
-- SetVertexColor tints them, same as any other icon here -- confirmed this
-- client loads addon-bundled .png textures the same way Questie/Baganator
-- do (Interface/AddOns/<name>/<path>).
local WAYPOINT_TEXTURE_TEMP = "Interface/AddOns/Wayfinder/Textures/WaypointTemp.png"
local WAYPOINT_TEXTURE_PERMANENT = "Interface/AddOns/Wayfinder/Textures/WaypointPermanent.png"

local CARDINALS = {
	{ 0, "N" }, { 45, "NE" }, { 90, "E" }, { 135, "SE" },
	{ 180, "S" }, { 225, "SW" }, { 270, "W" }, { 315, "NW" },
}

local TICK_INTERVAL = 15 -- degrees between tick marks along the strip

local function shortestAngleDiff(a, b)
	local d = (a - b) % 360
	if d > 180 then d = d - 360 end
	return d
end

local function acquireLabel(i)
	local l = markers[i]
	if not l then
		l = strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		markers[i] = l
	end
	return l
end

local function acquireTick(i)
	local t = ticks[i]
	if not t then
		t = strip:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(1, 1, 1, 0.8)
		ticks[i] = t
	end
	return t
end

local function headingToPixel(headingDiff, width, fov)
	-- headingDiff in [-180,180], maps to an x offset across the visible field of view.
	return (headingDiff / fov) * width
end

-- The compass strip has very little room, so for things that often come in
-- scattered multiples at the same location type (several mailboxes in one
-- city, say) we only ever show the NEAREST one of each distinct name here.
-- The full world map isn't short on room, so MapPins.lua intentionally does
-- NOT apply this -- it shows every recorded spot.
local function nearestPerName(items, px, py)
	local bestItem, bestDist = {}, {}
	for _, item in ipairs(items) do
		local key = (item.name or ""):lower()
		local dx, dy = item.position.x - px, item.position.y - py
		local d = dx * dx + dy * dy
		if not bestDist[key] or d < bestDist[key] then
			bestDist[key] = d
			bestItem[key] = item
		end
	end
	local out = {}
	for _, item in pairs(bestItem) do out[#out + 1] = item end
	return out
end

-- ---------------------------------------------------------------------------
-- Generic "icon pool that shows markers at a bearing" helper, used for every
-- category below (waypoints/party/quests/POI) so we only write the bearing
-- math and pool-recycling logic once.
-- ---------------------------------------------------------------------------

local function makePool(makeIcon)
	local pool = {}
	local function acquire(i)
		local icon = pool[i]
		if not icon then
			icon = makeIcon()
			pool[i] = icon
		end
		return icon
	end
	return pool, acquire
end

-- Renders `items` (each needing a .position = {x,y}) at their bearing from
-- (px,py), hiding any pool entries left over from the last call.
local function renderBearingIcons(pool, acquire, items, px, py, heading, width, fov, yOffset, style)
	local shown = 0
	for _, item in ipairs(items) do
		local dx = item.position.x - px
		local dy = item.position.y - py
		if dx ~= 0 or dy ~= 0 then
			-- Map coordinates: +y is south. Convert to a compass bearing
			-- (0 = north, clockwise) and compare against facing.
			local bearing = math.atan2(dx, -dy) * 180 / math.pi
			if bearing < 0 then bearing = bearing + 360 end
			local diff = shortestAngleDiff(bearing, heading)
			if math.abs(diff) <= fov / 2 then
				shown = shown + 1
				local icon = acquire(shown)
				icon:ClearAllPoints()
				icon:SetPoint("CENTER", strip, "CENTER", headingToPixel(diff, width, fov), yOffset)
				if style then style(icon, item) end
				icon:Show()
			end
		end
	end
	for i = shown + 1, #pool do pool[i]:Hide() end
end

-- A small colored swatch, no letter needed for waypoints/party (color alone
-- tells them apart -- sequential per-waypoint color, or class color for
-- party members). Quest/POI still use a one-letter label for now.
local function makeSwatchPool()
	return makePool(function()
		local icon = CreateFrame("Frame", nil, strip)
		icon:SetSize(16, 16)
		icon.bg = icon:CreateTexture(nil, "OVERLAY")
		icon.bg:SetAllPoints()
		icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		icon.label:SetAllPoints()
		return icon
	end)
end

-- Party icons get their own pool (not the shared swatch pool) since they
-- need an extra texture for the class-color outline that waypoints/quests
-- don't use.
local function makePartyPool()
	return makePool(function()
		local icon = CreateFrame("Frame", nil, strip)
		icon:SetSize(16, 16)
		icon.border = icon:CreateTexture(nil, "OVERLAY", nil, -1)
		icon.border:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
		icon.bg = icon:CreateTexture(nil, "OVERLAY")
		icon.bg:SetAllPoints()
		icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		icon.label:SetAllPoints()
		return icon
	end)
end

local wpPool, acquireWp = makeSwatchPool()
local partyPool, acquireParty = makePartyPool()
local questPool, acquireQuest = makeSwatchPool()
local poiPool, acquirePoi = makeSwatchPool()
local pingPool, acquirePing = makeSwatchPool()

-- Shared styling for the swatch-pool categories: uses a real Blizzard icon
-- when IconStyle finds one and the player has "icon" mode on, otherwise a
-- colored letter swatch in the category's configured color.
local function applyMarker(icon, kind, label, colorKey)
	local color = PC.db.options.colors[colorKey]
	local tex = PC.IconStyle.GetTexture(kind, label)
	if tex then
		icon.bg:SetTexture(tex)
		icon.bg:SetVertexColor(1, 1, 1, 1)
		icon.label:SetText("")
	else
		icon.bg:SetTexture(nil)
		icon.bg:SetColorTexture(color[1], color[2], color[3], 0.9)
		icon.label:SetText(label and label:sub(1, 1) or "")
	end
end

-- Real unit portrait (the same circular "face" render used by party/raid
-- frames, via the long-standing global SetPortraitTexture API -- confirmed
-- real and used this exact way by addons on this client) instead of a flat
-- color/letter. Falls back to the class color as a plain tint only if the
-- portrait genuinely isn't available yet (can briefly happen right as
-- someone comes into range).
local function applyPortrait(icon, unit, alpha)
	local c = PC.PartyTracker.ClassColor(unit)

	-- Class-color outline: same disc texture, a few px bigger, drawn one
	-- sublevel behind the portrait/dot so only its rim shows -- a ring,
	-- without a dedicated ring-shaped texture asset.
	if icon.border then
		icon.border:ClearAllPoints()
		icon.border:SetPoint("CENTER", icon, "CENTER")
		icon.border:SetSize(icon:GetWidth() + 4, icon:GetHeight() + 4)
		icon.border:SetVertexColor(c[1], c[2], c[3], alpha)
	end

	local ok = not PC.db.options.partyIconDots and pcall(SetPortraitTexture, icon.bg, unit)
	if ok then
		icon.bg:SetVertexColor(1, 1, 1, alpha)
	else
		-- Real Blizzard circular disc texture (confirmed used this exact
		-- way by other installed addons), tinted via vertex color -- a
		-- round dot instead of a flat SetColorTexture square.
		icon.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
		icon.bg:SetVertexColor(c[1], c[2], c[3], alpha)
	end
	icon.label:SetText("")
end

function Compass.Refresh()
	if not frame then return end
	frame:SetShown(PC.db.options.compassEnabled)
	if centerTick then
		local c = PC.db.options.centerLineColor
		centerTick:SetColorTexture(c[1], c[2], c[3], 0.8)
	end
	if bgTop and bgBottom then
		local c, a = PC.db.options.hudColor, PC.db.options.hudOpacity
		bgTop:SetColorTexture(c[1], c[2], c[3], a)
		bgBottom:SetColorTexture(c[1], c[2], c[3], a)
	end
end

-- CALIBRATED from /wf facingcheck: facing true north reads ~359.8/360
-- degrees (i.e. ~0, no offset at the zero-point), which combined with the
-- earlier SW-reported-as-NW result only fits a MIRROR (direction-reversed)
-- relationship, not an offset -- GetPlayerFacing() increases
-- counter-clockwise, our bearing convention increases clockwise, and they
-- happen to agree at exactly 0/north, which is why a single due-north
-- reading alone wouldn't have caught this.
local function facingDegrees()
	local facing = (GetPlayerFacing() or 0) * 180 / math.pi
	return (360 - facing) % 360
end

local function updateCompass()
	if not frame or not frame:IsShown() then return end
	local width = PC.db.options.compassWidth
	local fov = PC.db.options.fieldOfView
	local heading = facingDegrees()

	-- Cardinal letters
	local lc = PC.db.options.letterColor
	local shown = 0
	for _, c in ipairs(CARDINALS) do
		local diff = shortestAngleDiff(c[1], heading)
		if math.abs(diff) <= fov / 2 then
			shown = shown + 1
			local l = acquireLabel(shown)
			l:SetText(c[2])
			l:SetTextColor(lc[1], lc[2], lc[3])
			l:ClearAllPoints()
			-- Anchored from the TOP, right below the major ticks, not
			-- dead-center -- center-anchoring left an 11px gap between the
			-- ticks and the letters, which read as "letters too low". -16
			-- (was -18) leaves a clean 4px gap to the icon row below for
			-- the two-section background split (see Compass.Init).
			l:SetPoint("TOP", strip, "TOP", headingToPixel(diff, width, fov), -16)
			l:Show()
		end
	end
	for i = shown + 1, #markers do markers[i]:Hide() end

	-- Minor/major tick marks every TICK_INTERVAL degrees (major = taller, at
	-- the same headings as the cardinal/intercardinal labels above).
	local tc = PC.db.options.tickColor
	local ticksShown = 0
	for deg = 0, 345, TICK_INTERVAL do
		local diff = shortestAngleDiff(deg, heading)
		if math.abs(diff) <= fov / 2 then
			ticksShown = ticksShown + 1
			local t = acquireTick(ticksShown)
			local isMajor = (deg % 45 == 0)
			t:SetSize(isMajor and 2 or 1, isMajor and 14 or 7)
			t:SetColorTexture(tc[1], tc[2], tc[3], 0.8)
			t:SetAlpha(isMajor and 0.9 or 0.5)
			t:ClearAllPoints()
			t:SetPoint("TOP", strip, "TOP", headingToPixel(diff, width, fov), 0)
			t:Show()
		end
	end
	for i = ticksShown + 1, #ticks do ticks[i]:Hide() end

	-- Everything below needs the player's own position on the current map.
	local uiMapID = C_Map.GetBestMapForUnit("player")
	local myPos = uiMapID and C_Map.GetPlayerMapPosition(uiMapID, "player")
	if not (uiMapID and myPos) then
		for i = 1, #wpPool do wpPool[i]:Hide() end
		for i = 1, #partyPool do partyPool[i]:Hide() end
		for i = 1, #questPool do questPool[i]:Hide() end
		return
	end
	local px, py = myPos:GetXY()

	-- POI/pings are still shelved (see Core.lua); quests and party are live.
	local activeWaypoints = {}
	for _, wp in ipairs(PC.Waypoints.GetAll()) do
		if wp.uiMapID == uiMapID then
			activeWaypoints[#activeWaypoints + 1] = wp
		end
	end
	-- -16 (was -14): with letters now anchored right below the ticks
	-- instead of dead-center, the icon row needs to sit a bit lower to
	-- clear them without overlapping -- see the letter anchor's comment.
	renderBearingIcons(wpPool, acquireWp, activeWaypoints, px, py, heading, width, fov, -16, function(icon, item)
		-- Permanent waypoints are always white; temp ones round-robin
		-- through COLOR_SEQUENCE (1st = light blue, 2nd = green, ...) so
		-- you can tell which one's which at a glance -- see Waypoints.lua
		-- for why the two colors never overlap. Both kinds render at the
		-- same size now (adjustable via the small/medium/large setting --
		-- see Waypoints.IconSize). Icons are reused across both kinds over
		-- time, so size/texture/color have to be set fresh each render.
		local c = (item.kind == "P") and PC.Waypoints.PERMANENT_COLOR or PC.Waypoints.colorForIndex(item.colorIndex or 1)
		local sz = PC.Waypoints.IconSize()
		icon:SetSize(sz, sz)
		icon.bg:SetTexture(item.kind == "P" and WAYPOINT_TEXTURE_PERMANENT or WAYPOINT_TEXTURE_TEMP)
		icon.bg:SetVertexColor(c[1], c[2], c[3], 1)
		icon.label:SetText("")
	end)

	-- Quest objectives in your CURRENT zone only -- PC.Quests.GetAll() asks
	-- Blizzard for each tracked quest's next waypoint on your current map,
	-- so a quest whose objective is elsewhere simply never appears here.
	-- Only quests Blizzard actually attached waypoint data to can show up
	-- at all (see Quests.lua) -- that's a real coverage gap, not a bug.
	if PC.db.options.showQuests then
		renderBearingIcons(questPool, acquireQuest, PC.Quests.GetAll(), px, py, heading, width, fov, -16,
			function(icon, item)
				icon:SetSize(18, 18)
				applyMarker(icon, "quest", item.trackerNumber and tostring(item.trackerNumber) or "Q", "quest")
			end)
	else
		for i = 1, #questPool do questPool[i]:Hide() end
	end

	-- Live party member positions -- shown at ALL times regardless of zone or
	-- distance. Same-zone members get a precise bearing; a member in a
	-- different zone gets a bearing computed on the nearest map you both
	-- resolve a position on (usually the continent) -- coarser, but real
	-- geography, not a guess (see PartyTracker.GetCommonMapPosition). The
	-- one real ceiling: if there's truly no shared map at all (different
	-- continent, a dungeon/instance, etc.), no bearing is possible -- those
	-- members are pinned to the compass's right edge instead of hidden, so
	-- they're still always visibly present even without a direction.
	do
		local partyShown, edgeShown = 0, 0
		for _, member in ipairs(PC.PartyTracker.GetAll()) do
			local mapID, mpx, mpy, mmx, mmy = PC.PartyTracker.GetCommonMapPosition(member.unit, member.uiMapID)
			local placed = false
			if mapID then
				local dx, dy = mmx - mpx, mmy - mpy
				if dx ~= 0 or dy ~= 0 then
					local bearing = math.atan2(dx, -dy) * 180 / math.pi
					if bearing < 0 then bearing = bearing + 360 end
					local diff = shortestAngleDiff(bearing, heading)
					if math.abs(diff) <= fov / 2 then
						partyShown = partyShown + 1
						local icon = acquireParty(partyShown)
						icon:SetSize(28, 28) -- same size as permanent waypoints
						icon:ClearAllPoints()
						icon:SetPoint("CENTER", strip, "CENTER", headingToPixel(diff, width, fov), -16) -- bottom row, same as waypoints
						applyPortrait(icon, member.unit, 1)
						icon:Show()
						placed = true
					end
				end
			end
			if not placed and mapID == nil then
				-- No bearing possible at all -- pin to the edge, dimmed, so
				-- they're still visible rather than silently missing.
				edgeShown = edgeShown + 1
				partyShown = partyShown + 1
				local icon = acquireParty(partyShown)
				icon:SetSize(28, 28) -- same size as permanent waypoints
				icon:ClearAllPoints()
				icon:SetPoint("RIGHT", strip, "RIGHT", -4, -16 - (edgeShown - 1) * 18)
				applyPortrait(icon, member.unit, 0.45)
				icon:Show()
			end
		end
		for i = partyShown + 1, #partyPool do partyPool[i]:Hide() end
	end
end

function Compass.Init()
	-- 64 tall (was 44): the bottom-row icons are 28px, centered 14px below
	-- the strip's middle -- their bottom edge sits 28px below center, which
	-- didn't fit inside the old 44px-tall (+-22) frame and overhung the
	-- background by ~6px. 64px (+-32) gives them room with a small margin.
	frame = CreateFrame("Frame", "WayfinderHUD", UIParent)
	frame:SetSize(PC.db.options.compassWidth, 64)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -4)
	frame:SetFrameStrata("LOW")

	-- Two separate background panels instead of one continuous strip: the
	-- ticks+letters (directional heading) and the icon row (waypoints/
	-- party) are different kinds of information, so they get their own
	-- opacity panel each, with a gap of nothing between them rather than
	-- one unbroken bar. 3px gap (was 2px, +50% as asked) -- letters bottom
	-- out around y=+2 and icons start around y=-2, so a split at +-1.5
	-- sits cleanly between both without clipping either.
	bgTop = frame:CreateTexture(nil, "BACKGROUND")
	bgTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	bgTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	bgTop:SetHeight(30.5)

	bgBottom = frame:CreateTexture(nil, "BACKGROUND")
	bgBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	bgBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	bgBottom:SetHeight(30.5)
	-- Color/opacity applied below via Compass.Refresh(), from saved settings.

	strip = CreateFrame("Frame", nil, frame)
	strip:SetAllPoints()

	centerTick = frame:CreateTexture(nil, "OVERLAY")
	centerTick:SetSize(2, 64)
	centerTick:SetPoint("CENTER")
	centerTick:SetColorTexture(1, 1, 1, 0.8)

	-- Runs every frame, not throttled: the math here (a handful of trig calls
	-- over a dozen-ish markers) is cheap, and anything coarser than ~60fps
	-- reads as visibly choppy for something tracking continuous rotation,
	-- same as why the native minimap re-rotates every frame too.
	-- Wrapped in pcall so one bad frame (e.g. a zone/instance where some
	-- map/position API behaves differently) can't silently wedge the whole
	-- compass with no visible sign of why -- by default WoW shows nothing
	-- at all for an OnUpdate error unless /console scriptErrors is on, which
	-- is exactly how this could look "frozen" with zero clues. Reports the
	-- real error once instead of guessing.
	local warnedUpdateError = false
	frame:SetScript("OnUpdate", function(self, elapsed)
		local ok, err = pcall(updateCompass)
		if not ok and not warnedUpdateError then
			warnedUpdateError = true
			print("|cffff4444Wayfinder|r compass update error (won't spam further): " .. tostring(err))
		end
	end)

	Compass.Refresh()
end
