//
//  FileXchange.m
//  FileXchange
//
//  Created by Brian Gerfort on 18/10/12.
//  Copyright (c) 2012 2ndNature. All rights reserved.
//

#import "FileXchange.h"
#import "HTTPDataResponse.h"
#import "HTTPFileResponse.h"
#import "DDData.h"
#include <sys/time.h>
#import <CommonCrypto/CommonDigest.h>

#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#define PULSE_INTERVAL          10.0
#define FILEXCHANGE_VERSION     1.3

NSString *const kFileXchangeFilePath = @"kFileXchangeFilePath";
NSString *const kFileXchangeSuggestedFilename = @"kFileXchangeSuggestedFilename";
NSString *const kFileXchangeUserInfo = @"kFileXchangeUserInfo";

// The PhotoCopy service uses FileXchange and passes an NSDictionary as UserInfo for files if needed.
// The following is a list of standard keys used in that dictionary.

NSString *const kFileXchangeUserInfo_PhotoCopyDictionaryKeyXMPString = @"kFileXchangeUserInfo_PhotoCopyDictionaryKeyXMPString";

@interface FileXchange () <UIDocumentInteractionControllerDelegate>
{
	UIDocumentInteractionController *docIntController;
    dispatch_queue_t sharingQueue;
    
    NSMutableDictionary *sharing;
    BOOL transit;
    
    NSURLConnection *fileDownloadConnection;
    NSString *fileDownloadApplication;
    NSString *fileDownloadFilePath;
    NSFileHandle *fileDownloadHandle;
    NSUInteger fileDownloadIndex;
    unsigned long long bytesTransferred;
    unsigned long long totalNumberOfBytes;
    
    NSMutableDictionary *servers;
    
    UIBackgroundTaskIdentifier clientActive;
}

- (void)requestStart:(NSString *)application uuid:(NSString *)uuid port:(NSUInteger)port;
- (NSString *)pathForFileAtIndex:(NSUInteger)fileNo application:(NSString *)application;
- (NSArray *)newFilesForApplication:(NSString *)application;

- (BOOL)getUpdatesFromApplication:(NSString *)application;

@end

@implementation FileXchange

+ (NSString *)generateUUID
{
	CFUUIDRef     myUUID;
	CFStringRef   myUUIDString;
	char          strBuffer[100];
	myUUID = CFUUIDCreate(kCFAllocatorDefault);
	myUUIDString = CFUUIDCreateString(kCFAllocatorDefault, myUUID);
	CFStringGetCString(myUUIDString, strBuffer, 100, kCFStringEncodingASCII);
	CFRelease(myUUID);
	CFRelease(myUUIDString);
	return [NSString stringWithFormat:@"%s",strBuffer];
}

+ (UInt16)randomPort
{
	struct timeval tv;
    unsigned short int seed[3];
    gettimeofday(&tv, NULL);
    seed[0] = (tv.tv_sec >> 16) & 0xFFFF;
    seed[1] = tv.tv_sec & 0xFFFF;
    seed[2] = tv.tv_usec & 0xFFFF;
    seed48(seed);
	return (lrand48() % 999) + 54000;
}

+ (NSString *)md5:(NSString *)str
{
	const char *cstr = [(str) ? str : @"" cStringUsingEncoding:NSUTF8StringEncoding];
	unsigned char md5_result[CC_MD5_DIGEST_LENGTH];
	CC_MD5(cstr, strlen(cstr), md5_result);
	return [[NSString stringWithFormat: @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
			 md5_result[0], md5_result[1],
			 md5_result[2], md5_result[3],
			 md5_result[4], md5_result[5],
			 md5_result[6], md5_result[7],
			 md5_result[8], md5_result[9],
			 md5_result[10], md5_result[11],
			 md5_result[12], md5_result[13],
			 md5_result[14], md5_result[15]] lowercaseString];
}

- (void)dealloc
{
    DLog(@"dealloc");
    [self cancelDownload];
    if ([self isRunning]) DLog(@"Stopping server running on port %d",[self listeningPort]);
    [self stop:NO];
    _delegate = nil;
	docIntController.delegate = nil;
    docIntController = nil;
    servers = nil;
    if (clientActive > 0)
    {
        DLog(@"Stopping client background task %d",clientActive);
        [[UIApplication sharedApplication] endBackgroundTask:clientActive];
        clientActive = 0;
    }
    if (sharingQueue)
    {
        dispatch_release(sharingQueue);
        sharingQueue = nil;
    }
    sharing = nil;
    DLog(@"dealloc'ed");
}

- (id)init
{
    self = [super init];
    if (self)
    {
        _delegate = nil;
        docIntController = [[UIDocumentInteractionController alloc] init];
        [docIntController setDelegate:self];
        [docIntController setUTI:@"com.2ndnature.filexchange"];
        sharing = [[NSMutableDictionary alloc] initWithCapacity:1];
        servers = [[NSMutableDictionary alloc] initWithCapacity:1];
        sharingQueue = dispatch_queue_create("com.2ndnature.FileXchangeSharingQueue", NULL);
        fileDownloadConnection = nil;
        fileDownloadHandle = nil;
        _includeUniqueFileID = YES;
    }
    return self;
}

#pragma - Helper methods

