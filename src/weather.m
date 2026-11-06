#import "weather.h"
#import "desktop_weather.h"

static NSString* const CityKey = @"weatherCity";
static NSString* const AutomaticKey = @"weatherAutomatic";
// Keep the stored preference from the original rain-only version.
static NSString* const DesktopWeatherKey = @"weatherDesktopRain";
static const NSTimeInterval RefreshInterval = 10 * 60;
static const NSTimeInterval MaxObservationAge = 45 * 60;
static const NSTimeInterval PreviewDuration = 5 * 60;

typedef struct {
  KnitWeatherEffect effect;
  NSInteger intensity;
  __unsafe_unretained NSString* label;
} WeatherScene;

static WeatherScene scene_for_code(NSInteger code) {
  // Open-Meteo WMO interpretation codes.
  switch (code) {
    case 2: return (WeatherScene){KnitWeatherEffectClouds, 1, @"Partly Cloudy"};
    case 3: return (WeatherScene){KnitWeatherEffectClouds, 3, @"Overcast"};
    case 45: return (WeatherScene){KnitWeatherEffectFog, 2, @"Fog"};
    case 48: return (WeatherScene){KnitWeatherEffectFog, 3, @"Freezing Fog"};
    case 51: case 53: case 55: case 56: case 57:
      return (WeatherScene){KnitWeatherEffectRain, 1, @"Drizzle"};
    case 61: case 80: return (WeatherScene){KnitWeatherEffectRain, 1, @"Light Rain"};
    case 63: case 66: case 81: return (WeatherScene){KnitWeatherEffectRain, 2, @"Rain"};
    case 65: case 67: case 82: return (WeatherScene){KnitWeatherEffectRain, 3, @"Heavy Rain"};
    case 95: case 96: case 97: case 99:
      return (WeatherScene){KnitWeatherEffectRain, 3, @"Thunderstorm"};
    case 71: case 77: case 85: return (WeatherScene){KnitWeatherEffectSnow, 1, @"Light Snow"};
    case 73: return (WeatherScene){KnitWeatherEffectSnow, 2, @"Snow"};
    case 75: case 86: return (WeatherScene){KnitWeatherEffectSnow, 3, @"Heavy Snow"};
    case 0: return (WeatherScene){KnitWeatherEffectNone, 0, @"Clear"};
    case 1: return (WeatherScene){KnitWeatherEffectNone, 0, @"Mostly Clear"};
    default: return (WeatherScene){KnitWeatherEffectNone, 0, @"No Weather Effect"};
  }
}

static NSString* effect_name(KnitWeatherEffect effect) {
  switch (effect) {
    case KnitWeatherEffectRain: return @"Rain";
    case KnitWeatherEffectSnow: return @"Snow";
    case KnitWeatherEffectFog: return @"Fog";
    case KnitWeatherEffectClouds: return @"Clouds";
    case KnitWeatherEffectNone: return @"None";
  }
}

