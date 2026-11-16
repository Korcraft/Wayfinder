-- Wayfinder: PartyTracker.lua
-- Live positions of your current party/raid members, read straight from the
-- client -- no addon-message networking needed for this part. C_Map will
-- report a position for any group member it can resolve, the same technique
-- other group-aware addons use (confirmed against QuestTogether's own code,
-- which is already installed and working on this Forever client).
--
-- Party members are tracked regardless of what zone they're in. A bearing
-- is still only meaningful between two positions expressed in the SAME
-- coordinate space, so when a member is in a different zone than you, this
-- walks both of your maps up through their parent maps (zone -> continent
-- -> ...) to find the closest ancestor map where you BOTH resolve a
-- position (usually the continent), and computes the bearing from there.
-- That's real geography, just coarser -- not a guess. The one genuine
-- ceiling: if there's truly no shared map (different continent, a
-- dungeon/instance, etc.), no bearing exists at all; Compass.lua pins those
-- members to the compass's edge instead of hiding them, so they're still
-- visibly present as you asked, just without a direction.

local PC = Wayfinder
PC.PartyTracker = PC.PartyTracker or {}
local PartyTracker = PC.PartyTracker

function PartyTracker.Init() end

function PartyTracker.GetAll()
	local list = {}
	if not PC.db.options.showParty then return list end
	if not IsInGroup() then return list end

	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	else
		for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
	end

	for _, unit in ipairs(units) do
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local ok, mapID = pcall(C_Map.GetBestMapForUnit, unit)
			if ok and mapID then
				list[#list + 1] = { unit = unit, name = UnitName(unit), uiMapID = mapID }
			end
		end
	end
	return list
end

-- The same class color the game itself uses on unit frames/nameplates/the
-- minimap (RAID_CLASS_COLORS keyed by English class token, a long-standing
-- stable Blizzard global). Falls back to a neutral gray if class info
-- hasn't loaded yet for this unit (can briefly happen right as someone
-- comes into range).
function PartyTracker.ClassColor(unit)
	local _, classToken = UnitClass(unit)
	local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
	if c then
		return { c.r, c.g, c.b }
	end
	return { 0.7, 0.7, 0.7 }
end

-- uiMapID -> {uiMapID, parentMapID, parentMapID's parent, ...} up to the root.
local function mapChain(uiMapID)
	local chain = {}
	local seen = {}
	while uiMapID and uiMapID ~= 0 and not seen[uiMapID] do
		chain[#chain + 1] = uiMapID
		seen[uiMapID] = true
		local ok, info = pcall(C_Map.GetMapInfo, uiMapID)
		uiMapID = ok and info and info.parentMapID
	end
	return chain
end

-- Finds the closest map both you and `unit` can be positioned on, and
-- returns (commonMapID, yourX, yourY, theirX, theirY) -- or nil if no
-- shared map resolves a position for both of you.
function PartyTracker.GetCommonMapPosition(unit, unitMapID)
	local playerMapID = C_Map.GetBestMapForUnit("player")
	if not playerMapID or not unitMapID then return nil end

	local unitAncestors = {}
	for _, id in ipairs(mapChain(unitMapID)) do unitAncestors[id] = true end

	for _, candidate in ipairs(mapChain(playerMapID)) do
		if unitAncestors[candidate] then
			local okP, posP = pcall(C_Map.GetPlayerMapPosition, candidate, "player")
			local okU, posU = pcall(C_Map.GetPlayerMapPosition, candidate, unit)
			if okP and posP and okU and posU then
				local px, py = posP:GetXY()
				local ux, uy = posU:GetXY()
				return candidate, px, py, ux, uy
			end
		end
	end
	return nil
end
