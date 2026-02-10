local addon, ns = ...
local PVPSound = ns.PVPSound
local PS = ns.PS

local API = {}
PVPSound.API = API

----------------------
-- Dumping module info
function API:DumpInfo()
	if self == API then
		PVPSound:Error("Module expected")
	else
		if self.name then
			print("Name: ", self.name)
		end
		if self.zoneId then
			print("Zone id: ", self.zoneId)
		end
		if self.loaded then
			print("Loaded: ", self.loaded)
		end
	end
end

-- Dump all modules with loaded state
function API:DumpModules()
	local i = 1
	for _, v in pairs(PVPSound.modules) do
		print(i, v.name, v.loaded)
		i = i + 1
	end
end

-----------------
-- Event handling

local eventMap = {}
local BGFrame = CreateFrame("Frame", "BGFrame", nil)

-- In 12.0+ some UI operations (including event registration on certain frames) can be blocked during combat lockdown.
local function PVPS_InCombatLockdown()
	return type(InCombatLockdown) == "function" and InCombatLockdown()
end

function API:_ScheduleDeferredFlush()
	if self._deferredTimer == true then return end
	self._deferredTimer = true
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(0.5, function() API:_FlushDeferred() end)
	else
		-- No timer API, try next frame via OnUpdate
		if not self._deferredOnUpdateFrame then
			local f = CreateFrame("Frame")
			f:SetScript("OnUpdate", function()
				f:SetScript("OnUpdate", nil)
				API:_FlushDeferred()
			end)
			self._deferredOnUpdateFrame = f
		end
	end
end

function API:_FlushDeferred()
	if PVPS_InCombatLockdown() then
		self._deferredTimer = false
		self:_ScheduleDeferredFlush()
		return
	end

	self._deferredTimer = false
	if not self._deferred then return end
	local pending = self._deferred
	self._deferred = nil

	-- Apply deferred registrations/unregistrations now that combat lockdown is over.
	for _, op in ipairs(pending) do
		if op.action == "reg" then
			pcall(function() BGFrame:RegisterEvent(op.event) end)
		elseif op.action == "unreg" then
			pcall(function() BGFrame:UnregisterEvent(op.event) end)
		end
	end
end


BGFrame:SetScript("OnEvent", function(frame, event, ...)
	local map = eventMap[event]
	if not map then return end
		for k, v in pairs(map) do
		-- [FIX] Crash Shield: Use pcall to survive "Secret Value" errors in 12.0
		if type(v) == "function" then
			pcall(v, event, ...)
		else
			pcall(k[v], k, event, ...)
		end
	end
end)


function API:ShowRegisteredEvents()
	for k, t in pairs(eventMap) do
		print("event: ", k)
		for k, v in pairs(t) do
			print("    module: " , k, " function: ", v)
		end
	end
end

function API:RegisterEvent(event, func)
	-- if func parameter not used, this function should be called via dot operation with module instead self
	-- func parameter should be stand alone function (not table function), because in event handler it will be called like f(event,...)
	-- and event named table function of addon will be called like f(self, event,...)
	if type(event) ~= "string" then
		PVPSound:Error("RegisterEvent: Event name should be string to register it")
		return false
	elseif (not func) and (not self[event]) then
		PVPSound:Error("RegisterEvent: module "..tostring(self).." don't have function named "..event)
		return false
	elseif func and type(func) ~= "function" then
		-- [FIX] Allow string function names (Backward Compatibility)
		if type(func) == "string" and self[func] then
			func = self[func]
		else
			-- PVPSound:Error("RegisterEvent: Function reference expected")
			return false
		end
	end

	if BGFrame then
	-- Avoid registering events during combat lockdown (can cause ADDON_ACTION_FORBIDDEN in 12.0+).
	if PVPS_InCombatLockdown() then
		API._deferred = API._deferred or {}
		table.insert(API._deferred, { action = "reg", event = event })
		API:_ScheduleDeferredFlush()
		return true
	end

		BGFrame:RegisterEvent(event)
		if not eventMap[event] then eventMap[event] = {} end
		eventMap[event][self] = func or event
		return true
	else
		PVPSound:Error("RegisterEvent: API frame not initialized")
		return false
	end
end

