#include "raincoat.h"
#include <math.h>

bool g_knit_raincoat = false;

static void stroke_edge(CGContextRef ctx, CGRect bounds, CGFloat radius,
                        CGFloat inset, CGFloat width) {
  CGPathRef path = CGPathCreateWithRoundedRect(CGRectInset(bounds, inset, inset),
                                               fmax(0, radius - inset),
                                               fmax(0, radius - inset), NULL);
  CGContextSetLineWidth(ctx, width);
  CGContextAddPath(ctx, path);
  CGContextStrokePath(ctx);
  CGPathRelease(path);
}

static void draw_snaps(CGContextRef ctx, CGRect window, CGFloat radius, CGFloat band) {
  CGFloat top = CGRectGetMaxY(window) - radius - band;
  CGFloat bottom = CGRectGetMinY(window) + radius + band;
  if (top - bottom < 24 || band < 5) return;
  CGFloat x = CGRectGetMaxX(window) + band * 0.54;
  CGFloat size = fmin(5, band * 0.42);
  int count = 1 + (int)((top - bottom) / 52);
  for (int i = 0; i < count; i++) {
    CGFloat y = (top + bottom) / 2 + (i - (count - 1) / 2.0) * 52;
    CGRect snap = CGRectMake(x - size / 2, y - size / 2, size, size);
    CGContextSetRGBFillColor(ctx, 0.33, 0.23, 0.11, 0.85);
    CGContextFillEllipseInRect(ctx, CGRectOffset(snap, 0, -0.7));
    CGContextSetRGBFillColor(ctx, 0.68, 0.71, 0.70, 1);
    CGContextFillEllipseInRect(ctx, CGRectInset(snap, size * 0.10, size * 0.10));
    CGContextSetRGBFillColor(ctx, 1, 0.98, 0.85, 0.9);
    CGContextFillEllipseInRect(ctx, CGRectMake(x - size * 0.24, y + size * 0.06,
                                               size * 0.36, size * 0.21));
  }
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
  CGFloat inner_radius = fmax(0, radius - tuck);
  CGRect outer = CGRectInset(window, -band, -band);
  CGRect inner = CGRectInset(window, tuck, tuck);

  CGContextSaveGState(ctx);
  CGMutablePathRef ring = CGPathCreateMutable();
  CGPathAddRoundedRect(ring, NULL, outer, outer_radius, outer_radius);
  if (!CGRectIsEmpty(inner)) CGPathAddRoundedRect(ring, NULL, inner, inner_radius, inner_radius);
  CGContextAddPath(ctx, ring);
  CGContextEOClip(ctx);
  CGPathRelease(ring);

  // Glossy PVC: lemon at the shoulder, taxi yellow through the body, amber at the hem.
  const CGFloat colors[] = {
    1.00, 0.89, 0.30, 1,
    1.00, 0.78, 0.08, 1,
    0.97, 0.66, 0.03, 1
  };
  const CGFloat stops[] = {0, 0.38, 1};
  CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGGradientRef finish = CGGradientCreateWithColorComponents(srgb, colors, stops, 3);
  if (finish) {
    CGContextDrawLinearGradient(ctx, finish,
      CGPointMake(CGRectGetMidX(outer), CGRectGetMaxY(outer)),
      CGPointMake(CGRectGetMidX(outer), CGRectGetMinY(outer)), 0);
    CGGradientRelease(finish);
  } else {
    CGContextSetRGBFillColor(ctx, 1, 0.78, 0.08, 1);
    CGContextFillRect(ctx, outer);
  }
  CGColorSpaceRelease(srgb);

  CGFloat edge = fmin(1.15, band * 0.15);
  CGContextSetRGBStrokeColor(ctx, 0.58, 0.30, 0.035, 0.85);
  stroke_edge(ctx, outer, outer_radius, edge / 2, edge);
  CGContextSetRGBStrokeColor(ctx, 1, 0.97, 0.69, 0.69);
  stroke_edge(ctx, outer, outer_radius, band * 0.24, fmin(1.1, band * 0.12));
  CGContextSetRGBStrokeColor(ctx, 0.74, 0.43, 0.025, 0.57);
  stroke_edge(ctx, outer, outer_radius, band * 0.82, fmin(0.9, band * 0.11));
  draw_snaps(ctx, window, radius, band);

  if (dim > 0) {
    CGContextSetRGBFillColor(ctx, 0.25, 0.14, 0.02, fmin(1, dim));
    CGContextFillRect(ctx, outer);
  }
  CGContextRestoreGState(ctx);
}
