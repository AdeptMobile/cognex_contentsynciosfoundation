//
//  ContentSyncManager.m
//  ToloApp
//
//  Created by Torey Lomenda on 6/22/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//
#include <SystemConfiguration/SystemConfiguration.h>
#include <MobileCoreServices/MobileCoreServices.h>
#include <sys/xattr.h>

#import "ContentSyncManager.h"

#import "UnpackContentOperation.h"
#import "ContentSyncOperation.h"
#import "ApplyChangesOperation.h"

#import "Reachability.h"
#import "AFNetworking.h"

#import "AlertUtils.h"

#import "CJSONDeserializer.h"
#import "PDKeychainBindingsController.h"

#define UNPACK_TOLOAPP_CONTENTS @"user.toloapp.doUnpackToloAppContents"
#define SYNC_LAST_UPDATE @"user.toloapp.lastUpdateDate"
#define SYNC_LAST_ATTEMPT @"user.toloapp.lastUpdateAttemptDate"

#define KEYCHAIN_USER_KEY  @"com.objectpartners.salesfolio.SFUserNameKey"
#define KEYCHAIN_PW_KEY  @"com.objectpartners.salesfolio.SFPasswordKey"

@interface ContentSyncManager()

@property (nonatomic, assign) BOOL isAuthRequiredForJSON;

@property (nonatomic, strong) dispatch_queue_t backgroundQueue;

- (void) setupSyncMgr;
- (void) setupInAppUpdater;

- (void) setLastUpdateAttemptDate;
- (NSDate *) getLastUpdateAttemptDate;
- (void) setLastUpdateDate;
- (NSDate *) getLastUpdateDate;

- (BOOL) doUnpackToloAppContent;

- (BOOL) continueSyncActions;
- (BOOL) startScheduledSync;

// Sync operations
- (void) syncAppInstall;
- (void) syncDocuments:(BOOL)resetSync;
- (BOOL) isSyncResetEnabled;
- (void) turnOffSyncReset;

- (void) releaseResources;

// Content Metadata
- (NSString *) contentMetaDataJsonFromSyncFolder;
- (NSString *) contentStructureJsonFromSyncFolder;

- (NSString *) jsonStringFromFile:(NSString *)filePath;

@end
@implementation ContentSyncManager

@synthesize appUpdater;
@synthesize syncActions;

@synthesize syncDoApplyChanges;
@synthesize syncDoUnpack;
@synthesize downloadErrorList;
@synthesize detailedDownloadErrorList;

@synthesize baseSyncPath;
@synthesize baseContentPath;
@synthesize baseSharedWebURL;
@synthesize contentStructureWebURL;
@synthesize baseAppContentPath;
@synthesize alertTitle;
@synthesize initialContentZipFile;

@synthesize enableStructureSync = _enableStructureSync;

