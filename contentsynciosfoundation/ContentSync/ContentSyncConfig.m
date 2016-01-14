//
//  ContentSyncConfig.m
//  ContentSync
//
//  Created by Torey Lomenda on 1/30/13.
//  Copyright (c) 2013 NA. All rights reserved.
//

#import "ContentSyncConfig.h"

@implementation ContentSyncConfig

@synthesize contentMetaDataUrl = _contentMetaDataUrl;
@synthesize contentStructureUrl = _contentStructureUrl;
@synthesize localContentDocPath = _localContentDocPath;
@synthesize localContentRoot = _localContentRoot;
@synthesize localSyncRoot = _localSyncRoot;
@synthesize bundledContentZipFile = _bundledContentZipFile;
@synthesize alertTitle = _alertTitle;
@synthesize jsonAuthRequired = _jsonAuthRequired;
@synthesize downloadFilteringEnabled = _downloadFilteringEnabled;
@synthesize videoFilteringEnabled = _videoFilteringEnabled;
@synthesize presentationFilteringEnabled = _presentationFilteringEnabled;

@synthesize isStructureEnabled = _isStructureEnabled;

#pragma mark - init/dealloc
- (id) init {
    self = [super init];
    
    if (self) {
        // Configure anything here
    }
    
    return self;
}


#pragma mark - Accessor Methods

#pragma mark - Public Methods

#pragma mark - Private Methods

@end
