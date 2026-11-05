#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

extern bool g_knit_raincoat;

// Extra room above the usual border for the hood silhouette.
CGFloat raincoat_hood_height(CGFloat window_width);

void raincoat_draw(CGContextRef ctx, CGRect window, CGFloat radius, CGFloat band,
                   CGFloat dim, CGFloat tuck);
