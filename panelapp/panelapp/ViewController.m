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
@property (readwrite) CFURLRef soundFileURLRef;
@property (readonly) SystemSoundID soundFileObject;
@property (weak, nonatomic) IBOutlet UISwitch *switchPlaySound;
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
               name: @"XAD_DATA_TRANSMITTED"
             object: nil];
 }



- (void) onTrasmitCompleted:(NSNotification*)notification {
    NSLog(@"onTrasmitCompleted");
    
    if (self.switchPlaySound.on) {
        AudioServicesPlaySystemSound (_soundFileObject);
    }
}



- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
    
    


@end
