//
//  Created by De Pauw Jimmy on 25/04/14.
//

#import <UIKit/UIKit.h>
#import "ImageScrollView.h"

#define kUSemiAlphaBarHeight			44.0f
#define kUSemiAlphaBarHeightPhone5	88.0f

typedef NS_ENUM(NSUInteger, kUPickerCurrentWorkingMode) {
    kUPickerCurrentWorkingModeCamera = 0,
    kUPickerCurrentWorkingModeLibrary = 1
};

#define kUWorkingModeSetToCamera		0
#define kUWorkingModeSetToCamera		0

@class LoadingAnimation;
@interface PickerScrollPhotoView : UIView

@property (strong, nonatomic) LoadingAnimation *loadingAnimation;

@property (strong, nonatomic) UIImagePickerController *picker;
@property (strong, nonatomic) ImageScrollView *scrollView;

@property (strong, nonatomic) UIView *topBar;
@property (strong, nonatomic) UIView *bottomBar;

@property (assign) CGRect moveAndScaleZoneRectForCamera;
@property (assign) kUPickerCurrentWorkingMode currentPickerMode;

// Options
@property (assign) BOOL allowChangeOfCameraByShaking;
@property (assign) BOOL playSoundWhenCameraChanges;

// KVO property
@property (assign) BOOL cameraIsReady;

// Set the UIImagePickerControllerDelegate delegate object
- (void)setPickerDelegate:(id <UIImagePickerControllerDelegate, UINavigationControllerDelegate>)delegate;

// Set an image inside the scrollView
- (void)setDisplayImage:(UIImage*)image;

// If the picture is too small to be valid
- (BOOL)isPictureLargeEnough:(UIImage*)image;

// Set the color of the 2 bars
- (void)setAlphaBarColor:(UIColor*)color;

// Setup the pickerView mode
- (void)setupPickerForPhotosAlbum;
- (void)setupPickerForCameraAndDisplayIt:(BOOL)shouldDisplay;

// Setup the UIImagePickerController object
- (void)setupPicker;

// Destroy the UIImagePickerController object
- (void)unsetupPicker;

// Reset the EdgeInset of the scrollView to zero
- (void)resetInset;

// Will return an image of what was inside the cropZone
- (UIImage*)retrieveImageInsideCropZone;

// Save Frame for the top view
- (void)saveMoveAndScaleZoneRectForCamera;

// Handle the centered 3 dots animation
- (void)showLoadingAnimation;
- (void)hideLoadingAnimation;

// Options
- (void)setupOptionsEnableSoundPlaying:(BOOL)enableSound optionsAccel:(BOOL)enableAccel;

@end