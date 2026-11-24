-- Wayfinder: FlightPoints.lua
-- Tracks which flight points you've discovered, and surfaces the ones on
-- your CURRENT zone's map -- matching the same zone-scoped rule Quests.lua
-- already uses. Every flight point on the continent regardless of where you
-- are would be clutter, not useful, so a point only ever shows up here at
-- all while you're standing in that same zone.
--
-- Discovery detection: the modern map-data "isUndiscovered" flag is NOT
-- reliable on this Forever client -- confirmed via ForeverDungeonJournal's
-- own code comment ("the world map's isUndiscovered is not to be trusted on
-- WoW Forever"), not guessed. The reliable method, also confirmed via FDJ's
-- own working code on this exact client: while a flight master's taxi map
-- is open, the OLD-STYLE globals NumTaxiNodes()/TaxiNodeName(i)/
-- TaxiNodeGetType(i) report "CURRENT" or "REACHABLE" for every node you've
-- actually found, and (a Forever-specific quirk, also confirmed by FDJ)
-- "DISTANT" instead of the classic "NONE" for ones you've never visited.
-- That list is the flight map's own authoritative word, so
-- TAXIMAP_OPENED/TAXI_NODE_STATUS_CHANGED re-reads it and corrects our
-- saved discovery set either way -- adding newly-found points AND removing
-- a stale/wrong entry the same way FDJ's fpfix/fpdistant logic does.
--
-- This means discovery status updates RETROACTIVELY the first time you open
-- ANY flight map after installing -- the flight map always lists the whole
-- network you've found so far, not just points near where you are (the same
-- reason opening a flight map in one city shows distant previously-visited
-- cities too, on live WoW). You don't need to revisit every point one at a
-- time.
--
-- Persisted per-character (WayfinderDB.flightPointsFound[fullName]), same
-- myFullName() keying as Waypoints.lua -- flight discovery is genuinely
-- per-character, unlike waypoints which are meant to be shared with party.
--
-- The zone list itself comes from C_TaxiMap.GetTaxiNodesForMap(uiMapID).
-- Confirmed real, found via ForeverDungeonJournal/Systems/MapMarkers.lua's
-- own working code, NOT guessed -- an earlier guess at
-- C_TaxiMap.GetAllTaxiNodes was wrong and caught via grep before ever being
-- used.
--
-- IMPORTANT, confirmed via /wf flightcheck (not assumed): on this client,
-- this call does NOT filter by zone at all -- querying it from Duskwood
-- returned all 36 Eastern Kingdoms flight points, every one of them,
-- positioned as if plotted onto DUSKWOOD's own map frame regardless of
-- where they actually are (Ironforge, nowhere near Duskwood, came back as
-- x=0.74, y=-2.72 -- way outside the 0-1 canvas). The ONLY node that landed
-- inside 0-1 on BOTH axes was Darkshire -- Duskwood's own real flight
-- point. So the 0-1 bounds check in GetAll() below IS the zone filter here,
-- not a sanity clamp -- a point genuinely within the queried map's own
-- borders always lands inside 0-1; one that isn't basically never does.

local PC = Wayfinder
PC.FlightPoints = PC.FlightPoints or {}
local FlightPoints = PC.FlightPoints

-- Same pattern as Waypoints.lua's own local myFullName() -- no shared util
-- exported for this elsewhere in the codebase, so it's duplicated here too.
local function myFullName()
	local name, realm = UnitFullName("player")
	realm = realm ~= "" and realm or GetRealmName()
	return name .. "-" .. realm
end

local function foundSet()
	if type(WayfinderDB.flightPointsFound) ~= "table" then WayfinderDB.flightPointsFound = {} end
	local owner = myFullName()
	if type(WayfinderDB.flightPointsFound[owner]) ~= "table" then WayfinderDB.flightPointsFound[owner] = {} end
	return WayfinderDB.flightPointsFound[owner]
end

-- Alliance/Horde-only nodes: node.faction is 1 for Horde-only, 2 for
-- Alliance-only, anything else (0/nil) is neutral/both -- mirrors
-- ForeverDungeonJournal's own OurSide() check, confirmed real on this
-- client via that addon's working code, not guessed.
local function oursToSee(nodeFaction)
	local _, englishFaction = UnitFactionGroup("player")
	if nodeFaction == 1 then return englishFaction == "Horde" end
	if nodeFaction == 2 then return englishFaction == "Alliance" end
	return true
