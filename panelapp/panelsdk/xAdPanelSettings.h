//
//  Settings.h
//  panelapp
//
//  Created by Stephen Anderson on 2/23/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

// PRIVATE CLASS - CLIENT DOES NOT NEED TO USE

@interface xAdPanelSettings : NSObject

- (id) initWithAppKey:(id)appKey;
- (void) retrieveSettings;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL requiresM7;
@property (nonatomic, readonly) BOOL obeyTrackingFlag;
@property (nonatomic, readonly) id name;
@property (nonatomic, assign) BOOL useConstTime;
@property (nonatomic, readonly) double secondsBetweenSignaling;
@property (nonatomic, readonly) double motionUpdateInterval;
@property (nonatomic, readonly) BOOL eventsWhilePhoneIsLocked;
@property (nonatomic, readonly) double distanceWhileWalking;
@property (nonatomic, readonly) double distanceWhileRunning;
@property (nonatomic, readonly) double distanceWhileDriving;
@property (nonatomic, readonly) double timeBeforeStationary;
@property (nonatomic, readonly) double timeBeforeActive;
@property (nonatomic, readonly) double minGeoAccuracy;
@property (nonatomic, readonly) double maxGeoAge;
@property (nonatomic, readonly) double accelerationThreshold;

@property (nonatomic, readonly) NSUInteger dataFields;

@property (nonatomic, readonly) id userGender;
@property (nonatomic, readonly) id userDateOfBirth;
@property (nonatomic, readonly) BOOL userInPanel;



@end