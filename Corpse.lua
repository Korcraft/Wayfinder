-- Wayfinder: Corpse.lua
-- Tracks your own corpse's location while you're a ghost, so the compass
-- and world map can point you back to it during a corpse run.
--
-- C_DeathInfo.GetCorpseMapPosition(uiMapID), the parent-map walk (the
-- corpse's registered position isn't always on your own current sub-zone
-- map), and the "record where you died" fallback for when that API never
-- resolves at all -- confirmed real via ForeverDungeonJournal's own working
-- corpse-run arrow (Systems/MapMarkers.lua's Way.Corpse()), not guessed.
-- GetCorpseMapPosition can return either a Vector2D-shaped table (.x/.y or
-- :GetXY()) or two plain numbers depending on API version, so both shapes
-- are handled, same as FDJ's own code does.

local PC = Wayfinder
PC.Corpse = PC.Corpse or {}
local Corpse = PC.Corpse

-- {mapID=, x=, y=} -- recorded the instant you die, in case
-- GetCorpseMapPosition never resolves a position at all (a confirmed real
-- gap FDJ itself hit and fixed the same way).
local diedAt = nil

local function isValidSpot(x, y)
	if type(issecretvalue) == "function" and (issecretvalue(x) or issecretvalue(y)) then return false end
	return type(x) == "number" and type(y) == "number" and x > 0 and y > 0 and x < 1 and y < 1
end

local function resolveCorpsePosition(mapID)
	if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return nil, nil end
	local ok, pos, posY = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
	if not ok then return nil, nil end
	local x, y
	if type(pos) == "table" then
		x, y = pos.x, pos.y
		if (x == nil or y == nil) and pos.GetXY then
			local okXY
			okXY, x, y = pcall(pos.GetXY, pos)
			if not okXY then x, y = nil, nil end
		end
	elseif type(pos) == "number" then
		x, y = pos, posY
	end
	return x, y
end

-- Returns (uiMapID, x, y) for your corpse, or nil if you're not a ghost or
-- nothing resolves at all. Walks up the parent map chain the same way FDJ
-- does, since the corpse's own registered position isn't always on your
-- current sub-zone map -- up to 4 levels, matching FDJ's own guard.
function Corpse.GetPosition()
	if type(UnitIsGhost) ~= "function" then return nil end
	local okGhost, ghost = pcall(UnitIsGhost, "player")
	if not okGhost or (type(issecretvalue) == "function" and issecretvalue(ghost)) or ghost ~= true then
		return nil
	end

	local mapID = C_Map.GetBestMapForUnit("player")
	local guard = 0
	while mapID and guard < 4 do
		local x, y = resolveCorpsePosition(mapID)
		if isValidSpot(x, y) then
			return mapID, x, y
		end
		local okInfo, info = pcall(C_Map.GetMapInfo, mapID)
		mapID = okInfo and type(info) == "table" and info.parentMapID or nil
		if mapID == 0 then mapID = nil end
		guard = guard + 1
	end

	if diedAt then
		return diedAt.mapID, diedAt.x, diedAt.y
	end
	return nil
end

function Corpse.Init()
	local watch = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }) do
		pcall(watch.RegisterEvent, watch, event)
	end
	watch:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_DEAD" then
			diedAt = nil
			local mapID = C_Map.GetBestMapForUnit("player")
			if mapID then
				local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
				local x, y
				if okP and pos then
					local okXY
					okXY, x, y = pcall(pos.GetXY, pos)
					if not okXY then x, y = nil, nil end
				end
				if isValidSpot(x, y) then
					diedAt = { mapID = mapID, x = x, y = y }
				end
			end
		elseif event == "PLAYER_UNGHOST" then
			-- Alive again -- the old death location is no longer relevant.
			diedAt = nil
		end
	end)
end

-- /wf corpsecheck -- prints exactly what's being tracked, instead of
-- guessing why the icon isn't showing up.
function Corpse.Debug()
	print("|cff33ff99Wayfinder|r corpse debug:")
	local okGhost, ghost = pcall(UnitIsGhost, "player")
	print("  UnitIsGhost(\"player\"): ok=" .. tostring(okGhost) .. "  value=" .. tostring(ghost))
	local mapID, x, y = Corpse.GetPosition()
	print(string.format("  GetPosition(): mapID=%s x=%s y=%s", tostring(mapID), tostring(x), tostring(y)))
	print("  diedAt fallback: " .. (diedAt
		and string.format("mapID=%s x=%.4f y=%.4f", tostring(diedAt.mapID), diedAt.x, diedAt.y)
		or "nil"))
end
