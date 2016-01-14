//
//  ContentSyncActions.m
//  ToloApp
//
//  Created by Torey Lomenda on 6/22/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import "ContentSyncActions.h"

#import "ContentSyncManager.h"

@interface ContentSyncActions()

- (void) addToRemoveItems: (NSArray *) appContentItems webItems: (NSArray *) webContentItems;
- (void) addToAddItems: (NSArray *) appContentItems webItems: (NSArray *) webContentItems;
- (void) addToModifyItems:(NSArray *) appContentItems webItems: (NSArray *) webContentItems forceSync: (BOOL) forceSync;

- (BOOL) isHtmlResource: (NSString *) fileName;

- (BOOL) isHtmlResourceMarkedNotFound:  (NSString *) fileName;

@end

@implementation ContentSyncActions

@synthesize removeContentItems;
@synthesize addContentItems;
@synthesize modifyContentItems;
@synthesize symlinkItemsToCreate;
@synthesize downloadItemsRemaining;
@synthesize structureChanged;

#pragma mark - 
#pragma mark init/dealloc Methods
- (id) init {
    self = [super init];
    
    if (self) {
        removeContentItems = [NSMutableArray arrayWithCapacity:0];
        addContentItems = [NSMutableArray arrayWithCapacity:0];
        modifyContentItems = [NSMutableArray arrayWithCapacity:0];
        
        symlinkItemsToCreate = [NSMutableArray arrayWithCapacity:0];
        downloadItemsRemaining = [NSMutableArray arrayWithCapacity:0];
        
        structureChanged = NO;
    }
    
    return self;
}

- (void) dealloc {
    
    structureChanged = NO;
    
}

#pragma mark - 
#pragma mark Public Methods
- (void) determineSyncActions:(ContentMetaData *) appMetaData updatedContentMetaData:(ContentMetaData *) sharedWebContentMetaData {
    [self determineSyncActions:appMetaData updatedContentMetaData:sharedWebContentMetaData forceSync:NO];
}
- (void) determineSyncActions:(ContentMetaData *) appMetaData updatedContentMetaData:(ContentMetaData *) sharedWebContentMetaData forceSync:(BOOL)forceSync {
    
    if (appMetaData && sharedWebContentMetaData) {
        
        // If the generatedOn dates are different do a full sync check, otherwise just look for
        // modifications, which should catch things like files that aren't there
        if (![appMetaData.generatedOn isEqualToString:sharedWebContentMetaData.generatedOn]) {
            NSArray *appFileItems = [appMetaData getFileItems];
            NSArray *appSymlinkItems = [appMetaData getSymlinkItems];
            
            NSArray *webFileItems = [sharedWebContentMetaData getFileItems];
            NSArray *webSymlinkItems = [sharedWebContentMetaData getSymlinkItems];
            
            // Build the file add, modify, remove items
            [self addToRemoveItems:appFileItems webItems:webFileItems];
            [self addToAddItems:appFileItems webItems:webFileItems];
            [self addToModifyItems:appFileItems webItems:webFileItems forceSync:forceSync];
            
            // Build the symlink add, modify, remove items
            [self addToRemoveItems:appSymlinkItems webItems:webSymlinkItems];
            [self addToAddItems:appSymlinkItems webItems:webSymlinkItems];
            [self addToModifyItems:appSymlinkItems webItems:webSymlinkItems forceSync:forceSync];
        } else {
            NSArray *appFileItems = [appMetaData getFileItems];
            NSArray *appSymlinkItems = [appMetaData getSymlinkItems];
            
            NSArray *webFileItems = [sharedWebContentMetaData getFileItems];
            NSArray *webSymlinkItems = [sharedWebContentMetaData getSymlinkItems];
            
            [self addToModifyItems:appFileItems webItems:webFileItems forceSync:forceSync];
            [self addToModifyItems:appSymlinkItems webItems:webSymlinkItems forceSync:forceSync];
        }
    }
}

