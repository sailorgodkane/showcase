//
//  Created by Jimmy De Pauw on 07/05/14.
//

#import "LoadingAnimation.h"
#import <QuartzCore/QuartzCore.h>

#define kUMaxTransformScalingUp	1.3

@interface LoadingAnimation ()

@property (strong, nonatomic) NSColor *dotColor;
@property (assign) CGFloat animationSpeed;
@property (assign) CGFloat spaceBetween;
@property (assign) NSUInteger dotCount;
@property (assign) BOOL started;

@end

@implementation LoadingAnimation

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
		self.animationSpeed = 0.5f;
		self.hideWhenStopped = YES;
		self.hidden = YES;
        self.started = NO;
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		self.animationSpeed = 0.5f;
		self.hideWhenStopped = YES;
		self.hidden = YES;
		self.started = NO;
    }
    return self;
}

- (void)setupLoadingAnimation
{
	[self setupLoadingAnimationWithDotCount:kUDefaultLoadingAnimationDots dotColor:[NSColor whiteColor] animationSpeed:kUDefaultLoadingAnimationSpeed];
}

- (void)setupLoadingAnimationWithColor:(NSColor*)dotColor
{
	[self setupLoadingAnimationWithDotCount:kUDefaultLoadingAnimationDots dotColor:dotColor animationSpeed:kUDefaultLoadingAnimationSpeed];
}

- (void)setupLoadingAnimationWithDotCount:(NSUInteger)dotCount dotColor:(NSColor*)dotColor animationSpeed:(CGFloat)speed
{
	self.dotColor = dotColor;
	self.animationSpeed = speed;
	self.dotCount = dotCount;

    self.spaceBetween = (self.frame.size.width / 7.0f) * 0.4f;

	// This is the space used for between the dots
	CGFloat spaces = ((dotCount-1) * self.spaceBetween);
	
	// Depending on the width and dotCount, calculate the radius of the dots so it takes as much space as possible
	float dotRadius = MIN(((self.frame.size.width - spaces) / dotCount) / 2, (self.frame.size.height * 0.9f) / 2);
	
	for (int i=0; i<dotCount; i++) {
		[self addDotWithRadius:dotRadius dotNumber:i];
	}
}

- (void)startAnimating
{
    if (!_started) {
        if (self.hideWhenStopped) {
            [self setHidden:NO];
        }
        [self applyAnimationToDots];
        [self setAnimated:YES];
        _started = YES;
    }
}

- (void)stopAnimating
{
    _started = NO;
	NSArray *dots = self.layer.sublayers;
	for (CAShapeLayer *dot in dots) {
		[dot removeAllAnimations];
	}
	
	[self setAnimated:NO];
	
	if (self.hideWhenStopped) {
		[self setHidden:YES];
	}
}

- (CGPathRef)quartzPath:(NSBezierPath*)bezierPath
{
	NSInteger i, numElements;
	
	// Need to begin a path here.
	CGPathRef immutablePath = NULL;
	
	// Then draw the path elements.
	numElements = [bezierPath elementCount];
	
	if (numElements > 0) {
		CGMutablePathRef path = CGPathCreateMutable();
		NSPoint points[3];
		BOOL didClosePath = YES;
		
		for (i = 0; i < numElements; i++) {
			switch ([bezierPath elementAtIndex:i associatedPoints:points]) {
				case NSMoveToBezierPathElement:
					CGPathMoveToPoint(path, NULL, points[0].x, points[0].y);
					break;
					
				case NSLineToBezierPathElement:
					CGPathAddLineToPoint(path, NULL, points[0].x, points[0].y);
					didClosePath = NO;
					break;
					
				case NSCurveToBezierPathElement:
					CGPathAddCurveToPoint(path, NULL, points[0].x, points[0].y, points[1].x, points[1].y, points[2].x, points[2].y);
					didClosePath = NO;
					break;
					
				case NSClosePathBezierPathElement:
					CGPathCloseSubpath(path);
					didClosePath = YES;
					break;
			}
		}
		
		// Be sure the path is closed or Quartz may not do valid hit detection.
		if (!didClosePath) CGPathCloseSubpath(path);

		immutablePath = CGPathCreateCopy(path);
		CGPathRelease(path);
	}
	
	return immutablePath;
}

