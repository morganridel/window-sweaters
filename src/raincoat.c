#include "raincoat.h"
#include <math.h>

bool g_knit_raincoat = false;

struct hood {
  CGFloat x, y, half, lift;
};

CGFloat raincoat_hood_height(CGFloat window_width) {
  return window_width < 108 ? 0 : fmin(39, 22 + (window_width - 108) * 0.14);
}

static void hood_crown(CGMutablePathRef path, struct hood hood) {
  CGFloat x = hood.x, y = hood.y, w = hood.half, h = hood.lift;
  CGPathAddCurveToPoint(path, NULL, x - w * .68, y + h * .02, x - w * .89, y + h * .92,
                      x - w * .19, y + h * .99);
  CGPathAddCurveToPoint(path, NULL, x + w * .46, y + h * 1.08, x + w * .61, y + h * .86,
                      x + w * .72, y + h * .44);
  CGPathAddCurveToPoint(path, NULL, x + w * .82, y + h * .09, x + w * .88, y,
                      x + w, y);
}

static CGPathRef coat_outline(CGRect bounds, CGFloat radius, struct hood hood) {
  CGFloat l = CGRectGetMinX(bounds), r = CGRectGetMaxX(bounds);
  CGFloat b = CGRectGetMinY(bounds), t = CGRectGetMaxY(bounds);
  CGMutablePathRef path = CGPathCreateMutable();
  CGPathMoveToPoint(path, NULL, l + radius, t);
  if (hood.lift) {
    CGPathAddLineToPoint(path, NULL, hood.x - hood.half, t);
    hood_crown(path, hood);
  }
  CGPathAddArcToPoint(path, NULL, r, t, r, b, radius);
  CGPathAddArcToPoint(path, NULL, r, b, l, b, radius);
  CGPathAddArcToPoint(path, NULL, l, b, l, t, radius);
  CGPathAddArcToPoint(path, NULL, l, t, r, t, radius);
  CGPathCloseSubpath(path);
  return path;
}

