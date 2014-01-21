//
//  AppUtils.h
//  panelapp
//
//  Created by Stephen Anderson on 1/19/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface AppUtils : NSObject
    
+ (NSString*) toUrlEncoded:(NSDictionary*)fields;
+ (NSMutableURLRequest*) createRequestWithUrl:(NSURL *)resourceUrl andParameters:(NSDictionary *)params;
    
+ (id) applicationName;
+ (id) applicationVersion;
+ (id) deviceLanguage;
+ (id) advertisingIdentifier;
+ (id) isDoNotTrackEnabled;
+ (NSString*) stringFromTime:(NSDate*)date;

    
@end
