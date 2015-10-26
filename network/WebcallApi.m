//
//  Created by De Pauw Jimmy on 16/04/14.
//

#import "WebcallApi.h"
<********>
#import <FacebookSDK/FacebookSDK.h>

#if kUCompileDevel == 1
NSString *const kUWebCallUrl = @"***";
#elif kUCompileProduction == 1
NSString *const kUWebCallUrl = @"***";
#elif kUCompileInHouse == 1
NSString *const kUWebCallUrl = @"***";
#endif

// Fcts
NSString *const kUWebcallFctRegister = @"wc_usr_register.php";
NSString *const kUWebcallFctLogin = @"wc_usr_login.php";
<********>

// Filter constants
<********>

@interface WebcallApi(Private)
- (void)callWebserviceRetryAfterReconnect;
- (void)reconnectAfterSessionExpire:(void(^)(BOOL result))resultBlock;
@end

static WebcallApi *sharedInstance = nil;

@implementation WebcallApi

+ (WebcallApi*)createInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
		NSURL *baseUrl = [NSURL URLWithString:kUWebCallUrl];
		NSURLSessionConfiguration *sessionConfiguration = [WebcallApi generateSessionConfigurationWithTimeout:kUReachabilityTimeoutDefault];
		
		// Create the AFHTTPSessionManager singleton
        sharedInstance = [[WebcallApi alloc] initWithBaseURL:baseUrl sessionConfiguration:sessionConfiguration];
		sharedInstance.autoCancelPendingRequest = YES;
		
		// Reachability setup
		sharedInstance.hostReachability = [AFNetworkReachabilityManager managerForDomain:@"****"];
		[[NSNotificationCenter defaultCenter] addObserver:sharedInstance selector:@selector(reachabilityChanged:) name:AFNetworkingReachabilityDidChangeNotification object:nil];
		
		[sharedInstance.hostReachability startMonitoring];
		
		sharedInstance.currentSessionTimeout = kUReachabilityTimeoutDefault;
    });
    return sharedInstance;
}