#pragma mark -
#pragma mark Initialize Singleton
+ (ContentSyncManager *) sharedInstance {
    static dispatch_once_t pred;
    static ContentSyncManager *sharedInstance = nil;
    
    dispatch_once(&pred, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

#pragma mark -
#pragma init/dealloc
-(id) init {
    self = [super init];
    
    if (self) {
        self.backgroundQueue = dispatch_queue_create("com.opi.salesfolio.syncprocess", 0);
        
        // Initialize
        NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"SFAppConfig" ofType:@"plist"];
        NSDictionary *appConfigDict = [[NSDictionary alloc] initWithContentsOfFile:path];
        
        NSString *dictKey = @"com.sf.app.content";
        self.isAuthRequiredForJSON = [[((NSDictionary *) [appConfigDict objectForKey:dictKey]) objectForKey:@"jsonAuthRequired"] boolValue];
        
        // Initialize
        [self setupSyncMgr];
    }
    
    return self;
}

- (void) dealloc {
    [self releaseResources];
}

#pragma mark -
#pragma mark Setup Methods called by App Delegate
- (void) configure:(ContentSyncConfig *)config {
    
    self.baseSharedWebURL = config.contentMetaDataUrl;
    self.contentStructureWebURL = config.contentStructureUrl;
    self.baseContentPath = config.localContentRoot;
    self.baseSyncPath = config.localSyncRoot;
    self.baseAppContentPath = config.localContentDocPath;
    self.alertTitle = config.alertTitle;
    self.initialContentZipFile = config.bundledContentZipFile;
    self.enableStructureSync = config.isStructureEnabled;

    [self setupToUnpackToloAppContent];
    [self setupSyncActions];
    
    // Create the Content and Sync Folders if they do not already exist
    [self setupContentDirectories];
}

- (void) setupToUnpackToloAppContent {
    if (![self contentDirExists]) {
        NSUserDefaults *appDefaults = [NSUserDefaults standardUserDefaults];
        
        // This needs to be set to yes for unpacking contents for the first time
        [appDefaults setBool:YES forKey:UNPACK_TOLOAPP_CONTENTS];
    }
}

- (void) setupSyncActions {
    if (syncActions) {
        syncActions = nil;
    }
    
    syncActions = [[ContentSyncActions alloc] init];
}

- (void) reset {
    [self releaseResources];
    [self setupSyncMgr];
    [self setupSyncActions];
}

#pragma mark -
#pragma mark Main Content Sync Methods
- (BOOL) shouldStartScheduledSync {
    Reachability *internetReach = [Reachability reachabilityForInternetConnection];
    NSDate *lastUpdateDate = [self getLastUpdateDate];
    NSDate *lastUpdateAttempt = [self getLastUpdateAttemptDate];
    
    // Let us check the latest update date and wifi.  Check once per day for updates
    if ([internetReach isReachableViaWiFi]) {
        if (lastUpdateDate == nil) {
            return YES;
        }
        
        NSDate *todayDate = [NSDate date];
        NSTimeInterval interval = [todayDate timeIntervalSinceDate:lastUpdateDate];
        NSTimeInterval secsInADay = 86400;
        
        // A day has passed.  start the sync
        if (interval > secsInADay) {
            return YES;
        }
    }
    else{
        for (id<ContentSyncDelegate> delegate in syncDelegateList) {
            
            if (lastUpdateAttempt == nil) {
                // If lastUpdateAttempt is nil, it means we've never tried to sync before so
                // this is likely first install.  We should always provide the failure message
                // then for each time.  We also won't set the lastUpdateAttempt until we
                // try a sync with Wifi.
                [AlertUtils showModalAlertMessage:@"A WIFI Connection is required to sync.  Swipe up from the bottom of the screen and tap the sync button on the right to retry when Wifi is available." withTitle:alertTitle];
                if ([delegate respondsToSelector:@selector(syncCompleted:syncStatus:)]) {
                    [delegate syncCompleted:self syncStatus:SYNC_NO_WIFI];
                }
            } else {
                //Only send the wifi failure once a day, fail silently if an attempt was made in the last day
                NSDate *todayDate = [NSDate date];
                NSTimeInterval interval = [todayDate timeIntervalSinceDate:lastUpdateAttempt];
                NSTimeInterval secsInADay = 86400;
                
                if ([delegate respondsToSelector:@selector(syncCompleted:syncStatus:)] && (interval > secsInADay)) {
                    [delegate syncCompleted:self syncStatus:SYNC_NO_WIFI];
                    [self setLastUpdateAttemptDate];
                }
            }
        }
        
        //[delegate syncCompleted:self syncStatus:SYNC_NO_WIFI];
        //[AlertUtils showModalAlertMessage:@"A WIFI Connection is required to sync." withTitle:alertTitle];
    }
    
    return NO;
}

- (void) unpackContents {
    if (syncDoUnpack) {
        // Create the NSOperation to unpack any contents
        UnpackContentOperation *unpackOperation = [[UnpackContentOperation alloc] init];
        unpackOperation.delegate = unpackDelegate;
        unpackOperation.doUnpackInitial = [self doUnpackToloAppContent];
        
        [operationQueue addOperation:unpackOperation];
    }
}

- (void) performSync {
    // Setup the content directories to be sure
    [self setupContentDirectories];
    
    dispatch_async(self.backgroundQueue, ^{
        [self syncAppInstall];
    });
}
/** cancelSync
 *
 * Canceling an ongoing sync when the auto login fails (App re-enters active state).
 *
 */
- (void) cancelSync {
    operationQueue.suspended = YES;
    
    if (self.isSyncInProgress) {
        [operationQueue cancelAllOperations];
        
        syncIsInProgress = NO;
        
        // remove everything from the Sync folder
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDirectory = [paths objectAtIndex:0];
        NSString *syncContentPath = [cacheDirectory stringByAppendingPathComponent:
                                     [baseSyncPath stringByAppendingPathComponent:baseContentPath]];
        NSFileManager *fileMgr;
        @try {
            fileMgr = [NSFileManager new];
            [fileMgr removeItemAtPath:syncContentPath error:nil];
        }
        @finally {
            fileMgr = nil;
        }
    }
}

- (void) kickoffScheduledOrOngoingSync {
    dispatch_queue_t backgroundQueue = dispatch_queue_create("com.opi.salesfolio.syncprocess", 0);
    
    dispatch_async(backgroundQueue, ^{
        // Are there sync actions that have not been applied??  We can tell if there is anything in the sync folder
        if (![self continueSyncActions]) {
            // Should we be kicking off a scheduled update
            [self startScheduledSync];
        }
    });
}

- (void) applyChanges {
    if ([syncActions hasItemsForAppToApply]) {
        if (applyChangesDelegate && [applyChangesDelegate respondsToSelector:@selector(applyChangesStarted:)]) {
            [applyChangesDelegate applyChangesStarted:self];
        }
    }
    ApplyChangesOperation *applyOperation = [[ApplyChangesOperation alloc] init];
    [operationQueue addOperation:applyOperation];
}

#pragma mark -
#pragma mark Ongoing Sync methods
- (BOOL) isSyncInProgress {
    return syncIsInProgress;
}

- (BOOL) hasSyncItemsToApply {
    return [syncActions hasItemsForAppToApply];
}

- (void) addDownloadError:(NSString *)errorMsg {
    [downloadErrorList addObject:errorMsg];
}

- (void) addDetailedDownloadError:(NSString *)errorMsg {
    [detailedDownloadErrorList addObject:errorMsg];
}

- (NSString *) getLastUpdateDateAsString {
    NSDate *updateDate = [self getLastUpdateDate];
    
    if (updateDate) {
        NSLocale *usLocale = [[NSLocale alloc] initWithLocaleIdentifier: @"en_US"];
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat: @"yyyy-MM-dd HH:mm:ss"];
        [dateFormatter setLocale: usLocale];
        
        return [dateFormatter stringFromDate:updateDate];
    }
    
    return @"";
}

#pragma mark -
#pragma mark AppUpdateDelegate
- (void) appUpdateStatus:(AppUpdateStatusType) updateStatus {
    
    void (^showAppUpdateAlert)(void) = ^{
        UIAlertView *questionnaireAlert = [[UIAlertView alloc] init];
        questionnaireAlert.title = @"Update Available";
        questionnaireAlert.message = @"Would you like to install the update to maximize your user experience?";
        questionnaireAlert.delegate = self;
        [questionnaireAlert addButtonWithTitle:@"Yes"];
        [questionnaireAlert addButtonWithTitle:@"Later"];
        [questionnaireAlert show];
    };
    void (^showResetAlert)(void) = ^ {
        UIAlertView *questionnaireAlert = [[UIAlertView alloc] init];
        questionnaireAlert.title = @"Refresh All Documents";
        questionnaireAlert.message = @"Reset is enabled in Settings.  This will replace all documents within the app.  Do want a full document refresh or updates only?";
        questionnaireAlert.delegate = self;
        [questionnaireAlert addButtonWithTitle:@"Full Refresh"];
        [questionnaireAlert addButtonWithTitle:@"Update Only"];
        [questionnaireAlert show];
    };
    
    if (updateStatus == APP_UPDATE_AVAILABLE) {
        dispatch_async(dispatch_get_main_queue(), ^{
            showAppUpdateAlert();
        });
    } else {
        // If there was no update detected we can move on to syncing the documents
        if ([self isSyncResetEnabled]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                showResetAlert();
            });
        } else {
            [self syncDocuments:NO];
        }
    }
}

