//
//  PanelSettingsViewController.m
//  Sample Panel Application
//
//  Created by Stephen Anderson on 1/10/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "PanelSettingsViewController.h"
#import "xAdPanelSdk.h"

@interface PanelSettingsViewController ()
    @property (weak, nonatomic) IBOutlet UIDatePicker *dateOfBirth;
    @property (weak, nonatomic) IBOutlet UISwitch *joinPanel;
    @property (weak, nonatomic) IBOutlet UISegmentedControl *gender;
  
@end



@implementation PanelSettingsViewController



    
    
- (IBAction)onDobChanged:(id)sender {
    [xAdPanelSdk setDateOfBirth: self.dateOfBirth.date];
}
    
    
- (IBAction)onJoinPanelChanged:(id)sender {
    [xAdPanelSdk setUserInPanel: self.joinPanel.on];
}
    
    
- (IBAction)onGenderChanged:(id)sender {
    [xAdPanelSdk setGender: self.gender.selectedSegmentIndex == 0 ? GenderMale : GenderFemale];
}
    


    
    
- (void)viewDidLoad
{
    [super viewDidLoad];

    self.dateOfBirth.date = [xAdPanelSdk dateOfBirth];
    self.joinPanel.on = [xAdPanelSdk userInPanel];
    self.gender.selectedSegmentIndex = [xAdPanelSdk gender];
}




@end
