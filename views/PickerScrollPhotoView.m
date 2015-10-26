//
//  Created by De Pauw Jimmy on 25/04/14.
//

#import "PickerScrollPhotoView.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <CoreMotion/CoreMotion.h>
#import <AVFoundation/AVFoundation.h>
#import "LoadingAnimation.h"

@interface PickerScrollPhotoView () {
	// Motion variables
	double _currentMaxAccelY;
	double _newValX;
	int _reloadCount;
}
@property (strong, nonatomic) CMMotionManager *motionManager;
@property (assign) BOOL isChangingCamera;
@property(nonatomic, strong) AVAudioPlayer *clickSound;
@end

@implementation PickerScrollPhotoView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
		[self setup:frame];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setup:self.frame];
	}
	return self;
}

- (void)setup:(CGRect)frame
{	
	[self setBackgroundColor:[UIColor clearColor]];
	
	// Setup scroll view that will hold the image
	_scrollView = [[ImageScrollView alloc] initWithFrame:CGRectMake(0, 0, self.frame.size.width, self.frame.size.height)];
	_scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	
	// Setup scrollView
	[self addSubview:_scrollView];
	[self sendSubviewToBack:_scrollView];
	
	CGFloat heightToUse = (IS_IPHONE_5) ? kUSemiAlphaBarHeightPhone5 : kUSemiAlphaBarHeight;
	
	// Setup top bar
	_topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.frame.size.width, heightToUse)];
	[self.topBar setBackgroundColor:[UIColor clearColor]];
    [self.topBar setAlpha:0.5f];
	[self addSubview:self.topBar];
	
	// Setup bottom bar
	_bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.frame.size.height - heightToUse, self.frame.size.width, heightToUse)];
	[self.bottomBar setBackgroundColor:[UIColor clearColor]];
	[self.bottomBar setAlpha:0.5f];
	self.bottomBar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
	[self addSubview:self.bottomBar];
	
	// Setup center loading animation images
	CGRect loadingRect = CGRectMake(CGRectGetMidX(self.frame) - (kUDefaultLoadingAnimationWidth/2), CGRectGetMidY(self.frame) - (kUDefaultLoadingAnimationWidth/2), kUDefaultLoadingAnimationWidth, kUDefaultLoadingAnimationHeight);
	_loadingAnimation = [[LoadingAnimation alloc] initWithFrame:loadingRect];
	[_loadingAnimation setupLoadingAnimation];
	
	[self addSubview:_loadingAnimation];
	[self bringSubviewToFront:_loadingAnimation];
	
	_isChangingCamera = NO;
	_cameraIsReady = NO;
	
	// Options
	_allowChangeOfCameraByShaking = NO;
	_playSoundWhenCameraChanges = NO;
	_motionManager = [[CMMotionManager alloc] init];
}

- (void)setDisplayImage:(UIImage *)image
{
	NSInteger barHeight = kUSemiAlphaBarHeight*2;
	if (IS_IPHONE_5) {
		barHeight = kUSemiAlphaBarHeightPhone5*2;
	}
	
	// Check should we apply the inset
	BOOL setInset = YES;
	if ( (image.size.height >= (self.scrollView.frame.size.height-barHeight)) && (image.size.height < (self.scrollView.frame.size.height)) ) {
		setInset = NO;
	}
	
	[self.scrollView displayImage:image];
	
	//if (setInset) {
		// Set the image inside the scroll view, set the inset after so the inset is only applied when you move it
		if (IS_IPHONE_5) {
			[_scrollView setPaddingTop:kUSemiAlphaBarHeightPhone5 andBottom:kUSemiAlphaBarHeightPhone5];
		} else {
			[_scrollView setPaddingTop:kUSemiAlphaBarHeight andBottom:kUSemiAlphaBarHeight];
            [self.scrollView setContentOffset:CGPointMake(0, (self.scrollView.contentSize.height - self.scrollView.height) / 2)];
        }
	//}
}

