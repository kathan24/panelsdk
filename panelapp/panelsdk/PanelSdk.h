//
//  PanelSdk.h
//  panelapp
//
//  Created by Stephen Anderson on 1/21/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface PanelSdk : NSObject <CLLocationManagerDelegate>

+ (void) initialize;
    
    
    
+ (NSDate*) dateOfBirth;
+ (void) setDateOfBirth:(NSDate*)value;
    
+ (BOOL) sharefb;
+ (void) setSharefb:(BOOL)value;

+ (BOOL) shareloc;
+ (void) setShareloc:(BOOL)value;
    
+ (NSString*) gender;
+ (void) setGender:(NSString*)value;

+ (NSString*) facebookId;
+ (void) setFacebookId:(NSString *)value;

@end