function API:UnregisterEvent(event)
	if BGFrame and (type(event) == "string") then
		eventMap[event] = nil
	-- Avoid unregistering events during combat lockdown (can cause UI action blocked/taint warnings).
	if PVPS_InCombatLockdown() then
		API._deferred = API._deferred or {}
		table.insert(API._deferred, { action = "unreg", event = event })
		API:_ScheduleDeferredFlush()
		-- eventMap cleanup already done below; handler is guarded against nil eventMap[event]
		return true
	end

		BGFrame:UnregisterEvent(event)
		return true
	elseif type(event) ~= "string" then
		PVPSound:Error("UnregisterEvent: Event name should be string to urregister it")
		return false
	else
		PVPSound:Error("RegisterEvent: API frame not initialized")
		return false
	end
end

function API:UnregisterAllEvents()
	if BGFrame then
		-- Avoid unregistering events during combat lockdown.
		if PVPS_InCombatLockdown() then
			API._deferred = API._deferred or {}
			for k, _ in pairs(eventMap) do
				table.insert(API._deferred, { action = "unreg", event = k })
				eventMap[k] = nil
			end
			API:_ScheduleDeferredFlush()
			return true
		end

		for k, v in pairs(eventMap) do
			BGFrame:UnregisterEvent(k)
			eventMap[k] = nil
		end
		return true
	else
		return false
	end
end

-------------------------------
-- Module registration function

-- zoneId field should be a number. It used to load module for correponding uiMapID
-- pvptype is type (pvp,arena...) and should be a string
-- name also should be a string
-- This func returns table for module
function API:RegisterMod(zoneId, pvptype, name, instId)
	local mod = {}
	mod.name = name or "default_module_name"
	if zoneId and type(zoneId) == "number" then
		mod.zoneId = zoneId
	else
		PVPSound:Error("zone id should be a number to register module "..mod.name)
		return false
	end

	if pvptype and type(pvptype) == "string" then
		mod.type = pvptype
	else
		PVPSound:Error("pvptype should be a string to register module "..mod.name)
		return false
	end

	if instId and type(zoneId) == "number" then
		mod.instId = instId
	elseif instId then
		PVPSound:Error("zinstance id should be a number to register module "..mod.name)
		return false
	else
		mod.instId = nil
	end

	-- default methods and fields
	mod.loaded = false
	function mod:Initialize()
		if not mod.loaded then
			API:Announce("BG")
		end
		mod.loaded = true
	end

	function mod:Unload()
		API:UnregisterAllEvents()
		mod.loaded = false
	end

	PVPSound.modules[zoneId] = mod
	return mod
end

-------------------------------
-- Module load/unload function

function API:LoadModules(CurrentZoneId, InstanceType, CurrentInstId)
	-- loading BG modules
	-- Some BGs starts in the zone without  areaID (for example winter AB)
	-- for such cases instance ID is used
	-- Arenas module doesn't have real zoneId field (-1), so it will be loaded only by zone type check
	local loadedAddonsCheck = false
	-- loading by zoneId
	if CurrentZoneId and PVPSound.modules[CurrentZoneId] and InstanceType == PVPSound.modules[CurrentZoneId].type and not PVPSound.modules[CurrentZoneId].loaded then
		PVPSound:Debug("common loading")
		PVPSound:TimerReset()
		PVPSound:KillersReset()
		PVPSound.modules[CurrentZoneId]:Initialize()
		PVPSound:Debug(" "..PVPSound.modules[CurrentZoneId].name.." loaded")
		loadedAddonsCheck = true
	-- loading arenas
	elseif InstanceType == "arena" then
		PVPSound.modules[-1]:Initialize()
		loadedAddonsCheck = true
	else
	-- loading by instId
		PVPSound:Debug("alternative loading")
		for _, mod in pairs(PVPSound.modules) do
			PVPSound:Debug(" try "..mod.name.." instId: "..tostring(mod.instId).." ;cur instanceId: "..(select(8, GetInstanceInfo())))
			local curName = select(1, GetInstanceInfo())
			if ((mod.instId ~= nil and mod.instId == CurrentInstId) or (curName ~= nil and mod.name ~= nil and string.lower(curName) == string.lower(mod.name))) and (mod.type == nil or mod.type == InstanceType) and not mod.loaded then
				PVPSound:TimerReset()
				PVPSound:KillersReset()
				mod:Initialize()
				PVPSound:Debug(" "..mod.name.." loaded")
				loadedAddonsCheck = true
				break
			end
		end
	end
	if loadedAddonsCheck == false then
		PVPSound:Debug(" Nothing loaded")
	end
end