static NSDictionary* dictionary(id object) {
  return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static NSNumber* number(id object) {
  return [object isKindOfClass:NSNumber.class] &&
    CFGetTypeID((__bridge CFTypeRef)object) != CFBooleanGetTypeID() ? object : nil;
}

static NSString* string(id object) {
  return [object isKindOfClass:NSString.class] ? object : nil;
}

static BOOL valid_city(NSDictionary* city) {
  NSNumber* lat = number(city[@"latitude"]), *lon = number(city[@"longitude"]);
  return string(city[@"label"]).length && lat && lon &&
    fabs(lat.doubleValue) <= 90 && fabs(lon.doubleValue) <= 180;
}

static NSArray<NSDictionary*>* cities_from_response(NSDictionary* response) {
  NSMutableArray* cities = [NSMutableArray array];
  id results = response[@"results"];
  if (![results isKindOfClass:NSArray.class]) return cities;
  for (id result in results) {
    NSDictionary* entry = dictionary(result);
    NSString* name = string(entry[@"name"]);
    if (!name.length) continue;
    NSMutableOrderedSet* parts = [NSMutableOrderedSet orderedSetWithObject:name];
    for (NSString* key in @[@"admin1", @"country"]) {
      NSString* part = string(entry[key]);
      if (part.length) [parts addObject:part];
    }
    NSDictionary* city = @{@"label": [parts.array componentsJoinedByString:@", "],
      @"latitude": entry[@"latitude"] ?: NSNull.null,
      @"longitude": entry[@"longitude"] ?: NSNull.null};
    if (valid_city(city)) [cities addObject:city];
  }
  return cities;
}

static NSURL* url_with_query(NSString* endpoint, NSDictionary<NSString*, NSString*>* query) {
  NSURLComponents* url = [NSURLComponents componentsWithString:endpoint];
  NSMutableArray* items = [NSMutableArray array];
  for (NSString* name in query)
    [items addObject:[NSURLQueryItem queryItemWithName:name value:query[name]]];
  // Open-Meteo's query parser interprets bare plus signs as spaces.
  url.queryItems = items;
  url.percentEncodedQuery = [url.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+"
                                                                               withString:@"%2B"];
  return url.URL;
}

static NSURL* forecast_url(NSDictionary* city) {
  return url_with_query(@"https://api.open-meteo.com/v1/forecast", @{
    @"latitude": [NSString stringWithFormat:@"%.2f", [city[@"latitude"] doubleValue]],
    @"longitude": [NSString stringWithFormat:@"%.2f", [city[@"longitude"] doubleValue]],
    @"current": @"weather_code",
    @"timeformat": @"unixtime"
  });
}

static BOOL fresh_observation(NSTimeInterval observed, NSTimeInterval now) {
  return observed > 0 && now - observed <= MaxObservationAge && observed - now <= 15 * 60;
}

static NSNumber* observation_code(NSDictionary* response, NSTimeInterval now,
                                  NSTimeInterval* observed) {
  NSDictionary* current = dictionary(response[@"current"]);
  NSNumber* time = number(current[@"time"]), *code = number(current[@"weather_code"]);
  if (!time || !code || !fresh_observation(time.doubleValue, now)) return nil;
  double value = code.doubleValue;
  if (!(value >= 0 && value <= 99) || floor(value) != value) return nil;
  *observed = time.doubleValue;
  return code;
}

@interface KnitWeather ()
@property(strong) KnitDesktopWeather* desktop;
@property(copy) void (^raincoatChange)(BOOL);
@property(strong) NSURLSession* session;
@property(strong) NSURLSessionDataTask* forecast;
@property(strong) NSTimer* pollTimer;
@property(strong) NSTimer* previewTimer;
@property(copy) NSDictionary* city;
@property(strong) NSNumber* weatherCode;
@property NSTimeInterval observationTime;
@property BOOL automatic;
@property BOOL showDesktopWeather;
@property KnitWeatherEffect previewEffect;
@property BOOL searching;
@end

@implementation KnitWeather

- (instancetype)initWithRaincoatChange:(void (^)(BOOL))change {
  if (!(self = [super init])) return nil;
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  NSDictionary* city = dictionary([defaults objectForKey:CityKey]);
  if (valid_city(city)) self.city = city;
  self.automatic = self.city && [defaults boolForKey:AutomaticKey];
  self.showDesktopWeather = [defaults objectForKey:DesktopWeatherKey] == nil ||
                         [defaults boolForKey:DesktopWeatherKey];
  self.raincoatChange = change;
  self.desktop = [KnitDesktopWeather new];
  NSURLSessionConfiguration* config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
  config.timeoutIntervalForRequest = 12;
  config.timeoutIntervalForResource = 20;
  config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  self.session = [NSURLSession sessionWithConfiguration:config];
  [self updatePolling];
  return self;
}

- (void)dealloc {
  [_session invalidateAndCancel];
  [_pollTimer invalidate];
  [_previewTimer invalidate];
}

- (BOOL)hasLiveWeather {
  return self.automatic && self.weatherCode &&
    fresh_observation(self.observationTime, NSDate.date.timeIntervalSince1970);
}

- (void)applyWeather {
  WeatherScene scene = {0};
  if (self.previewEffect) scene = (WeatherScene){self.previewEffect, 2, nil};
  else if (self.hasLiveWeather) scene = scene_for_code(self.weatherCode.integerValue);
  self.raincoatChange(scene.effect == KnitWeatherEffectRain);
  [self.desktop showEffect:self.showDesktopWeather ? scene.effect : KnitWeatherEffectNone
                 intensity:scene.intensity];
}

- (NSURLSessionDataTask*)get:(NSURL*)url completion:(void (^)(NSDictionary*))complete {
  NSURLSessionDataTask* task = [self.session dataTaskWithURL:url
      completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
    NSDictionary* result = nil;
    if (!error && data && [(NSHTTPURLResponse*)response statusCode] == 200) {
      result = dictionary([NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ complete(result); });
  }];
  [task resume];
  return task;
}

- (void)refresh {
  [self applyWeather]; // expire old weather even if the new fetch fails
  if (!self.automatic || !self.city || self.forecast) return;
  __weak KnitWeather* weakSelf = self;
  // Compare task identifiers so a delayed reply can't restore an old city.
  __block NSUInteger identifier;
  self.forecast = [self get:forecast_url(self.city) completion:^(NSDictionary* result) {
    KnitWeather* weather = weakSelf;
    if (!weather || weather.forecast.taskIdentifier != identifier) return;
    weather.forecast = nil;
    NSTimeInterval observed = 0;
    NSNumber* code = observation_code(result, NSDate.date.timeIntervalSince1970, &observed);
    if (code) {
      weather.weatherCode = code;
      weather.observationTime = observed;
    }
    [weather applyWeather];
  }];
  identifier = self.forecast.taskIdentifier;
}

- (void)updatePolling {
  [self.forecast cancel];
  self.forecast = nil;
  self.weatherCode = nil;
  self.observationTime = 0;
  [self.pollTimer invalidate];
  self.pollTimer = nil;
  [self refresh];
  if (!self.automatic) return;
  __weak KnitWeather* weakSelf = self;
  self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:RefreshInterval repeats:YES
      block:^(NSTimer* timer) { (void)timer; [weakSelf refresh]; }];
  self.pollTimer.tolerance = 30;
}

