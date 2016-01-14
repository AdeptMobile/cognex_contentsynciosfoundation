//
//  ContentItem.h
//  ToloApp
//
//  Created by Torey Lomenda on 7/12/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface ContentItem : NSObject {
    BOOL isRoot;
    NSString *path;
    NSString *name;
    BOOL isDirectory;
    BOOL mustSync;
    
    NSString *symlink;
    
    NSString  *downloadUrl;
    NSInteger fileSize;
    NSString  *modifiedDate;
    
    NSMutableArray *contentItemList;
}

@property (nonatomic, assign, getter=isRoot) BOOL isRoot;
@property (nonatomic, strong) NSString *path;
@property (nonatomic, strong) NSString *name;

// Symbolic Link indicator
@property (nonatomic, strong) NSString *symlink;

// File properties
@property (nonatomic, strong) NSString *downloadUrl;
@property (nonatomic, assign) NSInteger fileSize;
@property (nonatomic, strong) NSString *modifiedDate;

// Directory properties
@property (nonatomic, assign, getter=isDirectory) BOOL isDirectory;
@property (nonatomic, strong) NSMutableArray *contentItemList;
@property (nonatomic, assign) BOOL mustSync;

- (id) initWithJsonData: (NSDictionary *) jsonData isRoot: (BOOL) isRootItem;

- (BOOL) isFile;
- (BOOL) isSymbolicLink;

- (NSArray *) getAllDirItems;
- (NSArray *) getAllFileItems;
- (NSArray *) getAllSymlinkItems;

@end
