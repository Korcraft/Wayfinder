-- Wayfinder: MapPins.lua
-- Our own waypoint pin on the real Blizzard world map.
--
-- ROOT CAUSE FOUND via a real test, not another guess: a frame parented to
-- WorldMapFrame:GetCanvas() never renders on this client, even trivially
-- simple (fixed position, no coordinate math, correct strata). A frame
-- parented to WorldMapFrame ITSELF renders fine -- confirmed with two
-- identical test squares, same code, only the parent different, one
-- visible and one not. That's not a Lua error (the visible one proves this
-- file runs fine) and not a strata/positioning bug -- it's specific to the
-- canvas object on this client.
--
-- Fix: parent pins to WorldMapFrame (proven to render), but POSITION them
-- anchored relative to the canvas's edges via SetPoint's `relativeTo`
-- parameter -- which is independent of actual parent/child rendering in
-- WoW's UI system. So the pin renders (parent = WorldMapFrame) AND tracks
-- the right map location (anchored relative to the canvas).
--
-- Also DROPPED Blizzard's native C_Map.SetUserWaypoint entirely. That
-- system has its own built-in gestures (double-click sets it, shift-click
-- shares it, ctrl-click clears it) which is exactly why our own shift-click
-- never appeared to do anything -- we were fighting Blizzard's own
-- click handling for the same map, not a bug we could patch around. Now
-- that we draw our own pin, we don't touch that system at all, so there's
-- nothing left to conflict with.

local PC = Wayfinder
PC.MapPins = PC.MapPins or {}
local MapPins = PC.MapPins

-- Same icon constants as Compass.lua -- see the note there.
local WAYPOINT_TEXTURE_TEMP = "Interface/AddOns/Wayfinder/Textures/WaypointTemp.png"
local WAYPOINT_TEXTURE_PERMANENT = "Interface/AddOns/Wayfinder/Textures/WaypointPermanent.png"
local FLIGHT_TEXTURE = "Interface/AddOns/Wayfinder/Textures/FlightPoint.png"
local FLIGHT_DISCOVERED_COLOR = { 0.78, 0.78, 0.82 }
local FLIGHT_UNDISCOVERED_COLOR = { 0.35, 1.0, 0.35 }
local AUCTIONEER_TEXTURE = "Interface/AddOns/Wayfinder/Textures/AuctionHouse.png"
local AUCTIONEER_COLOR = { 0.64, 0.21, 0.93 }
local MAILBOX_TEXTURE = "Interface/AddOns/Wayfinder/Textures/Mailbox.png"
local BANK_TEXTURE = "Interface/AddOns/Wayfinder/Textures/Bank.png"
local INNKEEPER_TEXTURE = "Interface/AddOns/Wayfinder/Textures/Innkeeper.png"
local INNKEEPER_COLOR = { 0.9, 0.15, 0.15 }

-- ---------------------------------------------------------------------------
-- Rename dialog for permanent waypoints' name tags (double-click to open).
-- Built from plain Frame/EditBox/Button primitives rather than Blizzard's
-- StaticPopupDialogs -- checked this client for a genuine native
-- StaticPopupDialogs+hasEditBox usage to confirm the exact field names
-- (self.editBox vs self.EditBox etc.) and found none; every hasEditBox
-- example here turned out to be Questie's own custom dialog system, not
-- the real native one. Rather than guess at an unverified API, this uses
-- only bedrock-stable widget methods (EditBox/Button are fundamental,
-- unchanged across WoW's entire history).
-- ---------------------------------------------------------------------------

local renameDialog

local function getRenameDialog()
	if renameDialog then return renameDialog end
	local f = CreateFrame("Frame", "WayfinderRenameDialog", UIParent)
	f:SetSize(260, 100)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)

	local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOP", 0, -12)
	label:SetText("Rename permanent waypoint")

	local edit = CreateFrame("EditBox", nil, f)
	edit:SetSize(220, 24)
	edit:SetPoint("TOP", label, "BOTTOM", 0, -10)
	edit:SetAutoFocus(true)
	edit:SetFontObject("ChatFontNormal")
	edit:SetTextInsets(6, 6, 0, 0)
	edit:SetMaxLetters(32)
	local editBg = edit:CreateTexture(nil, "BACKGROUND")
	editBg:SetAllPoints()
	editBg:SetColorTexture(0, 0, 0, 0.6)
	f.editBox = edit

	local renameBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	renameBtn:SetSize(80, 22)
	renameBtn:SetPoint("BOTTOMLEFT", 20, 14)
	renameBtn:SetText("Rename")

	local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	cancelBtn:SetSize(80, 22)
	cancelBtn:SetPoint("BOTTOMRIGHT", -20, 14)
	cancelBtn:SetText("Cancel")

	local function doRename()
		local newName = edit:GetText()
		if f.waypointId then
			PC.Waypoints.Rename(f.waypointId, newName)
		end
		f:Hide()
	end

	renameBtn:SetScript("OnClick", doRename)
	cancelBtn:SetScript("OnClick", function() f:Hide() end)
	edit:SetScript("OnEnterPressed", doRename)
	edit:SetScript("OnEscapePressed", function() f:Hide() end)

	f:Hide()
	renameDialog = f
	return f