- (void) determineSyncActions:(ContentMetaData *) appContentMetaData updatedContentMetaData: (ContentMetaData *) sharedWebContentMetaData compareStructureData:(BOOL)doCompare {
    [self determineSyncActions:appContentMetaData updatedContentMetaData:sharedWebContentMetaData compareStructureData:doCompare forceSync:NO];
}
- (void) determineSyncActions:(ContentMetaData *) appContentMetaData updatedContentMetaData: (ContentMetaData *) sharedWebContentMetaData compareStructureData:(BOOL)doCompare forceSync:(BOOL)forceSync {
    
    [self determineSyncActions:appContentMetaData updatedContentMetaData:sharedWebContentMetaData forceSync:forceSync];
    structureChanged = [[ContentSyncManager sharedInstance] didContentStructureChange];
}

- (void) clearSyncActions {
    [addContentItems removeAllObjects];
    [removeContentItems removeAllObjects];
    [modifyContentItems removeAllObjects];
    
    [symlinkItemsToCreate removeAllObjects];
    [downloadItemsRemaining removeAllObjects];

    structureChanged = NO;
}

- (void) removeItemToDownload:(ContentItem *)removeItem {
    [downloadItemsRemaining removeObject:removeItem];
}

- (BOOL) hasItemsToDownload {
    return downloadItemsRemaining && [downloadItemsRemaining count] > 0;
}

- (BOOL) hasItemsForAppToApply {
    return (removeContentItems && [removeContentItems count] > 0)
            || (addContentItems && [addContentItems count] > 0)
            || (modifyContentItems && [modifyContentItems count] > 0)
            || structureChanged == YES;
}

- (NSInteger) totalItemsToDownload {
    return [downloadItemsRemaining count];
}
- (NSInteger) totalItemsToApply {
    return [removeContentItems count] + [addContentItems count] + [modifyContentItems count];
}
- (NSInteger) totalSymLinksToApply {
    return [symlinkItemsToCreate count];
}

#pragma mark -
#pragma mark Private Methods
- (void) addToRemoveItems:(NSArray *) appContentItems webItems:(NSArray *) webContentItems {
    // The items we remove are ones that are in the app items but not in the web items
    if ([appContentItems count] > 0) {
        for (ContentItem *appItem in appContentItems) {
            BOOL isFound = NO;
            
            if ([webContentItems count] > 0) {
                for (ContentItem *webItem in webContentItems) {
                    if (([appItem isFile] && [webItem isFile]) ||  ([appItem isSymbolicLink] && [webItem isSymbolicLink])) {
                        if ([appItem.path isEqualToString:webItem.path]) {
                            isFound = YES;
                            break;
                        }
                    }
                }
            }
            
            // Add to the remove actions
            if (!isFound) {
                [removeContentItems addObject:appItem];
                // NSLog(@"add to remove: %@", appItem.path);
            }
        }
    }
}

- (void) addToAddItems:(NSArray *)appContentItems webItems:(NSArray *) webContentItems {
    // The items we add are ones that are in the latest items but not in the current items
    
    BOOL videoSyncDisabled = [[ContentSyncManager sharedInstance] isVideoSyncDisabled];
    BOOL presentationSyncDisabled = [[ContentSyncManager sharedInstance] isPresentationSyncDisabled];
    
    if ([webContentItems count] > 0) {
        for (ContentItem *webItem in webContentItems) {
            BOOL isFound = NO;
            
            if ([appContentItems count] > 0) {
                for (ContentItem *appItem in appContentItems) {
                    if (([appItem isFile] && [webItem isFile]) ||  ([appItem isSymbolicLink] && [webItem isSymbolicLink])) {
                        if ([webItem.path isEqualToString:appItem.path]) {
                            isFound = YES;
                            // It is in the meta-data but not on the file system
                            if (isFound && [appItem isFile]) {
                                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
                                NSString *cacheDirectory = [paths objectAtIndex:0];
                                if (![[ContentSyncManager sharedInstance] fileExists:[cacheDirectory stringByAppendingPathComponent:appItem.path]]) {
                                    isFound = NO;
                                }
                            }
                            break;
                        }
                    }
                }
            }
            
            // Add to the add actions
            if (!isFound) {
                if (webItem.mustSync == NO &&
                    ((videoSyncDisabled && [self isMovieFile:webItem.path]) ||
                    (presentationSyncDisabled && [self isPresentationFile:webItem.path]))) {
                    NSLog(@"Suppressing download of new file: %@ due to sync settings", webItem.path);
                } else {
                    [addContentItems addObject:webItem];
                    
                    // Add to download list or symbolic links to create list
                    if ([webItem isFile]) {
                        [downloadItemsRemaining addObject:webItem];
                        // NSLog(@"add download: %@ size: %d mod: %@", webItem.path, webItem.fileSize, webItem.modifiedDate);
                    } else if ([webItem isSymbolicLink]){
                        [symlinkItemsToCreate addObject:webItem];
                    }
                }
            }
        }
    }
}

