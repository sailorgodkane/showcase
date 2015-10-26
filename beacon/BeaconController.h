//
//  Created by De Pauw Jimmy on 16/04/14.
//

#import <Foundation/Foundation.h>
#import "ESTBeaconManager.h"
#import "ESTBeaconRegion.h"

#define kUSectionImmediate	0
#define kUSectionNear			1
#define kUSectionNotSoFar		2

typedef enum _kUBeaconControllerDetectionMode {
	kUBeaconControllerModeDetect = 1,
	kUBeaconControllerModeList = 2
} kUBeaconControllerDetectionMode;

FOUNDATION_EXPORT NSString *const kUBeaconControllerFoundBeaconNotification;
FOUNDATION_EXPORT NSString *const kUBeaconControllerUpdatedBeaconNotification;
FOUNDATION_EXPORT NSString *const kUBeaconControllerWillGetTrollDataNotification;
FOUNDATION_EXPORT NSString *const kUBeaconControllerGraceTimeExpiredNotification;

// Beacon specific timings in seconds
#define kUDisplayDetectionButtonOnListLength	10 // Button is displayed time on newsFeed
#define kUDisplayInitDetectionGraceTime		5  // Delay for the detection to start the first time

// Detection cycle
#define kUDisplayDetectionAllowedTime			20 // Number of seconds the user may be notified during a cycle
#define kUDisplayDetectionForbidTime			60 // Number of seconds the user may NOT be notified during a cycle


// In ProxiTrollView the list is refreshed only for this amount of second
#define kURefreshListLengthTimer				10

@interface BeaconController : NSObject <ESTBeaconManagerDelegate, CBCentralManagerDelegate>

@property (strong, nonatomic) ESTBeaconManager *manager;            // The manager to launch the broadcast
@property (strong, nonatomic) ESTBeaconRegion *region;
@property (strong, atomic) NSMutableArray __block *beaconsInRange;		// Used to build the list but only in kUBeaconControllerModeList mode
@property (strong, nonatomic) NSMutableArray *beaconsDetails;
@property (strong, nonatomic) ESTBeacon *lastDetectedBeacon;
@property (assign) kUBeaconControllerDetectionMode detectionMode;
@property (strong, nonatomic) CBCentralManager *bluetoothManager;
@property (assign) CBCentralManagerState bluetoothState;

@property (assign) BOOL hasStartedOnceAlready;				// Used to know that it was started at least once
@property (assign) BOOL userWarningIsAllowed;

@property (strong, nonatomic) NSTimer *beaconDetectionIsAllowedTimer;
@property (strong, nonatomic) NSTimer *beaconDetectionIsForbidTimer;

+ (BeaconController*)createInstance;
- (void)startDiscovering;
- (void)stopDiscovering;
- (void)switchDetectionToMode:(kUBeaconControllerDetectionMode)mode;

@end