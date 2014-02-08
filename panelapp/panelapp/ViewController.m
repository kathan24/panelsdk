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

@interface ViewController ()
    @property (readwrite)	CFURLRef		soundFileURLRef;
    @property (readonly)	SystemSoundID	soundFileObject;
    @property (weak, nonatomic) IBOutlet UILabel *activityLabel;
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
    
}
    
    
- (void) onTrasmitCompleted:(NSNotification*)notification {
    NSLog(@"onTrasmitCompleted");
    AudioServicesPlaySystemSound (_soundFileObject);
}


- (void) onActivityDetected:(NSNotification*)notification {
    NSLog(@"onActivityDetected");
   
    self.activityLabel.text = notification.object;
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
