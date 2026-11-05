#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

extern bool g_knit_raincoat;

void raincoat_draw(CGContextRef ctx, CGRect window, CGFloat radius, CGFloat band,
                   CGFloat dim, CGFloat tuck);