- (void) appUpdateIsInitiated:(BOOL)isInitiated {
    
}

#pragma mark -
#pragma mark AlertViewDelegate methods
- (void)alertView:(UIAlertView *)anAlertView clickedButtonAtIndex:(NSInteger)aButtonIndex {
	if ([anAlertView.title isEqualToString:@"Update Available"]) {
		// Check by titles rather than index since documentation suggests that different
		// devices can set the indexes differently.
		NSString *clickedButtonTitle = [anAlertView buttonTitleAtIndex:aButtonIndex];
		if ([clickedButtonTitle isEqualToString:@"Yes"]) {
			[appUpdater initiateAppDownload];
		} else if ([clickedButtonTitle isEqualToString:@"Later"]) {
            // Continue with syncing documents since we are cancelling the install
            [self syncDocuments:NO];
        }
	} else if ([anAlertView.title isEqualToString:@"Refresh All Documents"]) {
		// Determine if we do a full refresh or continue with update
		NSString *clickedButtonTitle = [anAlertView buttonTitleAtIndex:aButtonIndex];
        
        // Turn off the sync reset
        [self turnOffSyncReset];
        
		if ([clickedButtonTitle isEqualToString:@"Full Refresh"]) {
            [self syncDocuments:YES];
            
		} else if ([clickedButtonTitle isEqualToString:@"Update Only"]) {
            // Continue with syncing documents since we are cancelling the install
            [self syncDocuments:NO];
        }
	}
    
	// Other generic alerts will just fall through and dismiss with no other actions.
}

#pragma mark -
#pragma mark Registering Sync Delegates
- (void) registerSyncDelegate:(id<ContentSyncDelegate>)delegate {
    @synchronized(self) {
        if (![syncDelegateList containsObject:delegate]) {
            [syncDelegateList addObject:delegate];
        }
    }
}

- (void) unRegisterSyncDelegate:(id<ContentSyncDelegate>)delegate {
    @synchronized(self) {
        [syncDelegateList removeObject:delegate];
    }
}

- (void) setUnpackDelegate:(id<ContentUnpackDelegate>)delegate {
    @synchronized(self) {
        unpackDelegate = delegate;
    }
}

- (void) setApplyChangesDelegate:(id<ContentSyncApplyChangesDelegate>)delegate {
    @synchronized(self) {
        applyChangesDelegate = delegate;
    }
}

- (void) notifyDelegatesOfSyncActions {
    if (syncDelegateList && [syncDelegateList count] > 0) {
        for (id<ContentSyncDelegate> delegate in syncDelegateList) {
            if ([delegate respondsToSelector:@selector(syncActionsInitialized:)]) {
                [delegate syncActionsInitialized:self.syncActions];
            }
        }
    }
}
- (void) notifyDelegatesOfSyncProgress:(NSInteger)currentChangeIndex totalChanges:(NSInteger)totalChangeCount {
    if (syncDelegateList && [syncDelegateList count] > 0) {
        for (id<ContentSyncDelegate> delegate in syncDelegateList) {
            if ([delegate respondsToSelector:@selector(syncProgress:currentChange:totalChanges:)]) {
                [delegate syncProgress:self currentChange:currentChangeIndex totalChanges:totalChangeCount];
            }
        }
    }
}
- (void) notifyDelegatesOfSyncComplete: (SyncCompletionStatus)syncStatus {
    
    if (syncStatus == SYNC_STATUS_OK && ![syncActions hasItemsForAppToApply]) {
        // Set the last update date (no changes just move the metadata file).
        // Move the content file only (apply changes immediately)
        [self applyChanges];
    }
    
    if (syncDelegateList && [syncDelegateList count] > 0) {
        for (id<ContentSyncDelegate> delegate in syncDelegateList) {
            if ([delegate respondsToSelector:@selector(syncCompleted:syncStatus:)]) {
                [delegate syncCompleted:self syncStatus:syncStatus];
            }
        }
    }
    
    syncIsInProgress = NO;
}

#pragma mark -
#pragma mark Apply Changes notification methods
- (void) notifyDelegatesOfApplyChangesProgress:(NSInteger)currentChangeIndex totalChanges:(NSInteger)totalChangeCount {
    if (applyChangesDelegate && [applyChangesDelegate respondsToSelector:@selector(applyChangesProgress:currentChange:totalChanges:)]) {
        [applyChangesDelegate applyChangesProgress:self currentChange:currentChangeIndex totalChanges:totalChangeCount];
    }
}

- (void) notifyDelegatesOfApplyChangesComplete {
    if ([syncActions hasItemsForAppToApply]) {
        if (applyChangesDelegate && [applyChangesDelegate respondsToSelector:@selector(applyChangesComplete:)]) {
            [applyChangesDelegate applyChangesComplete:self];
        }
    }
    
    // set the last update date
    [self setLastUpdateDate];
    [self setLastUpdateAttemptDate];
    
    // Clear all actions
    [downloadErrorList removeAllObjects];
    [detailedDownloadErrorList removeAllObjects];
    [syncActions clearSyncActions];
    
    syncDoApplyChanges = NO;
}