end

local function showRenameDialog(waypointId, currentName)
	local f = getRenameDialog()
	f.waypointId = waypointId
	f.editBox:SetText(currentName or "")
	f.editBox:HighlightText()
	f:Show()
	f.editBox:SetFocus()
end

-- ---------------------------------------------------------------------------
-- Map-click gestures -- defined first so the pin pool below can attach the
-- exact same handling to each pin frame (see the note on handleMapClick).
--   Double-left-click   -> TEMP waypoint there (~15 min, shared with party)
--   Alt + left-click    -> PERMANENT waypoint there (local to you only)
--   Shift + left-click  -> remove whichever of YOUR OWN waypoints is
--                          nearest to that spot (confirms first for
--                          permanent ones -- see the StaticPopup below)
-- Right-click is never hooked -- that's the map's native zoom-out.
--
-- Ctrl+click was the first choice for "permanent waypoint" but Blizzard's
-- own map already does something with it natively (its own built-in
-- waypoint scheme, same reason double-click/shift-click used to conflict
-- before we dropped reliance on the native system) -- Alt+click avoids that
-- since nothing here is bound to it.
--
-- Cursor position via WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()
-- (confirmed real, used this exact way by Questie's own click code).
-- ---------------------------------------------------------------------------

StaticPopupDialogs["WAYFINDER_DELETE_PERMANENT"] = {
	text = "Delete permanent waypoint \"%s\"?",
	button1 = "Yes",
	button2 = "Cancel",
	OnAccept = function(_, id) PC.Waypoints.RemoveByID(id) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local DOUBLE_CLICK_WINDOW = 0.4 -- seconds
local lastClickTime = -1

local function cursorToMapPosition()
	local canvas = WorldMapFrame:GetCanvas()
	if not canvas:IsMouseOver() then return nil end
	local x, y = WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y
end

-- The one real gesture handler, shared by BOTH the map's own OnMouseUp AND
-- each waypoint pin's OnMouseUp (see acquirePin below). Without this, a
-- click landing exactly ON a pin -- the natural way to click "this
-- waypoint" to remove it -- gets swallowed by the pin's own mouse-enabled
-- frame (needed for its tooltip) before it ever reaches the map's handler
-- underneath, since the pin renders on top of it. That's exactly why
-- shift-click silently did nothing when clicking directly on an icon.
local function handleMapClick(button)
	if button ~= "LeftButton" then return end -- right-click: untouched, native zoom-out
	local mapID = WorldMapFrame:GetMapID()
	local nx, ny = cursorToMapPosition()
	if not mapID or not nx then return end

	-- No chat prints for any of these map-click actions on purpose -- the
	-- icon appearing/disappearing on the map is already the feedback; a
	-- print on every single click gets old fast. Slash commands still
	-- print confirmations (those are deliberate, typed, and infrequent).
	if IsShiftKeyDown() then
		local id, entry = PC.Waypoints.FindNearest(mapID, nx, ny)
		if not id then return end
		if entry.kind == "P" then
			StaticPopup_Show("WAYFINDER_DELETE_PERMANENT", entry.name, nil, id)
		else
			PC.Waypoints.RemoveByID(id)
		end
		return
	end

	if IsAltKeyDown() then
		PC.Waypoints.AddAt(mapID, { x = nx, y = ny }, nil, nil, false)
		return
	end

	local now = GetTime()
	if lastClickTime > 0 and (now - lastClickTime) < DOUBLE_CLICK_WINDOW then
		lastClickTime = -1 -- don't let a 3rd click chain into another double-click
		PC.Waypoints.AddAt(mapID, { x = nx, y = ny }, nil, nil, true)
	else
		lastClickTime = now
	end
end

-- ---------------------------------------------------------------------------
-- Pin pool: simple frames parented to WorldMapFrame (renders), positioned
-- relative to the canvas (tracks the right map location).
-- ---------------------------------------------------------------------------

local pool = {}
local used = 0

local function acquirePin()
	used = used + 1
	local pin = pool[used]
	if not pin then
		pin = CreateFrame("Frame", nil, WorldMapFrame)
		pin:SetFrameStrata(WorldMapFrame:GetFrameStrata())
		pin:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 50)
		pin:SetSize(20, 20)
		pin.bg = pin:CreateTexture(nil, "OVERLAY")
		pin.bg:SetAllPoints()
		pin:EnableMouse(true)
		pin:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipTitle or "")
			GameTooltip:Show()
		end)
		pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- Same click handling the map itself has -- see handleMapClick above.
		pin:SetScript("OnMouseUp", function(_, button) handleMapClick(button) end)

		-- Name tag for permanent waypoints: a small label above the pin,
		-- double-click to rename. Parented directly to WorldMapFrame (NOT
		-- to `pin`) -- same proven-safe pattern as the pin itself, rather
		-- than assuming a grandchild of WorldMapFrame (nameTag -> pin ->
		-- WorldMapFrame) would render the same way we haven't tested that.
		-- Only shown for permanent waypoints; Refresh() below toggles it.
		local nameTag = CreateFrame("Frame", nil, WorldMapFrame)
		nameTag:SetFrameStrata(WorldMapFrame:GetFrameStrata())
		nameTag:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 51)
		nameTag:SetSize(120, 16)
		nameTag.bg = nameTag:CreateTexture(nil, "BACKGROUND")
		nameTag.bg:SetAllPoints()
		nameTag.bg:SetColorTexture(0, 0, 0, 0.6)
		nameTag.text = nameTag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		nameTag.text:SetAllPoints()
		nameTag:EnableMouse(true)
		nameTag.lastClick = -1
		nameTag:SetScript("OnMouseUp", function(self, button)
			if button ~= "LeftButton" then return end
			local now = GetTime()
			if self.lastClick > 0 and (now - self.lastClick) < 0.4 then
				self.lastClick = -1
				showRenameDialog(self.waypointId, self.text:GetText())
			else
				self.lastClick = now
			end
		end)
		pin.nameTag = nameTag
		pool[used] = pin
	end
	pin:Show()
	return pin
