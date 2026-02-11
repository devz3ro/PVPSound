--[[
	   _          _     _         _        _           _      _          _
	 _/\\___   _ /\\  _/\\___    /\\__  __/\\___  ___ /\\   _/\\___   __/\\___
	(_   _ _))/ \\ \\(_   _ _)) /    \\(_     _))/  //\ \\ (_      ))(_  ____))
	 /  |))\\ \:'/ // /  |))\\ _\  \_// /  _  \\ \:.\\_\ \\ /  :   \\ /   _ \\
	/:. ___//  \  // /:. ___//// \:.\  /:.(_)) \\ \  :.  ///:. |   ///:. |_\ \\
	\_ \\     (_  _))\_ \\    \\__  /  \  _____//(_   ___))\___|  // \  _____//
	  \//       \//    \//       \\/    \//        \//5.1.0     \//   \//

	PVPSound
	Copyright (c) 2010-2020 Resperger Dániel (Resike)
	E-Mail: reske@gmail.com
	All rights reserved.
	See the accompanying "!Licence.txt" for more information.
	The addon can be found at:
	http://www.curse.com/addons/wow/pvpsound
	http://www.wowinterface.com/downloads/info19569-PVPSound.html
--]]

local addon, ns = ...
local PVPSound = ns.PVPSound
local PVPSoundOptions = ns.PVPSoundOptions
local PS = ns.PS
local L = ns.L


local bit = bit
local ceil = ceil
local floor = floor
local getglobal = getglobal
local pairs = pairs
local print = print
local select = select
local string = string
local table = table
local tonumber = tonumber
local tostring = tostring

local C_ChatInfo = C_ChatInfo
local C_Map = C_Map
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local CreateFrame = CreateFrame
local GetAddOnCPUUsage = GetAddOnCPUUsage
local GetAddOnMemoryUsage = GetAddOnMemoryUsage
local GetTime = GetTime
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local PlaySoundFile = PlaySoundFile
local SendChatMessage = SendChatMessage
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsEnemy = UnitIsEnemy
local UnitIsPlayer = UnitIsPlayer
local UnitName = UnitName
local UnitSex = UnitSex
local UpdateAddOnCPUUsage = UpdateAddOnCPUUsage
local UpdateAddOnMemoryUsage = UpdateAddOnMemoryUsage
local CombatLog_Object_IsA = CombatLog_Object_IsA

local LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE

--[[local GetBuildInfo = GetBuildInfo
local GetMapLandmarkInfo = GetMapLandmarkInfo
local SendChatMessage = SendChatMessage
local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitName = UnitName]]

-- Settings
local TimerReset
local ResetTime
local MultiKillTime
local RankStep

-- Player
local MyGender

-- Zones
local InstanceType
local CurrentInstId
local CurrentZoneId

-- Kills
local MultiKills
local CurrentStreak
local LastKill
local FirstKill
local FirstMultiKill

-- Deaths
local KilledMe
local KilledBy
local KilledWho
local GotKilledBy

-- Enemys
local ToEnemy
local FromEnemy
local ToEnemyNPC
local FromEnemyNPC
local ToEnemyPlayer
local ToEnemyPlayerAndNPC
local FromMyPets
local FromEnemyPlayer
local FromEnemyPlayerAndNPC

--addon modules table
PVPSound.modules = { }

-- WOW Version check
PS.isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local PVPSoundFrame = CreateFrame("Frame", nil)
PVPSoundFrame:RegisterEvent("ADDON_LOADED")

local PVPSoundFrameBG
local PVPSoundFrameExecute
local PVPSoundFrameKills
local PVPSoundFrameData

function PVPSound:LoadBG()
	if PS_EnableAddon == true and PS_BattlegroundSound == true then
		if not PVPSoundFrameBG then
			PVPSoundFrameBG = CreateFrame("Frame", nil)
		end
		PVPSoundFrameBG:RegisterEvent("PLAYER_ENTERING_WORLD")
		PVPSoundFrameBG:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		PVPSoundFrameBG:SetScript("OnEvent", PVPSound.OnEventBG)
		CurrentZoneId = C_Map.GetBestMapForUnit("player")
		InstanceType = (select(2, IsInInstance()))
		CurrentInstId = (select(8, GetInstanceInfo()))
		PVPSound.API:LoadModules(CurrentZoneId, InstanceType, CurrentInstId)
		PVPSound:Debug("!BG Events Loaded")
	end
end

-- If this function will be called during DG, nothng happens, but the next BG will not be loaded.
function PVPSound:UnloadBG()
	if PVPSoundFrameBG then
		PVPSoundFrameBG:UnregisterEvent("PLAYER_ENTERING_WORLD")
		PVPSoundFrameBG:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
		PVPSound.API:UnregisterAllEvents()
		PVPSound.API:UnloadModules()
		PVPSound:Debug("!BG Events Unloaded")
	end
end

function PVPSound:LoadExecute()
	if PS_EnableAddon == true and PS_Execute == true then
		if not PVPSoundFrameExecute then
			PVPSoundFrameExecute = CreateFrame("Frame", nil)
		end
		PVPSoundFrameExecute:RegisterEvent("PLAYER_TARGET_CHANGED")
		PVPSoundFrameExecute:RegisterEvent("UNIT_HEALTH")
		PVPSoundFrameExecute:RegisterEvent("UNIT_MAXHEALTH")
		PVPSoundFrameExecute:SetScript("OnEvent", PVPSound.OnEventExecute)
		PVPSound:Debug("!Execute Events Loaded")
	end
end

function PVPSound:UnloadExecute()
	if PVPSoundFrameExecute then
		PVPSoundFrameExecute:UnregisterEvent("PLAYER_TARGET_CHANGED")
		PVPSoundFrameExecute:UnregisterEvent("UNIT_HEALTH")
		PVPSoundFrameExecute:UnregisterEvent("UNIT_MAXHEALTH")
		PVPSound:Debug("!Execute Events Unloaded")
	end
end


local PVPSound_ScoreRequestElapsed = 0
local PVPSound_LastScoreRequest = 0
function PVPSound:LoadKills()
	if not PVPSoundFrameKills then
		PVPSoundFrameKills = CreateFrame("Frame", nil)
	end

	if (PS_KillSound == true or PS_MultiKillSound == true or PS_PaybackSound == true) and PS_EnableAddon == true then
		-- WoW 12.0+: some clients can flag Frame:RegisterEvent() as protected for certain scoreboard events.
		-- Polling the scoreboard avoids ADDON_ACTION_FORBIDDEN while keeping killing blow detection working.
		PVPSoundFrameKills:SetScript("OnUpdate", function(_, elapsed) PVPSound:KillsOnUpdate(elapsed) end)
		PVPSound:ResetScoreTracking()
		PVPSound:Debug("Kills poller loaded")
	else
		PVPSound:Debug("Kills not enabled")
	end
end
function PVPSound:UnloadKills()
	if PVPSoundFrameKills then
		if (PS_KillSound == false and PS_MultiKillSound == false and PS_PaybackSound == false) or PS_EnableAddon == false then
			PVPSoundFrameKills:SetScript("OnUpdate", nil)
			PVPSound:Debug("!Kills poller unloaded")
		end
	end
end


-- ===== WoW 12.0 PvP kill detection helpers (scoreboard + safe PARTY_KILL debug) =====

function PVPSound:ResetScoreTracking()
	PVPSound._LastKB = nil
	PVPSound._LastDeaths = nil
	PVPSound_ScoreRequestElapsed = 0
	PVPSound_LastScoreRequest = 0
	-- NEW: Initialize Kill Stat baseline for Fast Path
	-- (1487 is Total Killing Blows, 1 is the criteria index)
	local _, _, _, _, _, _, _, _, killCount = GetAchievementCriteriaInfoByID(1487, 0)
	PVPSound._LastKillStat = killCount or 0
	PVPSound._FastKillTimestamp = 0