- (UIImage *)appIconOfSize:(FileXchangeAppIconSize)iconSize
{
    UIImage *icon = nil;
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *filePath = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    CGFloat scale = 1.0;
    UIScreen *screen = [UIScreen mainScreen];
    if([screen respondsToSelector:@selector(scale)]) scale = screen.scale;
    if (iconSize == FileXchangeAppIconSizeSmall)
    {
        filePath = [mainBundle pathForResource:(scale > 1.0) ? @"Icon-Small@2x" : @"Icon-Small" ofType:@"png"];
        if ([fm fileExistsAtPath:filePath] == NO)
        {
            filePath = [mainBundle pathForResource:@"Icon-Small-50" ofType:@"png"];
        }
    }
    else // FileXchangeAppIconSizeLarge
    {
        filePath = [mainBundle pathForResource:(scale > 1.0) ? @"Icon@2x" : @"Icon" ofType:@"png"];
        if ([fm fileExistsAtPath:filePath] == NO)
        {
            filePath = [mainBundle pathForResource:@"Icon-72" ofType:@"png"];
        }
    }
    if (filePath != nil)
    {
        icon = [UIImage imageWithContentsOfFile:filePath];
        
        if ([[[mainBundle infoDictionary] objectForKey:@"UIPrerenderedIcon"] boolValue] == NO)
        {
            CGRect iconRect = CGRectMake(0.0, 0.0, icon.size.width * scale, icon.size.height * scale);
            UIImage *highlightImage = [UIImage imageWithData:[[@"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" dataUsingEncoding:NSUTF8StringEncoding] base64Decoded]];
            UIGraphicsBeginImageContext(iconRect.size);
            [icon drawInRect:iconRect];
            [highlightImage drawInRect:iconRect];
            icon = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
        
        UIImage *maskImage = [UIImage imageWithData:[[@"iVBORw0KGgoAAAANSUhEUgAAAJAAAACQCAIAAABoJHXvAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAzdJREFUeNrs2k9E+3Ecx/G1LyO+pBExpogvXcf4nkZERIwREbtGRKedolPETjGi04h1iU6jryVi107RNDF2mFjGN7FZvr37Lb/1z/ZdVn2+PB+nLi1eT9/v9/OdRhzH8Q2o1WpZ/5TL5VqtViqVHh4efHAhEonoum4YRiwWW1hYCAaDA3+E41qj0cjlcvF4XP4k0w/F/Px8Op2uVqvuK7gK9vj4KJ87NjbGxD9B07S1tbW7u7vhBMtms+FwmFl/mty3tre3bdv+frBKpWKaJlP+plAodHFx8Z1gp6en33kkYhh3yJ2dncGCHR4eBgIBtvtD6+vrboNJLfZSgZxE+gcrFApcW+rY2trqFUxOGTy3VHNycvJ1sHa7HY1GGUg1cgm9fbPuBstkMqyjpkQi8TGYvGZzM1RZPp9/FyyVSjGKykzT7AZrNBp8n6u+8/Pz12D7+/vMob7l5eXXYHxh6Amjo6NyL/TV63VN05jDE46Pj/1nZ2dPT09s4QmWZWlTU1PFYpEtPEGeX9r4+PjNzQ1beIJt25pEu7+/ZwtPaLVamjzAms0mWwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA+tJ1nRE8xB8MBlnBS8Gmp6dZwSsCgYDfMAyG8IqZmRm/aZoM4RWRSMRXqVQYwiuy2azPcZzZ2Vm2UJ+madVq1S8/raysMIf65ubmQqHQyxUm3aQeiygul8tJrJdgIplMsoji58N2u90Ndn19LWd8dlHWwcFBp9RrMJFKpdhFTdFotHN5vQtm23Y4HGYd1cid7/Ly8n+mbjBRLBa5Mapmd3f3baN3wUQmk2EjdcTj8Q+BPgbjYabUi1ez2ewfTGxubrLX34rFYnKq+Jzm62AinU7zNv1XEonE52urTzBRKBQmJyeZ75fPhHt7ez2i9Aom6vX6xsYGR8ffsbS0dHV11btIn2Adt7e3q6urDPqjr8byTuWmhatgHfL6JgdI/qVgiCYmJpLJZD6fd19h5CXagEql0tHRkWVZ5XK5Vqux+0B0XTcMQ47si4uLchQc9NefBRgAxML5kpjClZYAAAAASUVORK5CYII=" dataUsingEncoding:NSUTF8StringEncoding] base64Decoded]];
        CGImageRef maskRef = maskImage.CGImage;
        
        CGImageRef mask = CGImageMaskCreate(CGImageGetWidth(maskRef),
                                            CGImageGetHeight(maskRef),
                                            CGImageGetBitsPerComponent(maskRef),
                                            CGImageGetBitsPerPixel(maskRef),
                                            CGImageGetBytesPerRow(maskRef),
                                            CGImageGetDataProvider(maskRef), NULL, false);
        
        CGImageRef maskedImageRef = CGImageCreateWithMask([icon CGImage], mask);
        
        icon = [UIImage imageWithCGImage:maskedImageRef];
        
        CGImageRelease(mask);
        CGImageRelease(maskedImageRef);
    }
    return icon;
}

- (NSArray *)anonymizedFileInfoForFileAtPath:(NSString *)filePath fileAttributes:(NSDictionary *)fileAttribs suggestedFilename:(NSString *)filename userInfo:(id)userInfo
{
    return [[NSArray alloc] initWithObjects:(filename != nil) ? filename : [filePath lastPathComponent],
            [fileAttribs objectForKey:NSFileSize],
            [fileAttribs objectForKey:NSFileCreationDate],
            [fileAttribs objectForKey:NSFileModificationDate],
            (_includeUniqueFileID) ? [FileXchange md5:filePath] : @"",
            (userInfo != nil) ? userInfo : @"", nil];
}

#pragma mark - Server

- (void)startServer
{
    if ([self isRunning] == NO)
    {
        [self setConnectionClass:[FileXchangeConnection class]];
        
        do
        {
            [self setPort:[FileXchange randomPort]];
        }
        while ([self start:NULL] == NO);
        DLog(@"Server started on port %d",[self listeningPort]);
    }
}

- (NSURL *)prepareFiles:(NSArray *)files
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSString *exchangeFilename = nil;
    NSString *uuid = nil;
    do
    {
        uuid = [FileXchange generateUUID];
        exchangeFilename = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.fxch",uuid]];
    }
    while ([fileManager fileExistsAtPath:exchangeFilename]);
    
    NSMutableDictionary *payload = [[NSMutableDictionary alloc] initWithCapacity:([files isKindOfClass:[NSArray class]]) ? [files count] + 6 : 6];
    
    [payload setObject:[NSNumber numberWithFloat:FILEXCHANGE_VERSION] forKey:@"FileXchangeVersion"];
    [payload setObject:uuid forKey:@"UUID"];
    [payload setObject:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"] forKey:@"AppName"];
    NSData *appIcon = UIImagePNGRepresentation([self appIconOfSize:FileXchangeAppIconSizeSmall]);
    if (appIcon != nil)
    {
        [payload setObject:appIcon forKey:@"AppIconSmall"];
    }
    appIcon = UIImagePNGRepresentation([self appIconOfSize:FileXchangeAppIconSizeLarge]);
    if (appIcon != nil)
    {
        [payload setObject:appIcon forKey:@"AppIconLarge"];
    }
    
    if ([files isKindOfClass:[NSArray class]])
    {
        unsigned long long totalBytes = 0;
        NSMutableArray *filePaths = [[NSMutableArray alloc] initWithCapacity:[files count]];
        NSMutableArray *anonymizedFiles = [[NSMutableArray alloc] initWithCapacity:[files count]];

        for (int fileIndex = 0; fileIndex < [files count]; fileIndex++)
        {
            @autoreleasepool
            {
                NSString *filePath = [files objectAtIndex:fileIndex];
                NSString *suggestedFilename = nil;
                id userInfo = nil;
                if ([filePath isKindOfClass:[NSDictionary class]])
                {
                    suggestedFilename = [(NSDictionary *)filePath objectForKey:kFileXchangeSuggestedFilename];
                    userInfo = [(NSDictionary *)filePath objectForKey:kFileXchangeUserInfo];
                    filePath = [(NSDictionary *)filePath objectForKey:kFileXchangeFilePath];
                }
                if ([filePath isKindOfClass:[NSString class]])
                {
                    NSDictionary *fileAttribs = [fileManager attributesOfItemAtPath:filePath error:NULL];
                    if (fileAttribs != nil)
                    {
                        totalBytes += [[fileAttribs objectForKey:NSFileSize] unsignedLongLongValue];
                        [anonymizedFiles addObject:[self anonymizedFileInfoForFileAtPath:filePath fileAttributes:fileAttribs suggestedFilename:suggestedFilename userInfo:userInfo]];
                        [filePaths addObject:filePath];
                    }
                }
            }
        }
        [payload setObject:[NSNumber numberWithUnsignedLongLong:totalBytes] forKey:@"TotalNumberOfBytes"];
        [payload setObject:anonymizedFiles forKey:@"Files"];
        [payload setObject:filePaths forKey:@"FilePaths"];
    }
    
    if ([payload writeToFile:exchangeFilename atomically:YES] == NO)
    {
        DLog(@"Error. Couldn't write payload data");
        return nil;
    }
    
    return [[NSURL alloc] initFileURLWithPath:exchangeFilename isDirectory:NO];
}

- (BOOL)presentMenuFromBarButtonItem:(UIBarButtonItem *)buttonItem animated:(BOOL)animated servingFiles:(NSArray *)files
{
    BOOL success = NO;
    NSURL *exchangeURL = [self prepareFiles:files];
    if ([exchangeURL isKindOfClass:[NSURL class]])
    {
        [docIntController setURL:exchangeURL];
        success = [docIntController presentOpenInMenuFromBarButtonItem:buttonItem animated:animated];
        if (success == NO)
        {
            // Most likely, no apps support opening these UTIs
            [[NSFileManager defaultManager] removeItemAtURL:exchangeURL error:NULL];
        }
    }
    return success;
}

- (BOOL)presentMenuFromRect:(CGRect)aRect inView:(id)inView animated:(BOOL)animated servingFiles:(NSArray *)files
{
    BOOL success = NO;
    NSURL *exchangeURL = [self prepareFiles:files];
    if ([exchangeURL isKindOfClass:[NSURL class]])
    {
        [docIntController setURL:exchangeURL];
        success = [docIntController presentOpenInMenuFromRect:aRect inView:inView animated:animated];
        if (success == NO)
        {
            // Most likely, no apps support opening these UTIs
            [[NSFileManager defaultManager] removeItemAtURL:exchangeURL error:NULL];
        }
    }
    return success;
}

- (NSDictionary *)sharingInfo
{
    return [NSDictionary dictionaryWithDictionary:sharing];
}

- (void)addNewFiles:(NSArray *)files toShare:(NSMutableDictionary *)sharingData
{
 	NSAssert(dispatch_get_current_queue() == sharingQueue, @"addNewFiles:toShare: must be called on the sharingQueue.");
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
        
    NSMutableArray *currentlySharedFiles = [sharingData objectForKey:@"Files"];
    NSMutableArray *filesWaitingToBeSent = [sharingData objectForKey:@"NewFiles"];
    if ([filesWaitingToBeSent isKindOfClass:[NSMutableArray class]] == NO)
    {
        filesWaitingToBeSent = [[NSMutableArray alloc] initWithCapacity:[files count]];
    }
    unsigned long long totalBytes = [[sharingData objectForKey:@"TotalNumberOfBytes"] unsignedLongLongValue];
    
    for (int fileIndex = 0; fileIndex < [files count]; fileIndex++)
    {
        @autoreleasepool
        {
            NSString *filePath = [files objectAtIndex:fileIndex];
            NSString *suggestedFilename = nil;
            id userInfo = nil;
            if ([filePath isKindOfClass:[NSDictionary class]])
            {
                suggestedFilename = [(NSDictionary *)filePath objectForKey:kFileXchangeSuggestedFilename];
                userInfo = [(NSDictionary *)filePath objectForKey:kFileXchangeUserInfo];
                filePath = [(NSDictionary *)filePath objectForKey:kFileXchangeFilePath];
            }
            if ([filePath isKindOfClass:[NSString class]])
            {
                NSDictionary *fileAttribs = [fileManager attributesOfItemAtPath:filePath error:NULL];
                if (fileAttribs != nil)
                {
                    totalBytes += [[fileAttribs objectForKey:NSFileSize] unsignedLongLongValue];
                    [filesWaitingToBeSent addObject:[self anonymizedFileInfoForFileAtPath:filePath fileAttributes:fileAttribs suggestedFilename:suggestedFilename userInfo:userInfo]];
                    [currentlySharedFiles addObject:filePath];
                }
            }
        }
    }
    [sharingData setObject:[NSNumber numberWithUnsignedLongLong:totalBytes] forKey:@"TotalNumberOfBytes"];
    [sharingData setObject:filesWaitingToBeSent forKey:@"NewFiles"];
}

- (BOOL)addNewFiles:(NSArray *)files andNotifyApplication:(NSString *)application
{
    if ([files isKindOfClass:[NSArray class]] == NO) return NO;
    
    if ([application isKindOfClass:[NSString class]] == NO) return NO;
    
    __block NSMutableDictionary *sharingDataBackup = nil;
    __block NSString *reqString = nil;
    __block BOOL notificationDelivered = NO;
    
    dispatch_sync(sharingQueue, ^{
        
        NSMutableDictionary *sharingData = [sharing objectForKey:application];
        
        if ([sharingData isKindOfClass:[NSMutableDictionary class]])
        {
            sharingDataBackup = [sharingData mutableCopy];
            [self addNewFiles:files toShare:sharingData];
        }
        
        reqString = [NSString stringWithFormat:@"http://localhost:%d/update?app=%@",[[sharingData objectForKey:@"RemotePort"] unsignedShortValue],[[NSBundle mainBundle] bundleIdentifier]];
    });
    
    // We're splitting up the dispatch calls because the client will needs to get
    // the update info via our newFilesForApplication: method, which has a
    // dispatch_sync() call on the sharingQueue.
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        NSString *reply = [[NSString alloc] initWithData:[NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:reqString]
                                                                                                                  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                                                                              timeoutInterval:2.0] returningResponse:NULL error:NULL] encoding:NSUTF8StringEncoding];
        notificationDelivered = [reply isEqualToString:@"OK"];
        
    });
    
    if (notificationDelivered == NO && sharingDataBackup != nil)
    {
        dispatch_sync(sharingQueue, ^{
            
            [sharing setObject:sharingDataBackup forKey:application];
            
        });
    }
    
    return notificationDelivered;
}