end

local function releaseUnused()
	for i = used + 1, #pool do
		pool[i]:Hide()
		pool[i].nameTag:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- Party member portraits on the map -- same proven pattern as the waypoint
-- pins above (parented to WorldMapFrame, positioned relative to the canvas),
-- same real-portrait technique as the compass (SetPortraitTexture).
-- ---------------------------------------------------------------------------

local partyPinPool = {}
local partyPinUsed = 0

local function acquirePartyPin()
	partyPinUsed = partyPinUsed + 1
	local pin = partyPinPool[partyPinUsed]
	if not pin then
		pin = CreateFrame("Frame", nil, WorldMapFrame)
		pin:SetFrameStrata(WorldMapFrame:GetFrameStrata())
		pin:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 50)
		pin:SetSize(28, 28) -- placeholder -- real size set every refresh from mapPartyIconSize
		-- Class-color outline: the same circular disc texture, a few px
		-- bigger, drawn one sublevel behind the portrait/dot so only its
		-- rim peeks out around the edge -- a ring, without needing a
		-- dedicated ring-shaped texture asset.
		pin.border = pin:CreateTexture(nil, "OVERLAY", nil, -1)
		pin.border:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
		pin.bg = pin:CreateTexture(nil, "OVERLAY")
		pin.bg:SetAllPoints()
		pin:EnableMouse(true)
		pin:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipTitle or "")
			GameTooltip:Show()
		end)
		pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
		partyPinPool[partyPinUsed] = pin
	end
	pin:Show()
	return pin
