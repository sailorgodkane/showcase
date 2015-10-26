//
//  Created by Jimmy De Pauw on 12/04/12.
//

#import <Foundation/Foundation.h>
#import "cflatconst.h"
#import "UError.h"
#import "ASLLogging.h"

// Struct for everthing we need to connect a remote socket
typedef struct kUNDRemote
{
	CFReadStreamRef socketReadStream;
	CFWriteStreamRef socketWriteStream;
	id mainself;
	
} kUNDRemote;

/*
 *	Protocol
 */
@class UNDRemoteSocket;
@protocol UNDRemoteSocketDelegate <NSObject>
@optional
// Everything is ready
- (void)hasFinishedPreparing:(UNDRemoteSocket*)remoteSocket;
// Everything is ready
- (void)hasFailedPreparing:(UNDRemoteSocket*)remoteSocket withError:(NSError*)error;
// Remote server send some data
- (void)hasDataAvailable:(UNDRemoteSocket*)remoteSocket withData:(UInt8*)buffer ofLength:(CFIndex)length;
@end

/*
 *	Main object
 */
@interface UNDRemoteSocket : NSObject {
	kUNDRemote *remoteServer;
	BOOL writingOperationShouldPursue;
}

@property (assign) id <UNDRemoteSocketDelegate> delegate;
@property (readwrite) unsigned int portNumber;
@property (retain) NSString *hostAddr;

// Initiate the preparation
- (BOOL)prepareWithAddress:(NSString*)address andPort:(NSNumber*)port;

// Send a payload to the remote server
- (BOOL)writeBufferContent:(UInt8*)buf ofSize:(CFIndex)length;

// Log a sent command
- (void)logSentCommand:(char*)cmd;

@end
