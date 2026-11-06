#import "desktop_weather.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@interface KnitWeatherPanel : NSPanel
@property(copy) NSArray<CALayer*>* groups;
@end

@implementation KnitWeatherPanel
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
  CGContextSetLineWidth(ctx, 5.8);
  CGContextSetRGBStrokeColor(ctx, 0.14, 0.25, 0.39, 0.53);
  CGContextMoveToPoint(ctx, 8, 5);
  CGContextAddLineToPoint(ctx, 3.5, 52);
  CGContextStrokePath(ctx);

  CGContextSetLineWidth(ctx, 3.2);
  CGContextMoveToPoint(ctx, 8, 5);
  CGContextAddLineToPoint(ctx, 3, 61);
  CGContextReplacePathWithStrokedPath(ctx);
  CGContextClip(ctx);
  const CGFloat colors[] = { 0.91, 0.97, 1, 0.98, 0.60, 0.81, 0.95, 0 };
  CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
  CGContextDrawLinearGradient(ctx, gradient, CGPointMake(8, 5), CGPointMake(3, 61), 0);
  CGImageRef streak = CGBitmapContextCreateImage(ctx);
  CGGradientRelease(gradient);
  CGContextRelease(ctx);
  CGColorSpaceRelease(space);
  return streak;
}