end

local function releasePartyPinsUnused()
	for i = partyPinUsed + 1, #partyPinPool do partyPinPool[i]:Hide() end
end

-- ---------------------------------------------------------------------------
-- Flight point pins -- same proven WorldMapFrame-parented pattern, no click
-- gesture (just a hover tooltip with the node name + discovered status).
-- ---------------------------------------------------------------------------

local flightPinPool = {}
local flightPinUsed = 0

local function acquireFlightPin()
	flightPinUsed = flightPinUsed + 1
	local pin = flightPinPool[flightPinUsed]
	if not pin then
		pin = CreateFrame("Frame", nil, WorldMapFrame)
		pin:SetFrameStrata(WorldMapFrame:GetFrameStrata())
		pin:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 50)
		pin:SetSize(20, 20)
		pin.bg = pin:CreateTexture(nil, "OVERLAY")
		pin.bg:SetAllPoints()
		pin:EnableMouse(true)
		pin:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipTitle or "")
			GameTooltip:Show()
		end)
		pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
		flightPinPool[flightPinUsed] = pin
	end
	pin:Show()
	return pin
end

local function releaseFlightPinsUnused()
	for i = flightPinUsed + 1, #flightPinPool do flightPinPool[i]:Hide() end
end

-- ---------------------------------------------------------------------------
-- Auction house / bank / mailbox pins -- same shape as the flight pin pool
-- above (no click gesture, just a hover tooltip), shared since all three
-- are the same kind of thing (a static point of interest). One shared pool
-- function, separate pool INSTANCES per category below so each can be
-- shown/hidden independently.
-- ---------------------------------------------------------------------------

-- Returns (beginPass, acquire, endPass) -- beginPass zeroes the used-count
-- for a fresh render pass, acquire grabs the next pin (creating one if the
-- pool's run dry), endPass hides whatever's left over from last time. Same
-- explicit begin/acquire/end shape as the flight pin pool above, just
-- closure-based instead of module-level locals so this can be instantiated
-- once per category (Auctioneer/Banker/Mailbox) without copy-pasting the
-- whole pool.
local function makeLocationPinPool()
	local pool, used = {}, 0
	local function beginPass() used = 0 end
	local function acquire()
		used = used + 1
		local pin = pool[used]
		if not pin then
			pin = CreateFrame("Frame", nil, WorldMapFrame)
			pin:SetFrameStrata(WorldMapFrame:GetFrameStrata())
			pin:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 50)
			pin:SetSize(18, 18)
			pin.bg = pin:CreateTexture(nil, "OVERLAY")
			pin.bg:SetAllPoints()
			pin:EnableMouse(true)
			pin:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(self.tooltipTitle or "")
				GameTooltip:Show()
			end)
			pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
			pool[used] = pin
		end
		pin:Show()
		return pin
	end
	local function endPass()
		for i = used + 1, #pool do pool[i]:Hide() end
	end
	return beginPass, acquire, endPass
end

local beginAuctioneerPins, acquireAuctioneerPin, endAuctioneerPins = makeLocationPinPool()
local beginBankPins, acquireBankPin, endBankPins = makeLocationPinPool()
local beginMailboxPins, acquireMailboxPin, endMailboxPins = makeLocationPinPool()
local beginInnkeeperPins, acquireInnkeeperPin, endInnkeeperPins = makeLocationPinPool()

