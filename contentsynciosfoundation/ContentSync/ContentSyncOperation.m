//
//  ContentSyncOperation.m
//  ToloApp
//
//  Created by Torey Lomenda on 7/18/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#include <SystemConfiguration/SystemConfiguration.h>
#include <MobileCoreServices/MobileCoreServices.h>

#import "ContentSyncOperation.h"
#import "ContentSyncManager.h"

#import "AlertUtils.h"

#import "Reachability.h"
#import "AFNetworking.h"

@interface ContentSyncOperation()

- (ContentMetaData *) appContentMetaData;
- (ContentMetaData *) webContentMetaDataWithStatus:(NSInteger *)status;
- (NSString *) webContentStructureDataWithStatus:(NSInteger *)status;

- (void) downloadChanges: (ContentSyncManager *) syncMgr;
- (BOOL) fetchAndSaveContentItem: (ContentItem *) itemToDownload withFileMgr: (NSFileManager *) fileMgr;

@end
@implementation ContentSyncOperation
@synthesize downloadTotalBytes;
@synthesize downloadBytesRead;

#pragma mark - MAIN
- (void) main {
    // Need to create an auto release pool for the operation
    @autoreleasepool {
    
    // Initialize state variables
        self.downloadTotalBytes = 0;
        self.downloadBytesRead = 0;
        
        // Get the Content Sync Manager instance
        ContentSyncManager *syncManager = [ContentSyncManager sharedInstance];
        SyncCompletionStatus syncStatus = SYNC_STATUS_OK;
        
        // Is the sync already in progress from a previous start of the app or is it new or needs to be retried
        if (![syncManager.syncActions hasItemsForAppToApply] || (syncManager.downloadErrorList && [syncManager.downloadErrorList count] > 0)) {
            
            // Let us make sure the sync actions are reset
            [syncManager.downloadErrorList removeAllObjects];
            [syncManager.syncActions clearSyncActions];
            
            // Get the current Contents Metadata and download the latest from the Web Folder
            ContentMetaData *appMetaData = [self appContentMetaData];
            NSInteger metadataStatusCode;
            NSInteger structureStatusCode;
            ContentMetaData *webMetaData = [self webContentMetaDataWithStatus:&metadataStatusCode];
            NSString *contentStructureData = [self webContentStructureDataWithStatus:&structureStatusCode];
            
            if (appMetaData && webMetaData && contentStructureData) {
                [syncManager.syncActions determineSyncActions:appMetaData updatedContentMetaData:webMetaData compareStructureData:YES];
            } else if (metadataStatusCode == 401 || structureStatusCode == 401) {
                syncStatus = SYNC_AUTHORIZATION_FAILED;
            } else {
                syncStatus = SYNC_STATUS_FAILED;
            }
        }
        
        // Notify delegates of the sync actions being initialized
        dispatch_sync(dispatch_get_main_queue(), ^{
            [syncManager notifyDelegatesOfSyncActions];
        });
        
        // Download any files that need to be added or modified in the app (start a background task)
        // Prevent the iPad from locking while the app is downloading changes.
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        [self downloadChanges:syncManager];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        // The sync is now complete
        dispatch_sync(dispatch_get_main_queue(), ^{
            [syncManager notifyDelegatesOfSyncComplete: syncStatus];
        });
    
    }
}

#pragma mark - Public Methods
- (float) downloadProgress {
    return self.downloadBytesRead / self.downloadTotalBytes;
}

#pragma mark -
#pragma mark Private Methods
- (ContentMetaData *) appContentMetaData {
    ContentMetaData *appContentMetadata = [[ContentSyncManager sharedInstance] getAppContentMetaData];
    return appContentMetadata;
}

- (ContentMetaData *) webContentMetaDataWithStatus:(NSInteger *)status {
    ContentMetaData *webContentMetadata = [[ContentSyncManager sharedInstance] getWebContentMetaDataWithStatus:status];
    return webContentMetadata;
}