#pragma mark -
#pragma mark Unpacking Methods
- (BOOL) doUnpackToloAppContent {
    NSUserDefaults *appDefaults = [NSUserDefaults standardUserDefaults];
    
    id value = [appDefaults objectForKey:UNPACK_TOLOAPP_CONTENTS];
    
    if (value) {
        // It has not been done yet (this is a one time thing)
        [appDefaults setBool:NO forKey:UNPACK_TOLOAPP_CONTENTS];
        
        return [value boolValue];
    }
    
    // It has not been done yet (this is a one time thing)
    [appDefaults setBool:NO forKey:UNPACK_TOLOAPP_CONTENTS];
    return YES;
}

#pragma mark - Content Sync File and Directory Management


- (void) createDirForFile:(NSString *) filePath {
    NSFileManager *fileMgr;
    @try {
        fileMgr = [[NSFileManager alloc] init];
        [self createDirForFile:filePath withFileMgr:fileMgr];
    }
    @finally {
        fileMgr = nil;
        fileMgr = nil;
    }
}

- (void) createDirForFile:(NSString *) filePath withFileMgr:(NSFileManager *)fileMgr {
    if (fileMgr) {
        NSError *error = nil;
        BOOL isDir = YES;
        
        // Make sure the parent/containing directory exists for the file
        NSArray *pathComponents = [filePath pathComponents];
        NSString *dirPath = @"/";
        
        for (int i = 0; i < [pathComponents count] - 1; i++) {
            dirPath = [dirPath stringByAppendingPathComponent:(NSString *) [pathComponents objectAtIndex:i]];
        }
        
        if (![fileMgr fileExistsAtPath:dirPath isDirectory:&isDir]) {
            [fileMgr createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:&error];
            
            if (error) {
                NSLog(@"%@", [error description]);
            }
        }
    }
}

- (BOOL) fileExists:(NSString *)path {
    NSFileManager *fileMgr;
    @try {
        fileMgr = [[NSFileManager alloc] init];
        BOOL exists = [self fileExists:path withFileMgr:fileMgr];
        
        return exists;
    }
    @finally {
        fileMgr = nil;
        fileMgr = nil;
    }
}

- (BOOL) fileExists:(NSString *)filePath withFileMgr:(NSFileManager *)fileMgr {
    if (fileMgr) {
        return [fileMgr fileExistsAtPath:filePath];
    }
    
    return NO;
}

- (BOOL) compareFile:(NSString *)filePath1 withFile:(NSString *)filePath2 {
    NSFileManager *fileMgr;
    @try {
        fileMgr = [[NSFileManager alloc] init];
        if ([self fileExists:filePath1 withFileMgr:fileMgr] && [self fileExists:filePath2 withFileMgr:fileMgr]) {
            return [fileMgr contentsEqualAtPath:filePath1 andPath:filePath2];
        }
        return NO;
    }
    @finally {
        fileMgr = nil;
        fileMgr = nil;
    }
}

- (NSInteger) fileSize:(NSString *)path {
    NSFileManager *fileMgr;
    NSInteger fileSize = 0;
    BOOL isDir = NO;
    @try {
        fileMgr = [[NSFileManager alloc] init];
        BOOL exists = [fileMgr fileExistsAtPath:path isDirectory:&isDir];
        
        if (exists && !isDir && ![self isSymbolicLink:path withFileMgr:fileMgr]) {
            NSDictionary *fileAttributes = [fileMgr attributesOfItemAtPath:path error:nil];
            NSString *fileSize = [fileAttributes valueForKey:@"NSFileSize"];
            
            if (fileSize) {
                return [fileSize intValue];
            }
        }
        
        return fileSize;
    }
    @finally {
        fileMgr = nil;
        fileMgr = nil;
    }
}

- (NSString *) fileContentsAsString:(NSString *)path {
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"%@", [error description]);
    }
    return contents;
}

- (BOOL) addSkipBackupAttributeToItem:(NSURL *)URL {
    if (&NSURLIsExcludedFromBackupKey == nil) { // iOS <= 5.0.1
        const char* filePath = [[URL path] fileSystemRepresentation];
        
        const char* attrName = "com.apple.MobileBackup";
        u_int8_t attrValue = 1;
        
        int result = setxattr(filePath, attrName, &attrValue, sizeof(attrValue), 0, 0);
        return result == 0;
    } else { // iOS >= 5.1
        NSError *error = nil;
        
        BOOL success = [URL setResourceValue: [NSNumber numberWithBool: YES]
                                      forKey: NSURLIsExcludedFromBackupKey error: &error];
        
        if(!success){
            NSLog(@"Error excluding '%@' from backup %@", [URL lastPathComponent], error);
            
        }
        
        return success;
    }
}

- (BOOL) hasSkipBackupAttributeToItemAtURL:(NSURL *)URL {
    NSError *error = nil;
    
    id flag = nil;
    BOOL success = [URL getResourceValue: &flag
                                  forKey: NSURLIsExcludedFromBackupKey error: &error];
    
    if(!success) {
        NSLog(@"Error fetching exclude '%@' from backup %@", [URL lastPathComponent], error);
        return false;
    }
    
    if (!flag)
        return false;
    
    return [flag boolValue];
}

- (BOOL) isSymbolicLink:(NSString *)path withFileMgr:(NSFileManager *)fileMgr {
    NSDictionary *attributes = [fileMgr attributesOfItemAtPath:path error:nil];
    return [attributes objectForKey:@"NSFileType"] == NSFileTypeSymbolicLink || [path rangeOfString:@"symlink"].location != NSNotFound;
}