end

-- Only run while a flight map is confirmed open -- NumTaxiNodes() and
-- friends are taxi-frame-scoped globals, so calling them at the wrong time
-- could silently read 0/garbage and corrupt the saved discovery set. Mirrors
-- FDJ's own FDJ.taxiMapOpen gate.
local taxiMapOpen = false

-- Re-reads the open flight map and corrects the saved discovery set -- see
-- the file header for why this (not the map-data isUndiscovered flag) is
-- the reliable source on this client.
local function recordFlightMap()
	if not taxiMapOpen then return end
	if type(NumTaxiNodes) ~= "function" or type(TaxiNodeName) ~= "function"
		or type(TaxiNodeGetType) ~= "function" then
		return
	end
	local ok, count = pcall(NumTaxiNodes)
	if not ok then return end
	local found = foundSet()
	for i = 1, (count or 0) do
		local okName, name = pcall(TaxiNodeName, i)
		local okType, kind = pcall(TaxiNodeGetType, i)
		-- The modern sandboxing mechanism (confirmed in heavy use across
		-- almost every addon on this client, same as Compass.lua's
		-- facingDegrees) -- FDJ guards the exact same two fields the same way.
		if type(issecretvalue) == "function" and (issecretvalue(name) or issecretvalue(kind)) then
			name = nil
		end
		if okName and type(name) == "string" and name ~= "" and okType and type(kind) == "string" then
			local key = name:lower()
			if kind == "CURRENT" or kind == "REACHABLE" then
				found[key] = true
			elseif found[key] then
				-- The flight map itself says this one isn't found after all
				-- (NONE, or this client's DISTANT) -- fpfix/fpdistant: the
				-- flight map is the last word, so a wrong entry gets
				-- corrected here rather than staying stuck.
				found[key] = nil
			end
		end
	end
end

local MAX_NODES_IN_ONE_ZONE = 8

-- Every flight point on the CURRENT zone's map, found or not -- see
-- Compass.lua/MapPins.lua for how showFlightPathsCompass/showFlightPathsMap
-- separately gate whether these actually get drawn.
function FlightPoints.GetAll()
	local list = {}
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return list end

	local uiMapID = C_Map.GetBestMapForUnit("player")
	if not uiMapID then return list end

	-- The bounds check below only works on a zone-sized map. If the game
	-- reports a continent or world map as your location, every flight point
	-- on it lands inside 0-1, so show none rather than the whole network.
	local mapInfo = C_Map.GetMapInfo(uiMapID)
	local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
	if mapInfo and type(mapInfo.mapType) == "number" and mapInfo.mapType < zoneType then
		return list
	end

	local kept = FlightPoints.NodesInMap(uiMapID)

	-- Safety net for any other oversized map: no real zone has this many.
	if #kept > MAX_NODES_IN_ONE_ZONE then return {} end
	return kept
end

-- The continent a zone sits on, and the zone's rectangle on that continent's
-- map (minX, maxX, minY, maxY), or nil.
local continentCache = {}
local function zoneOnContinent(uiMapID)
	local cached = continentCache[uiMapID]
	if cached then return cached ~= false and cached or nil end
	local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
	local result = false
	local mapID = uiMapID
	for _ = 1, 10 do
		local info = mapID and C_Map.GetMapInfo(mapID)
		if not info then break end
		if info.mapType == CONTINENT then
			if C_Map.GetMapRectOnMap then
				local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, uiMapID, mapID)
				if ok and type(minX) == "number" and type(maxX) == "number" and maxX > minX
					and type(minY) == "number" and type(maxY) == "number" and maxY > minY then
					result = { continent = mapID, minX = minX, maxX = maxX, minY = minY, maxY = maxY }
				end
			end
			break
		end
		mapID = info.parentMapID
	end
	continentCache[uiMapID] = result
	return result or nil
end

