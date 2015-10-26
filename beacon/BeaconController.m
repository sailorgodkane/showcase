//
//  Created by De Pauw Jimmy on 16/04/14.
//

#import "BeaconController.h"
#import "SettingsPrefs.h"
#import "WebcallApi.h"

NSString *const kUBeaconControllerFoundBeaconNotification = @"BeaconControllerDidFoundBeacon";
NSString *const kUBeaconControllerUpdatedBeaconNotification = @"BeaconControllerDidUpdateBeacon";
NSString *const kUBeaconControllerWillGetTrollDataNotification = @"BeaconControllerWillGetTrollData";
NSString *const kUBeaconControllerGraceTimeExpiredNotification = @"BeaconControllerGraceTimeExpired";

@implementation BeaconController

+ (BeaconController*)createInstance
{
    static BeaconController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
		sharedInstance = [[BeaconController alloc] init];
		sharedInstance.beaconsInRange = [NSMutableArray array];
		sharedInstance.beaconsDetails = [NSMutableArray array];
		
		// Main broadcasting object
		sharedInstance.manager = [[ESTBeaconManager alloc] init];
		[sharedInstance.manager setDelegate:sharedInstance];
				
		// Estimote Beacon UUID
		NSUUID *proximityUUID = [[NSUUID alloc] initWithUUIDString:@"B9407F30-F5F8-466E-AFF9-25556B57FE6D"];
		
		// Set the region for the broadcasting
		sharedInstance.region = [[ESTBeaconRegion alloc] initWithProximityUUID:proximityUUID identifier:@"Estimote Region"];
		
		// Default detection
		sharedInstance.detectionMode = kUBeaconControllerModeDetect;
		
		// Check bluetooth status
        NSDictionary *options = @{CBCentralManagerOptionShowPowerAlertKey: [NSNumber numberWithBool:NO]};
		sharedInstance.bluetoothManager = [[CBCentralManager alloc]
                initWithDelegate:sharedInstance
                           queue:nil
                         options:options];
		sharedInstance.bluetoothState = sharedInstance.bluetoothManager.state;
		sharedInstance.hasStartedOnceAlready = NO;
		sharedInstance.userWarningIsAllowed = NO;
    });
    return sharedInstance;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
	if (central.state == CBCentralManagerStateUnsupported) {
		DLog(@"Bluetooth is unsupported");
	}
	if ( (central.state == CBCentralManagerStatePoweredOff) || (central.state == CBCentralManagerStateUnauthorized) ) {
		[self stopDiscovering];
	}
    @try {
	    self.bluetoothState = central.state;
    }
    @catch(NSException *e) {
        DLog(@"Crash Bluetooth: %@", e);
    }
}

- (void)startDiscovering
{
    [self.manager requestWhenInUseAuthorization];
	// In detection mode starting is done by timer
	if (self.detectionMode == kUBeaconControllerModeDetect) {
		if (!self.hasStartedOnceAlready) {
			self.beaconDetectionIsAllowedTimer = [NSTimer scheduledTimerWithTimeInterval:kUDisplayInitDetectionGraceTime target:self selector:@selector(delayDetectionForTheFirstStart:) userInfo:nil repeats:NO];
		} else {
			[self.manager startRangingBeaconsInRegion:self.region];
		}
	}
	
	// Always start in List when asked
	if (self.detectionMode == kUBeaconControllerModeList) {
		[self.manager startRangingBeaconsInRegion:self.region];
	}
}

- (void)allowedTimeIsOver:(NSTimer*)aTimer
{
	DLog(@"Warning user is forbidden for %d seconds", kUDisplayDetectionForbidTime);
	self.userWarningIsAllowed = NO;
	self.beaconDetectionIsForbidTimer = [NSTimer scheduledTimerWithTimeInterval:kUDisplayDetectionForbidTime target:self selector:@selector(forbidTimeIsOver:) userInfo:nil repeats:NO];
}

