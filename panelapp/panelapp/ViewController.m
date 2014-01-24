//
//  ViewController.m
//  Sample Panel Application
//
//  Created by Stephen Anderson on 1/10/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "ViewController.h"
#import "PanelSettingsViewController.h"
#include <AudioToolbox/AudioToolbox.h>

@interface ViewController ()
    @property (readwrite)	CFURLRef		soundFileURLRef;
    @property (readonly)	SystemSoundID	soundFileObject;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    

    NSURL *tapSound = [[NSBundle mainBundle] URLForResource: @"tap" withExtension: @"aif"];
    _soundFileURLRef = (CFURLRef) CFBridgingRetain(tapSound);

    AudioServicesCreateSystemSoundID ( _soundFileURLRef, &_soundFileObject );
	
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    [nc addObserver:self
           selector: @selector(onTrasmitCompleted:)
               name: @"TRANSMIT"
             object: nil];
}
    
    
- (void) onTrasmitCompleted:(NSNotification*)notification {
    NSLog(@"onTrasmitCompleted");
    AudioServicesPlaySystemSound (_soundFileObject);
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
