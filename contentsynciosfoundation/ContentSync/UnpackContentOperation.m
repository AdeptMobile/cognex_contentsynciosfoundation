//
//  UpackContentOperation.m
//  ToloApp
//
//  Created by Torey Lomenda on 7/11/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import "UnpackContentOperation.h"

#import "ContentSyncManager.h"
#import "AlertUtils.h"

@interface UnpackContentOperation()

- (void) unzipContent;
- (void) unzipFile:(NSString *) zipFile withFileMgr:(NSFileManager *) fileMgr;

@end

@implementation UnpackContentOperation

@synthesize delegate;
@synthesize doUnpackInitial;

#pragma mark -
#pragma mark init/dealloc
- (id) init {
    self = [super init];
    
    if (self) {
        doUnpackInitial = NO;
    }
    
    return self;
}

- (void) main {
    // Need to create an auto release pool for the operation
    @autoreleasepool {
    
    // Determine if we need to unzip any files
        [self unzipContent];
        
        if (delegate && [delegate respondsToSelector:@selector(unpackItemsComplete)]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [delegate unpackItemsComplete];
            });
        }
    
    }
}

#pragma mark -
#pragma mark ZipArchive Progress
- (void) totalItemsToUnzip:(NSInteger)totalItems {
    dispatch_sync(dispatch_get_main_queue(), ^{
        [delegate totalItemsToUnpack:totalItems];
    });

}

- (void) unzipProgress:(NSInteger)currentFileIndex total:(NSInteger)totalFileCount {    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [delegate unpackedItemsProgress:currentFileIndex total:totalFileCount];

    });
}

#pragma mark -
#pragma mark Private Methods
- (void) unzipContent {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    BOOL doUnzipContent = [[bundle objectForInfoDictionaryKey:@"com.tolomatic.support.unzip"] boolValue];
    
    id<ContentUnpackDelegate> unpackDelegate = self.delegate;
    
    if (doUnzipContent) {
        NSFileManager *fileMgr;
        NSMutableArray *zipFilePaths = [NSMutableArray arrayWithCapacity:0];
        
        @try {
            fileMgr = [[NSFileManager alloc] init];
            NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [docPaths objectAtIndex:0];
            
            NSArray *cachePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            NSString *cacheDirectory = [cachePaths objectAtIndex:0];
            
            BOOL unpackItemsDetectedDelegateNotified = NO;
            
            // Copy the resource zip file from the app:  NOTE:  For an initial install unpack notify any delegates immediately.
            if (doUnpackInitial) {
                NSString *toloContentZipPath = [[NSBundle mainBundle] pathForResource:[[ContentSyncManager sharedInstance] initialContentZipFile] ofType:nil];
                NSError *error;
                
                if ([fileMgr fileExistsAtPath:toloContentZipPath]) {
                    if (unpackDelegate && [unpackDelegate respondsToSelector:@selector(unpackItemsDetected:)]) {
                        unpackItemsDetectedDelegateNotified = YES;
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            [unpackDelegate unpackItemsDetected:YES];
                        });
                    }
                    
                    if(![fileMgr copyItemAtPath:toloContentZipPath toPath:[cacheDirectory stringByAppendingPathComponent:[[ContentSyncManager sharedInstance] initialContentZipFile]] error:&error]) {
                        // handle the error
                        NSLog(@"Error copying initial content zip file %@:  %@", [[ContentSyncManager sharedInstance] initialContentZipFile], [error description]);
                    }
                }
            }
            
            // Move any initial files from the Documents directory to the Cache directory if the
            // user has placed them there.
            NSArray *docFoundPaths = [fileMgr contentsOfDirectoryAtPath:documentsDirectory error:nil];
            if ([docFoundPaths count] > 0) {
                for (NSString *path in docFoundPaths) {
                    if ([[path pathExtension] isEqualToString:@"zip"]
                        || [[path pathExtension] isEqualToString:@"ZIP"]) {
                        NSError *error;
                        if(![fileMgr moveItemAtPath:path toPath:[cacheDirectory stringByAppendingPathComponent:path] error:&error]) {
                            // handle the error
                            NSLog(@"Error moving Documents content zip file %@:  %@", path, [error description]);
                        }
                    }
                }
            }
            
            // Unzip any found zip files and then delete them after success
            NSArray *cacheFoundPaths = [fileMgr contentsOfDirectoryAtPath:cacheDirectory error:nil];
            BOOL unpackDetected = NO;
            
            if ([cacheFoundPaths count] > 0) {
                for (NSString *path in cacheFoundPaths) {
                    if ([[path pathExtension] isEqualToString:@"zip"] 
                        || [[path pathExtension] isEqualToString:@"ZIP"]) {
                        [zipFilePaths addObject:path];
                    }
                }
            }
            
            if ([zipFilePaths count] > 0) {
                // Notification of a new package to unzip (if not already)
                unpackDetected = YES;
            }
            
            // Have I notified the delegate yet (on initial install we do it above - before the copy.
            if (unpackItemsDetectedDelegateNotified == NO) {
                if (unpackDelegate && [unpackDelegate respondsToSelector:@selector(unpackItemsDetected:)]) {
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        [unpackDelegate unpackItemsDetected:unpackDetected];
                    });
                }
            } 
            
            if (unpackDetected) {
                for (NSString *path in zipFilePaths) {
                    [self unzipFile:path withFileMgr:fileMgr];    
                }
            }
        }
        @finally {
            fileMgr = nil;
            fileMgr = nil;
        }
    } else {
        // No Unpacking of content is detected
        if (unpackDelegate && [unpackDelegate respondsToSelector:@selector(unpackItemsDetected:)]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [unpackDelegate unpackItemsDetected:NO];
            });
        }
    }
}

- (void) unzipFile:(NSString *) zipFile withFileMgr:(NSFileManager *) fileMgr {
    ZipArchive * za;
    // Unzip to the Content Directory
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths objectAtIndex:0];
    NSString *zipPath = [cacheDirectory stringByAppendingPathComponent:zipFile];
    NSString *contentPath = [cacheDirectory stringByAppendingPathComponent:[[ContentSyncManager sharedInstance] baseContentPath]];
    
    @try {
        za = [[ZipArchive alloc] init];
        za.delegate = self;            
        if( [za UnzipOpenFile:zipPath]) {
            BOOL ret = [za UnzipFileTo:contentPath overWrite:YES];
            if( NO==ret )
            {
                // error handler here
            }
            [za UnzipCloseFile]; 
            
            // Then delete any extra files (__MACOSX) and the zip file
            [fileMgr removeItemAtPath:[contentPath stringByAppendingPathComponent:@"__MACOSX"] error:nil];
        } else {
            
            dispatch_sync(dispatch_get_main_queue(), ^{
                [AlertUtils showModalAlertMessage:[NSString stringWithFormat:@"Problem opening compressed file '%@'.  Fix through iTunes App Sync.", zipFile] withTitle:[[ContentSyncManager sharedInstance] alertTitle]];
            });
            
            
        }
    }
    @finally {
        [fileMgr removeItemAtPath:zipPath error:nil];
        
        za = nil;
        za = nil;
    }
}

@end