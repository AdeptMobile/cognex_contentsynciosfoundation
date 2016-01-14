//
//  ContentSyncManager.h
//  ToloApp
//
//  Created by Torey Lomenda on 6/22/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ContentSyncActions.h"
#import "ContentSyncConfig.h"

#import "InAppUpdater.h"

#define CONTENT_METADATA_FILENAME @"content-metadata.json"
#define CONTENT_STRUCTURE_FILENAME @"content-structure.json"

typedef enum {
    SYNC_STATUS_OK,
    SYNC_NO_WIFI,
    SYNC_STATUS_FAILED,
    SYNC_AUTHORIZATION_FAILED
} SyncCompletionStatus;

@protocol ContentUnpackDelegate;
@protocol ContentSyncDelegate;
@protocol ContentSyncApplyChangesDelegate;

@interface ContentSyncManager : NSObject<UIAlertViewDelegate, InAppUpdaterDelegate> {
    NSMutableArray *syncDelegateList;
    
    NSMutableArray *downloadErrorList;
    NSMutableArray *detailedDownloadErrorList;
    
    id<ContentSyncApplyChangesDelegate> applyChangesDelegate;
    id<ContentUnpackDelegate> unpackDelegate;
    
    InAppUpdater *appUpdater;
    ContentSyncActions *syncActions;
    NSOperationQueue *operationQueue;
    
    // Properties to handle state for syncing operations
    BOOL syncIsInProgress;
    BOOL syncDoApplyChanges;
    
    BOOL syncDoUnpack;
    
    // This is where files are downloaded to
    NSString *baseSyncPath;
    // This is the base directory where all content goes
    NSString *baseContentPath;
    // This is the base directory where the application data content goes.  It is under the 
    // baseContentPath.
    NSString *baseAppContentPath;
    // This is the base URL on the remote system we are copying from.
    NSURL *baseSharedWebURL;
    // Title to use for informational alerts
    NSString *alertTitle;
    // Initial content zip file
    NSString *initialContentZipFile;
    
    BOOL enableStructureSync;
    
}

@property (nonatomic, readonly) NSMutableArray *downloadErrorList;
@property (nonatomic, readonly) NSMutableArray *detailedDownloadErrorList;

@property (nonatomic, readonly) InAppUpdater *appUpdater;
@property (nonatomic, readonly) ContentSyncActions *syncActions;

@property (nonatomic, assign, getter=isSyncDoApplyChanges) BOOL syncDoApplyChanges;
@property (nonatomic, assign, getter=isSyncDoUnpack) BOOL syncDoUnpack;

@property (nonatomic, copy) NSString *baseSyncPath;
@property (nonatomic, copy) NSString *baseContentPath;
@property (nonatomic, copy) NSString *baseAppContentPath;
@property (nonatomic, copy) NSURL *baseSharedWebURL;
@property (nonatomic, copy) NSURL *contentStructureWebURL;

@property (nonatomic, copy) NSString *alertTitle;
@property (nonatomic, copy) NSString *initialContentZipFile;

@property (nonatomic, assign, getter=isEnableStructureSync) BOOL enableStructureSync;

#pragma mark Shared Instance
+ (ContentSyncManager *) sharedInstance;

// Setup Methods
- (void) reset;

- (void) configure: (ContentSyncConfig *) config;
- (void) setupToUnpackToloAppContent;
- (void) setupSyncActions;

// Main Content Sync Methods
- (void) unpackContents;

- (void) performSync;
- (void) cancelSync;

- (BOOL) shouldStartScheduledSync;
- (void) kickoffScheduledOrOngoingSync;

- (void) applyChanges;

// Methods for ongoing sync
- (BOOL) isSyncInProgress;
- (BOOL) hasSyncItemsToApply;
- (void) addDownloadError: (NSString *) errorMsg;
- (void) addDetailedDownloadError:(NSString *) errorMsg;

- (NSString *) getLastUpdateDateAsString;

// Methods for determining if certain resources are suppressed in the sync
- (BOOL) isVideoSyncDisabled;
- (BOOL) isPresentationSyncDisabled;

