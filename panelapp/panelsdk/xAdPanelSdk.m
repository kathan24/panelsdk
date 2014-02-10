//
//  xAdPanelSdk.m
//  xAd Panel SDK
//
//  Created by Stephen Anderson on 1/21/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "xAdPanelSdk.h"

#import <Social/Social.h>
#import <Accounts/Accounts.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <AdSupport/ASIdentifierManager.h>


NSString * const XAD_NOTIFICATION_DATA_TRANSMITTED = @"XAD_DATA_TRANSMITTED";
NSString * const XAD_NOTIFICATION_ACTIVITY_DETECTED = @"XAD_ACTIVITY_DETECTED";

static NSString * const NOTIFICATION_DISTANCE_THRESHOLD_PASSED = @"XAD_PANEL_NOTIF_01";
static NSString * const NOTIFICATION_NEW_LOCATION_DETECTED = @"XAD_PANEL_NOTIF_02";

static NSString * const FACEBOOK_APP_ID_XAD_PANEL = @"1418228921754388";

static NSTimeInterval STATIONARY_TIME_THRESHOLD = 10;//180; // 3 min
static CLLocationDistance THRESHOLD_AT_100KPH = 1000; // meters
static NSTimeInterval LOCATION_AGE_THRESHOLD = 60; // 1 min old

static CLLocationDistance CONSTANT_DISTANCE_THRESHOLD = 50; // meters


@interface NSURLRequest (Extension)
    + (BOOL)allowsAnyHTTPSCertificateForHost:(NSString*)host;
    + (void)setAllowsAnyHTTPSCertificate:(BOOL)allow forHost:(NSString*)host;
@end

@interface xAdPanelSdk ()
    @property (strong, nonatomic)  NSTimer *pulseTimer;
    @property (strong, nonatomic) CLLocation *cachedLocation;
    @property (strong, nonatomic) CLLocationManager *locationManager;
    @property (strong, nonatomic) CMMotionActivityManager *activityManager;
    @property (nonatomic, strong) ACAccount * facebookAccount;

    + (NSString*) facebookId;
    + (void) setFacebookId:(NSString *)value;

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
    
    
+ (void) initialize {
    xAdPanelSdk *obj = [xAdPanelSdk sharedInstance];
    
    if (obj) {
        NSDictionary *defaults = @{
                                   @"xad_panel_dob": [NSDate date],
                                   @"xad_panel_sharefb":@NO,
                                   @"xad_panel_shareloc":@NO,
                                   @"xad_panel_gender":@"m",
                                   @"xad_panel_fbid":@""
                                   };
        
        [[NSUserDefaults standardUserDefaults] registerDefaults: defaults];
    }
}
    

