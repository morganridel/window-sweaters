#import "desktop_rain.h"
#import <QuartzCore/QuartzCore.h>

@interface KnitRainPanel : NSPanel
@property(copy) NSArray<CALayer*>* rainGroups;
@end

@implementation KnitRainPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// A cool streak with a bright leading edge and a fading tail. The darker
// outer stroke keeps it visible against pale wallpaper, too.
static CGImageRef new_streak(void) CF_RETURNS_RETAINED {
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef ctx = CGBitmapContextCreate(NULL, 12, 64, 8, 0, space,
                                            (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
  if (!ctx) {
    CGColorSpaceRelease(space);
    return NULL;
  }
  CGContextSetLineCap(ctx, kCGLineCapRound);
  CGContextSetLineWidth(ctx, 5);
  CGContextSetRGBStrokeColor(ctx, 0.17, 0.26, 0.36, 0.29);
  CGContextMoveToPoint(ctx, 8, 5);
  CGContextAddLineToPoint(ctx, 4, 47);
  CGContextStrokePath(ctx);

  CGContextSetLineWidth(ctx, 2.6);
  CGContextMoveToPoint(ctx, 8, 5);
  CGContextAddLineToPoint(ctx, 3, 61);
  CGContextReplacePathWithStrokedPath(ctx);
  CGContextClip(ctx);
  const CGFloat colors[] = { 0.87, 0.95, 1, 0.92, 0.58, 0.78, 0.93, 0 };
  CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
  CGContextDrawLinearGradient(ctx, gradient, CGPointMake(8, 5), CGPointMake(3, 61), 0);
  CGImageRef streak = CGBitmapContextCreateImage(ctx);
  CGGradientRelease(gradient);
  CGContextRelease(ctx);
  CGColorSpaceRelease(space);
  return streak;
}

static CGFloat random_unit(void) {
  return arc4random_uniform(10000) / 10000.0;
}

static CALayer* rain_group(CGImageRef streak, CGRect bounds, NSUInteger count) {
  CALayer* group = [CALayer layer];
  group.frame = bounds;
  CGFloat width = NSWidth(bounds), height = NSHeight(bounds);
  const CGFloat margin = 28;
  CGFloat travel = height + 2 * margin;
  CFTimeInterval now = CACurrentMediaTime();
  // Different depths give the scene motion without a single fast wall of rain.
  const struct { CGFloat speed, scale, alpha; } depths[] = {
    { 160, .48, .42 }, { 245, .68, .67 }, { 325, .88, .83 }
  };
  for (NSUInteger i = 0; i < count; i++) {
    NSUInteger depth = arc4random_uniform(10);
    depth = depth < 5 ? 0 : depth < 9 ? 1 : 2;
    CGFloat scale = depths[depth].scale * (.85 + random_unit() * .3);
    CGFloat speed = depths[depth].speed * (.9 + random_unit() * .2);
    CGFloat drift = travel * (.045 + random_unit() * .03);
    CGFloat startX = -drift + random_unit() * (width + drift);
    CGPoint start = CGPointMake(startX, height + margin);
    // AppKit layer coordinates run up. Positive x and decreasing y give a
    // slight rightward drift. Both ends are outside the visible desktop.
    CGPoint end = CGPointMake(startX + drift, -margin);
    CALayer* drop = [CALayer layer];
    drop.contents = (__bridge id)streak;
    drop.contentsScale = 2;
    drop.bounds = CGRectMake(0, 0, CGImageGetWidth(streak) * scale / 2,
                                   CGImageGetHeight(streak) * scale / 2);
    drop.opacity = depths[depth].alpha;
    drop.position = end;
    [group addSublayer:drop];

    CABasicAnimation* fall = [CABasicAnimation animationWithKeyPath:@"position"];
    fall.fromValue = [NSValue valueWithPoint:start];
    fall.toValue = [NSValue valueWithPoint:end];
    fall.duration = travel / speed;
    fall.beginTime = now - random_unit() * fall.duration;
    fall.repeatCount = HUGE_VALF;
    fall.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [drop addAnimation:fall forKey:@"fall"];
  }
  return group;
}

static KnitRainPanel* rain_panel(NSScreen* screen, CGImageRef streak) {
  KnitRainPanel* panel = [[KnitRainPanel alloc] initWithContentRect:screen.frame
      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
      backing:NSBackingStoreBuffered defer:NO];
  panel.releasedWhenClosed = NO;
  panel.opaque = NO;
  panel.backgroundColor = NSColor.clearColor;
  panel.hasShadow = NO;
  panel.hidesOnDeactivate = NO;
  panel.ignoresMouseEvents = YES;
  // Leave desktop icons, widgets, normal windows, the Dock and menu bar above us.
  panel.level = CGWindowLevelForKey(kCGDesktopIconWindowLevelKey) - 1;
  panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
    NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle |
    NSWindowCollectionBehaviorFullScreenNone;
  // The content rect initializer may constrain an oversized window on a secondary
  // display. Set the exact display frame before ordering the panel in.
  [panel setFrame:screen.frame display:NO];

  NSView* view = panel.contentView;
  view.wantsLayer = YES;
  view.layer.masksToBounds = YES;
  CGRect bounds = view.bounds;
  // Cap the count on large displays. Intensity changes reveal extra drops
  // at the same speeds without restarting the ones already on screen.
  CGFloat area = NSWidth(bounds) * NSHeight(bounds);
  NSUInteger count = MIN(360, MAX(24, ceil(area / 6800)));
  panel.rainGroups = @[
    rain_group(streak, bounds, (count + 1) / 2),
    rain_group(streak, bounds, count / 2),
    rain_group(streak, bounds, count * 3 / 5)
  ];
  for (CALayer* group in panel.rainGroups) [view.layer addSublayer:group];
  return panel;
}

@interface KnitDesktopRain ()
@property(copy) NSArray<KnitRainPanel*>* panels;
@property BOOL displaysAsleep;
@end

@implementation KnitDesktopRain

- (instancetype)init {
  if (!(self = [super init])) return nil;
  NSNotificationCenter* workspace = NSWorkspace.sharedWorkspace.notificationCenter;
  [workspace addObserver:self selector:@selector(screensSleep:)
                    name:NSWorkspaceScreensDidSleepNotification object:nil];
  [workspace addObserver:self selector:@selector(screensWake:)
                    name:NSWorkspaceScreensDidWakeNotification object:nil];
  [workspace addObserver:self selector:@selector(rebuild:)
                    name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rebuild:)
                    name:NSApplicationDidChangeScreenParametersNotification object:nil];
  return self;
}

- (void)dealloc {
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
  [NSNotificationCenter.defaultCenter removeObserver:self];
  for (KnitRainPanel* panel in self.panels) [panel close];
}

- (void)setIntensity:(NSInteger)intensity {
  intensity = MAX(0, MIN(intensity, 3));
  if (_intensity == intensity) return;
  _intensity = intensity;
  if (!intensity || !self.panels.count) [self rebuild:nil];
  else [self updateDensity];
}

- (void)updateDensity {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (KnitRainPanel* panel in self.panels)
    for (NSUInteger i = 0; i < panel.rainGroups.count; i++)
      panel.rainGroups[i].hidden = i >= (NSUInteger)self.intensity;
  [CATransaction commit];
}

- (void)rebuild:(NSNotification*)note {
  for (KnitRainPanel* panel in self.panels) [panel close];
  self.panels = nil;
  if (!self.intensity || self.displaysAsleep ||
      NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) return;

  CGImageRef streak = new_streak();
  if (!streak) return;
  NSMutableArray<KnitRainPanel*>* panels = [NSMutableArray array];
  for (NSScreen* screen in NSScreen.screens)
    [panels addObject:rain_panel(screen, streak)];
  CGImageRelease(streak);
  self.panels = panels;
  [self updateDensity];
  for (KnitRainPanel* panel in self.panels) [panel orderFrontRegardless];
}

- (void)screensSleep:(NSNotification*)note {
  self.displaysAsleep = YES;
  [self rebuild:note];
}

- (void)screensWake:(NSNotification*)note {
  self.displaysAsleep = NO;
  [self rebuild:note];
}
@end
