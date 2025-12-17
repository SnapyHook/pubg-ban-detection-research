# Server-Side Validation Logic

> Pseudocode representation of server-side validation processes

## Overview

The server performs independent validation of all client-reported data. This validation cannot be bypassed from the client side.

---

## IP Geolocation Validation
```python
def validate_ip_geolocation(client_data, client_ip):
    """
    Validates client-reported location data against IP geolocation
    """
    # Perform IP lookup
    ip_data = geoip_database.lookup(client_ip)
    
    mismatches = []
    
    # Check country
    if client_data.country != ip_data.country:
        mismatches.append({
            "type": "COUNTRY_MISMATCH",
            "reported": client_data.country,
            "actual": ip_data.country,
            "severity": "HIGH"
        })
    
    # Check timezone
    expected_tz = get_timezone_for_location(ip_data.location)
    if client_data.timezone != expected_tz:
        mismatches.append({
            "type": "TIMEZONE_MISMATCH",
            "reported": client_data.timezone,
            "expected": expected_tz,
            "severity": "HIGH"
        })
    
    # Check carrier
    if client_data.carrier != ip_data.isp:
        mismatches.append({
            "type": "CARRIER_MISMATCH",
            "reported": client_data.carrier,
            "actual": ip_data.isp,
            "severity": "MEDIUM"
        })
    
    return {
        "valid": len(mismatches) == 0,
        "mismatches": mismatches
    }
```

---

## VPN Detection
```python
def detect_vpn(client_ip, client_data):
    """
    Detects VPN usage through multiple methods
    """
    vpn_indicators = []
    
    # Method 1: IP range check
    if is_ip_in_vpn_database(client_ip):
        vpn_indicators.append("IP_IN_VPN_DATABASE")
    
    # Method 2: Reverse DNS check
    hostname = reverse_dns_lookup(client_ip)
    if contains_vpn_keywords(hostname):
        vpn_indicators.append("HOSTNAME_INDICATES_VPN")
    
    # Method 3: Port scanning
    if has_vpn_ports_open(client_ip):
        vpn_indicators.append("VPN_PORTS_DETECTED")
    
    # Method 4: ASN check
    asn = get_asn_for_ip(client_ip)
    if is_vpn_provider_asn(asn):
        vpn_indicators.append("VPN_PROVIDER_ASN")
    
    # Method 5: Latency analysis
    if client_data.latency > expected_latency_for_region(client_data.timezone):
        vpn_indicators.append("LATENCY_ANOMALY")
    
    return {
        "is_vpn": len(vpn_indicators) >= 2,
        "confidence": len(vpn_indicators) / 5.0,
        "indicators": vpn_indicators
    }
```

---

## Carrier Verification
```python
def verify_carrier(client_carrier, client_ip):
    """
    Verifies mobile carrier matches IP address
    """
    # Get carrier from IP
    ip_carrier = get_carrier_from_ip(client_ip)
    
    # Get list of carriers operating in IP location
    region_carriers = get_carriers_for_region(get_region_from_ip(client_ip))
    
    # Check if reported carrier is valid for region
    carrier_valid = client_carrier in region_carriers
    
    # Check if carrier matches IP carrier
    carrier_matches = client_carrier == ip_carrier
    
    return {
        "valid": carrier_valid and carrier_matches,
        "carrier_exists_in_region": carrier_valid,
        "carrier_matches_ip": carrier_matches,
        "expected_carrier": ip_carrier
    }
```

---

## Mismatch Detection Engine
```python
def detect_mismatches(client_data, server_data):
    """
    Central mismatch detection engine
    """
    mismatches = []
    weights = {
        "TIMEZONE": 30,
        "CARRIER": 30,
        "VPN": 20,
        "PLATFORM": 10,
        "ARCHITECTURE": 5,
        "LATENCY": 10
    }
    
    # Timezone mismatch
    if client_data.timezone != server_data.expected_timezone:
        mismatches.append({
            "type": "TIMEZONE",
            "weight": weights["TIMEZONE"]
        })
    
    # Carrier mismatch
    if client_data.carrier != server_data.expected_carrier:
        mismatches.append({
            "type": "CARRIER",
            "weight": weights["CARRIER"]
        })
    
    # VPN mismatch
    if client_data.vpn == False and server_data.vpn_detected == True:
        mismatches.append({
            "type": "VPN",
            "weight": weights["VPN"]
        })
    
    # Platform mismatch
    if client_data.platform == None or client_data.platform == "":
        mismatches.append({
            "type": "PLATFORM",
            "weight": weights["PLATFORM"]
        })
    
    # Architecture mismatch
    if client_data.architecture == 0:
        mismatches.append({
            "type": "ARCHITECTURE",
            "weight": weights["ARCHITECTURE"]
        })
    
    # Calculate total mismatch score
    total_score = sum(m["weight"] for m in mismatches)
    
    return {
        "mismatches": mismatches,
        "total_score": total_score,
        "should_ban": total_score >= 50  # Threshold
    }
```

---

## Ban Decision Logic
```python
def make_ban_decision(event_data):
    """
    Final ban decision based on all collected data
    """
    # Extract entry point
    entry = event_data.entry
    
    # Get validation results
    geo_validation = validate_ip_geolocation(event_data.client, event_data.ip)
    vpn_detection = detect_vpn(event_data.ip, event_data.client)
    carrier_validation = verify_carrier(event_data.client.carrier, event_data.ip)
    mismatch_detection = detect_mismatches(event_data.client, event_data.server)
    
    # Decision tree
    if entry == 1 or entry == 2 or entry == 3:
        # Detection triggered (claims not from China)
        if event_data.server.ip_country == "CN":
            # Claims not from China but IP shows China
            if mismatch_detection.should_ban:
                return ban_user(event_data.user_id, "BYPASS_ATTEMPT", mismatch_detection)
        # Otherwise allow
        return allow_user(event_data.user_id)
    
    elif entry == 4:
        # All checks passed (appears to be from China)
        if event_data.server.ip_country == "CN":
            return ban_user(event_data.user_id, "REGION_RESTRICTION", None)
        elif mismatch_detection.should_ban:
            return ban_user(event_data.user_id, "DATA_MISMATCH", mismatch_detection)
        return allow_user(event_data.user_id)
    
    elif entry == 5:
        # Detection only mode
        log_detection_data(event_data)
        return allow_user(event_data.user_id)
    
    # Default: deny
    return ban_user(event_data.user_id, "UNKNOWN", None)
```

---

## Ban Enforcement
```python
def ban_user(user_id, reason, evidence):
    """
    Enforces ban on user account and device
    """
    # Create ban record
    ban_record = {
        "user_id": user_id,
        "ban_type": "10_YEAR",
        "ban_reason": reason,
        "ban_timestamp": current_timestamp(),
        "ban_expiry": current_timestamp() + (10 * 365 * 24 * 60 * 60),
        "evidence": evidence,
        "ip_address": get_client_ip(user_id),
        "device_fingerprint": get_device_fingerprint(user_id)
    }
    
    # Save to database
    database.bans.insert(ban_record)
    
    # Add to cache for fast lookup
    redis.sadd("banned_users", user_id)
    redis.sadd("banned_devices", ban_record.device_fingerprint)
    redis.sadd("banned_ips", ban_record.ip_address)
    
    # Send notification to client
    send_ban_notification(user_id, ban_record)
    
    # Log ban event
    log_ban_event(ban_record)
    
    return {
        "banned": True,
        "ban_record": ban_record
    }

def allow_user(user_id):
    """
    Allows user to proceed with login
    """
    return {
        "banned": False,
        "message": "Login allowed"
    }
```
