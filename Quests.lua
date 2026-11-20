-- Wayfinder: Quests.lua
-- Surfaces objective-waypoint locations for quests in your log, for the
-- quests Blizzard actually attached position data to.
--
-- Three independent data sources are tried in order (see findPosition) --
-- GetNextWaypoint/GetNextWaypointForMap came back empty for every quest
-- tested on this client (confirmed via /wf questcheck), so the fallback to
-- GetQuestsOnMap (the same POI list behind the native map's own quest
-- markers) is what actually makes this work here.
--
-- REAL LIMITATION, not a bug: plenty of quests -- especially older/simpler
-- ones -- genuinely have no position data anywhere Blizzard exposes, even
-- with all three sources tried. This will only ever show SOME of your
-- quests.
--
-- Zone-scoped by construction: every source is asked about (or checked
-- against) the player's current specific zone map, so a quest whose
-- objective is in a different zone simply returns nil here -- no extra
-- filtering needed.
--
-- Visibility rule (see GetAll): a quest only shows up here AT ALL if
-- it's tracked/watched -- same set Blizzard's own tracker panel shows
-- (GetNumQuestWatches/GetQuestIDForQuestWatchIndex). If something is
-- FOCUSED (super-tracked -- Blizzard's own single-quest concept, the one
-- that gets the on-screen directional arrow), that one quest is shown
-- INSTEAD of the tracked set, ignoring tracked status entirely -- not
-- alongside it. C_SuperTrack.GetSuperTrackedQuestID/IsSuperTrackingQuest/
-- SetSuperTrackedQuestID are confirmed real and used this exact way by
-- QuestTogether on this client (including passing questID 0 to clear it).

local PC = Wayfinder
PC.Quests = PC.Quests or {}
local Quests = PC.Quests

function Quests.Init() end

-- Returns the one focused (super-tracked) quest ID, or nil if none.
local function getFocusedQuestID()
	if not (C_SuperTrack and C_SuperTrack.IsSuperTrackingQuest and C_SuperTrack.GetSuperTrackedQuestID) then
		return nil
	end
	local ok, tracking = pcall(C_SuperTrack.IsSuperTrackingQuest)
	if not ok or not tracking then return nil end
	local ok2, focusedID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
	if ok2 then return focusedID end
	return nil
end

local function isFocused(questID)
	return getFocusedQuestID() == questID
end

-- Every currently tracked/watched quest ID (the same set Blizzard's own
-- tracker panel shows) -- confirmed real via GetNumQuestWatches/
-- GetQuestIDForQuestWatchIndex, already used this way elsewhere in this
-- file. Used when nothing is focused, so quests only show up at all if
-- they're being tracked.
local function getWatchedQuestIDs()
	local watched = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex) then
		return watched
	end
	local ok, count = pcall(C_QuestLog.GetNumQuestWatches)
	if not ok or not count then return watched end
	for i = 1, count do
		local ok2, questID = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
		if ok2 and questID then watched[questID] = true end
	end
	return watched
end