local function placePin(pin, canvas, width, height, x, y)
	pin:ClearAllPoints()
	-- relativeTo = canvas (tracks the right map location); parent stays
	-- WorldMapFrame (the only thing confirmed to actually render).
	--
	-- CALIBRATED from a real screenshot: the pin was consistently landing
	-- at ~62% of the distance from the canvas's corner to the actual click,
	-- the same ratio on both axes -- a uniform shrink-toward-the-corner,
	-- not a fixed offset. That's the signature of a SetPoint offset given
	-- in the wrong frame's scale: our offset (x*width) is measured in the
	-- canvas's own pixel units, but since the pin is parented to
	-- WorldMapFrame (not the canvas), WoW interprets that offset using
	-- WorldMapFrame's effective scale instead. If the canvas has a
	-- different effective scale than WorldMapFrame (plausible if it scales
	-- itself for zooming), that mismatch shrinks/grows the offset by
	-- exactly their scale ratio -- so convert through it explicitly.
	local scale = canvas:GetEffectiveScale() / WorldMapFrame:GetEffectiveScale()
	pin:SetPoint("CENTER", canvas, "TOPLEFT", x * width * scale, -y * height * scale)
end

function MapPins.Refresh()
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	local shownMapID = WorldMapFrame:GetMapID()
	if not shownMapID then return end

	local canvas = WorldMapFrame:GetCanvas()
	local width, height = canvas:GetWidth(), canvas:GetHeight()

	-- Player's own position on the CURRENTLY SHOWN map, if they're actually
	-- standing on it -- used by the mailbox nearest-only filter below. Only
	-- meaningful when shownMapID is the zone you're in; if you're browsing
	-- a different zone's map, myX stays nil and that filter falls back to
	-- showing every mailbox in it instead (there's no "nearest" to compute
	-- without a real player position on that same map).
	local myX, myY, myMapWidth, myMapHeight
	local okMyPos, myPos = pcall(C_Map.GetPlayerMapPosition, shownMapID, "player")
	if okMyPos and myPos then myX, myY = myPos:GetXY() end
	local okMySize, mySizeW, mySizeH = pcall(C_Map.GetMapWorldSize, shownMapID)
	if okMySize then myMapWidth, myMapHeight = mySizeW, mySizeH end

	used = 0
	for _, wp in ipairs(PC.Waypoints.GetAll()) do
		if wp.uiMapID == shownMapID then
			local pin = acquirePin()
			-- Pins are reused across both kinds over time (the pool doesn't
			-- dedicate a frame to one kind forever), so size has to be set
			-- fresh each refresh, not just once at creation. Both kinds
			-- render at the same size now, adjustable via the
			-- small/medium/large setting (see Waypoints.MapIconSize).
			local sz = PC.Waypoints.MapIconSize()
			pin:SetSize(sz, sz)
			placePin(pin, canvas, width, height, wp.position.x, wp.position.y)
			pin.tooltipTitle = PC.Waypoints.TooltipLabel(wp)
			local c = (wp.kind == "P") and PC.Waypoints.PERMANENT_COLOR or PC.Waypoints.colorForIndex(wp.colorIndex or 1)
			pin.bg:SetTexture(wp.kind == "P" and WAYPOINT_TEXTURE_PERMANENT or WAYPOINT_TEXTURE_TEMP)
			pin.bg:SetVertexColor(c[1], c[2], c[3], 1)

			if wp.kind == "P" then
				pin.nameTag:ClearAllPoints()
				pin.nameTag:SetPoint("BOTTOM", pin, "TOP", 0, 2)
				pin.nameTag.text:SetText(wp.name)
				pin.nameTag.waypointId = wp.id
				pin.nameTag:Show()
			else
				pin.nameTag:Hide()
			end
		end
	end
	releaseUnused()

	-- Party member portraits -- same-map only (unlike the compass, a map
	-- view can only ever show what's on the map currently open; there's no
	-- sensible "edge pin" equivalent for a different zone here). Gated by
	-- its own setting, independent of the compass's.
	partyPinUsed = 0
	if PC.db.options.showPartyMap then
		for _, member in ipairs(PC.PartyTracker.GetAll()) do
			if member.uiMapID == shownMapID then
				local ok, pos = pcall(C_Map.GetPlayerMapPosition, shownMapID, member.unit)
				if ok and pos then
					local x, y = pos:GetXY()
					local pin = acquirePartyPin()
					local sz = PC.db.options.mapPartyIconSize
					pin:SetSize(sz, sz)
					placePin(pin, canvas, width, height, x, y)
					pin.tooltipTitle = member.name
					local c = PC.PartyTracker.ClassColor(member.unit)
					pin.border:ClearAllPoints()
					pin.border:SetPoint("CENTER", pin, "CENTER")
					pin.border:SetSize(pin:GetWidth() + 4, pin:GetHeight() + 4)
					pin.border:SetVertexColor(c[1], c[2], c[3], 1)
					local portraitOk = not PC.db.options.mapPartyIconDots and pcall(SetPortraitTexture, pin.bg, member.unit)
					if portraitOk then
						pin.bg:SetVertexColor(1, 1, 1, 1)
					else
						-- Same round-disc trick as the compass -- a real
						-- circular Blizzard texture tinted via vertex color,
						-- not a flat SetColorTexture square.
						pin.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
						pin.bg:SetVertexColor(c[1], c[2], c[3], 1)
					end
				end
			end
		end
	end
	releasePartyPinsUnused()

	-- Flight points -- same zone-scoped rule as the compass: GetAll()
	-- already only returns nodes on the player's CURRENT map (see
	-- FlightPoints.lua), and this double-checks against the map ACTUALLY
	-- open (which can be a different zone than the one you're standing in).
	flightPinUsed = 0
	if PC.db.options.showFlightPathsMap then
		for _, fp in ipairs(PC.FlightPoints.GetAll()) do
			if fp.uiMapID == shownMapID then
				local pin = acquireFlightPin()
				local sz = PC.db.options.mapFlightIconSize
				pin:SetSize(sz, sz)
				placePin(pin, canvas, width, height, fp.position.x, fp.position.y)
				pin.tooltipTitle = fp.name .. (fp.discovered and "" or " (undiscovered)")
				pin.bg:SetTexture(FLIGHT_TEXTURE)
				local c = fp.discovered and FLIGHT_DISCOVERED_COLOR or FLIGHT_UNDISCOVERED_COLOR
				pin.bg:SetVertexColor(c[1], c[2], c[3], 1)
			end
		end
	end
	releaseFlightPinsUnused()

	-- Auction house -- same zone-scoped rule, no distance limit (unlike the
	-- compass -- see Compass.lua for why that one needs a proximity radius
	-- and this doesn't: the map has room to show a whole zone's markers).
	beginAuctioneerPins()
	if PC.db.options.showAuctioneerMap then
		for _, loc in ipairs(PC.Locations.GetAll("Auctioneer")) do
			if loc.uiMapID == shownMapID then
				local pin = acquireAuctioneerPin()
				local sz = PC.db.options.mapLocationIconSize
				pin:SetSize(sz, sz)
				placePin(pin, canvas, width, height, loc.x, loc.y)
				pin.tooltipTitle = "Auction House"
				pin.bg:SetTexture(AUCTIONEER_TEXTURE)
				pin.bg:SetVertexColor(AUCTIONEER_COLOR[1], AUCTIONEER_COLOR[2], AUCTIONEER_COLOR[3], 1)
			end
		end
	end
	endAuctioneerPins()

	-- Bank -- same zone-scoped, no-distance-limit rule.
	beginBankPins()
	if PC.db.options.showBankMap then
		for _, loc in ipairs(PC.Locations.GetAll("Banker")) do
			if loc.uiMapID == shownMapID then
				local pin = acquireBankPin()
				local sz = PC.db.options.mapLocationIconSize
				pin:SetSize(sz, sz)
				placePin(pin, canvas, width, height, loc.x, loc.y)
				pin.tooltipTitle = "Bank"
				pin.bg:SetTexture(BANK_TEXTURE)
				pin.bg:SetVertexColor(1, 1, 1, 1)
			end
		end
	end
	endBankPins()

	-- Mailbox -- same nearest-only rule as the compass now (see
	-- Compass.lua's own note on why: several cities have multiple
	-- mailboxes, and showing all of them is worse clutter than any other
	-- marker). Needs a real player position on the SHOWN map to know what
	-- "nearest" means -- falls back to showing every mailbox in the zone
	-- if you're browsing a map you're not actually standing on.
	beginMailboxPins()
	if PC.db.options.showMailboxMap then
		local nearest, nearestDistSq
		for _, loc in ipairs(PC.Locations.GetAll("Mailbox")) do
			if loc.uiMapID == shownMapID then
				if myX then
					local dx = (loc.x - myX) * (myMapWidth or 1)
					local dy = (loc.y - myY) * (myMapHeight or 1)
					local distSq = dx * dx + dy * dy
					if not nearestDistSq or distSq < nearestDistSq then
						nearest, nearestDistSq = loc, distSq
					end
				else
					local pin = acquireMailboxPin()
					local sz = PC.db.options.mapLocationIconSize
					pin:SetSize(sz, sz)
					placePin(pin, canvas, width, height, loc.x, loc.y)
					pin.tooltipTitle = "Mailbox"
					pin.bg:SetTexture(MAILBOX_TEXTURE)
					pin.bg:SetVertexColor(1, 1, 1, 1)
				end
			end
		end
		if myX and nearest then
			local pin = acquireMailboxPin()
			local sz = PC.db.options.mapLocationIconSize
			pin:SetSize(sz, sz)
			placePin(pin, canvas, width, height, nearest.x, nearest.y)
			pin.tooltipTitle = "Mailbox"
			pin.bg:SetTexture(MAILBOX_TEXTURE)
			pin.bg:SetVertexColor(1, 1, 1, 1)
		end
	end
	endMailboxPins()

	-- Innkeeper -- same zone-scoped, no-distance-limit rule.
	beginInnkeeperPins()
	if PC.db.options.showInnkeeperMap then
		for _, loc in ipairs(PC.Locations.GetAll("Innkeeper")) do
			if loc.uiMapID == shownMapID then
				local pin = acquireInnkeeperPin()
				local sz = PC.db.options.mapLocationIconSize
				pin:SetSize(sz, sz)
				placePin(pin, canvas, width, height, loc.x, loc.y)
				pin.tooltipTitle = "Innkeeper"
				pin.bg:SetTexture(INNKEEPER_TEXTURE)
				pin.bg:SetVertexColor(INNKEEPER_COLOR[1], INNKEEPER_COLOR[2], INNKEEPER_COLOR[3], 1)
			end
		end
	end
	endInnkeeperPins()
end

local function setupMapClickGestures()
	WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", function(_, button)
		handleMapClick(button)
	end)
