-- Wayfinder: Waypoints.lua
-- Multiple NAMED, ICONED waypoints per player -- not just a single "my
-- waypoint" slot like the first version had. Each one is either:
--   permanent ("P") -- stays until someone removes it, and is LOCAL ONLY --
--     never shared with your party
--   temporary ("T") -- auto-expires ~15 minutes after creation, and IS
--     shared with your party (same as pings)
-- Stored per full player name so they survive roster reshuffles, and keyed
-- by a short per-waypoint id so you can have several at once and add/remove
-- them individually by name. Since permanent ones never leave your own
-- client, every waypoint you ever RECEIVE from someone else is necessarily
-- temporary.

local PC = Wayfinder
PC.Waypoints = PC.Waypoints or {}
local Waypoints = PC.Waypoints

local TEMP_DURATION = 15 * 60 -- seconds

-- Permanent waypoints are always white (icon + name tag), never round-robin
-- colored -- a fixed color means "permanent" at a glance.
Waypoints.PERMANENT_COLOR = { 1.0, 1.0, 1.0 }

-- Each TEMPORARY waypoint YOU create gets the next color in this list
-- (wrapping around past the end), so the first one is light blue, the
-- second green, etc. -- lets you tell "which one to run toward" apart on
-- the compass at a glance, without needing to read a label. Permanent
-- waypoints don't participate in this sequence at all (see
-- PERMANENT_COLOR above) -- white isn't in here, so nothing can be
-- mistaken for a permanent waypoint by color alone.
Waypoints.COLOR_SEQUENCE = {
	{ 0.5, 0.8, 1.0 }, -- light blue
	{ 0.2, 0.9, 0.2 }, -- green
	{ 0.3, 0.6, 1.0 }, -- blue
	{ 1.0, 0.6, 0.1 }, -- orange
	{ 1.0, 0.3, 0.8 }, -- pink
	{ 0.2, 0.9, 0.9 }, -- cyan
	{ 1.0, 0.9, 0.2 }, -- yellow
	{ 0.9, 0.15, 0.15 }, -- red
}

function Waypoints.Init() end

-- Both waypoint kinds render at the same size now (permanent used to be
-- drawn bigger as the "bolder" treatment, but that's gone now that they're
-- the same height) -- a direct pixel size now (slider in settings) instead
-- of a small/medium/large pick. The compass and the map each get their
-- own independent size setting.
function Waypoints.CompassIconSize()
	return PC.db.options.compassIconSize or 20
end

function Waypoints.MapIconSize()
	return PC.db.options.mapIconSize or 20
end

local function myFullName()
	local name, realm = UnitFullName("player")
	realm = realm ~= "" and realm or GetRealmName()
	return name .. "-" .. realm
end

-- Not cryptographically unique, just unique enough for "a few waypoints per
-- player in a party" -- a millisecond-ish time component plus a random tail.
local function genId()
	return string.format("%x%03d", math.floor(GetTime() * 1000) % 0xFFFFFF, math.random(0, 999))
end

local function hereAndNow()
	local uiMapID = C_Map.GetBestMapForUnit("player")
	local pos = uiMapID and C_Map.GetPlayerMapPosition(uiMapID, "player")
	if not uiMapID or not pos then return nil end
	local x, y = pos:GetXY()
	return uiMapID, { x = x, y = y }
end

