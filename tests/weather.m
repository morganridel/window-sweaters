#import "../src/weather.m"
#include <assert.h>

@interface RecordingRain : KnitDesktopRain
@property NSInteger recorded;
@end
@implementation RecordingRain
- (void)setIntensity:(NSInteger)value { self.recorded = value; }
@end

int main(void) {
  @autoreleasepool {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970, observed = 0;
    assert(rain_intensity(53) == 1 && rain_intensity(81) == 2 && rain_intensity(95) == 3);
    assert(rain_intensity(75) == 0 && rain_intensity(1) == 0);
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
    RecordingRain* rain = [RecordingRain new];
    weather.rain = rain;
    weather.showDesktopRain = YES;
    weather.automatic = YES;
    weather.weatherCode = code;
    weather.observationTime = observed;
    __block BOOL coat = NO;
    weather.raincoatChange = ^(BOOL on) { coat = on; };
    [weather applyWeather];
    assert(coat && rain.recorded == 3);

    [weather togglePreview:nil];
    weather.weatherCode = @0;
    [weather applyWeather];
    assert(coat && rain.recorded == 2);
    weather.showDesktopRain = NO;
    [weather applyWeather];
    assert(coat && !rain.recorded);
    [weather endPreview];
    assert(!coat && !rain.recorded);

    weather.showDesktopRain = YES;
    weather.weatherCode = @65;
    weather.observationTime = now - 3600;
    [weather applyWeather];
    assert(!coat && !rain.recorded);
  }
  puts("PASS: fresh weather, city parsing, rain intensity, preview, animation off, stale fallback");
  return 0;
}