- (void)startServing:(NSURL *)url toApplication:(NSString *)application
{
    if ([application isKindOfClass:[NSString class]] == NO) return;
    if ([application length] <= 0) return;
    
    DLog(@"startServing: %@ toApplication %@",[url lastPathComponent],application);
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkPulse) object:nil];
    
    dispatch_sync(sharingQueue, ^{
        
        NSMutableDictionary *connectionInfo = [[NSMutableDictionary alloc] initWithContentsOfURL:url];
        
        NSArray *files = [connectionInfo objectForKey:@"FilePaths"];
        [connectionInfo removeObjectForKey:@"FilePaths"];
        
        NSMutableDictionary *sharingInfo = [sharing objectForKey:application];

        if ([sharingInfo isKindOfClass:[NSMutableDictionary class]] && [self ping:application])
        {
            // Already sharing
            DLog(@"Already sharing, adding to share.");
            [connectionInfo writeToURL:url atomically:YES];
            [self addNewFiles:files toShare:sharingInfo];
        }
        else
        {
            UIBackgroundTaskIdentifier bgTId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{}];
            DLog(@"Starting server background task %d",bgTId);
            [connectionInfo setObject:[NSNumber numberWithUnsignedInteger:bgTId] forKey:@"BackgroundTaskIdentifier"];
            
            [self startServer];
            
            [connectionInfo setObject:[NSNumber numberWithUnsignedShort:[self listeningPort]] forKey:@"Port"];
            [connectionInfo writeToURL:url atomically:YES];
            
            [connectionInfo setObject:files forKey:@"Files"];
            files = nil;
            [sharing setObject:connectionInfo forKey:application];
        }
        
    });
    
    [self performSelector:@selector(checkPulse) withObject:nil afterDelay:PULSE_INTERVAL];
}