end

-- Small legend, bottom-right corner of the map, explaining the click
-- gestures above. (Confirmed rendering correctly -- same WorldMapFrame
-- parenting as the pins.)
local function setupLegend()
	local legend = CreateFrame("Frame", nil, WorldMapFrame)
	legend:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	legend:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 50)
	legend:SetSize(260, 64)
	legend:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -24, 24)

	local bg = legend:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)

	local text = legend:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("TOPLEFT", 6, -6)
	text:SetPoint("BOTTOMRIGHT", -6, 6)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetText(
		"Double-click: Temp waypoint (15m, shared)\n" ..
		"Alt+click: Permanent waypoint (local only)\n" ..
		"Shift+click: Remove nearest waypoint"
	)

	legend:Show()
end

function MapPins.Init()
	setupMapClickGestures()
	setupLegend()

	-- Wrapped in pcall so one bad map (e.g. a brand-new dungeon whose
	-- canvas/floor data behaves differently) can't silently wedge pin
	-- updates with no visible sign of why -- same reasoning as Compass.lua.
	local warnedRefreshError = false
	local function safeRefresh()
		local ok, err = pcall(MapPins.Refresh)
		if not ok and not warnedRefreshError then
			warnedRefreshError = true
			print("|cffff4444Wayfinder|r map pin update error (won't spam further): " .. tostring(err))
		end
	end

	WorldMapFrame:HookScript("OnShow", safeRefresh)
	hooksecurefunc(WorldMapFrame, "SetMapID", safeRefresh)

	-- Our own data can change (waypoint added/removed, a temp one expires)
	-- independently of the map being opened/navigated, so still poll.
	local ticker = CreateFrame("Frame")
	ticker:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t or 0) + elapsed
		if self.t > 1 then
			self.t = 0
			safeRefresh()
		end
	end)
end
