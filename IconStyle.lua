-- PartyCompass: IconStyle.lua
-- Shared helper for the "icons" vs "letters" display option. Rather than
-- hardcode guessed Blizzard texture file paths (several of which we couldn't
-- verify exist in this client), this asks the game's own minimap "Find X"
-- tracking-type list for a real texture at runtime and only uses it if one
-- is actually found. Anything that doesn't resolve falls back to a colored
-- letter swatch -- so "icon mode" never shows a broken/blank texture.

local PC = PartyCompass
PC.IconStyle = PC.IconStyle or {}
local IconStyle = PC.IconStyle

local trackingCache = {} -- [nameMatch] = texture or false (checked, not found)

local function findTrackingTexture(nameMatch)
	if trackingCache[nameMatch] ~= nil then
		return trackingCache[nameMatch] or nil
	end
	local texture = nil
	if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		local ok, count = pcall(C_Minimap.GetNumTrackingTypes)
		if ok and count then
			for i = 1, count do
				local ok2, name, tex = pcall(C_Minimap.GetTrackingInfo, i)
				if ok2 and name and tex and name:lower():find(nameMatch, 1, true) then
					texture = tex
					break
				end
			end
		end
	end
	trackingCache[nameMatch] = texture or false
	return texture
end

-- Returns a texture (fileID or path) for this icon kind/label, or nil if
-- icon mode is off or nothing real was found -- callers should fall back to
-- their colored-letter swatch on nil.
function IconStyle.GetTexture(kind, label)
	if PC.db.options.iconStyle ~= "icon" then return nil end

	if kind == "flight" then
		return findTrackingTexture("flight")
	elseif kind == "quest" then
		-- This is the same icon Blizzard ships as the default quest-giver "!",
		-- a long-standing global UI asset (also what QuestTogether's own .toc
		-- uses as its addon-list icon, which confirms it resolves on this client).
		return "Interface\\GossipFrame\\AvailableQuestIcon"
	elseif kind == "custom" then
		local l = (label or ""):lower()
		if l:find("bank", 1, true) then return findTrackingTexture("bank") end
		if l:find("auction", 1, true) then return findTrackingTexture("auction") end
	end
	return nil
end