function API:UnloadModules(CurrentZoneId, CurrentInstId)
	-- unloading of loaded modules (except the module for zone, where you are)
	local unloadedAddonsCheck = false
	if CurrentZoneId then
		PVPSound:Debug("common unloading")
		for _, mod in pairs(PVPSound.modules) do
			if (mod.zoneId ~= CurrentZoneId) and mod.loaded then
				mod:Unload()
				PVPSound:Debug(" "..mod.name.." unloaded")
				unloadedAddonsCheck = true
			end
		end
	else
		PVPSound:Debug("alternative unloading")
		for _, mod in pairs(PVPSound.modules) do
			if (mod.instId ~= CurrentInstId) and mod.loaded then
				mod:Unload()
				PVPSound:Debug(" "..mod.name.." unloaded")
				unloadedAddonsCheck = true
			end
		end
	end
	if unloadedAddonsCheck == false then
		PVPSound:Debug(" Nothing unloaded")
	end
end

-----------------------------------
-- BG and Arena Team announcer when BG starts
function API:Announce(zone)
	-- [FIX] Debounce: Prevent double-announcements (5 second cooldown)
	if self.LastAnnounce and (GetTime() - self.LastAnnounce < 5) then return end
	self.LastAnnounce = GetTime()

	if PS_Announce == false then return end

	-- Smart Faction Detection
	local MyFaction = nil
	local info = nil
	
	-- Try Scoreboard (Safe Call)
	if PVPSound and PVPSound.GetMyScoreInfo then
		local ok, res = pcall(function() return PVPSound:GetMyScoreInfo() end)
		if ok and res then info = res end
	end
	
	if info and info.faction then
		MyFaction = info.faction
	else
		-- Fallback to UnitFactionGroup
		local fGroup = UnitFactionGroup("player")
		if fGroup == "Alliance" then MyFaction = 1
		elseif fGroup == "Horde" then MyFaction = 0
		end
	end

	-- Debug
	-- print("|cFF00FF00[PVPSound]|r Announce: " .. tostring(zone))

	-- Queue Sound
	if zone == "BG" or zone == "Wintergrasp" or zone == "Tol Barad" or zone == "Ashran" then
		if MyFaction == 1 then
			PVPSound:AddToQueue(PS.SoundPackDirectory .. "\\" .. PS_SoundPackLanguage .. "\\GameStatus\\PlayYouAreOnBlue.mp3")
			PVPSound:AddToSct("Blue Team", "You Are On Blue Team", "KILL")
		elseif MyFaction == 0 then
			PVPSound:AddToQueue(PS.SoundPackDirectory .. "\\" .. PS_SoundPackLanguage .. "\\GameStatus\\PlayYouAreOnRed.mp3")
			PVPSound:AddToSct("Red Team", "You Are On Red Team", "KILL")
		end
	elseif zone == "Arena" then
		PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\GameStatus\\PrepareForBattle.mp3")
	end
end

-- winner announcer
-- type is BG or Arena
function API:AnnounceWinner(zone, winner)
	if zone == "BG" or zone == "Wintergrasp" or zone == "Tol Barad" or zone == "Ashran" then
		if winner == 0 then
			PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\GameStatus\\HordeWins.mp3")
		elseif winner == 1 then
			PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\GameStatus\\AllianceWins.mp3")
		else
			PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\GameStatus\\HumiliatingDefeat.mp3")
		end
		--BgIsOver = true -- don't know if we need it
		PVPSound:ClearPaybackQueue()
		PVPSound:ClearRetributionQueue()
	elseif zone == "Arena" then
		--local winner = ...
		local myFaction = GetBattlefieldArenaFaction()
		if winner == myFaction then
			PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\GameStatus\\YouHaveWonTheMatch.mp3")
		else
			PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\GameStatus\\YouHaveLostTheMatch.mp3")
		end
		--BgIsOver = true -- don't know if we need it
		PVPSound:ClearPaybackQueue()
		PVPSound:ClearRetributionQueue()
	else
		return false
	end
end


-----------------
-- Time Remaining

local TimeRemainingobjectives = {TimeRemaining = nil}

local TimerStopped = false	-- for such situations, when world Zone have timer and its timer id is the same as timer id of bg, you just leave

local function TimeRemainingget_objective(id)
	if id then
		return "TimeRemaining"
	else
		return false
	end
end

