#include "raincoat.h"
#include <math.h>

bool g_knit_raincoat = false;

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
  CGContextSaveGState(ctx);
  CGPathRef outline = CGPathCreateWithRoundedRect(outer, outer_radius, outer_radius, NULL);
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
  CGColorSpaceRelease(srgb);

  if (dim > 0) {
    CGContextSetRGBFillColor(ctx, .25, .14, .02, fmin(1, dim));
    CGContextFillRect(ctx, outer);
  }
  CGContextRestoreGState(ctx);
}