- (void)forbidTimeIsOver:(NSTimer*)aTimer
{
	DLog(@"Warning user is allowed for %d seconds", kUDisplayDetectionAllowedTime);
	self.userWarningIsAllowed = YES;
	self.beaconDetectionIsAllowedTimer = [NSTimer scheduledTimerWithTimeInterval:kUDisplayDetectionAllowedTime target:self selector:@selector(allowedTimeIsOver:) userInfo:nil repeats:NO];
	[[NSNotificationCenter defaultCenter] postNotificationName:kUBeaconControllerGraceTimeExpiredNotification object:self userInfo:nil];
}

- (void)delayDetectionForTheFirstStart:(NSTimer*)aTimer
{
	[self.manager startRangingBeaconsInRegion:self.region];
	self.hasStartedOnceAlready = YES;
	
	// SetupTimer
	DLog(@"Warning user is allowed for %d seconds", kUDisplayDetectionAllowedTime);
	self.userWarningIsAllowed = YES;
	self.beaconDetectionIsAllowedTimer = [NSTimer scheduledTimerWithTimeInterval:kUDisplayDetectionAllowedTime target:self selector:@selector(allowedTimeIsOver:) userInfo:nil repeats:NO];
}

- (void)stopDiscovering
{
	[self.manager stopRangingBeaconsInRegion:self.region];
}

- (NSString *)getFullBeaconID:(ESTBeacon*)beacon
{
    return [NSString stringWithFormat:@"%@-%@-%@", beacon.proximityUUID.UUIDString, beacon.major, beacon.minor];
}

- (void)switchDetectionToMode:(kUBeaconControllerDetectionMode)mode
{
	if (mode == kUBeaconControllerModeDetect) {
		[self.beaconsInRange removeAllObjects];
		[self.beaconsDetails removeAllObjects];
		self.lastDetectedBeacon = nil;
	}
	if (mode == kUBeaconControllerModeList) {
		if (self.lastDetectedBeacon) {
			DLog(@"Switched to LIST : getting details for the last beacon %@", [self getFullBeaconID:self.lastDetectedBeacon]);
		} else {
			DLog(@"Switched to LIST : no previous beacon");
		}
		
		// Auto update the list for the lastDetectedBeacon to avoid waiting for it's detection again
		[self fetchBeaconDetails:self.lastDetectedBeacon];
	}
	self.detectionMode = mode;
}