static void cloth_gradient(CGContextRef ctx, CGColorSpaceRef srgb, CGPoint start, CGPoint end,
                           const CGFloat colors[12]) {
  CGGradientRef gradient = CGGradientCreateWithColorComponents(srgb, colors, NULL, 3);
  if (!gradient) return;
  CGContextDrawLinearGradient(ctx, gradient, start, end,
                              kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
  CGGradientRelease(gradient);
}

static void snap(CGContextRef ctx, CGFloat x, CGFloat y, CGFloat size) {
  CGRect disc = CGRectMake(x - size / 2, y - size / 2, size, size);
  CGContextSetRGBFillColor(ctx, .48, .34, .16, .47);
  CGContextFillEllipseInRect(ctx, CGRectOffset(disc, 0, -.6));
  CGContextSetRGBFillColor(ctx, .75, .74, .70, 1);
  CGContextFillEllipseInRect(ctx, CGRectInset(disc, size * .07, size * .07));
  CGContextSetRGBFillColor(ctx, .98, .97, .91, .95);
  CGContextFillEllipseInRect(ctx, CGRectMake(x - size * .26, y + size * .02,
                                             size * .41, size * .25));
}

static void draw_placket(CGContextRef ctx, CGRect window, CGFloat radius, CGFloat band) {
  if (band < 4) return;
  CGFloat right = CGRectGetMaxX(window), b = CGRectGetMinY(window) + radius + band;
  CGFloat t = CGRectGetMaxY(window) - radius - band, length = t - b;
  if (length < 22) return;

  // A single overlapping flap, with the snaps on the sheltered side.
  CGFloat x = right + band * .33, width = band * .58;
  CGRect flap = CGRectMake(x, b, width, length);
  CGPathRef patch = CGPathCreateWithRoundedRect(flap, fmin(width * .28, 2.1), 2.1, NULL);
  CGContextSetRGBFillColor(ctx, .64, .36, .035, .28);
  CGContextTranslateCTM(ctx, -.55, -.65);
  CGContextAddPath(ctx, patch);
  CGContextFillPath(ctx);
  CGContextTranslateCTM(ctx, .55, .65);
  CGContextSetRGBFillColor(ctx, 1, .83, .32, .84);
  CGContextAddPath(ctx, patch);
  CGContextFillPath(ctx);
  CGPathRelease(patch);
  int count = 1 + (int)((length - 9) / 39);
  CGFloat size = fmin(5.2, width * .68);
  for (int i = 0; i < count; i++)
    snap(ctx, CGRectGetMidX(flap), (b + t) / 2 + (i - (count - 1) / 2.0) * 39, size);
}

static void draw_cord(CGContextRef ctx, CGPoint eyelet, CGPoint tip, CGFloat weight) {
  CGPoint bend = CGPointMake(eyelet.x + (tip.x - eyelet.x) * .08, tip.y + 2);
  CGContextSetLineCap(ctx, kCGLineCapRound);
  CGContextSetRGBStrokeColor(ctx, .48, .28, .065, .52);
  CGContextSetLineWidth(ctx, weight + .85);
  CGContextMoveToPoint(ctx, eyelet.x, eyelet.y);
  CGContextAddQuadCurveToPoint(ctx, bend.x + .35, bend.y, tip.x + .45, tip.y - .36);
  CGContextStrokePath(ctx);
  CGContextSetRGBStrokeColor(ctx, 1, .968, .82, 1);
  CGContextSetLineWidth(ctx, weight);
  CGContextMoveToPoint(ctx, eyelet.x, eyelet.y);
  CGContextAddQuadCurveToPoint(ctx, bend.x, bend.y, tip.x, tip.y);
  CGContextStrokePath(ctx);
  CGContextSetRGBStrokeColor(ctx, .73, .68, .54, 1);
  CGContextMoveToPoint(ctx, tip.x - .2, tip.y + 1.1);
  CGContextAddLineToPoint(ctx, tip.x, tip.y);
  CGContextStrokePath(ctx);
}

static void draw_hood(CGContextRef ctx, CGColorSpaceRef srgb, struct hood hood, CGFloat band) {
  CGFloat x = hood.x, y = hood.y, w = hood.half, h = hood.lift;
  // The collar dips onto the coat body and connects the hood to its shoulders.
  CGMutablePathRef shell = CGPathCreateMutable();
  CGPathMoveToPoint(shell, NULL, x - w, y);
  hood_crown(shell, hood);
  CGPathAddCurveToPoint(shell, NULL, x + w * .72, y - band * .10,
                      x + w * .52, y - band * .70, x + w * .08, y - band * .72);
  CGPathAddCurveToPoint(shell, NULL, x - w * .41, y - band * .76,
                      x - w * .75, y - band * .24, x - w, y);
  CGPathCloseSubpath(shell);

  CGContextSaveGState(ctx);
  CGContextAddPath(ctx, shell);
  CGContextClip(ctx);
  const CGFloat hood_yellow[] = {1, .88, .43, 1, 1, .82, .29, 1, .94, .66, .15, 1};
  cloth_gradient(ctx, srgb, CGPointMake(x - w * .30, y + h),
                CGPointMake(x + w * .19, y - band), hood_yellow);
  CGContextRestoreGState(ctx);
  CGContextSetLineWidth(ctx, .9);
  CGContextSetRGBStrokeColor(ctx, .68, .40, .075, .37);
  CGContextAddPath(ctx, shell);
  CGContextStrokePath(ctx);
  CGPathRelease(shell);

  // Warm lining shows through the opening, with a thin folded lip.
  CGMutablePathRef lining = CGPathCreateMutable();
  CGPathMoveToPoint(lining, NULL, x - w * .54, y + h * .29);
  CGPathAddCurveToPoint(lining, NULL, x - w * .55, y + h * .67, x - w * .32, y + h * .83,
                      x - w * .04, y + h * .83);
  CGPathAddCurveToPoint(lining, NULL, x + w * .35, y + h * .85, x + w * .54, y + h * .64,
                      x + w * .53, y + h * .28);
  CGPathAddCurveToPoint(lining, NULL, x + w * .31, y + h * .18, x - w * .25, y + h * .15,
                      x - w * .54, y + h * .29);
  CGPathCloseSubpath(lining);
  CGContextSaveGState(ctx);
  CGContextAddPath(ctx, lining);
  CGContextClip(ctx);
  const CGFloat amber[] = {.62, .35, .09, 1, .80, .50, .13, 1, .96, .71, .26, 1};
  cloth_gradient(ctx, srgb, CGPointMake(x, y + h * .8), CGPointMake(x, y + h * .23), amber);
  CGContextRestoreGState(ctx);
  CGContextSetLineWidth(ctx, .85);
  CGContextSetRGBStrokeColor(ctx, 1, .93, .59, .77);
  CGContextAddPath(ctx, lining);
  CGContextStrokePath(ctx);
  CGPathRelease(lining);

  CGPoint left = CGPointMake(x - w * .27, y + h * .14);
  CGPoint right = CGPointMake(x + w * .26, y + h * .12);
  CGFloat cord = fmin(1.65, .9 + h * .025);
  snap(ctx, left.x, left.y, cord * 2.1);
  snap(ctx, right.x, right.y, cord * 2.1);
  draw_cord(ctx, left, CGPointMake(left.x - w * .09, y - band * .41), cord);
  draw_cord(ctx, right, CGPointMake(right.x + w * .07, y - band * .74), cord);
  if (band >= 5) snap(ctx, x, y - band * .41, fmin(4.8, band * .46));
}

void raincoat_draw(CGContextRef ctx, CGRect window, CGFloat radius, CGFloat band,
                   CGFloat dim, CGFloat tuck) {
  if (!ctx || !isfinite(radius) || !isfinite(band) || !isfinite(tuck) ||
      !isfinite(window.origin.x) || !isfinite(window.origin.y) ||
      !isfinite(window.size.width) || !isfinite(window.size.height) ||
      CGRectIsEmpty(window)) return;

  CGFloat half = fmin(window.size.width, window.size.height) / 2;
  radius = fmax(0, fmin(radius, half));
  band = fmax(2, band);
  tuck = fmax(1, fmin(tuck, half - 2));
  CGFloat outer_radius = radius + band;
  CGRect outer = CGRectInset(window, -band, -band);
  CGRect inner = CGRectInset(window, tuck, tuck);
  CGFloat inner_radius = fmax(0, radius - tuck);
  struct hood hood = {CGRectGetMidX(outer), CGRectGetMaxY(outer),
                      fmin(45, window.size.width * .25), raincoat_hood_height(window.size.width)};
  // Keep the hood away from the window's rounded shoulders.
  hood.half = fmin(hood.half, window.size.width / 2 - radius - 2);
  if (hood.half < 18) hood.lift = 0;

  CGContextSaveGState(ctx);
  CGPathRef outline = coat_outline(outer, outer_radius, hood);
  CGMutablePathRef ring = CGPathCreateMutableCopy(outline);
  if (!CGRectIsEmpty(inner)) CGPathAddRoundedRect(ring, NULL, inner, inner_radius, inner_radius);
  CGContextAddPath(ctx, ring);
  CGContextEOClip(ctx);
  CGPathRelease(ring);

  CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  const CGFloat yellow[] = {1, .87, .40, 1, 1, .81, .26, 1, .96, .72, .20, 1};
  cloth_gradient(ctx, srgb, CGPointMake(CGRectGetMinX(outer), CGRectGetMaxY(outer)),
                CGPointMake(CGRectGetMaxX(outer), CGRectGetMinY(outer)), yellow);

  CGContextSetLineWidth(ctx, fmin(1.7, band * .29));
  CGContextSetRGBStrokeColor(ctx, .66, .38, .065, .44);
  CGContextAddPath(ctx, outline);
  CGContextStrokePath(ctx);
  CGPathRelease(outline);

  // A quiet stitched hem instead of a bright outline around every edge.
  CGFloat hem = CGRectGetMinY(outer) + band * .40;
  CGFloat left = CGRectGetMinX(outer) + outer_radius, right = CGRectGetMaxX(outer) - outer_radius;
  if (right > left && band >= 4) {
    const CGFloat stitch[] = {2.0, 2.9};
    CGContextSaveGState(ctx);
    CGContextSetLineDash(ctx, 0, stitch, 2);
    CGContextSetLineWidth(ctx, .85);
    CGContextSetRGBStrokeColor(ctx, .64, .39, .09, .48);
    CGContextMoveToPoint(ctx, left, hem);
    CGContextAddLineToPoint(ctx, right, hem);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);
  }

  draw_placket(ctx, window, radius, band);
  if (hood.lift) draw_hood(ctx, srgb, hood, band);
  CGColorSpaceRelease(srgb);

  if (dim > 0) {
    CGContextSetRGBFillColor(ctx, .25, .14, .02, fmin(1, dim));
    CGContextFillRect(ctx, CGRectMake(CGRectGetMinX(outer), CGRectGetMinY(outer),
                                     outer.size.width, outer.size.height + hood.lift + 2));
  }
  CGContextRestoreGState(ctx);
}
