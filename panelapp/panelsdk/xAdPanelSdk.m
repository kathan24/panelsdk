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

typedef void(^ActivityUpdateBlock)(CMMotionActivity *activity);

NSString * const XAD_NOTIFICATION_DATA_TRANSMITTED = @"XAD_DATA_TRANSMITTED";
NSString * const XAD_NOTIFICATION_ACTIVITY_DETECTED = @"XAD_ACTIVITY_DETECTED";

static NSString * const NOTIFICATION_DISTANCE_THRESHOLD_PASSED = @"XAD_PANEL_NOTIF_01";
static NSString * const NOTIFICATION_NEW_LOCATION_DETECTED = @"XAD_PANEL_NOTIF_02";

static NSString * const FACEBOOK_APP_ID_XAD_PANEL = @"1418228921754388";

static NSTimeInterval TIME_THRESHOLD = 60;



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

    @property (nonatomic, assign) CLLocationDistance variableDistanceThreshold;
    @property (nonatomic, assign) BOOL firstEmissionCompleted;

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
                                   @"dob": [NSDate date],
                                   @"sharefb":@NO,
                                   @"shareloc":@NO,
                                   @"gender":@"m",
                                   @"fbid":@""
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
        
        self.pulseTimer = [NSTimer scheduledTimerWithTimeInterval: TIME_THRESHOLD target:self selector:@selector(onTimerExpired:) userInfo:nil repeats:YES];
        
        self.cachedLocation = [[CLLocation alloc] initWithLatitude:40.780184 longitude:-73.966827];
        
        // TODO: Detect if the user did not enable location.
        
        self.variableDistanceThreshold = 100; // meters
        self.firstEmissionCompleted = NO;
        
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
        [self.locationManager startMonitoringSignificantLocationChanges];
        
        if ([CMMotionActivityManager isActivityAvailable]) {
            
            self.activityManager = [[CMMotionActivityManager alloc] init];
            
            [self.activityManager startActivityUpdatesToQueue:[[NSOperationQueue alloc] init]
                                                    withHandler: ^(CMMotionActivity *activity) {
                 
                 dispatch_async(dispatch_get_main_queue(), ^{
                     
                     
                     
                     if ([activity walking]) {
                         self.variableDistanceThreshold = 10;
                         self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
                         [[NSNotificationCenter defaultCenter] postNotificationName: XAD_NOTIFICATION_ACTIVITY_DETECTED object: @"walking"];
                     }
                     
                     else if ([activity running]) {
                         self.variableDistanceThreshold = 10;
                         self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
                         [[NSNotificationCenter defaultCenter] postNotificationName: XAD_NOTIFICATION_ACTIVITY_DETECTED object: @"running"];
                     }
                     
                     else if ([activity automotive]) {
                         self.variableDistanceThreshold = 100;
                         self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
                         [[NSNotificationCenter defaultCenter] postNotificationName: XAD_NOTIFICATION_ACTIVITY_DETECTED object: @"automotive"];
                     }

                     else if ([activity stationary]) {
                         // indirect GPS stopping
                         self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
                         [[NSNotificationCenter defaultCenter] postNotificationName: XAD_NOTIFICATION_ACTIVITY_DETECTED object: @"stationary"];
                     }
                     
                     else {
                         [[NSNotificationCenter defaultCenter] postNotificationName: XAD_NOTIFICATION_ACTIVITY_DETECTED object: @"stationary"];
                     }
                     
                 });
             }];
        
        }

        [self facebookLogin];
    }
    
    return self;
}




    
-(void) onTimerExpired:(NSTimer *)timer {
    
    // Constant time
    
    //[self transmitData];
}


-(void)onDistanceThresholdPassed:(NSNotification*)notification {
    
    // Constant distance
    
    [self transmitData];
}


    
- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
    {
        
        if (newLocation.coordinate.longitude == oldLocation.coordinate.longitude &&
            newLocation.coordinate.latitude == oldLocation.coordinate.latitude &&
            newLocation.horizontalAccuracy == oldLocation.horizontalAccuracy)
        {
            return;
        }
        
        // Check accuracy
        
        CLLocationDistance distance = ([newLocation distanceFromLocation:oldLocation]) * 0.000621371192;
        
        // Added due to minor fluctuations of the location perhaps due to hand movements.
        if (!self.firstEmissionCompleted && oldLocation && distance < .001) {
            return;
        }
        
        if (!self.firstEmissionCompleted || distance >= self.variableDistanceThreshold) {
            [[NSNotificationCenter defaultCenter] postNotificationName: NOTIFICATION_DISTANCE_THRESHOLD_PASSED object: [NSNumber numberWithInt:distance]];
        }

        self.cachedLocation = newLocation;
        
        [[NSNotificationCenter defaultCenter] postNotificationName: NOTIFICATION_NEW_LOCATION_DETECTED object:newLocation];
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


- (void) transmitData {
    
    NSLog(@"transmitData");
    
    NSURL *resourceUrl = nil;

    //resourceUrl = [NSURL URLWithString:@"https://ap.xad.com/rest/panel"];
    resourceUrl = [NSURL URLWithString:@"https://ec2-54-243-190-4.compute-1.amazonaws.com/rest/panel"];
    
    
    NSDictionary *params = @{
                             @"app": [xAdPanelSdk applicationName],
                             @"idfa": [xAdPanelSdk advertisingIdentifier],
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
                               
                               self.firstEmissionCompleted = YES;
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
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"dob"];
}
    
    
+ (void) setDateOfBirth:(NSDate*)value {
    [[NSUserDefaults standardUserDefaults] setObject: value forKey:@"dob"];
}
    
    
+ (BOOL) sharefb {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"sharefb"] boolValue];
}
    
+ (void) setSharefb:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool: value] forKey:@"sharefb"];
}
    
    
+ (BOOL) shareloc {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"shareloc"] boolValue];
}
    
+ (void) setShareloc:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool: value] forKey:@"shareloc"];
}
    
+ (NSString*) gender {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"gender"];
}
    
+ (void) setGender:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:@"gender"];
}
    
    
+ (NSString*) facebookId {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"fbid"];
}
    
+ (void) setFacebookId:(NSString *)value {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:@"fbid"];
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


+ (id) isDoNotTrackEnabled {
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