-- Which zone the game says this zone-map point is really in, or nil if it
-- can't tell. Same lookup the world map uses to highlight a zone on hover
-- (and ForeverDungeonJournal uses on this client to find zone borders).
local function zoneAtPoint(uiMapID, x, y)
	local rect = zoneOnContinent(uiMapID)
	if not (rect and C_Map.GetMapInfoAtPosition) then return nil end
	local cx = rect.minX + x * (rect.maxX - rect.minX)
	local cy = rect.minY + y * (rect.maxY - rect.minY)
	local ok, info = pcall(C_Map.GetMapInfoAtPosition, rect.continent, cx, cy)
	if ok and type(info) == "table" and type(info.mapID) == "number" then return info.mapID end
	return nil
end

-- "Stormwind, Elwynn" belongs to Elwynn Forest and to Stormwind City: either
-- part of the flight point's name starting the zone's name counts. Covers
-- cities, whose flight point may sit on the surrounding zone's ground.
local function nameMatchesZone(nodeName, zoneName)
	if type(zoneName) ~= "string" or zoneName == "" then return false end
	zoneName = zoneName:lower()
	for part in nodeName:lower():gmatch("[^,]+") do
		part = part:gsub("^%s+", ""):gsub("%s+$", "")
		if part ~= "" and zoneName:find(part, 1, true) == 1 then return true end
	end
	return false
end

-- The flight points that belong to one zone, before the too-many cap. Works
-- for any map ID, not just the one you're standing on, which is what lets
-- /wf flightzones test another continent from afar. Also returns how many
-- nodes the game handed back before filtering.
--
-- A zone map is a rectangle that overlaps its neighbors, so landing inside
-- 0-1 isn't enough (confirmed: Darkshore's rectangle caught Moonglade and
-- Felwood flight points). A "Place, Zone" name decides by itself. A name with
-- no zone in it ("Moonglade") counts if the game says it's in this zone; if
-- the game can't say, the old border check alone decides.
function FlightPoints.NodesInMap(uiMapID)
	local list = {}
	local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, uiMapID)
	if not ok or type(nodes) ~= "table" then return list, 0 end
	local zoneInfo = C_Map.GetMapInfo(uiMapID)
	local zoneName = zoneInfo and zoneInfo.name

	-- See the file header -- GetTaxiNodesForMap doesn't zone-filter on this
	-- client at all. This bounds check is the first pass (inside the zone's
	-- rectangle); the zone lookup below is the second. Small margin for floating-point jitter
	-- right at the edge of the canvas; the real out-of-zone values seen via
	-- /wf flightcheck were nowhere close to this margin (the nearest
	-- genuinely-out-of-zone node was still 0.075 away from 0).
	local MARGIN = 0.03
	local function inBounds(v) return v >= -MARGIN and v <= 1 + MARGIN end

	local found = foundSet()
	for _, node in ipairs(nodes) do
		if type(node) == "table" and node.position and oursToSee(node.faction) then
			local x, y = node.position.x, node.position.y
			if (x == nil or y == nil) and node.position.GetXY then x, y = node.position:GetXY() end
			local named = type(node.name) == "string" and node.name ~= ""
				and not node.name:find("^zzOLD") -- retired leftovers in the game's own list
			local belongs = false
			if named and x and y and inBounds(x) and inBounds(y) then
				if node.name:find(",", 1, true) then
					-- "Place, Zone": the name says where it is. Trusted over the
					-- lookup, which put Talrendis Point (Azshara, right on the
					-- border) in Ashenvale.
					belongs = nameMatchesZone(node.name, zoneName)
				else
					local actualZone = zoneAtPoint(uiMapID, x, y)
					belongs = actualZone == nil or actualZone == uiMapID or nameMatchesZone(node.name, zoneName)
				end
			end
			if belongs then
				list[#list + 1] = {
					nodeID = node.nodeID,
					name = node.name,
					uiMapID = uiMapID,
					position = { x = x, y = y },
					discovered = found[node.name:lower()] == true,
				}
			end
		end
	end

	return list, #nodes
end

-- ---------------------------------------------------------------------------
-- A copyable text window -- WoW's chat frame has no real select-and-copy, so
-- any debug dump longer than a line or two is practically unreadable there.
-- Built from plain Frame/EditBox/ScrollFrame/Button primitives, same as
-- MapPins.lua's rename dialog -- EditBox is a bedrock-stable widget
-- (SetMultiLine, HighlightText) unchanged across WoW's entire history, so
-- this needs no client-specific verification the way a real game API would.
-- ---------------------------------------------------------------------------

