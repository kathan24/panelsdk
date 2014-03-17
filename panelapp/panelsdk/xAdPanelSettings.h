//
//  Settings.h
//  panelapp
//
//  Created by Stephen Anderson on 2/23/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

// PRIVATE CLASS - CLIENT DOES NOT NEED TO USE


typedef enum {
    /* Panel SDK is disabled and no services are activated */
    xAdPanelSdkModeDisabled = 0,
    
    /* GPS is active while activity is detected, and signals are sent when
     X amount of time has passed or user becomes stationary. */
    xAdPanelSdkModeConstTime = 1,
    
    /* GPS is active while activity is detected, and signals are sent when
     the user has walked X amount of distance. Thresholds are constant 
     but vary by activity. Requires the M7 chip, when not present switches
     to the xAdPanelSdkModeGpsOnlyOnStop mode*/
    xAdPanelSdkModeConstDistance = 2,
    
    /*  When stationary detected, then we turn the GPS on. Get the 
     best accuracy we can and deliver. The turn GPS off again. */
    xAdPanelSdkModeGpsOnlyOnStop = 3
    
} xAdPanelSdkMode;



@interface xAdPanelSettings : NSObject

- (id) initWithAppKey:(id)appKey;
- (void) retrieveSettings;

@property (nonatomic, assign) xAdPanelSdkMode mode;

@property (nonatomic, readonly) BOOL requiresM7;
@property (nonatomic, readonly) BOOL obeyTrackingFlag;
@property (nonatomic, readonly) id name;

@property (nonatomic, readonly) double secondsBetweenSignaling;
@property (nonatomic, readonly) double motionUpdateInterval;
@property (nonatomic, readonly) BOOL eventsWhilePhoneIsLocked;
@property (nonatomic, readonly) double distanceWhileWalking;
@property (nonatomic, readonly) double distanceWhileRunning;
@property (nonatomic, readonly) double distanceWhileDriving;
@property (nonatomic, readonly) double timeBeforeStationary;
@property (nonatomic, readonly) double timeBeforeActive;
@property (nonatomic, readonly) double minHorizontalAccuracy;
@property (nonatomic, readonly) double maxGeoAge;
@property (nonatomic, readonly) double accelerationThreshold;
@property (nonatomic, readonly) double distanceFilter;

@property (nonatomic, readonly) NSUInteger dataFields;

@end
