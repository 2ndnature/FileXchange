//
//  MasterViewController.h
//  FileXchangeReceiver
//
//  Created by Brian Gerfort on 18/10/12.
//  Copyright (c) 2012 2ndNature. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FileXchange.h"

#define DOWNLOAD_PROGRESS_VIEW  123123

#define DEMO_FINE_GRAINED_UPDATES_ON_RUNLOOP    0
#define DEMO_STREAMING                          0
#define DEMO_SLOW_MOTION                        0.3

#define TIME_LIMIT_CALLBACK @"filexchangeclient://?anothertenminutes"

@class ImageViewerViewController;

@interface MasterViewController : UITableViewController

@property (strong, nonatomic) ImageViewerViewController *imageViewerViewController;

@end
