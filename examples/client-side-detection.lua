--[[
    PUBG Mobile - Client-Side Detection Examples
    
    This file contains examples of the client-side detection code
    extracted from the game's Lua scripts.
    
    ⚠️ WARNING: This is for EDUCATIONAL PURPOSES ONLY
    Do not use this code to bypass security measures.
]]

-- ============================================================================
-- VPN Detection
-- ============================================================================

function IsVPNConnected()
    -- Check cloud gaming VPN first
    local isCloudVPN = logic_cloud_game:IsClientVPNConnected()
    if isCloudVPN then
        return true
    end
    
    -- Check system VPN
    local isSystemVPN = Client.IsSystemVPNOpened()
    return isSystemVPN
end

-- ============================================================================
-- Timezone Detection
-- ============================================================================

function GetSysTimeZone()
    -- Try cloud gaming timezone first
    local tzName = logic_cloud_game:GetClientTimeZone()
    
    -- Fallback to system timezone
    if tzName == "" or tzName == nil then
        tzName = Client.GetTimezoneName()
    end
    
    -- Convert to lowercase for comparison
    return string.lower(tzName)
end

function CheckForbiddenTimezone(tzName)
    -- Forbidden timezones (Base64 decoded list)
    local forbiddenTimezones = {
        "asia/shanghai",
        "asia/chongqing",
        "asia/chunkking",
        "asia/harbin",
        "asia/kashgar",
        "asia/urumqi",
        "prc"
    }
    
    -- Check if timezone is in forbidden list
    for _, forbidden in ipairs(forbiddenTimezones) do
        if tzName == forbidden then
            return true  -- Is forbidden
        end
    end
    
    return false  -- Not forbidden
end

function CheckIOSTimezone(tzName)
    -- iOS-specific check: timezone ends with "_cn"
    local StringUtil = require("common.string_util")
    return StringUtil.Ends(tzName, "_cn")
end

-- ============================================================================
-- Carrier Detection (MCC - Mobile Country Code)
-- ============================================================================

function GetCarrierInfo()
    -- Try cloud gaming carrier first
    local carrierInfo = logic_cloud_game:GetCarrierInfo()
    
    -- Fallback to system carrier
    if carrierInfo == "" or carrierInfo == nil then
        carrierInfo = Client.GetCarrierInfo()
    end
    
    return carrierInfo
end

