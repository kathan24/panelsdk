//
//  xAdPanelSdk.h
//  xAd Panel SDK
//
//  Created by Stephen Anderson on 1/21/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

UIKIT_EXTERN NSString * const XAD_NOTIFICATION_DATA_TRANSMITTED;
UIKIT_EXTERN NSString * const XAD_NOTIFICATION_ACTIVITY_DETECTED;


@interface xAdPanelSdk : NSObject <CLLocationManagerDelegate>

+ (void) initialize;
    
+ (NSDate*) dateOfBirth;
+ (void) setDateOfBirth:(NSDate*)value;
    
+ (BOOL) sharefb;
+ (void) setSharefb:(BOOL)value;

+ (BOOL) shareloc;
+ (void) setShareloc:(BOOL)value;
    
+ (NSString*) gender;
+ (void) setGender:(NSString*)value;


@end
