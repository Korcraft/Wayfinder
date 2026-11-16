-- PartyCompass: Quests.lua
-- Surfaces objective-waypoint locations for quests in your log, for the
-- quests Blizzard actually attached waypoint data to.
--
-- REAL LIMITATION, not a bug: plenty of quests -- especially older/simpler
-- ones -- were never given this waypoint data, vanilla-style quests included.
-- This will only ever show SOME of your quests. The default map's own quest
-- markers (which this addon doesn't touch) may still know more than we can
-- surface here.
--
-- Already zone-scoped by construction: GetNextWaypointForMap is asked about
-- the player's current specific zone map, so a quest whose objective is in
-- a different zone simply returns nil here -- no extra filtering needed.
--
-- The number shown is the same one Blizzard's own quest tracker shows next
-- to each tracked quest (confirmed via GetNumQuestWatches/
-- GetQuestIndexForWatch, already used by addons installed on this client).
-- Only quests you're actively tracking get a number, same as the tracker;
-- anything else falls back to the generic "Q" swatch.

local PC = PartyCompass
PC.Quests = PC.Quests or {}
local Quests = PC.Quests

function Quests.Init() end

-- Returns the tracker slot number (1, 2, 3...) for this quest if it's
-- currently being watched/tracked, or nil if it isn't.
local function trackerNumberFor(questID)
	if not (C_QuestLog and C_QuestLog.GetNumQuestWatches and GetQuestIndexForWatch) then return nil end
	local ok, count = pcall(C_QuestLog.GetNumQuestWatches)
	if not ok or not count then return nil end
	for i = 1, count do
		local ok2, watchedID = pcall(GetQuestIndexForWatch, i)
		if ok2 and watchedID == questID then
			return i
		end
	end
	return nil
end

local warnedMissingAPI = false

function Quests.GetAll()
	local list = {}
	if not PC.db.options.showQuests then return list end
	if not (C_QuestLog and C_QuestLog.GetNextWaypointForMap) then
		-- This specific call couldn't be confirmed against any installed
		-- addon's code (unlike GetNumQuestLogEntries/GetInfo, which are
		-- verified real and in active use on this client) -- say so once,
		-- out loud, instead of just showing nothing forever with no clue why.
		if not warnedMissingAPI then
			warnedMissingAPI = true
			print("|cffff4444PartyCompass|r C_QuestLog.GetNextWaypointForMap doesn't exist on this client -- quest objectives can't be shown on the compass.")
		end
		return list
	end

	local uiMapID = C_Map.GetBestMapForUnit("player")
	if not uiMapID then return list end

	local numEntries = C_QuestLog.GetNumQuestLogEntries()
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader then
			local ok, x, y = pcall(C_QuestLog.GetNextWaypointForMap, info.questID, uiMapID)
			if ok and x and y then
				list[#list + 1] = {
					questID = info.questID,
					title = info.title,
					trackerNumber = trackerNumberFor(info.questID),
					uiMapID = uiMapID,
					position = { x = x, y = y },
				}
			end
		end
	end
	return list
end
