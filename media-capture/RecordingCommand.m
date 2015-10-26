//
//  Created by Jimmy De Pauw on 26/03/12.
//

#import "CommandController.h"
#import "RecordingCommand.h"
#import "UError.h"
#import "SharedConstants.h"
#import "ExternalUploader.h"
#import <QTKit/QTKit.h>

static RecordingCommand *recordingCommand = nil;

/*
 *	Private
 */
@interface RecordingCommand (RecordingCommand_Private)
// Get quality from configuration and set the preset to AVCaptureSession object
- (BOOL)defineCaptureSessionPreset:(NSString*)qua;

// Init input devices
- (BOOL)attachInputDeviceID:(NSString*)deviceID ofType:(NSString*)deviceType error:(NSError**)error;

// Get local path from configuration, create a GUID directory (if necessary) and append the file name
// Check for disk error
- (BOOL)defineRecordingFilePath;

// Initialize the capture session
- (BOOL)configureCaptureSessionForInput:(kURecordingMode)mode error:(NSError**)error;

// Clean the capture session
- (void)deconfigureCameraAndFileOutput;

// Report recording error
- (void)endOfRecordingErrorReportForFile:(NSString*)fileUrl error:(NSError*)error;

// Properly stop a recording session
- (void)finalizeRecordingSessions;

// easy way to post a notification
- (void)postRecordingNotificationNamed:(NSString*)notificationName withMessage:(NSString*)message;
@end

/*
 *	Main
 */
@implementation RecordingCommand

@synthesize jobuuid, subsequentJobuuid, basePath, recordingStartDate, lastMessage, lastReceivedCommand, timeoutTimer, connectionId;

#pragma mark - Singleton

+ (id)recordingManager {
    @synchronized(self) {
        if(recordingCommand == nil) recordingCommand = [[super allocWithZone:NULL] init];
    }
    return recordingCommand;
}

