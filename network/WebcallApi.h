//
//  Created by De Pauw Jimmy on 16/04/14.
//

#import "AFNetworking.h"
#import "AFNetworkReachabilityManager.h"

/* String Constants */
FOUNDATION_EXPORT NSString *const kUWebCallUrl; // Webcall main URL

// Method List
FOUNDATION_EXPORT NSString *const kUWebcallFctRegister;
FOUNDATION_EXPORT NSString *const kUWebcallFctLogin;
<********>

/* Numeric Constants */

<********>

// Max Reconnexion
#define kUMaxReconnection			2

// Timout value for connectivity type
#define kUReachabilityTimeoutDefault		10.0
#define kUReachabilityTimeoutForWIFI		10.0
#define kUReachabilityTimeoutCellular		20.0

#define kUMaxRetryWebcallAfterTimeout		2

@interface WebcallApi : AFHTTPSessionManager

+ (WebcallApi*)createInstance;

// Same webservices but using blocks
typedef void (^WebcallSuccessBlock)(Webcall *master);
typedef void (^WebcallFailureBlock)(NSError *error);
typedef void (^DownloadImageSuccessBlock)(UIImage *image);

// Login user
- (void)userLogin:(NSString*)login withPassword:(NSString*)password success:(WebcallSuccessBlock)successBlock failure:(WebcallFailureBlock)failBlock;
<********>

// Activation / reset
- (void)resendActivationEmail:(NSString*)login success:(WebcallSuccessBlock)successBlock failure:(WebcallFailureBlock)failBlock;
<********>

// Master method that performs the call, used by all other call function. Use this one direclty if you know what're doing :)
- (void)callWebserviceUsingBlocksWithParameters:(NSDictionary*)parameters andFct:(NSString*)fct success:(WebcallSuccessBlock)successBlock failure:(WebcallFailureBlock)failBlock;

// Cleanup methods, cancel all operations currently running on this object
- (void)cancelOperations;

// Properties
@property(strong, atomic) NSDictionary * __block savedWebcallData;			// Used to preserve webcall that triggered an auto-reconnect
@property(strong, nonatomic) Webcall *webcall;
@property(strong, atomic) NSError __block *error;
@property(assign) int tryReconnect;
@property(assign) int tryReconnectTimeout;
@property(assign) BOOL autoCancelPendingRequest;

@property(assign) float currentSessionTimeout;
@property(strong, nonatomic) AFNetworkReachabilityManager *hostReachability;

<********>

@end