- (BOOL) contentDirExists {
    NSFileManager *fileMgr;
    @try {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDirectory = [paths objectAtIndex:0];
        NSString *contentPath = [cacheDirectory stringByAppendingPathComponent:baseContentPath];
        
        fileMgr = [[NSFileManager alloc] init];
        return [self fileExists:contentPath withFileMgr:fileMgr];
    }
    @finally {
        fileMgr = nil;
        fileMgr = nil;
    }
}


- (void) setupContentDirectories {
    NSFileManager *fileMgr;
    @try {
        fileMgr = [[NSFileManager alloc] init];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDirectory = [paths objectAtIndex:0];
        
        NSError * error = nil;
        
        NSString *contentPath = [cacheDirectory stringByAppendingPathComponent:baseContentPath];
        NSString *syncPath = [cacheDirectory stringByAppendingPathComponent:baseSyncPath];
        BOOL isDir = YES;
        
        if (![fileMgr fileExistsAtPath:contentPath isDirectory:&isDir]) {
            [fileMgr createDirectoryAtPath:contentPath withIntermediateDirectories:NO attributes:nil error:&error];
            
            if (error) {
                NSLog(@"Error creating content path:  %@", [error description]);
                return;
            }
        }
        
        // Add an empty JSON metadata if one does not exist
        NSString *catalogContentPath = [contentPath stringByAppendingPathComponent:@"CatalogApp"];
        NSString *contentMetaDataPath = [catalogContentPath stringByAppendingPathComponent:@"content-metadata.json"];
        NSString *emptyMetaDataFile = [[NSBundle mainBundle] pathForResource:@"content-metadata-empty.json" ofType:nil];
        
        if (![fileMgr fileExistsAtPath:contentMetaDataPath] && [fileMgr fileExistsAtPath:emptyMetaDataFile]) {
            [fileMgr createDirectoryAtPath:catalogContentPath withIntermediateDirectories:NO attributes:nil error:&error];
            if(![fileMgr copyItemAtPath:emptyMetaDataFile toPath:contentMetaDataPath error:&error]) {
                // handle the error
                NSLog(@"Error copying content-metadata.json:  %@", [error description]);
            }
        }
        
        if (![fileMgr fileExistsAtPath:syncPath isDirectory:&isDir]) {
            [fileMgr createDirectoryAtPath:syncPath withIntermediateDirectories:NO attributes:nil error:&error];
            
            if (error) {
                NSLog(@"Error creating sync path:  %@", [error description]);
                return;
            }
        }
        
        // Now that we have moved out of the Documents directory we don't
        // need this.  SMM
        // Add the skip iTunes/iCloud backup check
        // NSURL *contentUrl = [NSURL fileURLWithPath:contentPath];
        // NSURL *syncUrl = [NSURL fileURLWithPath:syncPath];
        
        //if (![self hasSkipBackupAttributeToItemAtURL:contentUrl]) {
        //    [self addSkipBackupAttributeToItem:contentUrl];
        //}
        //if (![self hasSkipBackupAttributeToItemAtURL:syncUrl]) {
        //    [self addSkipBackupAttributeToItem:syncUrl];
        //}
    }
    @finally {
        fileMgr = nil;
        fileMgr = nil;
    }
}

- (void) resetContentDirectory {
    NSFileManager *fileMgr;
    @try {
        fileMgr = [[NSFileManager alloc] init];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDirectory = [paths objectAtIndex:0];
        
        NSError * error = nil;
        
        NSString *contentPath = [cacheDirectory stringByAppendingPathComponent:baseContentPath];
        BOOL isDir = YES;
        
        if ([fileMgr fileExistsAtPath:contentPath isDirectory:&isDir]) {
            if (![fileMgr removeItemAtPath:contentPath error:&error]) {
                NSLog(@"Error removing content directory:  %@", [error description]);
            }
        }
        
        // Setup the content directories again.
        if (error == nil) {
            [self setupContentDirectories];
        }
    }
    @finally {
        fileMgr = nil;
        fileMgr = nil;
    }
}

- (void) cleanSyncFolder {
    NSFileManager *fileMgr;
    @try {
        fileMgr = [[NSFileManager alloc] init];
        NSError *error = nil;
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDirectory = [paths objectAtIndex:0];
        NSString *syncContentPath = [cacheDirectory stringByAppendingPathComponent:
                                     [baseSyncPath stringByAppendingPathComponent:baseAppContentPath]];
        
        // You must loop through all directories in the sync folder, moving any files along the way
        [fileMgr removeItemAtPath:syncContentPath error:&error];
        
        if (error) {
            NSLog(@"Error cleaning sync folder:  '%@'", error);
        }
    }
    @finally {
        fileMgr = nil;
        fileMgr = nil;
    }
}

#pragma mark - Content MetaData JSON String Reading methods
- (NSString *) contentMetaDataJsonFromContentFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *contentMetaDataPath = [[cacheDirectory stringByAppendingPathComponent:baseAppContentPath] stringByAppendingPathComponent:CONTENT_METADATA_FILENAME];
    
    
    NSString *contents = [self jsonStringFromFile:contentMetaDataPath];
    return contents;
}

- (NSString *) contentMetaDataJsonFromSyncFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *syncContentMetaDataPath = [[[cacheDirectory stringByAppendingPathComponent:baseSyncPath]
                                          stringByAppendingPathComponent:baseAppContentPath]
                                         stringByAppendingPathComponent:CONTENT_METADATA_FILENAME];
    
    NSString *jsonString = [self jsonStringFromFile:syncContentMetaDataPath];
    return jsonString;
}