local debugWindow

local function showCopyableText(title, text)
	if not debugWindow then
		local f = CreateFrame("Frame", "WayfinderDebugWindow", UIParent)
		f:SetSize(560, 440)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetToplevel(true)
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)

		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.97)

		local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOP", 0, -10)
		f.label = label

		local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("TOP", label, "BOTTOM", 0, -4)
		hint:SetText("Click inside, then Ctrl+A, Ctrl+C to copy")

		local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		closeBtn:SetSize(80, 22)
		closeBtn:SetPoint("BOTTOM", 0, 10)
		closeBtn:SetText("Close")
		closeBtn:SetScript("OnClick", function() f:Hide() end)

		local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -44)
		scroll:SetPoint("BOTTOMRIGHT", -32, 40)

		local editBg = CreateFrame("Frame", nil, scroll)
		editBg:SetAllPoints()
		local editBgTex = editBg:CreateTexture(nil, "BACKGROUND")
		editBgTex:SetAllPoints()
		editBgTex:SetColorTexture(0, 0, 0, 0.5)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(500)
		edit:SetAutoFocus(false)
		edit:SetTextInsets(4, 4, 4, 4)
		edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		scroll:SetScrollChild(edit)
		f.edit = edit

		f:Hide()
		debugWindow = f
	end
	debugWindow.label:SetText(title)
	debugWindow.edit:SetText(text)
	debugWindow.edit:HighlightText()
	debugWindow.edit:SetFocus()
	debugWindow:Show()
end

