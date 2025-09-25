//
//  EpsonSDKWrapper.m
//

#import "EpsonSDKWrapper.h"

@implementation EpsonSDKWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
        _discoveredPrinters = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)startDiscoveryWithFilter:(int32_t)filter completion:(void (^)(NSArray<NSDictionary *> *))completion {
    NSLog(@"Starting discovery with filter: %d", filter);
    
    // Ensure we have a valid completion handler
    if (!completion) {
        NSLog(@"ERROR: No completion handler provided for discovery");
        return;
    }
    
    @try {
        // Stop any existing discovery first
        [Epos2Discovery stop];
        
        [self.discoveredPrinters removeAllObjects];
        self.discoveryCompletionHandler = completion;
        
        // Create filter option object
        Epos2FilterOption *filterOption = [[Epos2FilterOption alloc] init];
        if (!filterOption) {
            NSLog(@"ERROR: Failed to create filter option");
            completion(@[]);
            return;
        }
        
        // Use the filter value directly as the port type
        [filterOption setPortType:filter];
        NSLog(@"Set filter to port type: %d", filter);
        
        NSLog(@"Created filter option, starting discovery...");
        
        int32_t result = [Epos2Discovery start:filterOption delegate:self];
        NSLog(@"Discovery start result: %d (EPOS2_SUCCESS=0)", result);
        
        if (result != EPOS2_SUCCESS) {
            NSLog(@"Discovery start failed with result: %d", result);
            completion(@[]);
            self.discoveryCompletionHandler = nil;
            return;
        }
        
        // Set up a timer to stop discovery after 10 seconds
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"Discovery timeout reached, stopping discovery...");
            [self stopDiscovery];
            if (self.discoveryCompletionHandler) {
                NSLog(@"Completing discovery with %lu printers found", (unsigned long)self.discoveredPrinters.count);
                self.discoveryCompletionHandler([self.discoveredPrinters copy]);
                self.discoveryCompletionHandler = nil;
            }
        });
        
    } @catch (NSException *exception) {
        NSLog(@"Exception in startDiscovery: %@", exception);
        completion(@[]);
        self.discoveryCompletionHandler = nil;
    }
}

- (void)stopDiscovery {
    [Epos2Discovery stop];
}

- (BOOL)connectToPrinter:(NSString *)target withSeries:(int32_t)series language:(int32_t)language timeout:(int32_t)timeout {
    NSLog(@"Connecting to printer with target: %@, series: %d, language: %d, timeout: %d", target, series, language, timeout);
    
    if (self.printer) {
        NSLog(@"Disconnecting existing printer connection...");
        [self.printer disconnect];
        self.printer = nil;
    }
    
    NSLog(@"Creating new printer instance...");
    self.printer = [[Epos2Printer alloc] initWithPrinterSeries:series lang:language];
    if (!self.printer) {
        NSLog(@"ERROR: Failed to create printer instance");
        return NO;
    }
    
    NSLog(@"Setting receive event delegate...");
    [self.printer setReceiveEventDelegate:self];
    
    NSLog(@"Attempting to connect to target: %@", target);
    int32_t result;
    if ([target hasPrefix:@"BLE:"]) {
        NSLog(@"Using BLE connection with 30s timeout");
        result = [self.printer connect:target timeout:30000]; // 30 second timeout for BLE
    } else {
        NSLog(@"Using standard connection with %d ms timeout", timeout);
        result = [self.printer connect:target timeout:timeout];
    }
    
    NSLog(@"Connection result: %d", result);
    
    if (result != EPOS2_SUCCESS) {
        NSLog(@"Connection failed with result: %d", result);
        
        // Log detailed error information
        switch (result) {
            case EPOS2_ERR_PARAM:
                NSLog(@"ERROR: Invalid parameter");
                break;
            case EPOS2_ERR_CONNECT:
                NSLog(@"ERROR: Connection error - printer may be offline or unreachable");
                break;
            case EPOS2_ERR_TIMEOUT:
                NSLog(@"ERROR: Connection timeout");
                break;
            case EPOS2_ERR_MEMORY:
                NSLog(@"ERROR: Memory allocation error");
                break;
            case EPOS2_ERR_ILLEGAL:
                NSLog(@"ERROR: Illegal operation");
                break;
            case EPOS2_ERR_PROCESSING:
                NSLog(@"ERROR: Processing error");
                break;
            default:
                NSLog(@"ERROR: Unknown error code: %d", result);
                break;
        }
        
        self.printer = nil;
        return NO;
    }
    
    NSLog(@"Successfully connected to printer!");
    return YES;
}

- (void)disconnect {
    if (self.printer) {
        [self.printer disconnect];
        [self.printer clearCommandBuffer];
        self.printer = nil;
    }
}

