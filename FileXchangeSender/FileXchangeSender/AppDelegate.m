//
//  AppDelegate.m
//  FileXchangeSender
//
//  Created by Brian Gerfort on 18/10/12.
//  Copyright (c) 2012 2ndNature. All rights reserved.
//

#import "AppDelegate.h"

#import "MasterViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    
    MasterViewController *masterViewController = [[MasterViewController alloc] initWithNibName:@"MasterViewController" bundle:nil];
    self.navigationController = [[UINavigationController alloc] initWithRootViewController:masterViewController];
    self.window.rootViewController = self.navigationController;
    [self.window makeKeyAndVisible];
    return YES;
}

// Multitasking time limit workaround for large transfers.

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if ([url isKindOfClass:[NSURL class]])
	{
        NSRange parm = [[url absoluteString] rangeOfString:@"?callURL="];
        if (parm.location == NSNotFound) return NO;
        
        NSString *callURL = [[url absoluteString] substringFromIndex:parm.location+parm.length];
        if ([callURL length] > 0)
        {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:callURL]];
            return YES;
        }
    }
    return NO;
}

@end