function CheckAndroidCarrier()
    local carrierInfoStr = GetCarrierInfo()
    local carrierInfos = json.decode(carrierInfoStr)
    
    local foundForbiddenCount = 0
    local mccInfo = ""
    
    -- Check each carrier
    for i, carrier in ipairs(carrierInfos) do
        mccInfo = mccInfo .. carrier.mcc .. ","
        
        -- Check if MCC is "cn" (China)
        if string.lower(carrier.mcc) == "cn" then
            foundForbiddenCount = foundForbiddenCount + 1
        end
    end
    
    -- If ALL carriers are Chinese, it's forbidden
    local allCarriersChinese = (#carrierInfos ~= 0 and 
                                 #carrierInfos == foundForbiddenCount)
    
    return {
        isForbidden = allCarriersChinese,
        mccInfo = mccInfo,
        totalCarriers = #carrierInfos,
        chineseCarriers = foundForbiddenCount
    }
end

function CheckIOSOperator()
    local operator = Client.GetOperator()
    local isChinese = string.lower(operator) == "cn"
    
    return {
        isForbidden = isChinese,
        operator = operator
    }
end

-- ============================================================================
-- Platform Detection
-- ============================================================================

function GetDevicePlatform()
    return Client.GetDevicePlatformName()
end

function GetArchitecture()
    -- Returns 32 or 64 for Android
    return Client.GetAndroidSOVersion()
end

-- ============================================================================
-- Main Detection Flow
-- ============================================================================

function NatvieClientCheckFlow(skipMode)
    local stepToReturn = 0
    local isSystemVPNOpenning = ""
    local tzName = ""
    local mccinfo = ""
    
    -- Get remote configuration
    local enableVPNCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerVPNCheck", 1)
    local enableTZCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerTZCheck", 1)
    local enableMCCCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerMCCCheck", 1)
    
    -- STEP 1: VPN Detection
    if enableVPNCheck == 1 then
        isSystemVPNOpenning = IsVPNConnected()
        if not isSystemVPNOpenning then
            -- VPN not detected, might be from China
            stepToReturn = 1
            print("VPN check passed (no VPN detected)")
        else
            print("VPN detected")
        end
    end
    
    -- STEP 2: Timezone Detection
    if enableTZCheck == 1 then
        tzName = GetSysTimeZone()
        local forbidenTZNameNotFound = true
        
        local platform = GetDevicePlatform()
        
        if platform == "Android" then
            -- Check against forbidden timezone list
            forbidenTZNameNotFound = not CheckForbiddenTimezone(tzName)
        elseif platform == "IOS" then
            -- Check if timezone ends with _cn
            forbidenTZNameNotFound = not CheckIOSTimezone(tzName)
        end
        
        if forbidenTZNameNotFound then
            -- Timezone not forbidden
            stepToReturn = 2
            print("Timezone check passed (not forbidden): " .. tzName)
        else
            print("Forbidden timezone detected: " .. tzName)
        end
    end
    
    -- STEP 3: Carrier Detection
    if enableMCCCheck == 1 then
        local forbidenOperatorNotFound = true
        local platform = GetDevicePlatform()
        
        if platform == "Android" then
            local result = CheckAndroidCarrier()
            forbidenOperatorNotFound = not result.isForbidden
            mccinfo = result.mccInfo
            
            print(string.format("Android carrier check: %d/%d Chinese", 
                  result.chineseCarriers, result.totalCarriers))
        elseif platform == "IOS" then
            local result = CheckIOSOperator()
            forbidenOperatorNotFound = not result.isForbidden
            mccinfo = result.operator
            
            print("iOS operator check: " .. result.operator)
        end
        
        if forbidenOperatorNotFound then
            -- Carrier not Chinese
            stepToReturn = 3
            print("Carrier check passed (not Chinese)")
        else
            print("Chinese carrier detected")
        end
    end
    
    -- STEP 4: Decision Making
    if stepToReturn ~= 0 then
        -- At least one check indicates non-China region
        print(string.format("Detection triggered at step %d - ALLOW", stepToReturn))
        ReportForbidRegist(stepToReturn, isSystemVPNOpenning, tzName, mccinfo)
        return true  -- Allow login
        
    elseif skipMode == 5 then  -- CheckAndUnblock mode
        -- Detection-only mode (no ban)
        print("Detection-only mode - ALLOW")
        ReportForbidRegist(5, isSystemVPNOpenning, tzName, mccinfo)
        return true  -- Allow login
        
    else
        -- All checks passed = appears to be from China
        print("All checks passed (appears from China) - BLOCK")
        ReportForbidRegist(4, isSystemVPNOpenning, tzName, mccinfo)
        BlockAndReturnLogin()
        return false  -- Block login
    end
end

-- ============================================================================
-- Reporting Function
-- ============================================================================

function ReportForbidRegist(entry, vpn, tz, carrier, language, timeOffset)
    -- Get account info
    local IMSDKHelper = import("IMSDKHelper")
    local IMSDKHelperInstance = IMSDKHelper.GetInstance()
    local openid = IMSDKHelperInstance:getOpenID()
    
    -- Get client type
    local cloudGameClientType = logic_cloud_game:GetClientType()
    
    -- Build parameter table
    local ParamTable = {
        tostring(entry),                          -- [1] Entry point (1-5)
        tostring(openid),                         -- [2] Account ID
        tostring(vpn or "_"),                     -- [3] VPN status
        tostring(tz or "_"),                      -- [4] Timezone
        carrier or "_",                           -- [5] Carrier info
        tostring(cloudGameClientType or "_"),     -- [6] Client type
        tostring(timeOffset or "_"),              -- [7] Time offset
        tostring(language or "_")                 -- [8] Language
    }
    
    -- Send to server
    Client.GEMReportSubEvent(
        GameFrontendHUD,
        "GRomeLinkEvent",
        "NewPlayerEvent",
        ParamTable
    )
    
    print("Reported to server: entry=" .. entry)
end

-- ============================================================================
-- Block Function
-- ============================================================================

function BlockAndReturnLogin()
    -- Show error message
    local Util = import("common.util")
    local SystemMessage = import("system_message_module")
    
    SystemMessage.ShowMessage({
        title = Util.GetLanguageByKey("common.error"),
        message = Util.GetLanguageByKey("Login_Error"),
        buttons = {
            {
                text = Util.GetLanguageByKey("common.ok"),
                callback = function()
                    -- Logout and return to login
                    local SettingAccount = import("logic_setting_account")
                    SettingAccount.ClientLogout()
                    login_module:backLogin()
                end
            }
        }
    })
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

function ConvertInvalidConfig2Arr(base64Config)
    -- Decode base64 configuration
    local decoded = base64.decode(base64Config)
    
    -- Split by newline
    local arr = {}
    for s in string.gmatch(decoded, "[^\n]+") do
        table.insert(arr, string.lower(s))
    end
    
    return arr
end

-- ============================================================================
-- Block Type Configuration
-- ============================================================================

logic_tt_ban = {
    BlockType = {
        Disable = 1,           -- Skip all checks
        CheckAndBlock = 4,     -- Check and block if detected
        CheckAndUnblock = 5    -- Check but don't block (detection only)
    },
    
    InvalidConfig = {
        -- Base64 encoded forbidden timezones
        InvalidTimezone = "YXNpYS9zaGFuZ2hhaQphc2lhL2Nob25ncWluZwphc2lhL2NodW5ra2luZwphc2lhL2hhcmJpbgphc2lhL2thc2hnYXIKYXNpYS91cnVtcWkKcHJj",
        
        -- Base64 encoded forbidden languages
        InvalidLanguage = "emgtY24KemgtaGFucw==",
        
        -- Base64 encoded forbidden browsers
        InvalidBrand = "cXEKbHVjCnNvZ291CjM2MApsaWViYW8KYW95b3UKcXVhcms="
    }
}

function GetTTBlockType()
    local publishRegion = Client.GetPublishRegion()
    local defaultValue = logic_tt_ban.BlockType.Disable
    
    -- Set default based on region
    if publishRegion == "GLOBAL" or publishRegion == "FIT" then
        defaultValue = logic_tt_ban.BlockType.CheckAndBlock
    end
    
    -- Fetch from remote config
    local TTBlockType = HDmpveRemote.HDmpveRemoteConfigGetInt(
        "SkipNewPlayerEventCheck", 
        defaultValue
    )
    
    return TTBlockType
end

-- ============================================================================
-- Example Usage
-- ============================================================================

--[[
    Example 1: Check if user should be banned
    
    local blockType = GetTTBlockType()
    local allowed = NatvieClientCheckFlow(blockType)
    
    if allowed then
        print("User allowed to login")
    else
        print("User banned")
    end
]]

--[[
    Example 2: Check individual components
    
    -- Check VPN
    if IsVPNConnected() then
        print("VPN detected!")
    end
    
    -- Check timezone
    local tz = GetSysTimeZone()
    if CheckForbiddenTimezone(tz) then
        print("Forbidden timezone: " .. tz)
    end
    
    -- Check carrier
    if GetDevicePlatform() == "Android" then
        local result = CheckAndroidCarrier()
        print("Carrier check result:", result.isForbidden)
    end
]]