- (BOOL)isPictureLargeEnough:(UIImage*)image
{
	return YES;
}

- (void)setupPicker
{
	// Camera ready notification
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cameraIsReady:) name:AVCaptureSessionDidStartRunningNotification object:nil];
	
	// Create photo picker view
	_picker = [[UIImagePickerController alloc] init];
	_picker.sourceType = UIImagePickerControllerSourceTypeCamera;
	_picker.cameraCaptureMode = UIImagePickerControllerCameraCaptureModePhoto;
	_picker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
	_picker.showsCameraControls = NO;
	_picker.navigationBarHidden = YES;
	_picker.toolbarHidden = YES;
	_picker.delegate = nil;
	
	self.currentPickerMode = kUPickerCurrentWorkingModeCamera;
	
	// Position and add photo view in the view
	[_picker.view setFrame:CGRectMake(0, 0, self.frame.size.width, self.frame.size.height)];
	
	// Zoom to not have black bar at the bottom
    if(IS_IPHONE_5){
        CGAffineTransform translate = CGAffineTransformMakeTranslation(0.0, 11.0);
        _picker.cameraViewTransform = translate;
        CGAffineTransform scale = CGAffineTransformScale(translate, 1.06, 1.06);
        _picker.cameraViewTransform = scale;
    }
	
	// Setup picker
	[self addSubview:_picker.view];
	
	// Put alpha bar upfront
	[self bringSubviewToFront:_topBar];
	[self bringSubviewToFront:_bottomBar];
}

- (void)setupOptionsEnableSoundPlaying:(BOOL)enableSound optionsAccel:(BOOL)enableAccel
{	
	// Options
	_allowChangeOfCameraByShaking = enableAccel;
	_playSoundWhenCameraChanges = enableSound;
	
	if (_playSoundWhenCameraChanges) {
		[self loadSound];
	} else {
		self.clickSound = nil;
	}
	
	if (_allowChangeOfCameraByShaking) {
		// Motion manager
		_reloadCount = 4;
		_currentMaxAccelY = 0.75f;
		_motionManager.accelerometerUpdateInterval = .1;
		[_motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue currentQueue] withHandler:^(CMAccelerometerData  *accelerometerData, NSError *error) {
			[self accelerationData:accelerometerData.acceleration];
		}];
	} else {
		[_motionManager stopAccelerometerUpdates];
	}
}

- (void)setupPickerForPhotosAlbum
{
	// Reset picker capture mode
	_picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	self.currentPickerMode = kUPickerCurrentWorkingModeLibrary;
	
	// Resize myself to take up all the screen but the status bar's height
	self.frame = CGRectMake(0, 20.0f, self.superview.frame.size.width, self.superview.frame.size.height-20);
	_picker.view.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
	
	// Hide alpha bar
	[_topBar setHidden:YES];
	[_bottomBar setHidden:YES];
	
	[self.superview bringSubviewToFront:self];
	[self.picker.view setHidden:NO];
}

- (void)setupPickerForCameraAndDisplayIt:(BOOL)shouldDisplay
{
	// Reset picker capture mode
	_picker.sourceType = UIImagePickerControllerSourceTypeCamera;
	self.currentPickerMode = kUPickerCurrentWorkingModeCamera;
	
	// Resize it to it's original size
	self.frame = _moveAndScaleZoneRectForCamera;
	_picker.view.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
	
	// Hide alpha bar
	[_topBar setHidden:NO];
	[_bottomBar setHidden:NO];
	
	[_picker.view setHidden:!shouldDisplay];
}

- (void)unsetupPicker
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionDidStartRunningNotification object:nil];
	self.picker.delegate = nil;
	[self.picker.view removeFromSuperview];
	self.picker = nil;
}

- (void)setPickerDelegate:(id <UIImagePickerControllerDelegate, UINavigationControllerDelegate>)delegate
{
	_picker.delegate = delegate;
}

