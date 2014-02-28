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


static NSString * const PANEL_SDK_VERSION = @"1.0";


// Required to allow HTTPS connections to xAd's Servers
@interface NSURLRequest (Extension)
    + (BOOL)allowsAnyHTTPSCertificateForHost:(NSString*)host;
    + (void)setAllowsAnyHTTPSCertificate:(BOOL)allow forHost:(NSString*)host;
@end


@interface xAdPanelSdk ()
@property (strong, nonatomic) NSTimer *stationaryConfirmTimer;
@property (strong, nonatomic) NSTimer *reportLocationTimer;

@property (strong, nonatomic) CLLocation *lastReportedLocation;
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) CMMotionActivityManager *activityManager;
@property (strong, nonatomic) CMMotionManager *motionManager; // fallback

@property (nonatomic, strong) xAdPanelSettings *settings;
@property (nonatomic, assign) CLLocationDistance distanceThreshold;

@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;

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


+ (void) startPanelSdkWithAppKey:(id)appKey {
    
    xAdPanelSdk *obj = [xAdPanelSdk sharedInstance];
    
    if (obj) {
        NSDictionary *defaults = @{
                                   @"xad_panel_dob": [NSDate date],
                                   @"xad_panel_shareloc":@NO,
                                   @"xad_panel_gender":@"m"
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
    [self disableLocation];
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
    
    if (!self.settings.userInPanel) {
        NSLog(@"User is not in panel.");
        return NO;
    }
    
    
    if (self.settings.obeyTrFlag && ![[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled]) {
        NSLog(@"Tracking is prohibited");
        return NO;
    }

    if (!self.settings.enabled) {
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



- (void) enableEventsWhenPhoneLocked {

    // Needed to keep location events while phone is locked.

    UIApplication *app = [UIApplication sharedApplication];
    self.backgroundTask = 0;
    self.backgroundTask = [app beginBackgroundTaskWithExpirationHandler:^{ [app endBackgroundTask: self.backgroundTask]; }];

}

- (void) startStationaryConfirmation {
    // Prevent instantanious status change to stationary for cases like traffic lights.
    if (!self.stationaryConfirmTimer) {
        self.stationaryConfirmTimer = [NSTimer scheduledTimerWithTimeInterval: self.settings.timeBeforeStationary
                                                                       target: self
                                                                     selector: @selector(onStationaryConfirmed:)
                                                                     userInfo: nil
                                                                      repeats: NO];
    }
}

- (void) cancelStationaryConfirmation {
    if (self.stationaryConfirmTimer) {
        // Activity detected. Cancel timer and adjust based on activity type.
        [self.stationaryConfirmTimer invalidate];
        self.stationaryConfirmTimer = nil;
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
    
    [self.motionManager setDeviceMotionUpdateInterval: self.settings.motionUpdateInterval];
    
    [self.motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue currentQueue]
                                            withHandler:^(CMDeviceMotion *deviceMotion, NSError *error){
                                                
                                                if (error) {
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


- (void) startPanelServices {
    NSLog(@"startPanelServices");
    
    if (![self canStartServices]) {
        NSLog(@"Panel SDK is DISABLED");
        return;
    }
    
    if (self.settings.eventsWhilePhoneIsLocked) {
        [self enableEventsWhenPhoneLocked];
    }
    
    self.distanceThreshold = self.settings.distanceWhileDriving;
    
    // Initialize Location Services
    
    if (!self.locationManager) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
    }
    
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.lastReportedLocation = nil;
    [self.locationManager startUpdatingLocation];
    

    // Initialize Motion Detection
    if ([CMMotionActivityManager isActivityAvailable]) {
        
        [self enableActivityDetection];
        
    } else {
        // Motion detection does not compare to what the M7 activity monitor does.
        // We will use the const time based reporting for older devices.

        self.settings.useConstTime = YES;
        
        if (!self.motionManager) {
            self.motionManager = [[CMMotionManager alloc] init];
        }
        
        [self enableMotionDetection];
    }
    
    
    // Use const time IF provisioned OR it is a older device
    if (self.settings.useConstTime) {
        NSLog(@"Starting reportLocationTimer %.0f",  self.settings.secondsBetweenSignaling);
        self.reportLocationTimer =[NSTimer scheduledTimerWithTimeInterval: self.settings.secondsBetweenSignaling target:self selector:@selector(onReportLocationTimerExpired:) userInfo:nil repeats:YES];
    }
}


- (void) onActivityDetected:(id)activity {

    CLLocationAccuracy newAccuracy = kCLLocationAccuracyBest;

    if ([activity walking]) {
        NSLog(@"    [+] walking");
        self.distanceThreshold = self.settings.distanceWhileWalking;
    } else if ([activity running]) {
        NSLog(@"    [+] running");
        self.distanceThreshold = self.settings.distanceWhileRunning;
    } else if ([activity automotive]) {
        NSLog(@"    [+] automotive");
        self.distanceThreshold = self.settings.distanceWhileDriving;
        newAccuracy = kCLLocationAccuracyBestForNavigation;
    } else if (activity == nil) {
        self.distanceThreshold = self.settings.distanceWhileWalking;
        // User activity from non-M7 device
        NSLog(@"    [+] activity");
    }
    
    self.locationManager.desiredAccuracy = newAccuracy;

    [self enableLocation];
}


- (void) enableLocation {
    
    if (self.locationEnabled) {
        return;
    }
    
    [self.locationManager startUpdatingLocation];
    self.locationEnabled = YES;
    NSLog(@"GPS Started");
}


- (void) disableLocation {
    
    if (!self.locationEnabled) {
        return;
    }
    
    [self.locationManager stopUpdatingLocation];
    self.locationEnabled = NO;
    NSLog(@"GPS Stopped");
}


-(void) onStationaryConfirmed:(NSTimer *)timer {

    NSLog(@"    [+] stationary.");
    
    [self transmitLocation: self.locationManager.location force: YES];

    // Now we can stop the GPS
    [self disableLocation];
}


- (void) transmitLocation: (CLLocation*) newLocation force:(BOOL)force{

    NSTimeInterval locationAge = [[NSDate date] timeIntervalSinceDate: newLocation.timestamp];

    if (newLocation.coordinate.latitude == 0 && newLocation.coordinate.longitude == 0) {
        NSLog(@"Invalid Lat/Lon");
        return;
    }
    
    if (!force) {
        if (self.settings.maxGeoAge > 0 && locationAge > self.settings.maxGeoAge) {
            NSLog(@"Too Old %.0f", locationAge);
            return;
        }
        
        if (self.settings.minGeoAccuracy > 0 && newLocation.horizontalAccuracy > self.settings.minGeoAccuracy) {
            NSLog(@"Low Accuracy %0.f", newLocation.horizontalAccuracy);
            return;
        }
        
        CLLocationDistance distance = ([newLocation distanceFromLocation: self.lastReportedLocation]);
        
        if (!self.settings.useConstTime && distance < self.distanceThreshold) {
            // Distance threshold not exceeded yet.
            NSLog(@"UT(%0.f): %.0f m", self.distanceThreshold, distance);
            return;
        }
    }
    
    
    self.lastReportedLocation = newLocation;
    
    // Missing case: If const time, then only the timer can send

    if (!self.settings.userInPanel) {
        // User does has not opted-in.
        NSLog(@"User is not in panel.");
        return;
    }
    
    if (self.settings.obeyTrFlag && ![[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled]) {
        // Although advertising tracking is not relavant, we can choose to obey it and by default we do.
        NSLog(@"TR");
        return;
    }
    
    NSURL *resourceUrl = [xAdPanelSdk getWebServiceUrl];
    
    NSDictionary *params = @{
                             @"sdk_ver": PANEL_SDK_VERSION,
                             @"app": [xAdPanelSdk applicationName],
                             @"idfa": [xAdPanelSdk advertisingIdentifier],
                             @"dnt": [xAdPanelSdk advertisingTrackingEnabled],
                             @"pro": self.settings.name,
                             @"dob": self.settings.userDateOfBirth,
                             @"gender": self.settings.userGender,
                             @"lang": [xAdPanelSdk deviceLanguage],
                             @"lat": [NSString stringWithFormat:@"%f", newLocation.coordinate.latitude],
                             @"lon": [NSString stringWithFormat:@"%f", newLocation.coordinate.longitude],
                             @"geo_ha": [NSString stringWithFormat:@"%.0f", newLocation.horizontalAccuracy],
                             @"geo_age": [NSString stringWithFormat:@"%.0f", locationAge]
                             };
    
    NSURLRequest *httpRequest = [xAdPanelSdk createRequestWithUrl:resourceUrl andParameters:params];
    
    [NSURLRequest setAllowsAnyHTTPSCertificate:YES forHost:[resourceUrl host]];
    
    [NSURLConnection sendAsynchronousRequest:httpRequest
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *urlResponse, NSData *data, NSError *connectionError) {
                               
                               [[NSNotificationCenter defaultCenter] postNotificationName: @"XAD_DATA_TRANSMITTED" object: nil];
                               
                               return;
                           }];

}


- (void) onReportLocationTimerExpired:(NSTimer *)timer {
    NSLog(@"onReportLocationTimerExpired");
    
    [self transmitLocation: self.locationManager.location force: NO];
}




- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    if (!self.lastReportedLocation) {
        self.lastReportedLocation = newLocation;
        return;
    }
    
    CLLocationDistance distance = ([newLocation distanceFromLocation: oldLocation]);
    
    if (distance < 1 && newLocation.horizontalAccuracy <= oldLocation.horizontalAccuracy) {
        // Nothing of value - same location and of equal or lesser accuracy
        return;
    }

    if (!self.settings.useConstTime) {
        
        // In CONST TIME mode location is aquired from the location manager.
        // Does not rely on the events directly.
        
        [self transmitLocation: newLocation force: NO];
    }
}


- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if ([[error domain] isEqualToString: kCLErrorDomain] && [error code] == kCLErrorDenied) {
        
        NSLog(@"GPS ERROR");
        
        [self stopPanelServices];
    }
}


    
#pragma mark - Data Transmit

/*
 
 Options
 
 a) Constant time: Everytime an X amount of time elapses, we signal the server.
 
 b) Constant distance: Everytime an X amount of distance is detected, we signal the server.
 
 c) Density signaling: Signaling frequency changes based on store density where the user is located.
    REST could return the 'local' distance threshold.
 
    e.g. While in the city, distance threshold can be say 50meters, but in the desert it can be 20miles or 1hour which ever comes first.
 
 */

#define SUPPORT_SSL
    
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








#pragma mark - Private utility methods

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








#pragma mark - User Settings

+ (NSDate*) dateOfBirth {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"xad_panel_dob"];
}

+ (void) setDateOfBirth:(NSDate*)value {
    [[NSUserDefaults standardUserDefaults] setObject: value forKey:@"xad_panel_dob"];
}


+ (xAdPanelSdkGender) gender {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_gender"] intValue];
}

+ (void) setGender:(xAdPanelSdkGender)value {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:value] forKey:@"xad_panel_gender"];
}


+ (BOOL) userInPanel {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_user_in_panel"] boolValue];
}

+ (void) setUserInPanel:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:value] forKey:@"xad_user_in_panel"];
}

















@end
