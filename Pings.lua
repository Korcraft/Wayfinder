-- PartyCompass: Pings.lua
-- Quick, non-persistent "look here" markers (MOBA-style), separate from the
-- persistent shared waypoints in Waypoints.lua. A ping just flashes on the
-- map for a few seconds and then disappears -- nothing is saved.
--
-- Rendering lives in MapPins.lua's unified pin provider now (and in
-- Compass.lua for the HUD strip) -- this file just owns the data: which
-- pings are currently active, and expiring them after PING_LIFETIME.

local PC = PartyCompass
PC.Pings = PC.Pings or {}
local Pings = PC.Pings

local PING_LIFETIME = 5 -- seconds
local activePings = {} -- list of { uiMapID, position, who, expires }

function Pings.Init()
	local ticker = CreateFrame("Frame")
	ticker:SetScript("OnUpdate", function()
		local now = GetTime()
		local anyExpired = false
		for i = #activePings, 1, -1 do
			if now >= activePings[i].expires then
				table.remove(activePings, i)
				anyExpired = true
			end
		end
		if anyExpired and PC.MapPins then
			PC.MapPins.Refresh()
		end
	end)
end

-- Broadcasts (and shows locally) a ping at an arbitrary map position -- the
-- shared core behind both "ping where I'm standing" and "ping wherever I
-- just clicked on the world map" (see MapPins.lua's click handler).
function Pings.SendAt(uiMapID, x, y)
	local point = { uiMapID = uiMapID, position = { x = x, y = y } }
	Pings.Add("You", point)
	PC.Comm.BroadcastPing(point)
end

-- Broadcasts a ping at your current position.
function Pings.SendMine()
	local uiMapID = C_Map.GetBestMapForUnit("player")
	if not uiMapID then return end
	local pos = C_Map.GetPlayerMapPosition(uiMapID, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	Pings.SendAt(uiMapID, x, y)
end

function Pings.ReceivePing(who, point)
	Pings.Add(who, point)
end

function Pings.Add(who, point)
	activePings[#activePings + 1] = {
		uiMapID = point.uiMapID,
		position = point.position,
		who = who,
		expires = GetTime() + PING_LIFETIME,
	}
	print(string.format("|cff33ff99PartyCompass|r %s pinged the map.", who))
	if PC.MapPins then PC.MapPins.Refresh() end
end

-- Snapshot for the compass and MapPins' data provider -- just the still-
-- active pings, same shape as the other categories' GetAll().
function Pings.GetAll()
	local list = {}
	for _, p in ipairs(activePings) do
		list[#list + 1] = { uiMapID = p.uiMapID, position = p.position, who = p.who }
	end
	return list
end