local function TimeRemainingobj_state(id)
	if id == 5 then
		return 5 -- Time Remaining: 5:59-5:00
	elseif id == 4 then
		return 4 -- Time Remaining: 4:59-4:00
	elseif id == 3 then
		return 3 -- Time Remaining: 3:59-3:00
	elseif id == 2 then
		return 2 -- Time Remaining: 2:59-2:00
	elseif id == 1 then
		return 1 -- Time Remaining: 1:59-1:00
	elseif id == 0 then
		return 0 -- Time Remaining: 0:59-0:00
	else
		return false
	end
end


function API:TimeRemaining_check(id)
	local delay = 20
	if C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo(id) and TimerStopped == false then
		local TimeRemaining = tonumber(string.match(C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo(id).text, "(%d+)"))
		local state = TimeRemainingobj_state(TimeRemaining)

		if state == false then
			TimeRemainingobjectives.TimeRemaining = TimeRemaining
			C_Timer.After(delay, function() API:TimeRemaining_check(id) end)
		else
			local type = TimeRemainingget_objective(TimeRemaining)
			if type then
				if TimeRemainingobj_state(TimeRemainingobjectives[type]) == 5 and state == 4 then
					PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\CountDown\\FiveMinutesRemain.mp3")
					TimeRemainingobjectives[type] = TimeRemaining
					C_Timer.After(delay, function() API:TimeRemaining_check(id) end)
				elseif TimeRemainingobj_state(TimeRemainingobjectives[type]) == 3 and state == 2 then
					PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\CountDown\\ThreeMinutesRemain.mp3")
					TimeRemainingobjectives[type] = TimeRemaining
					C_Timer.After(delay, function() API:TimeRemaining_check(id) end)
				elseif TimeRemainingobj_state(TimeRemainingobjectives[type]) == 2 and state == 1 then
					PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\CountDown\\TwoMinutesRemain.mp3")
					TimeRemainingobjectives[type] = TimeRemaining
					C_Timer.After(delay, function() API:TimeRemaining_check(id) end)
				elseif TimeRemainingobj_state(TimeRemainingobjectives[type]) == 1 and state == 0 then
					PVPSound:AddToQueue(PS.SoundPackDirectory.."\\"..PS_SoundPackLanguage.."\\CountDown\\OneMinutesRemain.mp3")
					TimeRemainingobjectives[type] = TimeRemaining
				else
					TimeRemainingobjectives[type] = TimeRemaining
					C_Timer.After(delay, function() API:TimeRemaining_check(id) end)
				end

			end
		end
		return true
	else
		return false
	end
end

-- stops all time remaining timers
function API:StopTimers()
	TimerStopped = true
end

-- resets time remaining timers
-- should be used before any timer initialization
function API:ResetTimers()
	TimerStopped = false
end

--------------------------
-- Objective initializator

function API:ObjInit(zoneId, objectives, get, textureMode)
	-- objectives is BG objectives
	-- get is BG objectives getter
	if (not get) or (type(get) ~= "function") then
		PVPSound:Error("Objective initialization: Getter function expected")
		return false
	end
	if objectives and (type(objectives) ~= "table") then
		PVPSound:Error("Objective initialization: objectives should be a table")
		return false
	end
	if zoneId and (type(zoneId) ~= "number") then
		PVPSound:Error("Objective initialization: zone id should be a number")
		return false
	end

	local POIs = C_AreaPoiInfo.GetAreaPOIForMap(zoneId)
	local objective

	--reset all objectives
	for k, v in pairs(objectives) do
		objectives[k] = nil
	end

	for i = 1, #POIs do
	--if texturemod parameter exists, then check textures, else check POI id
	--textureMode = 1 - in case, where objective get and state methods operate with textureID (Arathi basin)
	--textureMode = 2 - in case, where objective get method operates with POI and it's state method operates with textureID (TBFG)
		if textureMode and textureMode == 1 then
			if (C_AreaPoiInfo.GetAreaPOIInfo(zoneId,POIs[i])) then
				objective = get(C_AreaPoiInfo.GetAreaPOIInfo(zoneId,POIs[i]).textureIndex)
			end
		else
			objective = get(POIs[i])
		end

		if objective then
			if textureMode and (textureMode == 1 or textureMode == 2) then
				if (C_AreaPoiInfo.GetAreaPOIInfo(zoneId,POIs[i])) then
					objectives[objective] = C_AreaPoiInfo.GetAreaPOIInfo(zoneId,POIs[i]).textureIndex
				end
			else
				objectives[objective] = POIs[i]
			end
		end
	end
end