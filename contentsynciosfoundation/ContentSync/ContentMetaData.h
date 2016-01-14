//
//  ContentMetaData.h
//  ToloApp
//
//  Created by Torey Lomenda on 6/22/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ContentItem.h"

@interface ContentMetaData : NSObject {
    NSString *generatedOn;
    ContentItem *contentRoot;
}

@property (nonatomic, strong) NSString *generatedOn;
@property (nonatomic, strong) ContentItem *contentRoot;

- (id) initWithJsonData: (NSDictionary *) jsonData;

- (NSArray *) getDirItems;
- (NSArray *) getFileItems;
- (NSArray *) getSymlinkItems;

- (ContentItem *) getContentItemAtPath: (NSString *) path;

@end
