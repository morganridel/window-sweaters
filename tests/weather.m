#import "../src/weather.m"
#include <assert.h>

@interface RecordingDesktop : KnitDesktopWeather
@property KnitWeatherEffect effect;
@property NSInteger intensity;
@end
@implementation RecordingDesktop
- (void)showEffect:(KnitWeatherEffect)effect intensity:(NSInteger)intensity {
  self.effect = effect;
  self.intensity = effect ? intensity : 0;
}
@end

int main(void) {
  @autoreleasepool {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970, observed = 0;
    assert(scene_for_code(53).effect == KnitWeatherEffectRain && scene_for_code(53).intensity == 1);
    assert(scene_for_code(81).intensity == 2 && scene_for_code(95).intensity == 3);
    assert(scene_for_code(75).effect == KnitWeatherEffectSnow && scene_for_code(75).intensity == 3);
    assert(scene_for_code(45).effect == KnitWeatherEffectFog && scene_for_code(48).intensity == 3);
    assert(scene_for_code(2).effect == KnitWeatherEffectClouds && scene_for_code(3).intensity == 3);
    assert(scene_for_code(1).effect == KnitWeatherEffectNone);
    assert(!observation_code(@{@"current": @{@"time": @(now - 3600), @"weather_code": @63}},
                             now, &observed));
    assert(!observation_code(@{@"current": @{@"time": @(now), @"weather_code": @YES}},
                             now, &observed));
    NSNumber* code = observation_code(@{@"current": @{@"time": @(now - 300), @"weather_code": @65}},
                                       now, &observed);
    assert(code.integerValue == 65 && observed == now - 300);

    NSArray* cities = cities_from_response(@{@"results": @[
      @{@"name": @"Brussels", @"admin1": @"Brussels", @"country": @"Belgium",
        @"latitude": @50.85045, @"longitude": @4.34878},
      @{@"name": @"Broken", @"latitude": @190, @"longitude": @0},
      NSNull.null
    ]});
    assert(cities.count == 1 && [cities[0][@"label"] isEqual:@"Brussels, Belgium"]);
    NSString* query = forecast_url(cities[0]).query;
    assert([query containsString:@"latitude=50.85"] && [query containsString:@"longitude=4.35"]);

    KnitWeather* weather = [KnitWeather new];
    RecordingDesktop* desktop = [RecordingDesktop new];
    weather.desktop = desktop;
    weather.showDesktopWeather = YES;
    weather.automatic = YES;
    weather.weatherCode = code;
    weather.observationTime = observed;
    __block BOOL coat = NO;
    weather.raincoatChange = ^(BOOL on) { coat = on; };
    [weather applyWeather];
    assert(coat && desktop.effect == KnitWeatherEffectRain && desktop.intensity == 3);

    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Weather"];
    [weather populateMenu:menu];
    NSMenu* previews = [menu itemWithTitle:@"Preview Weather"].submenu;
    assert(previews.numberOfItems == 4);
    [weather startPreview:[previews itemWithTitle:@"Rain"]];
    assert(coat && desktop.intensity == 2);
    NSTimer* first = weather.previewTimer;
    [weather startPreview:[previews itemWithTitle:@"Snow"]];
    assert(!first.valid && weather.previewTimer.valid);
    assert(!coat && desktop.effect == KnitWeatherEffectSnow);
    weather.weatherCode = @45;
    [weather applyWeather];
    assert(desktop.effect == KnitWeatherEffectSnow);
    [weather endPreview];
    assert(!coat && desktop.effect == KnitWeatherEffectFog);

    weather.showDesktopWeather = NO;
    weather.weatherCode = @63;
    [weather applyWeather];
    assert(coat && desktop.effect == KnitWeatherEffectNone);
    weather.showDesktopWeather = YES;
    weather.observationTime = now - 3600;
    [weather applyWeather];
    assert(!coat && desktop.effect == KnitWeatherEffectNone);
  }
  puts("PASS: fresh weather, city parsing, weather scenes, preview switching, animation off, stale fallback");
  return 0;
}