-- Returns the color {r,g,b} for the Nth waypoint you've created (1st =
-- green, 2nd = blue, ...), wrapping back to the start of COLOR_SEQUENCE if
-- you have more active waypoints than it has colors.
local function colorForIndex(index)
	local seq = Waypoints.COLOR_SEQUENCE
	return seq[((index - 1) % #seq) + 1]
end

-- Core waypoint-creation logic, usable both for "at my own current
-- position" (Waypoints.Add, /wf wp add) and "at wherever I just clicked on
-- the world map" (MapPins.lua's click handler). Always your own waypoint.
-- Only TEMPORARY waypoints get broadcast to your party -- permanent ones
-- stay purely local to you. Returns the created entry.
function Waypoints.AddAt(uiMapID, position, name, iconNum, isTemp)
	if not name or name:trim() == "" then
		name = isTemp and "Waypoint" or "Waypoint"
	end

	local owner = myFullName()
	PC.db.waypoints[owner] = PC.db.waypoints[owner] or {}
	local list = PC.db.waypoints[owner]

	-- colorIndex only matters for temp waypoints (permanent ones are always
	-- PERMANENT_COLOR, not round-robin -- see Waypoints.lua's header), so
	-- only count existing TEMP ones here, so adding/removing permanent
	-- waypoints never shifts the temp color sequence.
	local count = 0
	for _, existing in pairs(list) do
		if existing.kind == "T" then count = count + 1 end
	end
	local colorIndex = count + 1

	local id = genId()
	local entry = {
		id = id, name = name, colorIndex = colorIndex, uiMapID = uiMapID, position = position,
		kind = isTemp and "T" or "P",
		-- time() (real wall-clock Unix time), NOT GetTime() (process uptime
		-- -- resets to ~0 on a full client restart, which would silently
		-- break this comparison for anything saved to disk beforehand).
		expires = isTemp and (time() + TEMP_DURATION) or nil,
		mine = true,
	}
	list[id] = entry
	if isTemp then
		PC.Comm.BroadcastWaypointAdd(entry)
	end
	if PC.MapPins then PC.MapPins.Refresh() end
	if PC.Compass then PC.Compass.Refresh() end
	return entry
end

Waypoints.colorForIndex = colorForIndex

-- Adds a new waypoint at your current position. isTemp = true makes it
-- auto-expire after ~15 minutes AND shares it with your party; otherwise
-- it's permanent, stays until removed with Waypoints.Remove, and stays
-- purely local to you.
function Waypoints.Add(name, iconNum, isTemp)
	if not name or name:trim() == "" then
		print("|cffff4444Wayfinder|r usage: /wf wp add <name>")
		return
	end
	local uiMapID, position = hereAndNow()
	if not uiMapID then
		print("|cffff4444Wayfinder|r couldn't determine your position.")
		return
	end
	-- No success print on purpose -- the icon appearing is the feedback,
	-- same reasoning as the silent map-click path (see MapPins.lua).
	Waypoints.AddAt(uiMapID, position, name, iconNum, isTemp)
end

-- Removes one of YOUR OWN waypoints by name and tells your party it's gone.
function Waypoints.Remove(name)
	local owner = myFullName()
	local list = PC.db.waypoints[owner]
	if not list then
		print("|cffff4444Wayfinder|r you have no waypoints to remove.")
		return
	end
	for id, entry in pairs(list) do
		if entry.name:lower() == (name or ""):lower() then
			list[id] = nil
			if entry.kind == "T" then
				PC.Comm.BroadcastWaypointRemove(id)
			end
			if PC.MapPins then PC.MapPins.Refresh() end
			if PC.Compass then PC.Compass.Refresh() end
			return
		end
	end
	print("|cffff4444Wayfinder|r you have no waypoint named \"" .. tostring(name) .. "\".")
end

-- Removes ALL of your own waypoints at once (handy for clearing out test
-- clutter) -- doesn't touch anything received from party members.
function Waypoints.ClearAll()
	local owner = myFullName()
	local list = PC.db.waypoints[owner]
	if not list or not next(list) then
		print("|cff33ff99Wayfinder|r you have no waypoints to clear.")
		return
	end
	local count = 0
	for id, entry in pairs(list) do
		if entry.kind == "T" then
			PC.Comm.BroadcastWaypointRemove(id)
		end
		list[id] = nil
		count = count + 1
	end
	if PC.MapPins then PC.MapPins.Refresh() end
	if PC.Compass then PC.Compass.Refresh() end
end

-- Wipes EVERY waypoint in your saved data, including ones received from
-- party members that ClearAll/Remove/FindNearest can't touch (those only
-- ever act on your own). Doesn't broadcast anything -- this only clears
-- your own local copy of received data, not anyone else's. For cleaning up
-- test clutter that's otherwise stuck.
function Waypoints.WipeAll()
	local count = 0
	for owner, list in pairs(PC.db.waypoints) do
		for id in pairs(list) do
			list[id] = nil
			count = count + 1
		end
		PC.db.waypoints[owner] = nil
	end
	if PC.MapPins then PC.MapPins.Refresh() end
	if PC.Compass then PC.Compass.Refresh() end
end

-- Renames one of YOUR OWN waypoints by id (used by double-clicking a
-- permanent waypoint's name tag on the map -- see MapPins.lua). Permanent
-- waypoints are always local-only, so there's nothing to broadcast.
function Waypoints.Rename(id, newName)
	if not newName or newName:trim() == "" then return end
	local owner = myFullName()
	local list = PC.db.waypoints[owner]
	local entry = list and list[id]
	if not entry then return end
	entry.name = newName
	if PC.MapPins then PC.MapPins.Refresh() end
	if PC.Compass then PC.Compass.Refresh() end
end

-- "Close enough to what you clicked" tolerance for removing a waypoint by
-- clicking near it (normalized map units, roughly 4% of the map's size).
local REMOVE_CLICK_RADIUS = 0.04

-- Finds whichever of YOUR OWN waypoints on this map is nearest (x,y) --
-- used by shift-clicking the world map -- WITHOUT removing it yet, so the
-- caller can decide (e.g. confirm before deleting a permanent one). Only
-- ever considers your own; same scope as the name-based /wf wp remove.
-- Returns id, entry or nil if nothing is close enough.
function Waypoints.FindNearest(uiMapID, x, y)
	local owner = myFullName()
	local list = PC.db.waypoints[owner]
	if not list then return nil end
	local bestId, bestDistSq
	for id, entry in pairs(list) do
		if entry.uiMapID == uiMapID then
			local dx, dy = entry.position.x - x, entry.position.y - y
			local distSq = dx * dx + dy * dy
			if not bestDistSq or distSq < bestDistSq then
				bestDistSq, bestId = distSq, id
			end
		end
	end
	if bestId and bestDistSq <= REMOVE_CLICK_RADIUS * REMOVE_CLICK_RADIUS then
		return bestId, list[bestId]
	end
	return nil
end

-- Removes one of your own waypoints by its exact id (used after
-- FindNearest, directly for temp ones or after a delete confirmation for
-- permanent ones -- see MapPins.lua's shift-click handling). Only ever
-- called from map clicks, so no chat print here on purpose -- the icon
-- disappearing is the feedback; see MapPins.lua's handleMapClick.
function Waypoints.RemoveByID(id)
	local owner = myFullName()
	local list = PC.db.waypoints[owner]
	local entry = list and list[id]
	if not entry then return end
	list[id] = nil
	if entry.kind == "T" then
		PC.Comm.BroadcastWaypointRemove(id)
	end
	if PC.MapPins then PC.MapPins.Refresh() end
	if PC.Compass then PC.Compass.Refresh() end
end

-- Called by Comm when a party member adds/updates a waypoint.
function Waypoints.ReceiveAdd(owner, entry)
	PC.db.waypoints[owner] = PC.db.waypoints[owner] or {}
	PC.db.waypoints[owner][entry.id] = entry
	if PC.MapPins then PC.MapPins.Refresh() end
	if PC.Compass then PC.Compass.Refresh() end
end

function Waypoints.ReceiveRemove(owner, id)
	if PC.db.waypoints[owner] then
		PC.db.waypoints[owner][id] = nil
	end
	if PC.MapPins then PC.MapPins.Refresh() end
	if PC.Compass then PC.Compass.Refresh() end
end

-- Flattened, pruned snapshot of every active waypoint (yours + your
-- party's). Temporary waypoints past their expiry are deleted here as a
-- side effect, so nothing else needs its own cleanup timer.
function Waypoints.GetAll()
	local now = time()
	local list = {}
	for owner, entries in pairs(PC.db.waypoints) do
		for id, entry in pairs(entries) do
			if entry.kind == "T" and entry.expires and now > entry.expires then
				entries[id] = nil -- safe: clearing an existing key mid-pairs() traversal
			else
				list[#list + 1] = {
					owner = owner, id = entry.id, name = entry.name, colorIndex = entry.colorIndex,
					uiMapID = entry.uiMapID, position = entry.position,
					kind = entry.kind, expires = entry.expires, mine = entry.mine,
				}
			end
		end
	end
	return list
end

-- Removes every stored waypoint from players no longer in your group --
-- including a full disband, where nobody but you is left. Received
-- waypoints are always temporary (see the header comment -- permanent ones
-- never leave their owner's own client), so there's nothing to
-- re-broadcast here; this only touches your own local copy, same privacy
-- model as WipeAll. YOUR OWN waypoints are never touched by this, even
-- once you're solo -- they still have personal navigation value.
function Waypoints.PruneDepartedMembers()
	if not PC.db then return end
	local valid = { [myFullName()] = true }
	if IsInGroup() then
		local units = {}
		if IsInRaid() then
			for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
		else
			for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
		end
		for _, unit in ipairs(units) do
			if UnitExists(unit) then
				-- Addon-message senders arrive as either "Name-Realm" or
				-- just "Name" (see Comm.lua), so accept both forms here
				-- rather than assume one.
				local shortName = UnitName(unit)
				if shortName then valid[shortName] = true end
				local name, realm = UnitFullName(unit)
				if name then
					realm = realm ~= "" and realm or GetRealmName()
					valid[name .. "-" .. realm] = true
				end
			end
		end
	end

	local removed = 0
	for owner, list in pairs(PC.db.waypoints) do
		if not valid[owner] then
			for _ in pairs(list) do removed = removed + 1 end
			PC.db.waypoints[owner] = nil
		end
	end

	if removed > 0 then
		if PC.MapPins then PC.MapPins.Refresh() end
		if PC.Compass then PC.Compass.Refresh() end
	end
end

local pruneFrame = CreateFrame("Frame")
pruneFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
pruneFrame:SetScript("OnEvent", Waypoints.PruneDepartedMembers)

function Waypoints.PrintAll()
	local list = Waypoints.GetAll()
	if #list == 0 then
		print("|cff33ff99Wayfinder|r no active waypoints.")
		return
	end
	local now = time()
	for _, wp in ipairs(list) do
		local mapInfo = C_Map.GetMapInfo(wp.uiMapID)
		local mapName = mapInfo and mapInfo.name or ("map " .. wp.uiMapID)
		local status = (wp.kind == "T")
			and string.format("[temp, %dm left]", math.max(0, math.floor((wp.expires - now) / 60)))
			or "[permanent]"
		print(string.format("|cff33ff99Wayfinder|r %s%s \"%s\" %s - %s (%.0f, %.0f)",
			wp.mine and "[You] " or "", wp.owner, wp.name, status, mapName,
			wp.position.x * 100, wp.position.y * 100))
	end
end
