#import <Cocoa/Cocoa.h>

@interface KnitDesktopRain : NSObject
// 0 removes all rain windows. 1–3 are drizzle, rain and downpour.
@property(nonatomic) NSInteger intensity;
@end
