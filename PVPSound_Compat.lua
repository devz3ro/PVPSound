-- 11.x compatibility shims for PVPSound (load very early)

-- Capture original global, if present (Classic).
local _Legacy_GetAddOnMetadata = _G and _G.GetAddOnMetadata or nil

-- Unified metadata accessor (11.x uses C_AddOns).
function PVPS_GetAddOnMetadata(addonName, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, field)
    elseif _Legacy_GetAddOnMetadata then
        return _Legacy_GetAddOnMetadata(addonName, field)
    end
    return nil
end

-- Color Picker wrapper (OpenColorPicker removed in 11.x).
local function safeCall(fn, ...) if type(fn) == "function" then return fn(...) end end

function PVPS_OpenColorPicker(info)
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        local r, g, b = info.r, info.g, info.b
        local a = info.opacity or info.a
        local hasOpacity = info.hasOpacity or (a ~= nil)
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            opacity = a,
            hasOpacity = hasOpacity,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local no = ColorPickerFrame.opacity
                if info.swatchFunc then
                    info.r, info.g, info.b = nr, ng, nb
                    info.opacity = no
                    safeCall(info.swatchFunc, info)
                end
            end,
            cancelFunc = function(prevR, prevG, prevB, prevA)
                if info.cancelFunc then
                    info.r, info.g, info.b = prevR, prevG, prevB
                    info.opacity = prevA
                    safeCall(info.cancelFunc, info)
                end
            end,
            opacityFunc = function()
                if info.opacityFunc then
                    safeCall(info.opacityFunc, info)
                end
            end,
            extraInfo = info.extraInfo,
        })
        return
    end
    if OpenColorPicker then
        return OpenColorPicker(info)
    end
end

-- Wrapper for battlefield flag position across API versions.
-- Retail 11.x: use C_PvP.GetBattlefieldFlagPosition(flagIndex, uiMapId)
-- Classic/older: GetBattlefieldFlagPosition(flagIndex)
if not PVPS_GetBattlefieldFlagPosition then
    function PVPS_GetBattlefieldFlagPosition(index)
        local uiMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
        if C_PvP and C_PvP.GetBattlefieldFlagPosition and uiMapId then
            local x, y, token = C_PvP.GetBattlefieldFlagPosition(index, uiMapId)
            return x, y, token
        elseif _G.GetBattlefieldFlagPosition then
            return _G.GetBattlefieldFlagPosition(index)
        end
        return nil, nil, nil
    end
end
