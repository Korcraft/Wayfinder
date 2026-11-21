-- Wayfinder: Locations.lua
-- Static, baked-in locations for auction houses, banks, innkeepers, and
-- mailboxes. Extracted from Questie's own data via a temporary dev tool
-- (WayfinderExtract, since deleted) and reviewed by hand before being
-- committed here -- Wayfinder has NO runtime dependency on Questie; this
-- file is the only trace that extraction ever happened. Auctioneer/
-- Banker/Innkeeper came from Questie's NPC-flag data (Townsfolk module);
-- Mailbox came from its separate OBJECT data (gameobject_template IDs,
-- via Townsfolk.GetMailboxes() + QuestieDB.QueryObjectSingle), since a
-- mailbox is a world object you right-click, not an NPC.
--
-- Each entry also carries an optional `faction` field -- 1 for Horde-only,
-- 2 for Alliance-only, omitted for faction-neutral -- re-extracted
-- alongside the coordinates themselves: NPC entries from Questie's own
-- QuestieDB.QueryNPCSingle(id, "friendlyToFaction") ("A"/"H"/"AH"/nil),
-- Mailbox entries from Townsfolk.GetFactionSpecificMailboxes()'s real
-- alliance/horde split (itself derived from each mailbox object's real
-- factionTemplate bits, not guessed). This was a real gap before -- every
-- entry here used to show on the compass/map for both factions regardless
-- of whose territory it was actually in. Same convention as
-- FlightPoints.lua's own node.faction/oursToSee() -- that one is already
-- correct because it reads a live per-node faction field straight from
-- C_TaxiMap; this file needed its own one-time extraction to catch up
-- since static baked-in data has no live field to read.
--
-- Each entry is one real-world LOCATION (a building/outpost), not one NPC.
-- Several raw NPCs standing in the same spot -- Stormwind's 3 bank
-- tellers, Undercity's many scattered auctioneers, etc. -- were merged
-- into a single point during review, since a player thinks of those as
-- "the bank" / "the auction house", not N separate markers. Zones with
-- more than one legitimate separate town (Hillsbrad's Southshore AND
-- Tarren Mill, The Barrens' three outposts, etc.) correctly kept their
-- entries distinct.
--
-- x/y are normalized 0-1 for the given uiMapID, same convention as every
-- other Wayfinder marker (waypoints, quests, flight points) -- no
-- conversion needed to use these directly.
--
-- TODO: Winterspring's Auctioneer (Grizzlin, npcId 9857) was deliberately
-- left out -- Winterspring never had an AH in classic WoW, so this needs
-- confirming as real/intentional Forever content before it gets added.
-- Winterspring's Banker and Innkeeper WERE kept (only the Auctioneer was
-- in question). Investigate and add the Auctioneer entry if it checks out:
--   uiMapID = 1452, x = 0.6145, y = 0.3720, zoneName = "Winterspring"
--
-- Deliberately excluded (not a TODO -- not expected to ever be added):
-- "Auctioneer Quickcoin" / "Uninspected Shipment" (npcId 258878 / 258880),
-- which both showed up in The Barrens AND Redridge Mountains at oddly
-- specific, non-town coordinates, flagged as both an Auctioneer AND a
-- Banker. That pattern (same NPC, two unrelated zones, double-flagged)
-- points to a quest-chain NPC (a smuggling/black-market questline), not a
-- real fixed vendor.
--
-- TODO: the Mailbox list has NO entries on any of the new Forever
-- continents (Riverglades, Zephras Isle, Mount Hyjal, Shen'dralas), unlike
-- Auctioneer/Banker/Innkeeper above which all have at least one. Questie's
-- mailbox list (Townsfolk.GetMailboxes()) is a hardcoded set of
-- gameobject_template IDs sourced from retail data, so it has no way to
-- know about a brand-new mailbox object Forever might have added on those
-- continents -- this gap is expected, not a sign anything broke. If those
-- zones turn out to have real mailboxes, they'll need their object IDs
-- found some other way (e.g. inspecting one in-game) and added by hand.

local PC = Wayfinder
PC.LocationsData = {
	Auctioneer = {
		{ uiMapID = 1457, x = 0.5637, y = 0.5182, zoneName = "Darnassus", faction = 2 },
		{ uiMapID = 1455, x = 0.2377, y = 0.7179, zoneName = "Ironforge", faction = 2 },
		{ uiMapID = 1454, x = 0.5590, y = 0.6271, zoneName = "Orgrimmar", faction = 1 },
		{ uiMapID = 1453, x = 0.6085, y = 0.7152, zoneName = "Stormwind City", faction = 2 },
		{ uiMapID = 1434, x = 0.2778, y = 0.7705, zoneName = "Stranglethorn Vale" },
		{ uiMapID = 1446, x = 0.5196, y = 0.2965, zoneName = "Tanaris" },
		{ uiMapID = 1456, x = 0.4041, y = 0.5177, zoneName = "Thunder Bluff", faction = 1 },
		{ uiMapID = 1458, x = 0.6049, y = 0.4175, zoneName = "Undercity", faction = 1 },
		{ uiMapID = 1458, x = 0.7151, y = 0.4190, zoneName = "Undercity", faction = 1 },
		{ uiMapID = 1458, x = 0.6755, y = 0.5242, zoneName = "Undercity", faction = 1 },
		{ uiMapID = 2521, x = 0.5791, y = 0.7712, zoneName = "Zephras Isle" },
	},
	Banker = {
		{ uiMapID = 1457, x = 0.3939, y = 0.4244, zoneName = "Darnassus", faction = 2 },
		{ uiMapID = 1455, x = 0.3497, y = 0.5841, zoneName = "Ironforge", faction = 2 },
		{ uiMapID = 1454, x = 0.4958, y = 0.6912, zoneName = "Orgrimmar", faction = 1 },
		{ uiMapID = 2548, x = 0.7675, y = 0.5433, zoneName = "Riverglades" },
		{ uiMapID = 1453, x = 0.6429, y = 0.8075, zoneName = "Stormwind City", faction = 2 },
		{ uiMapID = 1434, x = 0.2654, y = 0.7657, zoneName = "Stranglethorn Vale" },
		{ uiMapID = 1446, x = 0.5230, y = 0.2891, zoneName = "Tanaris" },
		{ uiMapID = 1413, x = 0.6264, y = 0.3742, zoneName = "The Barrens" },
		{ uiMapID = 1456, x = 0.4763, y = 0.5858, zoneName = "Thunder Bluff", faction = 1 },
		{ uiMapID = 1458, x = 0.6593, y = 0.4343, zoneName = "Undercity", faction = 1 },
		{ uiMapID = 1452, x = 0.6145, y = 0.3698, zoneName = "Winterspring" },
		{ uiMapID = 2521, x = 0.5763, y = 0.7717, zoneName = "Zephras Isle" },
	},
	Innkeeper = {
		{ uiMapID = 1416, x = 0.1822, y = 0.6663, zoneName = "Alterac Mountains", faction = 2 },
		{ uiMapID = 1417, x = 0.7384, y = 0.3246, zoneName = "Arathi Highlands", faction = 1 },
		{ uiMapID = 1440, x = 0.7399, y = 0.6065, zoneName = "Ashenvale", faction = 1 },
		{ uiMapID = 1440, x = 0.3699, y = 0.4922, zoneName = "Ashenvale", faction = 2 },
		{ uiMapID = 1447, x = 0.1260, y = 0.7736, zoneName = "Azshara", faction = 2 },
		{ uiMapID = 1418, x = 0.0282, y = 0.4586, zoneName = "Badlands", faction = 1 },
		{ uiMapID = 1439, x = 0.3704, y = 0.4413, zoneName = "Darkshore", faction = 2 },
		{ uiMapID = 1457, x = 0.6742, y = 0.1565, zoneName = "Darnassus", faction = 2 },
		{ uiMapID = 1443, x = 0.2409, y = 0.6821, zoneName = "Desolace", faction = 1 },
		{ uiMapID = 1443, x = 0.6627, y = 0.0655, zoneName = "Desolace", faction = 2 },
		{ uiMapID = 1426, x = 0.4738, y = 0.5252, zoneName = "Dun Morogh", faction = 2 },
		{ uiMapID = 1411, x = 0.5151, y = 0.4164, zoneName = "Durotar", faction = 1 },
		{ uiMapID = 1431, x = 0.7387, y = 0.4441, zoneName = "Duskwood", faction = 2 },
		{ uiMapID = 1445, x = 0.6659, y = 0.4522, zoneName = "Dustwallow Marsh", faction = 2 },
		{ uiMapID = 1423, x = 0.7180, y = 0.4852, zoneName = "Eastern Plaguelands" },
		{ uiMapID = 1429, x = 0.4377, y = 0.6580, zoneName = "Elwynn Forest", faction = 2 },
		{ uiMapID = 1444, x = 0.3097, y = 0.4349, zoneName = "Feralas", faction = 2 },
		{ uiMapID = 1444, x = 0.7480, y = 0.4518, zoneName = "Feralas", faction = 1 },
		{ uiMapID = 1424, x = 0.5117, y = 0.5893, zoneName = "Hillsbrad Foothills", faction = 2 },
		{ uiMapID = 1424, x = 0.6278, y = 0.1903, zoneName = "Hillsbrad Foothills", faction = 1 },
		{ uiMapID = 1455, x = 0.1815, y = 0.5145, zoneName = "Ironforge", faction = 2 },
		{ uiMapID = 1432, x = 0.3553, y = 0.4840, zoneName = "Loch Modan", faction = 2 },
		{ uiMapID = 2482, x = 0.7087, y = 0.5155, zoneName = "Mount Hyjal" },
		{ uiMapID = 2482, x = 0.1565, y = 0.5044, zoneName = "Mount Hyjal", faction = 2 },
		{ uiMapID = 1412, x = 0.4593, y = 0.6416, zoneName = "Mulgore", faction = 1 },
		{ uiMapID = 1454, x = 0.5410, y = 0.6841, zoneName = "Orgrimmar", faction = 1 },
		{ uiMapID = 1433, x = 0.2192, y = 0.4482, zoneName = "Redridge Mountains", faction = 2 },
		{ uiMapID = 2548, x = 0.6462, y = 0.8416, zoneName = "Riverglades" },
		{ uiMapID = 2548, x = 0.7877, y = 0.5398, zoneName = "Riverglades" },
		{ uiMapID = 2548, x = 0.5800, y = 0.4510, zoneName = "Riverglades", faction = 1 },
		{ uiMapID = 2652, x = 0.4238, y = 0.6975, zoneName = "Shen'dralas" },
		{ uiMapID = 1451, x = 0.5189, y = 0.3916, zoneName = "Silithus" },
		{ uiMapID = 1421, x = 0.4318, y = 0.4128, zoneName = "Silverpine Forest", faction = 1 },
		{ uiMapID = 1442, x = 0.3579, y = 0.0574, zoneName = "Stonetalon Mountains", faction = 2 },
		{ uiMapID = 1442, x = 0.4747, y = 0.6213, zoneName = "Stonetalon Mountains", faction = 1 },
		{ uiMapID = 1453, x = 0.6039, y = 0.7527, zoneName = "Stormwind City", faction = 2 },
		{ uiMapID = 1434, x = 0.3149, y = 0.2975, zoneName = "Stranglethorn Vale", faction = 1 },
		{ uiMapID = 1434, x = 0.2704, y = 0.7731, zoneName = "Stranglethorn Vale" },
		{ uiMapID = 1435, x = 0.4516, y = 0.5666, zoneName = "Swamp of Sorrows", faction = 1 },
		{ uiMapID = 1446, x = 0.5251, y = 0.2791, zoneName = "Tanaris" },
		{ uiMapID = 1438, x = 0.5562, y = 0.5979, zoneName = "Teldrassil", faction = 2 },
		{ uiMapID = 1413, x = 0.6205, y = 0.3941, zoneName = "The Barrens" },
		{ uiMapID = 1413, x = 0.4558, y = 0.5904, zoneName = "The Barrens", faction = 1 },
		{ uiMapID = 1413, x = 0.5199, y = 0.2989, zoneName = "The Barrens", faction = 1 },
		{ uiMapID = 1425, x = 0.1415, y = 0.4157, zoneName = "The Hinterlands", faction = 2 },
		{ uiMapID = 1425, x = 0.7814, y = 0.8138, zoneName = "The Hinterlands", faction = 1 },
		{ uiMapID = 1441, x = 0.4607, y = 0.5152, zoneName = "Thousand Needles", faction = 1 },
		{ uiMapID = 1456, x = 0.4581, y = 0.6471, zoneName = "Thunder Bluff", faction = 1 },
		{ uiMapID = 1420, x = 0.6172, y = 0.5205, zoneName = "Tirisfal Glades", faction = 1 },
		{ uiMapID = 1458, x = 0.6774, y = 0.3789, zoneName = "Undercity", faction = 1 },
		{ uiMapID = 1436, x = 0.5286, y = 0.5371, zoneName = "Westfall", faction = 2 },
		{ uiMapID = 1437, x = 0.1070, y = 0.6095, zoneName = "Wetlands", faction = 2 },
		{ uiMapID = 1452, x = 0.6136, y = 0.3883, zoneName = "Winterspring" },
		{ uiMapID = 2521, x = 0.6219, y = 0.7261, zoneName = "Zephras Isle" },
		{ uiMapID = 2521, x = 0.4301, y = 0.4323, zoneName = "Zephras Isle" },
	},
	Mailbox = {
		{ uiMapID = 1417, x = 0.7386, y = 0.3311, zoneName = "Arathi Highlands", faction = 1 },
		{ uiMapID = 1440, x = 0.3633, y = 0.5022, zoneName = "Ashenvale", faction = 2 },
		{ uiMapID = 1440, x = 0.7363, y = 0.6089, zoneName = "Ashenvale", faction = 1 },
		{ uiMapID = 1418, x = 0.0383, y = 0.4730, zoneName = "Badlands", faction = 1 },
		{ uiMapID = 1419, x = 0.6406, y = 0.1922, zoneName = "Blasted Lands", faction = 2 },
		{ uiMapID = 1439, x = 0.3732, y = 0.4373, zoneName = "Darkshore", faction = 2 },
		{ uiMapID = 1457, x = 0.4163, y = 0.4185, zoneName = "Darnassus", faction = 2 },
		{ uiMapID = 1443, x = 0.2479, y = 0.6876, zoneName = "Desolace", faction = 1 },
		{ uiMapID = 1443, x = 0.6543, y = 0.0680, zoneName = "Desolace", faction = 2 },
		{ uiMapID = 1426, x = 0.4702, y = 0.5258, zoneName = "Dun Morogh", faction = 2 },
		{ uiMapID = 1411, x = 0.5190, y = 0.4215, zoneName = "Durotar", faction = 1 },
		{ uiMapID = 1431, x = 0.7373, y = 0.4610, zoneName = "Duskwood", faction = 2 },
		{ uiMapID = 1445, x = 0.6596, y = 0.4529, zoneName = "Dustwallow Marsh", faction = 2 },
		{ uiMapID = 1423, x = 0.7118, y = 0.4891, zoneName = "Eastern Plaguelands" },
		{ uiMapID = 1429, x = 0.4292, y = 0.6552, zoneName = "Elwynn Forest", faction = 2 },
		{ uiMapID = 1444, x = 0.3126, y = 0.4380, zoneName = "Feralas", faction = 2 },
		{ uiMapID = 1444, x = 0.7488, y = 0.4400, zoneName = "Feralas", faction = 1 },
		{ uiMapID = 1424, x = 0.5042, y = 0.5870, zoneName = "Hillsbrad Foothills", faction = 2 },
		{ uiMapID = 1424, x = 0.6238, y = 0.1971, zoneName = "Hillsbrad Foothills", faction = 1 },
		{ uiMapID = 1455, x = 0.2096, y = 0.5241, zoneName = "Ironforge", faction = 2 },
		{ uiMapID = 1455, x = 0.3322, y = 0.6466, zoneName = "Ironforge", faction = 2 },
		{ uiMapID = 1455, x = 0.7131, y = 0.7213, zoneName = "Ironforge", faction = 2 },
		{ uiMapID = 1455, x = 0.7228, y = 0.4910, zoneName = "Ironforge", faction = 2 },
		{ uiMapID = 1432, x = 0.3482, y = 0.4773, zoneName = "Loch Modan", faction = 2 },
		{ uiMapID = 1412, x = 0.4625, y = 0.6350, zoneName = "Mulgore", faction = 1 },
		{ uiMapID = 1454, x = 0.5069, y = 0.7037, zoneName = "Orgrimmar", faction = 1 },
		{ uiMapID = 1454, x = 0.6226, y = 0.4051, zoneName = "Orgrimmar", faction = 1 },
		{ uiMapID = 1433, x = 0.2132, y = 0.4651, zoneName = "Redridge Mountains", faction = 2 },
		{ uiMapID = 1451, x = 0.5175, y = 0.3797, zoneName = "Silithus" },
		{ uiMapID = 1421, x = 0.4341, y = 0.4152, zoneName = "Silverpine Forest", faction = 1 },
		{ uiMapID = 1442, x = 0.3602, y = 0.0721, zoneName = "Stonetalon Mountains", faction = 2 },
		{ uiMapID = 1442, x = 0.4801, y = 0.6114, zoneName = "Stonetalon Mountains", faction = 1 },
		{ uiMapID = 1453, x = 0.3680, y = 0.6917, zoneName = "Stormwind City", faction = 2 },
		{ uiMapID = 1453, x = 0.5058, y = 0.8974, zoneName = "Stormwind City", faction = 2 },
		{ uiMapID = 1453, x = 0.6164, y = 0.7607, zoneName = "Stormwind City", faction = 2 },
		{ uiMapID = 1453, x = 0.7454, y = 0.5539, zoneName = "Stormwind City", faction = 2 },
		{ uiMapID = 1434, x = 0.2670, y = 0.7636, zoneName = "Stranglethorn Vale" },
		{ uiMapID = 1434, x = 0.3252, y = 0.2865, zoneName = "Stranglethorn Vale", faction = 1 },
		{ uiMapID = 1435, x = 0.4544, y = 0.5514, zoneName = "Swamp of Sorrows", faction = 1 },
		{ uiMapID = 1446, x = 0.5233, y = 0.2781, zoneName = "Tanaris" },
		{ uiMapID = 1438, x = 0.5612, y = 0.5843, zoneName = "Teldrassil", faction = 2 },
		{ uiMapID = 1413, x = 0.4508, y = 0.5867, zoneName = "The Barrens", faction = 1 },
		{ uiMapID = 1413, x = 0.5203, y = 0.3043, zoneName = "The Barrens", faction = 1 },
		{ uiMapID = 1413, x = 0.6216, y = 0.3919, zoneName = "The Barrens" },
		{ uiMapID = 1425, x = 0.1404, y = 0.4570, zoneName = "The Hinterlands", faction = 2 },
		{ uiMapID = 1425, x = 0.7884, y = 0.8050, zoneName = "The Hinterlands", faction = 1 },
		{ uiMapID = 1441, x = 0.4585, y = 0.5106, zoneName = "Thousand Needles", faction = 1 },
		{ uiMapID = 1456, x = 0.4523, y = 0.5940, zoneName = "Thunder Bluff", faction = 1 },
		{ uiMapID = 1420, x = 0.6150, y = 0.5308, zoneName = "Tirisfal Glades", faction = 1 },
		{ uiMapID = 1458, x = 0.6816, y = 0.3826, zoneName = "Undercity", faction = 1 },
		{ uiMapID = 1436, x = 0.5310, y = 0.5334, zoneName = "Westfall", faction = 2 },
		{ uiMapID = 1437, x = 0.1086, y = 0.5972, zoneName = "Wetlands", faction = 2 },
		{ uiMapID = 1452, x = 0.6128, y = 0.3862, zoneName = "Winterspring" },
	},
}

-- Thin accessor, same shape as every other tracker module's GetAll() --
-- returns the full static list for a category (Auctioneer/Banker/
-- Innkeeper/Mailbox); zone-scoping and the compass-only proximity radius
-- are applied by the callers (Compass.lua/MapPins.lua), same as how
-- Waypoints.GetAll() returns everything and each surface filters by
-- uiMapID itself.
-- Same faction convention and reasoning as FlightPoints.lua's oursToSee():
-- 1 = Horde-only, 2 = Alliance-only, anything else (0/nil) is neutral/both.
local function oursToSee(locFaction)
	local _, englishFaction = UnitFactionGroup("player")
	if locFaction == 1 then return englishFaction == "Horde" end
	if locFaction == 2 then return englishFaction == "Alliance" end
	return true
end

PC.Locations = PC.Locations or {}
function PC.Locations.Init() end
function PC.Locations.GetAll(category)
	local all = PC.LocationsData[category]
	if not all then return {} end
	local list = {}
	for _, loc in ipairs(all) do
		if oursToSee(loc.faction) then
			list[#list + 1] = loc
		end
	end
	return list
end

-- /wf locationscheck -- prints exactly what location data exists for your
-- CURRENT zone and how far away each entry computes as, instead of
-- guessing why something isn't showing on the compass. Mirrors
-- FlightPoints.Debug()'s reasoning: verify the real numbers before
-- changing any filtering logic.
function PC.Locations.Debug()
	print("|cff33ff99Wayfinder|r locations debug:")
	local uiMapID = C_Map.GetBestMapForUnit("player")
	local mapInfo = uiMapID and C_Map.GetMapInfo(uiMapID)
	print("  current zone: " .. tostring(mapInfo and mapInfo.name) .. "  (uiMapID " .. tostring(uiMapID) .. ")")
	if not uiMapID then return end

	local myPos = C_Map.GetPlayerMapPosition(uiMapID, "player")
	if not myPos then
		print("  no player position available right now")
		return
	end
	local px, py = myPos:GetXY()
	local okSize, mapWidth, mapHeight = pcall(C_Map.GetMapWorldSize, uiMapID)
	print(string.format("  player pos: x=%.4f y=%.4f   map world size: %s x %s",
		px, py, tostring(okSize and mapWidth), tostring(okSize and mapHeight)))
	print("  compassLocationRadius setting: " .. tostring(PC.db.options.compassLocationRadius))
	print("  showMailboxCompass: " .. tostring(PC.db.options.showMailboxCompass)
		.. "   showBankCompass: " .. tostring(PC.db.options.showBankCompass)
		.. "   showAuctioneerCompass: " .. tostring(PC.db.options.showAuctioneerCompass)
		.. "   showInnkeeperCompass: " .. tostring(PC.db.options.showInnkeeperCompass))

	for _, category in ipairs({ "Auctioneer", "Banker", "Mailbox", "Innkeeper" }) do
		print("  -- " .. category .. " --")
		local any = false
		for _, loc in ipairs(PC.LocationsData[category] or {}) do
			if loc.uiMapID == uiMapID then
				any = true
				local dx = (loc.x - px) * ((okSize and mapWidth) or 1)
				local dy = (loc.y - py) * ((okSize and mapHeight) or 1)
				local dist = math.sqrt(dx * dx + dy * dy)
				print(string.format("    x=%.4f y=%.4f  distance=%.0fy  zoneName=%s",
					loc.x, loc.y, dist, tostring(loc.zoneName)))
			end
		end
		if not any then print("    (no entries for this zone)") end
	end
end
