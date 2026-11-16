-- Wayfinder: Comm.lua
-- Party/raid addon-message networking. Other players only see your waypoints/pings
-- if they also have Wayfinder installed -- there is no API to draw on someone
-- else's map without their own client rendering it locally.

local PC = Wayfinder
PC.Comm = PC.Comm or {}
local Comm = PC.Comm

local commFrame = CreateFrame("Frame", "WayfinderCommFrame")

function Comm.Init()
	local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PC.PREFIX)
	if not ok then
		print("|cffff4444Wayfinder|r could not register addon message prefix.")
	end
	commFrame:RegisterEvent("CHAT_MSG_ADDON")
end

-- Picks the right channel for whatever group the player is currently in.
-- Scenario/LFR groups need INSTANCE_CHAT instead of PARTY/RAID -- confirmed
-- real (LE_PARTY_CATEGORY_INSTANCE, "INSTANCE_CHAT") via Details' own
-- working network code on this client. Checked first since an instance
-- group would also read true for plain IsInGroup()/IsInRaid().
local function currentChannel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
	return nil
end

-- Small pipe-delimited wire format. Keep it simple and dependency-free
-- rather than pulling in a serialization library for a handful of fields.
--
-- WPADD|id|uiMapID|x|y|colorIndex|kind|remaining|name
--   A waypoint added or updated. kind is "P" (permanent) or "T" (temporary).
--   colorIndex picks from Waypoints.COLOR_SEQUENCE -- sent across so a party
--   member's waypoint renders in the SAME color on your screen as on theirs.
--   `remaining` is seconds-left, only meaningful for "T", and is a RELATIVE
--   duration computed fresh at send time -- never an absolute timestamp.
--   Even though expiry is tracked via time() (real wall-clock) now rather
--   than GetTime() (each client's own uptime counter), sending a relative
--   duration instead of the absolute value stays the safer choice -- it
--   doesn't depend on both players' system clocks agreeing. The receiver
--   adds `remaining` to its OWN time() to get a locally-meaningful expiry.
-- WPDEL|id
--   A waypoint removed.
-- PING|uiMapID|x|y
--   A transient ping.
-- POI|uiMapID|x|y|name
--   A custom POI (bank/AH/mailbox/inn/etc.) recorded or re-synced.

local function escapeField(s)
	return (s or ""):gsub("|", "/")
end

function Comm.BroadcastWaypointAdd(entry)
	local channel = currentChannel()
	if not channel then return end
	local remaining = 0
	if entry.kind == "T" and entry.expires then
		remaining = math.max(0, entry.expires - time())
	end
	local msg = string.format("WPADD|%s|%d|%.5f|%.5f|%d|%s|%.1f|%s",
		entry.id, entry.uiMapID, entry.position.x, entry.position.y,
		entry.colorIndex, entry.kind, remaining, escapeField(entry.name))
	C_ChatInfo.SendAddonMessage(PC.PREFIX, msg, channel)
end

function Comm.BroadcastWaypointRemove(id)
	local channel = currentChannel()
	if not channel then return end
	C_ChatInfo.SendAddonMessage(PC.PREFIX, "WPDEL|" .. id, channel)
end

function Comm.BroadcastPing(point)
	local channel = currentChannel()
	if not channel then return end
	local msg = string.format("PING|%d|%.5f|%.5f", point.uiMapID, point.position.x, point.position.y)
	C_ChatInfo.SendAddonMessage(PC.PREFIX, msg, channel)
end

function Comm.BroadcastPOI(point, name)
	local channel = currentChannel()
	if not channel then return end
	local msg = string.format("POI|%d|%.5f|%.5f|%s", point.uiMapID, point.position.x, point.position.y, escapeField(name))
	C_ChatInfo.SendAddonMessage(PC.PREFIX, msg, channel)
end

commFrame:SetScript("OnEvent", function(_, event, prefix, text, _channel, sender)
	if event ~= "CHAT_MSG_ADDON" or prefix ~= PC.PREFIX then return end

	-- sender arrives as "Name-Realm" or sometimes just "Name".
	local who = sender
	local parts = { strsplit("|", text) }
	local kind = parts[1]

	if kind == "WPADD" then
		local id = parts[2]
		local uiMapID, x, y, colorIndex = tonumber(parts[3]), tonumber(parts[4]), tonumber(parts[5]), tonumber(parts[6])
		local wpKind, remaining, name = parts[7], tonumber(parts[8]), parts[9]
		if id and uiMapID and x and y and colorIndex then
			PC.Waypoints.ReceiveAdd(who, {
				id = id, name = name or "?", colorIndex = colorIndex, uiMapID = uiMapID,
				position = { x = x, y = y }, kind = wpKind,
				expires = (wpKind == "T") and (time() + (remaining or 0)) or nil,
				mine = false,
			})
		end
	elseif kind == "WPDEL" then
		PC.Waypoints.ReceiveRemove(who, parts[2])
	elseif kind == "PING" then
		local uiMapID, x, y = tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4])
		if uiMapID and x and y then
			PC.Pings.ReceivePing(who, { uiMapID = uiMapID, position = { x = x, y = y } })
		end
	elseif kind == "POI" then
		local uiMapID, x, y, name = tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4]), parts[5]
		if uiMapID and x and y and name then
			PC.POI.ReceiveCustom(uiMapID, name, { x = x, y = y })
		end
	end
end)
