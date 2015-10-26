//
//  Created by Jimmy De Pauw on 07/05/14.
//

#define kUDefaultLoadingAnimationDots   3
#define kUDefaultLoadingAnimationSpeed	0.7f
#define kUDefaultLoadingAnimationWidth	125.0f
#define kUDefaultLoadingAnimationHeight	50.0f

@interface LoadingAnimation : NSView

// Initiators
- (void)setupLoadingAnimation;
- (void)setupLoadingAnimationWithColor:(NSColor*)dotColor;
- (void)setupLoadingAnimationWithDotCount:(NSUInteger)dotCount dotColor:(NSColor*)dotColor animationSpeed:(CGFloat)speed;

// Control animation
- (void)startAnimating;
- (void)stopAnimating;

// KVO ready property
@property (assign, getter = isAnimated) BOOL animated;

// Auto-hide when not animating if set to YES
@property (assign) BOOL hideWhenStopped;

@end