- (NSString *) contentMetaDataJsonFromWebFolderWithStatus:(NSInteger *)status {
    
    // Build a request to get the file contents
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *syncContentPath = [[cacheDirectory stringByAppendingPathComponent:baseSyncPath]
                                 stringByAppendingPathComponent:baseAppContentPath];
    NSString *syncContentMetaDataPath = [syncContentPath stringByAppendingPathComponent:CONTENT_METADATA_FILENAME];
    
    // Make sure the parent directory exists before downloading the file
    [self createDirForFile:syncContentMetaDataPath];
    
    // Invoke the request
    // Configuration now has full path either to content-metadata.json file or the CM url that produces the same
    // format.
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:baseSharedWebURL cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:60.0];
    
    // Do the AFNetworking Way
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    BOOL isValidFile = YES;
    if (self.isAuthRequiredForJSON == YES) {
        NSString *username = [self getUsernameFromKeychain];
        NSString *password = [self getPasswordFromKeychain];
        NSURLCredential *credential = [NSURLCredential credentialWithUser:username password:password persistence:NSURLCredentialPersistenceForSession];
        [operation setCredential:credential];
    }
    
    @try {
        operation.outputStream = [NSOutputStream outputStreamToFileAtPath:syncContentMetaDataPath append:NO];
        
        [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            // Nothing to do here, synchronous request.
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            // Nothing to do here, synchronous request.
        }];
        
        [operation start];
        [operation waitUntilFinished];
        
        *status = [operation.response statusCode];
        
        if (![operation error] && [operation.response statusCode] == 200) {
            NSString *jsonString = [self jsonStringFromFile:syncContentMetaDataPath];
            
            if (jsonString == nil) {
                isValidFile = NO;
            } else {
                return jsonString;
            }
        } else {
            NSLog(@"content-metadata.json file download failed, error: %@, response code: %ld", [[operation error] localizedDescription], (long)[operation.response statusCode]);
            isValidFile = NO;
        }
    }
    @finally {
        operation = nil;
    }
    
    if (!isValidFile) {
        NSFileManager *fileMgr;
        @try {
            fileMgr = [[NSFileManager alloc] init];
            
            // Remove everything from the sync folder since there was an issue with getting the content metadata.
            [fileMgr removeItemAtPath:syncContentPath error:nil];
        }
        @finally {
            fileMgr = nil;
            fileMgr = nil;
        }
        
    }
    
    return nil;
}

- (NSString *) contentStructureJsonFromSyncFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *syncContentStructurePath = [[[cacheDirectory stringByAppendingPathComponent:baseSyncPath]
                                           stringByAppendingPathComponent:baseAppContentPath]
                                          stringByAppendingPathComponent:CONTENT_STRUCTURE_FILENAME];
    
    NSString *jsonString = [self jsonStringFromFile:syncContentStructurePath];
    
    return jsonString;
}

- (NSString *) contentStructureDataJsonFromWebFolderWithStatus:(NSInteger *)status {
    
    // Build a request to get the file contents
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *syncContentPath = [[cacheDirectory stringByAppendingPathComponent:baseSyncPath]
                                 stringByAppendingPathComponent:baseAppContentPath];
    NSString *syncContentStructurePath = [syncContentPath stringByAppendingPathComponent:CONTENT_STRUCTURE_FILENAME];
    
    // Make sure the parent directory exists before downloading the file
    [self createDirForFile:syncContentStructurePath];
    
    // Invoke the request
    // Configuration now has full path either to content-structure.json file or the CM url that produces the same
    // format.
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:contentStructureWebURL cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:60.0];
    
    // Do the AFNetworking Way
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    BOOL isValidFile = YES;
    if (self.isAuthRequiredForJSON == YES) {
        NSString *username = [self getUsernameFromKeychain];
        NSString *password = [self getPasswordFromKeychain];
        NSURLCredential *credential = [NSURLCredential credentialWithUser:username password:password persistence:NSURLCredentialPersistenceForSession];
        [operation setCredential:credential];
    }
    
    @try {
        operation.outputStream = [NSOutputStream outputStreamToFileAtPath:syncContentStructurePath append:NO];
        
        [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            // Nothing to do here, synchronous request.
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            // Nothing to do here, synchronous request.
        }];
        
        [operation start];
        [operation waitUntilFinished];
        
        *status = [operation.response statusCode];
        
        if (![operation error] && [operation.response statusCode] == 200) {
            NSString *jsonString = [self jsonStringFromFile:syncContentStructurePath];
            
            if (jsonString == nil) {
                isValidFile = NO;
            } else {
                return jsonString;
            }
        } else {
            NSLog(@"content-structure.json file download failed, error: %@, response code: %ld", [[operation error] localizedDescription], (long)[operation.response statusCode]);
            isValidFile = NO;
        }
    }
    @finally {
        operation = nil;
    }
    
    if (!isValidFile) {
        NSFileManager *fileMgr;
        @try {
            fileMgr = [[NSFileManager alloc] init];
            
            // Remove file from the sync folder since there was an issue with getting it.
            [fileMgr removeItemAtPath:syncContentPath error:nil];
        }
        @finally {
            fileMgr = nil;
            fileMgr = nil;
        }
    }
    
    return nil;
}

- (BOOL) didContentStructureChange {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *syncContentPath = [[cacheDirectory stringByAppendingPathComponent:baseSyncPath]
                                 stringByAppendingPathComponent:baseAppContentPath];
    NSString *syncContentStructurePath = [syncContentPath stringByAppendingPathComponent:CONTENT_STRUCTURE_FILENAME];
    NSString *appContentStructurePath = [[cacheDirectory stringByAppendingPathComponent:baseAppContentPath] stringByAppendingPathComponent:CONTENT_STRUCTURE_FILENAME];
    
    if ([self fileExists:syncContentStructurePath] == YES && [self fileExists:appContentStructurePath] == NO) {
        return YES;
    } else if ([self fileExists:syncContentStructurePath] == YES && [self fileExists:appContentStructurePath] == YES) {
        NSString *existingStructure = [self jsonStringFromFile:appContentStructurePath];
        NSString *updatedStructure = [self jsonStringFromFile:syncContentStructurePath];
        if (existingStructure == nil && updatedStructure) {
            return YES;
        } else if (existingStructure && updatedStructure) {
            return (![existingStructure isEqualToString:updatedStructure]);
        } else {
            return NO;
        }
        
    }
    return NO;
}

