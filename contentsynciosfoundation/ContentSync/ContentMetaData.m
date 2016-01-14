//
//  ContentMetaData.m
//  ToloApp
//
//  Created by Torey Lomenda on 6/22/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import "ContentMetaData.h"
#import "ContentSyncManager.h"

@implementation ContentMetaData

@synthesize generatedOn;
@synthesize contentRoot;

#pragma mark -
#pragma mark init/dealloc
- (id) initWithJsonData: (NSDictionary *) jsonData {
    self = [super init];
    
    if (self) {
        if (jsonData) {
            NSDictionary *dataDict = (NSDictionary *) [jsonData objectForKey:@"metadata"];
            
            generatedOn = [((NSString *) [dataDict objectForKey:@"generatedOn"]) copy];
            contentRoot = [[ContentItem alloc] initWithJsonData:dataDict isRoot:YES];
        }
    }
    
    return self;
}


#pragma mark - 
#pragma mark Public Methods
- (NSArray *) getDirItems {
    NSArray *dirItems = [contentRoot getAllDirItems];
    return dirItems;
}

- (NSArray *) getFileItems {
    NSArray *fileItems = [contentRoot getAllFileItems];
    return fileItems;
}

- (NSArray *) getSymlinkItems {
    NSArray *symlinkItems = [contentRoot getAllSymlinkItems];
    return  symlinkItems;
}

- (ContentItem *) getContentItemAtPath:(NSString *) path {
    NSArray *fileItems = [self getFileItems];
    
    if (fileItems && [fileItems count] > 0) {
        NSString *baseContentPath = [[ContentSyncManager sharedInstance] baseAppContentPath];
        NSRange baseContentPathRange = [path rangeOfString:baseContentPath];
        
        if (baseContentPathRange.location != NSNotFound) {
            NSString *lookupPath = [path substringFromIndex:baseContentPathRange.location];
            for (ContentItem *item in fileItems) {
                if ([item.path isEqualToString:lookupPath]) {
                    return item;
                }
            }
         }  
    }
    
    return nil;
}

@end
