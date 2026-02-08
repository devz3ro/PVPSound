local addon, ns = ...
local PVPSound = ns.PVPSound
local PS = ns.PS

local API = PVPSound.API

-- Deephaul Ravine (The War Within)
-- UIMapID: 2345
-- InstanceID: 2656
local mod = API:RegisterMod(2345, "pvp", "Deephaul Ravine", 2656)

local function DumpPOIs()
	if not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOIForMap or not C_AreaPoiInfo.GetAreaPOIInfo then
		PVPSound:Debug("Deephaul: C_AreaPoiInfo API not available")
		return
	end

	local ids = C_AreaPoiInfo.GetAreaPOIForMap(mod.zoneId)
	if not ids then
		PVPSound:Debug("Deephaul: no POIs returned for map "..tostring(mod.zoneId))
		return
	end

	PVPSound:Debug("Deephaul: POIs for map "..tostring(mod.zoneId).." ("..tostring(#ids)..")")
	for _, id in ipairs(ids) do
		local info = C_AreaPoiInfo.GetAreaPOIInfo(mod.zoneId, id)
		local name = info and info.name or ""
		local atlas = info and info.atlasName or ""
		local tex = info and info.textureIndex or ""
		PVPSound:Debug("  POI "..tostring(id).." name="..tostring(name).." atlas="..tostring(atlas).." textureIndex="..tostring(tex))
	end
end

function mod:Initialize()
	API.RegisterEvent(self, "AREA_POIS_UPDATED")

	if not self.loaded then
		API:Announce("BG")
	end

	self.loaded = true

	if PS_PoiDebug == true then
		DumpPOIs()
	end
end

function mod:Unload()
	API:UnregisterAllEvents()
	self.loaded = false
end

function mod:AREA_POIS_UPDATED()
	if PS_PoiDebug == true then
		DumpPOIs()
	end
end

-- Expose helper for slash command dump
function mod:DumpPOIs()
	DumpPOIs()
end
