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
-- "Focused" means super-tracked -- Blizzard's own single-quest concept
-- (the one quest that gets the on-screen directional arrow/highlight in
-- the tracker), NOT "watched" -- GetNumQuestWatches/GetQuestIDForQuestWatchIndex
-- cover every quest shown in the tracker panel, which on this client
-- defaults to nearly your whole log, so using that for "the highlighted
-- one" ended up highlighting almost everything. C_SuperTrack.
-- GetSuperTrackedQuestID/IsSuperTrackingQuest/SetSuperTrackedQuestID are
-- confirmed real and used this exact way by QuestTogether on this client
-- (including passing questID 0 to clear it).

local PC = Wayfinder
PC.Quests = PC.Quests or {}
local Quests = PC.Quests

function Quests.Init() end

local function isFocused(questID)
	if not (C_SuperTrack and C_SuperTrack.IsSuperTrackingQuest and C_SuperTrack.GetSuperTrackedQuestID) then
		return false
	end
	local ok, tracking = pcall(C_SuperTrack.IsSuperTrackingQuest)
	if not ok or not tracking then return false end
	local ok2, focusedID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
	return ok2 and focusedID == questID
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

function Quests.GetAll()
	local list = {}
	if not PC.db.options.showQuests then return list end
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return list end

	local uiMapID = C_Map.GetBestMapForUnit("player")
	if not uiMapID then return list end

	local poiCache = buildPOICache(uiMapID)
	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader then
			local x, y = findPosition(info.questID, uiMapID, poiCache)
			if x and y then
				local completeOk, completed = pcall(C_QuestLog.IsComplete, info.questID)
				list[#list + 1] = {
					questID = info.questID,
					title = info.title,
					focused = isFocused(info.questID),
					completed = completeOk and completed or false,
					uiMapID = uiMapID,
					position = { x = x, y = y },
				}
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

	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	print("  quest log entries: " .. tostring(numEntries))

	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader then
			local x, y = findPosition(info.questID, uiMapID, poiCache)
			print(string.format("  [%d] %s -- x=%s y=%s", info.questID, info.title, tostring(x), tostring(y)))
		end
	end
end