- (void)setAlphaBarColor:(UIColor*)color
{
	[_topBar setBackgroundColor:color];
    [_bottomBar setBackgroundColor:color];
}

- (void)resetInset
{
	[self.scrollView setContentInset:UIEdgeInsetsZero];
}

- (UIImage*)retrieveImageInsideCropZone
{
	CGRect cropRect;
	if(IS_IPHONE_5) {
		// Base rect for cropping the screenshots
		cropRect = CGRectMake(self.frame.origin.x, self.frame.origin.y + kUSemiAlphaBarHeightPhone5, self.frame.size.width, self.frame.size.height - (kUSemiAlphaBarHeightPhone5*2));
	} else {
		// Base rect for cropping the screenshots
		cropRect = CGRectMake(self.frame.origin.x, self.frame.origin.y + kUSemiAlphaBarHeight, self.frame.size.width, self.frame.size.height - (kUSemiAlphaBarHeight*2));
	}
	
	// Base screenshots
	UIImage *screen = [self.scrollView screenshot];
	return [self.scrollView cropScreenShots:screen usingRect:cropRect];
}

- (void)saveMoveAndScaleZoneRectForCamera
{
	[self setMoveAndScaleZoneRectForCamera:self.frame];
}

- (void)showLoadingAnimation
{
    //[_loadingAnimation setHidden:NO];
    [_loadingAnimation startAnimating];
}

- (void)hideLoadingAnimation
{
    [_loadingAnimation stopAnimating];
    //[_loadingAnimation setHidden:YES];
}

#pragma mark - Motion

- (void)accelerationData:(CMAcceleration)acceleration
{
    _reloadCount ++;
    
    // Reload current Y
    if(_reloadCount > 3){
        _reloadCount = 0;
        _currentMaxAccelY = acceleration.y;
    }
    
    // Horizontal rotation return to not show camera
    _newValX = fabs(acceleration.x);
    if(_newValX > 0.6){
        return;
	}
    
    // Compare  current and new Y values
    double newValY = fabs(acceleration.y);
    double currentValY = fabs(_currentMaxAccelY)-0.4;
	
    if(currentValY >= newValY){
        // move position detected
        [self changeCamera];
    }
}

#pragma mark - Change front/back camera

- (void)changeCamera
{
    if(_isChangingCamera) return;
        
	// Play a sound
	_clickSound.currentTime = 0;
	[_clickSound performSelectorInBackground:@selector(play) withObject:nil];
		
	// Change camera
	if(self.currentPickerMode == kUPickerCurrentWorkingModeCamera){
		if(_picker.cameraDevice == UIImagePickerControllerCameraDeviceRear){
			_picker.cameraDevice = UIImagePickerControllerCameraDeviceFront;
		} else {
			_picker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
		}
	}
        
	// End changing camera
	_isChangingCamera = YES;
	[self performSelector:@selector(endChangingCamera) withObject:nil afterDelay:1];
}

- (void)endChangingCamera
{
	_isChangingCamera = NO;
}

#pragma mark - Sounds

- (void)loadSound
{
    NSError *setOverrideError;
    NSError *setCategoryError;
    
    NSString *soundFilePath = [[NSBundle mainBundle] pathForResource:@"Switch_Item" ofType:@"mp3"];
    NSURL *soundFileURL = [NSURL fileURLWithPath:soundFilePath];
    _clickSound = [[AVAudioPlayer alloc] initWithContentsOfURL:soundFileURL error:nil];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:NULL];
	
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryAmbient error:&setCategoryError];
    if(setCategoryError){
        DLog(@"Set Category : %@", [setCategoryError description]);
    }
	
    [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&setOverrideError];
    if(setOverrideError){
        DLog(@"Override Output : %@", [setOverrideError description]);
    }
	
    _clickSound.volume = 1.0;
}

#pragma mark - Notification

- (void)cameraIsReady:(NSNotification*)aNotification
{
	[self setCameraIsReady:YES];
}

@end