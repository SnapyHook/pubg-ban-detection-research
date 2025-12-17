# Complete Detection Methods Table

| # | Method | Client Function | Server Validation | Type | Bypassable | Effectiveness |
|---|--------|----------------|-------------------|------|-----------|---------------|
| 1 | VPN Detection | `IsSystemVPNOpened()` | IP range check | Hybrid | ❌ | ⭐⭐⭐⭐⭐ |
| 2 | Timezone Check | `GetTimezoneName()` | IP geolocation | Hybrid | ❌ | ⭐⭐⭐⭐⭐ |
| 3 | Carrier Detection | `GetCarrierInfo()` | IP carrier match | Hybrid | ❌ | ⭐⭐⭐⭐⭐ |
| 4 | Platform Detection | `GetDevicePlatformName()` | App signature | Hybrid | ❌ | ⭐⭐⭐⭐ |
| 5 | Architecture | `GetAndroidSOVersion()` | APK validation | Client | ❌ | ⭐⭐⭐ |
| 6 | iOS Audit | `IsIOSCheck()` | Receipt validation | Client | ❌ | ⭐⭐⭐ |
| 7 | Language | `GetSystemLanguage()` | HTTP headers | Hybrid | ❌ | ⭐⭐⭐⭐ |
| 8 | IP Geolocation | N/A | MaxMind/IP2Location | Server | ❌ | ⭐⭐⭐⭐⭐ |
| 9 | Hardware Fingerprint | Multiple | SHA256 hashing | Server | ❌ | ⭐⭐⭐⭐⭐ |
| 10 | Account History | N/A | Database query | Server | ❌ | ⭐⭐⭐⭐⭐ |
| 11 | Network Analysis | N/A | Traffic patterns | Server | ❌ | ⭐⭐⭐⭐ |
| 12 | Behavioral Analysis | N/A | ML models | Server | ❌ | ⭐⭐⭐⭐ |
| 13 | Browser Detection | `GetBrowserBrand()` | User-Agent | Hybrid | ❌ | ⭐⭐⭐ |
| 14 | Time Offset | `GetTimeOffset()` | Calculation | Hybrid | ❌ | ⭐⭐⭐⭐ |
| 15 | Remote Config | N/A | Server-side | Server | ❌ | ⭐⭐⭐⭐⭐ |
