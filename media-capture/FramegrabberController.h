//
//  UNDFramegrabberController.h
//  UNDUnicast
//
//  Created by Jimmy De Pauw on 19/07/12.
//  Copyright (c) 2012 Underside. All rights reserved.
//

/*
 *	Notification
 */
extern NSString * const kUNotificationEpiphanPreviewImageAvailable;
extern NSString * const kUEpiphanFeedNotificationContext;

#import <Foundation/Foundation.h>
#include "frmgrab.h"

@interface FramegrabberController : NSObject {
	// Reference to the hardware
	FrmGrabber *epiphan;
	
	// Structure with the output resolution
	V2U_VideoMode videoMode;
	
	// How regular the status will be verified
	NSTimer *detectionInterval;
}

// Call it BEFORE releasing this object
- (void)cleanupTimer;

// Request a preview frame, NSThreaded!
- (void)requestFrame;

// KVO boolean you can observe to know if the epiphan state has changed
@property (readwrite) BOOL videoFeed;

@end