-- Sets (or clears, if it's already the focused one) this quest as the
-- single highlighted/super-tracked quest. Used by right-clicking a quest
-- icon on the compass -- see Compass.lua's makeQuestPool.
function Quests.ToggleFocus(questID)
	if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
	if isFocused(questID) then
		pcall(C_SuperTrack.SetSuperTrackedQuestID, 0)
	else
		pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
	end
end

-- Three independent ways to find a quest's position on the CURRENT map, in
-- order -- mirrors the fallback chain a real, working compass addon
-- (CompassHUD) uses, since C_QuestLog.GetNextWaypoint/GetNextWaypointForMap
-- alone came back empty for every quest tested on this client (confirmed
-- via /wf questcheck, not guessed). NOTE: GetNextWaypoint returns
-- (uiMapID, x, y) -- map ID FIRST -- unlike GetNextWaypointForMap's (x, y).
-- Getting that order backwards was the bug in the first version of this.
local function findPosition(questID, uiMapID, poiCache)
	if C_QuestLog.GetNextWaypoint then
		local ok, wpMapID, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
		if ok and wpMapID == uiMapID and x and y then
			return x, y
		end
	end

	if C_QuestLog.GetNextWaypointForMap then
		local ok, x, y = pcall(C_QuestLog.GetNextWaypointForMap, questID, uiMapID)
		if ok and x and y then
			return x, y
		end
	end

	-- Same POI list that drives the native in-game map's own quest markers
	-- (confirmed real and in use by other installed addons -- QuestieTrace,
	-- QuestTogether) -- built once per GetAll() call, not per-quest.
	if poiCache then
		local poi = poiCache[questID]
		if poi and poi.x and poi.y then
			return poi.x, poi.y
		end
	end
	return nil
end

local function buildPOICache(uiMapID)
	if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return nil end
	local ok, pois = pcall(C_QuestLog.GetQuestsOnMap, uiMapID)
	if not ok or not pois then return nil end
	local cache = {}
	for _, poi in ipairs(pois) do
		if poi.questID then
			cache[poi.questID] = poi
		end
	end
	return cache
end

-- Which zone a quest belongs to -- a DIFFERENT, more basic question than
-- "where exactly is its waypoint" (findPosition above), so it's worth
-- trying even though GetNextWaypoint's own coordinate resolution came back
-- empty for every quest tested on this client (see file header).
-- GetQuestUiMapID (confirmed real via Questie's own QuestieCompat.lua,
-- which documents and uses it this exact way, linking to the real Blizzard
-- API wiki page) only needs to know which map a quest is associated with,
-- not resolve a precise coordinate on it -- falls back to
-- GetNextWaypoint's own map-ID return (ignoring its x/y) only if the
-- direct API is missing entirely.
local function getQuestUiMapID(questID)
	if _G.GetQuestUiMapID then
		local ok, uiMapID = pcall(_G.GetQuestUiMapID, questID)
		if ok and uiMapID and uiMapID ~= 0 then return uiMapID end
	end
	if C_QuestLog and C_QuestLog.GetNextWaypoint then
		local ok, uiMapID = pcall(C_QuestLog.GetNextWaypoint, questID)
		if ok and uiMapID and uiMapID ~= 0 then return uiMapID end
	end
	return nil
end

-- uiMapID -> its own name, or nil if unresolvable.
local function mapName(uiMapID)
	local ok, info = pcall(C_Map.GetMapInfo, uiMapID)
	if not ok or not info then return nil end
	return info.name
end

-- uiMapID -> its continent-level ancestor's name, walking up the parent
-- chain (same technique as PartyTracker.lua's mapChain) until a map whose
-- mapType is genuinely Continent (confirmed real via Enum.UIMapType --
-- used this exact way by Questie/TellMeWhen/Spoken_Places on this client)
-- turns up, or nil if none does.
local function continentName(uiMapID)
	local id = uiMapID
	local seen = {}
	while id and id ~= 0 and not seen[id] do
		seen[id] = true
		local ok, info = pcall(C_Map.GetMapInfo, id)
		if not ok or not info then return nil end
		if info.mapType == Enum.UIMapType.Continent then
			return info.name
		end
		id = info.parentMapID
	end
	return nil
end

-- The two continents this server's leveling content spans -- used only to
-- pick a fixed compass direction for a focused quest on the OTHER
-- continent (see Compass.lua), nothing more geography-accurate than that.
local WEST_CONTINENT = "Kalimdor"
local EAST_CONTINENT = "Eastern Kingdoms"

-- Info for the focused quest, meant for when it ISN'T on your current map
-- (Compass.lua only calls this once the normal same-zone position lookup
-- already came up empty). Returns (label, direction, questID, title,
-- completed):
--   label     -> "Zone" normally, or "Zone - Continent" specifically when
--                the quest's continent differs from YOUR OWN current one
--                (not just "whenever a continent happens to resolve" --
--                that would append it even for a same-continent, different-
--                zone quest, which isn't useful context since you're
--                already on that continent)
--   direction -> "west" or "east" if the quest's continent is one of the
--                two known ones and differs from yours, else nil -- lets
--                Compass.lua show a fixed-direction icon for it, same idea
--                as Blizzard's own cross-continent supertrack arrow
--   questID/title/completed -> everything else a quest icon's style
--                function needs, so Compass.lua doesn't need a second
--                round-trip through the quest log for this one entry
-- All nil if nothing's focused or its zone can't be resolved at all.
function Quests.GetFocusedOutOfZoneInfo()
	local focusedQuestID = getFocusedQuestID()
	if not focusedQuestID then return nil end
	local questUiMapID = getQuestUiMapID(focusedQuestID)
	if not questUiMapID then return nil end

	local label = mapName(questUiMapID)
	if not label then return nil end

	local playerUiMapID = C_Map.GetBestMapForUnit("player")
	local questContinent = continentName(questUiMapID)
	local playerContinent = playerUiMapID and continentName(playerUiMapID)

	local direction = nil
	if questContinent and playerContinent and questContinent ~= playerContinent then
		label = label .. " - " .. questContinent
		if questContinent == WEST_CONTINENT then
			direction = "west"
		elseif questContinent == EAST_CONTINENT then
			direction = "east"
		end
	end

	local titleOk, title = pcall(C_QuestLog.GetTitleForQuestID, focusedQuestID)
	local completedOk, completed = pcall(C_QuestLog.IsComplete, focusedQuestID)

	return label, direction, focusedQuestID, titleOk and title or "", completedOk and completed or false
end

-- What should show: if a quest is focused, ONLY that one, ignoring
-- tracked/watched status entirely. Otherwise, every tracked quest.
function Quests.GetAll()
	local list = {}
	if not PC.db.options.showQuests then return list end
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return list end

	local uiMapID = C_Map.GetBestMapForUnit("player")
	if not uiMapID then return list end

	local focusedQuestID = getFocusedQuestID()
	local watchedIDs = not focusedQuestID and getWatchedQuestIDs() or nil

	local poiCache = buildPOICache(uiMapID)
	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader then
			local shouldShow = focusedQuestID and info.questID == focusedQuestID
				or (watchedIDs and watchedIDs[info.questID])
			if shouldShow then
				local x, y = findPosition(info.questID, uiMapID, poiCache)
				if x and y then
					local completeOk, completed = pcall(C_QuestLog.IsComplete, info.questID)
					list[#list + 1] = {
						questID = info.questID,
						title = info.title,
						focused = focusedQuestID ~= nil and info.questID == focusedQuestID,
						completed = completeOk and completed or false,
						uiMapID = uiMapID,
						position = { x = x, y = y },
					}
				end
			end
		end
	end
	return list
end

-- /wf questcheck -- prints exactly what's happening for every quest in your
-- log right now, instead of guessing why nothing's showing on the compass.
function Quests.Debug()
	print("|cff33ff99Wayfinder|r quest debug:")
	print("  showQuests option: " .. tostring(PC.db.options.showQuests))
	print("  GetNextWaypoint exists: " .. tostring(C_QuestLog and C_QuestLog.GetNextWaypoint ~= nil))
	print("  GetNextWaypointForMap exists: " .. tostring(C_QuestLog and C_QuestLog.GetNextWaypointForMap ~= nil))
	print("  GetQuestsOnMap exists: " .. tostring(C_QuestLog and C_QuestLog.GetQuestsOnMap ~= nil))
	print("  GetQuestIDForQuestWatchIndex exists: " .. tostring(C_QuestLog and C_QuestLog.GetQuestIDForQuestWatchIndex ~= nil))
	print("  GetQuestUiMapID (raw global) exists: " .. tostring(_G.GetQuestUiMapID ~= nil))
	local outOfZoneLabel, outOfZoneDirection = Quests.GetFocusedOutOfZoneInfo()
	print("  focused quest out-of-zone label: " .. tostring(outOfZoneLabel) .. "  direction: " .. tostring(outOfZoneDirection))

	if C_QuestLog and C_QuestLog.GetNumQuestWatches then
		local ok, count = pcall(C_QuestLog.GetNumQuestWatches)
		print("  GetNumQuestWatches(): ok=" .. tostring(ok) .. " count=" .. tostring(count))
		if ok and count and C_QuestLog.GetQuestIDForQuestWatchIndex then
			for i = 1, count do
				local ok2, watchedID = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
				print(string.format("    watch slot %d -> ok=%s questID=%s", i, tostring(ok2), tostring(watchedID)))
			end
		end
	else
		print("  GetNumQuestWatches: missing")
	end

	local uiMapID = C_Map.GetBestMapForUnit("player")
	print("  current uiMapID: " .. tostring(uiMapID))
	if not uiMapID then return end

	local poiCache = buildPOICache(uiMapID)
	local poiCount = 0
	if poiCache then
		for _ in pairs(poiCache) do poiCount = poiCount + 1 end
	end
	print("  quests on map (POI list): " .. tostring(poiCache and poiCount or "unavailable"))

	local focusedQuestID = getFocusedQuestID()
	print("  focused questID: " .. tostring(focusedQuestID))
	local watchedIDs = not focusedQuestID and getWatchedQuestIDs() or nil

	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	print("  quest log entries: " .. tostring(numEntries))

	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader then
			local shouldShow = focusedQuestID and info.questID == focusedQuestID
				or (watchedIDs and watchedIDs[info.questID])
			local x, y = findPosition(info.questID, uiMapID, poiCache)
			print(string.format("  [%d] %s -- shown=%s x=%s y=%s",
				info.questID, info.title, tostring(shouldShow and true or false), tostring(x), tostring(y)))
		end
	end
end
