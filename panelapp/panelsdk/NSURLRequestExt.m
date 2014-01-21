//
//  NSURLRequestExt.m
//  panelapp
//
//  Created by Stephen Anderson on 1/21/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "NSURLRequestExt.h"

@interface NSURLRequest (Extension)
    + (BOOL)allowsAnyHTTPSCertificateForHost:(NSString*)host;
    + (void)setAllowsAnyHTTPSCertificate:(BOOL)allow forHost:(NSString*)host;
@end
