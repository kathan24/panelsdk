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
    @property (weak, nonatomic) IBOutlet UISwitch *shareFacebook;
    @property (weak, nonatomic) IBOutlet UISwitch *shareLocation;
    @property (weak, nonatomic) IBOutlet UISegmentedControl *gender;

    @property (weak, nonatomic) IBOutlet UILabel *labelTitle;
    @property (weak, nonatomic) IBOutlet UILabel *labelDOB;
    @property (weak, nonatomic) IBOutlet UILabel *labelShareFb;
    @property (weak, nonatomic) IBOutlet UILabel *labelShareLoc;
    
@end

@implementation PanelSettingsViewController

+ (PanelSettingsViewController*) create {
    return [[PanelSettingsViewController alloc] initWithNibName:@"PanelSettingsViewController" bundle:nil];
}
    
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}
    
    
- (IBAction)onDoneTapped:(id)sender {
    
    [xAdPanelSdk setDateOfBirth: self.dateOfBirth.date];
    [xAdPanelSdk setShareLocation: self.shareLocation.on];
    [xAdPanelSdk setGender: self.gender.selectedSegmentIndex == 0 ? GenderMale : GenderFemale];
    [self dismissViewControllerAnimated:YES completion: nil];
}

    
    
- (void)viewDidLoad
{
    [super viewDidLoad];

    self.dateOfBirth.date = [xAdPanelSdk dateOfBirth];
    self.shareLocation.on = [xAdPanelSdk shareLocation];
    
    self.gender.selectedSegmentIndex = [xAdPanelSdk gender];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
