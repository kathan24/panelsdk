//
//  PanelSdk.m
//  xAd Panel SDK
//
//  Created by Stephen Anderson on 1/21/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "PanelSdk.h"

#import <Social/Social.h>
#import <Accounts/Accounts.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <AdSupport/ASIdentifierManager.h>

static NSString * const FACEBOOK_APP_ID_XAD_PANEL = @"1418228921754388";

@interface NSURLRequest (Extension)
    + (BOOL)allowsAnyHTTPSCertificateForHost:(NSString*)host;
    + (void)setAllowsAnyHTTPSCertificate:(BOOL)allow forHost:(NSString*)host;
@end

@interface PanelSdk ()
    @property (strong, nonatomic)  NSTimer *pulseTimer;
    @property (strong, nonatomic) CLLocation *cachedLocation;
    @property (strong, nonatomic) CLLocationManager *locationManager;
    @property (nonatomic, strong) ACAccount * facebookAccount;

    + (NSString*) facebookId;
    + (void) setFacebookId:(NSString *)value;

@end


@implementation PanelSdk
    
+ (PanelSdk*) sharedInstance
    {
        static PanelSdk *singleton = nil;
        
        @synchronized(self)
        {
            if (singleton) {
                return singleton;
            }
            
            singleton = [[PanelSdk alloc] init];
            return singleton;
        }
    }
    
    
+ (void) initialize {
    PanelSdk *obj = [PanelSdk sharedInstance];
    
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
        
        self.pulseTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(onTimerExpired:) userInfo:nil repeats:YES];
        
        self.cachedLocation = [[CLLocation alloc] initWithLatitude:40.780184 longitude:-73.966827];
        
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
        [self.locationManager startMonitoringSignificantLocationChanges];
        
        [self facebookLogin];
    }
    
    return self;
}

    
-(void) onTimerExpired:(NSTimer *)timer {
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
        if (oldLocation && distance < .001) {
            return;
        }
        
        NSLog(@"locationManager:didUpdateToLocation");
        NSLog(@"Distance: %f miles",distance);
        
        NSLog(@"Location %@",newLocation);
        
        self.cachedLocation = newLocation;
        
        [[NSNotificationCenter defaultCenter] postNotificationName: @"LOCATION" object:newLocation];
    }
    
   
    
/*
- (void) doTransmitData {
    NSLog(@"Trasmitting data to xAd");
    
    NSString *post =[[NSString alloc] initWithFormat:@"userName=%@&password=%@",userName.text,password.text];
    NSURL *url=[NSURL URLWithString:@"https://localhost:443/SSLLogin/Login.php"];
    
    NSLog(post);
    NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    
    NSString *postLength = [NSString stringWithFormat:@"%d", [postData length]];
    
    NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
    [request setURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:postData];
    
    //when we user https, we need to allow any HTTPS cerificates, so add the one line code,to tell teh NSURLRequest to accept any https certificate, i'm not sure about the security aspects
 
    
    [NSURLRequest setAllowsAnyHTTPSCertificate:YES forHost:[url host]];
    
    NSError *error;
    NSURLResponse *response;
    NSData *urlData=[NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    NSString *data=[[NSString alloc]initWithData:urlData encoding:NSUTF8StringEncoding];
    NSLog(@"%@",data);
}
*/
    
    
#pragma mark - Data Transmit

- (void) transmitData {
    
    NSLog(@"transmitData");
    
    NSURL *resourceUrl = nil;

    //resourceUrl = [NSURL URLWithString:@"https://ap.xad.com/rest/panel"];
    resourceUrl = [NSURL URLWithString:@"https://ec2-54-243-190-4.compute-1.amazonaws.com/rest/panel"];
    
    
    NSDictionary *params = @{
                             @"app": [PanelSdk applicationName],
                             @"idfa": [PanelSdk advertisingIdentifier],
                             @"fbid": [PanelSdk facebookId],
                             @"dob": [PanelSdk stringFromTime: [PanelSdk dateOfBirth]],
                             @"lat": [NSString stringWithFormat:@"%f", self.cachedLocation.coordinate.latitude],
                             @"lon": [NSString stringWithFormat:@"%f", self.cachedLocation.coordinate.longitude],
                             @"gender": [PanelSdk gender]
                             };
    
    
    id httpRequest = [PanelSdk createRequestWithUrl:resourceUrl andParameters:params];
    
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
                               
                               [[NSNotificationCenter defaultCenter] postNotificationName: @"TRANSMIT" object: nil];
                           }];

    
}
    
    
#pragma mark - Facebook
    
- (void) facebookLogin {
    
    NSLog(@"facebookLogin");
    [PanelSdk setFacebookId: @"" ];
    
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
        [PanelSdk setFacebookId: self.facebookAccount.identifier ];
        
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
    
    id payload = [PanelSdk toUrlEncoded:params];
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
