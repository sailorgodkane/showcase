//
//  Created by Jimmy De Pauw on 19/07/12.
//

#import "cflatconst.h"
#import "UConstants.h"
#import "FramegrabberController.h"
#import "AVFoundation/AVFoundation.h"

/*
 *	Notification
 */
NSString * const kUNotificationEpiphanPreviewImageAvailable = @"kUNotificationEpiphanPreviewImageAvailable";
NSString * const kUEpiphanFeedNotificationContext = @"kUEpiphanFeedNotificationContext";

@implementation FramegrabberController

- (id)init
{
    self = [super init];
    if (self) {
		FrmGrab_Init();
		epiphan = NULL;
		detectionInterval = [[NSTimer scheduledTimerWithTimeInterval:kUEpiphanDetectionInterval target:self selector:@selector(detectorLoop:) userInfo:nil repeats:YES] retain];
    }
    return self;
}

- (void)dealloc
{	
	if (NULL != epiphan) {
		FrmGrab_Close(epiphan);
	}
	
	FrmGrab_Deinit();
    [super dealloc];
}

- (void)cleanupTimer
{
	[detectionInterval invalidate];
	[detectionInterval release];
	detectionInterval = nil;
}

- (void)requestFrame
{
	@autoreleasepool {		
		V2U_GrabFrame2 *capturedFrame = NULL;
				
		capturedFrame = FrmGrab_Frame(epiphan, V2U_GRABFRAME_FORMAT_ARGB32, NULL);
		
		if (capturedFrame && capturedFrame->imagelen > 0)  {
			
			CVPixelBufferRef pixel_buffer = NULL;
			NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:(id)kCVPixelBufferCGImageCompatibilityKey];
			CVPixelBufferCreateWithBytes(kCFAllocatorDefault, videoMode.width, videoMode.height, kCVPixelFormatType_32ARGB, capturedFrame->pixbuf, 4*videoMode.width, NULL ,0 ,(CFDictionaryRef)options, &pixel_buffer);
			CVPixelBufferLockBaseAddress(pixel_buffer,0);
			
			// Get information about the image
			uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixel_buffer);
			size_t width = CVPixelBufferGetWidth(pixel_buffer);
			size_t height = CVPixelBufferGetHeight(pixel_buffer);
			
			// Create a CGImageRef from the CVImageBufferRef
			CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB(); 
			CGContextRef newContext = CGBitmapContextCreate(baseAddress, width, height, 8, CVPixelBufferGetBytesPerRow(pixel_buffer), colorSpace, (kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedFirst));
			CGImageRef newImage = CGBitmapContextCreateImage(newContext);
			
			NSImage *imageOutput = [[NSImage alloc] initWithCGImage:newImage size:CGSizeMake(videoMode.width, videoMode.height)];
			
			//We release some components
			CGImageRelease(newImage);
			CGContextRelease(newContext); 
			CGColorSpaceRelease(colorSpace);
			CVPixelBufferRelease(pixel_buffer);
			
			// The image is sent using a notification, post it with the image as the notification object
			[[NSNotificationCenter defaultCenter] postNotificationName:kUNotificationEpiphanPreviewImageAvailable object:self userInfo:[NSDictionary dictionaryWithObject:imageOutput forKey:kUNotificationPreviewImageData]];
			[imageOutput release];
		}
	
		FrmGrab_Release(epiphan, capturedFrame);
	}
}

#pragma mark - Timer

- (void)detectorLoop:(NSTimer*)timer
{	
	int deviceCount = FrmGrabLocal_Count();
	if (deviceCount == 0) {
		[self setVideoFeed:NO];
		if (NULL != epiphan) {
			FrmGrab_Close(epiphan);
			epiphan = NULL;
		}
	} else {
		if (NULL == epiphan) {
			epiphan = FrmGrabLocal_Open();
		}
		
		FrmGrab_DetectVideoMode(epiphan, &videoMode);
		
		if ( (videoMode.width != 0) && (videoMode.height != 0) && (videoMode.vfreq != 0) ) {
			[self setVideoFeed:YES];
		} else {
			[self setVideoFeed:NO];
		}
	}
}

@end