# Function Reference Guide

## Client Functions

### VPN Detection
```lua
Client.IsSystemVPNOpened()
```
- **Returns**: `boolean`
- **Purpose**: Detect system VPN
- **Platform**: All
- **Bypassable**: No

### Timezone Detection
```lua
Client.GetTimezoneName()
```
- **Returns**: `string` (e.g., "Asia/Shanghai")
- **Purpose**: Get system timezone
- **Platform**: All
- **Bypassable**: No

### Carrier Detection
```lua
Client.GetCarrierInfo()  -- Android
Client.GetOperator()     -- iOS
```
- **Returns**: `string` (JSON for Android, country code for iOS)
- **Purpose**: Get mobile carrier info
- **Platform**: Android/iOS
- **Bypassable**: No

### Platform Detection
```lua
Client.GetDevicePlatformName()
```
- **Returns**: `string` ("Android", "IOS", "Windows", "Mac")
- **Purpose**: Get device platform
- **Platform**: All
- **Bypassable**: No

### Architecture Detection
```lua
Client.GetAndroidSOVersion()
```
- **Returns**: `number` (32 or 64)
- **Purpose**: Get CPU architecture
- **Platform**: Android
- **Bypassable**: No

### Device Information
```lua
Client.GetPhoneType()
Client.GetOSVersion()
Client.GetMemorySize()
Client.GetAppVersion()
```

### Event Reporting
```lua
Client.GEMReportSubEvent(context, eventType, subEvent, params)
```
- **Purpose**: Send analytics event to server
- **Platform**: All

## GlobalData Functions

### iOS Check
```lua
GlobalData.IsIOSCheck()
GlobalData.SaveIOSCheck(info)
```

## HDmpveRemote Functions

### Remote Configuration
```lua
HDmpveRemote.HDmpveRemoteConfigGetInt(key, defaultValue)
```
- **Purpose**: Get remote configuration value
- **Returns**: `number`

## Configuration Keys

- `NewPlayerVPNCheck`: Enable VPN detection (1=on, 0=off)
- `NewPlayerTZCheck`: Enable timezone check
- `NewPlayerMCCCheck`: Enable carrier check
- `SkipNewPlayerEventCheck`: Ban mode (1=Disable)