end
local function PVPSound_SafeToString(v)
	if v == nil then return nil end
	-- If the client provides secret-value helpers, try to scrub first
	if type(scrubsecretvalues) == "function" then
		local ok, t = pcall(scrubsecretvalues, { v })
		if ok and type(t) == "table" then
			v = t[1]
		end
	end
	if v == nil then return nil end

	local ok, s = pcall(tostring, v)
	if ok then
		return s
	end
	return nil
end

function PVPSound:HandlePartyKill(killerGUID, victimGUID)
	-- [12.0 Fix] Helper to safely check secrets
	local function IsSecret(val)
		if type(issecretvalue) == "function" then return issecretvalue(val) end
		return false
	end

	-- 1. Check "Total Killing Blows" Statistic (ID 1487, Criteria 1)
	local _, _, _, _, _, _, _, _, currentKillStat = GetAchievementCriteriaInfoByID(1487, 0)
	currentKillStat = currentKillStat or 0
	
	if not PVPSound._LastKillStat then PVPSound._LastKillStat = currentKillStat end

	local statIncreased = currentKillStat > PVPSound._LastKillStat
	
	-- 2. Determine if it was OUR kill
	local isMyKill = false
	local myGUID = UnitGUID("player")

	-- Check A: Explicit GUID match (Only if not secret)
	if not IsSecret(killerGUID) and killerGUID == myGUID then
		isMyKill = true
	-- Check B: Stat increased (Works even if secret)
	elseif statIncreased then
		isMyKill = true
	end

	-- 3. Trigger and Sync
	if isMyKill then
		if PS_Debug then PVPSound:Debug("FAST PATH: Kill Detected via " .. (statIncreased and "Stat" or "GUID")) end
		
		-- Update stat baseline
		PVPSound._LastKillStat = currentKillStat
		
		-- Set timestamp to deduplicate against the slow scoreboard update later
		PVPSound._FastKillTimestamp = GetTime()
		
		PVPSound:HandleKillingBlowInternal("PARTY_KILL")
	end
end
function PVPSound:KillsOnUpdate(elapsed)
	if PS_EnableAddon == false then return end

	local inInst, instType = IsInInstance()
	if not (inInst and (instType == "pvp" or instType == "arena")) then
		PVPSound._ScoreInInstance = nil
		return
	end
	PVPSound._ScoreInInstance = true

	-- Reset tracking on instance/map changes (prevents stale deltas when queueing/porting).
	local mapID = (C_Map and C_Map.GetBestMapForUnit) and C_Map.GetBestMapForUnit("player") or nil
	if PVPSound._ScoreLastMapID ~= mapID or PVPSound._ScoreLastInstType ~= instType then
		PVPSound._ScoreLastMapID = mapID
		PVPSound._ScoreLastInstType = instType
		PVPSound:ResetScoreTracking()
	end

	PVPSound_ScoreRequestElapsed = PVPSound_ScoreRequestElapsed + elapsed
	if PVPSound_ScoreRequestElapsed < 0.5 then
		return
	end
	PVPSound_ScoreRequestElapsed = 0

	if type(RequestBattlefieldScoreData) == "function" then
		pcall(RequestBattlefieldScoreData)
	end

	-- Without UPDATE_BATTLEFIELD_SCORE events (12.0 restrictions), we compute deltas by polling.
	PVPSound:HandleScoreUpdate()
end

function PVPSound:GetMyScoreInfo()
	local my = UnitGUID("player")
	if not my then return nil end

	-- Preferred 12.0+ helper (if present)
	if C_PvP and C_PvP.GetScoreInfoByPlayerGuid then
		local ok, info = pcall(C_PvP.GetScoreInfoByPlayerGuid, my)
		if ok and type(info) == "table" then
			return info
		end
	end

	-- Fallback: iterate scores
	if C_PvP and C_PvP.GetScoreInfo and GetNumBattlefieldScores then
		local n = GetNumBattlefieldScores()
		for i = 1, n do
			local info = C_PvP.GetScoreInfo(i)
			if info and info.guid == my then
				return info
			end
		end
	end

	return nil
end

function PVPSound:HandleScoreUpdate()
	local inInst, instType = IsInInstance()
	if not (inInst and (instType == "pvp" or instType == "arena")) then
		return
	end

	local info = PVPSound:GetMyScoreInfo()
	if not info then return end

	local kb = info.killingBlows or 0
	local deaths = info.deaths or 0

	if PVPSound._LastKB == nil then
		PVPSound._LastKB = kb
		PVPSound._LastDeaths = deaths
		return
	end

	local deltaKB = kb - (PVPSound._LastKB or 0)
	PVPSound._LastKB = kb
	PVPSound._LastDeaths = deaths

	if deltaKB and deltaKB > 0 then
		-- DEDUPLICATION:
		local now = GetTime()
		if PVPSound._FastKillTimestamp and (now - PVPSound._FastKillTimestamp) < 3.0 then
			if PS_Debug then PVPSound:Debug("SCORE_DELTA: Ignored duplicate (Fast Path handled it)") end
			deltaKB = deltaKB - 1
			PVPSound._FastKillTimestamp = 0 
		end

		if deltaKB > 0 then
			if PS_Debug == true then
				PVPSound:Debug("SCORE_DELTA killingBlows +"..tostring(deltaKB).." total="..tostring(kb).." deaths="..tostring(deaths))
			end
			for _ = 1, deltaKB do
				PVPSound:HandleKillingBlowInternal("SCORE")
			end
		end
	end
end
function PVPSound:HandleKillingBlowInternal(source)
	-- Minimal, safe killing-blow pipeline for 12.0 BG/Arena scoreboard deltas
	-- NOTE: We do not have reliable victim identity here (12.0 secret-value restrictions),
	-- so PaybackKill identity-based features are intentionally skipped.
	local t = GetTime()

	local KillSoundLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."KillDurations")
	local maxKillRank = KillSoundLengthTable and table.getn(KillSoundLengthTable) or 10

	-- First kill or after long reset
	if LastKill == nil or (t - LastKill) > ResetTime or TimerReset == true then
		CurrentStreak = 1
		MultiKills = 1
		PVPSound:TriggerKill("Kill", CurrentStreak)
		LastKill = t
		TimerReset = false
		return
	end

	-- Streak rank (within KillTime)
	if (t - LastKill) <= PS.KillTime then
		CurrentStreak = (CurrentStreak or 1) + (1 / RankStep)
		if CurrentStreak > maxKillRank then
			CurrentStreak = maxKillRank
		end
		CurrentStreak = floor(CurrentStreak + 0.5)
	else
		CurrentStreak = 1
	end

	PVPSound:TriggerKill("Kill", CurrentStreak)

	-- Multi-kill (within MultiKillTime)
	if PS_MultiKillSound == true then
		if (t - LastKill) <= MultiKillTime then
			MultiKills = (MultiKills or 1) + 1

			local MultiKillSoundLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."MultiKillDurations")
			local maxMultiRank = MultiKillSoundLengthTable and table.getn(MultiKillSoundLengthTable) or 5

			local rank = MultiKills - 1
			if rank > maxMultiRank then rank = maxMultiRank end

			if rank >= 1 then
				PVPSound:TriggerKill("MultiKill", rank)
			end
		else
			MultiKills = 1
		end
	end

	LastKill = t
end

