-- Wayfinder: POI.lua
-- Three different kinds of "points of interest":
--
--  1. Flight masters -- read live from C_TaxiMap, always accurate, zero
--     setup required.
--  2. Bank / Auction House / Mailbox / Inn -- there is no Blizzard API for
--     "nearest bank" (or mailbox, or inn), and no addon anywhere has one
--     either; they all rely on a hand-built coordinate database. Rather
--     than fabricate coordinates we can't verify, we record these
--     AUTOMATICALLY: WoW fires BANKFRAME_OPENED, AUCTION_HOUSE_SHOW, and
--     MAIL_SHOW the moment you open the respective UI (confirmed against
--     Baganator, Auctionator, and other addons already installed and
--     working on this exact client). Inns don't get their own dedicated
--     event -- talking to an innkeeper just opens the same generic
--     GOSSIP_SHOW every NPC conversation uses -- so we detect it by
--     checking whether this particular conversation offers to set your
--     hearthstone (every innkeeper's does; nothing else does). Either way,
--     just playing normally -- no slash command needed -- captures your
--     position and shares it with your party.
--  3. Anything else custom -- same idea as #2 but manual, via /wf poi add
--     <name>, for any other spot worth marking.
--
-- Either way, only the FIRST person in the party to ever visit a given
-- bank/AH/spot has to trigger the recording; everyone else just sees it
-- show up. Anyone who joins later and missed that can ask for a re-send
-- with /wf poi sync.

local PC = Wayfinder
PC.POI = PC.POI or {}
local POI = PC.POI

-- "Same spot" tolerance: two same-named POIs closer together than this
-- (normalized map units, roughly 2% of the map's width/height) are treated
-- as the same real-world spot. Matters for mailboxes especially -- most
-- cities have several, scattered around, all opening the same MAIL_SHOW
-- event -- so dedupe has to be by name+location, not name alone, or every
-- mailbox after the first one found in a city would get silently dropped.
local DEDUPE_RADIUS = 0.02

local function distance(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

local function findNearbyMatch(list, name, position)
	for _, p in ipairs(list) do
		if p.name:lower() == name:lower() and distance(p.position, position) < DEDUPE_RADIUS then
			return p
		end
	end
	return nil
end

-- Inserts (uiMapID, name, position) if nothing matching already exists at
-- roughly this spot, and broadcasts it to the party. Returns false (does
-- nothing further) if it was already recorded here, so neither manual adds
-- nor the automatic bank/AH/mailbox hooks spam your party every single time
-- -- while still allowing e.g. several distinct mailboxes in the same city.
local function addIfNew(uiMapID, name, position)
	PC.db.customPOIs[uiMapID] = PC.db.customPOIs[uiMapID] or {}
	local list = PC.db.customPOIs[uiMapID]
	if findNearbyMatch(list, name, position) then
		return false
	end
	table.insert(list, { name = name, position = position })
	PC.Comm.BroadcastPOI({ uiMapID = uiMapID, position = position }, name)
	return true
end

local function hereAndNow()
	local uiMapID = C_Map.GetBestMapForUnit("player")
	local pos = uiMapID and C_Map.GetPlayerMapPosition(uiMapID, "player")
	if not uiMapID or not pos then return nil end
	local x, y = pos:GetXY()
	return uiMapID, { x = x, y = y }
end

local function autoRecord(label)
	local uiMapID, position = hereAndNow()
	if not uiMapID then
		if PC.db.debugPins then
			print("|cffff9900PC-DEBUG poi|r auto-record(" .. label .. ") aborted: hereAndNow() couldn't resolve a position.")
		end
		return
	end
	local added = addIfNew(uiMapID, label, position)
	if PC.db.debugPins then
		print(string.format("|cffff9900PC-DEBUG poi|r auto-record(%s) at map %d (%.3f,%.3f) -> %s",
			label, uiMapID, position.x, position.y, added and "added+broadcast" or "already known nearby, skipped"))
	end
	if added then
		print("|cff33ff99Wayfinder|r auto-recorded \"" .. label .. "\" here and shared it with your party.")
	end
end

-- Innkeepers don't get their own event -- talking to ANY NPC fires the same
-- GOSSIP_SHOW. The tell is that every innkeeper's gossip menu includes an
-- option to set your hearthstone there, and nothing else does.
local function isTalkingToInnkeeper()
	if not (C_GossipInfo and C_GossipInfo.GetOptions) then
		if PC.db.debugPins then print("|cffff9900PC-DEBUG poi|r GOSSIP_SHOW: C_GossipInfo.GetOptions not available on this client.") end
		return false
	end
	local ok, options = pcall(C_GossipInfo.GetOptions)
	if not ok or not options then
		if PC.db.debugPins then print("|cffff9900PC-DEBUG poi|r GOSSIP_SHOW: GetOptions() call failed or returned nothing.") end
		return false
	end
	if PC.db.debugPins then
		local names = {}
		for _, option in ipairs(options) do names[#names + 1] = tostring(option.name) end
		print("|cffff9900PC-DEBUG poi|r GOSSIP_SHOW options: " .. table.concat(names, " | "))
	end
	for _, option in ipairs(options) do
		if option.name and option.name:lower():find("hearthstone", 1, true) then
			return true
		end
	end
	return false
end

function POI.Init()
	PC.db.customPOIs = PC.db.customPOIs or {} -- [uiMapID] = { {name=, position={x,y}}, ... }

	local autoFrame = CreateFrame("Frame")
	autoFrame:RegisterEvent("BANKFRAME_OPENED")
	autoFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
	autoFrame:RegisterEvent("MAIL_SHOW")
	autoFrame:RegisterEvent("GOSSIP_SHOW")
	autoFrame:SetScript("OnEvent", function(_, event)
		if PC.db.debugPins then print("|cffff9900PC-DEBUG poi|r event fired: " .. event) end
		if event == "BANKFRAME_OPENED" then
			autoRecord("Bank")
		elseif event == "AUCTION_HOUSE_SHOW" then
			autoRecord("Auction House")
		elseif event == "MAIL_SHOW" then
			autoRecord("Mailbox")
		elseif event == "GOSSIP_SHOW" and isTalkingToInnkeeper() then
			autoRecord("Inn")
		end
	end)
end

-- Manual recording for anything else worth marking.
function POI.Add(name)
	if not name or name:trim() == "" then
		print("|cffff4444Wayfinder|r usage: /wf poi add <name>")
		return
	end
	local uiMapID, position = hereAndNow()
	if not uiMapID then
		print("|cffff4444Wayfinder|r couldn't determine your position.")
		return
	end
	if addIfNew(uiMapID, name, position) then
		print("|cff33ff99Wayfinder|r saved POI \"" .. name .. "\" at your current spot and shared it with your party.")
	else
		print("|cffff4444Wayfinder|r \"" .. name .. "\" is already saved on this map.")
	end
end

-- Called by Comm when a party member's recorded (or re-synced) POI arrives.
-- Dedupes by name+location (see findNearbyMatch above) within the same map
-- so repeated syncs don't pile up duplicate pins for the SAME spot, while
-- still keeping multiple distinct same-named spots (e.g. several mailboxes).
function POI.ReceiveCustom(uiMapID, name, position)
	PC.db.customPOIs[uiMapID] = PC.db.customPOIs[uiMapID] or {}
	local list = PC.db.customPOIs[uiMapID]
	local existing = findNearbyMatch(list, name, position)
	if existing then
		existing.position = position
		return
	end
	table.insert(list, { name = name, position = position })
end

-- Re-broadcasts everything you personally know about, across every map --
-- useful right after someone new joins the party and missed earlier
-- auto-recordings or /wf poi add calls. Fires one addon message per saved
-- POI with no throttling; fine for the handful of spots you'd realistically
-- have, but if this list ever grows into the hundreds, space these out
-- (e.g. via ChatThrottleLib, which Details already ships locally) rather
-- than firing them all in one tick.
function POI.BroadcastAllMine()
	local sent = 0
	for uiMapID, list in pairs(PC.db.customPOIs) do
		for _, p in ipairs(list) do
			PC.Comm.BroadcastPOI({ uiMapID = uiMapID, position = p.position }, p.name)
			sent = sent + 1
		end
	end
	print("|cff33ff99Wayfinder|r re-synced " .. sent .. " custom POI(s) to your party.")
end

-- NOTE: with mailboxes (or anything else) having several same-named entries
-- per map now, this removes whichever one happens to be LAST in the list,
-- not necessarily the one nearest you. Fine for a quick cleanup; if you need
-- to remove one specific mailbox out of several, say so and we'll make this
-- proximity-aware too.
function POI.Remove(name)
	local uiMapID = C_Map.GetBestMapForUnit("player")
	local list = uiMapID and PC.db.customPOIs[uiMapID]
	if not list then
		print("|cffff4444Wayfinder|r no custom POIs saved on this map.")
		return
	end
	for i = #list, 1, -1 do
		if list[i].name:lower() == (name or ""):lower() then
			table.remove(list, i)
			print("|cff33ff99Wayfinder|r removed POI \"" .. name .. "\".")
			return
		end
	end
	print("|cffff4444Wayfinder|r no POI named \"" .. tostring(name) .. "\" on this map.")
end

function POI.ListMine()
	local uiMapID = C_Map.GetBestMapForUnit("player")
	local list = uiMapID and PC.db.customPOIs[uiMapID]
	if not list or #list == 0 then
		print("|cff33ff99Wayfinder|r no custom POIs saved on this map.")
		return
	end
	for _, p in ipairs(list) do
		print(string.format("|cff33ff99Wayfinder|r %s (%.0f, %.0f)", p.name, p.position.x * 100, p.position.y * 100))
	end
end

-- Live flight master nodes on the given map.
local function flightNodes(uiMapID)
	local list = {}
	if not (PC.db.options.showFlightPaths and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return list end
	local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, uiMapID)
	if not ok or not nodes then return list end
	for _, node in ipairs(nodes) do
		if node.position then
			list[#list + 1] = {
				kind = "flight",
				name = node.name,
				uiMapID = uiMapID,
				position = { x = node.position.x, y = node.position.y },
			}
		end
	end
	return list
end

-- Everything POI-related for the map you're currently standing on.
function POI.GetAll()
	local uiMapID = C_Map.GetBestMapForUnit("player")
	if not uiMapID then return {} end

	local list = flightNodes(uiMapID)

	if PC.db.options.showPOI then
		for _, p in ipairs(PC.db.customPOIs[uiMapID] or {}) do
			list[#list + 1] = { kind = "custom", name = p.name, uiMapID = uiMapID, position = p.position }
		end
	end
	return list
end