- (BOOL)ping:(NSString *)application
{
 	NSAssert(dispatch_get_current_queue() == sharingQueue, @"ping: must be called on the sharingQueue.");
    
    NSMutableDictionary *sharingInfo = [sharing objectForKey:application];
    
    unsigned short remotePort = [[sharingInfo objectForKey:@"RemotePort"] unsignedShortValue];
    
    BOOL pong = NO;
    
    if (remotePort > 0)
    {
        NSString *reply = [[NSString alloc] initWithData:[NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%d/ping",remotePort]]
                                                                                                                  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                                                                              timeoutInterval:10.0] returningResponse:NULL error:NULL] encoding:NSUTF8StringEncoding];
        pong = [reply isEqualToString:@"pong"];
    }
    
    if (pong == NO)
    {
        DLog(@"No answer from %@ on port %d.",application,remotePort);
        
        [sharing removeObjectForKey:application];
        
        NSNumber *backgroundTaskIdentifier = [sharingInfo objectForKey:@"BackgroundTaskIdentifier"];
        if ([backgroundTaskIdentifier isKindOfClass:[NSNumber class]])
        {
            UIBackgroundTaskIdentifier bgTId = [backgroundTaskIdentifier unsignedIntegerValue];
            DLog(@"Stopping server background task %d for %@",bgTId,application);
            [[UIApplication sharedApplication] endBackgroundTask:bgTId];
        }
        
        if ([sharing count] == 0)
        {
            DLog(@"No clients. Turning off server on port %d.",[self listeningPort]);
            [self stop:NO];
        }
        
        if ([_delegate respondsToSelector:@selector(fileXchange:applicationDidCloseConnection:)])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [_delegate fileXchange:self applicationDidCloseConnection:application];
                
            });
        }
    }
    
    return pong;
}

