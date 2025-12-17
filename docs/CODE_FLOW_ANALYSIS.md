# PUBG Mobile Ban Detection - Complete Code Flow Analysis

> **Detailed execution flow from login to ban enforcement**

---

## Table of Contents

- [Overview](#overview)
- [Login Flow](#login-flow)
- [Detection Flow](#detection-flow)
- [Reporting Flow](#reporting-flow)
- [Server Processing](#server-processing)
- [Ban Enforcement](#ban-enforcement)

---

## Overview

This document traces the complete execution path of PUBG Mobile's ban detection system, from the moment a user attempts to log in until a ban is triggered.

### Key Files Involved

```
/client/logic/login/logic_tt_ban.lua          # Main ban detection
/client/logic/login/login_module.lua          # Login flow
/client/umg/bp_global.lua                     # Global data management
/client/logic/HDmpveRemote/HDmpveRemote.lua   # Remote config
/client/logic/login/device_module.lua         # Device info
```

---

## Login Flow

### Step 1: Login Initiation

```lua
-- File: Login_UIBP (UI Blueprint)
function Login_UIBP:LoginImplementation()
    login_module:reqLoginLobby()
end
```

### Step 2: Prepare Login Data

```lua
-- File: /client/logic/login/login_module.lua
function login_module:reqLoginLobby()
    local data = {
        clientVersion = Client.GetClientVersion(),
        device_type = Client.GetDeviceType(),
        platform = Client.GetDevicePlatformName(),
        so_version = Client.GetAndroidSOVersion(),
        appVersion = Client.GetAppVersion(),
        DeviceOSInfo = DeviceOSInfo.InfoList
    }
    
    LoginHandler.send_login(data)
end
```

### Step 3: Send Login Request

```lua
-- File: /client/logic/login/LoginHandler.lua
function LoginHandler.send_login(data)
    -- Construct login packet
    local packet = {
        clientVersion = data.clientVersion,
        device_type = data.device_type,
        platform = data.platform,
        so_version = data.so_version,
        appVersion = data.appVersion,
        os_info = json.encode(data.DeviceOSInfo)
    }
    
    -- Send to server
    Network.SendPacket("LOGIN_REQUEST", packet)
end
```

### Step 4: Receive Server Response

```lua
-- File: /client/logic/login/LoginHandler.lua
function LoginHandler.receive_login_response(response)
    -- Extract role data
    local roleData = response.roleData
    
    -- Save server-provided flags
    GlobalData.OnLogin(roleData)
    
    -- Check ban status
    if response.ban_status then
        -- User is already banned
        self:ShowBanMessage(response.ban_info)
        return
    end
    
    -- Proceed to lobby
    self:EnterLobby()
end
```

### Step 5: Update Global Data

```lua
-- File: /client/umg/bp_global.lua
function GlobalData.OnLogin(roleData)
    -- Set platform
    GlobalData.SetPlatform(roleData.channel)
    
    -- Set startup type
    GlobalData.SetStartUpType(roleData.startup_type)
    
    -- Set iOS audit status
    GlobalData.SaveIOSCheck(roleData)
    
    -- Save additional flags
    BP_PLATFORM = roleData.channel
    BP_STARTUP_TYPE = roleData.startup_type
end

function GlobalData.SaveIOSCheck(info)
    if info ~= nil then
        if info.IOSCheck ~= nil and info.IOSCheck == "1" then
            BP_IOS_CHECK = true
            EventSystem:postEvent(EVENTTYPE_BIND_INTL, EVENTID_VERSION_UPDATE_IOS_CHECK)
        end
    end
end
```

---

## Detection Flow

### Step 6: Ban Check Trigger

```lua
-- File: /client/logic/login/logic_tt_ban.lua
function logic_tt_ban:CheckIfCanCreateRole()
    -- Get block type from remote config
    local SkipNewPlayerCheck = self:GetTTBlockType()
    
    -- If detection disabled, allow
    if SkipNewPlayerCheck == logic_tt_ban.BlockType.Disable then
        return true
    end
    
    -- Determine detection flow
    if logic_cloud_game:IsCloudGameWeb() then
        -- Web/cloud gaming detection
        return self:WebClientCheckFlow(SkipNewPlayerCheck)
    else
        -- Native client detection
        return self:NatvieClientCheckFlow(SkipNewPlayerCheck)
    end
end
```

### Step 7: Get Block Type Configuration

```lua
-- File: /client/logic/login/logic_tt_ban.lua
function logic_tt_ban:GetTTBlockType()
    local publishRegion = Client.GetPublishRegion()
    local defaultValue = logic_tt_ban.BlockType.Disable
    
    -- Set default based on region
    if publishRegion == PublishRegionMacros.GLOBAL or 
       publishRegion == PublishRegionMacros.FIT then
        defaultValue = logic_tt_ban.BlockType.CheckAndBlock
    end
    
    -- Fetch from remote config
    local TTBlockType = HDmpveRemote.HDmpveRemoteConfigGetInt(
        "SkipNewPlayerEventCheck", 
        defaultValue
    )
    
    return TTBlockType
end
```

### Step 8: Native Client Detection Flow

```lua
-- File: /client/logic/login/logic_tt_ban.lua
function logic_tt_ban:NatvieClientCheckFlow(SkipNewPlayerCheck)
    local StepToReturn = 0
    local isSystemVPNOpenning = ""
    local tzName = ""
    local mccinfo = ""
    
    -- STEP 1: VPN Detection
    local enableVPNCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerVPNCheck", 1)
    if enableVPNCheck == 1 then
        isSystemVPNOpenning = self:IsVPNConnected()
        if not isSystemVPNOpenning then
            -- VPN not detected, user might be from China
            StepToReturn = 1
            -- Log but continue checks
        end
    end
    
    -- STEP 2: Timezone Detection
    local enableTZCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerTZCheck", 1)
    if enableTZCheck == 1 then
        tzName = self:GetSysTimeZone()
        local forbidenTZNameNotFound = true
        
        if Client.GetDevicePlatformName() == DevicePlatformNameMacros.Android then
            -- Check against forbidden timezone list
            local forbidenRegisterTimezoneName = self:ConvertInvalidConfig2Arr(
                logic_tt_ban.InvalidConfig.InvalidTimezone
            )
            for i, s in ipairs(forbidenRegisterTimezoneName) do
                if s == tzName then
                    forbidenTZNameNotFound = false
                    break
                end
            end
        elseif Client.GetDevicePlatformName() == DevicePlatformNameMacros.IOS then
            -- Check if timezone ends with _cn
            local StringUtil = require("common.string_util")
            if StringUtil.Ends(tzName, "_cn") then
                forbidenTZNameNotFound = false
            end
        end
        
        if forbidenTZNameNotFound then
            -- Timezone not in forbidden list
            StepToReturn = 2
        end
    end
    
    -- STEP 3: Carrier Detection
    local enableMCCCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerMCCCheck", 1)
    if enableMCCCheck == 1 then
        local forbidenOperatorNotFound = true
        
        if Client.GetDevicePlatformName() == DevicePlatformNameMacros.Android then
            local carrierInfoStrs = self:GetCarrierInfo()
            local carrierInfos = json.decode(carrierInfoStrs)
            local foundForbidenOperatorCount = 0
            
            for i, s in ipairs(carrierInfos) do
                mccinfo = mccinfo .. s.mcc .. ","
                if string.lower(s.mcc) == "cn" then
                    foundForbidenOperatorCount = foundForbidenOperatorCount + 1
                end
            end
            
            if #carrierInfos ~= 0 and #carrierInfos == foundForbidenOperatorCount then
                forbidenOperatorNotFound = false
            end
        elseif Client.GetDevicePlatformName() == DevicePlatformNameMacros.IOS then
            local opRegionName = Client.GetOperator()
            mccinfo = opRegionName
            if string.lower(opRegionName) == "cn" then
                forbidenOperatorNotFound = false
            end
        end
        
        if forbidenOperatorNotFound then
            -- Carrier not Chinese
            StepToReturn = 3
        end
    end
    
    -- STEP 4: Decision Making
    if StepToReturn ~= 0 then
        -- At least one check indicates non-China region
        self:ReportForbidRegist(StepToReturn, isSystemVPNOpenning, tzName, mccinfo)
        return true  -- Allow login
    elseif SkipNewPlayerCheck == logic_tt_ban.BlockType.CheckAndUnblock then
        -- Detection-only mode (no ban)
        self:ReportForbidRegist(5, isSystemVPNOpenning, tzName, mccinfo)
        return true  -- Allow login
    else
        -- All checks passed = appears to be from China
        self:ReportForbidRegist(4, isSystemVPNOpenning, tzName, mccinfo)
        self:BlockAndReturnLogin()
        return false  -- Block login
    end
end
```

### Step 9: Helper Functions

```lua
-- File: /client/logic/login/logic_tt_ban.lua

function logic_tt_ban:IsVPNConnected()
    -- Check cloud gaming VPN
    local isVPN = logic_cloud_game:IsClientVPNConnected()
    if not isVPN then
        -- Check system VPN
        isVPN = Client.IsSystemVPNOpened()
    end
    return isVPN
end

function logic_tt_ban:GetSysTimeZone()
    -- Get timezone from cloud gaming or system
    local tzName = logic_cloud_game:GetClientTimeZone()
    if tzName == "" or tzName == nil then
        tzName = Client.GetTimezoneName()
    end
    return string.lower(tzName)
end

function logic_tt_ban:GetCarrierInfo()
    -- Get carrier info from cloud gaming or system
    local carrierInfo = logic_cloud_game:GetCarrierInfo()
    if carrierInfo == "" or carrierInfo == nil then
        carrierInfo = Client.GetCarrierInfo()
    end
    return carrierInfo
end

function logic_tt_ban:ConvertInvalidConfig2Arr(base64Config)
    -- Decode base64 configuration
    local decoded = base64.decode(base64Config)
    local arr = {}
    for s in string.gmatch(decoded, "[^,]+") do
        table.insert(arr, string.lower(s))
    end
    return arr
end
```

---

## Reporting Flow

### Step 10: Report Detection Results

```lua
-- File: /client/logic/login/logic_tt_ban.lua
function logic_tt_ban:ReportForbidRegist(entry, vpn, tz, carrier, httpAcceptLanuage, timeOffset)
    -- Get account info
    local IMSDKHelper = import("IMSDKHelper")
    local IMSDKHelperInstance = IMSDKHelper.GetInstance()
    local openid = IMSDKHelperInstance:getOpenID()
    
    -- Get client type
    local cloudGameClientType = logic_cloud_game:GetClientType()
    
    -- Build parameter table
    local ParamTable = {
        tostring(entry),                              -- [1] Detection entry point
        tostring(openid),                             -- [2] Account ID
        tostring(vpn or "_"),                         -- [3] VPN status
        tostring(tz or "_"),                          -- [4] Timezone
        carrier or "_",                               -- [5] Carrier info
        tostring(cloudGameClientType or "_"),         -- [6] Client type
        tostring(timeOffset or "_"),                  -- [7] Time offset
        tostring(httpAcceptLanuage or "_")            -- [8] Language
    }
    
    -- Send to server
    Client.GEMReportSubEvent(
        GameFrontendHUD,
        "GRomeLinkEvent",
        "NewPlayerEvent",
        ParamTable
    )
end
```

### Step 11: Client Sends Event

```lua
-- File: Client API (Native)
function Client.GEMReportSubEvent(context, eventType, subEvent, params)
    -- Construct event packet
    local event = {
        context = context,
        event_type = eventType,
        sub_event = subEvent,
        timestamp = os.time(),
        params = params
    }
    
    -- Send to analytics server
    Network.SendAnalyticsEvent(event)
end
```

---

## Server Processing

### Step 12: Server Receives Event

```
Server receives: GRomeLinkEvent / NewPlayerEvent
├─ Extract parameters:
│  ├─ [1] entry (detection step: 1-5)
│  ├─ [2] openid (account ID)
│  ├─ [3] vpn (VPN status)
│  ├─ [4] tz (timezone)
│  ├─ [5] carrier (carrier info)
│  ├─ [6] clientType (native/cloud)
│  ├─ [7] timeOffset (UTC offset)
│  └─ [8] language (Accept-Language)
└─ Process ban detection
```

### Step 13: Server-Side Validation

```python
# Pseudocode for server-side processing

def process_ban_detection(event):
    # Extract data
    entry = event.params[0]
    openid = event.params[1]
    reported_vpn = event.params[2]
    reported_tz = event.params[3]
    reported_carrier = event.params[4]
    
    # Get client IP
    client_ip = event.source_ip
    
    # Perform IP geolocation lookup
    ip_data = geoip_lookup(client_ip)
    ip_timezone = ip_data.timezone
    ip_carrier = ip_data.carrier
    ip_country = ip_data.country
    ip_is_vpn = ip_data.is_vpn
    
    # Get device fingerprint
    device_fingerprint = get_device_fingerprint(openid)
    
    # Get account history
    account_history = get_account_history(openid)
    
    # Validation checks
    mismatches = 0
    
    # Check timezone mismatch
    if reported_tz != ip_timezone:
        mismatches += 1
        log_mismatch("timezone", reported_tz, ip_timezone)
    
    # Check carrier mismatch
    if reported_carrier != ip_carrier:
        mismatches += 1
        log_mismatch("carrier", reported_carrier, ip_carrier)
    
    # Check VPN mismatch
    if reported_vpn == "false" and ip_is_vpn == True:
        mismatches += 1
        log_mismatch("vpn", reported_vpn, ip_is_vpn)
    
    # Check if device is banned
    if is_device_banned(device_fingerprint):
        return trigger_ban(openid, "DEVICE_BAN")
    
    # Decision logic
    if entry == "1" or entry == "2" or entry == "3":
        # Detection triggered (not from China)
        if ip_country == "CN":
            # Client claims not from China but IP says China
            if mismatches >= 2:
                return trigger_ban(openid, "BYPASS_ATTEMPT")
        return allow_login()
    
    elif entry == "4":
        # All checks passed (appears to be from China)
        if ip_country == "CN":
            return trigger_ban(openid, "REGION_RESTRICTION")
        elif mismatches >= 2:
            return trigger_ban(openid, "DATA_MISMATCH")
        return allow_login()
    
    elif entry == "5":
        # Detection only mode (no ban)
        log_detection_only(openid, event)
        return allow_login()
```

### Step 14: Ban Decision Tree

```
┌─────────────────────────────────────┐
│   Receive Detection Report          │
└──────────────┬──────────────────────┘
               │
               ├─ entry == 1, 2, 3 (Detection Triggered)
               │  │
               │  ├─ IP Country == China?
               │  │  ├─ YES → Check Mismatches
               │  │  │  ├─ Mismatches >= 2 → BAN (Bypass Attempt)
               │  │  │  └─ Mismatches < 2 → ALLOW (Legitimate)
               │  │  └─ NO → ALLOW (Not from China)
               │  │
               │  └─ Device Banned? → BAN (Hardware Ban)
               │
               ├─ entry == 4 (All Checks Passed)
               │  │
               │  ├─ IP Country == China?
               │  │  ├─ YES → BAN (Region Restriction)
               │  │  └─ NO → Check Mismatches
               │  │     ├─ Mismatches >= 2 → BAN (Suspicious)
               │  │     └─ Mismatches < 2 → ALLOW
               │  │
               │  └─ Device Banned? → BAN (Hardware Ban)
               │
               └─ entry == 5 (Detection Only)
                  │
                  └─ Log Data → ALLOW (No Ban)
```

---

## Ban Enforcement

### Step 15: Trigger Ban

```python
# Pseudocode for ban enforcement

def trigger_ban(openid, reason):
    # Create ban record
    ban_record = {
        "openid": openid,
        "ban_type": "10_YEAR",
        "ban_reason": reason,
        "ban_timestamp": current_timestamp(),
        "ban_expiry": current_timestamp() + (10 * 365 * 24 * 60 * 60),
        "device_fingerprint": get_device_fingerprint(openid),
        "ip_address": get_client_ip(),
        "detection_data": get_detection_data()
    }
    
    # Save to database
    database.save_ban_record(ban_record)
    
    # Add to ban cache
    cache.add_banned_account(openid)
    cache.add_banned_device(ban_record.device_fingerprint)
    
    # Send ban notification to client
    send_ban_notification(openid, ban_record)
    
    # Log ban event
    log_ban_event(ban_record)
```

### Step 16: Send Ban Notification

```lua
-- File: /client/logic/login/logic_tt_ban.lua
function logic_tt_ban:BlockAndReturnLogin()
    -- Show error message
    local Util = import("common.util")
    local SystemMessage = import("system_message_module")
    
    -- Display ban message
    SystemMessage.ShowMessage({
        title = Util.GetLanguageByKey("common.error"),
        message = Util.GetLanguageByKey("Login_Error"),
        buttons = {
            {
                text = Util.GetLanguageByKey("common.ok"),
                callback = function()
                    -- Logout and return to login screen
                    local SettingAccount = import("logic_setting_account")
                    SettingAccount.ClientLogout()
                    login_module:backLogin()
                end
            }
        }
    })
end
```

### Step 17: Client Logout

```lua
-- File: /client/logic/setting/logic_setting_account.lua
function SettingAccount.ClientLogout()
    -- Clear session data
    GlobalData.ClearSession()
    
    -- Disconnect from server
    Network.Disconnect()
    
    -- Clear local cache
    Cache.Clear()
    
    -- Reset UI state
    UI.ResetToLoginScreen()
end
```

### Step 18: Return to Login

```lua
-- File: /client/logic/login/login_module.lua
function login_module:backLogin()
    -- Reset login state
    self:ResetLoginState()
    
    -- Show login screen
    UI.ShowLoginScreen()
    
    -- Clear previous session
    self:ClearPreviousSession()
end
```

---

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    USER ATTEMPTS LOGIN                       │
└──────────────┬──────────────────────────────────────────────┘
               │
               ├─ LoginImplementation()
               ├─ reqLoginLobby()
               ├─ send_login() → [Server]
               │
               ├─ [Server] ← receive_login_response()
               ├─ GlobalData.OnLogin()
               ├─ GlobalData.SaveIOSCheck()
               │
               ├─ CheckIfCanCreateRole()
               ├─ GetTTBlockType()
               │  ├─ HDmpveRemote.Get("SkipNewPlayerEventCheck")
               │  └─ Return: Disable / CheckAndBlock / CheckAndUnblock
               │
               ├─ NatvieClientCheckFlow()
               │  │
               │  ├─ VPN Check
               │  │  ├─ IsVPNConnected()
               │  │  ├─ Client.IsSystemVPNOpened()
               │  │  └─ Result: StepToReturn = 1 (if no VPN)
               │  │
               │  ├─ Timezone Check
               │  │  ├─ GetSysTimeZone()
               │  │  ├─ Client.GetTimezoneName()
               │  │  ├─ Check against forbidden list
               │  │  └─ Result: StepToReturn = 2 (if not forbidden)
               │  │
               │  ├─ Carrier Check
               │  │  ├─ GetCarrierInfo()
               │  │  ├─ Client.GetCarrierInfo()
               │  │  ├─ Check if MCC == "cn"
               │  │  └─ Result: StepToReturn = 3 (if not CN)
               │  │
               │  └─ Decision
               │     ├─ If StepToReturn != 0 → Report & Allow
               │     ├─ If mode == CheckAndUnblock → Report & Allow
               │     └─ Else → Report & Block
               │
               ├─ ReportForbidRegist()
               │  ├─ Build ParamTable
               │  ├─ Client.GEMReportSubEvent() → [Server]
               │  └─ Send: entry, openid, vpn, tz, carrier, etc.
               │
               ├─ [Server] ← Receive GRomeLinkEvent
               │  │
               │  ├─ Extract: entry, openid, vpn, tz, carrier
               │  ├─ Get: client_ip
               │  │
               │  ├─ IP Geolocation Lookup
               │  │  ├─ Get: ip_timezone
               │  │  ├─ Get: ip_carrier
               │  │  ├─ Get: ip_country
               │  │  └─ Get: ip_is_vpn
               │  │
               │  ├─ Device Fingerprint Check
               │  │  └─ is_device_banned()
               │  │
               │  ├─ Validation
               │  │  ├─ Check: reported_tz vs ip_timezone
               │  │  ├─ Check: reported_carrier vs ip_carrier
               │  │  ├─ Check: reported_vpn vs ip_is_vpn
               │  │  └─ Count: mismatches
               │  │
               │  └─ Decision
               │     ├─ If entry == 1,2,3
               │     │  ├─ If ip_country == "CN" AND mismatches >= 2 → BAN
               │     │  └─ Else → ALLOW
               │     ├─ If entry == 4
               │     │  ├─ If ip_country == "CN" → BAN
               │     │  ├─ If mismatches >= 2 → BAN
               │     │  └─ Else → ALLOW
               │     └─ If entry == 5 → ALLOW (log only)
               │
               ├─ [Server] → trigger_ban()
               │  ├─ Create ban_record
               │  ├─ Save to database
               │  ├─ Add to cache
               │  └─ send_ban_notification() → [Client]
               │
               ├─ [Client] ← Receive ban notification
               ├─ BlockAndReturnLogin()
               │  ├─ ShowMessage("Login_Error")
               │  ├─ SettingAccount.ClientLogout()
               │  └─ login_module:backLogin()
               │
               └─ Return to Login Screen
                  └─ ACCOUNT BANNED FOR 10 YEARS
```

---

## Key Execution Paths

### Path 1: User Not From China (Allowed)

```
Login → Detection → VPN Not Detected → StepToReturn=1
     → Report(1) → Server: IP not from China → ALLOW
```

### Path 2: User From China (Banned)

```
Login → Detection → All Checks Pass → StepToReturn=0
     → Report(4) → Server: IP from China → BAN
```

### Path 3: User Attempting Bypass (Banned)

```
Login → Detection → Spoofed Data → StepToReturn=2
     → Report(2) → Server: Mismatches Detected → BAN
```

### Path 4: Detection Only Mode (Allowed)

```
Login → Detection → Any Result → mode=CheckAndUnblock
     → Report(5) → Server: Log Only → ALLOW
```

---

## Timing Analysis

### Average Execution Time

```
Login Request:         100-200ms
Client Detection:      50-100ms
Report to Server:      100-300ms
Server Validation:     200-500ms
Ban Decision:          50-100ms
Total:                 500-1200ms (0.5-1.2 seconds)
```

### Critical Performance Points

- **Remote Config Fetch**: Cached, no delay
- **Client Detection**: Fast (< 100ms)
- **Network Report**: Depends on latency
- **Server Validation**: Most time-consuming
- **Ban Enforcement**: Immediate

---

## Summary

The complete execution flow shows:

1. **Login initiates** ban detection check
2. **Client-side detection** runs 3 main checks (VPN, timezone, carrier)
3. **Results are reported** to server with full context
4. **Server independently validates** all reported data
5. **Ban decision** is made based on entry point and mismatches
6. **Ban enforcement** is immediate and permanent (10 years)

**Key Insight**: Even if client-side detection is bypassed, server-side validation will detect mismatches and trigger ban. The system is designed to be **fail-secure** - any doubt results in a ban.