- (NSArray *) allFilePathsInDir:(NSString *)dirPath traverseDir:(BOOL)doTraverseDir withFileMgr:(NSFileManager *)fileMgr {
    
    NSMutableArray *filePaths = [NSMutableArray arrayWithCapacity:0];
    NSArray *foundPaths = [fileMgr contentsOfDirectoryAtPath:dirPath error:nil];
    
    if (foundPaths) {
        // Build directories and file paths (I do not care about content at this point, just the paths
        BOOL isDir;
        for (NSString *path in foundPaths) {
            NSString *fullPath = [dirPath stringByAppendingPathComponent:path];
            
            if ([path rangeOfString:@"."].location != 0) {
                // Do we add the path or traverse
                if ([fileMgr fileExistsAtPath:fullPath isDirectory:&isDir]) {
                    if (isDir && doTraverseDir) {
                        [filePaths addObjectsFromArray:[self allFilePathsInDir:fullPath traverseDir:doTraverseDir withFileMgr:fileMgr]];
                    } else {
                        [filePaths addObject:fullPath];
                    }
                }
            }
        }
    }
    return filePaths;
}

#pragma mark - Content Meta Data methods
- (ContentMetaData *) getAppContentMetaData {
    NSError *jsonError = nil;
    NSString *jsonMetaData = [self contentMetaDataJsonFromContentFolder];
    
    // Initialize the sync actions
    if (jsonMetaData) {
        NSDictionary *jsonData = (NSDictionary *) [[CJSONDeserializer deserializer]
                                                   deserializeAsDictionary:[jsonMetaData dataUsingEncoding:NSUTF8StringEncoding] error:&jsonError];
        
        if (jsonError) {
            return [[ContentMetaData alloc] initWithJsonData:nil];
        }
        
        return [[ContentMetaData alloc] initWithJsonData:jsonData];
    }
    
    return nil;
}

- (ContentMetaData *) getWebContentMetaDataWithStatus:(NSInteger *)status {
    NSError *jsonError = nil;
    NSString *jsonMetaData = [self contentMetaDataJsonFromWebFolderWithStatus:status];
    
    if (jsonMetaData) {
        // Initialize the sync actions
        NSDictionary *jsonData = (NSDictionary *) [[CJSONDeserializer deserializer]
                                                   deserializeAsDictionary:[jsonMetaData dataUsingEncoding:NSUTF8StringEncoding] error:&jsonError];
        
        if (jsonError) {
            return nil;
        }
        
        return [[ContentMetaData alloc] initWithJsonData:jsonData];
    }
    
    return nil;
}

#pragma mark - Private methods to fetch username and password from keychain
#pragma mark - Username and Password Handling
- (NSString *) getUsernameFromKeychain {
    PDKeychainBindings *keyBindings = [PDKeychainBindings sharedKeychainBindings];
    NSString *username = (NSString *)[keyBindings objectForKey:KEYCHAIN_USER_KEY];
    return username;
}

- (NSString *) getPasswordFromKeychain {
    PDKeychainBindings *keyBindings = [PDKeychainBindings sharedKeychainBindings];
    NSString *password = (NSString *)[keyBindings objectForKey:KEYCHAIN_PW_KEY];
    return password;
}
#pragma mark -
#pragma mark Private Sync Methods
- (void) syncAppInstall {
    [appUpdater checkForUpdate];
}

- (void) syncDocuments:(BOOL)resetSync {
    if (!syncDoUnpack) {
        syncIsInProgress = YES;
        
        if (syncDelegateList && [syncDelegateList count] > 0) {
            for (id<ContentSyncDelegate> delegate in syncDelegateList) {
                if ([delegate respondsToSelector:@selector(syncStarted:isFullSync:)]) {
                    [delegate syncStarted:self isFullSync:resetSync];
                }
            }
        }
        
        Reachability *internetReach = [Reachability reachabilityForInternetConnection];
        if ([internetReach isReachableViaWiFi]) {
            if (resetSync) {
                // If this is a full sync, remove any content files first and start from "scratch"
                [self resetContentDirectory];
                if (syncDelegateList && [syncDelegateList count] > 0) {
                    for (id<ContentSyncDelegate> delegate in syncDelegateList) {
                        if ([delegate respondsToSelector:@selector(syncResetContentDirectory:)]) {
                            [delegate syncResetContentDirectory:self];
                        }
                    }
                }
            }
            ContentSyncOperation *syncOperation = [[ContentSyncOperation alloc] init];
            [operationQueue addOperation:syncOperation];
        } else {
            syncIsInProgress = NO;
            
            void (^callSyncDelegates)(void) = ^ {
                for (id<ContentSyncDelegate> delegate in syncDelegateList) {
                    if ([delegate respondsToSelector:@selector(syncCompleted:syncStatus:)]) {
                        [delegate syncCompleted:self syncStatus:SYNC_NO_WIFI];
                    }
                }
            };
            
            dispatch_async(dispatch_get_main_queue(), ^{
                callSyncDelegates();
            });
        }
    }
}

#pragma mark - Private Methods
- (BOOL) isSyncResetEnabled {
    // First check to see if the app has a content sync reset action from settings
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL resetEnabled = [defaults boolForKey:@"sf.app.settings.contentSyncReset"];
    
    return resetEnabled;
}

- (void) turnOffSyncReset {
    // Set the reset toggle back to OFF
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:NO forKey:@"sf.app.settings.contentSyncReset"];
    [defaults synchronize];
}

- (BOOL) isVideoSyncDisabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults boolForKey:@"sf.app.settings.contentSyncDisableVideo"];
}

