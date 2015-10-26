//
//  Created by Jimmy De Pauw on 13/04/12.
//

#import "LibSockets.h"
#import "ASLLogging.h"
#import "UError.h"

void fRemoveSourceFromRunLoop(CFSocketRef socket)
{
	CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, socket, 0);
	CFRunLoopRemoveSource([[NSRunLoop mainRunLoop] getCFRunLoop], source, kCFRunLoopDefaultMode);	
	CFRelease(source);
	
	CFSocketInvalidate(socket);
	CFRelease(socket);
	
	socket = NULL;
}

void fCleanupReadStream(CFReadStreamRef stream)
{
	CFReadStreamUnscheduleFromRunLoop(stream, [[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
	CFReadStreamSetClient(stream, kCFStreamEventNone, NULL, NULL);
	CFReadStreamClose(stream);	
	CFRelease(stream);
	
	stream = NULL;
}

void fCleanupWriteStream(CFWriteStreamRef stream)
{	
	CFWriteStreamClose(stream);
	CFRelease(stream);
	
	stream = NULL;
}

void fCleanupWriteStreamFromLoop(CFWriteStreamRef stream)
{	
	CFWriteStreamUnscheduleFromRunLoop(stream, [[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
	CFWriteStreamSetClient(stream, kCFStreamEventNone, NULL, NULL);
	CFWriteStreamClose(stream);
	CFRelease(stream);
	
	stream = NULL;
}

void fCleanupHostResolution(CFHostRef host)
{	
	CFHostUnscheduleFromRunLoop(host, [[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
	CFHostSetClient(host, NULL, NULL);
	host = NULL;
}

BOOL fWriteBufferContent(UInt8 *buf, CFIndex length, CFWriteStreamRef stream)
{		
	BOOL finished = NO;
	
	// Copy the buffer so this method can alter it.
	UInt8 *bufferCopy = (UInt8*)malloc(length);
	memcpy(bufferCopy, buf, length);
	
	CFIndex bufLen = length;
	
	while (!finished) {
		CFIndex bytesWritten = CFWriteStreamWrite(stream, bufferCopy, bufLen);

		if (bytesWritten < 0) {
			CFErrorRef streamErr = CFWriteStreamCopyError(stream);
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
	
	return YES;
}