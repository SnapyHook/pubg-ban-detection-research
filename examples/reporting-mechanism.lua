--[[
    PUBG Mobile - Event Reporting Mechanism
    
    This file demonstrates how detection events are reported
    to the server for validation.
]]

-- ============================================================================
-- Event Reporting System
-- ============================================================================

local EventReporter = {}

-- Event types
EventReporter.EventTypes = {
    LOGIN = "LoginEvent",
    DETECTION = "NewPlayerEvent",
    BAN = "BanEvent",
    APPEAL = "AppealEvent"
}

-- ============================================================================
-- Main Reporting Function
-- ============================================================================

function EventReporter:ReportDetectionEvent(detectionData)
    --[[
        Reports detection event to server
        
        Parameters:
            detectionData = {
                entry = 1-5 (detection step),
                openid = "user_account_id",
                vpn = "true/false",
                timezone = "timezone_name",
                carrier = "carrier_info",
                clientType = "native/cloud",
                timeOffset = "-480",
                language = "en-US"
            }
    ]]
    
    -- Build parameter table
    local params = {
        tostring(detectionData.entry),
        tostring(detectionData.openid),
        tostring(detectionData.vpn or "_"),
        tostring(detectionData.timezone or "_"),
        tostring(detectionData.carrier or "_"),
        tostring(detectionData.clientType or "_"),
        tostring(detectionData.timeOffset or "_"),
        tostring(detectionData.language or "_")
    }
    
    -- Send event
    self:SendGEMEvent(
        GameFrontendHUD,
        "GRomeLinkEvent",
        EventReporter.EventTypes.DETECTION,
        params
    )
    
    -- Log locally
    print(string.format(
        "Detection event reported: entry=%s, user=%s",
        detectionData.entry,
        detectionData.openid
    ))
end

-- ============================================================================
-- GEM Event Sender
-- ============================================================================

function EventReporter:SendGEMEvent(context, eventType, subEvent, params)
    --[[
        Sends analytics event to server
        
        GEM = Game Event Management system
    ]]
    
    -- Add metadata
    local eventData = {
        context = context,
        event_type = eventType,
        sub_event = subEvent,
        timestamp = os.time(),
        params = params,
        metadata = {
            app_version = Client.GetAppVersion(),
            client_version = Client.GetClientVersion(),
            platform = Client.GetDevicePlatformName(),
            os_version = Client.GetOSVersion()
        }
    }
    
    -- Send via native client
    Client.GEMReportSubEvent(context, eventType, subEvent, params)
    
    -- Store in local queue if network unavailable
    if not Network.IsConnected() then
        self:QueueEvent(eventData)
    end
end

-- ============================================================================
-- Event Queue System
-- ============================================================================

EventReporter.EventQueue = {}

function EventReporter:QueueEvent(eventData)
    --[[
        Queues event for later sending if network unavailable
    ]]
    table.insert(self.EventQueue, eventData)
    print("Event queued for later sending")
end

function EventReporter:FlushQueue()
    --[[
        Sends all queued events when network becomes available
    ]]
    if #self.EventQueue == 0 then
        return
    end
    
    print(string.format("Flushing %d queued events", #self.EventQueue))
    
    for _, event in ipairs(self.EventQueue) do
        Client.GEMReportSubEvent(
            event.context,
            event.event_type,
            event.sub_event,
            event.params
        )
    end
    
    -- Clear queue
    self.EventQueue = {}
end

-- ============================================================================
-- Specialized Reporting Functions
-- ============================================================================

function EventReporter:ReportVPNDetection(isVPN, openid)
    self:ReportDetectionEvent({
        entry = 1,
        openid = openid,
        vpn = tostring(isVPN),
        timezone = Client.GetTimezoneName(),
        carrier = Client.GetCarrierInfo()
    })
end

function EventReporter:ReportTimezoneDetection(timezone, openid)
    self:ReportDetectionEvent({
        entry = 2,
        openid = openid,
        timezone = timezone,
        vpn = tostring(Client.IsSystemVPNOpened()),
        carrier = Client.GetCarrierInfo()
    })
end

function EventReporter:ReportCarrierDetection(carrier, openid)
    self:ReportDetectionEvent({
        entry = 3,
        openid = openid,
        carrier = carrier,
        vpn = tostring(Client.IsSystemVPNOpened()),
        timezone = Client.GetTimezoneName()
    })
end

function EventReporter:ReportAllChecksPassed(openid)
    -- All checks passed = user appears to be from China
    self:ReportDetectionEvent({
        entry = 4,
        openid = openid,
        vpn = tostring(Client.IsSystemVPNOpened()),
        timezone = Client.GetTimezoneName(),
        carrier = Client.GetCarrierInfo()
    })
end

function EventReporter:ReportDetectionOnly(openid)
    -- Detection-only mode (no ban)
    self:ReportDetectionEvent({
        entry = 5,
        openid = openid,
        vpn = tostring(Client.IsSystemVPNOpened()),
        timezone = Client.GetTimezoneName(),
        carrier = Client.GetCarrierInfo()
    })
end

-- ============================================================================
-- Example Usage
-- ============================================================================

--[[
    Example 1: Report VPN detection
    
    if Client.IsSystemVPNOpened() then
        EventReporter:ReportVPNDetection(true, user_openid)
    end
]]

--[[
    Example 2: Report timezone detection
    
    local tz = Client.GetTimezoneName()
    if IsForbiddenTimezone(tz) then
        EventReporter:ReportTimezoneDetection(tz, user_openid)
    end
]]

--[[
    Example 3: Report all checks passed
    
    if AllChecksPassed() then
        EventReporter:ReportAllChecksPassed(user_openid)
    end
]]

return EventReporter
