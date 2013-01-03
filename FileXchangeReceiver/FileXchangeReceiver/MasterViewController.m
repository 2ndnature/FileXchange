//
//  MasterViewController.m
//  FileXchangeReceiver
//
//  Created by Brian Gerfort on 18/10/12.
//  Copyright (c) 2012 2ndNature. All rights reserved.
//

#import "MasterViewController.h"
#import "ImageViewerViewController.h"

@interface MasterViewController () <FileXchangeDelegate>
{
    NSMutableArray *_objects;
    FileXchange *_fileXchange;
    NSString *_targetFolder;
    
    NSUInteger _currentIndex;
    unsigned long long _bytesDownloaded;
    unsigned long long _totalNumberOfBytes;
    
    NSDate *_transferBegan;
}
@end

@implementation MasterViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileXchange:) name:@"FileXchange" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(timeLimitRebooted:) name:@"TimeLimitRebooted" object:nil];
        
        self.title = NSLocalizedString(@"Receiver", @"Receiver");
        _targetFolder = [[NSSearchPathForDirectoriesInDomains (NSDocumentDirectory, NSUserDomainMask, YES ) lastObject] stringByAppendingPathComponent:@"Downloads"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_targetFolder withIntermediateDirectories:YES attributes:nil error:NULL];
        _transferBegan = nil;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTintColor:[UIColor colorWithRed:175.0/255.0 green:2.0/255.0 blue:2.0/255.0 alpha:1.0]];
    [self reloadObjects];
    [self setEditing:NO animated:NO];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    UIActivityIndicatorView *spinner = (DEMO_STREAMING && _fileXchange != nil) ? [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite] : nil;
    [spinner startAnimating];
    [self.navigationItem setRightBarButtonItem:(editing) ? [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Delete all", @"Delete all button") style:UIBarButtonItemStyleBordered target:self action:@selector(deleteAll:)] : [[UIBarButtonItem alloc] initWithCustomView:spinner] animated:animated];
    
    [super setEditing:editing animated:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)deleteAll:(id)sender
{
    [[NSFileManager defaultManager] removeItemAtPath:_targetFolder error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:_targetFolder withIntermediateDirectories:YES attributes:nil error:NULL];
    [self setEditing:NO];
    [self reloadObjects];
}

- (void)fileXchange:(NSNotification *)notification
{
    DLog(@"Received FileXchange notification");
    if ([notification isKindOfClass:[NSNotification class]] == NO) return;
    
    NSDictionary *info = [notification object];
    if ([info isKindOfClass:[NSDictionary class]] == NO) return;
    
    NSString *application = [info objectForKey:@"Application"];
    if ([application isKindOfClass:[NSString class]] == NO) return;
    
    NSDictionary *data = [info objectForKey:@"Data"];
    if ([data isKindOfClass:[NSDictionary class]] == NO) return;
    
    DLog(@"%@ has %d file%@ for us!",[data objectForKey:@"AppName"],[[data objectForKey:@"Files"] count], ([[data objectForKey:@"Files"] count] == 1) ? @"" : @"s" );
    
    if (_fileXchange == nil)
    {
        // Warning: The object will start a background task and keep
        // the app alive until the object is released ..or the 10 minutes
        // of alotted backgrounding time runs out.
        
        _fileXchange = [[FileXchange alloc] initWithDelegate:self];
    }
    
    // Tell our object that there are new files, and it will call the
    // delegate method fileXchange:application:newFilesAdded: if any
    // files were added:
    
    [_fileXchange addFileXchangeData:data forApplication:application];
}

- (void)timeLimitRebooted:(NSNotification *)notification
{
    _transferBegan = [NSDate date];
}

- (void)downloadProgress:(float)theProgress
{
    UIProgressView *progress = (UIProgressView *)[self.navigationController.view viewWithTag:DOWNLOAD_PROGRESS_VIEW];
    
    if (progress == nil)
    {
        [self.navigationItem setPrompt:@""];
        progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        [self.navigationController.view addSubview:progress];
        CGRect frm = progress.frame;
        frm.origin.x = floorf((self.view.frame.size.width - frm.size.width) / 2.0);
        frm.origin.y = 20.0;
        [progress setAlpha:0.0];
        [progress setFrame:frm];
        [progress setTag:DOWNLOAD_PROGRESS_VIEW];
        [progress setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
        frm.origin.y = 38.0;
        [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationCurveEaseOut animations:^{
            
            [progress setFrame:frm];
            [progress setAlpha:1.0];
            
        } completion:^(BOOL finished) {
            
        }];
    }
    
    [UIView animateWithDuration:0.2 delay:0.0 options:UIViewAnimationCurveLinear animations:^{
        
        [progress setProgress:theProgress];
        
    } completion:^(BOOL finished) {
        
    }];
}

- (void)downloadDone
{
    UIProgressView *progress = (UIProgressView *)[self.navigationController.view viewWithTag:DOWNLOAD_PROGRESS_VIEW];
    if (progress != nil)
    {
        [progress setProgress:1.0];
        CGRect frm = progress.frame;
        frm.origin.y = -20.0;
        [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationCurveEaseOut animations:^{
            
            [progress setFrame:frm];
            [progress setAlpha:0.0];
            
        } completion:^(BOOL finished) {
            [progress removeFromSuperview];
        }];
    }
    [self.navigationItem setPrompt:nil];
    
    [self reloadObjects];
    
    // Be a good iOS citizen and release the FileXchange object when you've
    // downloaded the files you need. This will allow both apps to go to sleep.
    
    if (!DEMO_STREAMING)
    {
        DLog(@"Exchange done. Thank you, come again!");
        _fileXchange = nil;
    }
    
    _transferBegan = nil;
}

- (void)reloadObjects
{
    [_objects removeAllObjects];
    _objects = [[NSMutableArray alloc] initWithArray:[[NSFileManager defaultManager] contentsOfDirectoryAtPath:_targetFolder error:NULL]];
    
    [self.navigationItem setLeftBarButtonItem:([_objects count] > 0) ? self.editButtonItem : nil animated:YES];
    
    [self.tableView reloadData];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _objects.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    NSDate *object = _objects[indexPath.row];
    cell.textLabel.text = [object description];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete)
    {
        if ([[NSFileManager defaultManager] removeItemAtPath:[_targetFolder stringByAppendingPathComponent:[_objects[indexPath.row] description]] error:NULL])
        {
            [_objects removeObjectAtIndex:indexPath.row];
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.imageViewerViewController)
    {
        self.imageViewerViewController = [[ImageViewerViewController alloc] init];
    }
    [self.imageViewerViewController setImageFilename:[_targetFolder stringByAppendingPathComponent:[_objects[indexPath.row] description]]];
    [self.navigationController pushViewController:self.imageViewerViewController animated:YES];
}

#pragma mark - FileXchangeDelegate

- (void)fileXchange:(FileXchange *)fe application:(NSString *)application downloadedBytes:(NSUInteger)bytes soFar:(NSUInteger)bytesSoFar totalBytes:(NSUInteger)totalBytes
{
    unsigned long long totalNumberOfBytes = [[[fe fileXchangeDataForApplication:application] objectForKey:@"TotalNumberOfBytes"] unsignedLongLongValue];
    
    _bytesDownloaded += bytes;
    
    [self downloadProgress:(totalNumberOfBytes == 0) ? 0.0 : _bytesDownloaded / (float)_totalNumberOfBytes];
    
    // Potentially dangerous for epileptic customers, but would give us
    // unlimited background time for very large transfers (wonder how many
    // gigs we're talking).
    
    // This works using the CFBundleURLTypes in Info.plist in both apps and
    // handling it in application:openURL:sourceApplication:annotation:
    // method of the appDelegates. The URL Scheme for the sender must be
    // the last part of the application name.
    
    if ([_transferBegan timeIntervalSinceNow] < 60 * -9.5)
    {
        _transferBegan = nil;
        
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@://?callURL=%@",[[application componentsSeparatedByString:@"."] lastObject],[TIME_LIMIT_CALLBACK stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]]];
    }
}

- (void)fileXchange:(FileXchange *)fe application:(NSString *)application didFinishDownload:(NSString *)filePath
{
    if (DEMO_FINE_GRAINED_UPDATES_ON_RUNLOOP)
    {
        _currentIndex++;
        if (_currentIndex < [[[fe fileXchangeDataForApplication:application] objectForKey:@"Files"] count])
        {
            // Just to show there's actually a progress bar in this example app. :)
            if (DEMO_SLOW_MOTION) [NSThread sleepForTimeInterval:DEMO_SLOW_MOTION];
            
            [_fileXchange downloadFileAtIndex:_currentIndex fromApplication:application toFolder:_targetFolder];
            return;
        }
        [self downloadDone];
    }
}

- (void)fileXchange:(FileXchange *)fe application:(NSString *)application didFailWithError:(NSError *)error
{
    DLog(@"DidFailWithError: %@",[error description]);
    
    [[[UIAlertView alloc] initWithTitle:@"Error" message:[error description] delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"OK button") otherButtonTitles:nil] show];
    
    [self downloadDone];
}

- (void)fileXchange:(FileXchange *)fe application:(NSString *)application newFilesAdded:(NSRange)range
{
    DLog(@"New files added. A smart app would add that range (%d, %d in [[fe fileXchangeDataForApplication:application] objectForKey:@\"Files\"]) to a download queue. But we live dangerously in this example and just download them without checking if other downloads are active.",range.location,range.length);
    
    [self downloadProgress:0.0];
    [self setEditing:NO animated:YES];
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    
    _transferBegan = [NSDate date];
    
    if (DEMO_FINE_GRAINED_UPDATES_ON_RUNLOOP)
    {
        _currentIndex = range.location;
        _bytesDownloaded = 0;
        _totalNumberOfBytes = 0;
        
        NSArray *files = [[fe fileXchangeDataForApplication:application] objectForKey:@"Files"];
        
        for (NSUInteger idx = range.location; idx < range.location + range.length; idx++)
        {
            _totalNumberOfBytes += [[[files objectAtIndex:idx] objectAtIndex:1] unsignedLongLongValue];
        }
        
        [_fileXchange downloadFileAtIndex:_currentIndex fromApplication:application toFolder:_targetFolder];
    }
    else
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            for (NSUInteger idx = range.location; idx < range.location + range.length; idx++)
            {
                [_fileXchange synchronouslyDownloadFileAtIndex:idx fromApplication:application toFolder:_targetFolder];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    [self downloadProgress:idx / (float)(range.location + range.length)];
                    
                });
                
                // Just to show there's actually a progress bar in this example app. :)
                if (DEMO_SLOW_MOTION) [NSThread sleepForTimeInterval:DEMO_SLOW_MOTION];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [self downloadDone];
                
            });
            
        });
    }
}

@end
