//
//  MasterViewController.m
//  FileXchangeSender
//
//  Created by Brian Gerfort on 18/10/12.
//  Copyright (c) 2012 2ndNature. All rights reserved.
//

#import "MasterViewController.h"
#import "FileXchange.h"

@interface MasterViewController () <FileXchangeDelegate>
{
    NSMutableArray *_objects;
    FileXchange *_fileXchange;
    NSMutableDictionary *_selection;
    NSString *_exampleFilesFolder;
}
@end

@implementation MasterViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        self.title = NSLocalizedString(@"Sender", @"Sender");
        _fileXchange = [[FileXchange alloc] initWithDelegate:self];
        _selection = [[NSMutableDictionary alloc] initWithCapacity:0];
        _exampleFilesFolder = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"ExampleFiles"];
        _objects = [[NSMutableArray alloc] initWithArray:[[NSFileManager defaultManager] contentsOfDirectoryAtPath:_exampleFilesFolder error:NULL]];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTintColor:[UIColor colorWithRed:35.0/255.0 green:89.0/255.0 blue:162.0/255.0 alpha:1.0]];
    [self updateButtons];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)invertSelection:(id)sender
{
    for (NSInteger idx = 0; idx < [_objects count]; idx++)
    {
        NSString *key = [NSString stringWithFormat:@"%d",idx];
        NSNumber *selected = [_selection objectForKey:key];
        
        if ([selected boolValue])
        {
            [_selection removeObjectForKey:key];
        }
        else
        {
            [_selection setObject:[NSNumber numberWithBool:YES] forKey:key];
        }
    }
    [self.tableView reloadData];
    [self updateButtons];
}

- (void)pushSelection:(id)sender
{
    // Dispatching to a background queue because addNewFiles:andNotifyApplication:
    // could take seconds to return if the client is missing in action.
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        if ([[[_fileXchange sharingInfo] allKeys] count] > 0)
        {
            NSString *streamApp = [[[_fileXchange sharingInfo] allKeys] objectAtIndex:0];
            if (streamApp != nil)
            {
                if ([_fileXchange addNewFiles:[self selectedFiles] andNotifyApplication:streamApp])
                {
                    DLog(@"Notification delivered.");
                    return;
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            
            DLog(@"Notification could not be delivered.");
            [self updateButtons];
            [self shareFiles:self.navigationItem.rightBarButtonItem];
            
        });
        
    });
}

- (void)updateButtons
{
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Invert", @"Invert button") style:UIBarButtonItemStyleBordered target:self action:@selector(invertSelection:)];
    if (DEMO_STREAMING && [[[_fileXchange sharingInfo] allKeys] count])
    {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Push", @"Push button") style:UIBarButtonItemStyleBordered target:self action:@selector(pushSelection:)];
    }
    else
    {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Service-icon-inverted-32px-PhotoCopy"] style:UIBarButtonItemStyleBordered target:self action:@selector(shareFiles:)];
    }
    [self.navigationItem.rightBarButtonItem setEnabled:([_selection count] > 0)];
}

- (NSMutableArray *)selectedFiles
{
    NSMutableArray *files = [[NSMutableArray alloc] initWithCapacity:[_selection count]];
    if (DEMO_SUGGESTED_FILENAMES_AND_USER_INFO)
    {
        int i = 0;
        for (NSString *key in _selection)
        {
            NSString *filePath = [_exampleFilesFolder stringByAppendingPathComponent:[_objects objectAtIndex:[key integerValue]]];
            [files addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                              filePath,kFileXchangeFilePath,
                              [NSString stringWithFormat:@"%d.%@",i,[filePath pathExtension]],kFileXchangeSuggestedFilename,
                              [NSDictionary dictionaryWithObjectsAndKeys:@"UserInfo 1", @"Parm 1", @"UserInfo 2", @"Parm 2", nil], kFileXchangeUserInfo,
                              nil]];
            i++;
        }
    }
    else
    {
        for (NSString *key in _selection)
        {
            [files addObject:[_exampleFilesFolder stringByAppendingPathComponent:[_objects objectAtIndex:[key integerValue]]]];
        }
    }
    return files;
}

- (void)shareFiles:(id)sender
{
    [_fileXchange presentMenuFromBarButtonItem:sender animated:YES servingFiles:[self selectedFiles]];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_objects count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    cell.accessoryType = ([[_selection objectForKey:[NSString stringWithFormat:@"%d",indexPath.row]] boolValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    NSDate *object = [_objects objectAtIndex:indexPath.row];
    cell.textLabel.text = [object description];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *key = [NSString stringWithFormat:@"%d",indexPath.row];
    NSNumber *selected = [_selection objectForKey:key];
    
    if ([selected boolValue])
    {
        [_selection removeObjectForKey:key];
    }
    else
    {
        [_selection setObject:[NSNumber numberWithBool:YES] forKey:key];
    }
    
    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
    
    [self updateButtons];
}

#pragma mark - FileXchangeDelegate

- (void)fileXchange:(FileXchange *)fe applicationDidAcceptSharing:(NSString *)application
{
    [self updateButtons];
}

- (void)fileXchange:(FileXchange *)fe applicationDidCloseConnection:(NSString *)application
{
    [self updateButtons];
}

@end
