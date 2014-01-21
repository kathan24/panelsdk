//
//  PanelSdk.m
//  panelapp
//
//  Created by Stephen Anderson on 1/21/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "PanelSdk.h"
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import "NSURLRequestExt.h"
#import "AppUtils.h"

@interface PanelSdk ()
    @property (strong, nonatomic)  NSTimer *pulseTimer;
    @property (strong, nonatomic) CLLocation *cachedLocation;
    @property (strong, nonatomic) CLLocationManager *locationManager;
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
        NSDictionary *defaults = @{@"dob": [NSDate date], @"sharefb":@NO, @"shareloc":@NO };
        [[NSUserDefaults standardUserDefaults] registerDefaults: defaults];
    }
}
    

- (id) init {
    
    self = [super init];
    
    if (self) {
        
        self.pulseTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(onTimerExpired:) userInfo:nil repeats:YES];
        self.cachedLocation = [[CLLocation alloc] initWithLatitude:40.780184 longitude:-73.966827];
        
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
        [self.locationManager startMonitoringSignificantLocationChanges];
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
    
- (void) transmitData {
    
    NSLog(@"transmitData");
    
    NSURL *resourceUrl = nil;

    resourceUrl = [NSURL URLWithString:@"https://ap.xad.com/rest/panel"];
    
    
    NSDictionary *params = @{
                             @"app": [AppUtils applicationName],
                             @"idfa": [AppUtils advertisingIdentifier],
                             @"fbid": @"",
                             @"dob": [PanelSdk dateOfBirth],
                             @"lat": [NSString stringWithFormat:@"%f", self.cachedLocation.coordinate.latitude],
                             @"lon": [NSString stringWithFormat:@"%f", self.cachedLocation.coordinate.longitude],
                             };
    
    
    id httpRequest = [AppUtils createRequestWithUrl:resourceUrl andParameters:params];
    
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
    

    
@end
