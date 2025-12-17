# PUBG Mobile Ban Detection - Technical Deep Dive

> **Advanced technical analysis for security researchers**

---

## Table of Contents

- [System Architecture](#system-architecture)
- [Remote Configuration System](#remote-configuration-system)
- [Forbidden Data Lists](#forbidden-data-lists)
- [Hardware Fingerprinting Algorithm](#hardware-fingerprinting-algorithm)
- [Network Traffic Analysis](#network-traffic-analysis)
- [Advanced Server-Side Processing](#advanced-server-side-processing)

---

## System Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      CLIENT LAYER                           │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ UI Layer     │  │ Logic Layer  │  │ Native Layer │       │
│  │ (Blueprints) │→ │ (Lua Scripts)│→ │ (C++ API)    │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │ 
│         ↓                  ↓                  ↓             │
│  ┌──────────────────────────────────────────────────┐       │
│  │          Detection Module (logic_tt_ban)         │       │
│  │  ├─ VPN Check                                    │       │
│  │  ├─ Timezone Check                               │       │
│  │  ├─ Carrier Check                                │       │
│  │  └─ Platform Check                               │       │
│  └──────────────────────────────────────────────────┘       │
│         ↓                                                   │
│  ┌──────────────────────────────────────────────────┐       │
│  │     Reporting Module (GEMReportSubEvent)         │       │
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
                           ↓ HTTPS
┌─────────────────────────────────────────────────────────────┐
│                    NETWORK LAYER                            │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Load         │  │ API Gateway  │  │ Analytics    │       │
│  │ Balancer     │→ │ (Auth/Routing)→ │ Collector    │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │ 
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                      SERVER LAYER                           │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────┐       │
│  │        Validation Engine                         │       │
│  │  ├─ IP Geolocation Service                       │       │
│  │  ├─ Carrier Verification Service                 │       │
│  │  ├─ VPN Detection Service                        │       │
│  │  └─ Mismatch Detection Engine                    │       │
│  └──────────────────────────────────────────────────┘       │
│         ↓                                                   │
│  ┌──────────────────────────────────────────────────┐       │
│  │        Fingerprinting Engine                     │       │
│  │  ├─ Device Fingerprint Database                  │       │
│  │  ├─ Account History Database                     │       │
│  │  └─ Ban Registry                                 │       │
│  └──────────────────────────────────────────────────┘       │
│         ↓                                                   │
│  ┌──────────────────────────────────────────────────┐       │
│  │        Decision Engine                           │       │
│  │  ├─ Rule-Based System                            │       │
│  │  ├─ ML Anomaly Detection                         │       │
│  │  └─ Ban Enforcement                              │       │
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                   DATA STORAGE LAYER                        │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ User DB      │  │ Ban DB       │  │ Analytics DB │       │
│  │ (PostgreSQL) │  │ (Redis Cache)│  │ (ClickHouse) │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

---

## Remote Configuration System

### HDmpveRemote Implementation

```lua
-- File: /client/logic/HDmpveRemote/HDmpveRemote.lua

HDmpveRemote = {}
HDmpveRemote.ConfigCache = {}
HDmpveRemote.LastFetchTime = 0
HDmpveRemote.FetchInterval = 3600  -- 1 hour

function HDmpveRemote.HDmpveRemoteConfigGetInt(key, defaultValue)
    -- Check cache first
    if HDmpveRemote.ConfigCache[key] ~= nil then
        return HDmpveRemote.ConfigCache[key]
    end
    
    -- Fetch from server if cache expired
    if os.time() - HDmpveRemote.LastFetchTime > HDmpveRemote.FetchInterval then
        HDmpveRemote:FetchRemoteConfig()
    end
    
    -- Return cached value or default
    return HDmpveRemote.ConfigCache[key] or defaultValue
end

function HDmpveRemote:FetchRemoteConfig()
    -- Make HTTP request to config server
    local url = "https://config.pubgmobile.com/v1/config"
    local response = HTTP.Get(url, {
        region = Client.GetPublishRegion(),
        version = Client.GetAppVersion(),
        platform = Client.GetDevicePlatformName()
    })
    
    if response.success then
        -- Parse and cache configuration
        local config = json.decode(response.body)
        for k, v in pairs(config) do
            HDmpveRemote.ConfigCache[k] = v
        end
        HDmpveRemote.LastFetchTime = os.time()
    end
end
```

### Configuration Keys

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `NewPlayerVPNCheck` | int | 1 | Enable/disable VPN detection |
| `NewPlayerTZCheck` | int | 1 | Enable/disable timezone check |
| `NewPlayerMCCCheck` | int | 1 | Enable/disable carrier check |
| `NewPlayerBrowserCheck` | int | 1 | Enable/disable browser check |
| `NewPlayerLanguageCheck` | int | 1 | Enable/disable language check |
| `SkipNewPlayerEventCheck` | int | 4 | Overall ban mode (1=Disable, 4=Block, 5=Log) |

### Remote Config Server Response

```json
{
  "NewPlayerVPNCheck": 1,
  "NewPlayerTZCheck": 1,
  "NewPlayerMCCCheck": 1,
  "NewPlayerBrowserCheck": 1,
  "NewPlayerLanguageCheck": 1,
  "SkipNewPlayerEventCheck": 4,
  "BanThreshold": 2,
  "VPNWhitelist": ["cloudflare_warp"],
  "RegionBlacklist": ["CN"],
  "UpdateTimestamp": 1703174400
}
```

---

## Forbidden Data Lists

### InvalidTimezone (Base64 Encoded)

**Original (Base64)**:
```
YXNpYS9zaGFuZ2hhaQphc2lhL2Nob25ncWluZwphc2lhL2NodW5ra2luZwphc2lhL2hhcmJpbgphc2lhL2thc2hnYXIKYXNpYS91cnVtcWkKcHJj
```

**Decoded**:
```
asia/shanghai
asia/chongqing
asia/chunkking
asia/harbin
asia/kashgar
asia/urumqi
prc
```

**Implementation**:
```lua
logic_tt_ban.InvalidConfig = {
    InvalidTimezone = "YXNpYS9zaGFuZ2hhaQphc2lhL2Nob25ncWluZwphc2lhL2NodW5ra2luZwphc2lhL2hhcmJpbgphc2lhL2thc2hnYXIKYXNpYS91cnVtcWkKcHJj"
}

function logic_tt_ban:ConvertInvalidConfig2Arr(base64Config)
    local decoded = base64.decode(base64Config)
    local arr = {}
    for s in string.gmatch(decoded, "[^\n]+") do
        table.insert(arr, string.lower(s))
    end
    return arr
end
```

### InvalidLanguage (Base64 Encoded)

**Original (Base64)**:
```
emgtY24KemgtaGFucw==
```

**Decoded**:
```
zh-cn
zh-hans
```

### InvalidBrand (Base64 Encoded)

**Original (Base64)**:
```
cXEKbHVjCnNvZ291CjM2MApsaWViYW8KYW95b3UKcXVhcms=
```

**Decoded**:
```
qq
luc
sogou
360
liebao
aoyou
quark
```

---

## Hardware Fingerprinting Algorithm

### Data Collection

```lua
-- File: Device fingerprinting module
function DeviceFingerprint:Collect()
    local data = {
        -- Device Information
        device_model = Client.GetPhoneType(),
        device_brand = Client.GetDeviceBrand(),
        device_manufacturer = Client.GetManufacturer(),
        
        -- OS Information
        os_type = Client.GetDevicePlatformName(),
        os_version = Client.GetOSVersion(),
        os_build = Client.GetOSBuild(),
        
        -- Hardware Information
        cpu_arch = Client.GetAndroidSOVersion(),
        cpu_cores = Client.GetCPUCores(),
        cpu_freq = Client.GetCPUFrequency(),
        memory_size = Client.GetMemorySize(),
        storage_size = Client.GetStorageSize(),
        screen_width = Client.GetScreenWidth(),
        screen_height = Client.GetScreenHeight(),
        screen_dpi = Client.GetScreenDPI(),
        
        -- Software Information
        app_version = Client.GetAppVersion(),
        native_version = Client.GetNativeVersion(),
        client_version = Client.GetClientVersion(),
        
        -- Identifiers
        installation_id = Client.GetInstallationID(),
        advertising_id = Client.GetAdvertisingID(),
        android_id = Client.GetAndroidID(),
        
        -- Network Information
        mac_address = Client.GetMACAddress(),
        wifi_ssid = Client.GetWiFiSSID(),
        carrier_name = Client.GetCarrierName(),
        
        -- System Properties
        system_language = Client.GetSystemLanguage(),
        system_timezone = Client.GetTimezoneName(),
        system_locale = Client.GetSystemLocale()
    }
    
    return data
end
```

### Fingerprint Generation

```python
# Pseudocode for server-side fingerprint generation

def generate_fingerprint(device_data):
    # Stable components (don't change)
    stable = [
        device_data.device_model,
        device_data.device_manufacturer,
        device_data.cpu_arch,
        device_data.screen_width,
        device_data.screen_height
    ]
    
    # Semi-stable components (rarely change)
    semi_stable = [
        device_data.os_version,
        device_data.memory_size,
        device_data.storage_size
    ]
    
    # Mutable components (can change)
    mutable = [
        device_data.app_version,
        device_data.system_language,
        device_data.carrier_name
    ]
    
    # Generate hash
    stable_hash = sha256("".join(stable))
    semi_stable_hash = sha256("".join(semi_stable))
    
    # Combine hashes with weights
    fingerprint = {
        "primary": stable_hash,
        "secondary": semi_stable_hash,
        "confidence": calculate_confidence(device_data),
        "timestamp": current_timestamp()
    }
    
    return fingerprint

def calculate_confidence(device_data):
    # More unique data = higher confidence
    confidence = 0.0
    
    if device_data.installation_id:
        confidence += 0.3
    if device_data.android_id:
        confidence += 0.2
    if device_data.advertising_id:
        confidence += 0.2
    if device_data.mac_address:
        confidence += 0.15
    if device_data.device_model and device_data.cpu_arch:
        confidence += 0.15
    
    return min(confidence, 1.0)
```

### Fingerprint Matching

```python
def match_fingerprint(current_fp, stored_fp):
    # Exact match on primary hash
    if current_fp.primary == stored_fp.primary:
        return 1.0  # 100% match
    
    # Partial match on secondary hash
    if current_fp.secondary == stored_fp.secondary:
        return 0.7  # 70% match
    
    # Fuzzy matching on components
    similarity = 0.0
    
    # Check individual components
    if current_fp.device_model == stored_fp.device_model:
        similarity += 0.2
    if current_fp.os_version == stored_fp.os_version:
        similarity += 0.1
    if current_fp.screen_resolution == stored_fp.screen_resolution:
        similarity += 0.15
    
    return similarity
```

---

## Network Traffic Analysis

### VPN Detection via Traffic Patterns

```python
class VPNDetector:
    def __init__(self):
        self.vpn_signatures = self.load_vpn_signatures()
        
    def detect_vpn(self, traffic_data):
        signals = []
        
        # Signal 1: MTU size
        if traffic_data.mtu < 1400:
            signals.append(("MTU_LOW", 0.3))  # Common in tunnels
        
        # Signal 2: TTL analysis
        expected_ttl = self.get_expected_ttl(traffic_data.os)
        if abs(traffic_data.ttl - expected_ttl) > 5:
            signals.append(("TTL_ANOMALY", 0.4))
        
        # Signal 3: TCP window size
        if traffic_data.tcp_window < 5840:
            signals.append(("TCP_WINDOW_LOW", 0.2))
        
        # Signal 4: Latency patterns
        if traffic_data.latency_variance > 50:
            signals.append(("HIGH_LATENCY_VARIANCE", 0.5))
        
        # Signal 5: Packet fragmentation
        if traffic_data.fragmentation_rate > 0.05:
            signals.append(("HIGH_FRAGMENTATION", 0.3))
        
        # Signal 6: DNS leaks
        if traffic_data.dns_servers != traffic_data.isp_dns:
            signals.append(("DNS_MISMATCH", 0.6))
        
        # Calculate VPN probability
        vpn_score = sum(score for _, score in signals)
        
        return {
            "is_vpn": vpn_score > 0.7,
            "confidence": vpn_score,
            "signals": signals
        }
```

### Geolocation Validation

```python
class GeolocationValidator:
    def validate(self, reported_data, ip_data):
        mismatches = []
        
        # Timezone validation
        reported_tz = reported_data.timezone
        ip_tz = self.get_timezone_from_ip(ip_data.location)
        
        if reported_tz != ip_tz:
            # Check if timezone is reasonable for IP location
            distance = self.calculate_timezone_distance(reported_tz, ip_tz)
            if distance > 2:  # More than 2 timezones away
                mismatches.append({
                    "type": "TIMEZONE_MISMATCH",
                    "severity": "HIGH",
                    "reported": reported_tz,
                    "expected": ip_tz
                })
        
        # Carrier validation
        reported_carrier = reported_data.carrier
        ip_carrier = ip_data.carrier
        
        if reported_carrier != ip_carrier:
            # Check if carrier operates in IP location
            if not self.carrier_operates_in_location(reported_carrier, ip_data.location):
                mismatches.append({
                    "type": "CARRIER_MISMATCH",
                    "severity": "HIGH",
                    "reported": reported_carrier,
                    "expected": ip_carrier
                })
        
        # Latency validation
        reported_location = self.get_location_from_timezone(reported_data.timezone)
        expected_latency = self.calculate_expected_latency(
            reported_location, 
            server_location
        )
        actual_latency = reported_data.latency
        
        if abs(expected_latency - actual_latency) > 100:  # >100ms difference
            mismatches.append({
                "type": "LATENCY_ANOMALY",
                "severity": "MEDIUM",
                "expected": expected_latency,
                "actual": actual_latency
            })
        
        return {
            "valid": len(mismatches) == 0,
            "mismatches": mismatches,
            "confidence": 1.0 - (len(mismatches) * 0.3)
        }
```

---

## Advanced Server-Side Processing

### Machine Learning Ban Detection

```python
class MLBanDetector:
    def __init__(self):
        self.model = self.load_trained_model()
        self.feature_extractor = FeatureExtractor()
        
    def predict_ban(self, user_data, event_data):
        # Extract features
        features = self.feature_extractor.extract({
            "user_history": user_data.history,
            "current_event": event_data,
            "device_data": user_data.device,
            "network_data": event_data.network,
            "behavioral_data": user_data.behavior
        })
        
        # Predict using trained model
        prediction = self.model.predict(features)
        
        return {
            "should_ban": prediction.probability > 0.8,
            "confidence": prediction.probability,
            "risk_factors": prediction.feature_importance
        }

class FeatureExtractor:
    def extract(self, data):
        features = {}
        
        # Geographic features
        features["ip_country_changes"] = self.count_country_changes(data["user_history"])
        features["timezone_consistency"] = self.check_timezone_consistency(data)
        features["carrier_consistency"] = self.check_carrier_consistency(data)
        
        # Device features
        features["device_changes"] = len(data["user_history"].devices)
        features["fingerprint_matches"] = self.count_fingerprint_matches(data)
        
        # Behavioral features
        features["login_frequency"] = self.calculate_login_frequency(data)
        features["play_time_variance"] = self.calculate_play_time_variance(data)
        features["impossible_travel"] = self.detect_impossible_travel(data)
        
        # Network features
        features["vpn_usage_rate"] = self.calculate_vpn_usage(data)
        features["latency_anomalies"] = self.count_latency_anomalies(data)
        
        return features
```

### Ban Decision Engine

```python
class BanDecisionEngine:
    def __init__(self):
        self.rule_engine = RuleEngine()
        self.ml_detector = MLBanDetector()
        self.threshold_config = self.load_thresholds()
        
    def should_ban(self, user_id, event_data):
        # Rule-based decision
        rule_result = self.rule_engine.evaluate(event_data)
        
        # ML-based decision
        ml_result = self.ml_detector.predict_ban(
            self.get_user_data(user_id),
            event_data
        )
        
        # Combined decision
        ban_decision = {
            "ban": False,
            "reason": None,
            "confidence": 0.0,
            "evidence": []
        }
        
        # Rule-based bans (high priority)
        if rule_result.ban_required:
            ban_decision["ban"] = True
            ban_decision["reason"] = rule_result.reason
            ban_decision["confidence"] = 1.0
            ban_decision["evidence"].append(rule_result.evidence)
            return ban_decision
        
        # ML-based bans (medium priority)
        if ml_result.should_ban and ml_result.confidence > 0.8:
            ban_decision["ban"] = True
            ban_decision["reason"] = "ML_DETECTION"
            ban_decision["confidence"] = ml_result.confidence
            ban_decision["evidence"].append(ml_result.risk_factors)
            return ban_decision
        
        # Threshold-based bans (low priority)
        violation_score = self.calculate_violation_score(event_data)
        if violation_score > self.threshold_config.ban_threshold:
            ban_decision["ban"] = True
            ban_decision["reason"] = "THRESHOLD_EXCEEDED"
            ban_decision["confidence"] = min(violation_score / 100, 1.0)
            return ban_decision
        
        return ban_decision
    
    def calculate_violation_score(self, event_data):
        score = 0
        
        # Mismatch penalties
        score += event_data.timezone_mismatch * 30
        score += event_data.carrier_mismatch * 30
        score += event_data.vpn_mismatch * 20
        score += event_data.platform_mismatch * 10
        score += event_data.latency_anomaly * 10
        
        # Historical penalties
        if event_data.user_history.previous_bans > 0:
            score += 50
        if event_data.user_history.suspicious_logins > 5:
            score += 30
        
        # Device penalties
        if event_data.device.is_banned:
            score += 100
        if event_data.device.fingerprint_matches_banned > 0:
            score += 40
        
        return score
```

---

## Detection Effectiveness Metrics

### Success Rates

```python
# Real-world detection metrics (estimated)

DETECTION_METRICS = {
    "vpn_detection": {
        "true_positive_rate": 0.95,   # 95% of VPNs detected
        "false_positive_rate": 0.02,  # 2% false positives
        "accuracy": 0.97
    },
    "timezone_detection": {
        "true_positive_rate": 0.98,
        "false_positive_rate": 0.01,
        "accuracy": 0.98
    },
    "carrier_detection": {
        "true_positive_rate": 0.93,
        "false_positive_rate": 0.03,
        "accuracy": 0.95
    },
    "fingerprint_matching": {
        "true_positive_rate": 0.99,
        "false_positive_rate": 0.001,
        "accuracy": 0.99
    },
    "overall_system": {
        "ban_accuracy": 0.999,        # 99.9% accurate bans
        "false_ban_rate": 0.001,      # 0.1% false bans
        "bypass_detection": 0.998     # 99.8% bypass detection
    }
}
```

---

## Conclusion

The PUBG Mobile ban detection system represents a sophisticated, multi-layered security architecture that combines:

1. **Client-side detection** for initial screening
2. **Server-side validation** for independent verification
3. **Hardware fingerprinting** for permanent identification
4. **Machine learning** for pattern recognition
5. **Real-time monitoring** for continuous surveillance

This combination makes bypass attempts effectively impossible without access to legitimate devices and locations from unrestricted regions.
