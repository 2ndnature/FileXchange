//
//  FileXchange.h
//  FileXchange
//
//  Created by Brian Gerfort on 18/10/12.
//  Copyright (c) 2012 2ndNature. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HTTPServer.h"
#import "HTTPConnection.h"

extern NSString *const kFileXchangeFilePath;
extern NSString *const kFileXchangeSuggestedFilename;
extern NSString *const kFileXchangeUserInfo;

#define DEBUGGING 1

#if DEBUGGING
//#   define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#   define DLog(fmt, ...) NSLog((fmt), ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

enum {
	FileXchangeAppIconSizeSmall	= 0,
	FileXchangeAppIconSizeLarge	= 1
};
typedef NSInteger FileXchangeAppIconSize;

@protocol FileXchangeDelegate;

@interface FileXchange : HTTPServer

@property (assign) id<FileXchangeDelegate> delegate;
@property (assign) BOOL includeUniqueFileID;

- (UIImage *)appIconOfSize:(FileXchangeAppIconSize)iconSize;

#pragma mark - Server

- (BOOL)presentMenuFromRect:(CGRect)aRect inView:(id)inView animated:(BOOL)animated servingFiles:(NSArray *)files;
- (BOOL)presentMenuFromBarButtonItem:(UIBarButtonItem *)buttonItem animated:(BOOL)animated servingFiles:(NSArray *)files;

- (NSDictionary *)sharingInfo;
- (BOOL)addNewFiles:(NSArray *)files andNotifyApplication:(NSString *)application;

#pragma mark - Client

- (id)initWithDelegate:(id<FileXchangeDelegate>)aDelegate;
- (void)addFileXchangeData:(NSDictionary *)fileXchangeData forApplication:(NSString *)application;
- (NSDictionary *)fileXchangeDataForApplication:(NSString *)application;

- (void)downloadFileAtIndex:(NSUInteger)index fromApplication:(NSString *)application toFolder:(NSString *)destinationFolder;
- (void)cancelDownload;

- (BOOL)synchronouslyDownloadFileAtIndex:(NSUInteger)index fromApplication:(NSString *)application toFolder:(NSString *)destinationFolder;

@end

@interface FileXchangeConnection : HTTPConnection

@end


#pragma mark - Delegate

@protocol FileXchangeDelegate <NSObject>

@optional

- (void)fileXchange:(FileXchange *)fe applicationDidAcceptSharing:(NSString *)application;
- (void)fileXchange:(FileXchange *)fe applicationDidCloseConnection:(NSString *)application;
- (void)fileXchange:(FileXchange *)fe application:(NSString *)application downloadedBytes:(NSUInteger)bytes soFar:(NSUInteger)bytesSoFar totalBytes:(NSUInteger)totalBytes;
- (void)fileXchange:(FileXchange *)fe application:(NSString *)application didFinishDownload:(NSString *)filePath;
- (void)fileXchange:(FileXchange *)fe application:(NSString *)application didFailWithError:(NSError *)error;
- (void)fileXchange:(FileXchange *)fe application:(NSString *)application newFilesAdded:(NSRange)range;

@end

/*
 
 For new projects:
 
 1. Add the CFNetwork.framework and Security.framework.
 2. Add the CocoaHTTPServer Core and Vendor files.
 3. Add the FileXchange files.
 4. The receiving app needs these two keys in the Info.plist:
 
 <?xml version="1.0" encoding="UTF-8"?>
 <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
 <plist version="1.0">
 <array>
 <dict>
 <key>CFBundleTypeName</key>
 <string>FileXchange data</string>
 <key>CFBundleTypeRole</key>
 <string>Viewer</string>
 <key>LSHandlerRank</key>
 <string>Alternate</string>
 <key>LSItemContentTypes</key>
 <array>
 <string>com.2ndnature.FileXchange</string>
 </array>
 </dict>
 </array>
 </plist>
 
 <?xml version="1.0" encoding="UTF-8"?>
 <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
 <plist version="1.0">
 <array>
 <dict>
 <key>UTTypeConformsTo</key>
 <array>
 <string>public.data</string>
 </array>
 <key>UTTypeDescription</key>
 <string>FileXchange data</string>
 <key>UTTypeIdentifier</key>
 <string>com.2ndnature.FileXchange</string>
 <key>UTTypeTagSpecification</key>
 <dict>
 <key>public.filename-extension</key>
 <string>fxch</string>
 <key>public.mime-type</key>
 <string>application/xml</string>
 </dict>
 </dict>
 </array>
 </plist>
 
 */