- (NSString *) webContentStructureDataWithStatus:(NSInteger *)status {
    NSString *contentStructureData = [[ContentSyncManager sharedInstance] contentStructureDataJsonFromWebFolderWithStatus:status];
    return contentStructureData;
}

- (void) downloadChanges:(ContentSyncManager *) syncMgr {
    // Want this to run in the background if the app enters background
    UIApplication *theApp = [UIApplication sharedApplication];
    
    __block UIBackgroundTaskIdentifier bgTask = [theApp beginBackgroundTaskWithExpirationHandler:^(void) {
        [theApp endBackgroundTask: bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
    
    ContentSyncActions *syncActions = syncMgr.syncActions;
    NSArray *downloadItems = [NSArray arrayWithArray:syncActions.downloadItemsRemaining];
    
    if (downloadItems && [downloadItems count] > 0) {
        NSFileManager *fileMgr;
        @try {
            fileMgr = [[NSFileManager alloc] init];
            BOOL allDownloadsSuccessful = YES;
            
            for (ContentItem *itemToDownload in downloadItems) {
                
                // SMM: Special condition to skip content-structure.json if it is in the list.
                // We used to download the structure file like other data files by using an
                // entry in content-metadata.json but this did not work when we added multiple
                // catalog support.  There may be some conditions where the entry may still be
                // getting added to content-metadata if the CMS or database has not been updated
                // yet.  If this is the case, the following code will skip content-structure.json
                // if it is in the list.  We should be able to remove this after the CMS migration.
                if ([[itemToDownload.name lowercaseString] isEqualToString:@"content-structure.json"] == NO) {
                    if (![self fetchAndSaveContentItem:itemToDownload withFileMgr:fileMgr] && allDownloadsSuccessful) {
                        allDownloadsSuccessful = NO;
                    }
                }
                
                // Remove from the sync actions items to download and notify content sync manager delegates of progress
                [syncActions removeItemToDownload:itemToDownload];
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    [syncMgr notifyDelegatesOfSyncProgress:[syncActions totalItemsToApply] - [syncActions totalItemsToDownload]
                                              totalChanges:[syncActions totalItemsToApply]];
                });
            }
            
            if (!allDownloadsSuccessful) {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    [AlertUtils showModalAlertMessage:@"Some downloads failed.  Please retry updating again later." withTitle:[[ContentSyncManager sharedInstance] alertTitle]];
                });
            } else {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    [AlertUtils showModalAlertMessage:@"Downloads are complete.  Tap sync icon on products screen to apply changes." withTitle:[[ContentSyncManager sharedInstance] alertTitle]];
                });
            }
        }
        @finally {
            fileMgr = nil;
            fileMgr = nil;
        }
    }
    
    // End the background task
    [theApp endBackgroundTask: bgTask];
    bgTask = UIBackgroundTaskInvalid;
}