+ (NSURLSessionConfiguration*)generateSessionConfigurationWithTimeout:(float)timeout
{
	NSURL *baseUrl = [NSURL URLWithString:kUWebCallUrl];
	
	// Configure the webcall protection space forcing a server, a secured protocol and a realm
	NSURLProtectionSpace *protectionSpace = [[NSURLProtectionSpace alloc] initWithHost:[baseUrl host] port:443 protocol:NSURLProtectionSpaceHTTPS realm:@"Restricted Files" authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
	NSURLCredentialStorage *credStorage = [NSURLCredentialStorage sharedCredentialStorage];
	
	// Set the master login/password for the webcall
	NSURLCredential *creds = [NSURLCredential credentialWithUser:kUWebcallLoginCredentials password:kUWebcallPasswordCredentials persistence:NSURLCredentialPersistencePermanent];
	[credStorage setCredential:creds forProtectionSpace:protectionSpace];
	
	// Create the global SessionConfiguration object
	NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
	[sessionConfiguration setHTTPShouldSetCookies:YES];
	[sessionConfiguration setURLCredentialStorage:credStorage];
	[sessionConfiguration setTimeoutIntervalForRequest:timeout];
	[sessionConfiguration setTimeoutIntervalForResource:timeout];
	
	return sessionConfiguration;
}

#pragma mark - Reachability

- (void)reachabilityChanged:(NSNotification*)aNotification
{
	AFNetworkReachabilityStatus status = [[[aNotification userInfo] objectForKey:AFNetworkingReachabilityNotificationStatusItem] integerValue];
	DLog(@"%@", AFStringFromNetworkReachabilityStatus(status));
	
	// WiFi, high speed connection. Set timeout to a low value
	if (status == AFNetworkReachabilityStatusReachableViaWiFi) {
		DLog(@"Current connection is WiFi | Set timeout to : %f", kUReachabilityTimeoutForWIFI);
		[self reconfigureCurrentSessionConfigurationUsingTimeout:kUReachabilityTimeoutForWIFI];
	} else if(status == AFNetworkReachabilityStatusReachableViaWWAN) {
		DLog(@"Current connection is Cellular | Set timeout to : %f", kUReachabilityTimeoutCellular);
		[self reconfigureCurrentSessionConfigurationUsingTimeout:kUReachabilityTimeoutCellular];
	}
}

- (void)reconfigureCurrentSessionConfigurationUsingTimeout:(float)newTimeout
{
	// Don't do anything if the timeout do not need to be changed
	if (self.currentSessionTimeout == newTimeout) {
		return;
	}
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	NSURL *baseUrl = [NSURL URLWithString:kUWebCallUrl];
	NSURLSessionConfiguration *sessionConfiguration = [WebcallApi generateSessionConfigurationWithTimeout:kUReachabilityTimeoutDefault];
	
	// Create the AFHTTPSessionManager singleton
	sharedInstance = [[WebcallApi alloc] initWithBaseURL:baseUrl sessionConfiguration:sessionConfiguration];
	sharedInstance.autoCancelPendingRequest = YES;
	
	// Reachability setup
	sharedInstance.hostReachability = [AFNetworkReachabilityManager managerForDomain:@"***"];
	[[NSNotificationCenter defaultCenter] addObserver:sharedInstance selector:@selector(reachabilityChanged:) name:AFNetworkingReachabilityDidChangeNotification object:nil];
	[sharedInstance.hostReachability startMonitoring];
	
	sharedInstance.currentSessionTimeout = newTimeout;
}

#pragma mark - Block Version : Users

<********>

- (void)userRegisterWithLogin:(NSString*)login password:(NSString*)password firstname:(NSString*)fn lastname:(NSString*)ln success:(WebcallSuccessBlock)successBlock failure:(WebcallFailureBlock)failBlock
{
	_tryReconnect = 0;
	_tryReconnectTimeout = 0;
    [self callWebserviceUsingBlocksWithParameters:@{@"yt_user_login":login, @"yt_user_pass":[password EncryptPlainTextWithSalt:kUSalt], @"yt_user_fn":fn, @"yt_user_ln":ln} andFct:kUWebcallFctRegister success:successBlock failure:failBlock];
}

- (void)userLogin:(NSString*)login withPassword:(NSString*)password success:(WebcallSuccessBlock)successBlock failure:(WebcallFailureBlock)failBlock
{
	_tryReconnect = 0;
	_tryReconnectTimeout = 0;
    [self callWebserviceUsingBlocksWithParameters:@{@"yt_user_login":login, @"yt_user_pass":[password EncryptPlainTextWithSalt:kUSalt]} andFct:kUWebcallFctLogin success:successBlock failure:failBlock];
}

<********>

#pragma mark - Block Version : Private

- (void)cancelOperations
{
	// Manager Object
    [self.operationQueue cancelAllOperations];
}

- (void)callWebserviceUsingBlocksWithParameters:(NSDictionary *)parameters andFct:(NSString*)fct success:(WebcallSuccessBlock)successBlock failure:(WebcallFailureBlock)failBlock
{
	if (parameters == nil) {
		parameters = @{};
	}
    
    NSMutableDictionary *params = [parameters mutableCopy];

    // Automatically add the version number to every webcall
    params[@"appVersionNumber"] = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];

    // Manager Object
	if (self.autoCancelPendingRequest) {
		[self cancelOperations];
	}
	
    // Call Webservice with params
	__block __typeof(self)weakSelf = self;	
    [self POST:fct parameters:params success:^(NSURLSessionDataTask *task, id responseObject) {
		
        // Parser Object to create native Dictionary with response object
        Webcall *subwebcall = [[Webcall alloc] initParseWebcallReturnObject:responseObject];
		
		// Always return if this is a login call, it makes no sense to try reconnection when it is not connected in the first place
		if ([fct isEqualToString:kUWebcallFctLogin]) {
			successBlock(subwebcall);
		} else if ([subwebcall returnCode] == (long)kUSessionExpired) {
			// Preserve original webcall data
			[weakSelf setSavedWebcallData:@{
                    @"parameters": params,
                    @"function": fct,
                    @"successBlock": successBlock,
                    @"failBlock": failBlock
            }];

			// Start reconnect loop
			[weakSelf reconnectAfterSessionExpire:^(BOOL result) {
				if (!result) {
					WebcallFailureBlock fail = [weakSelf.savedWebcallData objectForKey:@"failBlock"];
					if (fail) { fail(nil); }
				} else {
					// Reconnect has succeeded, resume the original webcall
					[weakSelf callWebserviceRetryAfterReconnect];
				}
			}];
		} else {
			successBlock(subwebcall);
		}
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
		DLog(@"Webcall error : %@", error);
		
		if ( ([error code] == NSURLErrorTimedOut) && (_tryReconnectTimeout < kUMaxRetryWebcallAfterTimeout) ) {
			DLog(@"RETRY WEBCALL AFTER TIMEOUT");
			
			_tryReconnectTimeout++;
			[weakSelf callWebserviceUsingBlocksWithParameters:params andFct:fct success:successBlock failure:failBlock];
			
		} else {
			// Operation may have been cancelled, view was dismissed before the call could finish for instance
			// Don't bother if that happens
			if (failBlock && ([error code] != NSURLErrorCancelled)) {
				failBlock(error);
			}
		}
    }];
}
- (void)callWebserviceRetryAfterReconnect
{
	if (self.savedWebcallData == nil) {
		return;
	}
	
	// Reconnect has succeeded, resume the original webcall
	[self callWebserviceUsingBlocksWithParameters:[self.savedWebcallData objectForKey:@"parameters"]
										   andFct:[self.savedWebcallData objectForKey:@"function"]
										  success:[self.savedWebcallData objectForKey:@"successBlock"]
										  failure:[self.savedWebcallData objectForKey:@"failBlock"]];
}

