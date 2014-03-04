//
//  xAdPanelSettings.m
//  panelapp
//
//  Created by Stephen Anderson on 2/23/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "xAdPanelSettings.h"


static NSString * const PROVISIONING_LINK = @"http://cdn.xadcentral.com/content/provisioning/%@.json";

static double TIME_BETWEEN_SETTINGS_RELOAD = 21600;


@interface xAdPanelSettings ()
@property (nonatomic, strong) id appKey;
@property (nonatomic, strong) NSMutableDictionary *fields;
@property (nonatomic, strong) NSTimer *settingsTimer;

@end

@implementation xAdPanelSettings

- (id) initWithAppKey:(id)appKey;
{
    self = [super init];
    
    if (self)
    {
        self.appKey = appKey;

        self.settingsTimer = [NSTimer scheduledTimerWithTimeInterval: TIME_BETWEEN_SETTINGS_RELOAD
                                                             target: self
                                                           selector: @selector(onRefreshSettingsTimerExpired:)
                                                           userInfo: nil
                                                            repeats: YES];
        
        [self performSelector:@selector(retrieveSettings) withObject:nil afterDelay:0];
    }
    
    return self;
}




- (void) onRefreshSettingsTimerExpired:(NSTimer *)timer {
    NSLog(@"onRefreshSettingsTimerExpired");
    [self retrieveSettings];
}




#pragma mark - Provisining Settings


- (xAdPanelSdkMode) mode {
    
    if (!self.fields) {
        return xAdPanelSdkModeDisabled;
    }

    int value = [[self.fields objectForKey:@"mode"] intValue];
    
    if (value < 0 || value > xAdPanelSdkModeOnStop) {
        return xAdPanelSdkModeDisabled;
    }
    
    return value;
}


- (void) setMode:(xAdPanelSdkMode)value {
    return [self.fields setObject: [NSNumber numberWithInt: value] forKey:@"mode"];
}


- (BOOL) requiresM7 {
    return [[self.fields objectForKey:@"requiresM7"] boolValue];
}


- (BOOL) obeyTrackingFlag {
    return [[self.fields objectForKey:@"obeyTrFlag"] boolValue];
}


- (id) name {
    return [self.fields objectForKey:@"name"];
}


- (double) secondsBetweenSignaling {
    return [[self.fields objectForKey:@"constTimeSeconds"] doubleValue];
}


- (double) motionUpdateInterval {
    return [[self.fields objectForKey:@"motionUpdateInterval"] doubleValue];
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


- (double) timeBeforeActive {
    return [[self.fields objectForKey:@"tActive"] doubleValue];
}


- (double) minGeoAccuracy {
    return [[self.fields objectForKey:@"minAccuracy"] doubleValue];
}


- (double) maxGeoAge {
    return [[self.fields objectForKey:@"maxAge"] doubleValue];
}


- (double) accelerationThreshold {
    return [[self.fields objectForKey:@"accelerationThreshold"] doubleValue];
}


- (NSUInteger) dataFields {
    return [[self.fields objectForKey:@"data"] doubleValue];
}



- (NSString*) userDateOfBirth {
    NSDate *dob = [[NSUserDefaults standardUserDefaults] objectForKey:@"xad_panel_dob"];
    
    return [xAdPanelSettings stringFromTime:dob];
}



- (NSString*) userGender {
    
    int genderValue = [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_user_in_panel"] intValue];
    
    return (genderValue == 0) ? @"m" : @"f";
}



- (BOOL) userInPanel {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:@"xad_user_in_panel"] boolValue];
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

    [[NSNotificationCenter defaultCenter] postNotificationName:@"XAD_SETTINGS_UPDATED" object: self];
}


@end
