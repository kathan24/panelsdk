//
//  xAdPanelSdk.m
//  xAd Panel SDK
//
//  Created by Stephen Anderson on 1/21/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "xAdPanelSdk.h"
#import "xAdPanelSettings.h"

#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <AdSupport/ASIdentifierManager.h>

#define SUPPORT_SSL


static NSString * const PANEL_SDK_VERSION = @"1.2";


@interface xAdPanelSdk ()
@property (strong, nonatomic) NSTimer *stationaryConfirmTimer;
@property (strong, nonatomic) NSTimer *reportLocationTimer;

@property (strong, nonatomic) CLLocation *lastReportedLocation;
    
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) CMMotionActivityManager *activityManager;
@property (strong, nonatomic) CMMotionManager *motionManager; // fallback

@property (nonatomic, strong) xAdPanelSettings *settings;
@property (nonatomic, assign) CLLocationDistance distanceThreshold;
@property (nonatomic, assign) BOOL locationEnabled;

@end


@implementation xAdPanelSdk
    
+ (xAdPanelSdk*) sharedInstance
{
    static xAdPanelSdk *singleton = nil;
    
    @synchronized(self)
    {
        if (singleton) {
            return singleton;
        }
        
        singleton = [[xAdPanelSdk alloc] init];
        return singleton;
    }
}


#pragma mark - Starting/Stopping the Services

+ (void) startPanelSdkWithAppKey:(id)appKey {
    
    xAdPanelSdk *obj = [xAdPanelSdk sharedInstance];
    
    if (obj) {
        NSDictionary *defaults = @{
                                   @"xad_panel_dob": [NSDate date],
                                   @"xad_panel_opted_in":@NO,
                                   @"xad_panel_gender":@0
                                   };
        
        [[NSUserDefaults standardUserDefaults] registerDefaults: defaults];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        
        [nc addObserver: obj
               selector: @selector(onSettingsUpdated:)
                   name: @"XAD_SETTINGS_UPDATED"
                 object: nil];
        
        obj.settings = [[xAdPanelSettings alloc] initWithAppKey:appKey];
    }
}



- (void) stopPanelServices {
    [self stopUpdatingLocation];
    [self.activityManager stopActivityUpdates];
    [self.motionManager stopDeviceMotionUpdates];
    
    [self.reportLocationTimer invalidate];
    [self.stationaryConfirmTimer invalidate];
    
    self.distanceThreshold = 9999;
    self.lastReportedLocation = nil;
}


- (void) onSettingsUpdated:(NSNotification*)notification {

    // Restart services
    
    [self stopPanelServices];

    [self startPanelServices];
}



