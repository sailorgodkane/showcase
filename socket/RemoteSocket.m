//
//  Created by Jimmy De Pauw on 12/04/12.
//

#include <netdb.h>
#import "RemoteSocket.h"
#import "LibSockets.h"

// Private
@interface RemoteSocket (RemoteSocket_Private)
- (void)reportFailureWithError:(NSError*)error;
@end

/*
 *	Public
 */
@implementation RemoteSocket
@synthesize delegate, portNumber, hostAddr;

#pragma mark - Socket callback

/*
 *	Callback function called when the remote server send us data
 */
static void remoteReadCallback (CFReadStreamRef stream, CFStreamEventType event, void *info)
{
	kURemote *remoteServer = info;
	RemoteSocket *mainself = remoteServer->mainself;
	
	switch (event) {			
		case kCFStreamEventOpenCompleted:
			if ([mainself.delegate respondsToSelector:@selector(hasFinishedPreparing:)]) {
				[mainself.delegate hasFinishedPreparing:mainself];
			}
			break;
			
		case kCFStreamEventHasBytesAvailable: {
			
			// Bytes available, safe to read
			UInt8 *bufferRead = malloc(kUSocketStreamBuffer * sizeof(UInt8));
			bzero(bufferRead, kUSocketStreamBuffer);
			
			CFIndex bytesRead = CFReadStreamRead(stream, bufferRead, kUSocketStreamBuffer);
			
			if (bytesRead > 0) {
				// Get rid of special characters at the end of the buffer
				if (bufferRead[bytesRead-1] == '\r' || bufferRead[bytesRead-1] == '\n') {
					bufferRead[bytesRead-1] = '\0';
				}
				
				if (bufferRead[bytesRead-2] == '\r' || bufferRead[bytesRead-2] == '\n') {
					bufferRead[bytesRead-2] = '\0';
				}
				
				if ([mainself.delegate respondsToSelector:@selector(hasDataAvailable:withData:ofLength:)]) {
					[mainself.delegate hasDataAvailable:mainself withData:bufferRead ofLength:bytesRead];
				}
			}
			
			free(bufferRead);
			
			break;
		}
			
		// Got an error, treat it and close everyting
		case kCFStreamEventErrorOccurred: {
			CFErrorRef error = CFReadStreamCopyError(stream);
			[UError throwASLError:[UError errorWithCFError:error code:kUErrorSocketReadOpenFailure userInfo:nil functionCall:@"remoteReadCallback()"]];
			CFRelease(error);
			
			NSError *err = [UError errorWithErrorCode:kUErrorSocketReadOpenFailure userInfo:[NSDictionary dictionaryWithObject:[mainself hostAddr] forKey:kUErrorHostThatFail]];
			[mainself reportFailureWithError:err];
			break;
		}
			
		default:
			break;
	}
}

/*
 *	Callback function called when the write socket is ok to accept bytes
 */
