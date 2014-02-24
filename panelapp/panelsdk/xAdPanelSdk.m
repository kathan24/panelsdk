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


@interface NSURLRequest (Extension)
    + (BOOL)allowsAnyHTTPSCertificateForHost:(NSString*)host;
    + (void)setAllowsAnyHTTPSCertificate:(BOOL)allow forHost:(NSString*)host;
@end

static double SECONDS_IN_DAY = 86400;

@interface xAdPanelSdk ()
@property (strong, nonatomic) NSTimer *pulseTimer;
@property (strong, nonatomic) NSTimer *constTimer;
@property (strong, nonatomic) NSTimer *settingsTimer;

@property (strong, nonatomic) CLLocation *cachedLocation;
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) CMMotionActivityManager *activityManager;

@property (nonatomic, strong) xAdPanelSettings *settings;
@property (nonatomic, assign) CLLocationDistance distanceThreshold;

@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;
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
        obj.settings = [[xAdPanelSettings alloc] initWithAppKey:appKey];
        obj.settingsTimer = [NSTimer scheduledTimerWithTimeInterval: SECONDS_IN_DAY target: obj selector:@selector(onRefreshSettingsTimerExpired:) userInfo:nil repeats:YES];
    }
}



- (BOOL) canStartServices {
    
    // Any of these cases is reason enough not to start the SDK.
    
    return (
            !self.settings.userSharesLocation ||
            !self.settings.enabled ||
            (self.settings.requiresM7 && ![CMMotionActivityManager isActivityAvailable]) ||
            (self.settings.obeyTrFlag && ![[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled])
            );
    
    
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


- (void) enableActivityDetection {
    self.activityManager = [[CMMotionActivityManager alloc] init];
    
    [self.activityManager startActivityUpdatesToQueue:[[NSOperationQueue alloc] init]
                                          withHandler: ^(CMMotionActivity *activity) {
                                              
                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                  
                                                  if ([activity stationary]) {
                                                      
                                                      // Prevent instantanious status change to stationary for cases like traffic lights.
                                                      if (!self.pulseTimer) {
                                                          NSLog(@"Stationary: starting timer.");
                                                          self.pulseTimer = [NSTimer scheduledTimerWithTimeInterval: self.settings.timeBeforeStationary target:self selector:@selector(onUserIsStationary:) userInfo:nil repeats:NO];
                                                      }
                                                      
                                                  } else if ([activity walking] || [activity running] || [activity automotive]) {
                                                      
                                                      if (self.pulseTimer) {
                                                          NSLog(@"Activity: cancelling timer.");
                                                          // Activity detected. Cancel timer and adjust based on activity type.
                                                          [self.pulseTimer invalidate];
                                                          self.pulseTimer = nil;
                                                      }
                                                      
                                                      [self onActivityDetected: activity];
                                                  }
                                                  
                                                  
                                              });
                                          }];
    
}


- (void) startPanelServices {
    
    if (![self canStartServices]) {
        NSLog(@"Panel SDK is DISABLED");
        return;
    }
    
    
    if (self.settings.useConstTime) {
        
        self.constTimer =[NSTimer scheduledTimerWithTimeInterval: self.settings.secondsBetweenSignaling target:self selector:@selector(onConstTimerExpired:) userInfo:nil repeats:YES];
        
    }

    
    if (self.settings.eventsWhilePhoneIsLocked) {
        [self enableEventsWhenPhoneLocked];
    }
    
    // Initialize Location Services
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.cachedLocation = nil;
    [self.locationManager startUpdatingLocation];
    

    // Initialize Motion Detection
    if ([CMMotionActivityManager isActivityAvailable]) {
        
        [self enableActivityDetection];
        
    } else {
        
        // TODO: How to handle older devices?
        
    }

    
}