- (NSDictionary *)getPrinterStatus {
    if (!self.printer) {
        return @{};
    }
    
    Epos2PrinterStatusInfo *status = [self.printer getStatus];
    
    return @{
        @"isOnline": @(status.online == EPOS2_TRUE),
        @"status": status.online == EPOS2_TRUE ? @"online" : @"offline",
        @"errorMessage": [NSNull null],
        @"paperStatus": @(status.paper),
        @"drawerStatus": @(status.drawer),
        @"batteryLevel": @(status.batteryLevel),
        @"isCoverOpen": @(status.coverOpen == EPOS2_TRUE),
        @"errorCode": @(status.errorStatus),
        @"connection": @(status.connection == EPOS2_TRUE),
        @"paperFeed": @(status.paperFeed == EPOS2_TRUE),
        @"panelSwitch": @(status.panelSwitch)
    };
}

- (BOOL)printWithCommands:(NSArray<NSDictionary *> *)commands {
    NSLog(@"Starting print with %lu commands", (unsigned long)commands.count);
    
    if (!self.printer) {
        NSLog(@"ERROR: No printer connected");
        return NO;
    }
    
    NSLog(@"Clearing command buffer...");
    [self.printer clearCommandBuffer];
    
    for (NSDictionary *command in commands) {
        NSString *type = command[@"type"];
        NSLog(@"Processing command type: %@", type);
        
        // Handle both old format (addText) and new format (text)
        if ([type isEqualToString:@"addText"] || [type isEqualToString:@"text"]) {
            NSDictionary *parameters = command[@"parameters"];
            NSString *text = parameters[@"data"];
            if (text) {
                NSLog(@"Adding text: %@", text);
                [self.printer addText:text];
            } else {
                NSLog(@"WARNING: Text command missing data parameter");
            }
        } else if ([type isEqualToString:@"addTextLn"]) {
            NSDictionary *parameters = command[@"parameters"];
            NSString *text = parameters[@"data"];
            if (text) {
                NSLog(@"Adding text with newline: %@", text);
                [self.printer addText:text];
                [self.printer addFeedLine:1];
            }
        } else if ([type isEqualToString:@"addFeedLine"] || [type isEqualToString:@"feed"]) {
            NSDictionary *parameters = command[@"parameters"];
            NSNumber *lines = parameters[@"line"];
            int lineCount = lines ? lines.intValue : 1;
            NSLog(@"Adding feed lines: %d", lineCount);
            [self.printer addFeedLine:lineCount];
        } else if ([type isEqualToString:@"addCut"] || [type isEqualToString:@"cut"]) {
            NSLog(@"Adding cut command");
            [self.printer addCut:EPOS2_CUT_FEED];
        } else {
            NSLog(@"WARNING: Unknown command type: %@", type);
        }
    }
    
    NSLog(@"Sending print data to printer...");
    int32_t result = [self.printer sendData:EPOS2_PARAM_DEFAULT];
    NSLog(@"Print result: %d (EPOS2_SUCCESS=0)", result);
    
    if (result == EPOS2_SUCCESS) {
        NSLog(@"Print job sent successfully");
        return YES;
    } else {
        NSLog(@"Print job failed with error code: %d", result);
        return NO;
    }
}

- (void)clearCommandBuffer {
    if (self.printer) {
        [self.printer clearCommandBuffer];
    }
}

- (BOOL)openCashDrawer {
    if (!self.printer) {
        return NO;
    }
    
    NSLog(@"DEBUG: openCashDrawer called");
    // Clear any existing commands in the buffer first
    [self.printer clearCommandBuffer];
    
    NSLog(@"DEBUG: Adding pulse command for cash drawer");
    [self.printer addPulse:EPOS2_DRAWER_2PIN time:EPOS2_PULSE_100];
    
    NSLog(@"DEBUG: Sending cash drawer pulse...");
    int32_t result = [self.printer sendData:EPOS2_PARAM_DEFAULT];
    NSLog(@"DEBUG: Cash drawer result: %d (EPOS2_SUCCESS=0)", result);
    
    return result == EPOS2_SUCCESS;
}

#pragma mark - Epos2DiscoveryDelegate

- (void)onDiscovery:(Epos2DeviceInfo *)deviceInfo {
    NSLog(@"Discovery found device: %@ (target: %@, IP: %@)", deviceInfo.deviceName, deviceInfo.target, deviceInfo.ipAddress);
    
    NSDictionary *printerInfo = @{
        @"target": deviceInfo.target ?: @"",
        @"deviceName": deviceInfo.deviceName ?: @"",
        @"deviceType": @(deviceInfo.deviceType),
        @"ipAddress": deviceInfo.ipAddress ?: @"",
        @"macAddress": deviceInfo.macAddress ?: @""
    };
    
    [self.discoveredPrinters addObject:printerInfo];
}

- (void)onComplete {
    NSLog(@"Discovery completed. Found %lu printers", (unsigned long)self.discoveredPrinters.count);
    
    // Don't call completion here, let the timer handle it
    // The onComplete can be called before all devices are found
}

#pragma mark - Epos2PtrReceiveDelegate

- (void)onPtrReceive:(Epos2Printer *)printerObj code:(int32_t)code status:(Epos2PrinterStatusInfo *)status printJobId:(NSString *)printJobId {
    NSLog(@"Print job completed with code: %d", code);
}

@end
