//
//  ContentSyncConfig.h
//  ContentSync
//
//  Created by Torey Lomenda on 1/30/13.
//  Copyright (c) 2013 NA. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ContentSyncConfig : NSObject

@property (nonatomic, strong) NSURL *contentMetaDataUrl;
@property (nonatomic, strong) NSURL *contentStructureUrl;
@property (nonatomic, strong) NSString *localContentDocPath;
@property (nonatomic, strong) NSString *localContentRoot;
@property (nonatomic, strong) NSString *localSyncRoot;
@property (nonatomic, strong) NSString *bundledContentZipFile;
@property (nonatomic, strong) NSString *alertTitle;
@property (nonatomic, assign) BOOL jsonAuthRequired;
@property (nonatomic, assign) BOOL downloadFilteringEnabled;
@property (nonatomic, assign) BOOL videoFilteringEnabled;
@property (nonatomic, assign) BOOL presentationFilteringEnabled;

@property (nonatomic, assign, getter=isStructureEnabled) BOOL isStructureEnabled;

@end