- (void)checkPulse
{
    __block BOOL living = NO;
    
    dispatch_sync(sharingQueue, ^{
        
        for (NSString *application in sharing)
        {
            DLog(@"Checking pulse on %@",application);
            if ([self ping:application])
            {
                living = YES;
            }
        }
        
    });
    
    if (living)
    {
        DLog(@"It's aliiive. Will check again in %1.0f seconds",PULSE_INTERVAL);
        [self performSelector:@selector(checkPulse) withObject:nil afterDelay:PULSE_INTERVAL];
    }
}

- (void)deliveryCheck:(NSString *)application
{
    if (transit)
    {
        DLog(@"Error. Application %@ is not receiving the payload.",application);
        transit = NO;
        if ([_delegate respondsToSelector:@selector(fileXchange:application:didFailWithError:)])
        {
            NSError *error = [NSError errorWithDomain:@"" code:504 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Target application is not responding.",@""),NSLocalizedDescriptionKey,nil]];
            [_delegate fileXchange:self application:application didFailWithError:error];
        }
    }
}

#pragma mark - FileXchangeConnection Server Methods

- (void)requestStart:(NSString *)application uuid:(NSString *)uuid port:(NSUInteger)remotePort
{
    DLog(@"Client %@ is alive on port %d",application,remotePort);
    
    if (remotePort <= 0) return;
    
    dispatch_async(sharingQueue, ^{
        
        if ([[[sharing objectForKey:application] objectForKey:@"UUID"] isEqualToString:uuid])
        {
            [[sharing objectForKey:application] setObject:[NSNumber numberWithUnsignedInteger:remotePort] forKey:@"RemotePort"];
        }
        
        if ([_delegate respondsToSelector:@selector(fileXchange:applicationDidAcceptSharing:)])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [_delegate fileXchange:self applicationDidAcceptSharing:application];
                
            });
        }
        
    });
}

- (NSString *)pathForFileAtIndex:(NSUInteger)fileNo application:(NSString *)application
{
    __block NSString *fullPath = nil;
    
    dispatch_sync(sharingQueue, ^{
        
        NSArray *files = [[sharing objectForKey:application] objectForKey:@"Files"];
        if (fileNo < [files count])
        {
            fullPath = [files objectAtIndex:fileNo];
        }
        
    });
    return fullPath;
}

- (NSArray *)newFilesForApplication:(NSString *)application
{
    if ([application isKindOfClass:[NSString class]] == NO) return nil;
    
    __block NSArray *result = nil;
    
    dispatch_sync(sharingQueue, ^{
        
        NSMutableDictionary *connectionInfo = [sharing objectForKey:application];
        result = [connectionInfo objectForKey:@"NewFiles"];
        [connectionInfo removeObjectForKey:@"NewFiles"];
        
    });
    
    DLog(@"new files: %@",[result description]);
    
    return result;
}


#pragma mark - Client

- (id)initWithDelegate:(id<FileXchangeDelegate>)aDelegate;
{
    self = [self init];
    if (self)
    {
        _delegate = aDelegate;
    }
    return self;
}


- (void)addFileXchangeData:(NSDictionary *)feData forApplication:(NSString *)application
{
    if ([feData isKindOfClass:[NSDictionary class]])
    {
        if (clientActive <= 0)
        {
            clientActive = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{}];
            DLog(@"Starting client background task %d",clientActive);
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            NSArray *newFiles = [feData objectForKey:@"Files"];
            
            NSMutableDictionary *existingData = [servers objectForKey:application];
            if ([existingData isKindOfClass:[NSMutableDictionary class]])
            {
                if ([[feData objectForKey:@"Port"] unsignedShortValue] == [[existingData objectForKey:@"Port"] unsignedShortValue])
                {
                    if ([newFiles count] > 0)
                    {
                        dispatch_sync(sharingQueue, ^{
                            
                            NSMutableArray *files = [existingData objectForKey:@"Files"];
                            NSRange range = NSMakeRange([files count], [newFiles count]);
                            [files addObjectsFromArray:newFiles];
                            
                            if ([_delegate respondsToSelector:@selector(fileXchange:application:newFilesAdded:)])
                            {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    
                                    [_delegate fileXchange:self application:application newFilesAdded:range];
                                    
                                });
                            }
                            
                        });
                    }
                    return;
                }
                DLog(@"Port has changed. Reboot the server. Stopping server that is currently running on port %d",[self listeningPort]);
                [self stop:NO];
            }
            
            [servers setObject:[feData mutableCopy] forKey:application];
            
            [self startServer]; // Well... "startClient" would be a better description.
            
            NSData *replyData = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%d/connection?begin=%@&port=%d&app=%@",[[feData objectForKey:@"Port"] unsignedShortValue],[feData objectForKey:@"UUID"],[self listeningPort],[[NSBundle mainBundle] bundleIdentifier]]]
                                                                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                                                     timeoutInterval:10.0] returningResponse:NULL error:NULL];
            DLog(@"Engage with %@. Reply: %@",application,[[NSString alloc] initWithData:replyData encoding:NSUTF8StringEncoding]);
            replyData = nil;
            
            if ([newFiles count] > 0)
            {
                if ([_delegate respondsToSelector:@selector(fileXchange:application:newFilesAdded:)])
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        [_delegate fileXchange:self application:application newFilesAdded:NSMakeRange(0, [newFiles count])];
                        
                    });
                }
            }
            
        });
    }
}