function PVPSound:DumpCurrentPOIs()
	if not (C_Map and C_Map.GetBestMapForUnit and C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap and C_AreaPoiInfo.GetAreaPOIInfo) then
		print("PVPSound: POI APIs not available")
		return
	end

	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then
		print("PVPSound: mapID unavailable")
		return
	end

	local ids = C_AreaPoiInfo.GetAreaPOIForMap(mapID)
	if not ids then
		print("PVPSound: no POIs for map "..tostring(mapID))
		return
	end

	print("PVPSound: POIs for map "..tostring(mapID).." ("..tostring(#ids)..")")
	for _, id in ipairs(ids) do
		local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
		local name = info and info.name or ""
		local atlas = info and info.atlasName or ""
		local tex = info and info.textureIndex or ""
		print("  POI "..tostring(id).." name="..tostring(name).." atlas="..tostring(atlas).." textureIndex="..tostring(tex))
	end

	-- If a module for this map exists and exposes DumpPOIs(), call it too
	if PVPSound.API and PVPSound.API.modules and PVPSound.API.modules[mapID] and PVPSound.API.modules[mapID].DumpPOIs then
		PVPSound.API.modules[mapID]:DumpPOIs()
	end
end

function PVPSound:LoadDeathShare()
	if PS_EnableAddon == true and (PS_DeathMessage == true or PS_DataShare ==true) then
		if not PVPSoundFrameData then
			PVPSoundFrameData = CreateFrame("Frame", nil)
		end
		PVPSoundFrameData:RegisterEvent("PLAYER_DEAD")
		PVPSoundFrameData:SetScript("OnEvent", PVPSound.OnEventData)
		PVPSound:Debug("!DeathShare Events Loaded")
	end
end

function PVPSound:UnloadDeathShare()
	if PVPSoundFrameData then
		if (PS_DeathMessage == false and PS_DataShare ==false) or  PS_EnableAddon == false then
			PVPSoundFrameData:UnregisterEvent("PLAYER_DEAD")
			PVPSound:Debug("!DeathShare Events Unloaded")
		end
	end
end

function PVPSound:RegisterEvents()
	PVPSound:LoadBG()
	PVPSound:LoadExecute()
	PVPSound:LoadKills()
	PVPSound:LoadDeathShare()
	PVPSound:Debug("!All Events Loaded")
end

function PVPSound:UnregisterEvents()
	PVPSound:UnloadBG()
	PVPSound:UnloadExecute()
	PVPSound:UnloadKills()
	PVPSound:UnloadDeathShare()
	PVPSound:Debug("!All Events Unloaded")
end

-- Killing Settings
function PVPSound:KillingSettings()
	TimerReset = false						-- Resets every timer and counter
	ResetTime = 1800						-- Automatically resets everything when no kills made in 30 minutes
	MultiKillTime = 16						-- If you get the Multi Kills in 16 sec difference you gain a Multi Kill rank, else resets
	RankStep = 1							-- How many kills need for the next rank after the First Blood
	PS.KillTime = 60						-- If you get the Kills in 60 sec difference you gain a rank, else just replays your last rank and rank gaining continuing from that rank
	PS.PaybackKillTime = 90					-- The time you can revenge the players they killed you, or the players can revenge you whom you killed
	PS.RecentlyKilledTime = 1.500			-- The time in you cant gain more then one kill on the same target
	PS.RecentlyPaybackTime = 1.500			-- The time in you cant gain more then one payback and retribution kill
end

-- Default Settings
function PVPSound:DefaultSettings()
	if PS_EnableAddon == nil then
		PS_EnableAddon = true
	end
	if PS_AddonLanguage == nil then
		PS_AddonLanguage = "English"
		PVPSound:English()
	end
	if PS_Mode == nil then
		PS_Mode = "PVP"
	end
	if PS_Emote == nil then
		PS_Emote = true
	end
	if PS_EmoteMode == nil then
		PS_EmoteMode = true
	end
	if PS_DeathMessage == nil then
		PS_DeathMessage = true
	end
	if PS_KillSound == nil then
		PS_KillSound = true
	end
	if PS_MultiKillSound == nil then
		PS_MultiKillSound = true
	end
	if PS_PetKill == nil then
		PS_PetKill = true
	end
	if PS_PaybackSound == nil then
		PS_PaybackSound = true
	end
	if PS_BattlegroundSound == nil then
		PS_BattlegroundSound = true
	end
	if PS_SoundEffect == nil then
		PS_SoundEffect = true
	end
	if PS_KillSoundEngine == nil then
		PS_KillSoundEngine = true
	end
	if PS_Debug == nil then
		PS_Debug = false
	end
	if PS_PoiDebug == nil then
		PS_PoiDebug = false
	end
	debug = PS_Debug

	if PS_BattlegroundSoundEngine == nil then
		PS_BattlegroundSoundEngine = true
	end
	if PS_DataShare == nil then
		PS_DataShare = true
	end
	if PS_KillSct == nil then
		PS_KillSct = true
	end
	if PS_MultiKillSct == nil then
		PS_MultiKillSct = true
	end
	if PS_PaybackSct == nil then
		PS_PaybackSct = true
	end
	if PS_SctEngine == nil then
		PS_SctEngine = true
	end
	if PS_ShowKillTextWithName == nil then
		PS_ShowKillTextWithName = true
	end
	-- Intended name
	if PSSctFrame == nil then
		if MikSBT then
			PSSctFrame = "Notification"
		elseif Parrot then
			PSSctFrame = "Notification"
		elseif SCT then
			PSSctFrame = "Frame 1"
		elseif xCT then
			PSSctFrame = "Frame 3"
		elseif xCT_Plus then
			PSSctFrame = "General"
		end
	end
	if PSSctFrame == nil then
		PSSctFrame = "RaidWarning"
	end
	if PS_HideServerName == nil then
		PS_HideServerName = true
	end
	if PS_Channel == nil then
		PS_Channel = "Master"
	end
	if PS_KillSoundPackName == nil then
		PS_KillSoundPackName = "UnrealTournament3"
	end
	if PS_KillSoundPackLanguage == nil then
		PS_KillSoundPackLanguage = "Eng"
	end
	if PS_SoundPackName == nil then
		PS_SoundPackName = "UnrealTournament3"
	end
	if PS_SoundPackLanguage == nil then
		PS_SoundPackLanguage = "Eng"
	end
	-- Data Share Register
	if PS_DataShare == true then
		C_ChatInfo.RegisterAddonMessagePrefix("PVPSound")
	end
	--finish him/her sounds
	if PS_Execute == nil then
		PS_Execute = false
	end
end

function PVPSound:SetAddonLanguage()
	if PS_AddonLanguage == "English" then
		PVPSound:English()
	elseif PS_AddonLanguage == "German" then
		PVPSound:German()
	elseif PS_AddonLanguage == "Spanish" then
		PVPSound:Spanish()
	elseif PS_AddonLanguage == "LatinAmericanSpanish" then
		PVPSound:LatinAmericanSpanish()
	elseif PS_AddonLanguage == "French" then
		PVPSound:French()
	elseif PS_AddonLanguage == "Italian" then
		PVPSound:Italian()
	elseif PS_AddonLanguage == "Korean" then
		PVPSound:Korean()
	elseif PS_AddonLanguage == "Portuguese" then
		PVPSound:Portuguese()
	elseif PS_AddonLanguage == "Russian" then
		PVPSound:Russian()
	elseif PS_AddonLanguage == "SimplifiedChinese" then
		PVPSound:SimplifiedChinese()
	elseif PS_AddonLanguage == "TraditionalChinese" then
		PVPSound:TraditionalChinese()
	end
end

-- resetting queries
function PVPSound:TimerReset()
	TimerReset = true
end
function PVPSound:KillersReset()
	KilledMe = nil
	KilledBy = nil
end

-- Addon error messages function
function PVPSound:Error(msg)
	if type(msg) ~= "string" then
		msg = tostring(msg)
	end
	print("|cFFf44336PVPSound ERROR:|r |cFF1688f1"..msg.."|r")
end

-- Addon debug messages function on/off switcher
local debug = false
-- Switch debug
function PVPSound:SwitchDebug()
	PS_Debug = not PS_Debug
	debug = PS_Debug
	return debug
end

function PVPSound:SwitchPoiDebug()
	PS_PoiDebug = not PS_PoiDebug
	return PS_PoiDebug
end
-- Addon debug messages function
function PVPSound:Debug(msg)
	if debug == true then
		if type(msg) ~= "string" then
			msg = tostring(msg)
		end
		print("|cFFff9a00PVPSound Debug:|r |cFF7FFF00"..msg.."|r")
	end
end

-- Addon metadata compatibility (WoW 12.0 / The War Within)
function PVPSound:GetAddonMetadata(field)
	if not field then return "" end

	-- Retail 12.0+ uses C_AddOns
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		local ok, val = pcall(C_AddOns.GetAddOnMetadata, "PVPSound", field)
		if ok and val ~= nil then
			return val
		end
	end

	-- Fallback for older clients / Classic
	if GetAddOnMetadata then
		local ok, val = pcall(GetAddOnMetadata, "PVPSound", field)
		if ok and val ~= nil then
			return val
		end
	end

	return ""
end


--addon performanse info dump
function PVPSound:perfDump()
	PVPSound:Debug(addon)
	UpdateAddOnMemoryUsage()
	UpdateAddOnCPUUsage()
	local mem = GetAddOnMemoryUsage(addon)
	local cpu = GetAddOnCPUUsage(addon)
	print("current memory usege: ", mem)
	print("current CPU usege: ", cpu)
end

-- configuration info dump
function PVPSound:ConfigDump()
		print("Addon cofig:")
		print("Retail: ", PS.isRetail)
		print("Addon language: ", PS_AddonLanguage)
		print("Kill soundpack name: ", PS_KillSoundPackName)
		print("Kill soundpack language: ", PS_KillSoundPackLanguage)
		print("Soundpack name: ", PS_SoundPackName)
		print("Soundpack language: ", PS_SoundPackLanguage)
		print("Mode: ", PS_Mode)
		print("Emote: ",PS_Emote)
		print("Emote mode: ",PS_EmoteMode)
		print("Death message: ",PS_DeathMessage)
		print("Kill sounds: ",PS_KillSound)
		print("MultiKill Sound: ", PS_MultiKillSound)
		print("PetKill: ", PS_PetKill)
		print("PaybackSound: ", PS_PaybackSound)
		print("BattlegroundSound: ", PS_BattlegroundSound)
		print("SoundEffect: ", PS_SoundEffect)
		print("KillSoundEngine: ", PS_KillSoundEngine)
		print("BattlegroundSoundEngine: ", PS_BattlegroundSoundEngine)
		print("Datashare: ", PS_DataShare)
		print("Kill SCT: ", PS_KillSct)
		print("MultiKill SCT: ", PS_MultiKillSct)
		print("Payback SCT: ", PS_PaybackSct)
		print("SCT engine: ", PS_SctEngine)
		print("SCT Frame: ", PSSctFrame)
		print("Hide server name: ", PS_HideServerName)
		print("Sound channel name: ", PS_Channel)
		print("Finishing sounds: ", PS_Execute)
		print("Reset time: ",ResetTime)
		print("Multikill time: ",MultiKillTime)
		print("Payback time: ",PS.PaybackKillTime)
		print("Recently killed penalty time: ",PS.RecentlyKilledTime)
		print("Recently payback penalty time: ",PS.RecentlyPaybackTime)
		print("Rank step for kills: ", RankStep)
		print("Debug output trigger: ", debug)
end

-- Table and functions for execute sounds
local TargetHealthObjectives = {Percent = nil}

local function TargetHealthGetObjective(healthPercent)
	if healthPercent then
		return "Percent"
	else
		return false
	end
end

local function TargetHealthState(healthPercent)
	if healthPercent then
		if healthPercent >= 0.2 then
			return 1
		elseif healthPercent < 0.2 and UnitIsDeadOrGhost("target") ~= 1 then
			return 2
		else
			return false
		end
	end
end

function PVPSound:OnEvent(event, ...)
	if event == "ADDON_LOADED" then
		local Addon = ...
		if Addon == "PVPSound" then
			PVPSound:KillingSettings()
			PVPSound:DefaultSettings()
			PVPSound:SetAddonLanguage()
			-- SoundPack Settings
			if PS_KillSoundPackName == "DevilMayCry" then
				PS.KillSoundPackDirectory = "Interface\\Addons\\PVPSound\\Sounds\\"..PS_KillSoundPackName
			elseif PS_KillSoundPackName == "Dota2" then
				PS.KillSoundPackDirectory = "Interface\\Addons\\PVPSound\\Sounds\\"..PS_KillSoundPackName
			elseif PS_KillSoundPackName == "Halo4" then
				PS.KillSoundPackDirectory = "Interface\\Addons\\PVPSound\\Sounds\\"..PS_KillSoundPackName
			elseif PS_KillSoundPackName == "UnrealTournament3" then
				PS.KillSoundPackDirectory = "Interface\\Addons\\PVPSound\\Sounds\\"..PS_KillSoundPackName
			elseif PS_KillSoundPackName == "Custom" then
				PS.KillSoundPackDirectory = "Interface\\Addons\\PVPSound_CustomSoundPack\\Sounds\\"..PS_KillSoundPackName
			end
			if PS_SoundPackName == "UnrealTournament3" then
				PS.SoundPackDirectory = "Interface\\Addons\\PVPSound\\Sounds\\"..PS_SoundPackName
			elseif PS_SoundPackName == "Custom" then
				PS.SoundPackDirectory = "Interface\\Addons\\PVPSound_CustomSoundPack\\Sounds\\"..PS_SoundPackName
			end
			PS.KillSoundPack = PS_KillSoundPackName..""..PS_KillSoundPackLanguage
			PS.SoundPack = PS_SoundPackName..""..PS_SoundPackLanguage
			if PS_EnableAddon == true then
				PVPSound:RegisterEvents()
			end
			PVPSoundOptions:OptionsAddonIsLoaded()
			-- Addon loaded message
			-- print("|cFF50C0FFPVPSound |cFFFFA500"..GetAddOnMetadata("PVPSound", "Version").."|cFF50C0FF loaded.|r")
		end
	end
end
PVPSoundFrame:SetScript("OnEvent", PVPSound.OnEvent)

function PVPSound:OnEventBG(event, ...)
	if PS_EnableAddon == true then
		--------------------------------------
		-- modules loading routine
		-- each module must have 2 functions
		-- initialize and unload
		-- these funcs called from event handler of PVPSound frame
		-- each time ZONE_CHANGED_NEW_AREA or PLAYER_ENTERING_WORLD fires
		-- unload function of each "loaded" (loaded parameter setted to true in initialize function) module should be called
		-- it needed to release all events and resourses before initializing new module, and to avoid conflicts like
		-- calling unload function of module right after calling intialize function (such problem occures when unload function called on
		-- ZONE_CHANGED_NEW_AREA event on API frame and init function called on ZONE_CHANGED_NEW_AREA event in PVPSound frame)
		-- If module don,t have initialize function, it will not be loaded
		-- If module don't have unload function, all events of API frame will automaticlly be unregistered
		-- Also, on each ZONE_CHANGED_NEW_AREA or PLAYER_ENTERING_WORLD event, if module is existed for new zone, PVPSound timer and killing qoueues will be resetted
		--------------------------------------
		if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
			-- on initial login (and when you use portals or smth like this) both events fired, but PLAYER_ENTERING_WORLD fires with wrong zone id (id of parent map)
			-- on TP using both events fired, but PLAYER_ENTERING_WORLD fires with wrong zone id (id of parent map)
			-- on /reload fires only PLAYER_ENTERING_WORLD, but with correct zone id

			-- instance id can be used for BGs, but then, we can't use this code open world battlefields as is
			CurrentZoneId = C_Map.GetBestMapForUnit("player")
			InstanceType = (select(2, IsInInstance())) -- check it to aviod uncorrect returm value of GetBestMapForUnit after PLAYER_ENTERING_WORLD event
			CurrentInstId = (select(8, GetInstanceInfo()))
			-- Player's Gender
			if UnitSex("player") == 2 then
				MyGender = "Male"
			elseif UnitSex("player") == 3 then
				MyGender = "Female"
			end
			PS.PaybackKillTime = 90

			PVPSound.API:UnloadModules(CurrentZoneId, InstanceType, CurrentInstId)

			PVPSound.API:LoadModules(CurrentZoneId, InstanceType, CurrentInstId)
		end
	end
end

function PVPSound:OnEventData(event, ...)
	if PS_EnableAddon == true then
		if event == "PLAYER_DEAD" then
			local Channel = "INSTANCE_CHAT"

			-- Death Data Share
			if KilledBy ~= nil then
				if PS_DataShare == true then
					if CurrentStreak ~= nil then
						local KillSoundLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."KillDurations")
						local Message
						if CurrentStreak <= table.getn(KillSoundLengthTable) then
							Message = KillSoundLengthTable[CurrentStreak].name
						else
							Message = KillSoundLengthTable[table.getn(KillSoundLengthTable)].name
						end
						if string.find(KilledBy, "!") then
							GotKilledBy = string.sub(KilledBy, 1, string.len(KilledBy) - 1)
						else
							GotKilledBy = tostring(KilledBy)
						end
						if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then --channel choose
							if InstanceType == "pvp" or InstanceType == "arena" or InstanceType == "raid" or InstanceType == "party" or InstanceType == nil then
								C_ChatInfo.SendAddonMessage("PVPSound", Message..":"..GotKilledBy, Channel)
							end
						else
							C_ChatInfo.SendAddonMessage("PVPSound", Message..":"..GotKilledBy, "RAID")
						end
					end
				end
				-- Death Messages
				if PS_DeathMessage == true then
					if string.sub(KilledBy, - 1) == "!" then
						GotKilledBy = string.sub(KilledBy, 1, string.len(KilledBy) - 1)
					else
						if string.find(KilledBy, "-") and PS_HideServerName ~= false then
							GotKilledBy = tostring(string.match(KilledBy, "(.+)-"))
							if string.find(GotKilledBy, "-") then
								GotKilledBy = tostring(string.match(GotKilledBy, "(.+)-"))
							end
						else
							GotKilledBy = tostring(KilledBy)
						end
					end
					if GotKilledBy ~= nil then
						print("|cFFFF4500"..L["You got killed by"].." "..GotKilledBy.."!|r")
					end
					GotKilledBy = nil
				end
				KilledBy = nil
			end
			TimerReset = true
		end
	end
end

function PVPSound:OnEventExecute(event, ...)
	if PS_EnableAddon == true  then
		--execute sounds can not be places in ideology of kill or bg sounds
		--because it is more about an dueling announcement
		--so it can not be placed in any sound engine queues
		--so i just play the sound file without a queues

		if (event == "PLAYER_TARGET_CHANGED" or event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and PS_Execute == true then
			local isEnemy = UnitIsEnemy("target","player")

			if UnitExists("target") and isEnemy == true and UnitIsDeadOrGhost("target") == false then

				local TargetGender
				if UnitSex("target") == 1 then
					TargetGender = "Unknown"
				elseif UnitSex("target") == 2 then
					TargetGender = "Male"
				elseif UnitSex("target") == 3 then
					TargetGender = "Female"
				end
				local TargetHealthPercent = UnitHealth("target") / UnitHealthMax("target")
				if PS_Mode == "PVP" then
					if UnitIsPlayer("target") == true then
						local type = TargetHealthGetObjective(TargetHealthPercent)
						if type then
							if TargetHealthState(TargetHealthObjectives[type]) == 1 and TargetHealthState(TargetHealthPercent) == 2 then
								if TargetGender == "Male" or TargetGender == "Unknown" then
									--PVPSound:AddKillToQueue("Execute", PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\Execute\\FinishHim.mp3")
									PlaySoundFile("Interface\\Addons\\PVPSound\\Sounds\\MortalKombat\\Eng\\Execute\\FinishHim.mp3", PS_Channel)
								elseif TargetGender == "Female" then
									--PVPSound:AddKillToQueue("Execute", PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\Execute\\FinishHer.mp3")
									PlaySoundFile("Interface\\Addons\\PVPSound\\Sounds\\MortalKombat\\Eng\\Execute\\FinishHer.mp3", PS_Channel)
								end
							end
							TargetHealthObjectives[type] = TargetHealthPercent
						end
					end
				elseif PS_Mode == "PVE" then
					if UnitIsPlayer("target") == false then
						local type = TargetHealthGetObjective(TargetHealthPercent)
						if type then
							if TargetHealthState(TargetHealthObjectives[type]) == 1 and TargetHealthState(TargetHealthPercent) == 2 then
								if TargetGender == "Male" or TargetGender == "Unknown" then
									--PVPSound:AddKillToQueue("Execute", PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\Execute\\FinishHim.mp3")
									PlaySoundFile("Interface\\Addons\\PVPSound\\Sounds\\MortalKombat\\Eng\\Execute\\FinishHim.mp3", PS_Channel)
								elseif TargetGender == "Female" then
									--PVPSound:AddKillToQueue("Execute", PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\Execute\\FinishHer.mp3")
									PlaySoundFile("Interface\\Addons\\PVPSound\\Sounds\\MortalKombat\\Eng\\Execute\\FinishHer.mp3", PS_Channel)
								end
							end
							TargetHealthObjectives[type] = TargetHealthPercent
						end
					end
				elseif PS_Mode == "PVPandPVE" then
					local type = TargetHealthGetObjective(TargetHealthPercent)
					if type then
						if TargetHealthState(TargetHealthObjectives[type]) == 1 and TargetHealthState(TargetHealthPercent) == 2 then
							if TargetGender == "Male" or TargetGender == "Unknown" then
								--PVPSound:AddKillToQueue("Execute", PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\Execute\\FinishHim.mp3")
								PlaySoundFile("Interface\\Addons\\PVPSound\\Sounds\\MortalKombat\\Eng\\Execute\\FinishHim.mp3", PS_Channel)
							elseif TargetGender == "Female" then
								--PVPSound:AddKillToQueue("Execute", PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\Execute\\FinishHer.mp3")
								PlaySoundFile("Interface\\Addons\\PVPSound\\Sounds\\MortalKombat\\Eng\\Execute\\FinishHer.mp3", PS_Channel)
							end
						end
						TargetHealthObjectives[type] = TargetHealthPercent
					end
				end
			end
		end
	end
end

local PS_COMBATLOG_FILTER_MY_PETS					= bit.bor(COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_REACTION_FRIENDLY, COMBATLOG_OBJECT_CONTROL_PLAYER, COMBATLOG_OBJECT_TYPE_OBJECT, COMBATLOG_OBJECT_TYPE_GUARDIAN, COMBATLOG_OBJECT_TYPE_PET)
local PS_COMBATLOG_FILTER_ENEMY_NPCS				= bit.bor(COMBATLOG_OBJECT_AFFILIATION_MASK, COMBATLOG_OBJECT_REACTION_MASK, COMBATLOG_OBJECT_CONTROL_NPC, COMBATLOG_OBJECT_TYPE_NPC)
local PS_COMBATLOG_FILTER_ENEMY_PLAYERS				= bit.bor(COMBATLOG_OBJECT_AFFILIATION_MASK, COMBATLOG_OBJECT_REACTION_MASK, COMBATLOG_OBJECT_CONTROL_PLAYER, COMBATLOG_OBJECT_TYPE_PLAYER)
local PS_COMBATLOG_FILTER_ENEMY_PLAYERS_AND_NPCS	= bit.bor(COMBATLOG_OBJECT_AFFILIATION_MASK, COMBATLOG_OBJECT_REACTION_MASK, COMBATLOG_OBJECT_CONTROL_PLAYER, COMBATLOG_OBJECT_TYPE_PLAYER, COMBATLOG_OBJECT_CONTROL_NPC, COMBATLOG_OBJECT_TYPE_NPC)

function PVPSound:OnEventKills(event, ...)

	-- 12.0+: PARTY_KILL args can be "secret values" (restricted comparisons).
	-- In BG/Arena, we rely on scoreboard deltas for personal killing blows.
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		PVPSound:ResetScoreTracking()
		return
	elseif event == "UPDATE_BATTLEFIELD_SCORE" then
		PVPSound:HandleScoreUpdate()
		return
	elseif event == "PARTY_KILL" then
		PVPSound:HandlePartyKill(...)
		return
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local inInst, instType = IsInInstance()
		if inInst and (instType == "pvp" or instType == "arena") then
			-- Ignore CLEU inside PvP instances in 12.0 to avoid secret-value payload issues.
			return
		end
	end
	if PS_EnableAddon == true then
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then --no longer have payload
			local _, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, swingOverkill, spellOverkill
			_, eventType, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, _, swingOverkill, _, _, spellOverkill = CombatLogGetCurrentEventInfo()

			-- To an Enemy
			if destName and not CombatLog_Object_IsA(destFlags, COMBATLOG_OBJECT_NONE) then
				ToEnemyPlayer = CombatLog_Object_IsA(destFlags, PS_COMBATLOG_FILTER_ENEMY_PLAYERS)
				ToEnemyNPC = CombatLog_Object_IsA(destFlags, PS_COMBATLOG_FILTER_ENEMY_NPCS)
				ToEnemyPlayerAndNPC = CombatLog_Object_IsA(destFlags, PS_COMBATLOG_FILTER_ENEMY_PLAYERS_AND_NPCS)
			end
			-- From an Enemy or from My Pets
			if sourceName and not CombatLog_Object_IsA(sourceFlags, COMBATLOG_OBJECT_NONE) then
				FromMyPets = CombatLog_Object_IsA(sourceFlags, PS_COMBATLOG_FILTER_MY_PETS)
				FromEnemyNPC = CombatLog_Object_IsA(sourceFlags, PS_COMBATLOG_FILTER_ENEMY_NPCS)
				FromEnemyPlayer = CombatLog_Object_IsA(sourceFlags, PS_COMBATLOG_FILTER_ENEMY_PLAYERS)
				FromEnemyPlayerAndNPC = CombatLog_Object_IsA(sourceFlags, PS_COMBATLOG_FILTER_ENEMY_PLAYERS_AND_NPCS)
			end
			-- PVP and PVE Mode
			if PS_Mode == "PVP" then
				ToEnemy = ToEnemyPlayer
				-- [12.0 Fix] Allow PvE/NPC kills if we are NOT in a PvP instance
				local inInst, instType = IsInInstance()
				if not (inInst and (instType == "pvp" or instType == "arena")) then
					ToEnemy = ToEnemyPlayer or ToEnemyNPC
				end
				FromEnemy = FromEnemyPlayer
			elseif PS_Mode == "PVE" then
				ToEnemy = ToEnemyNPC
				FromEnemy = FromEnemyNPC
			elseif PS_Mode == "PVPandPVE" then
				ToEnemy = ToEnemyPlayerAndNPC
				FromEnemy = FromEnemyPlayerAndNPC
			end

			--check killing source (player, mele pet or range pet)
			if (eventType == "PARTY_KILL" and sourceGUID == UnitGUID("player") and ToEnemy)
				or ((eventType == "SWING_DAMAGE" and destGUID ~= UnitGUID("player") and FromMyPets and ToEnemy and tonumber(swingOverkill) ~= nil and tonumber(swingOverkill) ~= - 1) and PS_PetKill == true)
				or (((eventType == "RANGE_DAMAGE" or eventType == "SPELL_DAMAGE" or eventType == "SPELL_PERIODIC_DAMAGE") and destGUID ~= UnitGUID("player") and FromMyPets and ToEnemy and tonumber(spellOverkill) ~= nil and tonumber(spellOverkill) ~= - 1) and PS_PetKill == true) then

				if PVPSound:CheckRecentlyKilledQueue(destGUID) ~= true then
					if PS_PaybackSound == true then
						KilledWho = destName
						PVPSound:AddToPaybackQueue(KilledWho)
					end
					-- First Killing
					if not LastKill or (GetTime() - LastKill > ResetTime) or TimerReset then
						CurrentStreak = 1
						PVPSound:TriggerKill("Kill", CurrentStreak)
						-- RetributionKilling (First Blood)
						if PS_PaybackSound == true then
							if PVPSound:CheckRetributionQueue(KilledWho) == true then
								if PVPSound:CheckRecentlyPaybackQueue("Retribution") ~= true then
									PVPSound:TriggerKill("PaybackKill", 2)
								end
								PVPSound:AddToRecentlyPaybackQueue("Retribution")
							end
						end
						-- Emotes and Fake Emotes
						if PS_Emote == true then
							local KillSoundLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."KillDurations")
							if PS_EmoteMode == true then
								if MyGender == "Male" then
									local Message = L["Streak1Male"]
									SendChatMessage(Message.." "..KillSoundLengthTable[CurrentStreak].name.."!", "EMOTE")
								elseif MyGender == "Female" then
									local Message = L["Streak1Female"]
									SendChatMessage(Message.." "..KillSoundLengthTable[CurrentStreak].name.."!", "EMOTE")
								end
							elseif PS_EmoteMode == false then
								if MyGender == "Male" then
									local Message = L["Streak1Male"]
									print("|cFFFF4500"..sourceName.." "..Message.." "..KillSoundLengthTable[CurrentStreak].name.."!".."|r")
								elseif MyGender == "Female" then
									local Message = L["Streak1Female"]
									print("|cFFFF4500"..sourceName.." "..Message.." "..KillSoundLengthTable[CurrentStreak].name.."!".."|r")
								end
							end
						end
						if PS_MultiKillSound == true then
							if not LastKill or (GetTime() - LastKill > MultiKillTime) or TimerReset then
								MultiKills = 1
							end
						end
						TimerReset = false
					 -- Killing
					elseif (GetTime() - LastKill <= ResetTime) then
						if (GetTime() - LastKill <= PS.KillTime) then --rank update condition
							FirstKill = LastKill
							if (GetTime() - FirstKill <= PS.KillTime) then
								local KillSoundLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."KillDurations")
								CurrentStreak = CurrentStreak + (1 / RankStep)

								if CurrentStreak > table.getn(KillSoundLengthTable) then
									CurrentStreak = (table.getn(KillSoundLengthTable) - 1) + (1 / RankStep)
								end
								CurrentStreak = floor(CurrentStreak + 0.5)
								if CurrentStreak <= table.getn(KillSoundLengthTable) then
									PVPSound:TriggerKill("Kill", CurrentStreak)
								end
								-- RetributionKilling (0-60sec)
								if PS_PaybackSound == true then
									if PVPSound:CheckRetributionQueue(KilledWho) == true then
										if PVPSound:CheckRecentlyPaybackQueue("Retribution") ~= true then
											PVPSound:TriggerKill("PaybackKill", 2)
										end
										PVPSound:AddToRecentlyPaybackQueue("Retribution")
									end
								end
								-- Emotes and Fake Emotes
								if PS_Emote == true then
									local KillSoundLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."KillDurations")
									if PS_EmoteMode == true then
										if CurrentStreak > 1 then
											local Message = L["Streak"..CurrentStreak]
											if CurrentStreak > 10 then
												Message = L["Streak10"]
											end
											if CurrentStreak < table.getn(KillSoundLengthTable) then
												SendChatMessage(Message.." "..KillSoundLengthTable[CurrentStreak].name.."!", "EMOTE")
											elseif CurrentStreak == table.getn(KillSoundLengthTable) then
												SendChatMessage(Message.." "..KillSoundLengthTable[CurrentStreak].name.."!!!", "EMOTE")
											else
												SendChatMessage(Message.." "..KillSoundLengthTable[table.getn(KillSoundLengthTable)].name.."!!!", "EMOTE")
											end
										end
									elseif PS_EmoteMode == false then
										if CurrentStreak > 1 then
											local Message = L["Streak"..CurrentStreak]
											if CurrentStreak > 10 then
												Message = L["Streak10"]
											end
											if CurrentStreak < table.getn(KillSoundLengthTable) then
												print("|cFFFF4500"..sourceName.." "..Message.." "..KillSoundLengthTable[CurrentStreak].name.."!".."|r")
											elseif CurrentStreak == table.getn(KillSoundLengthTable) then
												print("|cFFFF4500"..sourceName.." "..Message.." "..KillSoundLengthTable[CurrentStreak].name.."!!!".."|r")
											else
												print("|cFFFF4500"..sourceName.." "..Message.." "..KillSoundLengthTable[table.getn(KillSoundLengthTable)].name.."!!!".."|r")
											end
										end
									end
								end
								-- MultiKilling
								if PS_MultiKillSound == true then
									if (GetTime() - LastKill <= MultiKillTime) then
										FirstMultiKill = LastKill
										if (GetTime() - FirstMultiKill > MultiKillTime) then
											MultiKills = 1
										elseif (GetTime() - FirstMultiKill <= MultiKillTime) then
											if MultiKills then
												MultiKills = MultiKills + 1
												local MultiKillSoundLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."MultiKillDurations")
												if MultiKills - 1 <= table.getn(MultiKillSoundLengthTable) then
													PVPSound:TriggerKill("MultiKill", MultiKills - 1)
												else
													PVPSound:TriggerKill("MultiKill", table.getn(MultiKillSoundLengthTable))
												end
											end
										end
									end
								end
							end
						elseif (GetTime() - LastKill > PS.KillTime) then
							-- If triggers a kill after the Killing Time (60 sec) than replay the last KillSound without emote and SCT
							if PS_KillSound == true then
								if RankStep <= 1 then
									local KillSoundLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."KillDurations")
									PVPSound:AddKillToQueue("Kill", KillSoundLengthTable[CurrentStreak].dir)
									-- Create a blank table in the Sct Queue with "nil" string message
									if PS_KillSct == true or PS_MultiKillSct == true or PS_PaybackSct == true then
										local KillSoundLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."KillDurations")
										PVPSound:AddSctToQueue("Kill", KillSoundLengthTable[CurrentStreak].dir, "nil", PSSctFrame)
									end
								end
							end
							-- RetributionKilling (60-90sec)
							if (GetTime() - LastKill < PS.PaybackKillTime) then
								if PS_PaybackSound == true then
									if PVPSound:CheckRetributionQueue(KilledWho) == true then
										if PVPSound:CheckRecentlyPaybackQueue("Retribution") ~= true then
											PVPSound:TriggerKill("PaybackKill", 2)
										end
										PVPSound:AddToRecentlyPaybackQueue("Retribution")
									end
								end
							end
						end
					end
					-- Reseting MultiKilling
					if PS_MultiKillSound == true then
						if not LastKill or (GetTime() - LastKill > MultiKillTime) then
							MultiKills = 1
						end
					end
					LastKill = GetTime()
				end
				PVPSound:AddToRecentlyKilledQueue(destGUID)
			 -- PaybackKilling
			elseif (eventType == "SWING_DAMAGE" and FromEnemy and destGUID == UnitGUID("player") and tonumber(swingOverkill) ~= nil and tonumber(swingOverkill) ~= - 1) or ((eventType == "RANGE_DAMAGE" or eventType == "SPELL_DAMAGE" or eventType == "SPELL_PERIODIC_DAMAGE") and FromEnemy and destGUID == UnitGUID("player") and tonumber(spellOverkill) ~= nil and tonumber(spellOverkill) ~= - 1) then
				-- If the killer is not nil
				if sourceName ~= nil then
					-- If the killer is not the player
					if sourceName ~= UnitName("player") then
						KilledMe = sourceName
						if FromEnemyPlayer then
							KilledBy = tostring(sourceName)
						elseif FromEnemyNPC then
							KilledBy = tostring(sourceName.."!")
						else
							KilledBy = tostring(sourceName)
						end
						if PS_PaybackSound == true then
							PVPSound:AddToRetributionQueue(KilledMe)
							if PVPSound:CheckPaybackQueue(KilledMe) == true then
								if PVPSound:CheckRecentlyPaybackQueue("Payback") ~= true then
									PVPSound:TriggerKill("PaybackKill", 1)
								end
								PVPSound:AddToRecentlyPaybackQueue("Payback")
							end
						end
					end
				end
			 -- Environmental Deaths
			elseif eventType == "ENVIRONMENTAL" and destGUID == UnitGUID("player") then
				if sourceName ~= nil or sourceName == nil then
					KilledMe = nil
					KilledBy = nil
				end
			end
		end
	end
end

function PVPSound:FormatKillAnnouncementText(baseText, killType, streakNumber)
	-- Cosmetic: show the player's name alongside streak text (e.g. "Player got First Blood", "Player is Dominating")
	if baseText == nil then return baseText end
	if PS_ShowKillTextWithName ~= true then return baseText end

	local playerName = UnitName("player")
	if playerName == nil or playerName == "" then
		return baseText
	end

	-- Keep it simple and mostly language-agnostic; only add a small helper verb for the most common case.
	if killType == "Kill" then
		if streakNumber == 1 then
			return playerName .. " got " .. baseText
		else
			return playerName .. " is " .. baseText
		end
	end

	return playerName .. " " .. baseText
end

function PVPSound:TriggerKill(killType, streakNumber)
	if killType and streakNumber and streakNumber ~= 0 then
		if killType == "Kill" then
			local KillLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."KillDurations")
			if streakNumber <= table.getn(KillLengthTable) then
				-- Kills
				if PS_KillSound == true then
					--See comment in upper function in Kills->Emote section
					if (streakNumber - floor(streakNumber) > 0.5) then
						streakNumber = ceil(streakNumber)
					else
						streakNumber = floor(streakNumber)
					end
					--print(KillLengthTable[streakNumber])
					PVPSound:AddKillToQueue(killType, KillLengthTable[streakNumber].dir)
				end
				-- Sounds Effects
				if PS_SoundEffect == true then
					if streakNumber < table.getn(KillLengthTable) then
						PVPSound:AddEffectToQueue(killType, KillLengthTable[streakNumber].dir)
					elseif streakNumber == table.getn(KillLengthTable) then
						PVPSound:AddEffectToQueue("", PS.KillSoundPackDirectory.."\\"..PS_KillSoundPackLanguage.."\\Effects\\KillingMaxRank.mp3")
						PVPSound:AddEffectToQueue(killType, KillLengthTable[streakNumber].dir)
					end
				end
				-- Kill SCT
				if PS_KillSct == true or PS_MultiKillSct == true or PS_PaybackSct == true then
					PVPSound:AddSctToQueue(killType, KillLengthTable[streakNumber].dir, PVPSound:FormatKillAnnouncementText(KillLengthTable[streakNumber].name, killType, streakNumber), PSSctFrame)
				end
			end
		elseif killType == "MultiKill" then
			local MultiKillLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."MultiKillDurations")
			if streakNumber <= table.getn(MultiKillLengthTable) then
				-- Multi Kills
				if PS_MultiKillSound == true then
					PVPSound:AddKillToQueue(killType, MultiKillLengthTable[streakNumber].dir)
				end
				-- Multi Kill Sounds Effects
				if PS_SoundEffect == true then
					if streakNumber < table.getn(MultiKillLengthTable) then
						PVPSound:AddEffectToQueue(killType, MultiKillLengthTable[streakNumber].dir)
					elseif streakNumber == table.getn(MultiKillLengthTable) then
						PVPSound:AddEffectToQueue("", PS.KillSoundPackDirectory.."\\"..PS_KillSoundPackLanguage.."\\Effects\\MultiKillingMaxRank.mp3")
						PVPSound:AddEffectToQueue(killType, MultiKillLengthTable[streakNumber].dir)
					end
				end
				-- Multi Kill SCT
				if PS_KillSct == true or PS_MultiKillSct == true or PS_PaybackSct == true then
					PVPSound:AddSctToQueue(killType, MultiKillLengthTable[streakNumber].dir, PVPSound:FormatKillAnnouncementText(MultiKillLengthTable[streakNumber].name, killType, streakNumber), PSSctFrame)
				end
			end
		elseif killType == "PaybackKill" then
			local PaybackKillLengthTable = getglobal("PVPSound_"..PS.KillSoundPack.."PaybackKillDurations")
			-- Payback Kills
			if PS_PaybackSound == true then
				PVPSound:AddKillToQueue(killType, PaybackKillLengthTable[streakNumber].dir)
			end
			-- Payback Kill Sound Effects
			if PS_SoundEffect == true then
				PVPSound:AddEffectToQueue(killType, PaybackKillLengthTable[streakNumber].dir)
			end
			-- Payback Kill SCT
			if PS_KillSct == true or PS_MultiKillSct == true or PS_PaybackSct == true then
				PVPSound:AddSctToQueue(killType, PaybackKillLengthTable[streakNumber].dir, PVPSound:FormatKillAnnouncementText(PaybackKillLengthTable[streakNumber].name, killType, streakNumber), PSSctFrame)
			end
		end
	end