- (BOOL) canStartServices {
    
    if (!self.settings) {
        NSLog(@"Settings not initialized");
        return NO;
    }
    
    // Any of these cases is reason enough not to start the SDK.
    
    if (![xAdPanelSdk userInPanel]) {
        NSLog(@"User is not in panel.");
        return NO;
    }
    
    
    if (self.settings.obeyTrackingFlag && ![[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled]) {
        NSLog(@"Tracking is prohibited");
        return NO;
    }

    if (self.settings.mode == xAdPanelSdkModeDisabled) {
        NSLog(@"xAd wants panel OFF.");
        return NO;
    }
    
#if !TARGET_IPHONE_SIMULATOR
    if (self.settings.requiresM7 && ![CMMotionActivityManager isActivityAvailable]) {
        NSLog(@"M7 chip required but not available");
        return NO;
    }
#endif
    
    return YES;
    
    
    // NOTE: isActivityAvailable is only available on devices with M7.
    // The M7 guaratees a battery effiecient use of the GPS by detecting
    // if the user is stationary and disabling it.
    
    // The panel SDK might take effect during the next launch if all conditions are met
}
    
    
- (void) startPanelServices {
    NSLog(@"startPanelServices");
    
    if (![self canStartServices]) {
        NSLog(@"Panel SDK is DISABLED");
        return;
    }

    if (!self.locationManager) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
    }
    
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = self.settings.distanceFilter;

    if (![CMMotionActivityManager isActivityAvailable] && self.settings.mode == xAdPanelSdkModeConstDistance) {
        NSLog(@"No M7 - switching modes");
        self.settings.mode = xAdPanelSdkModeGpsOnlyOnStop;
    }
    
    switch (self.settings.mode) {
        case xAdPanelSdkModeGpsOnlyOnStop:
            NSLog(@"MODE: GpsOnlyOnStop");
            [self startUpdatingUserActivity];
            [self stopUpdatingLocation];
            break;
        
        case xAdPanelSdkModeConstDistance:
            NSLog(@"MODE: ConstDistance");
            self.distanceThreshold = self.settings.distanceWhileWalking;
            [self startUpdatingUserActivity];
            [self startUpdatingLocation];
            break;
        
        case xAdPanelSdkModeConstTime:
            NSLog(@"MODE: ConstTime");
            [self startUpdatingUserActivity];
            [self startUpdatingLocation];
            self.reportLocationTimer = [NSTimer scheduledTimerWithTimeInterval: self.settings.secondsBetweenSignaling
                                                                        target: self
                                                                      selector: @selector(onReportLocationTimerExpired:)
                                                                      userInfo: nil
                                                                       repeats: YES];
            break;
        
        case xAdPanelSdkModeDisabled:
        default:
            NSLog(@"MODE: Disabled");
            return;
    }
    
    
}


    
#pragma mark - Handling Activity

    
- (void) onActivityDetected:(id)activity {
    
    CLLocationAccuracy newAccuracy = kCLLocationAccuracyBest;
    
    if (self.settings.mode == xAdPanelSdkModeConstDistance) {
        if ([activity walking]) {
            NSLog(@"    [+] walking");
            self.distanceThreshold = self.settings.distanceWhileWalking;
            newAccuracy = kCLLocationAccuracyBest;
        } else if ([activity running]) {
            NSLog(@"    [+] running");
            self.distanceThreshold = self.settings.distanceWhileRunning;
            newAccuracy = kCLLocationAccuracyBest;
        } else if ([activity automotive]) {
            NSLog(@"    [+] automotive");
            self.distanceThreshold = self.settings.distanceWhileDriving;
            newAccuracy = kCLLocationAccuracyBestForNavigation;
        }
        
    }
    
    
        if (activity == nil) {
            self.distanceThreshold = self.settings.distanceWhileWalking;
            newAccuracy = kCLLocationAccuracyBest;
            // User activity from non-M7 device
            NSLog(@"    [+] activity");
        }
    
    
    self.locationManager.desiredAccuracy = newAccuracy;
    
    if (self.settings.mode != xAdPanelSdkModeGpsOnlyOnStop) {
        [self startUpdatingLocation];
    }
}
    

    
#pragma mark - Handling Stationary


- (void) startStationaryConfirmation {
    // Prevent instantanious status change to stationary for cases like traffic lights.
    if (!self.stationaryConfirmTimer) {
        NSLog(@"startStationaryConfirmation");
        self.stationaryConfirmTimer = [NSTimer scheduledTimerWithTimeInterval: self.settings.timeBeforeStationary
                                                                       target: self
                                                                     selector: @selector(onStationaryConfirmed:)
                                                                     userInfo: nil
                                                                      repeats: NO];
    }
}

    
- (void) cancelStationaryConfirmation {
    if (self.stationaryConfirmTimer) {
        NSLog(@"cancelStationaryConfirmation");
        // Activity detected. Cancel timer and adjust based on activity type.
        [self.stationaryConfirmTimer invalidate];
        self.stationaryConfirmTimer = nil;
    }
}

    
-(void) onStationaryConfirmed:(NSTimer *)timer {
    
    NSLog(@"    [+] stationary.");
    
    switch (self.settings.mode) {
        case xAdPanelSdkModeGpsOnlyOnStop:
            [self startUpdatingLocation];
            break;
        
        case xAdPanelSdkModeConstDistance:
        case xAdPanelSdkModeConstTime:
            [self stopUpdatingLocation];
            break;

        case xAdPanelSdkModeDisabled:
        default:
            NSLog(@"Unknown mode or disabled - terminating services");
            [self stopPanelServices];
    }
}

    
    