- (void) onActivityDetected:(id)activity {

    CLLocationAccuracy newAccuracy = kCLLocationAccuracyBest;

    if ([activity walking]) {
        self.distanceThreshold = self.settings.distanceWhileWalking;
    } else if ([activity running]) {
        self.distanceThreshold = self.settings.distanceWhileRunning;
    } else if ([activity automotive]) {
        self.distanceThreshold = self.settings.distanceWhileDriving;
        newAccuracy = kCLLocationAccuracyBestForNavigation;
    }
    
    self.locationManager.desiredAccuracy = newAccuracy;
    [self.locationManager startUpdatingLocation];
}


-(void) onUserIsStationary:(NSTimer *)timer {

    [self transmitLocation: self.locationManager.location force:YES];

    // Now we can stop the GPS
    [self.locationManager stopUpdatingLocation];
}





- (void) transmitLocation: (CLLocation*) newLocation force:(BOOL)force{

    NSTimeInterval locationAge = [[NSDate date] timeIntervalSinceDate: newLocation.timestamp];

    if (newLocation.coordinate.latitude == 0 && newLocation.coordinate.longitude == 0) {
        // Invalid lat/long. Ignore.
        return;
    }
    
    if (!force) {
        if (self.settings.maxGeoAge > 0 && locationAge > self.settings.maxGeoAge) {
            return;
        }
        
        if (self.settings.minGeoAccuracy > 0 && newLocation.horizontalAccuracy > self.settings.minGeoAccuracy) {
            return;
        }
    }
    
    CLLocationDistance distance = ([newLocation distanceFromLocation: self.cachedLocation]);
    self.cachedLocation = newLocation;
    
    if (!self.settings.useConstTime && self.distanceThreshold > distance) {
        // Distance threshold not exceeded yet.
        return;
    }

    if (!self.settings.userSharesLocation) {
        // User does has not opted-in.
        return;
    }
    
    if (self.settings.obeyTrFlag && ![[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled]) {
        // Although advertising tracking is not relavant, we can choose to obey it and by default we do.
        return;
    }
    
    NSURL *resourceUrl = [xAdPanelSdk getWebServiceUrl];
    
    NSDictionary *params = @{
                             @"app": [xAdPanelSdk applicationName],
                             @"idfa": [xAdPanelSdk advertisingIdentifier],
                             @"dnt": [xAdPanelSdk advertisingTrackingEnabled],
                             @"pro": self.settings.name,
                             @"dob": self.settings.userDateOfBirth,
                             @"gender": self.settings.userGender,
                             @"lang": [xAdPanelSdk deviceLanguage],
                             @"lat": [NSString stringWithFormat:@"%f", newLocation.coordinate.latitude],
                             @"lon": [NSString stringWithFormat:@"%f", newLocation.coordinate.longitude],
                             @"geo_ha": [NSString stringWithFormat:@"%f", newLocation.horizontalAccuracy],
                             @"geo_age": [NSString stringWithFormat:@"%f", locationAge]
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


- (void) onRefreshSettingsTimerExpired:(NSTimer *)timer {
    NSLog(@"onRefreshSettingsTimerExpired");
    
    [self.locationManager stopUpdatingLocation];
    [self.activityManager stopActivityUpdates];
    [self.constTimer invalidate];
    [self.pulseTimer invalidate];
    
    // Perhaps not needed?!
    [[UIApplication sharedApplication] endBackgroundTask: self.backgroundTask];
    
    [self.settings retrieveSettings];

    [self startPanelServices];
    
}


- (void) onConstTimerExpired:(NSTimer *)timer {
    NSLog(@"onConstTimerExpired");
    
    [self transmitLocation: self.locationManager.location force: NO];
}




- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    if (!self.cachedLocation) {
        self.cachedLocation = newLocation;
        
        return;
    }
    
    [self transmitLocation: newLocation force:NO];
}


- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if ([[error domain] isEqualToString: kCLErrorDomain] && [error code] == kCLErrorDenied) {
        
        NSLog(@"GPS ERROR");
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


+ (BOOL) shareLocation {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_shareloc"] boolValue];
}

+ (void) setShareLocation:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:value] forKey:@"xad_panel_shareloc"];
}

















@end
