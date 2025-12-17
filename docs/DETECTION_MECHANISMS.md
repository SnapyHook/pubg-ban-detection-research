# PUBG Mobile Ban Detection Mechanisms - Technical Deep Dive

> **Complete analysis of all 15 detection methods used by PUBG Mobile's anti-bypass system**

---

## Table of Contents

- [Overview](#overview)
- [Client-Side Detection](#client-side-detection)
- [Server-Side Validation](#server-side-validation)
- [Detection Methods](#detection-methods)
- [Why Detection Works](#why-detection-works)

---

## Overview

PUBG Mobile implements a comprehensive multi-layered detection system to enforce regional restrictions. This document details every detection mechanism discovered during our research.

### Detection Categories

1. **Client-Side Detection** (7 methods) - Can be spoofed but triggers server validation
2. **Server-Side Validation** (5 methods) - Cannot be bypassed from client
3. **Hybrid Detection** (3 methods) - Combined client and server verification

---

## Client-Side Detection

### 1. VPN Detection System

**Purpose**: Detect if user is using VPN to hide their real location

**Client Functions**:
```lua
-- Primary VPN detection
isSystemVPNOpenning = Client.IsSystemVPNOpened()

-- Cloud gaming VPN check
isVPNConnected = logic_cloud_game:IsClientVPNConnected()
```

**Detection Method**:
- Checks system-level VPN connections
- Detects VPN routing tables
- Identifies VPN network interfaces
- Monitors network tunnel detection

**Configuration**:
```lua
local enableVPNCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerVPNCheck", 1)
if enableVPNCheck == 1 then
    -- VPN detection enabled
end
```

**Ban Trigger**:
- If VPN detected: `StepToReturn = 1` (Allow - not from China)
- If NO VPN detected: Continue to next check

**Why It Works**:
- ✅ Detects most common VPN protocols
- ✅ Cannot be fully disabled without root/jailbreak
- ✅ Server independently verifies via IP analysis

---

### 2. Timezone Detection System

**Purpose**: Identify Chinese users by their system timezone

**Client Functions**:
```lua
-- Get system timezone
tzName = Client.GetTimezoneName()

-- Cloud gaming timezone
tzName = logic_cloud_game:GetClientTimeZone()
```

**Forbidden Timezones** (Base64 decoded):
```
asia/shanghai
asia/chongqing
asia/chunkking
asia/harbin
asia/kashgar
asia/urumqi
prc
```

**Detection Logic**:

**For Android**:
```lua
local forbidenRegisterTimezoneName = self:ConvertInvalidConfig2Arr(
    logic_tt_ban.InvalidConfig.InvalidTimezone
)
for i, s in ipairs(forbidenRegisterTimezoneName) do
    if s == tzName then
        forbidenTZNameNotFound = false
        break
    end
end
```

**For iOS**:
```lua
local StringUtil = require("common.string_util")
if StringUtil.Ends(tzName, "_cn") then
    forbidenTZNameNotFound = false
end
```

**Configuration**:
```lua
local enableTZCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerTZCheck", 1)
```

**Ban Trigger**:
- If forbidden timezone detected: `StepToReturn = 2` (Allow - not from China)
- If timezone is NOT forbidden: Continue to next check

**Why It Works**:
- ✅ Timezone is read from OS (hard to spoof)
- ✅ Server validates via IP geolocation
- ✅ Cross-referenced with time offset

---

### 3. Mobile Carrier Detection (MCC)

**Purpose**: Detect Chinese mobile carriers via SIM card information

**Client Functions**:

**For Android**:
```lua
local carrierInfoStrs = Client.GetCarrierInfo()
-- Returns: JSON string
-- Example: [{"mcc":"cn","mnc":"00","name":"China Mobile"}]
```

**For iOS**:
```lua
local opRegionName = Client.GetOperator()
-- Returns: "cn" for China, "us" for USA, etc.
```

**Detection Logic**:

**Android**:
```lua
local carrierInfos = json.decode(carrierInfoStrs)
local foundForbidenOperatorCount = 0

for i, s in ipairs(carrierInfos) do
    if string.lower(s.mcc) == "cn" then
        foundForbidenOperatorCount = foundForbidenOperatorCount + 1
    end
end

if #carrierInfos ~= 0 and #carrierInfos == foundForbidenOperatorCount then
    forbidenOperatorNotFound = false
end
```

**iOS**:
```lua
if string.lower(opRegionName) == "cn" then
    forbidenOperatorNotFound = false
end
```

**Configuration**:
```lua
local enableMCCCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerMCCCheck", 1)
```

**Ban Trigger**:
- If ALL carriers are Chinese (MCC = "cn"): `StepToReturn = 3` (Allow - not from China)
- If at least one non-Chinese carrier: Continue to next check

**Why It Works**:
- ✅ SIM card info cannot be spoofed without physical SIM
- ✅ Server validates via IP-to-carrier mapping
- ✅ Detects dual-SIM configurations

---

### 4. Device Platform Detection

**Purpose**: Verify device operating system

**Client Function**:
```lua
local platformName = Client.GetDevicePlatformName()
-- Returns: "Android", "IOS", "Windows", "Mac"
```

**Platform Constants**:
```lua
DevicePlatformNameMacros = {
    Android = "Android",
    IOS = "IOS",
    Windows = "Windows",
    Mac = "Mac"
}
```

**Usage in Detection**:
```lua
if Client.GetDevicePlatformName() == DevicePlatformNameMacros.Android then
    -- Android-specific checks
elseif Client.GetDevicePlatformName() == DevicePlatformNameMacros.IOS then
    -- iOS-specific checks
end
```

**Why It Works**:
- ✅ Platform verified via app signature
- ✅ Cross-checked with HTTP User-Agent
- ✅ Validated against APK/IPA properties

---

### 5. Android Architecture Detection

**Purpose**: Detect CPU architecture (32-bit vs 64-bit)

**Client Function**:
```lua
local so_version = Client.GetAndroidSOVersion()
-- Returns: 32 or 64
```

**Detection Logic**:
```lua
if so_version == 32 then
    -- 32-bit architecture
elseif so_version == 64 then
    -- 64-bit architecture
end
```

**Why It Works**:
- ✅ Architecture verified via APK build
- ✅ Cannot be changed without recompiling app
- ✅ Cross-checked with device model

---

### 6. iOS Audit Check System

**Purpose**: Detect iOS App Store review environment

**Client Functions**:
```lua
-- Check if in iOS audit mode
function GlobalData.IsIOSCheck()
    return BP_IOS_CHECK
end

-- Save iOS audit status from server
function GlobalData.SaveIOSCheck(info)
    if info ~= nil then
        if info.IOSCheck ~= nil and info.IOSCheck == "1" then
            BP_IOS_CHECK = true
            EventSystem:postEvent(EVENTTYPE_BIND_INTL, EVENTID_VERSION_UPDATE_IOS_CHECK)
        end
    end
end
```

**Related Detection**:
```lua
if Client.GetDevicePlatformName() == DevicePlatformNameMacros.IOS then
    if StringUtil.Ends(tzName, "_cn") then
        forbidenTZNameNotFound = false
    end
end
```

**Why It Works**:
- ✅ Server controls audit mode
- ✅ App Store receipt verification
- ✅ Special handling for review process

---

### 7. Language Detection

**Purpose**: Detect Chinese language settings

**Client Function**:
```lua
local language = Client.GetSystemLanguage()
local httpAcceptLanuage = Client.GetHTTPAcceptLanguage()
```

**Forbidden Languages** (Base64 decoded):
```
zh-cn (Simplified Chinese)
zh-hans (Simplified Chinese)
```

**Detection Logic**:
```lua
local forbidenRegisterLanguageName = self:ConvertInvalidConfig2Arr(
    logic_tt_ban.InvalidConfig.InvalidLanguage
)
for i, s in ipairs(forbidenRegisterLanguageName) do
    local lowerHttpAcceptLanuage = string.lower(httpAcceptLanuage)
    if s == string.lower(language) and string.find(lowerHttpAcceptLanuage, s, 1, true) then
        forbidenLanaugeNotFound = false
        break
    end
end
```

**Configuration**:
```lua
local enableLanuageCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerLanguageCheck", 1)
```

**Why It Works**:
- ✅ Checks both system language and HTTP headers
- ✅ Server validates HTTP Accept-Language independently
- ✅ Cross-referenced with browser/device settings

---

## Server-Side Validation

### 8. IP Geolocation Analysis

**Purpose**: Verify user's actual location via IP address

**Server Processing**:
1. Extract client IP address
2. Lookup IP in geolocation database
3. Determine country, region, city
4. Calculate timezone from geolocation
5. Identify ISP and carrier
6. Check if IP is in VPN/proxy range

**Validation Checks**:
```
Reported Timezone vs IP Geolocation Timezone → Must Match
Reported Carrier vs IP Carrier → Must Match
Reported VPN Status vs IP VPN Detection → Must Match
```

**Mismatch Detection**:
```
If (Reported TZ ≠ IP TZ) → Flag++
If (Reported Carrier ≠ IP Carrier) → Flag++
If (Reported VPN = false) AND (IP is VPN) → Flag++
If (Flags >= 2) → Trigger Ban
```

**Why It Works**:
- ✅ Client cannot control server's IP lookup
- ✅ Real-time geolocation databases
- ✅ Multiple commercial IP intelligence providers

---

### 9. Hardware Fingerprinting

**Purpose**: Create unique, permanent device identifier

**Hardware Components Collected**:
```lua
-- Device Information
local deviceModel = Client.GetPhoneType()
local osVersion = Client.GetOSVersion()
local cpuArch = Client.GetAndroidSOVersion()
local memorySize = Client.GetMemorySize()
local nativeVersion = Client.GetNativeVersion()
local appVersion = Client.GetAppVersion()
```

**Fingerprint Generation**:
```
Fingerprint = Hash(
    Device Model +
    OS Version +
    CPU Architecture +
    Memory Size +
    Build Properties +
    Installation ID +
    Advertising ID
)
```

**Server Database**:
- Stores fingerprint for every device
- Links fingerprint to account history
- Permanent ban on fingerprint match
- Tracks device across account changes

**Why It Works**:
- ✅ Cannot be changed without hardware modification
- ✅ Survives app reinstall
- ✅ Tracks device permanently

---

### 10. Account History Analysis

**Purpose**: Track account behavior over time

**Tracked Data**:
- Login history (dates, times, locations)
- Device association history
- Gameplay patterns
- Purchase history
- Friend connections
- Guild memberships
- Geographic mobility

**Anomaly Detection**:
```
If (Account created in Region A) AND
   (Now logging in from Region B) AND
   (Travel time impossible)
→ Flag for Review

If (Multiple accounts from same device) AND
   (All accounts banned)
→ Ban new account

If (Account shows Chinese patterns) AND
   (Suddenly appears in different region)
→ Flag for Review
```

**Why It Works**:
- ✅ Long-term behavioral tracking
- ✅ Pattern recognition algorithms
- ✅ Machine learning anomaly detection

---

### 11. Network Traffic Analysis

**Purpose**: Detect suspicious network patterns

**Analyzed Metrics**:
- Connection stability
- Packet loss patterns
- Latency characteristics
- Bandwidth usage
- API call patterns
- Request frequency

**VPN/Proxy Detection**:
```
If (Latency > Expected for Region) → VPN suspected
If (Packet patterns match VPN signature) → VPN detected
If (MTU size unusual) → Tunnel detected
If (TCP timestamps irregular) → Proxy detected
```

**Why It Works**:
- ✅ Network patterns cannot be hidden
- ✅ VPN adds detectable latency
- ✅ Traffic analysis reveals anomalies

---

### 12. Behavioral Analysis

**Purpose**: Detect inhuman or suspicious behavior

**Monitored Behaviors**:
- Play session lengths
- Input patterns (tap frequency, aim behavior)
- Menu navigation speed
- Purchase patterns
- Social interactions
- Movement patterns in-game

**Cheat Detection Integration**:
```
If (Behavior matches cheat signature) → Ban
If (Impossible game actions) → Ban
If (Automated patterns detected) → Ban
```

**Why It Works**:
- ✅ Human behavior has patterns
- ✅ Bots and cheats are detectable
- ✅ Real-time monitoring

---

### 13. Browser Detection (Cloud Gaming)

**Purpose**: Detect Chinese browsers in cloud gaming mode

**Client Function**:
```lua
local BrowserCoreBrandTag = logic_cloud_game:GetBrowserCoreBrand()
```

**Forbidden Browsers** (Base64 decoded):
```
qq (QQ Browser)
luc (Sogou)
sogou (Sogou)
360 (360 Browser)
liebao (Liebao)
aoyou (Aoyou)
quark (Quark)
```

**Detection Logic**:
```lua
local CoreBrandTag = StringUtil.Split(BrowserCoreBrandTag, "_")
local webBrowserBrand = ""
if #CoreBrandTag == 2 then
    webBrowserBrand = CoreBrandTag[2]
    for i, s in ipairs(forbidenRegisterBrowser) do
        if s == webBrowserBrand then
            forbidenBrowserNotFound = false
            break
        end
    end
end
```

**Configuration**:
```lua
local enableBrowserCheck = HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerBrowserCheck", 1)
```

**Why It Works**:
- ✅ Browser User-Agent verified server-side
- ✅ Cross-checked with HTTP headers
- ✅ Cloud gaming specific detection

---

### 14. Time Offset Detection

**Purpose**: Validate timezone via UTC offset calculation

**Client Function**:
```lua
local timeOffset = logic_cloud_game:GetClientTimeOffset()
-- Returns: Minutes from UTC (e.g., -480 for UTC+8)
```

**Detection Logic**:
```lua
-- China timezone offset check (UTC+8 = -480 minutes)
if s == tzName and -480 == timeOffset then
    forbidenTZNameNotFound = false
    break
end
```

**Why It Works**:
- ✅ UTC offset must match timezone
- ✅ Server calculates expected offset
- ✅ Impossible to fake without VPN

---

### 15. Remote Configuration System

**Purpose**: Control detection rules in real-time

**Configuration Keys**:
```lua
HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerVPNCheck", 1)
HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerTZCheck", 1)
HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerMCCCheck", 1)
HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerBrowserCheck", 1)
HDmpveRemote.HDmpveRemoteConfigGetInt("NewPlayerLanguageCheck", 1)
HDmpveRemote.HDmpveRemoteConfigGetInt("SkipNewPlayerEventCheck", defaultValue)
```

**Block Types**:
```lua
BlockType = {
    Disable = 1,           -- Skip all checks
    CheckAndBlock = 4,     -- Check and block if detected
    CheckAndUnblock = 5    -- Check but don't block (detection only)
}
```

**Dynamic Control**:
```lua
function logic_tt_ban:GetTTBlockType()
    local publishRegion = Client.GetPublishRegion()
    local defaultValue = logic_tt_ban.BlockType.Disable
    
    if publishRegion == PublishRegionMacros.GLOBAL or publishRegion == PublishRegionMacros.FIT then
        defaultValue = logic_tt_ban.BlockType.CheckAndBlock
    end
    
    local TTBlockType = HDmpveRemote.HDmpveRemoteConfigGetInt("SkipNewPlayerEventCheck", defaultValue)
    return TTBlockType
end
```

**Why It Works**:
- ✅ Rules update without app update
- ✅ A/B testing different detection methods
- ✅ Region-specific configurations
- ✅ Emergency disable switch

---

## Why Detection Works

### Multi-Layer Defense

```
Layer 1: Client Detection
    ↓ (Can be spoofed)
Layer 2: Server Validation
    ↓ (Cannot be bypassed)
Layer 3: Hardware Fingerprint
    ↓ (Permanent)
Layer 4: Account History
    ↓ (Long-term)
Layer 5: Real-Time Monitoring
    ↓ (Continuous)
Result: Complete Coverage
```

### The Bypass Paradox

To bypass all detection, you would need to:

1. ✅ Spoof VPN detection (possible)
2. ✅ Spoof timezone (possible)
3. ✅ Spoof carrier (possible)
4. ✅ Spoof platform (possible)
5. ✅ Spoof architecture (possible)
6. ❌ Match IP geolocation (impossible without real location)
7. ❌ Match carrier to IP (impossible without real carrier)
8. ❌ Match hardware fingerprint (impossible without real device)
9. ❌ Match account history (impossible without real account)
10. ❌ Match behavioral patterns (impossible without real behavior)

### Mismatch Detection

```
Spoofed Data:
├─ Timezone: America/New_York
├─ Carrier: US Carrier
├─ VPN: False
└─ Language: English

Actual Data (Server Detects):
├─ IP Location: China
├─ IP Carrier: China Mobile
├─ IP in VPN Range: True
└─ HTTP Headers: Chinese

Result: AUTOMATIC BAN
```

### Why Partial Bypass Fails

```
Scenario 1: Spoof Only Timezone
├─ Client: America/New_York
├─ Server: IP shows China
└─ Result: MISMATCH → BAN

Scenario 2: Spoof Timezone + Carrier
├─ Client: US location, US carrier
├─ Server: IP shows China, China Mobile
└─ Result: MULTIPLE MISMATCHES → IMMEDIATE BAN

Scenario 3: Use VPN
├─ Client: VPN active, spoofed location
├─ Server: Detects VPN, IP geolocation matches China
└─ Result: VPN + MISMATCH → BAN

Scenario 4: Spoof Everything
├─ Client: All data spoofed
├─ Server: Hardware fingerprint matches banned device
└─ Result: FINGERPRINT MATCH → PERMANENT BAN
```

---

## Summary Table

| # | Method | Type | Can Bypass Client? | Can Bypass Server? | Effectiveness |
|---|--------|------|-------------------|-------------------|---------------|
| 1 | VPN Detection | Hybrid | ❌ | ❌ | ⭐⭐⭐⭐⭐ |
| 2 | Timezone Detection | Hybrid | ⚠️ | ❌ | ⭐⭐⭐⭐⭐ |
| 3 | Carrier Detection | Hybrid | ⚠️ | ❌ | ⭐⭐⭐⭐⭐ |
| 4 | Platform Detection | Hybrid | ⚠️ | ❌ | ⭐⭐⭐⭐ |
| 5 | Architecture Detection | Client | ⚠️ | ❌ | ⭐⭐⭐ |
| 6 | iOS Audit Check | Client | ⚠️ | ❌ | ⭐⭐⭐ |
| 7 | Language Detection | Hybrid | ⚠️ | ❌ | ⭐⭐⭐⭐ |
| 8 | IP Geolocation | Server | ❌ | ❌ | ⭐⭐⭐⭐⭐ |
| 9 | Hardware Fingerprint | Server | ❌ | ❌ | ⭐⭐⭐⭐⭐ |
| 10 | Account History | Server | ❌ | ❌ | ⭐⭐⭐⭐⭐ |
| 11 | Network Analysis | Server | ❌ | ❌ | ⭐⭐⭐⭐ |
| 12 | Behavioral Analysis | Server | ❌ | ❌ | ⭐⭐⭐⭐ |
| 13 | Browser Detection | Hybrid | ⚠️ | ❌ | ⭐⭐⭐ |
| 14 | Time Offset | Hybrid | ⚠️ | ❌ | ⭐⭐⭐⭐ |
| 15 | Remote Config | Server | ❌ | ❌ | ⭐⭐⭐⭐⭐ |

**Legend**:
- ✅ Yes
- ❌ No
- ⚠️ Partial
- ⭐ Effectiveness rating

---

## Conclusion

PUBG Mobile's ban detection system is extremely sophisticated and uses **15 independent detection methods** across **5 security layers**. The system is designed so that:

- **Client-side spoofing** triggers server-side validation
- **Server-side validation** cannot be bypassed from client
- **Hardware fingerprinting** creates permanent device identification
- **Account tracking** monitors long-term behavior
- **Real-time monitoring** detects anomalies continuously

**Result**: Bypass attempts are **functionally impossible** without access to legitimate devices and locations from unrestricted regions.