#pragma mark - User Activity Detection
    
- (void) startUpdatingUserActivity {

    // New devices support activity and older devices use motion
    
    if ([CMMotionActivityManager isActivityAvailable]) {
        [self enableActivityDetection];
    } else {
        [self enableMotionDetection];
    }
}
    
    
- (void) enableActivityDetection {
    self.activityManager = [[CMMotionActivityManager alloc] init];
    
    [self.activityManager startActivityUpdatesToQueue:[[NSOperationQueue alloc] init]
                                          withHandler: ^(CMMotionActivity *activity) {
                                              
                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                  
                                                  if ([activity stationary]) {
                                                      
                                                      [self startStationaryConfirmation];
                                                      
                                                  } else if ([activity walking] || [activity running] || [activity automotive]) {
                                                      
                                                      [self cancelStationaryConfirmation];
                                                      
                                                      [self onActivityDetected: activity];
                                                  }
                                                  
                                                  
                                              });
                                          }];
    
}
    
    
    
- (void) enableMotionDetection {
    self.motionManager = [[CMMotionManager alloc] init];
    
    [self.motionManager setDeviceMotionUpdateInterval: self.settings.motionUpdateInterval];
    
    [self.motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue currentQueue]
                                            withHandler:^(CMDeviceMotion *deviceMotion, NSError *error){
                                                
                                                if (error) {
                                                    NSLog(@"motionManager error %@", error.localizedDescription);
                                                    return;
                                                }
                                                
                                                CMAcceleration userAcceleration = deviceMotion.userAcceleration;
                                                
                                                double totalAcceleration = sqrt(userAcceleration.x * userAcceleration.x +
                                                                                userAcceleration.y * userAcceleration.y +
                                                                                userAcceleration.z * userAcceleration.z);
                                                
                                                if (totalAcceleration < self.settings.accelerationThreshold) {
                                                    [self startStationaryConfirmation];
                                                } else {
                                                    [self cancelStationaryConfirmation];
                                                    [self onActivityDetected: nil];
                                                }
                                            }];
}
    

#pragma mark - Timer Handlers



- (void) onReportLocationTimerExpired:(NSTimer *)timer {
    NSLog(@"onReportLocationTimerExpired");
    
    if (!self.lastReportedLocation) {
        NSLog(@"No good location acquired yet.");
        return;
    }
    
    [self transmitLocation: self.lastReportedLocation ];
    self.lastReportedLocation = nil;
}





#pragma mark - GPS Management


- (void) startUpdatingLocation {
    
    if (self.locationEnabled) {
        return;
    }
    
    [self.locationManager startUpdatingLocation];
    self.locationEnabled = YES;
    NSLog(@"GPS Started");
}


- (void) stopUpdatingLocation {
    
    if (!self.locationEnabled) {
        return;
    }
    
    [self.locationManager stopUpdatingLocation];
    self.locationEnabled = NO;
    NSLog(@"GPS Stopped");
}


- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{

    if (newLocation.coordinate.latitude == 0 && newLocation.coordinate.longitude == 0) {
        NSLog(@"Invalid Lat/Lon");
        return;
    }
    
    if (self.settings.minHorizontalAccuracy > 0 && newLocation.horizontalAccuracy > self.settings.minHorizontalAccuracy) {
        NSLog(@"Low Accuracy %0.f", newLocation.horizontalAccuracy);
        return;
    }
    
    NSTimeInterval locationAge = [[NSDate date] timeIntervalSinceDate: newLocation.timestamp];
    if (self.settings.maxGeoAge > 0 && locationAge > self.settings.maxGeoAge) {
        NSLog(@"Too Old %.0f", locationAge);
        return;
    }

    NSLog(@"Location Acquired");

    switch (self.settings.mode) {

        case xAdPanelSdkModeConstTime:
            [self handleConstTime: newLocation];
            break;
        
        case xAdPanelSdkModeGpsOnlyOnStop:
            [self handleOnStopOnly: newLocation];
            break;

        case xAdPanelSdkModeConstDistance:
            [self handleConstDistance: newLocation];
            break;
        
        case xAdPanelSdkModeDisabled:
        default:
            NSLog(@"Disabling GPS");
            [self stopUpdatingLocation];
            break;
    }
    
}


- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if ([[error domain] isEqualToString: kCLErrorDomain] && [error code] == kCLErrorDenied) {
        
        NSLog(@"GPS ERROR");
        
        [self stopPanelServices];
    }
}


#pragma mark - Location Handlers Per Mode
    
    
- (void) handleConstTime:(CLLocation*)newLocation {
    self.lastReportedLocation = newLocation;

    // Waits for the timer to transmit
    // onReportLocationTimerExpired gets called
}

    
- (void) handleOnStopOnly:(CLLocation*)newLocation {

    [self transmitLocation: newLocation];
    [self stopUpdatingLocation];
}
    
    
- (void) handleConstDistance:(CLLocation*)newLocation {
    
    CLLocationDistance distance = -1.0; // Covers first time cases - transmit first good location
    
    if (self.lastReportedLocation) {
        distance = ([newLocation distanceFromLocation: self.lastReportedLocation]);
    }
    
    if (distance < self.distanceThreshold) {
        // Distance threshold not exceeded yet.
        NSLog(@"UT(%0.f): %.0f m", self.distanceThreshold, distance);
        return;
    }
    
    self.lastReportedLocation = newLocation;
    [self transmitLocation: newLocation];
}
    

 
    
 

 
#pragma mark - Data Transmit
 
- (void) transmitLocation: (CLLocation*) newLocation {

    if (![xAdPanelSdk userInPanel]) {
        // User does has not opted-in.
        NSLog(@"User is not in panel.");
        return;
    }
    
    if (self.settings.obeyTrackingFlag && ![[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled]) {
        // Although advertising tracking is not relavant, we can choose to obey it and by default we do.
        NSLog(@"TROFF");
        return;
    }

    NSTimeInterval locationAge = [[NSDate date] timeIntervalSinceDate: newLocation.timestamp];

    NSString *userDateOfBirth = [xAdPanelSdk stringFromTime: [[NSUserDefaults standardUserDefaults] objectForKey:@"xad_panel_dob"]];
    
    xAdPanelSdkGender genderValue = [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_gender"] intValue];
    NSString *userGender = (genderValue == GenderMale) ? @"m" : @"f";

    NSURL *resourceUrl = [xAdPanelSdk getWebServiceUrl];

    NSDictionary *params = @{
                             @"sdk_ver": PANEL_SDK_VERSION,
                             @"sdk_app": [xAdPanelSdk applicationName],
                             @"sdk_test": self.settings.name,
                             @"user_dob": userDateOfBirth,
                             @"user_gender": userGender,
                             @"geo_ha": [NSString stringWithFormat:@"%.0f", newLocation.horizontalAccuracy],
                             @"geo_va": [NSString stringWithFormat:@"%.0f", newLocation.verticalAccuracy],
                             @"geo_lat": [NSString stringWithFormat:@"%f", newLocation.coordinate.latitude],
                             @"geo_lon": [NSString stringWithFormat:@"%f", newLocation.coordinate.longitude],
                             @"geo_alt": [NSString stringWithFormat:@"%f", newLocation.altitude],
                             @"geo_age": [NSString stringWithFormat:@"%.0f", locationAge],
                             @"dev_ua": [xAdPanelSdk userAgent],
                             @"dev_lang": [xAdPanelSdk deviceLanguage],
                             @"dev_idfa": [xAdPanelSdk advertisingIdentifier],
                             @"dev_dnt": [xAdPanelSdk advertisingTrackingEnabled] /* for privacy watchdogs */
                             };
    
    NSURLRequest *httpRequest = [xAdPanelSdk createRequestWithUrl:resourceUrl andParameters:params];

    [NSURLConnection sendAsynchronousRequest:httpRequest
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *urlResponse, NSData *data, NSError *connectionError) {
                               
                               [[NSNotificationCenter defaultCenter] postNotificationName: @"XAD_DATA_TRANSMITTED" object: nil];
                               
                               return;
                           }];
    
}
    
    





#pragma mark - Utility Methods
    

+ (id) getWebServiceUrl {
   
#if TARGET_IPHONE_SIMULATOR
    return [NSURL URLWithString:@"http://ec2-54-243-190-3.compute-1.amazonaws.com/rest/panel"];
#else
#ifdef SUPPORT_SSL
    return [NSURL URLWithString:@"https://ap.xad.com/rest/panel"];
#else
    return [NSURL URLWithString:@"http://ap.xad.com/rest/panel"];
#endif
#endif
}



+ (NSString*) toUrlEncoded:(NSDictionary*)fields
{
    NSMutableArray *urlParams = [NSMutableArray array];
    
    NSArray *keys = [fields allKeys];
    for (id key in keys)
    {
        id value = [fields objectForKey:key];
        
        // Lets check if it is an array - used for listing ids.
        if ([value isKindOfClass:[NSArray class]]) {
            
            for (id singleValue in value) {
                // Same key, but with repeats
                id pair = [NSString stringWithFormat:@"%@=%@", key, singleValue];
                
                [urlParams addObject:pair];
            }
            
        } else {
            // Lets encode only string parameters
            if ([value isKindOfClass:[NSString class]]) {
                value = [value stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            } else if ([value isKindOfClass:[NSNumber class]]) {
                value = [value stringValue];
            }
            
            id pair = [NSString stringWithFormat:@"%@=%@", key, value];
            
            [urlParams addObject:pair];
        }
    }
    
    return [urlParams componentsJoinedByString:@"&"];
}


+ (NSURLRequest*) createRequestWithUrl:(NSURL *)resourceUrl andParameters:(NSDictionary *)params {
    
    id payload = [xAdPanelSdk toUrlEncoded:params];
    NSLog(@"%@", payload);
    
    NSMutableURLRequest *httpRequest = [[NSMutableURLRequest alloc] initWithURL:resourceUrl];
    [httpRequest setTimeoutInterval:9];
    
    [httpRequest setHTTPMethod:@"POST"];
    [httpRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    [httpRequest setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[payload length]] forHTTPHeaderField:@"Content-length"];
    [httpRequest setHTTPBody:[payload dataUsingEncoding:NSUTF8StringEncoding]];
    
    return httpRequest;
}


    
+ (NSString*) stringFromTime:(NSDate*)date
{
    NSLocale *curLocale = [NSLocale currentLocale];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        
    [dateFormatter setDateStyle:NSDateFormatterShortStyle];
    [dateFormatter setLocale:curLocale];
        
    return [dateFormatter stringFromDate:date];
}
    
    

#pragma mark - System information

+ (id) applicationName {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
}


+ (id) applicationVersion {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
}


+ (id) deviceLanguage {
    return [[NSLocale preferredLanguages] objectAtIndex:0];
}


+ (id) advertisingIdentifier {
    return [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
}


+ (id) advertisingTrackingEnabled {
    return [[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled] ? @"0" : @"1";
}


+ (id) userAgent {
    UIWebView* webView = [[UIWebView alloc] initWithFrame:CGRectZero];
    return [webView stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"];
}


    
#pragma mark - User Settings

+ (NSDate*) dateOfBirth {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"xad_panel_dob"];
}

+ (void) setDateOfBirth:(NSDate*)value {
    NSLog(@"setDateOfBirth %@", value);
    [[NSUserDefaults standardUserDefaults] setObject: value forKey:@"xad_panel_dob"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


+ (xAdPanelSdkGender) gender {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_gender"] intValue];
}

+ (void) setGender:(xAdPanelSdkGender)value {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:value] forKey:@"xad_panel_gender"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


+ (BOOL) userInPanel {
    NSLog(@"userInPanel");
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_opted_in"] boolValue];
}

+ (void) setUserInPanel:(BOOL)value {
    NSLog(@"setUserInPanel");
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:value] forKey:@"xad_panel_opted_in"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


@end