- (NSDictionary *)fileXchangeDataForApplication:(NSString *)application
{
    return [servers objectForKey:application];
}

- (NSURLRequest *)requestForFileAtIndex:(NSUInteger)index fromApplication:(NSString *)application
{
    NSDictionary *fileExhangeData = [self fileXchangeDataForApplication:application];
    NSString *urlStr = [NSString stringWithFormat:@"http://localhost:%d/file?idx=%d&app=%@",[[fileExhangeData objectForKey:@"Port"] unsignedShortValue],index,[[NSBundle mainBundle] bundleIdentifier]];
    // DLog(@"req: %@",urlStr);
    return [NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]
                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                        timeoutInterval:10.0];
}

- (NSData *)synchronouslyDownloadFileAtIndex:(NSUInteger)index fromApplication:(NSString *)application returningResponse:(NSURLResponse **)response error:(NSError **)error
{
    NSDictionary *fileExhangeData = [self fileXchangeDataForApplication:application];
    if ([fileExhangeData isKindOfClass:[NSDictionary class]] == NO)
    {
        DLog(@"Error. Don't know anything about application %@",application);
        return nil;
    }
    
    __block NSUInteger currentNumberOfFiles = 0;
    
    dispatch_sync(sharingQueue, ^{
        
        NSArray *files = [fileExhangeData objectForKey:@"Files"];
        currentNumberOfFiles = [files count];
        
    });
    
    if (index >= currentNumberOfFiles)
    {
        DLog(@"Error. Invalid index %d. We only have %d file%@.",index,currentNumberOfFiles,(currentNumberOfFiles == 1) ? @"" : @"s");
        return nil;
    }
    
    NSData *data = [NSURLConnection sendSynchronousRequest:[self requestForFileAtIndex:index fromApplication:application] returningResponse:response error:error];
    
    if (data == nil)
    {
        DLog(@"No reply.");
    }
    
    return data;
}

- (NSArray *)infoForFileAtIndex:(NSUInteger)index fromApplication:(NSString *)application
{
    NSDictionary *fileExhangeData = [self fileXchangeDataForApplication:application];
    
    __block NSArray *remoteFileInfo = nil;
    
    dispatch_sync(sharingQueue, ^{
        
        NSArray *files = [fileExhangeData objectForKey:@"Files"];
        if ([files isKindOfClass:[NSArray class]] && index < [files count])
        {
            remoteFileInfo = [files objectAtIndex:index];
            if ([remoteFileInfo isKindOfClass:[NSArray class]] == NO)
            {
                remoteFileInfo = nil;
            }
        }
        
    });
    
    return remoteFileInfo;
}

- (BOOL)updateFileAttributesOnFile:(NSString *)filePath fromFileAtIndex:(NSUInteger)index fromApplication:(NSString *)application
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath] == NO)
    {
        DLog(@"Error. Couldn't set file attributes. The file %@ does not exist.",filePath);
        return NO;
    }
    
    NSDictionary *fileAttribs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:NULL];
    if ([fileAttribs isKindOfClass:[NSDictionary class]] == NO)
    {
        DLog(@"Error. Failed to get file attributes for file %@.",filePath);
        return NO;
    }
    
    NSArray *remoteFileInfo = [self infoForFileAtIndex:index fromApplication:application];
    if ([remoteFileInfo count] < 4)
    {
        if ([_delegate respondsToSelector:@selector(fileXchange:application:didFailWithError:)])
        {
            NSError *error = [NSError errorWithDomain:@"" code:417 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Invalid file information retrieved.",@""),NSLocalizedDescriptionKey,nil]];
            [_delegate fileXchange:self application:fileDownloadApplication didFailWithError:error];
        }
        DLog(@"Error. Invalid file information retrieved: %@",[remoteFileInfo description]);
        return NO;
    }
    
    NSMutableDictionary *newAttribs = [[NSMutableDictionary alloc] initWithDictionary:fileAttribs];
    [newAttribs setObject:[remoteFileInfo objectAtIndex:2] forKey:NSFileCreationDate];
    [newAttribs setObject:[remoteFileInfo objectAtIndex:3] forKey:NSFileModificationDate];
    
    BOOL success = [[NSFileManager defaultManager] setAttributes:newAttribs ofItemAtPath:filePath error:NULL];
    
    if (success == NO)
    {
        DLog(@"Error. Failed to set file attributes for file %@.",filePath);
    }
    
    return success;
}

