#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, KnitWeatherEffect) {
  KnitWeatherEffectNone,
  KnitWeatherEffectRain,
  KnitWeatherEffectSnow,
  KnitWeatherEffectFog,
  KnitWeatherEffectClouds
};

@interface KnitDesktopWeather : NSObject
// Intensity 1–3 changes density. None removes the desktop overlay.
- (void)showEffect:(KnitWeatherEffect)effect intensity:(NSInteger)intensity;
@end