- (void) addToModifyItems:(NSArray *) appContentItems webItems:(NSArray *) webContentItems forceSync:(BOOL)forceSync {
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    BOOL isVideoSuppressed = [[ContentSyncManager sharedInstance] isVideoSyncDisabled];
    BOOL isPresentationSuppresed = [[ContentSyncManager sharedInstance] isPresentationSyncDisabled];
    NSFileManager *fileMgr;
    @try {
        fileMgr = [[NSFileManager alloc] init];
    }
    @finally {
        fileMgr = nil;
    }
    
    // The item is found in the latest but the symlink or fileModified date is changed
    if ([appContentItems count] > 0) {
        for (ContentItem *appItem in appContentItems) {
            ContentItem *modifiedItem  = nil;
            if ([webContentItems count] > 0) {
                for (ContentItem *webItem in webContentItems) {
                    // Ignore for the actual Meta Data file
                    if ([appItem.path rangeOfString:@"content-metadata.json"].location == NSNotFound) {
                        if ([appItem.path isEqualToString:webItem.path]) {
                            
                            // If the type is suppressed and the file path matches it,
                            // and if it is not on the filesystem, don't check it for
                            // modifications.  If it is there, check and sync it if
                            // needed.
                            if (webItem.mustSync == NO &&
                                isVideoSuppressed &&
                                [self isMovieFile:appItem.path] &&
                                ([[ContentSyncManager sharedInstance] fileExists:appItem.path withFileMgr:fileMgr] == NO)) {
                                NSLog(@"Skipping modification check for suppressed video file: %@ due to sync suppression settings.", appItem.path);
                                break;
                            }
                            if (webItem.mustSync == NO &&
                                isPresentationSuppresed &&
                                [self isPresentationFile:appItem.path] &&
                                ([[ContentSyncManager sharedInstance] fileExists:[cacheDirectory stringByAppendingPathComponent:appItem.path] withFileMgr:fileMgr] == NO)) {
                                NSLog(@"Skipping modification check for suppressed presentation file: %@ due to sync suppression settings.", appItem.path);
                                break;
                            }
                            
                            if ([appItem isFile] && [webItem isFile]) {
                                if (![appItem.modifiedDate isEqualToString:webItem.modifiedDate]) {
                                    modifiedItem = webItem;
                                    break;
                                } else if (appItem.fileSize ==  webItem.fileSize) {
                                    // To check if a file is modified
                                    //  1.  For text files (if the file size of local version is 0), add to modified
                                    //  2.  If the file is an HTML file and it has the text NOTFOUND (exception hack) add to modified
                                    //  3.  If the actual size is different than metadata file size, sync the file
                                    // Only check the existing file attributes for non-text files since text files actual size on iOS is
                                    // different than the source version even though the file contents are the same.
                                    
                                    // Check the existing file attributes

                                    NSInteger actualFileSize = [[ContentSyncManager sharedInstance] fileSize:[cacheDirectory stringByAppendingPathComponent:appItem.path]];
                                    
                                    if ([self isTextFile:appItem.path]) {
                                        if (forceSync || actualFileSize <= 0 || [self isHtmlResourceMarkedNotFound:appItem.path]) {
                                            modifiedItem = webItem;
                                            break;
                                        }
                                    } else if (actualFileSize != webItem.fileSize) {
                                        // Check the filesize.  If different add to modify list
                                        modifiedItem = webItem;
                                        break;
                                    }
                                }
                            } else if ([appItem isSymbolicLink] && [webItem isSymbolicLink] && ![appItem.symlink isEqualToString:webItem.symlink]) {
                                modifiedItem = webItem;
                                break;
                            }
                            
                            
                        }
                    }
                }
                
                // Adds the the modified items
                if (modifiedItem) {
                    [modifyContentItems addObject:modifiedItem];
                    
                    // Add to download list or symbolic links to create list
                    if ([modifiedItem isFile]) {
//                        NSLog(@"mod app item    : %@, size: %d, mod: %@", appItem.path, appItem.fileSize, appItem.modifiedDate);
//                        NSLog(@"mod download add: %@, size: %d, mod: %@", modifiedItem.path, modifiedItem.fileSize, modifiedItem.modifiedDate);
                        [downloadItemsRemaining addObject:modifiedItem];
                    } else if ([modifiedItem isSymbolicLink]){
                        [symlinkItemsToCreate addObject:modifiedItem];
                    }
                    
                }
            }
        }
    }
}