- (BOOL) fetchAndSaveContentItem:(ContentItem *)itemToDownload withFileMgr:(NSFileManager *)fileMgr {
    if (itemToDownload) {
        ContentSyncManager *syncManager = [ContentSyncManager sharedInstance];
        NSString *baseContentPath = [[ContentSyncManager sharedInstance] baseAppContentPath];
        NSRange pathStartRange = [itemToDownload.path rangeOfString:baseContentPath];
        
        // Reset download progress
        self.downloadTotalBytes = 0;
        self.downloadBytesRead = 0;
        
        if (pathStartRange.location != NSNotFound) {
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            NSString *cacheDirectory = [paths objectAtIndex:0];
            NSString *baseSyncPath = [[ContentSyncManager sharedInstance] baseSyncPath];
            
            NSString *savePath = [cacheDirectory
                                  stringByAppendingPathComponent:
                                  [baseSyncPath
                                   stringByAppendingPathComponent:itemToDownload.path]];
            
            // Only download the file if it is not already in the sync folder and their is a wifi connection
            // and the file sizes match
            if (![[ContentSyncManager sharedInstance] fileExists:savePath withFileMgr:fileMgr] ||
                [[ContentSyncManager sharedInstance] fileSize:savePath] != itemToDownload.fileSize) {
                Reachability *internetReach = [Reachability reachabilityForInternetConnection];
                
                if ([internetReach isReachableViaWiFi]) {
                    // Make sure the parent directory exists before downloading and saving the file
                    [[ContentSyncManager sharedInstance] createDirForFile:savePath withFileMgr:fileMgr];
                    
                    if ([itemToDownload isFile]) {
                        // TODO put comments back for these download messages
                        NSDate *startTime = [NSDate date];
                        NSLog(@"Content Sync Downloading: %@ to %@ with name %@ and size %li", itemToDownload.downloadUrl, itemToDownload.path, itemToDownload.name, (long)itemToDownload.fileSize);
                        NSURL *downloadUrl = [NSURL URLWithString:[itemToDownload.downloadUrl stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
                        NSURLRequest *request = [NSURLRequest requestWithURL:downloadUrl cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:120];
                        
                        // Do the AFNetworking Way
                        AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
                        @try {
                            operation.outputStream = [NSOutputStream outputStreamToFileAtPath:savePath append:NO];
                            
                            [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
                                // Nothing to do here, synchronous request.
                            } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                // Nothing to do here, synchronous request.
                            }];
                            
                            // Create Download Progress to track bytes read
                            [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
                                self.downloadBytesRead = (float) totalBytesRead;
                                self.downloadTotalBytes = (float) totalBytesExpectedToRead;
                            }];
                            
                            [operation start];
                            [operation waitUntilFinished];
                            
                            if ([operation.response statusCode] != 200) {
                                [fileMgr removeItemAtPath:savePath error:nil];
                                NSString *detailedError = [NSString stringWithFormat:@"Download error.  Status code '%ld' for name '%@' URL '%@'", (long)[operation.response statusCode], [itemToDownload name], downloadUrl];
                                NSLog(@"%@", detailedError);
                                
                                [syncManager addDownloadError:[itemToDownload name]];
                                [syncManager addDetailedDownloadError:detailedError];
                                return NO;
                            }
                            
                            // Check if the saved file is a 0 length file or if not a text file matches the
                            // actual size of the file.  If we get a -1, that means we were not sent
                            // a Content-Length Header and could not tell how much we were supposed to
                            // get.  Seems to happen for HTML files from the CMS.  Need to fix.  SMM
                            if (self.downloadTotalBytes != -1 && truncf(self.downloadBytesRead) != truncf(self.downloadTotalBytes)) {
                                [fileMgr removeItemAtPath:savePath error:nil];
                                NSString *detailedError = [NSString stringWithFormat:@"Download error.  Bytes read do not match total bytes expected (likely timeout or connection dropped) for name '%@' URL '%@', expected %f bytes, got %f bytes",[itemToDownload name], downloadUrl, truncf(self.downloadTotalBytes), truncf(self.downloadBytesRead)];
                                NSLog(@"%@", detailedError);
                                
                                [syncManager addDownloadError:[itemToDownload name]];
                                [syncManager addDetailedDownloadError:detailedError];
                                return NO;
                            }
                        }
                        @finally {
                            operation = nil;
                        }
                        
                        // TODO SMM - put comments back on these log messages for downloading
                        // Log end time
                        NSDate *endTime = [NSDate date];
                        NSTimeInterval difference = [endTime timeIntervalSinceDate:startTime];
                        NSLog(@"Download '%@' took '%f'", downloadUrl, difference);
                    }
                }
                else if ([internetReach isReachableViaWWAN]){
                    //3g only
                }
            }
        } else {
            NSLog(@"Invalid path: %@", itemToDownload.path);
            return NO;
        }
        
        return YES;
    }
    
    return NO;
}

@end
