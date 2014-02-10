//
//  ViewController.m
//  Sample Panel Application
//
//  Created by Stephen Anderson on 1/10/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "ViewController.h"
#import "xAdPanelSdk.h"
#import "PanelSettingsViewController.h"
#include <AudioToolbox/AudioToolbox.h>
#include <CoreLocation/CoreLocation.h>

@interface ViewController ()
    @property (readwrite)	CFURLRef		soundFileURLRef;
    @property (readonly)	SystemSoundID	soundFileObject;
    @property (weak, nonatomic) IBOutlet UILabel *activityLabel;

    @property (weak, nonatomic) IBOutlet UILabel *labelC;
    @property (weak, nonatomic) IBOutlet UILabel *labelB;
    @property (weak, nonatomic) IBOutlet UILabel *labelA;
    @property (weak, nonatomic) IBOutlet UILabel *labelD;
@property (weak, nonatomic) IBOutlet UILabel *labelGeo;
@property (weak, nonatomic) IBOutlet UILabel *labelAddress;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    

    NSURL *sonarSound = [[NSBundle mainBundle] URLForResource: @"sonar_ping" withExtension: @"aif"];
    _soundFileURLRef = (CFURLRef) CFBridgingRetain(sonarSound);

    AudioServicesCreateSystemSoundID ( _soundFileURLRef, &_soundFileObject );
	
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    [nc addObserver:self
           selector: @selector(onTrasmitCompleted:)
               name: XAD_NOTIFICATION_DATA_TRANSMITTED
             object: nil];
    
    
    [nc addObserver:self
           selector:@selector(onActivityDetected:)
               name:XAD_NOTIFICATION_ACTIVITY_DETECTED
             object:nil];
    
    [nc addObserver:self
           selector:@selector(onSignalADetected:)
               name:@"SIGNAL_A"
             object:nil];
    
    [nc addObserver:self
           selector:@selector(onSignalBDetected:)
               name:@"SIGNAL_B"
             object:nil];
    
    [nc addObserver:self
           selector:@selector(onSignalCDetected:)
               name:@"SIGNAL_C"
             object:nil];
    
    [nc addObserver:self
           selector:@selector(onSignalDDetected:)
               name:@"SIGNAL_D"
             object:nil];
    
    [nc addObserver:self
           selector:@selector(onSignalGeoDetected:)
               name:@"SIGNAL_GEO"
             object:nil];

    [nc addObserver:self
           selector:@selector(onSignalGeoDisabled:)
               name:@"SIGNAL_GEO_OFF"
             object:nil];
    
    [nc addObserver:self
           selector:@selector(onDoNotTrackDetected:)
               name:@"DNT"
             object:nil];
    
    
}
    
    
- (void) onTrasmitCompleted:(NSNotification*)notification {
    NSLog(@"onTrasmitCompleted");
    AudioServicesPlaySystemSound (_soundFileObject);
}


- (void) onActivityDetected:(NSNotification*)notification {
    self.activityLabel.text = notification.object;
}


- (void) onSignalADetected:(NSNotification*)notification {
    self.labelA.text = notification.object;
}


- (void) onSignalBDetected:(NSNotification*)notification {
    self.labelB.text = notification.object;
}


- (void) onSignalCDetected:(NSNotification*)notification {
    self.labelC.text = notification.object;
}


- (void)onSignalDDetected:(NSNotification*)notification {
    self.labelD.text = notification.object;
}


- (void) onSignalGeoDisabled: (NSNotification*) notification {
    [[[UIAlertView alloc] initWithTitle:@"Location Sharing" message:@"The SDK detected that the location sharing request was denied. The Panel SDK will not operate without location.\n\nPlease enable location sharing and try again." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void) onDoNotTrackDetected: (NSNotification*) notification {
    [[[UIAlertView alloc] initWithTitle:@"Advertiser Tracking" message:@"The SDK detected you wish not to be tracked. The Panel SDK will not operate without tracking.\n\nPlease enable tracking under Settings / General / Privacy and try again." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}




- (void)onSignalGeoDetected:(NSNotification*)notification {
    CLLocation* geo = (CLLocation*)notification.object;
    self.labelGeo.text = [NSString stringWithFormat:@"%f, %f", geo.coordinate.latitude, geo.coordinate.longitude];

    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder reverseGeocodeLocation:geo completionHandler:^(NSArray *placemarks, NSError *error){
        
        if (placemarks.count == 0) {
            self.labelAddress.text = @"Unknown";
        }
        
        CLPlacemark *placemark = placemarks[0];
        
        if (placemark) {
            self.labelAddress.text = placemark.name;
        }
    }];
}




- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
    
    
- (IBAction)onSettingsTapped:(id)sender {
    
    PanelSettingsViewController *settings = [PanelSettingsViewController create];
    
    [self presentViewController: settings animated:YES completion: nil];
}

@end