- (id) init {
    
    self = [super init];
    
    if (self) {
        
        UIApplication *app = [UIApplication sharedApplication];
        UIBackgroundTaskIdentifier bgTask = 0;
        bgTask = [app beginBackgroundTaskWithExpirationHandler:^{ [app endBackgroundTask: bgTask]; }];
        
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        
        [nc addObserver:self
               selector: @selector(onDistanceThresholdPassed:)
                   name: NOTIFICATION_DISTANCE_THRESHOLD_PASSED
                 object: nil];
        
        self.cachedLocation = nil;
        
        // TODO: Detect if the user did not enable location.
        
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
        [self.locationManager startMonitoringSignificantLocationChanges];
        
        if ([CMMotionActivityManager isActivityAvailable]) {
            
            self.activityManager = [[CMMotionActivityManager alloc] init];
            
            [self.activityManager startActivityUpdatesToQueue:[[NSOperationQueue alloc] init]
                                                    withHandler: ^(CMMotionActivity *activity) {
                 
                 dispatch_async(dispatch_get_main_queue(), ^{

                     if ([activity stationary]) {
                         [[NSNotificationCenter defaultCenter] postNotificationName: XAD_NOTIFICATION_ACTIVITY_DETECTED object: @"Stationary"];

                         // Stopped moving, but give a 3 min in case of red lights, etc
                     
                         if (!self.pulseTimer) {
                             NSLog(@"Stationary: starting timer.");
                             self.pulseTimer = [NSTimer scheduledTimerWithTimeInterval: STATIONARY_TIME_THRESHOLD target:self selector:@selector(onUserIsStationary:) userInfo:nil repeats:NO];
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

        [self facebookLogin];
    }
    
    return self;
}


- (void) onActivityDetected:(id)activity {
    
    NSLog(@"onActivityDetected");

    // Re-activate the GPS,

    CLLocationAccuracy newAccuracy = kCLLocationAccuracyBest;

    id activityName = nil;
    
    if ([activity walking]) {
        activityName = @"Walking";
    } else if ([activity running]) {
        activityName = @"Running";
    } else if ([activity automotive]) {
        activityName = @"Automotive";
        newAccuracy = kCLLocationAccuracyBestForNavigation;
    }
    
    if (self.locationManager.desiredAccuracy != newAccuracy) {
        NSLog(@"Updating location accuracy to %f", newAccuracy);
        self.locationManager.desiredAccuracy = newAccuracy;
    }
    
    [self.locationManager startMonitoringSignificantLocationChanges];
    
    [[NSNotificationCenter defaultCenter] postNotificationName: XAD_NOTIFICATION_ACTIVITY_DETECTED object: activityName];
        
    NSArray* conf = @[@"Low Confidence", @"Medium Confidence", @"High Confidence"];
    [[NSNotificationCenter defaultCenter] postNotificationName: @"SIGNAL_B" object: [conf objectAtIndex:[activity confidence]]];
    [[NSNotificationCenter defaultCenter] postNotificationName: @"SIGNAL_C" object: [NSString stringWithFormat:@"%.1f", CONSTANT_DISTANCE_THRESHOLD]];
}


-(void) onUserIsStationary:(NSTimer *)timer {
    
    NSLog(@"onUserIsStationary");

    self.cachedLocation = self.locationManager.location;
    [self processLocation: self.locationManager.location];
    
    // User has been stationary for 3 min
    [self transmitData];
    
    // Now we can stop the GPS
    // self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
    [self.locationManager stopMonitoringSignificantLocationChanges];
}


-(void)onDistanceThresholdPassed:(NSNotification*)notification {
    NSLog(@"onDistanceThresholdPassed");
    // User's activity resulted in a new location beyond the activity based threshold.
    [self transmitData];
}


- (void) processLocation: (CLLocation*) newLocation {
    NSTimeInterval locationAge = [[NSDate date] timeIntervalSinceDate: newLocation.timestamp];
    
    if (locationAge > LOCATION_AGE_THRESHOLD) {
        NSLog(@"Location is old.");
        [[NSNotificationCenter defaultCenter] postNotificationName: @"SIGNAL_D" object: @"Old"];
        return;
    }
    
    if (newLocation.horizontalAccuracy > CONSTANT_DISTANCE_THRESHOLD || newLocation.verticalAccuracy > CONSTANT_DISTANCE_THRESHOLD) {
        NSLog(@"Location is inaccurate");
        [[NSNotificationCenter defaultCenter] postNotificationName: @"SIGNAL_D" object: @"Inaccurate"];
        return;
    }
    
    
    CLLocationDistance distance = ([newLocation distanceFromLocation: self.cachedLocation]);
    
    NSLog(@"New location: %@", newLocation);
    NSLog(@"    [+] Speed:%f  Altitude:%f  Distance:%f  Threshold:%f", newLocation.speed, newLocation.altitude, distance, CONSTANT_DISTANCE_THRESHOLD);
    NSLog(@"    [+] HA:%f  VA:%f  ", newLocation.horizontalAccuracy, newLocation.verticalAccuracy);
    
    if (distance >= CONSTANT_DISTANCE_THRESHOLD)  {
        NSLog(@"    [+] New point recorded");
        self.cachedLocation = newLocation;
        [[NSNotificationCenter defaultCenter] postNotificationName: NOTIFICATION_DISTANCE_THRESHOLD_PASSED object: [NSNumber numberWithInt:distance]];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName: @"SIGNAL_GEO" object: newLocation];
    [[NSNotificationCenter defaultCenter] postNotificationName: @"SIGNAL_A" object: [NSString stringWithFormat:@"%.1f", newLocation.speed]];
    [[NSNotificationCenter defaultCenter] postNotificationName: @"SIGNAL_D" object: [NSString stringWithFormat:@"%.1f m", distance]];

}


- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    if (!self.cachedLocation) {
        self.cachedLocation = newLocation;
        // Treat as if old location. Distance will be 0 thus no problem.
    }
    
    [self processLocation: newLocation];
}


- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if ([[error domain] isEqualToString: kCLErrorDomain] && [error code] == kCLErrorDenied) {
        
        [[NSNotificationCenter defaultCenter] postNotificationName: @"SIGNAL_GEO_OFF" object: nil];
        
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


- (void) transmitData {
    
    NSLog(@"transmitData");
    
    if (![[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled]) {
        NSLog(@"DO NOT TRACK IS ON");
        // User blocks use of IDFA - respect the users wish to deny any tracking.
        [[NSNotificationCenter defaultCenter] postNotificationName: @"DNT" object: nil];
        return;
    }
    
    if (self.cachedLocation.coordinate.latitude == 0 && self.cachedLocation.coordinate.longitude == 0) {
        // Nothing to transmit
        return;
    }
    
    NSURL *resourceUrl = [xAdPanelSdk getWebServiceUrl];

    NSDictionary *params = @{
                             @"app": [xAdPanelSdk applicationName],
                             @"idfa": [xAdPanelSdk advertisingIdentifier],
                             @"dnt": [xAdPanelSdk advertisingTrackingEnabled],
                             @"fbid": [xAdPanelSdk facebookId],
                             @"dob": [xAdPanelSdk stringFromTime: [xAdPanelSdk dateOfBirth]],
                             @"lat": [NSString stringWithFormat:@"%f", self.cachedLocation.coordinate.latitude],
                             @"lon": [NSString stringWithFormat:@"%f", self.cachedLocation.coordinate.longitude],
                             @"gender": [xAdPanelSdk gender]
                             };
    
    
    id httpRequest = [xAdPanelSdk createRequestWithUrl:resourceUrl andParameters:params];
    
    [NSURLRequest setAllowsAnyHTTPSCertificate:YES forHost:[resourceUrl host]];
    
    [NSURLConnection sendAsynchronousRequest:httpRequest
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *urlResponse, NSData *data, NSError *connectionError) {
                               
                               if (connectionError) {
                                   NSLog(@"connectionError: %@", connectionError);
                                   NSString * message = @"Network error";
                                   
                                   if (connectionError.code == -9) {
                                       message = @"Please check your connection.";
                                   }
                                   
                                   if (connectionError.code == -1202) {
                                       message = [connectionError localizedDescription];
                                   }
                                   
                                   NSLog(@"%@", message);
                                   
                                   return;
                               }
                               
                               if (data.length == 0) {
                                   NSLog(@"No data returned.");
                                   return;
                               }
                               
                               NSString* txtResponse = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                               
                               NSLog(@"REST Response: %@", txtResponse);
                               
                               [[NSNotificationCenter defaultCenter] postNotificationName: XAD_NOTIFICATION_DATA_TRANSMITTED object: nil];
                           }];

    
}
    
    
#pragma mark - Facebook
    
- (void) facebookLogin {
    
    NSLog(@"facebookLogin");
    [xAdPanelSdk setFacebookId: @"" ];
    
    ACAccountStore *accountStore = [[ACAccountStore alloc] init] ;
    ACAccountType *facebookAccountType = [accountStore accountTypeWithAccountTypeIdentifier: ACAccountTypeIdentifierFacebook];
    
    NSArray * permissions = @[@"email"];
    
    NSDictionary *options = @{   ACFacebookAppIdKey : FACEBOOK_APP_ID_XAD_PANEL,
                                 ACFacebookAudienceKey : ACFacebookAudienceFriends,
                                 ACFacebookPermissionsKey : permissions};
    
    [accountStore requestAccessToAccountsWithType: facebookAccountType options: options completion:^(BOOL granted, NSError *error) {
        
        NSLog(@"facebookLogin - callback");
        
        if (!granted) {
            NSLog(@"Error code: %ld - %@", (long)error.code, error.localizedDescription);
            
            switch (error.code) {
                case ACErrorAccountNotFound:
                    NSLog(@"%@", @"Account not found. Please setup your account in settings app.");
                    break;
                
                case ACErrorPermissionDenied:
                    NSLog(@"%@", @"You must grant access for all social features");
                    break;
                
                default:
                    NSLog(@"%@", error.localizedDescription);
                    break;
            }
            
            return;
        }
        
        NSArray *accounts = [accountStore accountsWithAccountType: facebookAccountType];
        
        if([accounts count] == 0) {
            NSLog(@"%@", @"Unable to find any facebook accounts.");
            return;
        }
        
        self.facebookAccount = [accounts lastObject];
        [xAdPanelSdk setFacebookId: self.facebookAccount.identifier ];
        
        NSLog(@"facebookLogin: %@", self.facebookAccount.identifier);
    }];
    
}
    
    
#pragma mark - Application Settings
    
+ (NSDate*) dateOfBirth {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"xad_panel_dob"];
}
    
    
+ (void) setDateOfBirth:(NSDate*)value {
    [[NSUserDefaults standardUserDefaults] setObject: value forKey:@"xad_panel_dob"];
}
    
    
+ (BOOL) sharefb {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_sharefb"] boolValue];
}
    
+ (void) setSharefb:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool: value] forKey:@"xad_panel_sharefb"];
}
    
    
+ (BOOL) shareloc {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_shareloc"] boolValue];
}
    
+ (void) setShareloc:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool: value] forKey:@"xad_panel_shareloc"];
}
    
+ (NSString*) gender {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_gender"];
}
    
+ (void) setGender:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:@"xad_panel_gender"];
}
    
    
+ (NSString*) facebookId {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_fbid"];
}
    
+ (void) setFacebookId:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:@"xad_panel_fbid"];
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


+ (NSMutableURLRequest*) createRequestWithUrl:(NSURL *)resourceUrl andParameters:(NSDictionary *)params {
    
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



+ (NSString*) stringFromTime:(NSDate*)date
{
    NSLocale *curLocale = [NSLocale currentLocale];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    
    [dateFormatter setDateStyle:NSDateFormatterShortStyle];
    [dateFormatter setLocale:curLocale];
    
    return [dateFormatter stringFromDate:date];
}


@end