- (void)downloadFileAtIndex:(NSUInteger)index fromApplication:(NSString *)application toFolder:(NSString *)destinationFolder
{
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:destinationFolder isDirectory:&isDir] == NO || isDir == NO)
    {
        DLog(@"Error. Destination folder does not exist.");
        return;
    }
    
    NSArray *remoteFileInfo = [self infoForFileAtIndex:index fromApplication:application];
    if ([remoteFileInfo count] < 4)
    {
        if ([_delegate respondsToSelector:@selector(fileXchange:application:didFailWithError:)])
        {
            NSError *error = [NSError errorWithDomain:@"" code:417 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Invalid file information retrieved.",@""),NSLocalizedDescriptionKey,nil]];
            [_delegate fileXchange:self application:fileDownloadApplication didFailWithError:error];
        }
        DLog(@"Error. Invalid file information retrieved: %@",[remoteFileInfo description]);
        return;
    }
    
    if (fileDownloadHandle != nil)
    {
        DLog(@"Error. Already downloading.");
        return;
    }

    fileDownloadFilePath = [destinationFolder stringByAppendingPathComponent:[remoteFileInfo objectAtIndex:0]];
    if ([@"" writeToFile:fileDownloadFilePath atomically:YES encoding:NSUTF8StringEncoding error:NULL] == NO)
    {
        DLog(@"Error. Couldn't write new file %@",fileDownloadFilePath);
        fileDownloadFilePath = nil;
        return;
    }
    fileDownloadApplication = [application copy];
    
    fileDownloadHandle = [NSFileHandle fileHandleForWritingAtPath:fileDownloadFilePath];
    [fileDownloadHandle seekToEndOfFile];
    
    fileDownloadIndex = index;
    bytesTransferred = 0;
    totalNumberOfBytes = [[remoteFileInfo objectAtIndex:1] integerValue];
    fileDownloadConnection = [NSURLConnection connectionWithRequest:[self requestForFileAtIndex:index fromApplication:application] delegate:self];
}

- (void)downloadDone
{
    fileDownloadConnection = nil;
    fileDownloadFilePath = nil;
    fileDownloadApplication = nil;
    fileDownloadConnection = nil;
    fileDownloadHandle = nil;
    bytesTransferred = 0;
    totalNumberOfBytes = 0;
    fileDownloadIndex = NSNotFound;
}

- (void)cancelDownload
{
    if (fileDownloadConnection != nil)
    {
        [fileDownloadConnection cancel];
    }
    [fileDownloadHandle closeFile];
    [[NSFileManager defaultManager] removeItemAtPath:fileDownloadFilePath error:NULL];
    [self downloadDone];
}

- (BOOL)synchronouslyDownloadFileAtIndex:(NSUInteger)index fromApplication:(NSString *)application toFolder:(NSString *)destinationFolder
{
    @autoreleasepool
    {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:destinationFolder isDirectory:&isDir] == NO || isDir == NO)
        {
            DLog(@"Error. Destination folder does not exist.");
            return NO;
        }
        
        NSArray *remoteFileInfo = [self infoForFileAtIndex:index fromApplication:application];
        if ([remoteFileInfo count] < 4)
        {
            if ([_delegate respondsToSelector:@selector(fileXchange:application:didFailWithError:)])
            {
                NSError *error = [NSError errorWithDomain:@"" code:417 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Invalid file information retrieved.",@""),NSLocalizedDescriptionKey,nil]];
                if ([NSThread isMainThread])
                {
                    [_delegate fileXchange:self application:application didFailWithError:error];
                }
                else
                {
                    NSString *theApplication = [application copy];
                    NSError *theError = [error copy];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [_delegate fileXchange:self application:theApplication didFailWithError:theError];
                    });
                }
            }
            DLog(@"Error. Invalid file information retrieved: %@",[remoteFileInfo description]);
            return NO;
        }
        
        NSData *data = [self synchronouslyDownloadFileAtIndex:index fromApplication:application returningResponse:NULL error:NULL];
        if (data == nil)
        {
            DLog(@"Error. No data downloaded.");
            return NO;
        }
        
        NSString *targetFile = [destinationFolder stringByAppendingPathComponent:[remoteFileInfo objectAtIndex:0]];
        if ([data writeToFile:targetFile atomically:YES] == NO)
        {
            DLog(@"Error. Failed to save the file %@",targetFile);
            return NO;
        }
        
        BOOL successfulUpdate = [self updateFileAttributesOnFile:targetFile fromFileAtIndex:index fromApplication:application];
        
        if ([_delegate respondsToSelector:@selector(fileXchange:application:didFinishDownload:userInfo:)])
        {
            NSArray *fileAttributes = [self infoForFileAtIndex:index fromApplication:application];
            id userInfo = ([fileAttributes count] > 4) ? [fileAttributes objectAtIndex:5] : nil;
            if ([NSThread isMainThread])
            {
                [_delegate fileXchange:self application:application didFinishDownload:targetFile userInfo:userInfo];
            }
            else
            {
                NSString *theFilename = [targetFile copy];
                NSString *theApplication = [application copy];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_delegate fileXchange:self application:theApplication didFinishDownload:theFilename userInfo:userInfo];
                });
            }
        }
        
        return successfulUpdate;
    }
}


#pragma mark - FileXchangeConnection Client Methods

- (BOOL)getUpdatesFromApplication:(NSString *)application
{
    NSDictionary *fileExhangeData = [self fileXchangeDataForApplication:application];
    if (fileExhangeData == nil) return NO;
    
    unsigned short remotePort = [[fileExhangeData objectForKey:@"Port"] unsignedShortValue];
    if (remotePort == 0) return NO;
    
    NSString *str = [NSString stringWithFormat:@"http://localhost:%d/newfiles?app=%@",remotePort,[[NSBundle mainBundle] bundleIdentifier]];
    
    NSArray *newFiles = [[NSArray alloc] initWithContentsOfURL:[NSURL URLWithString:str]];
    
    if ([newFiles count] > 0)
    {
        NSDictionary *fileExhangeData = [self fileXchangeDataForApplication:application];
        
        dispatch_sync(sharingQueue, ^{
            
            NSMutableArray *files = [fileExhangeData objectForKey:@"Files"];
            NSRange range = NSMakeRange([files count], [newFiles count]);
            [files addObjectsFromArray:newFiles];
            
            if ([_delegate respondsToSelector:@selector(fileXchange:application:newFilesAdded:)])
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    [_delegate fileXchange:self application:application newFilesAdded:range];
                    
                });
            }
            
        });
    }
    
    return (newFiles != nil);
}