- (BOOL) isTextFile: (NSString *) fileName {
    NSArray *textFileTypeList = [NSArray arrayWithObjects:@"csv", @"txt", @"xml", @"html", @"css", @"js", nil];
    
    for (NSString *fileType in textFileTypeList) {
        if ([[fileName lowercaseString] hasSuffix:fileType]) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL) isHtmlResource: (NSString *) fileName {
    NSArray *textFileTypeList = [NSArray arrayWithObjects:@"html", @"css", @"js", nil];
    
    for (NSString *fileType in textFileTypeList) {
        if ([[fileName lowercaseString] hasSuffix:fileType]) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL) isHtmlResourceMarkedNotFound: (NSString *) fileName {
    if ([self isHtmlResource: fileName]) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDirectory = [paths objectAtIndex:0];
        NSString *fileContents = [[ContentSyncManager sharedInstance] fileContentsAsString:[cacheDirectory stringByAppendingPathComponent:fileName]];
        
        if (fileContents != nil && [fileContents rangeOfString:@"NOTFOUND"].location != NSNotFound) {
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - Private Methods needed for sync
- (BOOL) isMovieFile:(NSString *)filePath {
    if ([[filePath pathExtension] isEqualToString:@"mov"]
        || [[filePath pathExtension] isEqualToString:@"MOV"]
        || [[filePath pathExtension] isEqualToString:@"mp4"]
        || [[filePath pathExtension] isEqualToString:@"MP4"]
        || [[filePath pathExtension] isEqualToString:@"mpv"]
        || [[filePath pathExtension] isEqualToString:@"MPV"]
        || [[filePath pathExtension] isEqualToString:@"3gp"]
        || [[filePath pathExtension] isEqualToString:@"3GP"]
        || [[filePath pathExtension] isEqualToString:@"m4v"]
        || [[filePath pathExtension] isEqualToString:@"M4V"]) {
        return  YES;
    }
    
    return NO;
}

- (BOOL) isPresentationFile:(NSString *)filePath {
    if ([[filePath pathExtension] isEqualToString:@"key"]
        || [[filePath pathExtension] isEqualToString:@"KEY"]
        || [[filePath pathExtension] isEqualToString:@"doc"]
        || [[filePath pathExtension] isEqualToString:@"DOC"]
        || [[filePath pathExtension] isEqualToString:@"docx"]
        || [[filePath pathExtension] isEqualToString:@"DOCX"]
        || [[filePath pathExtension] isEqualToString:@"xls"]
        || [[filePath pathExtension] isEqualToString:@"XLS"]
        || [[filePath pathExtension] isEqualToString:@"xlsx"]
        || [[filePath pathExtension] isEqualToString:@"XLSX"]
        || [[filePath pathExtension] isEqualToString:@"ppt"]
        || [[filePath pathExtension] isEqualToString:@"PPT"]
        || [[filePath pathExtension] isEqualToString:@"pptx"]
        || [[filePath pathExtension] isEqualToString:@"PPTX"]) {
        return  YES;
    }
    
    return NO;
    
}

@end
