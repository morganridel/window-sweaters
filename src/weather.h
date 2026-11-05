#import <Cocoa/Cocoa.h>

@interface KnitWeather : NSObject
- (instancetype)initWithRaincoatChange:(void (^)(BOOL on))change;
- (void)populateMenu:(NSMenu*)menu;
@end
