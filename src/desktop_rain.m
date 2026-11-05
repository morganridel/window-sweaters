#import "desktop_rain.h"
#import <QuartzCore/QuartzCore.h>

@interface KnitRainPanel : NSPanel
@property(strong) CAEmitterLayer* emitter;
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

static CAEmitterCell* rain_cell(CGImageRef streak, CGFloat velocity, CGFloat height,
                                CGFloat width, CGFloat scale, CGFloat rate, CGFloat alpha) {
  CAEmitterCell* drop = [CAEmitterCell emitterCell];
  drop.contents = (__bridge id)streak;
  drop.contentsScale = 2;
  drop.color = [NSColor colorWithWhite:1 alpha:alpha].CGColor;
  drop.scale = scale;
  drop.scaleRange = scale * 0.30;
  drop.velocity = velocity;
  drop.velocityRange = velocity * 0.18;
  // AppKit's backing layer uses an upward y axis.
  drop.emissionLongitude = -M_PI_2 + 0.09;
  drop.emissionRange = 0.06;
  drop.lifetime = (height + 150) / (velocity * 0.8);
  drop.birthRate = rate * width / 1000;
  return drop;
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
  CGFloat width = NSWidth(view.bounds), height = NSHeight(view.bounds);
  CAEmitterLayer* emitter = [CAEmitterLayer layer];
  emitter.frame = view.bounds;
  emitter.masksToBounds = YES;
  emitter.emitterShape = kCAEmitterLayerLine;
  emitter.emitterMode = kCAEmitterLayerOutline;
  emitter.emitterPosition = CGPointMake(width / 2, height + 24);
  emitter.emitterSize = CGSizeMake(width + 320, 0);
  emitter.emitterCells = @[
    rain_cell(streak, 460, height, width, 0.66, 66, 0.43),
    rain_cell(streak, 760, height, width, 1.00, 52, 0.72),
    rain_cell(streak, 990, height, width, 1.30, 17, 0.91)
  ];
  [view.layer addSublayer:emitter];
  panel.emitter = emitter;
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
  else [self updateBirthRates];
}

- (void)updateBirthRates {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  const float rates[] = { 0, 0.48, 1.0, 1.6 };
  for (KnitRainPanel* panel in self.panels)
    panel.emitter.birthRate = rates[self.intensity];
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
  [self updateBirthRates];
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