static CGContextRef sprite_context(size_t width, size_t height, CGColorSpaceRef space)
    CF_RETURNS_RETAINED {
  return CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                               (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
}

// The same flake reads as a soft dot at a distance and as a crystal up close.
static void stroke_crystal(CGContextRef ctx) {
  CGPoint center = CGPointMake(10, 10);
  for (int i = 0; i < 6; i++) {
    CGFloat angle = M_PI * i / 3;
    CGFloat x = cos(angle), y = sin(angle);
    CGContextMoveToPoint(ctx, center.x, center.y);
    CGContextAddLineToPoint(ctx, center.x + 6.6 * x, center.y + 6.6 * y);
    for (int sign = -1; sign <= 1; sign += 2) {
      CGContextMoveToPoint(ctx, center.x + 4.0 * x, center.y + 4.0 * y);
      CGContextAddLineToPoint(ctx, center.x + 5.7 * x - sign * 1.5 * y,
                                  center.y + 5.7 * y + sign * 1.5 * x);
    }
  }
  CGContextStrokePath(ctx);
}

static CGImageRef new_flake(void) CF_RETURNS_RETAINED {
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef ctx = sprite_context(20, 20, space);
  CGColorSpaceRelease(space);
  if (!ctx) return NULL;
  CGContextSetLineCap(ctx, kCGLineCapRound);
  CGContextSetRGBStrokeColor(ctx, .23, .34, .47, .68);
  CGContextSetLineWidth(ctx, 3.7);
  stroke_crystal(ctx);
  CGContextSetRGBStrokeColor(ctx, .92, .97, 1, 1);
  CGContextSetLineWidth(ctx, 1.8);
  stroke_crystal(ctx);
  CGImageRef flake = CGBitmapContextCreateImage(ctx);
  CGContextRelease(ctx);
  return flake;
}

static void puff(CGContextRef ctx, CGGradientRef gradient, CGRect bounds) {
  CGContextSaveGState(ctx);
  CGContextTranslateCTM(ctx, CGRectGetMidX(bounds), CGRectGetMidY(bounds));
  CGContextScaleCTM(ctx, CGRectGetWidth(bounds) / 2, CGRectGetHeight(bounds) / 2);
  CGContextDrawRadialGradient(ctx, gradient, CGPointZero, 0, CGPointZero, 1, 0);
  CGContextRestoreGState(ctx);
}

static CGImageRef new_atmosphere(BOOL fog) CF_RETURNS_RETAINED {
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef ctx = sprite_context(384, 140, space);
  if (!ctx) { CGColorSpaceRelease(space); return NULL; }

  const CGFloat shade[] = {.38, .47, .60, .48, .48, .57, .68, .38, .56, .66, .75, 0};
  const CGFloat cloud[] = {.97, .97, 1, .87, .84, .89, .98, .70, .73, .82, .93, 0};
  const CGFloat mist[] = {.87, .93, .98, .57, .73, .83, .92, .26, .66, .77, .86, 0};
  const CGFloat stops[] = {0, .60, 1};
  CGGradientRef shadow = CGGradientCreateWithColorComponents(space, shade, stops, 3);
  CGGradientRef light = CGGradientCreateWithColorComponents(space, fog ? mist : cloud, stops, 3);
  CGColorSpaceRelease(space);
  if (shadow && light) {
    if (fog) {
      // Long, shallow wisps, with soft edges that never make a hard horizon.
      puff(ctx, shadow, CGRectMake(6, 23, 365, 88));
      puff(ctx, light, CGRectMake(0, 43, 347, 47));
      puff(ctx, light, CGRectMake(83, 16, 301, 53));
      puff(ctx, light, CGRectMake(65, 62, 303, 51));
    } else {
      // A shaded underside and overlapping billows give clouds a readable silhouette.
      puff(ctx, shadow, CGRectMake(9, 2, 365, 84));
      puff(ctx, light, CGRectMake(12, 17, 177, 83));
      puff(ctx, light, CGRectMake(99, 24, 170, 114));
      puff(ctx, light, CGRectMake(210, 19, 171, 91));
      puff(ctx, light, CGRectMake(65, 12, 263, 57));
    }
  }
  if (shadow) CGGradientRelease(shadow);
  if (light) CGGradientRelease(light);
  CGImageRef sprite = CGBitmapContextCreateImage(ctx);
  CGContextRelease(ctx);
  return sprite;
}

static CGFloat random_unit(void) {
  return arc4random_uniform(10000) / 10000.0;
}

static CALayer* sprite_layer(CGImageRef image, CGSize size, CGFloat opacity) {
  CALayer* sprite = [CALayer layer];
  sprite.contents = (__bridge id)image;
  sprite.contentsScale = 2;
  sprite.bounds = (CGRect){CGPointZero, size};
  sprite.opacity = opacity;
  return sprite;
}

static void animate_path(CALayer* layer, NSArray<NSValue*>* points,
                         CFTimeInterval duration, CGFloat phase) {
  CAKeyframeAnimation* motion = [CAKeyframeAnimation animationWithKeyPath:@"position"];
  motion.values = points;
  motion.duration = duration;
  // Stagger the loops so the first frame is populated and has no visible reset.
  motion.beginTime = CACurrentMediaTime() - phase * duration;
  motion.repeatCount = HUGE_VALF;
  motion.calculationMode = kCAAnimationLinear;
  layer.position = points.lastObject.pointValue;
  [layer addAnimation:motion forKey:@"drift"];
}

static CALayer* precipitation_group(CGImageRef sprite, CGRect bounds, NSUInteger count, BOOL snow) {
  CALayer* group = [CALayer layer];
  group.frame = bounds;
  CGFloat width = NSWidth(bounds), height = NSHeight(bounds);
  const CGFloat margin = 28;
  CGFloat travel = height + 2 * margin;
  const struct { CGFloat speed, scale, alpha; } rain[] = {
    { 160, .54, .57 }, { 245, .75, .80 }, { 325, .94, .94 }
  }, flakes[] = {
    { 35, .44, .54 }, { 52, .64, .77 }, { 68, .92, .91 }
  };
  for (NSUInteger i = 0; i < count; i++) {
    NSUInteger depth = arc4random_uniform(10);
    depth = depth < 5 ? 0 : depth < 9 ? 1 : 2;
    CGFloat scale = (snow ? flakes[depth].scale : rain[depth].scale) * (.85 + random_unit() * .3);
    CGFloat speed = (snow ? flakes[depth].speed : rain[depth].speed) * (.9 + random_unit() * .2);
    CGFloat drift = travel * (.045 + random_unit() * .03);
    CGFloat startX = -drift + random_unit() * (width + drift);
    CGPoint start = CGPointMake(startX, height + margin);
    // AppKit layer coordinates run up. Both ends are outside the desktop.
    CGPoint end = CGPointMake(startX + drift, -margin);
    CGSize size = CGSizeMake(CGImageGetWidth(sprite) * scale / 2,
                             CGImageGetHeight(sprite) * scale / 2);
    CALayer* particle = sprite_layer(sprite, size, snow ? flakes[depth].alpha : rain[depth].alpha);
    [group addSublayer:particle];
    NSArray* points;
    if (snow) {
      CGFloat sway = 12 + random_unit() * 17;
      if (arc4random_uniform(2)) sway = -sway;
      points = @[[NSValue valueWithPoint:start],
        [NSValue valueWithPoint:CGPointMake(startX + drift / 3 + sway, start.y - travel / 3)],
        [NSValue valueWithPoint:CGPointMake(startX + drift * 2 / 3 - sway, start.y - travel * 2 / 3)],
        [NSValue valueWithPoint:end]];
    } else {
      points = @[[NSValue valueWithPoint:start], [NSValue valueWithPoint:end]];
    }
    animate_path(particle, points, travel / speed, random_unit());
  }
  return group;
}

static CALayer* atmosphere_group(CGImageRef sprite, CGRect bounds, NSUInteger count, BOOL fog) {
  CALayer* group = [CALayer layer];
  group.frame = bounds;
  CGFloat width = NSWidth(bounds), height = NSHeight(bounds);
  CGFloat offset = random_unit();
  for (NSUInteger i = 0; i < count; i++) {
    CGFloat size = MIN(width * (fog ? .94 : .50), (fog ? 660 : 390)) * (.70 + random_unit() * .50);
    CGFloat y = height * ((fog ? .08 : .40) + random_unit() * (fog ? .59 : .55));
    CGFloat margin = size / 2 + 2;
    CALayer* layer = sprite_layer(sprite, CGSizeMake(size, size * (fog ? .19 : .36)),
                                 (fog ? .61 : .53) + random_unit() * .19);
    if (i % 2) layer.transform = CATransform3DMakeScale(-1, 1, 1);
    [group addSublayer:layer];
    CGPoint start = CGPointMake(-margin, y);
    CGPoint end = CGPointMake(width + margin, y + (random_unit() - .5) * 24);
    CGFloat speed = (fog ? 16 : 20) + random_unit() * 12;
    CGFloat phase = fmod(offset + (i + .6 * random_unit()) / count, 1);
    animate_path(layer, @[[NSValue valueWithPoint:start], [NSValue valueWithPoint:end]],
                 (width + 2 * margin) / speed, phase);
  }
  return group;
}

static NSArray<CALayer*>* weather_groups(KnitWeatherEffect effect, CGImageRef sprite, CGRect bounds) {
  CGFloat area = NSWidth(bounds) * NSHeight(bounds);
  if (effect == KnitWeatherEffectRain || effect == KnitWeatherEffectSnow) {
    BOOL snow = effect == KnitWeatherEffectSnow;
    NSUInteger count = MIN(snow ? 280 : 480, MAX(24, ceil(area / (snow ? 9400 : 4700))));
    return @[precipitation_group(sprite, bounds, (count + 1) / 2, snow),
             precipitation_group(sprite, bounds, count / 2, snow),
             precipitation_group(sprite, bounds, count * 3 / 5, snow)];
  }
  BOOL fog = effect == KnitWeatherEffectFog;
  NSUInteger count = MIN(8, MAX(3, ceil(NSWidth(bounds) / 380)));
  return @[atmosphere_group(sprite, bounds, count, fog),
           atmosphere_group(sprite, bounds, count, fog),
           atmosphere_group(sprite, bounds, (count + 1) / 2, fog)];
}

static KnitWeatherPanel* weather_panel(NSScreen* screen, KnitWeatherEffect effect, CGImageRef sprite) {
  KnitWeatherPanel* panel = [[KnitWeatherPanel alloc] initWithContentRect:screen.frame
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
  panel.groups = weather_groups(effect, sprite, view.bounds);
  for (CALayer* group in panel.groups) [view.layer addSublayer:group];
  return panel;
}

@interface KnitDesktopWeather ()
@property(copy) NSArray<KnitWeatherPanel*>* panels;
@property BOOL displaysAsleep;
@property KnitWeatherEffect effect;
@property NSInteger intensity;
@end

@implementation KnitDesktopWeather

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
  for (KnitWeatherPanel* panel in self.panels) [panel close];
}

- (void)showEffect:(KnitWeatherEffect)effect intensity:(NSInteger)intensity {
  if (intensity <= 0) effect = KnitWeatherEffectNone;
  intensity = effect == KnitWeatherEffectNone ? 0 : MIN(intensity, 3);
  BOOL changed = _effect != effect;
  if (!changed && _intensity == intensity) return;
  _effect = effect;
  _intensity = intensity;
  if (changed || !self.panels.count) [self rebuild:nil];
  else [self updateDensity];
}

- (void)updateDensity {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (KnitWeatherPanel* panel in self.panels)
    for (NSUInteger i = 0; i < panel.groups.count; i++)
      panel.groups[i].hidden = i >= (NSUInteger)self.intensity;
  [CATransaction commit];
}

- (void)rebuild:(NSNotification*)note {
  for (KnitWeatherPanel* panel in self.panels) [panel close];
  self.panels = nil;
  if (!self.intensity || self.displaysAsleep ||
      NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) return;

  CGImageRef sprite = NULL;
  switch (self.effect) {
    case KnitWeatherEffectRain: sprite = new_streak(); break;
    case KnitWeatherEffectSnow: sprite = new_flake(); break;
    case KnitWeatherEffectFog:
    case KnitWeatherEffectClouds: sprite = new_atmosphere(self.effect == KnitWeatherEffectFog); break;
    case KnitWeatherEffectNone: return;
  }
  if (!sprite) return;
  NSMutableArray<KnitWeatherPanel*>* panels = [NSMutableArray array];
  for (NSScreen* screen in NSScreen.screens)
    [panels addObject:weather_panel(screen, self.effect, sprite)];
  CGImageRelease(sprite);
  self.panels = panels;
  [self updateDensity];
  for (KnitWeatherPanel* panel in self.panels) [panel orderFrontRegardless];
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
