//
//  xAdPanelSettings.m
//  panelapp
//
//  Created by Stephen Anderson on 2/23/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "xAdPanelSettings.h"


static NSString * const PROVISIONING_LINK = @"http://cdn.xadcentral.com/content/provisioning/%@.json";



@interface xAdPanelSettings ()
@property (nonatomic, strong) id appKey;
@property (nonatomic, strong) NSMutableDictionary *fields;
@end

@implementation xAdPanelSettings

- (id) initWithAppKey:(id)appKey;
{
    self = [super init];
    
    if (self)
    {
        self.appKey = appKey;
        
        NSDictionary *defaults = @{
                                   @"xad_panel_dob": [NSDate date],
                                   @"xad_panel_shareloc":@NO,
                                   @"xad_panel_gender":@"m"
                                   };
        
        [[NSUserDefaults standardUserDefaults] registerDefaults: defaults];

        [self retrieveSettings];
    }
    
    return self;
}









#pragma mark - Provisining Settings

- (BOOL) enabled {
    
    if (!self.fields) {
        return NO;
    }
    
    return [[self.fields objectForKey:@"enabled"] boolValue];
}


- (BOOL) requiresM7 {
    return [[self.fields objectForKey:@"requiresM7"] boolValue];
}


- (BOOL) obeyTrFlag {
    return [[self.fields objectForKey:@"obeyTrFlag"] boolValue];
}


- (id) name {
    return [self.fields objectForKey:@"name"];
}


- (BOOL) useConstTime {
    return [[self.fields objectForKey:@"constTime"] boolValue];
}


- (double) secondsBetweenSignaling {
    return [[self.fields objectForKey:@"constTimeSeconds"] doubleValue];
}


- (BOOL) eventsWhilePhoneIsLocked {
    return [[self.fields objectForKey:@"eventsWhileLocked"] boolValue];
}

- (double) distanceWhileWalking{
    return [[self.fields objectForKey:@"dWalk"] doubleValue];
}


- (double) distanceWhileRunning {
    return [[self.fields objectForKey:@"dRun"] doubleValue];
}


- (double) distanceWhileDriving {
    return [[self.fields objectForKey:@"dCar"] doubleValue];
}


- (double) timeBeforeStationary {
    return [[self.fields objectForKey:@"tStationary"] doubleValue];
}


- (double) minGeoAccuracy {
    return [[self.fields objectForKey:@"minAccuracy"] doubleValue];
}


- (double) maxGeoAge {
    return [[self.fields objectForKey:@"maxAge"] doubleValue];
}


- (NSUInteger) dataFields {
    return [[self.fields objectForKey:@"data"] doubleValue];
}



+ (NSString*) userDateOfBirth {
    NSDate *dob = [[NSUserDefaults standardUserDefaults] objectForKey:@"xad_panel_dob"];
    
    return [xAdPanelSettings stringFromTime:dob];
}



+ (NSString*) userGender {
    
    int genderValue = [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_gender"] intValue];
    
    return (genderValue == 0) ? @"m" : @"f";
}



+ (BOOL) userSharesLocation {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_panel_shareloc"] boolValue];
}



+ (NSString*) stringFromTime:(NSDate*)date
{
    NSLocale *curLocale = [NSLocale currentLocale];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    
    [dateFormatter setDateStyle:NSDateFormatterShortStyle];
    [dateFormatter setLocale:curLocale];
    
    return [dateFormatter stringFromDate:date];
}


- (void) retrieveSettings {
    
    NSURL* provisioningUrl = nil;
    NSData* provisioningData = nil;
    
    if (self.appKey) {
        provisioningUrl = [NSURL  URLWithString: [NSString stringWithFormat:PROVISIONING_LINK, self.appKey] ];
        provisioningData = [NSData dataWithContentsOfURL: provisioningUrl];
    }
    
    if (!provisioningData) {
        provisioningUrl = [NSURL  URLWithString: [NSString stringWithFormat:PROVISIONING_LINK, @"default"] ];
        provisioningData = [NSData dataWithContentsOfURL: provisioningUrl];
    }
    
    if (!provisioningData) {
        NSLog(@"Error: Unable to retrieve provisioning settings");
        return;
    }
    
#ifdef DEBUG
    NSString *json = [[NSString alloc] initWithData:provisioningData encoding:NSUTF8StringEncoding];
    NSLog(@"JSON: %@", json);
#endif

    NSError *localError = nil;
    NSDictionary *provisioning = [NSJSONSerialization JSONObjectWithData: provisioningData options: 0 error: &localError];
    
    if (!provisioning) {
        
        NSLog(@"Failed to get settings. %@", localError);
        return;
    }
    
    self.fields = [NSMutableDictionary dictionaryWithDictionary: provisioning];
}


@end
