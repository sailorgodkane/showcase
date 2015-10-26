//
//  Created by Jimmy De Pauw on 26/03/12.
//

#import <Foundation/Foundation.h>
#import "AVFoundation/AVFoundation.h"

/*
 *	Main object
 */
@interface RecordingCommand : NSObject <AVCaptureFileOutputRecordingDelegate> {
	// Recording objects
	AVCaptureMovieFileOutput *movieOutput;
	AVCaptureSession *captureSession;
	
	// Identify the recording mode
	kURecordingMode recMode;
	
	// Has a start recording command received while a recording was already started
	BOOL subsequentStart;
	
	// To avoid the same error being reported twice in the captureOutput delegate
	BOOL willErrorWasThrow;
	
	// Stopped because of a cancel request ?
	BOOL stoppedForCancelation;
	
	// Number of segments / files recorded
	//NSInteger recordingSegments;
	
	// How is the recording ? 
	kURecordingState recordingState;
}

+ (id)recordingManager;

// Start the recording after receiving the "START_AUDIO_RECORDING [UUID]" | "START_RECORDING [UUID]" command
- (void)startRecordingWithMode:(kURecordingMode)rec andUuid:(NSString*)uuid;

// Cancel the recording after receiving the "CANCEL_RECORDING" command
- (void)cancelActiveRecording;

// Stop the recording after receiving the "STOP_RECORDING" command
- (kUCommandReturnValue)stopActiveRecording;

// Pause the recording after receiving the "PAUSE_RECORDING" command
- (kUCommandReturnValue)pauseActiveRecording;

// Resume the recording after receiving the "RESUME_RECORDING" command
- (kUCommandReturnValue)resumeActiveRecording;

// Check if a recording is active after receiving the "status" command
- (BOOL)checkForActiveRecording;

- (void)fullSingletonCleanup;

// GUID that identify the record job
@property (retain) NSString *jobuuid;

// GUID that identify the record job resulting of a subsequent start
@property (retain) NSString *subsequentJobuuid;

// Full path of the recorded file
@property (retain) NSString *basePath;

// Will contain the real recording start date (not when the command was received)
@property (retain) NSDate *recordingStartDate;

// Will contain the last message
@property (retain) NSString *lastMessage;

// Used for the session timeout
@property (retain) NSDate *lastReceivedCommand;

// The timer that manage the timeout
@property (retain) NSTimer *timeoutTimer;

// Identify the connection id, used in UChilds to identify its position in the main dyn array
@property (readwrite) unsigned long int connectionId;

@end