- (void)toggleAutomatic:(id)sender {
  if (!self.city) { [self chooseCity:sender]; return; }
  self.automatic = !self.automatic;
  [NSUserDefaults.standardUserDefaults setBool:self.automatic forKey:AutomaticKey];
  [self updatePolling];
}

- (void)toggleDesktopWeather:(id)sender {
  self.showDesktopWeather = !self.showDesktopWeather;
  [NSUserDefaults.standardUserDefaults setBool:self.showDesktopWeather forKey:DesktopWeatherKey];
  [self applyWeather];
}

- (void)endPreview {
  [self.previewTimer invalidate];
  self.previewTimer = nil;
  self.previewEffect = KnitWeatherEffectNone;
  [self applyWeather];
}

- (void)stopPreview:(id)sender {
  [self endPreview];
}

- (void)startPreview:(NSMenuItem*)sender {
  [self.previewTimer invalidate];
  self.previewEffect = sender.tag;
  __weak KnitWeather* weakSelf = self;
  self.previewTimer = [NSTimer scheduledTimerWithTimeInterval:PreviewDuration repeats:NO
      block:^(NSTimer* timer) { (void)timer; [weakSelf endPreview]; }];
  [self applyWeather];
}

- (void)chooseCity:(id)sender {
  if (self.searching) return;
  NSAlert* alert = [NSAlert new];
  alert.messageText = @"Find Your Weather City";
  alert.informativeText = @"Open-Meteo receives the city name when you search, and the selected city’s approximate coordinates for weather updates.";
  NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
  field.placeholderString = @"City name";
  [field setAccessibilityLabel:@"City name"];
  alert.accessoryView = field;
  [alert addButtonWithTitle:@"Search"];
  [alert addButtonWithTitle:@"Cancel"];
  alert.window.initialFirstResponder = field;
  [NSApp activateIgnoringOtherApps:YES];
  if ([alert runModal] != NSAlertFirstButtonReturn) return;
  NSString* name = [field.stringValue stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (name.length < 2) return;
  self.searching = YES;
  NSURL* url = url_with_query(@"https://geocoding-api.open-meteo.com/v1/search",
                            @{@"name":name, @"count":@"8", @"language":@"en"});
  __weak KnitWeather* weakSelf = self;
  [self get:url completion:^(NSDictionary* result) {
    [weakSelf offerCities:cities_from_response(result) searchFailed:result == nil];
  }];
}

- (void)offerCities:(NSArray<NSDictionary*>*)cities searchFailed:(BOOL)failed {
  self.searching = NO;
  NSAlert* alert = [NSAlert new];
  [NSApp activateIgnoringOtherApps:YES];
  if (!cities.count) {
    alert.messageText = failed ? @"City Search Is Unavailable" : @"No Matching Cities";
    alert.informativeText = failed ? @"Try again in a moment." : @"Try another spelling or a nearby city.";
    [alert runModal];
    return;
  }

  alert.messageText = @"Choose a Weather City";
  alert.informativeText = @"Window Sweaters will follow the weather in this city.";
  NSPopUpButton* choices = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 320, 26)
                                                       pullsDown:NO];
  [choices setAccessibilityLabel:@"Matching cities"];
  for (NSDictionary* city in cities) {
    // Add an item directly so places with identical labels stay selectable.
    [choices.menu addItem:[[NSMenuItem alloc] initWithTitle:city[@"label"] action:NULL keyEquivalent:@""]];
  }
  [choices selectItemAtIndex:0];
  alert.accessoryView = choices;
  [alert addButtonWithTitle:@"Use City"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn || choices.indexOfSelectedItem < 0) return;
  self.city = cities[choices.indexOfSelectedItem];
  self.automatic = YES;
  [NSUserDefaults.standardUserDefaults setObject:self.city forKey:CityKey];
  [NSUserDefaults.standardUserDefaults setBool:YES forKey:AutomaticKey];
  [self updatePolling];
}

