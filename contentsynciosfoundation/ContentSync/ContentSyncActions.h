//
//  ContentSyncActions.h
//  ToloApp
//
//  Created by Torey Lomenda on 6/22/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ContentMetaData.h"

@interface ContentSyncActions : NSObject {
    NSMutableArray *removeContentItems;
    NSMutableArray *addContentItems;
    NSMutableArray *modifyContentItems;
    
    NSMutableArray *symlinkItemsToCreate;
    NSMutableArray *downloadItemsRemaining;
    
    BOOL structureChanged;
}

@property (nonatomic, readonly) NSArray *removeContentItems;
@property (nonatomic, readonly) NSArray *addContentItems;
@property (nonatomic, readonly) NSArray *modifyContentItems;

@property (nonatomic, readonly) NSArray *symlinkItemsToCreate;
@property (nonatomic, readonly) NSArray *downloadItemsRemaining;

@property (nonatomic, readonly) BOOL structureChanged;

- (void) determineSyncActions:(ContentMetaData *) appContentMetaData updatedContentMetaData: (ContentMetaData *) sharedWebContentMetaData;
- (void) determineSyncActions:(ContentMetaData *) appContentMetaData updatedContentMetaData: (ContentMetaData *) sharedWebContentMetaData forceSync:(BOOL) forceSync;

- (void) determineSyncActions:(ContentMetaData *) appContentMetaData updatedContentMetaData: (ContentMetaData *) sharedWebContentMetaData compareStructureData:(BOOL)doCompare;
- (void) determineSyncActions:(ContentMetaData *) appContentMetaData updatedContentMetaData: (ContentMetaData *) sharedWebContentMetaData compareStructureData:(BOOL)doCompare forceSync: (BOOL) forceSync;

- (void) clearSyncActions;
- (void) removeItemToDownload: (ContentItem *) removeItem;
- (BOOL) hasItemsToDownload;
- (BOOL) hasItemsForAppToApply;

- (BOOL) isTextFile: (NSString *) fileName;

- (NSInteger) totalItemsToApply;
- (NSInteger) totalSymLinksToApply;
- (NSInteger) totalItemsToDownload;

@end