- (BOOL) isPresentationSyncDisabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults boolForKey:@"sf.app.settings.contentSyncDisablePresentation"];
}

- (void) releaseResources {
    syncDelegateList = nil;
    
    downloadErrorList = nil;
    
    detailedDownloadErrorList = nil;
    
    syncActions = nil;
    
    [operationQueue cancelAllOperations];
    operationQueue = nil;
    
    appUpdater = nil;
}

- (void) setupSyncMgr {
    syncDoUnpack = YES;
    syncIsInProgress = NO;
    syncDoApplyChanges = NO;
    
    syncDelegateList = [NSMutableArray arrayWithCapacity:0];
    downloadErrorList = [NSMutableArray arrayWithCapacity:0];
    detailedDownloadErrorList = [NSMutableArray arrayWithCapacity:0];
    operationQueue = [[NSOperationQueue alloc] init];
    
    [self setupInAppUpdater];
}

- (void) setupInAppUpdater {
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"SFAppConfig" ofType:@"plist"];
    NSDictionary *lookupDictionary = [[NSDictionary alloc] initWithContentsOfFile:path];
    
    if (lookupDictionary) { 
        NSString *baseUrl = (NSString *) [((NSDictionary *) [lookupDictionary objectForKey:@"com.sf.app.updater"]) objectForKey:@"baseUrl"];
         NSString *manifestPath = (NSString *) [((NSDictionary *) [lookupDictionary objectForKey:@"com.sf.app.updater"]) objectForKey:@"manifestPath"];
        NSString *username = (NSString *) [((NSDictionary *) [lookupDictionary objectForKey:@"com.sf.app.updater"]) objectForKey:@"basicauth.user"];
        NSString *password = (NSString *) [((NSDictionary *) [lookupDictionary objectForKey:@"com.sf.app.updater"]) objectForKey:@"basicauth.pwd"];
        
        appUpdater = [[InAppUpdater alloc] initWithAppInstallUrl:baseUrl];
        appUpdater.delegate = self;
        appUpdater.manifestPath = manifestPath;
        appUpdater.username = username;
        appUpdater.password = password;
        
    }
}

- (void) setLastUpdateAttemptDate{
    NSUserDefaults *appDefaults = [NSUserDefaults standardUserDefaults];
    NSDate *updateDate = [NSDate date];
    
    [appDefaults setObject:updateDate forKey:SYNC_LAST_ATTEMPT];
}

- (NSDate *) getLastUpdateAttemptDate {
    NSUserDefaults *appDefaults = [NSUserDefaults standardUserDefaults];
    
    NSDate *updateDate = (NSDate *) [appDefaults objectForKey:SYNC_LAST_ATTEMPT];
    
    return updateDate;
}

- (void) setLastUpdateDate {
    NSUserDefaults *appDefaults = [NSUserDefaults standardUserDefaults];
    NSDate *updateDate = [NSDate date];
    
    [appDefaults setObject:updateDate forKey:SYNC_LAST_UPDATE];
}

- (NSDate *) getLastUpdateDate {
    NSUserDefaults *appDefaults = [NSUserDefaults standardUserDefaults];
    
    NSDate *updateDate = (NSDate *) [appDefaults objectForKey:SYNC_LAST_UPDATE];
    
    return updateDate;
}

-(BOOL) continueSyncActions {
    NSError *jsonError = nil;
    NSString *metadataInContentFolder = [self contentMetaDataJsonFromContentFolder];
    NSString *metadataInSyncFolder = [self contentMetaDataJsonFromSyncFolder];
    NSString *structureInSyncFolder = [self contentStructureJsonFromSyncFolder];
    
    if (metadataInContentFolder && metadataInSyncFolder && structureInSyncFolder) {
        NSDictionary *appMetaData = nil;
        NSDictionary *syncMetaData = nil;
        
        appMetaData = (NSDictionary *) [[CJSONDeserializer deserializer]
                                                      deserializeAsDictionary:[metadataInContentFolder dataUsingEncoding:NSUTF8StringEncoding] error:&jsonError];
        
        if (jsonError) {
            appMetaData = nil;
            jsonError = nil;
        }
        
        syncMetaData = (NSDictionary *) [[CJSONDeserializer deserializer]
                                                       deserializeAsDictionary:[metadataInSyncFolder dataUsingEncoding:NSUTF8StringEncoding] error:&jsonError];
        
        if (jsonError) {
            [self cleanSyncFolder];
            return NO;
        }
        
        ContentMetaData *appMetaDataObj = [[ContentMetaData alloc] initWithJsonData:appMetaData];
        ContentMetaData *syncMetaDataObj = [[ContentMetaData alloc] initWithJsonData:syncMetaData];
        
        [syncActions determineSyncActions:appMetaDataObj updatedContentMetaData:syncMetaDataObj compareStructureData:YES forceSync:YES];
        
        
        // At this point we should kickoff the sync since it appears that one was in progress when the app was last started.
        [self syncDocuments:NO];
        return YES;
    }
    
    return NO;
}

- (BOOL) startScheduledSync {
    if ([self shouldStartScheduledSync]) {
        [self performSync];
        return YES;
    }
    
    return NO;
}

- (NSString *) jsonStringFromFile:(NSString *)filePath {
    NSError *error = nil;
    // Attempt to read with UTF8 first and then fall back to ISO Latin 1 if it didn't work.  Do this because
    // the http transfer defaults to ISO Latin 1 if it can't determine the correct encoding for some reason.
    NSString *jsonString = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error];
    
    if (jsonString == nil || error) {
        jsonString = [NSString stringWithContentsOfFile:filePath encoding:NSISOLatin1StringEncoding error:&error];
        
        if (error) {
            return nil;
        }
    }
    
    return jsonString;
    
}

@end
