-- Wayfinder: Core.lua
-- Addon bootstrap: shared namespace, saved variables, slash commands, event wiring.

Wayfinder = Wayfinder or {}
local PC = Wayfinder

PC.PREFIX = "PCOMPASS1" -- addon message prefix, must be <= 16 chars, same on every client

-- Default saved-variable shape. Each module reads/writes WayfinderDB directly.
local DEFAULTS = {
	waypoints = {},   -- [playerFullName] = { [id] = { id, name, colorIndex, uiMapID, position={x,y}, kind, expires, mine } }
	options = {
		compassEnabled = true,
		compassWidth = 420,
		fieldOfView = 180, -- degrees of heading shown across the compass strip
		waypointIconSize = "medium", -- "small", "medium", or "large"
		showQuests = true,
		showParty = true,
		showFlightPaths = true,
		showPOI = true,
		partyIconDots = false, -- false = real portraits, true = flat class-color dots
		centerLineColor = { 1.0, 1.0, 1.0 }, -- the "straight ahead" line in the middle of the compass HUD
		tickColor = { 1.0, 1.0, 1.0 }, -- the minor/major degree ticks
		letterColor = { 1.0, 1.0, 1.0 }, -- the N/NE/E/... cardinal letters
		hudColor = { 0.0, 0.0, 0.0 }, -- the two background panels behind the ticks+letters and the icon row
		hudOpacity = 0.35,
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

eventFrame:SetScript("OnEvent", function(_, event, addonName)
	if event == "ADDON_LOADED" and addonName == "Wayfinder" then
		WayfinderDB = WayfinderDB or {}
		applyDefaults(WayfinderDB, DEFAULTS)
		PC.db = WayfinderDB

		if PC.Comm and PC.Comm.Init then PC.Comm.Init() end
	elseif event == "PLAYER_LOGIN" then
		-- Waypoints + map + compass + party tracking + quests are active.
		-- POI/Pings are still shelved -- their code is untouched, just not
		-- running, so they add no risk or noise right now.
		if PC.Waypoints and PC.Waypoints.Init then PC.Waypoints.Init() end
		if PC.PartyTracker and PC.PartyTracker.Init then PC.PartyTracker.Init() end
		if PC.Quests and PC.Quests.Init then PC.Quests.Init() end
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
	print("  (ping is shelved for now while this is being tested)")
	print("  /wf wp temp <name>            - add a waypoint at your current position")
	print("  /wf wp remove <name>          - remove one of YOUR waypoints by name")
	print("  /wf wp clear                  - remove ALL of your own waypoints at once (clears test clutter)")
	print("  /wf wp wipeall                - nuke EVERY waypoint, including any received from party (full reset)")
	print("  /wf wp list  (or /wf list)    - list every active waypoint, yours and your party's")
	print("  /wf settings       - open the Wayfinder settings panel (also under Options > AddOns)")
	print("  /wf compass        - toggle the HUD compass")
	print("  /wf quests         - toggle showing quest objectives")
	print("  /wf party          - toggle showing party member positions")
	print("  /wf flightpaths    - toggle showing flight masters")
	print("  (bank & auction house record themselves automatically the moment anyone in your party opens one)")
	print("  /wf poi add <name> - save any other custom POI at your current spot")
	print("  /wf poi remove <name> - remove a saved custom POI on this map")
	print("  /wf poi list       - list saved custom POIs on this map")
	print("  /wf poi sync       - re-share everything you know with your current party")
	print("  /wf style letter|icon - switch markers between colored letters and real icons where available")
	print("  /wf color <category> <r> <g> <b> - set a marker color, 0-255 each")
	print("      categories: waypointmine, waypointother, party, quest, flight, poi")
	print("  /wf debug          - toggle diagnostic output for map pin placement")
	print("  /wf facingcheck    - print the raw GetPlayerFacing() value, for calibrating the compass")
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
			PC.Waypoints.Add(arg, nil, true)
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
	elseif cmd == "party" then
		toggleOption("showParty", "party member positions")
	elseif cmd == "flightpaths" or cmd == "flights" then
		toggleOption("showFlightPaths", "flight masters")
	elseif cmd == "poi" then
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
		local raw = GetPlayerFacing() or 0
		print(string.format("|cff33ff99Wayfinder|r GetPlayerFacing() = %.4f radians = %.1f degrees",
			raw, raw * 180 / math.pi))
	else
		printHelp()
	end
end
