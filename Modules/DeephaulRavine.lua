local addon, ns = ...
local PVPSound = ns.PVPSound
local PS = ns.PS
local API = PVPSound.API
local L = PVPSound.L

-- Deephaul Ravine is new-ish; objective text is parsed from BG system messages where possible.
local mod = API:RegisterMod(2552, "pvp", "Deephaul Ravine", 2345)

local L = PVPSound.L
local POIDebug = false

-- Reuse existing CTF flag announcements (Deephaul does not have dedicated sound assets in most packs yet)
local FlagSoundZone = "Zone_WarsongGulch"

local function MsgLower(msg)
	if msg == nil then return nil end
	return string.lower(msg)
end

local function IsCrystalTaken(msgLower)
	if msgLower == nil then return false end
	-- Common English variants seen in-game / community clips:
	-- "<name> has taken the crystal!"
	-- "<name> picked up the crystal!"
	return (msgLower:find("crystal") ~= nil) and
		((msgLower:find("has taken") ~= nil) or (msgLower:find("picked") ~= nil) or (msgLower:find("picked up") ~= nil))
end

local function IsCrystalDropped(msgLower)
	if msgLower == nil then return false end
	return (msgLower:find("crystal") ~= nil) and (msgLower:find(L["dropped"]) ~= nil or msgLower:find("dropped") ~= nil)
end

local function IsCrystalReturned(msgLower)
	if msgLower == nil then return false end
	return (msgLower:find("crystal") ~= nil) and (msgLower:find(L["returned"]) ~= nil or msgLower:find("returned") ~= nil)
end

local function AnnounceCrystal(faction, state)
	-- faction: "Alliance" (blue) / "Horde" (red)
	-- state: "Taken" / "Dropped" / "Returned"
	if faction == nil or state == nil then return end

	if faction == "Alliance" then
		if state == "Taken" then
			PVPSound:AddToQueue(PS.SoundPackDirectory .. "\\" .. PS_SoundPackLanguage .. "\\" .. FlagSoundZone .. "\\ALLIANCE_Flag_Taken.mp3")
			PVPSound:AddToSct("Blue flag taken", PSSctFrame)
		elseif state == "Dropped" then
			PVPSound:AddToQueue(PS.SoundPackDirectory .. "\\" .. PS_SoundPackLanguage .. "\\" .. FlagSoundZone .. "\\ALLIANCE_Flag_Dropped.mp3")
			PVPSound:AddToSct("Blue flag dropped", PSSctFrame)
		elseif state == "Returned" then
			PVPSound:AddToQueue(PS.SoundPackDirectory .. "\\" .. PS_SoundPackLanguage .. "\\" .. FlagSoundZone .. "\\ALLIANCE_Flag_Returned.mp3")
			PVPSound:AddToSct("Blue flag returned", PSSctFrame)
		end
	elseif faction == "Horde" then
		if state == "Taken" then
			PVPSound:AddToQueue(PS.SoundPackDirectory .. "\\" .. PS_SoundPackLanguage .. "\\" .. FlagSoundZone .. "\\HORDE_Flag_Taken.mp3")
			PVPSound:AddToSct("Red flag taken", PSSctFrame)
		elseif state == "Dropped" then
			PVPSound:AddToQueue(PS.SoundPackDirectory .. "\\" .. PS_SoundPackLanguage .. "\\" .. FlagSoundZone .. "\\HORDE_Flag_Dropped.mp3")
			PVPSound:AddToSct("Red flag dropped", PSSctFrame)
		elseif state == "Returned" then
			PVPSound:AddToQueue(PS.SoundPackDirectory .. "\\" .. PS_SoundPackLanguage .. "\\" .. FlagSoundZone .. "\\HORDE_Flag_Returned.mp3")
			PVPSound:AddToSct("Red flag returned", PSSctFrame)
		end
	end
end

function mod:Setup()
	--Keep track of POIs
	API:RegisterEvent("PLAYER_ENTERING_WORLD", self)
	API:RegisterEvent("ZONE_CHANGED_NEW_AREA", self)

	-- Deephaul crystal/flag messages are broadcast via BG system chat events.
	API:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE", self)
	API:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE", self)
	API:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL", self)

	-- Legacy event (some builds still fire it); harmless if unused.
	API:RegisterEvent("WORLD_MAP_UPDATE", self)
end

function mod:Unload()
	API:UnregisterAllEvents()
end

function mod:WORLD_MAP_UPDATE()
	if POIDebug == true then
		PVPSound:Debug("POI Debug: " .. tostring(POIDebug))
		PVPSound:GetPOIs(mod.zoneId)
	end
end

function mod:CHAT_MSG_BG_SYSTEM_ALLIANCE(event, msg)
	local m = MsgLower(msg)
	if IsCrystalTaken(m) then
		AnnounceCrystal("Alliance", "Taken")
	elseif IsCrystalDropped(m) then
		AnnounceCrystal("Alliance", "Dropped")
	elseif IsCrystalReturned(m) then
		AnnounceCrystal("Alliance", "Returned")
	end
end

function mod:CHAT_MSG_BG_SYSTEM_HORDE(event, msg)
	local m = MsgLower(msg)
	if IsCrystalTaken(m) then
		AnnounceCrystal("Horde", "Taken")
	elseif IsCrystalDropped(m) then
		AnnounceCrystal("Horde", "Dropped")
	elseif IsCrystalReturned(m) then
		AnnounceCrystal("Horde", "Returned")
	end
end

function mod:CHAT_MSG_BG_SYSTEM_NEUTRAL(event, msg)
	-- Some locales/routes send certain objective messages as neutral.
	-- We don't have a reliable faction in that case, so ignore for now.
	-- If you see crystal events arriving here, capture the chat text and we can expand parsing.
end

function mod:PLAYER_ENTERING_WORLD()
	-- timer for fighting
	PVPSound:StartFightingTimer()
end

function mod:ZONE_CHANGED_NEW_AREA()
	-- timer for fighting
	PVPSound:StartFightingTimer()
end

function mod:OnLoad()
	mod:Setup()
end

function mod:OnUnload()
	mod:Unload()
end