+ (id)allocWithZone:(NSZone *)zone { return [[self recordingManager] retain]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (id)retain { return self; }
- (NSUInteger)retainCount { return UINT_MAX; /*denotes an object that cannot be released*/ }
- (oneway void)release { /* never release*/ }
- (id)autorelease { return self; }

#pragma mark - Init/Dealloc

- (void)fullSingletonCleanup
{
	if (movieOutput) {
		[movieOutput release];
		movieOutput = nil;
	}
	
	if (captureSession) {
		[captureSession release];
		captureSession = nil;
	}
	
	if (timeoutTimer) {
		[timeoutTimer invalidate];
		[timeoutTimer release];
		timeoutTimer = nil;
	}

	[lastMessage release];
	lastMessage = nil;
	
	[recordingStartDate release];
	recordingStartDate = nil;
	
	[jobuuid release];
	jobuuid = nil;
	
	[subsequentJobuuid release];
	subsequentJobuuid = nil;
	
	[basePath release];
	basePath = nil;
	
	[lastReceivedCommand release];
	lastReceivedCommand = nil;
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
	// First segment means first start!
	if (recordingState == kURecordingStateIdle) {
		
		recordingState = kURecordingStateRunning;
		[self setRecordingStartDate:[NSDate date]];
		[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"[%s] Recording started to file : %s", [[self jobuuid] UTF8String], [[fileURL path] UTF8String]];
		
		[[NSFileManager defaultManager] createFileAtPath:[[[fileURL path] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@".recording.lock"] contents:[NSData data] attributes:nil];
		
		// Prepare and send the notification
		[self postRecordingNotificationNamed:kUNotificationRecordingDidStart withMessage:[NSString stringWithFormat:@"%d %d Recording to file : %@\n",kUCommandSuccess,kUVideoDaemonCommandStartRecording,[fileURL path]]];
		
	}
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput willFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections error:(NSError *)error
{	
	willErrorWasThrow = NO;	
	if (error != nil) {
		// Reset the recording state
		recordingState = kURecordingStateIdle;
		
		// Finalize in case of an error
		willErrorWasThrow = YES;
		[self endOfRecordingErrorReportForFile:[fileURL path] error:error];
	}
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{	
	const char *guid = [[self jobuuid] UTF8String];
	const char *file = [[outputFileURL path] UTF8String];
		
	// Determine if the recording was successfull
	// It may be okay even if an error was throwned, check for a key AVErrorRecordingSuccessfullyFinishedKey
	BOOL recordedSuccessfully = YES;
	if ([error code] != noErr) {
		id value = [[error userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey];
        if (value) recordedSuccessfully = [value boolValue];
	}
		
	if (recordedSuccessfully) {
		
		// Check for the recording status, did it stop because of a 'stop' or a 'pause' command ?
		if (recordingState == kURecordingStateStopping) {
			// This is for a stop!
			[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"[%s] Recording finished writing to file : %s", guid, file];
			[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"[%s] File size : %llu bytes", guid, movieOutput.recordedFileSize];
			[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"[%s] Movie duration : %f sec", guid, CMTimeGetSeconds(movieOutput.recordedDuration)];
			
			// Final actions
			[self finalizeRecordingSessions];
			
		}
		
	} else if (!willErrorWasThrow) {
		[self endOfRecordingErrorReportForFile:[outputFileURL path] error:error];
	}
		
	// Check if this stop result of a force stop or not
	// If it did then a new recording must be started immediately
	if (subsequentStart) {
		if (recMode == kURecordingModeVideoAudio) {
			[self startRecordingWithMode:kURecordingModeVideoAudio andUuid:[self subsequentJobuuid]];
		} else {
			[self startRecordingWithMode:kURecordingModeAudioPC andUuid:[self subsequentJobuuid]];
		}
	}
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didPauseRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
	recordingState = kURecordingStatePaused;
	
	[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"[%s] recording paused", [[self jobuuid] UTF8String]];
	[self postRecordingNotificationNamed:kUNotificationRecordingDidPause withMessage:[NSString stringWithFormat:@"%d %d Recording of file paused : %@\n",kUCommandSuccess,kUVideoDaemonCommandPauseRecording,[fileURL path]]];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didResumeRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
	recordingState = kURecordingStateResumed;
	// Other then first means resume!
	[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"[%s] recording resumed", [[self jobuuid] UTF8String]];
	
	// Prepare and send the notification
	[self postRecordingNotificationNamed:kUNotificationRecordingDidResume withMessage:[NSString stringWithFormat:@"%d %d Recording of file resumed : %@\n",kUCommandSuccess,kUVideoDaemonCommandResumeRecording,[fileURL path]]];
}

#pragma mark - Methods

- (void)startRecordingWithMode:(kURecordingMode)rec andUuid:(NSString*)uuid
{
	stoppedForCancelation = NO;
	recMode = rec;
	
	/*
		If a recording is active when a START command is received, stop properly the first one and start anew.
		No record should be lost!
	 */
	if ([self checkForActiveRecording]) {
		
		[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Received a new START while a recording is already active."];
		
		subsequentStart = YES;
		
		// If it was not finalized (like the session is paused) do the cleanup and uploading
		if (recordingState == kURecordingStatePaused) {
			recordingState = kURecordingStateStopping;
			[self finalizeRecordingSessions];
			
			[self setSubsequentJobuuid:uuid];
			
			if (recMode == kURecordingModeVideoAudio) {
				[self startRecordingWithMode:kURecordingModeVideoAudio andUuid:[self subsequentJobuuid]];
			} else {
				[self startRecordingWithMode:kURecordingModeAudioPC andUuid:[self subsequentJobuuid]];
			}
		} else {
			recordingState = kURecordingStateStopping;
			// Always stop so a new recording can start
			[movieOutput stopRecording];
			[self setSubsequentJobuuid:uuid];
		}
	
	} else {
		// reset flags
		subsequentStart = NO;
		recordingState = kURecordingStateIdle;
		
		// Set the recording timeout timer
		[self setTimeoutTimer:[NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(checkForTimeout:) userInfo:nil repeats:YES]];
		[self setJobuuid:uuid];
		
		NSError *error = nil;
		if (![self configureCaptureSessionForInput:recMode error:&error]) {
			
			[UError throwASLError:error];
			[self postRecordingNotificationNamed:kUNotificationRecordingDidFailInit withMessage:[NSString stringWithFormat:@"%ld %d %@\n",[error code], kUVideoDaemonCommandStartRecording, [error localizedDescription]]];
			
		} else {
			// Start recording video stream to a file
			[captureSession startRunning];
			
			BOOL hasDefinedOk = [self defineRecordingFilePath];
			NSString *filename = [[self basePath] stringByAppendingPathComponent:[NSString stringWithFormat:@"1-%@-camera.%@",uuid,(recMode==kURecordingModeAudioPC)?@"m4a":@"mov"]];
			
			if (!hasDefinedOk) {
				NSError *error = [UError errorWithErrorCode:kUErrorVidCheckDestFolder userInfo:[NSDictionary dictionaryWithObject:filename forKey:kUErrorFilePath]];
				[UError throwASLError:error];
				[self postRecordingNotificationNamed:kUNotificationRecordingDidFailInit withMessage:[NSString stringWithFormat:@"%ld %d %@\n",[error code], kUVideoDaemonCommandStartRecording, [error localizedDescription]]];
			} else {
				[movieOutput setMovieFragmentInterval:CMTimeMake(20, 1)];
				[movieOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:filename] recordingDelegate:self];
			}
		}
	}
}

- (void)cancelActiveRecording
{
	subsequentStart = NO;
	stoppedForCancelation = YES;
	
	// Properly terminate recording if any
	if ([movieOutput isRecording]) {
		[timeoutTimer invalidate];
		[timeoutTimer release];
		timeoutTimer = nil;
		
		recordingState = kURecordingStateStopping;
		
		[movieOutput stopRecording];
	}
	
	// If it was not finalized (like the session is paused) do the cleanup and uploading
	if (recordingState == kURecordingStatePaused) {
		recordingState = kURecordingStateStopping;
		[self finalizeRecordingSessions];
	}
}

- (kUCommandReturnValue)stopActiveRecording
{	
	subsequentStart = NO;
	
	// Properly terminate recording if any
	if ([movieOutput isRecording]) {
		[timeoutTimer invalidate];
		[timeoutTimer release];
		timeoutTimer = nil;

		recordingState = kURecordingStateStopping;
		
		[movieOutput stopRecording];
		return kUCommandSuccess;
	}
	
	// If it was not finalized (like the session is paused) do the cleanup and uploading
	if (recordingState == kURecordingStatePaused) {
		
		recordingState = kURecordingStateStopping;
		
		[self finalizeRecordingSessions];
		
		return kUCommandSuccess;
	}

	[self setLastMessage:[NSString stringWithFormat:@"%d %d Nothing to stop\n", kUCommandSuccess, kUVideoDaemonCommandStopRecording]];
	return kUCommandNothingToStop;
}

- (kUCommandReturnValue)pauseActiveRecording
{	
	if ([movieOutput isRecording]) {
		[movieOutput pauseRecording];
		return kUCommandSuccess;
	}
	
	[self setLastMessage:[NSString stringWithFormat:@"%d %d Nothing to pause\n", kUCommandSuccess, kUVideoDaemonCommandPauseRecording]];
	return kUCommandNothingToPause;
}

- (kUCommandReturnValue)resumeActiveRecording
{
	if ((recordingState == kURecordingStatePaused) && ([movieOutput isRecordingPaused])) {
		[movieOutput resumeRecording];
		return kUCommandSuccess;
	}
	
	[self setLastMessage:[NSString stringWithFormat:@"%d %d Nothing to resume\n", kUCommandSuccess, kUVideoDaemonCommandResumeRecording]];
	return kUCommandNothingToResume;
}

- (BOOL)checkForActiveRecording
{
	BOOL val = ( recordingState != kURecordingStateIdle );
	if (val) {
		[self setLastMessage:[NSString stringWithFormat:@"%d %d Recording\n",kUCommandSuccess,kUVideoDaemonCommandStatusRecording]];
	} else {
		[self setLastMessage:[NSString stringWithFormat:@"%d %d Error\n",kUErrorDuringRecording,kUVideoDaemonCommandStatusRecording]];
	}
	
	return val;
}

#pragma mark - Private

- (BOOL)configureCaptureSessionForInput:(kURecordingMode)mode error:(NSError**)error
{	
	// Setup session coordinator
	captureSession = [[AVCaptureSession alloc] init];
	
	recMode = mode;
	
	NSDictionary *recOptions = [[UConfiguration configurationManager] recordingQualityOptions];
	BOOL usePreset = [[recOptions objectForKey:@"UseFrameworkPreset"] boolValue];
	
	BOOL presetReturn = (usePreset) ? [self defineCaptureSessionPreset:[recOptions objectForKey:@"PresetQuality"]] : [self defineCaptureSessionPreset:@"Medium"];
	if (!presetReturn) {
		*error = [UError errorWithErrorCode:kUErrorVidSessionInit userInfo:nil];
		return NO;
	}
	
	// Setup ouput object
	movieOutput = [[AVCaptureMovieFileOutput alloc] init];
	if ([captureSession canAddOutput:movieOutput]) {
		[captureSession addOutput:movieOutput];
	} else {
		*error = [UError errorWithErrorCode:kUErrorVidOutputInit userInfo:nil];
		return NO;
	}
	
	if (recMode == kURecordingModeVideoAudio) {
		// Setup video input
		if (![self attachInputDeviceID:[[Configuration configurationManager] deviceUniqueIDToUse] ofType:AVMediaTypeVideo error:error]) {
			return NO;
		}
	}
	
	// Set FPS
	AVCaptureConnection *videoConnection = [movieOutput connectionWithMediaType:AVMediaTypeVideo];
	if (videoConnection.supportsVideoMinFrameDuration) {
		int FPS = [[recOptions objectForKey:@"OutputVideoMaxFPS"] intValue];
		videoConnection.videoMinFrameDuration = CMTimeMake(1, FPS);
	}
	
	if (!usePreset) {
		[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Preset is not to be used, creating custom recording options"];
		
		NSDictionary *custom = [recOptions objectForKey:@"CustomCodecSettings"];
		
		NSDictionary *videoColor = nil;
		if ([recOptions objectForKey:@"OutputColorMode"]) {
			
			if ([[recOptions objectForKey:@"OutputColorMode"] isEqualToString:@"HD"]) {
				
				[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Use HD color preset."];
				videoColor = [NSDictionary dictionaryWithObjectsAndKeys:
							  AVVideoColorPrimaries_ITU_R_709_2, AVVideoColorPrimariesKey,
							  AVVideoTransferFunction_ITU_R_709_2, AVVideoTransferFunctionKey,
							  AVVideoYCbCrMatrix_ITU_R_709_2, AVVideoYCbCrMatrixKey, nil];
				
			} else if ([[recOptions objectForKey:@"OutputColorMode"] isEqualToString:@"SD_PAL"]) {
				
				[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Use SD_PAL color preset."];
				videoColor = [NSDictionary dictionaryWithObjectsAndKeys:
							  AVVideoColorPrimaries_EBU_3213, AVVideoColorPrimariesKey,
							  AVVideoTransferFunction_ITU_R_709_2, AVVideoTransferFunctionKey,
							  AVVideoYCbCrMatrix_ITU_R_601_4 , AVVideoYCbCrMatrixKey, nil];
				
			} else if ([[recOptions objectForKey:@"OutputColorMode"] isEqualToString:@"SD"]) {
				
				[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Use SD color preset."];
				videoColor = [NSDictionary dictionaryWithObjectsAndKeys:
							  AVVideoColorPrimaries_SMPTE_C, AVVideoColorPrimariesKey,
							  AVVideoTransferFunction_ITU_R_709_2, AVVideoTransferFunctionKey,
							  AVVideoYCbCrMatrix_ITU_R_601_4 , AVVideoYCbCrMatrixKey, nil];
			}
			
		} else
			[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Use detected source color preset."];
			
		
		NSDictionary *videoCleanApertureSettings = [NSDictionary dictionaryWithObjectsAndKeys:
													[custom objectForKey:@"OutputVideoWidth"], AVVideoCleanApertureWidthKey,
													[custom objectForKey:@"OutputVideoHeight"], AVVideoCleanApertureHeightKey,
													[NSNumber numberWithInt:0], AVVideoCleanApertureHorizontalOffsetKey,
													[NSNumber numberWithInt:0], AVVideoCleanApertureVerticalOffsetKey, nil];
		
		NSDictionary *videoAspectRatioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
												  [NSNumber numberWithInt:5], AVVideoPixelAspectRatioHorizontalSpacingKey,
												  [NSNumber numberWithInt:5], AVVideoPixelAspectRatioVerticalSpacingKey, nil];
		
		NSDictionary *compressions = [NSDictionary dictionaryWithObjectsAndKeys:
									  [custom objectForKey:@"OutputVideoBitrate"], AVVideoAverageBitRateKey,
									  AVVideoProfileLevelH264HighAutoLevel, AVVideoProfileLevelKey,
									  @NO, AVVideoAllowFrameReorderingKey,						      // 10.10
									  [NSNumber numberWithInt:25], AVVideoExpectedSourceFrameRateKey, // 10.10
									  [NSNumber numberWithInt:30], AVVideoMaxKeyFrameIntervalKey, nil];
		
		NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObjectsAndKeys:
								 AVVideoCodecH264, AVVideoCodecKey,
								 [custom objectForKey:@"OutputVideoWidth"], AVVideoWidthKey,
								 [custom objectForKey:@"OutputVideoHeight"], AVVideoHeightKey,
								 [custom objectForKey:@"OutputVideoScalingMode"], AVVideoScalingModeKey,
								 videoAspectRatioSettings, AVVideoPixelAspectRatioKey,
								 videoCleanApertureSettings, AVVideoCleanApertureKey,
								 compressions, AVVideoCompressionPropertiesKey, nil];
		
		if (videoColor != nil) {
			[options setObject:videoColor forKey:AVVideoColorPropertiesKey];
		}
		
		[movieOutput setOutputSettings:options forConnection:videoConnection];
	
	}
	
	if (usePreset) {
		[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Using preset"];
		[movieOutput setOutputSettings:[NSDictionary dictionary] forConnection:videoConnection];
	}
	
	// Setup audio input
	if (![self attachInputDeviceID:[[Configuration configurationManager] audioDeviceUniqueIDToUse] ofType:AVMediaTypeAudio error:error]) {
		return NO;
	}
	
	NSDictionary *findOpts = [movieOutput outputSettingsForConnection:videoConnection];
	
	[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Settings currently attached =>"];
	[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"%s", [[findOpts description] UTF8String]];
	
	return YES;
}

- (void)deconfigureCameraAndFileOutput
{	
	[movieOutput release];
	movieOutput = nil;
	[captureSession release];
	captureSession = nil;
}

- (void)postRecordingNotificationNamed:(NSString*)notificationName withMessage:(NSString*)message
{
	[self setLastMessage:message];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLong:connectionId], kUNotificationConnectionId, [self lastMessage], kUNotificationOutputMessage, nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:self userInfo:userInfo];
}

- (void)finalizeRecordingSessions
{
	[captureSession stopRunning];
	[self deconfigureCameraAndFileOutput];
	
	// Don't go ay further if it was canceled
	if (!stoppedForCancelation) {
		[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"[%s] Recording session finished", [[self jobuuid] UTF8String]];
		
		if (recordingState == kURecordingStateStopping) {		
			// Wether an error occured or not, if a video file was created it must be sent to the server
			[self mergeAndUploadSegment];
		}
		
		recordingState = kURecordingStateIdle;
		
		if (!subsequentStart) {
			[self postRecordingNotificationNamed:kUNotificationRecordingDidStop withMessage:[NSString stringWithFormat:@"%d %d Stopped recording session\n",kUCommandSuccess,kUVideoDaemonCommandStopRecording]];
		}
	}
	
	recordingState = kURecordingStateIdle;
}

- (void)endOfRecordingErrorReportForFile:(NSString*)fileUrl error:(NSError*)error
{	
	recordingState = kURecordingStateIdle;
	[[ASLLogging loggingManager] logthis:ASL_LEVEL_ERR andFormat:@"[%s] Recording to file : %s failed with error %d %s", [[self jobuuid] UTF8String], [fileUrl UTF8String], [error code], [[error localizedDescription] UTF8String]];
	
	// Merge
	[self mergeAndUploadSegment];
	
	// Don't warn for anything if this stop occured because of a subsequent start
	if (!subsequentStart) {
		[self postRecordingNotificationNamed:kUNotificationRecordingDidStop withMessage:[NSString stringWithFormat:@"%d %d %@\n",kUErrorDuringRecording,kUVideoDaemonCommandStopRecording,[error localizedDescription]]];
	}
	
	// Cleanup
	[self deconfigureCameraAndFileOutput];
}
 
- (BOOL)defineRecordingFilePath
{
	BOOL isDir;
	NSString *fPath = [NSString stringWithFormat:@"%@/%@",[[UConfiguration configurationManager] localCacheRepository],[self jobuuid]];
	if (![[NSFileManager defaultManager] fileExistsAtPath:fPath isDirectory:&isDir]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:fPath withIntermediateDirectories:YES attributes:nil error:nil];
	} else {
		if (!isDir) {
			return NO;
		}
	}

	[self setBasePath:fPath];
	
	return YES;
}


- (BOOL)defineCaptureSessionPreset:(NSString*)qua
{	
	// Default is medium
	NSString *preset = AVCaptureSessionPresetMedium;
	
	if ([qua isEqualToString:@"High"]) {
		preset = AVCaptureSessionPresetHigh;
	} else if ([qua isEqualToString:@"Medium"]) {
		preset = AVCaptureSessionPresetMedium;
	} else if ([qua isEqualToString:@"Low"]) {
		preset = AVCaptureSessionPresetLow;
	} else if ([qua isEqualToString:@"1280x720"]) {
		preset = AVCaptureSessionPreset1280x720;
	} else if ([qua isEqualToString:@"960x540"]) {
		preset = AVCaptureSessionPreset960x540;
	} else if ([qua isEqualToString:@"640x480"]) {
		preset = AVCaptureSessionPreset640x480;
	} else if ([qua isEqualToString:@"352x288"]) {
		preset = AVCaptureSessionPreset352x288;
	} else if ([qua isEqualToString:@"320x240"]) {
		preset = AVCaptureSessionPreset320x240;
	} else {
		preset = AVCaptureSessionPresetMedium;
	}
	
	if ([captureSession canSetSessionPreset:preset]) {
		[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Preset set to : %s", [preset UTF8String]];
		[captureSession setSessionPreset:preset];
	} else {
		return NO;
	}	
	
	return YES;
}

- (BOOL)attachInputDeviceID:(NSString*)deviceID ofType:(NSString*)deviceType error:(NSError **)error
{
	// Fetch device to use
	AVCaptureDevice *device = nil;
	if (!deviceID || ([deviceID length] == 0)) {
		
		// If configuration plist is incomplete try to use the first device that support video
		NSArray *devices = [AVCaptureDevice devicesWithMediaType:deviceType];
		if ([devices count] > 0) {
			device = [devices objectAtIndex:0];
			deviceID = [device uniqueID];
		} else {
			*error = [UError errorWithErrorCode:kUErrorVidInputNoVideo userInfo:nil];
			return NO;
		}
		
	} else {
		// Try to use the specified device ID found in configuration
		if (!(device = [AVCaptureDevice deviceWithUniqueID:deviceID])) {
			*error = [UError errorWithErrorCode:kUErrorVidInputNotFound userInfo:[NSDictionary dictionaryWithObject:deviceID forKey:kUErrorDeviceID]];
			return NO;
		}
	}
	
	[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"Detected device : %s (%s)",[[device localizedName] UTF8String], [deviceID UTF8String]];
	
	// Setup device input object
	NSError *errorInput = nil;
	AVCaptureDeviceInput *input = nil;
	if (!(input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&errorInput])) {
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:deviceID, kUErrorDeviceID, [device localizedName], kUErrorDeviceLocalName, errorInput, NSUnderlyingErrorKey, nil];
		*error = [UError errorWithErrorCode:kUErrorVidInputCannotInit userInfo:userInfo];
		return NO;
	}
	
	NSError *errorLock = nil;
	if (![device lockForConfiguration:&errorLock]) {
		NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:deviceID, kUErrorDeviceID, [device localizedName], kUErrorDeviceLocalName, nil];
		*error = [UError errorWithErrorCode:kUErrorVidInputCannotAdd userInfo:userInfo];
		return NO;
	}
	
	if ([deviceType isEqualToString:AVMediaTypeAudio]) {
		
		// No restriction for audio device, let the framework do the work
		if ([captureSession canAddInput:input]) {
			[captureSession addInput:input];
		} else {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:deviceID, kUErrorDeviceID, [device localizedName], kUErrorDeviceLocalName, nil];
			*error = [UError errorWithErrorCode:kUErrorVidInputCannotAdd userInfo:userInfo];
			return NO;
		}
	} else {
		
		// Input ports must be filtered to avoid conflict, add it without connection
		[captureSession addInputWithNoConnections:input];
		
		// Search on the device ports and extract the one we need
		NSMutableArray *videoPorts = [[NSMutableArray alloc] init];
		for (AVCaptureInputPort *port in [input ports]) {
			if ([[port mediaType] isEqualToString:@"vide"]) {
				[videoPorts addObject:port];
			}
		}
		
		AVCaptureConnection *inputConnection = [AVCaptureConnection connectionWithInputPorts:videoPorts output:movieOutput];
		
		if ([captureSession canAddConnection:inputConnection]) {
			[captureSession addConnection:inputConnection];
		} else {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:deviceID, kUErrorDeviceID, [device localizedName], kUErrorDeviceLocalName, nil];
			*error = [UError errorWithErrorCode:kUErrorVidInputCannotAdd userInfo:userInfo];
			return NO;
		}
		
		[videoPorts release];
	}
	
	[device unlockForConfiguration];

	return YES;
}

#pragma mark - FileMerging

// Start the thread that will merge the file
- (void)mergeAndUploadSegment
{
	// Remove the lock file
	[[NSFileManager defaultManager] removeItemAtPath:[basePath stringByAppendingPathComponent:@".recording.lock"] error:nil];
		
	[[ASLLogging loggingManager] logthis:ASL_LEVEL_NOTICE andFormat:@"[%s] No merging required, yosemite has not the pause/resume bug", [[self jobuuid] UTF8String]];
		
	// There is only one segment
	[[ExternalUploader defaultController] uploadForProjectUuid:[self jobuuid] andRecordingMode:recMode];
}

#pragma mark - Timer

- (void)checkForTimeout:(NSTimer*)timer
{
	// Abort current recording operation if any
	BOOL check = ( recordingState != kURecordingStateIdle );
	NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:[self lastReceivedCommand]];
		 
	if ( check && (interval > kUSocketTimeout) ) {
		[self stopActiveRecording];
		[[ASLLogging loggingManager] logthis:ASL_LEVEL_WARNING andFormat:@"A recording was stopped because of a timeout"];
	}
}

@end