-- /wf flightcheck -- opens a copyable dump of exactly what
-- C_TaxiMap.GetTaxiNodesForMap is handing back for your CURRENT zone,
-- instead of guessing why the zone filter isn't narrowing things down. If
-- this lists nodes whose x/y are wildly outside 0-1 (or just far more nodes
-- than this one zone could ever have), that proves the API itself isn't
-- zone-scoped the way ForeverDungeonJournal's own per-zone iteration
-- implied it would be -- which is a real, useful thing to confirm before
-- changing the filtering logic any further.
function FlightPoints.Debug()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end

	local uiMapID = C_Map.GetBestMapForUnit("player")
	local mapInfo = uiMapID and C_Map.GetMapInfo(uiMapID)
	add("current zone: " .. tostring(mapInfo and mapInfo.name) .. "  (uiMapID " .. tostring(uiMapID) .. ")")
	add("map type: " .. tostring(mapInfo and mapInfo.mapType) .. "  (3 = zone, 2 = continent, 4 = dungeon)")
	add("GetTaxiNodesForMap exists: " .. tostring(C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap ~= nil))

	-- What Wayfinder actually hands the compass and map after its filters.
	local okAll, drawn = pcall(FlightPoints.GetAll)
	if okAll then
		local names = {}
		for _, fp in ipairs(drawn) do names[#names + 1] = fp.name end
		add("Wayfinder draws " .. #drawn .. ": " .. (#names > 0 and table.concat(names, ", ") or "(none)"))
	else
		add("Wayfinder GetAll ERROR: " .. tostring(drawn))
	end
	add("compass setting=" .. tostring(PC.db.options.showFlightPathsCompass)
		.. "  map setting=" .. tostring(PC.db.options.showFlightPathsMap))

	if uiMapID and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
		local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, uiMapID)
		add("pcall ok: " .. tostring(ok) .. "   node count: " .. tostring(type(nodes) == "table" and #nodes or nodes))
		add("")
		if ok and type(nodes) == "table" then
			for i, node in ipairs(nodes) do
				local x, y = node.position and node.position.x, node.position and node.position.y
				if (x == nil or y == nil) and node.position and node.position.GetXY then x, y = node.position:GetXY() end
				add(string.format("[%d] %-28s faction=%-6s x=%-10s y=%-10s nodeID=%s",
					i, tostring(node.name), tostring(node.faction), tostring(x), tostring(y), tostring(node.nodeID)))
			end
		end
	end

	showCopyableText("Wayfinder flight debug", table.concat(lines, "\n"))
	print("|cff33ff99Wayfinder|r flight debug window opened -- click inside it, Ctrl+A then Ctrl+C, then paste it back.")
end

-- Finds every continent by walking up from your current map to the world
-- map and listing its continents. Falls back to the classic Kalimdor and
-- Eastern Kingdoms map IDs if that walk finds nothing.
local function allContinents()
	local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
	local WORLD = (Enum and Enum.UIMapType and Enum.UIMapType.World) or 1
	local mapID = C_Map.GetBestMapForUnit("player")
	for _ = 1, 10 do
		local info = mapID and C_Map.GetMapInfo(mapID)
		if not info then break end
		if info.mapType == WORLD then
			local ok, kids = pcall(C_Map.GetMapChildrenInfo, mapID, CONTINENT)
			if ok and type(kids) == "table" and #kids > 0 then return kids end
			break
		end
		mapID = info.parentMapID
	end
	local fallback = {}
	for _, id in ipairs({ 1414, 1415 }) do
		local info = C_Map.GetMapInfo(id)
		if info then fallback[#fallback + 1] = info end
	end
	return fallback
end

-- /wf flightzones -- runs Wayfinder's zone filter on every zone of every
-- continent from wherever you stand, so a continent can be tested without
-- travelling there. OK = 1-8 points kept (what the compass would show),
-- NONE = zero kept, TOO MANY = the cap would hide them all.
function FlightPoints.ZoneReport()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end
	local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and C_Map.GetMapChildrenInfo) then
		add("Missing API: GetTaxiNodesForMap or GetMapChildrenInfo.")
	else
		local continents = allContinents()
		if #continents == 0 then add("No continents found.") end
		for _, continent in ipairs(continents) do
			add(string.format("=== %s (uiMapID %s) ===", tostring(continent.name), tostring(continent.mapID)))
			local ok, zones = pcall(C_Map.GetMapChildrenInfo, continent.mapID, ZONE)
			if not ok or type(zones) ~= "table" then zones = {} end
			table.sort(zones, function(a, b) return tostring(a.name) < tostring(b.name) end)
			local sampleShown = false
			for _, zone in ipairs(zones) do
				local kept, raw = FlightPoints.NodesInMap(zone.mapID)
				local verdict = (#kept == 0 and "NONE") or (#kept > MAX_NODES_IN_ONE_ZONE and "TOO MANY") or "OK"
				local names = {}
				for i, fp in ipairs(kept) do
					if i <= 4 then names[#names + 1] = fp.name end
				end
				if #kept > 4 then names[#names + 1] = "..." end
				add(string.format("%-8s %-24s map=%-5s game gave %-3d kept %-3d %s",
					verdict, tostring(zone.name), tostring(zone.mapID), raw, #kept, table.concat(names, ", ")))

				-- Raw positions for the first zone that keeps too many, so
				-- the coordinate pattern behind the failure is visible.
				if verdict == "TOO MANY" and not sampleShown then
					sampleShown = true
					local okN, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, zone.mapID)
					if okN and type(nodes) == "table" then
						for i, node in ipairs(nodes) do
							if i > 12 then add("      ...") break end
							local x, y = node.position and node.position.x, node.position and node.position.y
							if (x == nil or y == nil) and node.position and node.position.GetXY then x, y = node.position:GetXY() end
							add(string.format("      %-28s faction=%-4s x=%-8s y=%s", tostring(node.name),
								tostring(node.faction),
								type(x) == "number" and string.format("%.3f", x) or tostring(x),
								type(y) == "number" and string.format("%.3f", y) or tostring(y)))
						end
					end
				end
			end
			add("")
		end
	end

	showCopyableText("Wayfinder flight zones", table.concat(lines, "\n"))
end

function FlightPoints.Init()
	local watch = CreateFrame("Frame")
	for _, event in ipairs({ "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TAXI_NODE_STATUS_CHANGED" }) do
		pcall(watch.RegisterEvent, watch, event)
	end
	watch:SetScript("OnEvent", function(_, event)
		if event == "TAXIMAP_OPENED" then
			taxiMapOpen = true
			pcall(recordFlightMap)
		elseif event == "TAXIMAP_CLOSED" then
			taxiMapOpen = false
		elseif event == "TAXI_NODE_STATUS_CHANGED" then
			pcall(recordFlightMap)
		end
	end)
end
