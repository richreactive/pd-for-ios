//
//  WaveTableView.m
//  WaveTables
//
//  Created by Rich E on 16/05/11.
//  Copyright 2011 Richard T. Eakin. All rights reserved.
//

#import "WaveTableView.h"
#import "PdArray.h"
#import <QuartzCore/QuartzCore.h>

@interface WaveTableView ()

@property (nonatomic, retain) PdArray *wavetable;
@property (nonatomic, retain) UIColor *borderColor;
@property (nonatomic, retain) UIColor *arrayColor;
@property (nonatomic, assign) CGPoint lastPoint; // the last [x,y] set written to the PdArray *wavetable (used for interpolation) note: x is in magnitude (-1:1) while y is in pixels
@property (nonatomic, assign) BOOL dragging; // indicates whether the user is currently dragging a finder across the device

- (void)updateTableWithPoint:(CGPoint)point;

@end

@implementation WaveTableView

@synthesize wavetable = wavetable_;
@synthesize borderColor = borderColor_;
@synthesize arrayColor = arrayColor_;
@synthesize lastPoint = lastPoint_;
@synthesize dragging = dragging_;
@synthesize minY = minY_;
@synthesize maxY = maxY_;

#pragma mark -
#pragma mark Init / Dealloc

- (id)initWithWavetable:(PdArray *)pdArray {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.borderColor = [UIColor darkGrayColor];
        self.layer.borderColor = self.borderColor.CGColor;
        self.layer.borderWidth = 1.0;
        self.arrayColor = [UIColor blackColor];
        
        self.wavetable = pdArray;
		self.lastPoint = CGPointMake(-1.0, 0.0); // set so any new point will not be the same as the last
        self.minY = -1.0;
        self.maxY = 1.0;
    }
    return self;
}

- (void)dealloc {
    self.wavetable = nil;
    self.borderColor = nil;
    self.arrayColor = nil;
    [super dealloc];
}

#pragma mark -
#pragma mark Inline Conversion functions

static inline CGFloat convertMagToY(CGFloat mag, CGFloat minY, CGFloat maxY, CGFloat viewHeight) {
	return (maxY - mag) * viewHeight / (maxY - minY);
}

static inline CGFloat convertYToMag(CGFloat y, CGFloat minY, CGFloat maxY, CGFloat viewHeight) {
    return  maxY - y * (maxY - minY) / viewHeight;
}

#pragma mark -
#pragma mark Drawing

- (void)drawRect:(CGRect)rect {
    if (self.wavetable) {
        CGRect bounds = self.bounds;
        
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetLineWidth(context, 2.0);
	
        CGContextSetStrokeColorWithColor(context, [self.arrayColor CGColor]);
        
        CGFloat scaleX = bounds.size.width / (self.wavetable.size - 1); // the wavetable spans the entire view, 0 to last index
		int startIndex = (int)floor(rect.origin.x / scaleX);
		int endIndex = (int)ceil((rect.origin.x + rect.size.width) / scaleX);
        CGFloat minY = self.minY;
        CGFloat maxY = self.maxY;
		CGFloat y = convertMagToY([self.wavetable floatAtIndex:startIndex], minY, maxY, bounds.size.height);
		
        CGContextMoveToPoint(context, startIndex * scaleX, y);
        for (int i = startIndex + 1; i <= endIndex; i++) {
			y = convertMagToY([self.wavetable floatAtIndex:i], minY, maxY, bounds.size.height);
            CGContextAddLineToPoint(context, i * scaleX, y);
        }
        CGContextStrokePath(context);
    }
}

#pragma mark -
#pragma mark Touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    self.dragging = NO;
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    [self updateTableWithPoint:point];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    self.dragging = YES;
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    if([self hitTest:point withEvent:event] == self) {
        [self updateTableWithPoint:point];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    self.dragging = NO;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    self.dragging = NO;
}

#pragma mark -
#pragma mark Private

/* This is where all the calculations are done as for what elements of the
 * PdArray should be changed as well as what rect should be invalidated
 * to redraw the new points (we don't want to redraw the unchanged sections).
 * If the new point has skipped a few indeces and we are in the middle of a
 * touchesMoved, it will draw a line from the last point recorded to the new one.
 */
- (void)updateTableWithPoint:(CGPoint)point {
	CGSize viewSize = self.bounds.size;
	CGFloat	waveTableToViewXRatio = (float)(self.wavetable.size - 1)/ viewSize.width;
	//float mag = (point.y * -2.0 / viewSize.height) + 1.0; // TODO: generalize to take a minY and maxY.  will need to update the name too
    CGFloat mag = convertYToMag(point.y, self.minY, self.maxY, viewSize.height);
	CGFloat redrawPadding = ceil(1.0 / waveTableToViewXRatio) * 2.0; // minimal amount to invalidate a rect that still keeps a continious line
    int index = (int)round(point.x * waveTableToViewXRatio);
	int lastIndex = (int)round(self.lastPoint.x * waveTableToViewXRatio);
	int numPoints = abs(lastIndex - index);
	CGFloat redrawX;

	if (self.dragging && numPoints > 1) {
		//draw a line from lastPoint.x to point.x and feed it to self.wavetable

		float incr = (self.lastPoint.y - mag) / (float)(lastIndex - index);
		int currentIndex = lastIndex;
		float currentMag = self.lastPoint.y;

		if (index > lastIndex) { // going forward
			for (int i = 0; i < numPoints; i++) {
				currentIndex++;
				currentMag += incr;
				[self.wavetable setFloat:currentMag atIndex:currentIndex];
			}
			redrawX = (self.lastPoint.x < redrawPadding ? 0.0 : self.lastPoint.x - redrawPadding);
		} else {
			for (int i = 0; i < numPoints; i++) {
				currentIndex--;
				currentMag -= incr;
				[self.wavetable setFloat:currentMag atIndex:currentIndex];
			}
			redrawX = (point.x < redrawPadding ? 0.0 : point.x - redrawPadding);
		}

		[self setNeedsDisplayInRect:CGRectMake(redrawX, 0.0, redrawPadding * (numPoints + 1), viewSize.height)];
		
	} else {
		// no need to interpolate so just draw one point and store the last calculated value
		[self.wavetable setFloat:mag atIndex:index];
		
		redrawX = (point.x < redrawPadding ? 0.0 : point.x - redrawPadding);
		[self setNeedsDisplayInRect:CGRectMake(redrawX, 0.0, redrawPadding * 2.0, viewSize.height)];
	}
	
    self.lastPoint = CGPointMake(point.x, mag); 
}

@end
