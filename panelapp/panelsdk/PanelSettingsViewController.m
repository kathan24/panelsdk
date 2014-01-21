//
//  PanelSettingsViewController.m
//  panelapp
//
//  Created by Stephen Anderson on 1/10/14.
//  Copyright (c) 2014 xAd Inc. All rights reserved.
//

#import "PanelSettingsViewController.h"
#import "PanelSdk.h"

@interface PanelSettingsViewController ()
    @property (weak, nonatomic) IBOutlet UIDatePicker *dateOfBirth;
    @property (weak, nonatomic) IBOutlet UISwitch *shareFacebook;
    @property (weak, nonatomic) IBOutlet UISwitch *shareLocation;

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
    
    [PanelSdk setDateOfBirth: self.dateOfBirth.date];
    [PanelSdk setSharefb: self.shareFacebook.on];
    [PanelSdk setShareloc: self.shareLocation.on];
    
    [self dismissViewControllerAnimated:YES completion: nil];
}

    
    
- (void)viewDidLoad
{
    [super viewDidLoad];

    self.dateOfBirth.date = [PanelSdk dateOfBirth];
    self.shareFacebook.on = [PanelSdk sharefb];
    self.shareLocation.on = [PanelSdk shareloc];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
