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

-- Every flight point on the CURRENT zone's map, found or not -- see
-- Compass.lua/MapPins.lua for how showFlightPathsCompass/showFlightPathsMap
-- separately gate whether these actually get drawn.
function FlightPoints.GetAll()
	local list = {}
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return list end

	local uiMapID = C_Map.GetBestMapForUnit("player")
	if not uiMapID then return list end

	local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, uiMapID)
	if not ok or type(nodes) ~= "table" then return list end

	-- See the file header -- GetTaxiNodesForMap doesn't zone-filter on this
	-- client at all, so THIS bounds check is what actually restricts the
	-- list to your current zone. Small margin for floating-point jitter
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
			if x and y and inBounds(x) and inBounds(y) and type(node.name) == "string" and node.name ~= "" then
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
	return list
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
	add("GetTaxiNodesForMap exists: " .. tostring(C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap ~= nil))

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