static void remoteWriteCallback (CFWriteStreamRef stream, CFStreamEventType event, void *info)
{	
	kURemote *remoteServer = info;
	RemoteSocket *mainself = remoteServer->mainself;
	
	switch (event) {
		case kCFStreamEventCanAcceptBytes: {
			// We only need this to be called once, unregister the callback and runloop
			CFWriteStreamUnscheduleFromRunLoop(stream, [[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
			CFWriteStreamSetClient(stream, kCFStreamEventNone, NULL, NULL);
			
			if (!CFReadStreamOpen(remoteServer->socketReadStream)) {
				NSError *err = [UError errorWithErrorCode:kUErrorSocketReadOpenFailure userInfo:[NSDictionary dictionaryWithObject:[mainself hostAddr] forKey:kUErrorHostThatFail]];
				[mainself reportFailureWithError:err];
			}
			break;
		}
			
			// Got an error, treat it and close everyting
		case kCFStreamEventErrorOccurred: {
			NSDictionary *host = [NSDictionary dictionaryWithObject:[mainself hostAddr] forKey:kUErrorHostThatFail];
			
			CFErrorRef error = CFWriteStreamCopyError(stream);
			[UError throwASLError:[UError errorWithCFError:error code:kUErrorSocketWriteOpenFailure userInfo:nil functionCall:@"remoteWriteCallback()"]];
			CFRelease(error);
			
			NSError *err = [UError errorWithErrorCode:kUErrorSocketWriteOpenFailure userInfo:host];
			[mainself reportFailureWithError:err];
			break;
		}
			
		default:
			break;
	}
}

- (void)createSocketPair:(CFHostRef)host
{
	int errorCode = -1;
	
	CFStreamCreatePairWithSocketToCFHost(kCFAllocatorDefault, host, self.portNumber, &remoteServer->socketReadStream, &remoteServer->socketWriteStream);
	
	if (NULL == remoteServer->socketReadStream) {
		errorCode = kUErrorSocketReadOpenFailure;
	} else if (NULL == remoteServer->socketWriteStream) {
		errorCode = kUErrorSocketWriteOpenFailure;
	} else {
		CFStreamClientContext contextRef = {0, remoteServer, NULL, NULL, NULL };
		// Register the stream on the daemon runLoop
		if (CFReadStreamSetClient(remoteServer->socketReadStream, (kCFStreamEventOpenCompleted | kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered), remoteReadCallback, &contextRef)) {
			CFReadStreamScheduleWithRunLoop(remoteServer->socketReadStream, [[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
		}
		if (CFWriteStreamSetClient(remoteServer->socketWriteStream, (kCFStreamEventCanAcceptBytes | kCFStreamEventErrorOccurred), remoteWriteCallback, &contextRef)) {
			CFWriteStreamScheduleWithRunLoop(remoteServer->socketWriteStream, [[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
		}
		
		if (!CFWriteStreamOpen(remoteServer->socketWriteStream)) errorCode = kUErrorSocketWriteOpenFailure;
	}
	
	if (errorCode > -1) {
		NSError *err = [UError errorWithErrorCode:errorCode userInfo:[NSDictionary dictionaryWithObject:self.hostAddr forKey:kUErrorHostThatFail]];
		[self reportFailureWithError:err];
	}
}

#pragma mark - Init/Dealloc

- (id)init
{
    self = [super init];
    if (self) {
        remoteServer = malloc(sizeof(kUNDRemote));
		remoteServer->mainself = self;
		remoteServer->socketReadStream = NULL;
		remoteServer->socketWriteStream = NULL;
    }
    return self;
}

- (void)dealloc
{
	[self cleanupSockets];
	remoteServer->mainself = nil;
	
    free(remoteServer);
	[hostAddr release];
	
    [super dealloc];
}

- (void)cleanupSockets
{
	writingOperationShouldPursue = NO;
	
	if (NULL != remoteServer->socketReadStream) {
		fCleanupReadStream(remoteServer->socketReadStream);
		remoteServer->socketReadStream = NULL;
	}
	if (NULL != remoteServer->socketWriteStream) {
		fCleanupWriteStreamFromLoop(remoteServer->socketWriteStream);
		remoteServer->socketWriteStream = NULL;
	}
}

#pragma mark - Private

- (void)reportFailureWithError:(NSError*)error
{	
	[self cleanupSockets];
	
	if ([self.delegate respondsToSelector:@selector(hasFailedPreparing:withError:)]) {
		[self.delegate hasFailedPreparing:self withError:error];
	}
}

#pragma mark - Methods

- (BOOL)prepareWithAddress:(NSString*)address andPort:(NSNumber*)port
{	
	[self cleanupSockets];
	
	self.portNumber = [port intValue];
	self.hostAddr = address;
	
	CFStringRef coreAddress = CFStringCreateCopy(kCFAllocatorDefault, (CFStringRef)address);

	CFHostRef host = (CFHostRef)NSMakeCollectable(CFHostCreateWithName(kCFAllocatorDefault, coreAddress));
	CFRelease(coreAddress);
	
	[self createSocketPair:host];
	
	CFRelease(host);
	
	return YES;
}

- (BOOL)writeBufferContent:(UInt8*)buf ofSize:(CFIndex)length
{
	writingOperationShouldPursue = YES;
	BOOL finished = NO;
	
	// Copy the buffer so this method can alter it. Trying to alter the buffer directly would cause a crash.
	UInt8 *bufferCopy = (UInt8*)malloc(length);
	memcpy(bufferCopy, buf, length);
	
	CFIndex bufLen = length;
	
	while (!finished && writingOperationShouldPursue) {
		CFIndex bytesWritten = CFWriteStreamWrite(remoteServer->socketWriteStream, bufferCopy, bufLen);
		
		if (bytesWritten < 0) {
			CFErrorRef streamErr = CFWriteStreamCopyError(remoteServer->socketWriteStream);
			[UError throwASLError:[UError errorWithCFError:streamErr code:kUErrorGeneralWriteStream userInfo:nil functionCall:@"CFWriteStreamWrite()"]];
			CFRelease(streamErr);
			
			free(bufferCopy);
			
			return NO;
			
		} else if (bytesWritten == bufLen) {
			
			finished = YES;
			
		} else if (bytesWritten != bufLen) {
			// Determine how much has been written and adjust the buffer
			bufLen = bufLen - bytesWritten;
			memmove(bufferCopy, bufferCopy + bytesWritten, bufLen);
		}
	}
	
	free(bufferCopy);
	
	return finished;
}

- (void)logSentCommand:(char*)cmd
{	
	NSString *command = [NSString stringWithCString:cmd encoding:NSUTF8StringEncoding];
	NSString *sub = [command substringToIndex:[command length]-2];
	[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Sending command : %s",[sub UTF8String]];
}

@end