- (NSMenuItem*)addTo:(NSMenu*)menu title:(NSString*)title action:(SEL)action checked:(BOOL)checked {
  NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
  item.target = action ? self : nil;
  item.enabled = action != NULL;
  item.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
  [menu addItem:item];
  return item;
}

- (void)populateMenu:(NSMenu*)menu {
  NSString* status;
  if (self.previewEffect)
    status = [NSString stringWithFormat:@"%@ Preview · Ends Automatically", effect_name(self.previewEffect)];
  else if (!self.automatic) status = @"Live Weather Is Off";
  else if (!self.hasLiveWeather) status = self.forecast ? @"Checking Weather…" : @"Weather Is Unavailable";
  else status = scene_for_code(self.weatherCode.integerValue).label;

  if (self.city) status = [NSString stringWithFormat:@"%@ · %@", self.city[@"label"], status];
  [self addTo:menu title:status action:NULL checked:NO];
  [menu addItem:NSMenuItem.separatorItem];
  [self addTo:menu title:@"Follow Local Weather" action:@selector(toggleAutomatic:) checked:self.automatic];
  [self addTo:menu title:self.searching ? @"Searching for Cities…" : @"Choose City…"
      action:self.searching ? NULL : @selector(chooseCity:) checked:NO];
  [self addTo:menu title:@"Show Desktop Weather" action:@selector(toggleDesktopWeather:) checked:self.showDesktopWeather];
  BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  if (self.showDesktopWeather && reduceMotion)
    [self addTo:menu title:@"Animation Paused by Reduce Motion" action:NULL checked:NO];
  [menu addItem:NSMenuItem.separatorItem];

  NSMenuItem* previewItem = [self addTo:menu title:@"Preview Weather" action:NULL checked:NO];
  previewItem.enabled = YES;
  previewItem.toolTip = @"Previews end after five minutes.";
  NSMenu* previews = [[NSMenu alloc] initWithTitle:previewItem.title];
  previews.autoenablesItems = NO;
  const KnitWeatherEffect effects[] = {KnitWeatherEffectRain, KnitWeatherEffectSnow,
    KnitWeatherEffectFog, KnitWeatherEffectClouds};
  for (NSUInteger i = 0; i < sizeof effects / sizeof effects[0]; i++) {
    KnitWeatherEffect effect = effects[i];
    NSMenuItem* item = [self addTo:previews title:effect_name(effect) action:@selector(startPreview:)
                          checked:self.previewEffect == effect];
    item.tag = effect;
    // Rain can still preview the coat if the user turned off desktop motion.
    item.enabled = effect == KnitWeatherEffectRain || (self.showDesktopWeather && !reduceMotion);
  }
  previewItem.submenu = previews;
  if (self.previewEffect)
    [self addTo:menu title:@"End Preview" action:@selector(stopPreview:) checked:NO];
}
@end