- (void)beaconManager:(ESTBeaconManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(ESTBeaconRegion *)region
{
	// iBeacon Color : UUID                                 - Major - Minor
    // Turquoise     : B9407F30-F5F8-466E-AFF9-25556B57FE6D - 10029 - 54035
    // Mauve         : B9407F30-F5F8-466E-AFF9-25556B57FE6D - 63885 - 58528
    // Blue          : B9407F30-F5F8-466E-AFF9-25556B57FE6D - 60045 - 62426
	
    if (beacons.count > 0) {
        for (int i = 0; i < beacons.count; i++) {
            ESTBeacon *theBeacon = [beacons objectAtIndex:i];
            
            // Beacon proximity
            int proxi = theBeacon.proximity;
            
            // Compare is in range from settings
            if([[theBeacon.proximityUUID UUIDString] isEqual:@"B9407F30-F5F8-466E-AFF9-25556B57FE6D"]) {
				// In detection mode only save the last beacon detected, do not do the webcall to get the items
				if( (self.detectionMode == kUBeaconControllerModeDetect) && ([SettingsPrefs getCoverageDistanceForProxi] >= proxi) ) {
										
					// Post notification that we found a new beacon
					if ([self isFoundInCacheArray:[self getFullBeaconID:theBeacon]]) {
						[[NSNotificationCenter defaultCenter] postNotificationName:kUBeaconControllerFoundBeaconNotification object:self userInfo:nil];
						self.lastDetectedBeacon = theBeacon;
					}
				}
				
				// In list mode a complete list is kept in memory, the linked items is also fetched and sent along the notification
				// The same beacon won't be fetched twice of course
				if (self.detectionMode == kUBeaconControllerModeList) {
					[self fetchBeaconDetails:theBeacon];
				}
            }
        }
    }
}

- (void)updateDistanceFromExistingData:(ESTBeacon*)beacon
{
	NSString *fullBeacon = [self getFullBeaconID:beacon];
	
	for (int i = 0;i<[self.beaconsDetails count]; i++) {
		NSDictionary *previousData = [self.beaconsDetails objectAtIndex:i];
		NSMutableDictionary *beaconData = [previousData mutableCopy];
		
		// Check if already detected
		if ([[beaconData objectForKey:@"BeaconUUID"] isEqualToString:fullBeacon]) {
			
			// Check if the distance changed
			if (beacon.proximity != [[beaconData objectForKey:@"BeaconDistance"] intValue]) {
                
                // Move cell to center
                DLog(@"Change distance");

				[beaconData setObject:[NSNumber numberWithInt:beacon.proximity] forKey:@"BeaconDistance"];
				[self.beaconsDetails replaceObjectAtIndex:i withObject:beaconData];

				NSDictionary *userInfo = @{@"OldData":previousData,@"NewData":beaconData};
				[[NSNotificationCenter defaultCenter] postNotificationName:kUBeaconControllerUpdatedBeaconNotification object:self userInfo:userInfo];
			}
			break;
		}
	}
}

- (BOOL)isFoundInDetectedArray:(NSString*)UUID
{
	BOOL isFound = NO;
	for (int i=0; i<[self.beaconsInRange count]; i++) {
		NSString *obj = [self.beaconsInRange objectAtIndex:i];
		if ([obj isEqualToString:UUID]) {
			isFound = YES;
		}
	}
	return isFound;
}

- (BOOL)isFoundInCacheArray:(NSString*)UUID
{
	BOOL isFound = NO;
	for (int i=0; i<[[[WebcallApi createInstance] beaconList] count]; i++) {
		NSString *obj = [[[WebcallApi createInstance] beaconList] objectAtIndex:i];
		if ([obj isEqualToString:UUID]) {
			isFound = YES;
		}
	}
	return isFound;
}

- (void)fetchBeaconDetails:(ESTBeacon*)beacon
{
	if (beacon == nil) {
		return;
	}
	
	NSString __block *fullBeacon = [self getFullBeaconID:beacon];
	
	if (![self isFoundInDetectedArray:fullBeacon]) {
		
		// Warn that we are about to do a webcall
		[[NSNotificationCenter defaultCenter] postNotificationName:kUBeaconControllerWillGetDataNotification object:self userInfo:nil];
		
		__weak __typeof(self) weakSelf = self;
		[[WebcallApi createInstance] getLinkedToBeaconUUID:fullBeacon success:^(Webcall *master) {
			
			[weakSelf.beaconsInRange addObject:fullBeacon];
			
			if (master.returnCode == kUOperationOk) {
				for (NSDictionary *t in master.data) {
					
					DLog(@"Posting new beacon notification : %@", fullBeacon);
                    
                    Model *tM = [Model getFromData:t];
					
					// Post notification that we found a new beacon, also put as userInfo the item linked to it
					NSDictionary *userInfo = @{@"BeaconUUID":fullBeacon,@"BeaconDistance":[NSNumber numberWithInt:beacon.proximity],@"LinkedData":tm};
					[weakSelf.beaconsDetails addObject:userInfo];
					[[NSNotificationCenter defaultCenter] postNotificationName:kUBeaconControllerFoundBeaconNotification object:self userInfo:userInfo];
				}
			} else if (master.returnCode == kUSQLNoResult) {
				// This beacon has no item linked at all, should be ignored and not trigger any notification
				DLog(@"Beacon : %@ has no item linked to it", fullBeacon);
			} else {
				[weakSelf.beaconsInRange removeObject:fullBeacon];
			}

		} failure:^(NSError *error) {
			[weakSelf.beaconsInRange removeObject:fullBeacon];
		}];
	} else {
		// Update the distance
		[self updateDistanceFromExistingData:beacon];
	}
}

@end