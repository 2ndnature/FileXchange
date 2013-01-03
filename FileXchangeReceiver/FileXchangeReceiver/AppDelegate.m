//
//  AppDelegate.m
//  FileXchangeReceiver
//
//  Created by Brian Gerfort on 18/10/12.
//  Copyright (c) 2012 2ndNature. All rights reserved.
//

#import "AppDelegate.h"
#import "MasterViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    DLog(@"didFinishLaunchingWithOptions %@",[launchOptions description]);
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    MasterViewController *masterViewController = [[MasterViewController alloc] initWithNibName:@"MasterViewController" bundle:nil];
    self.navigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
    self.window.rootViewController = self.navigationController;
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    DLog(@"openURL %@, %@, %@",[url description],sourceApplication,annotation);
    if ([url isKindOfClass:[NSURL class]])
	{
        NSString *uti = nil;
        if ([url getResourceValue:&uti forKey:NSURLTypeIdentifierKey error:NULL] && [uti caseInsensitiveCompare:@"com.2ndnature.FileXchange"] == NSOrderedSame)
        {
            DLog(@"Post notification");
            NSDictionary *fileXchangeData = [NSDictionary dictionaryWithContentsOfURL:url];
            [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"FileXchange" object:[NSDictionary dictionaryWithObjectsAndKeys:sourceApplication, @"Application", fileXchangeData, @"Data", nil]]];
            
            DLog(@"Delete file");
            [[NSFileManager defaultManager] removeItemAtURL:url error:NULL]; // Not needed after we read it.
            
            return YES;
        }
        
        // Multitasking time limit workaround for large transfers.
        if ([[url absoluteString] isEqualToString:TIME_LIMIT_CALLBACK])
        {
            [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"TimeLimitRebooted" object:nil]];
            return YES;
        }
    }
    return NO;
}

@end