end

-- [FORCE PATCH: PVP STRICT MODE]
_G["PVPSound"] = PVPSound

-- 1. DISABLE STAT TRACKING (Stops PvE/Mob Kill Detection)
function PVPSound:ResetScoreTracking() end
function PVPSound:HandleScoreUpdate() end
function PVPSound:HandlePartyKill() end

-- 2. SAFE STARTUP (Polling Only - No Crashes)
function PVPSound:LoadKills()
    if not PVPSoundFrameKills then
        PVPSoundFrameKills = CreateFrame("Frame", nil)
    end
    -- Only use polling for background tasks, NOT for event registration
    if PS_EnableAddon == true then
        PVPSoundFrameKills:SetScript("OnUpdate", function(_, elapsed) PVPSound:KillsOnUpdate(elapsed) end)
    else
        PVPSoundFrameKills:SetScript("OnUpdate", nil)
    end
end

-- 3. SAFE FACTION CHECK (Fixes Secret Value Crash)
function PVPSound:GetMyScoreInfo() return nil end

-- 4. UNLOCKED COMBAT LOG LOGIC
-- This replaces the original handler. It REMOVES the code that disabled CLEU in BGs.
function PVPSound:OnEventKills(event, ...)
    if PS_EnableAddon ~= true then return end

    -- We strictly ignore Scoreboard/PartyKill events because they are Tainted or Noisy.
    -- We ONLY process the Combat Log.
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, eventType, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, _, swingOverkill, _, _, spellOverkill = CombatLogGetCurrentEventInfo()

        -- Filter Setup (Crucial for PvP Only)
        local ToEnemy = false
        local ToEnemyPlayer = CombatLog_Object_IsA(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER)
        
        -- Enforce PvP Mode Logic
        if PS_Mode == "PVP" then
            ToEnemy = ToEnemyPlayer -- STRICTLY Players Only
        elseif PS_Mode == "PVE" then
            ToEnemy = CombatLog_Object_IsA(destFlags, COMBATLOG_OBJECT_TYPE_NPC)
        else -- PVPandPVE
            ToEnemy = ToEnemyPlayer or CombatLog_Object_IsA(destFlags, COMBATLOG_OBJECT_TYPE_NPC)
        end
        
        local FromMyPets = CombatLog_Object_IsA(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) or CombatLog_Object_IsA(sourceFlags, COMBATLOG_OBJECT_TYPE_GUARDIAN)
        
        -- KILL DETECTION
        -- Check 1: Player Kill (Party Kill event inside CLEU is safe)
        if (eventType == "PARTY_KILL" and sourceGUID == UnitGUID("player") and ToEnemy)
        -- Check 2: Pet Kill
        or ((eventType == "SWING_DAMAGE" or eventType == "RANGE_DAMAGE" or eventType == "SPELL_DAMAGE") and FromMyPets and ToEnemy and (tonumber(swingOverkill) or tonumber(spellOverkill))) then
            
            -- Success! It's a valid PvP Kill.
            if PVPSound:CheckRecentlyKilledQueue(destGUID) ~= true then
                -- Trigger Sound/Text
                local currentT = GetTime()
                if not LastKill or (currentT - LastKill > ResetTime) then
                    CurrentStreak = 1
                    PVPSound:TriggerKill("Kill", CurrentStreak)
                elseif (currentT - LastKill <= PS.KillTime) then
                     CurrentStreak = (CurrentStreak or 1) + 1
                     PVPSound:TriggerKill("Kill", CurrentStreak)
                end
                LastKill = currentT
                PVPSound:AddToRecentlyKilledQueue(destGUID)
            end
        end
    end