#pragma mark - NSURLConnection callbacks for Runloop downloads

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    bytesTransferred += [data length];
    [fileDownloadHandle writeData:data];
    
    if ([_delegate respondsToSelector:@selector(fileXchange:application:downloadedBytes:soFar:totalBytes:)])
    {
        [_delegate fileXchange:self application:fileDownloadApplication downloadedBytes:[data length] soFar:bytesTransferred totalBytes:totalNumberOfBytes];
    }
    
    if (bytesTransferred >= totalNumberOfBytes)
    {
        [fileDownloadHandle closeFile];
        [self updateFileAttributesOnFile:fileDownloadFilePath fromFileAtIndex:fileDownloadIndex fromApplication:fileDownloadApplication];
        
        NSString *filename = [fileDownloadFilePath copy];
        NSString *application = [fileDownloadApplication copy];
        [self downloadDone];
        
        if ([_delegate respondsToSelector:@selector(fileXchange:application:didFinishDownload:userInfo:)])
        {
            NSArray *fileAttributes = [self infoForFileAtIndex:index fromApplication:application];
            id userInfo = ([fileAttributes count] > 4) ? [fileAttributes objectAtIndex:5] : nil;
            [_delegate fileXchange:self application:application didFinishDownload:filename userInfo:userInfo];
        }
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    if ([_delegate respondsToSelector:@selector(fileXchange:application:didFailWithError:)])
    {
        [_delegate fileXchange:self application:fileDownloadApplication didFailWithError:error];
    }
    [self cancelDownload];
}


#pragma mark - UIDocumentInteractionControllerDelegate

- (void)documentInteractionController:(UIDocumentInteractionController *)controller willBeginSendingToApplication:(NSString *)application
{
    transit = YES;
    [self startServing:[controller URL] toApplication:application];
    [self performSelector:@selector(deliveryCheck:) withObject:application afterDelay:5.0];
}

- (void)documentInteractionControllerDidDismissOpenInMenu: (UIDocumentInteractionController *) controller
{
    [[NSFileManager defaultManager] removeItemAtURL:[controller URL] error:NULL];
}

- (void)documentInteractionController:(UIDocumentInteractionController *)controller didEndSendingToApplication:(NSString *)application
{
    transit = NO;
}

@end

#pragma mark - FileXchangeConnection

@implementation FileXchangeConnection

- (NSObject<HTTPResponse> *)httpResponseForMethod:(NSString *)method URI:(NSString *)path
{
    if ([path isEqualToString:@"/ping"])
    {
        DLog(@"Pong");
        return [[HTTPDataResponse alloc] initWithData:[@"pong" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    NSArray *split = [path componentsSeparatedByString:@"?"];
    
    if ([split count] == 2)
    {
        NSArray *elements = [[split objectAtIndex:1] componentsSeparatedByString:@"&"];
        NSMutableDictionary *parms = [[NSMutableDictionary alloc] initWithCapacity:[elements count]];
        
        for (NSString *element in elements)
        {
            NSArray *xplosivo = [element componentsSeparatedByString:@"="];
            if ([xplosivo count] == 2)
            {
                [parms setObject:[xplosivo objectAtIndex:1] forKey:[xplosivo objectAtIndex:0]];
            }
        }
        
        
        if ([[split objectAtIndex:0] isEqualToString:@"/connection"])
        {
            // Client asking to end or begin a new connection
            if ([parms objectForKey:@"begin"])
            {
                unsigned short remotePort = [[parms objectForKey:@"port"] integerValue];
                if (remotePort > 0)
                {
                    [(FileXchange *)config.server requestStart:[parms objectForKey:@"app"] uuid:[parms objectForKey:@"begin"] port:remotePort];
                    return [[HTTPDataResponse alloc] initWithData:[@"OK" dataUsingEncoding:NSUTF8StringEncoding]];
                }
            }
        }
        
        
        else if ([[split objectAtIndex:0] isEqualToString:@"/file"])
        {
            // Client asking server for a file
            if ([parms objectForKey:@"idx"])
            {
                NSString *fullPath = [(FileXchange *)config.server pathForFileAtIndex:[[parms objectForKey:@"idx"] integerValue] application:[parms objectForKey:@"app"]];
                if ([fullPath isKindOfClass:[NSString class]])
                {
                    DLog(@"Sending %@",[fullPath lastPathComponent]);
                    return [[HTTPFileResponse alloc] initWithFilePath:fullPath forConnection:self];
                }
            }
        }
        
        
        else if ([[split objectAtIndex:0] isEqualToString:@"/update"])
        {
            // Server notifying the client that it should update.
            if ([(FileXchange *)config.server getUpdatesFromApplication:[parms objectForKey:@"app"]])
            {
                return [[HTTPDataResponse alloc] initWithData:[@"OK" dataUsingEncoding:NSUTF8StringEncoding]];
            }
        }
        
        
        else if ([[split objectAtIndex:0] isEqualToString:@"/newfiles"])
        {
            // Client asking for list of new files
            NSArray *newFiles = [(FileXchange *)config.server newFilesForApplication:[parms objectForKey:@"app"]];
            if ([newFiles isKindOfClass:[NSArray class]])
            {
                NSString *tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:[FileXchange generateUUID]];
                [newFiles writeToFile:tempFile atomically:YES];
                NSData *data = [[NSData alloc] initWithContentsOfFile:tempFile];
                [[NSFileManager defaultManager] removeItemAtPath:tempFile error:NULL];
                if ([data isKindOfClass:[NSData class]]) return [[HTTPDataResponse alloc] initWithData:data];
            }
        }
    }
    
	return [[HTTPDataResponse alloc] initWithData:[[NSMutableData alloc] initWithLength:0]];
}

@end