// Registering Delegates
- (void) registerSyncDelegate: (id<ContentSyncDelegate>) delegate;
- (void) unRegisterSyncDelegate: (id<ContentSyncDelegate>) delegate;

- (void) setUnpackDelegate: (id<ContentUnpackDelegate>) delegate;
- (void) setApplyChangesDelegate: (id<ContentSyncApplyChangesDelegate>) delegate;

- (void) notifyDelegatesOfSyncActions;
- (void) notifyDelegatesOfSyncProgress: (NSInteger)currentChangeIndex totalChanges:(NSInteger)totalChangeCount;
- (void) notifyDelegatesOfSyncComplete: (SyncCompletionStatus) syncStatus;

- (void) notifyDelegatesOfApplyChangesProgress: (NSInteger)currentChangeIndex totalChanges:(NSInteger)totalChangeCount;
- (void) notifyDelegatesOfApplyChangesComplete;

// Methods for managing content file and directory structure
- (void) createDirForFile:(NSString *) filePath;
- (void) createDirForFile:(NSString *) filePath withFileMgr:(NSFileManager *)fileMgr;
- (BOOL) fileExists:(NSString *)filePath withFileMgr:(NSFileManager *)fileMgr;
- (BOOL) fileExists:(NSString *)path;
- (BOOL) compareFile:(NSString *)filePath1 withFile:(NSString *)filePath2;

- (NSInteger) fileSize:(NSString *)path;
- (NSString *) fileContentsAsString: (NSString *) path;

- (BOOL)addSkipBackupAttributeToItem:(NSURL *)URL;
- (BOOL) hasSkipBackupAttributeToItemAtURL:(NSURL *)URL;

- (BOOL) isSymbolicLink:(NSString *)path withFileMgr:(NSFileManager *)fileMgr;
- (BOOL) contentDirExists;
- (void) setupContentDirectories;
- (void) resetContentDirectory;
- (void) cleanSyncFolder;

- (NSArray *) allFilePathsInDir: (NSString *) dirPath traverseDir: (BOOL) doTraverseDir withFileMgr: (NSFileManager *) fileMgr;

// Methods for getting content metadata from the files
- (NSString *) contentMetaDataJsonFromContentFolder;
- (NSString *) contentMetaDataJsonFromSyncFolder;
- (NSString *) contentMetaDataJsonFromWebFolderWithStatus:(NSInteger *)status;

// Methods for getting and checking content structure data
- (NSString *) contentStructureDataJsonFromWebFolderWithStatus:(NSInteger *)status;
- (BOOL) didContentStructureChange;

// Content Meta Data object methods
- (ContentMetaData *) getWebContentMetaDataWithStatus:(NSInteger *)status;
- (ContentMetaData *) getAppContentMetaData;

@end
     
@protocol ContentUnpackDelegate <NSObject>

- (void) unpackItemsDetected: (BOOL) doUnpack;
- (void) totalItemsToUnpack: (NSInteger) itemsToUnpack;
- (void) unpackedItemsProgress: (NSInteger)currentFileIndex total:(NSInteger)totalFileCount;
- (void) unpackItemsComplete;

@end

@protocol ContentSyncDelegate<NSObject>
- (void) syncStarted: (ContentSyncManager *) syncManager isFullSync: (BOOL) isFullSync;
- (void) syncActionsInitialized: (ContentSyncActions *) syncActions;
- (void) syncCompleted: (ContentSyncManager *) syncManager syncStatus: (SyncCompletionStatus) syncStatus;
- (void) syncProgress: (ContentSyncManager *) syncManager currentChange:(NSInteger)currentChangeIndex totalChanges:(NSInteger)totalChangeCount;

@optional
- (void) syncResetContentDirectory:(ContentSyncManager *)syncManager;
@end

@protocol ContentSyncApplyChangesDelegate<NSObject>
- (void) applyChangesStarted: (ContentSyncManager *) syncManager;
- (void) applyChangesProgress: (ContentSyncManager *) syncManager currentChange:(NSInteger)currentChangeIndex totalChanges:(NSInteger)totalChangeCount;
- (void) applyChangesComplete: (ContentSyncManager *) syncManager;

@end