- (void)reconnectAfterSessionExpire:(void(^)(BOOL result))resultBlock
{
	_tryReconnect++;
	
	// Try standard login first if we have that saved
	if ([[NSUserDefaults standardUserDefaults] objectForKey:@"pass"] != nil) {
        
        // Well our session expired, try login again.
        NSString *login = [[NSUserDefaults standardUserDefaults] objectForKey:@"login"];
        NSString *password = [[NSUserDefaults standardUserDefaults] objectForKey:@"pass"];
        
        [self userLogin:[login DecryptHashWithSalt:kUSalt] withPassword:[password DecryptHashWithSalt:kUSalt]
				success:^(Webcall *master) {
					if ([master returnCode] == kUOperationOk) {
						resultBlock(YES);
					} else {
						if (_tryReconnect <= kUMaxReconnection) {
							// Failed again :/
							[self reconnectAfterSessionExpire:resultBlock];
						} else {
							resultBlock(NO);
						}
					}
				} failure:^(NSError *error) {
					resultBlock(NO);
				}];
		
    } else if ([[NSUserDefaults standardUserDefaults] objectForKey:@"token_facebook"] != nil) {
        [self userFacebookLogin:[[[FBSession activeSession] accessTokenData] accessToken]
                        success:^(Webcall *master) {
                            if ([master returnCode] == kUOperationOk) {
                                resultBlock(YES);
                            } else {
                                if (_tryReconnect <= kUMaxReconnection) {
                                    [self reconnectAfterSessionExpire:resultBlock];
                                } else {
                                    resultBlock(NO);
                                }
                            }
                        }
                        failure:^(NSError *error) {
                            resultBlock(NO);
                        }];
    }
}

@end