end

-- 5. SAFE LISTENER (The "Ears")
-- Registers the Combat Log on a clean, local frame to avoid Taint Crashes.
local SafeListener = CreateFrame("Frame")
SafeListener:RegisterEvent("PLAYER_ENTERING_WORLD")
SafeListener:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Attempt to register CLEU. If blocked, it fails silently (No Crash).
        pcall(function() self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") end)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if PVPSound then PVPSound:OnEventKills(event) end
    end
end)

-- 6. VISUALS & COMMANDS
local oldDefaultSettings = PVPSound.DefaultSettings
function PVPSound:DefaultSettings()
    if oldDefaultSettings then oldDefaultSettings(self) end
    PS_Emote = true
    PS_EmoteMode = false -- Console Mode
end

SLASH_PSANNOUNCE1 = "/psannounce"
SlashCmdList["PSANNOUNCE"] = function(msg)
    local fGroup = UnitFactionGroup("player")
    if fGroup == "Alliance" then
        print("|cFF00FF00[PVPSound]|r Faction: Alliance -> Blue Team")
        PVPSound:AddToQueue(PS.SoundPackDirectory.."\\Eng\\GameStatus\\PlayYouAreOnBlue.mp3")
    else
        print("|cFF00FF00[PVPSound]|r Faction: Horde -> Red Team")
        PVPSound:AddToQueue(PS.SoundPackDirectory.."\\Eng\\GameStatus\\PlayYouAreOnRed.mp3")
    end
end
