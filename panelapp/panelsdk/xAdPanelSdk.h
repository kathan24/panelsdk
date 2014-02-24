//
//  xAdPanelSdk.h
//  xAd Panel SDK
//
//  Created by Stephen Anderson on 1/21/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>


typedef enum {
    GenderMale,
    GenderFemale
} xAdPanelSdkGender;


@interface xAdPanelSdk : NSObject <CLLocationManagerDelegate>


+ (void) startPanelSdkWithAppKey:(id)appKey;


+ (NSDate*)dateOfBirth;
+ (void) setDateOfBirth:(NSDate*)value;

+ (xAdPanelSdkGender) gender;
+ (void) setGender:(xAdPanelSdkGender)value;

+ (BOOL) shareLocation;
+ (void) setShareLocation:(BOOL)value;





@end