- (void)addDotWithRadius:(float)radius dotNumber:(int)cpt
{
	// Set up the shape of the circle
	CAShapeLayer *circle = [CAShapeLayer layer];
	
	// Make a circular shape
	NSBezierPath *bezierPath = [NSBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 1.5*radius, 1.5*radius) xRadius:radius yRadius:radius];
	circle.path = [self quartzPath:bezierPath];
	
	// Setup the shape frame
	float baseX = cpt * (radius*2 + self.spaceBetween) + 5;
	circle.frame = CGRectMake(baseX, CGRectGetMidY(self.bounds)-radius, radius, radius);
	
	// Configure the apperence of the circle
	circle.fillColor = self.dotColor.CGColor;
	circle.lineWidth = 0;
	
	// Set anchor to the center of the circle so it scales from it.
	CGRect circleFrame = circle.bounds;
	circle.anchorPoint = CGPointMake(CGRectGetMidX(circleFrame) / CGRectGetMaxX(circleFrame), CGRectGetMidY(circleFrame) / CGRectGetMaxY(circleFrame));
	
	// Add to parent layer
	[self.layer addSublayer:circle];
}

- (void)addAnimate:(CAShapeLayer*)circle dotNumber:(int)cpt
{
	// Seconds per frame	: 0.02
	// Total frames per dot : 48
	CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
	animation.values = [NSArray arrayWithObjects:
						[NSNumber numberWithFloat:1.0f],	// Frame 00
						[NSNumber numberWithFloat:1.2f],	// Frame 01
						[NSNumber numberWithFloat:1.3f],	// Frame 02
						[NSNumber numberWithFloat:1.4f],	// Frame 03
						[NSNumber numberWithFloat:1.2f],	// Frame 09
						[NSNumber numberWithFloat:1.3f],	// Frame 15
						[NSNumber numberWithFloat:1.2f],	// Frame 21
						[NSNumber numberWithFloat:1.25f],	// Frame 26
						[NSNumber numberWithFloat:1.0f],	// Frame 47
						nil];
	
	animation.keyTimes = [NSArray arrayWithObjects:
						  [NSNumber numberWithFloat:0.0f],
						  [NSNumber numberWithFloat:0.02f],
						  [NSNumber numberWithFloat:0.04f],
						  [NSNumber numberWithFloat:0.06f],
						  [NSNumber numberWithFloat:0.18f],
						  [NSNumber numberWithFloat:0.3f],
						  [NSNumber numberWithFloat:0.42f],
						  [NSNumber numberWithFloat:0.52f],
						  [NSNumber numberWithFloat:1.0f], nil];
	
	animation.duration = self.animationSpeed;
	animation.repeatCount = 0;
	animation.autoreverses = NO;
	animation.removedOnCompletion = YES;
	animation.delegate = (cpt == (self.dotCount-1))?self:nil;
	
	// Next dot start it's animation after 7 frames so 0.14 seconds delay
	animation.beginTime = CACurrentMediaTime() + (cpt*0.14f);
	
	[circle addAnimation:animation forKey:@"drawCircleAnimation"];
}

- (void)applyAnimationToDots
{
	NSArray *dots = self.layer.sublayers;
	
	[CATransaction lock];
	[CATransaction begin];
	
	int i = 0;
	for (CAShapeLayer *dot in dots) {
		[self addAnimate:dot dotNumber:i++];
	}
	
	[CATransaction commit];
	[CATransaction unlock];
}

- (void)animationDidStop:(CAAnimation *)theAnimation finished:(BOOL)flag
{
	if ([self isAnimated]) {
		[self performSelector:@selector(applyAnimationToDots) withObject:self afterDelay:0.3f];
	}
}

@end