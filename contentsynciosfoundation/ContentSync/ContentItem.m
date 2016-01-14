//
//  ContentItem.m
//  ToloApp
//
//  Created by Torey Lomenda on 7/12/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import "ContentItem.h"
#import "ContentSyncManager.h"

@interface ContentItem()
- (void) setContentItemFromJson:(NSDictionary *) jsonData;
- (void) setDirectoryContentsFromJson:(NSArray *) contentItemsJsonArray;

@end

@implementation ContentItem

@synthesize isRoot;
@synthesize path;
@synthesize name;
@synthesize isDirectory;
@synthesize symlink;
@synthesize downloadUrl;
@synthesize fileSize;
@synthesize modifiedDate;
@synthesize contentItemList;
@synthesize mustSync;

#pragma mark -
#pragma mark init/dealloc
- (id) initWithJsonData:(NSDictionary *)jsonData isRoot:(BOOL)isRootItem {
    self = [super init];
    
    if (self) {
        // Initialize the object (is it a root node use the content array)
        isRoot = isRootItem;
        
        if (isRoot) {
            self.name = @"ContentItemRoot";
            self.path = [[ContentSyncManager sharedInstance] baseAppContentPath];
            self.isDirectory = YES;
            [self setDirectoryContentsFromJson:(NSArray *) [jsonData objectForKey:@"content"]];
        } else {
            [self setContentItemFromJson:jsonData];
        }
    }
    
    return self;
}


#pragma mark -
#pragma mark Accessor Methods
- (BOOL) isFile {
    if (!isDirectory && ![self isSymbolicLink]) {
        return YES;
    }
    
    return NO;
}

- (BOOL) isSymbolicLink {
    if (!isDirectory && symlink && ![symlink isEqualToString:@""]) {
        return YES;
    }
    
    return NO;
}

#pragma mark - 
#pragma mark Public Methods
- (NSArray *) getAllDirItems {
    NSMutableArray *dirItemList = [NSMutableArray arrayWithCapacity:0];
    
    if (isDirectory) {
        
        if (!isRoot) {
            [dirItemList addObject:self];
        }
        if (contentItemList && [contentItemList count] > 0) {
            for (ContentItem *item in contentItemList) {
                [dirItemList addObjectsFromArray:[item getAllDirItems]];
            }
        }
    }
    
    return dirItemList; 
}
    
- (NSArray *) getAllFileItems {
    NSMutableArray *fileItemList = [NSMutableArray arrayWithCapacity:0];
    
    if (isDirectory && contentItemList && [contentItemList count] > 0) {
        for (ContentItem *item in contentItemList) {
            // SMM: Ignore any content-structure.json entries in the content-metadata.json file.
            // We now manage the download of content-structure directly rather than through the metadata.
            if ([[item.name lowercaseString] isEqualToString:@"content-structure.json"] == NO) {
                [fileItemList addObjectsFromArray:[item getAllFileItems]];
            }
        }
    } else if ([self isFile]) {
        [fileItemList addObject:self];
    }
    
    return fileItemList;
}
- (NSArray *) getAllSymlinkItems {
    NSMutableArray *symlinkItemList = [NSMutableArray arrayWithCapacity:0];
    
    if (isDirectory && contentItemList && [contentItemList count] > 0) {
        for (ContentItem *item in contentItemList) {
            [symlinkItemList addObjectsFromArray:[item getAllSymlinkItems]];
        }
    } else if ([self isSymbolicLink]) {
        [symlinkItemList addObject:self];
    }
    
    return symlinkItemList;
}

#pragma mark -
#pragma mark Private Methods
- (void) setContentItemFromJson:(NSDictionary *)jsonData {
    self.name = (NSString *) [jsonData objectForKey:@"name"];
    self.path = (NSString *) [jsonData objectForKey:@"path"];
    self.isDirectory = [((NSNumber *) [jsonData valueForKey:@"isDir"]) boolValue];
    
    // In case we are running against a server that doesn't export the
    // mustSync flag with the metadata, we will default it to false.
    // This can cause videos in the info pages to be suppressed if
    // filtering is on, but is better than crashing.  SMM
    NSNumber *mustSyncJson = (NSNumber *) [jsonData valueForKey:@"mustSync"];
    if (mustSyncJson != nil) {
        self.mustSync = [mustSyncJson boolValue];
    } else {
        self.mustSync = NO;
    }
    
    self.symlink = (NSString *) [jsonData objectForKey:@"symlink"];
    
    // TODO:  append the accessible web folder base URI to the fileUrl
    self.downloadUrl = (NSString *) [jsonData objectForKey:@"fileUrl"];
    self.fileSize = [((NSNumber *) [jsonData valueForKey:@"fileSize"]) intValue];
    self.modifiedDate = (NSString *) [jsonData objectForKey:@"fileModifiedDate"];
    
//    NSString * escapedUrlString =
//    (NSString *)CFURLCreateStringByAddingPercentEscapes(
//                                                        NULL,
//                                                        (CFStringRef)self.downloadUrl,
//                                                        NULL,
//                                                        (CFStringRef)@"!*'();:@&=+$,/?%#[]",
//                                                        kCFStringEncodingUTF8 );
//    
//    self.downloadUrl = escapedUrlString;
//    [escapedUrlString release];

    
    if (isDirectory) {
        [self setDirectoryContentsFromJson:(NSArray *) [jsonData objectForKey:@"contents"]];
    }
}

- (void) setDirectoryContentsFromJson:(NSArray *) contentItemsJsonArray {
    // Initialize a new array
    self.contentItemList = [NSMutableArray arrayWithCapacity:0];
    
    if (contentItemsJsonArray && [contentItemsJsonArray count] > 0) {
        for (NSDictionary *contentItemData in contentItemsJsonArray) {
            [contentItemList addObject: [[ContentItem alloc] initWithJsonData:contentItemData isRoot:NO]];
        }
    }
}
@end
