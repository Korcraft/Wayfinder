-- Wayfinder: Core.lua
-- Addon bootstrap: shared namespace, saved variables, slash commands, event wiring.

Wayfinder = Wayfinder or {}
local PC = Wayfinder

PC.PREFIX = "PCOMPASS1" -- addon message prefix, must be <= 16 chars, same on every client

-- Default saved-variable shape. Each module reads/writes WayfinderDB directly.
local DEFAULTS = {
	waypoints = {},   -- [playerFullName] = { [id] = { id, name, colorIndex, uiMapID, position={x,y}, kind, expires, mine } }
	flightPointsFound = {}, -- [playerFullName] = { [lowercase flight point name] = true } -- per-character, see FlightPoints.lua
	options = {
		compassEnabled = true,
		compassWidth = 420,
		compassHeight = 64,
		fieldOfView = 180, -- degrees of heading shown across the compass strip
		compassIconSize = 20, -- pixels -- waypoint icon size on the compass HUD
		mapIconSize = 20, -- pixels -- waypoint icon size on the world map
		compassPartyIconSize = 28, -- pixels -- party member icon size on the compass HUD
		mapPartyIconSize = 28, -- pixels -- party member icon size on the world map
		compassQuestIconSize = 22, -- pixels -- quest icon size on the compass HUD (quests aren't shown on the map)
		compassFlightIconSize = 22, -- pixels -- flight point icon size on the compass HUD
		mapFlightIconSize = 20, -- pixels -- flight point icon size on the world map
		-- Shared by Auctioneer/Banker/Mailbox/Innkeeper -- one size per
		-- surface and one compass-only proximity radius for all four,
		-- rather than a separate size/radius per category, since they're
		-- visually similar "static points of interest" (buildings, not
		-- NPCs) rather than distinct concepts the way party/quests/flight
		-- points are from each other.
		compassLocationIconSize = 20, -- pixels
		mapLocationIconSize = 18, -- pixels
		compassLocationRadius = 300, -- yards -- compass-only; the map always shows the whole zone regardless of distance, same as every other marker
		showQuests = true,
		showPartyCompass = true,
		showPartyMap = true,
		showFlightPathsCompass = true,
		showFlightPathsMap = true,
		showAuctioneerCompass = true,
		showAuctioneerMap = true,
		showBankCompass = true,
		showBankMap = true,
		showMailboxCompass = true,
		showMailboxMap = true,
		showInnkeeperCompass = true,
		showInnkeeperMap = true,
		showCorpseCompass = true,
		showCorpseMap = true,
		compassCorpseIconSize = 22, -- pixels
		mapCorpseIconSize = 20, -- pixels
		showPOI = true,
		compassPartyIconDots = false, -- false = real portraits, true = flat class-color dots
		mapPartyIconDots = false,
		centerLineColor = { 1.0, 1.0, 1.0 }, -- the "straight ahead" line in the middle of the compass HUD
		tickColor = { 1.0, 1.0, 1.0 }, -- the minor/major degree ticks
		letterColor = { 1.0, 1.0, 1.0 }, -- the N/NE/E/... cardinal letters
		hudColor = { 0.0, 0.0, 0.0 }, -- the two background panels behind the ticks+letters and the icon row
		hudOpacity = 0.35,
		-- When enabled, every bearing icon on the compass HUD shrinks and
		-- fades smoothly between full size/opacity dead-center and these
		-- two floors at the exact edge of the field of view -- see
		-- Compass.lua's applyDynamicIcon() for the actual falloff math.
		dynamicIconsEnabled = false,
		dynamicIconsScale = 0.5, -- minimum scale (fraction of normal) at the edge of the HUD
		dynamicIconsFade = 0.5, -- minimum opacity (fraction of normal) at the edge of the HUD
		iconStyle = "letter", -- "letter" or "icon"
		colors = {
			waypointMine = { 0.3, 1.0, 0.3 },
			waypointOther = { 1.0, 0.82, 0.3 },
			party = { 0.3, 0.6, 1.0 },
			quest = { 1.0, 0.85, 0.0 },
			flight = { 0.6, 0.3, 1.0 },
			poi = { 0.2, 0.9, 0.5 },
		},
	},
}

local function applyDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then
			if type(v) == "table" then
				db[k] = {}
				applyDefaults(db[k], v)
			else
				db[k] = v
			end
		elseif type(v) == "table" and type(db[k]) == "table" then
			applyDefaults(db[k], v)
		end
	end
end

local eventFrame = CreateFrame("Frame", "WayfinderEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

-- v1.1.0 changed compassIconSize/mapIconSize from a "small"/"medium"/"large"
-- string to a direct pixel number. applyDefaults only fills in MISSING
-- keys, so anyone upgrading still has the old string sitting there -- left
-- alone, that string gets handed straight to icon:SetSize() and errors.
-- Converts it once, using the old multipliers against the old base size,
-- so an upgrade doesn't silently change anyone's chosen size.
local OLD_SIZE_PIXELS = { small = 15, medium = 20, large = 27 }
local function migrateIconSizeSettings(options)
	for _, key in ipairs({ "compassIconSize", "mapIconSize" }) do
		if type(options[key]) == "string" then
			options[key] = OLD_SIZE_PIXELS[options[key]] or 20
		end
	end
end

-- showParty/partyIconDots used to drive both the compass and the map from
-- one shared setting -- now each surface has its own. Unlike
-- migrateIconSizeSettings above, this one MUST run BEFORE applyDefaults:
-- applyDefaults would otherwise create the new split keys with their
-- defaults before this ever gets a chance to see the old shared value and
-- carry it forward, silently discarding whatever the user had set.
local function migrateSharedPartySettings(options)
	if options.showParty ~= nil then
		if options.showPartyCompass == nil then options.showPartyCompass = options.showParty end
		if options.showPartyMap == nil then options.showPartyMap = options.showParty end
		options.showParty = nil
	end
	if options.partyIconDots ~= nil then
		if options.compassPartyIconDots == nil then options.compassPartyIconDots = options.partyIconDots end
		if options.mapPartyIconDots == nil then options.mapPartyIconDots = options.partyIconDots end
		options.partyIconDots = nil
	end
end

-- showFlightPaths used to drive both surfaces from one shared setting --
-- same split, same BEFORE-applyDefaults ordering requirement, as
-- migrateSharedPartySettings above.
local function migrateFlightPathSettings(options)
	if options.showFlightPaths ~= nil then
		if options.showFlightPathsCompass == nil then options.showFlightPathsCompass = options.showFlightPaths end
		if options.showFlightPathsMap == nil then options.showFlightPathsMap = options.showFlightPaths end
		options.showFlightPaths = nil
	end
end

eventFrame:SetScript("OnEvent", function(_, event, addonName)
	if event == "ADDON_LOADED" and addonName == "Wayfinder" then
		WayfinderDB = WayfinderDB or {}
		if WayfinderDB.options then
			migrateSharedPartySettings(WayfinderDB.options)
			migrateFlightPathSettings(WayfinderDB.options)
		end
		applyDefaults(WayfinderDB, DEFAULTS)
		migrateIconSizeSettings(WayfinderDB.options)
		PC.db = WayfinderDB

		if PC.Comm and PC.Comm.Init then PC.Comm.Init() end
	elseif event == "PLAYER_LOGIN" then
		-- Waypoints + map + compass + party tracking + quests are active.
		-- POI/Pings are still shelved -- their code is untouched, just not
		-- running, so they add no risk or noise right now.
		if PC.Waypoints and PC.Waypoints.Init then PC.Waypoints.Init() end
		if PC.PartyTracker and PC.PartyTracker.Init then PC.PartyTracker.Init() end
		if PC.Quests and PC.Quests.Init then PC.Quests.Init() end
		if PC.FlightPoints and PC.FlightPoints.Init then PC.FlightPoints.Init() end
		if PC.Locations and PC.Locations.Init then PC.Locations.Init() end
		if PC.Corpse and PC.Corpse.Init then PC.Corpse.Init() end
		if PC.MapPins and PC.MapPins.Init then PC.MapPins.Init() end
		if PC.Compass and PC.Compass.Init then PC.Compass.Init() end
		if PC.Settings and PC.Settings.Init then PC.Settings.Init() end
		print("|cff33ff99Wayfinder|r loaded. Type |cffffffff/wf help|r for commands.")
	end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local function printHelp()
	print("|cff33ff99Wayfinder|r commands:")
	print("  On the world map right now: Double-click = temp waypoint (~15 min, shared, color-coded)")
	print("                              Alt+click = permanent waypoint (local only)")
	print("                              Shift+click = remove nearest of yours (confirms first if permanent)")
	print("                              Right-click is untouched -- that's still the map's native zoom-out")
	print("  /wf wp temp                   - add a 15-minute waypoint at your current position (shared with party, can't be named)")
	print("  /wf wp remove <name>          - remove one of YOUR waypoints by name")
	print("  /wf wp clear                  - remove ALL of your own waypoints at once (clears test clutter)")
	print("  /wf wp wipeall                - nuke EVERY waypoint, including any received from party (full reset)")
	print("  /wf wp list  (or /wf list)    - list every active waypoint, yours and your party's")
	print("  /wf settings       - open the Wayfinder settings panel (also under Options > AddOns)")
	print("  /wf compass        - toggle the HUD compass")
	print("  /wf quests         - toggle showing quest objectives")
	print("  /wf facingcheck    - 10-second live test of which facing sources work here (turn while it runs)")
	print("  /wf questcheck     - print exactly why quests are/aren't showing on the compass")
	print("  /wf flightcheck    - print exactly what flight points are returned for your current zone")
	print("  /wf locationscheck - print exactly what AH/bank/mailbox data exists for your current zone")
	print("  /wf corpsecheck    - print exactly what's tracked for your own corpse's location")
end

local function toggleOption(key, label)
	PC.db.options[key] = not PC.db.options[key]
	print("|cff33ff99Wayfinder|r " .. label .. " " .. (PC.db.options[key] and "enabled" or "disabled"))
end

SLASH_WAYFINDER1 = "/wf"
SlashCmdList.WAYFINDER = function(msg)
	msg = (msg or ""):trim()
	local cmd, rest = msg:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()

	if cmd == "wp" then
		local sub, arg = rest:match("^(%S*)%s*(.*)$")
		sub = (sub or ""):lower()
		if sub == "add" then
			PC.Waypoints.Add(arg, nil, false)
		elseif sub == "temp" then
			PC.Waypoints.Add(nil, nil, true) -- temp waypoints can never be named
		elseif sub == "remove" then
			PC.Waypoints.Remove(arg)
		elseif sub == "clear" then
			PC.Waypoints.ClearAll()
		elseif sub == "wipeall" then
			PC.Waypoints.WipeAll()
		elseif sub == "list" then
			PC.Waypoints.PrintAll()
		else
			printHelp()
		end
	elseif cmd == "list" then
		if PC.Waypoints then PC.Waypoints.PrintAll() end
	elseif cmd == "ping" then
		if PC.Pings then PC.Pings.SendMine() end
	elseif cmd == "compass" then
		PC.db.options.compassEnabled = not PC.db.options.compassEnabled
		if PC.Compass then PC.Compass.Refresh() end
		print("|cff33ff99Wayfinder|r compass " .. (PC.db.options.compassEnabled and "enabled" or "disabled"))
	elseif cmd == "quests" then
		toggleOption("showQuests", "quest objectives")
	elseif cmd == "poi" then
			if not (PC.POI and PC.db.customPOIs) then
				print("|cffff4444Wayfinder|r the custom-POI feature isn't enabled yet.")
				return
			end
		local sub, arg = rest:match("^(%S*)%s*(.*)$")
		sub = (sub or ""):lower()
		if sub == "add" then
			PC.POI.Add(arg)
		elseif sub == "remove" then
			PC.POI.Remove(arg)
		elseif sub == "list" then
			PC.POI.ListMine()
		elseif sub == "sync" then
			PC.POI.BroadcastAllMine()
		else
			printHelp()
		end
	elseif cmd == "style" then
		local style = rest:lower()
		if style == "letter" or style == "icon" then
			PC.db.options.iconStyle = style
			print("|cff33ff99Wayfinder|r marker style set to " .. style .. ".")
		else
			print("|cffff4444Wayfinder|r usage: /wf style letter|icon")
		end
	elseif cmd == "debug" then
		PC.db.debugPins = not PC.db.debugPins
		print("|cff33ff99Wayfinder|r pin placement debug output " .. (PC.db.debugPins and "ON" or "off") .. " -- place a waypoint on the map to see it.")
	elseif cmd == "color" then
		local category, r, g, b = rest:match("^(%S*)%s+(%d+)%s+(%d+)%s+(%d+)")
		category = (category or ""):lower()
		if category ~= "" and PC.db.options.colors[category] and r then
			PC.db.options.colors[category] = { tonumber(r) / 255, tonumber(g) / 255, tonumber(b) / 255 }
			print("|cff33ff99Wayfinder|r " .. category .. " color updated.")
		else
			print("|cffff4444Wayfinder|r usage: /wf color <category> <r> <g> <b>  (0-255 each)")
			print("      categories: waypointmine, waypointother, party, quest, flight, poi")
		end
	elseif cmd == "settings" then
		if PC.Settings then PC.Settings.Open() end
	elseif cmd == "facingcheck" then
		if PC.Compass then PC.Compass.FacingProbe() end
	elseif cmd == "questcheck" then
		if PC.Quests then PC.Quests.Debug() end
	elseif cmd == "flightcheck" then
		if PC.FlightPoints then PC.FlightPoints.Debug() end
	elseif cmd == "locationscheck" then
		if PC.Locations then PC.Locations.Debug() end
	elseif cmd == "corpsecheck" then
		if PC.Corpse then PC.Corpse.Debug() end
	else
		printHelp()
	end
end
