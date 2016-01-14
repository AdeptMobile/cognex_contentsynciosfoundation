//
//  ApplyChangesOperation.m
//  ToloApp
//
//  Created by Torey Lomenda on 7/21/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import "ApplyChangesOperation.h"

#import "ContentSyncManager.h"

#import "NSFileManager+Extensions.h"

#define KEY_FROM_DOCUMENT_ID(doc_id) [NSString stringWithFormat:@"bookmarks_%@",(doc_id)]

@interface ApplyChangesOperation()

- (void) applyChangesFromSyncFolder: (NSFileManager *) fileMgr;
- (void) applyChangesRemoveFromContentFolder: (NSFileManager *) fileMgr;
- (void) applyChangesSymlinks: (NSFileManager *) fileMgr;
- (void) pruneEmptyContentFolders: (NSFileManager *) fileMgr;

@end
@implementation ApplyChangesOperation

#pragma mark -
#pragma mark init/dealloc
- (id) init {
    self = [super init];
    
    if (self) {
        currentChangeCount = 0;
    }
    
    return self;
}


- (void) main {
    // Need to create an auto release pool for the operation
    @autoreleasepool {
    
    // Get the Content Sync Manager instance
        ContentSyncManager *syncManager = [ContentSyncManager sharedInstance];
           
        NSFileManager *fileMgr;    
        @try {
            fileMgr = [[NSFileManager alloc] init];
            
            [self applyChangesFromSyncFolder:fileMgr];
            [self applyChangesSymlinks:fileMgr];
            [self applyChangesRemoveFromContentFolder:fileMgr];
            
            // Let us prune any empty directories
            [self pruneEmptyContentFolders:fileMgr];
            
        }
        @finally {
            fileMgr = nil;
            fileMgr = nil;
            
            // APPLY Changes is complete
            dispatch_sync(dispatch_get_main_queue(), ^{
                [syncManager notifyDelegatesOfApplyChangesComplete];
            });
        }
    
    }
}

- (void) applyChangesFromSyncFolder: (NSFileManager *) fileMgr {
    NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *baseContentPath = [[ContentSyncManager sharedInstance] baseAppContentPath];
    NSString *baseSyncPath = [[ContentSyncManager sharedInstance] baseSyncPath];
    NSString *syncContentPath = [cacheDirectory stringByAppendingPathComponent:
                                 [baseSyncPath stringByAppendingPathComponent:baseContentPath]];
    
    // You must loop through all directories in the sync folder, moving any files along the way
    NSArray *filePaths = [[ContentSyncManager sharedInstance] allFilePathsInDir:syncContentPath traverseDir:YES withFileMgr:fileMgr];
    
    if (filePaths && [filePaths count] > 0) {
        NSRange baseContentPathRange;
        NSString *copyPath = nil;
        ContentSyncActions *syncActions = [ContentSyncManager sharedInstance].syncActions;
        
        for (NSString *fileToSyncPath in filePaths) {
            baseContentPathRange = [fileToSyncPath rangeOfString:baseContentPath];
            
            if (baseContentPathRange.location != NSNotFound) {
                copyPath = [cacheDirectory stringByAppendingPathComponent:[fileToSyncPath substringFromIndex:baseContentPathRange.location]];
                
                if ([fileMgr fileExistsAtPath:copyPath]) {
                    [fileMgr removeItemAtPath:copyPath error:nil];
                }
                
                [[ContentSyncManager sharedInstance ] createDirForFile:copyPath];
                [fileMgr moveItemAtPath:fileToSyncPath toPath:copyPath error:&error];
                
                if (error) {
                    NSLog(@"%@", [error description]);
                }
            }
            
            // Ignore the metadata and structure JSON files in the apply changes count
            if ([fileToSyncPath rangeOfString:CONTENT_METADATA_FILENAME].location == NSNotFound &&
                [fileToSyncPath rangeOfString:CONTENT_STRUCTURE_FILENAME].location == NSNotFound) {
                
                currentChangeCount += 1;
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    [[ContentSyncManager sharedInstance] notifyDelegatesOfApplyChangesProgress:currentChangeCount
                                                                                  totalChanges:[syncActions totalItemsToApply]];
                });
            }
        }
        copyPath = nil;
        
        [fileMgr removeItemAtPath:syncContentPath error:nil];
    }
}

- (void) applyChangesRemoveFromContentFolder:(NSFileManager *)fileMgr {
    NSError *error = nil;
    ContentSyncActions *syncActions = [ContentSyncManager sharedInstance].syncActions;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSArray *removeContentItems = syncActions.removeContentItems;
    
    if (removeContentItems && [removeContentItems count] > 0) {
        NSString *removePath = nil;
        for (ContentItem *removeItem in removeContentItems) {
            removePath = [cacheDirectory stringByAppendingPathComponent:removeItem.path];
            [fileMgr removeItemAtPath:removePath error:&error];
            if (error) {
                NSLog(@"%@", [error description]);
            }
            
            // Any bookmarks to remove
            [[NSUserDefaults standardUserDefaults]removeObjectForKey:KEY_FROM_DOCUMENT_ID(removePath)];
            
            currentChangeCount += 1;
            dispatch_sync(dispatch_get_main_queue(), ^{
                [[ContentSyncManager sharedInstance] notifyDelegatesOfApplyChangesProgress:currentChangeCount
                                                                              totalChanges:[syncActions totalItemsToApply]];
            });
            
            removePath = nil;
        }
    }
}

- (void) applyChangesSymlinks: (NSFileManager *) fileMgr {
    NSError *error = nil;
    ContentSyncActions *syncActions = [ContentSyncManager sharedInstance].syncActions;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSArray *symlinksToCreate = syncActions.symlinkItemsToCreate;
    
    if (symlinksToCreate && [symlinksToCreate count] > 0) {
        NSString *symlinkCopyPath = nil;
        NSString *symlinkDestPath = nil; 
        for (ContentItem *symlinkItem in symlinksToCreate) {
            symlinkCopyPath = [cacheDirectory stringByAppendingPathComponent:symlinkItem.path];
            symlinkDestPath = [cacheDirectory stringByAppendingPathComponent:symlinkItem.symlink];
            
            [fileMgr removeItemAtPath:symlinkCopyPath error:nil];
            
            [[ContentSyncManager sharedInstance] createDirForFile:symlinkCopyPath];
            [fileMgr createSymbolicLinkAtPath:symlinkCopyPath withDestinationPath:symlinkDestPath error:&error];
            if (error) {
                NSLog(@"%@", [error description]);
            }
            
            currentChangeCount += 1;
            dispatch_sync(dispatch_get_main_queue(), ^{
                [[ContentSyncManager sharedInstance] notifyDelegatesOfApplyChangesProgress:currentChangeCount
                                                                              totalChanges:[syncActions totalItemsToApply]];
            });
        }
    }
}

- (void) pruneEmptyContentFolders:(NSFileManager *)fileMgr {    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *baseContentPath = [[ContentSyncManager sharedInstance] baseAppContentPath];
    NSString *fullContentPath = [cacheDirectory stringByAppendingPathComponent:baseContentPath];
    
    [fileMgr pruneEmptyDirs:fullContentPath];
}

@end
