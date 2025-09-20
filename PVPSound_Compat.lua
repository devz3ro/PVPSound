-- 11.x compatibility shims for PVPSound
-- Load very early (listed near the top of PVPSound.toc).

local select = select
local GetBuildInfo = GetBuildInfo
local WOW_PROJECT_ID = WOW_PROJECT_ID
local WOW_PROJECT_MAINLINE = WOW_PROJECT_MAINLINE

local isDragonflight11 = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and select(4, GetBuildInfo()) >= 110000

-- Capture the original global function (if present) BEFORE any global replacements.
local _Legacy_GetAddOnMetadata = _G and _G.GetAddOnMetadata or nil

-- GetAddOnMetadata was moved under C_AddOns in modern clients.
function PVPS_GetAddOnMetadata(addonName, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addonName, field)
    elseif _Legacy_GetAddOnMetadata then
        return _Legacy_GetAddOnMetadata(addonName, field) -- classic/fallback
    end
    return nil
end

-- Color Picker: OpenColorPicker(info) was removed; use SetupColorPickerAndShow in 10.2.5+ / 11.x.
local function safeCall(fn, ...)
    if type(fn) == "function" then
        return fn(...)
    end
end

function PVPS_OpenColorPicker(info)
    -- info: { r, g, b, a, hasOpacity, swatchFunc, cancelFunc, opacityFunc, previousValues, extraInfo }
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

    -- Fallback to legacy if available (Classic).
    if OpenColorPicker then
        return OpenColorPicker(info)
    end
end

-- Ensure default sound channel remains Master if unset.
if type(PS_Channel) ~= "string" or PS_Channel == "" then
    PS_Channel = "Master"
end
