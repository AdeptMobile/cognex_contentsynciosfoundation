//
//  ContentMetaDataTests.m
//  ToloApp
//
//  Created by Torey Lomenda on 7/12/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//
#import <SenTestingKit/SenTestingKit.h>

#import "ContentSyncActions.h"
#import "CJSONDeserializer.h"

@interface ContentMetaDataTests : SenTestCase 

- (void) testLoadContentMetaDataFromJson;
- (void) testGetContentItemTypes;

- (void) testDetermineSyncActions;

@end

@interface ContentMetaDataTests()

- (NSString *) loadContentMetaData;
- (NSString *) loadContentMetaDataChanges;

- (ContentMetaData *) buildContentMetaData;
- (ContentMetaData *) buildContentMetaDataChanges;

@end

@implementation ContentMetaDataTests

- (void) testLoadContentMetaDataFromJson {
    ContentMetaData *originalContentMetadata = nil;
    ContentMetaData *changesContentMetadata = nil;
    
    NSError *jsonError = nil;
    
    // Load the original content metadata
    NSString *metadataJson = [self loadContentMetaData];
    
    STAssertNotNil(metadataJson, @"I expected this to have a value");
    
    NSDictionary *jsonData = (NSDictionary *) [[CJSONDeserializer deserializer] 
                                               deserializeAsDictionary:[metadataJson dataUsingEncoding:NSUTF8StringEncoding] error:&jsonError];
    
    STAssertNil(jsonError, @"ERROR not nil:  %@", jsonError);
    originalContentMetadata = [[ContentMetaData alloc] initWithJsonData:jsonData];
    
    STAssertTrue([originalContentMetadata.generatedOn isEqualToString:@"2011-07-15 00:00:00"], @"Expected generatedOn date to match");
    
    STAssertNotNil(originalContentMetadata, @"Expected this to be populated");
    
    // Test changed content metadata
    metadataJson = [self loadContentMetaDataChanges];
    jsonData = (NSDictionary *) [[CJSONDeserializer deserializer] 
                                 deserializeAsDictionary:[metadataJson dataUsingEncoding:NSUTF8StringEncoding] error:&jsonError];
    STAssertNil(jsonError, @"ERROR not nil:  %@", jsonError);
    changesContentMetadata = [[ContentMetaData alloc] initWithJsonData:jsonData];
    STAssertNotNil(changesContentMetadata, @"Expected this to be populated");
}

- (void) testGetContentItemTypes {
    NSError *jsonError = nil;
    NSString *metadataJson = [self loadContentMetaData];
    NSDictionary *jsonData = (NSDictionary *) [[CJSONDeserializer deserializer] 
                                               deserializeAsDictionary:[metadataJson dataUsingEncoding:NSUTF8StringEncoding] error:&jsonError];
    ContentMetaData * originalContentMetadata = [[ContentMetaData alloc] initWithJsonData:jsonData];
    
    NSArray *fileItems = [originalContentMetadata getFileItems];
    NSArray *symlinkItems = [originalContentMetadata getSymlinkItems];
    NSArray *dirItems = [originalContentMetadata getDirItems];
    
    STAssertTrue([fileItems count] == 4, @"Expected 4 file items");
    STAssertTrue([symlinkItems count] == 2, @"Expected 2 symlink items");
    STAssertTrue([dirItems count] == 4, @"Expected 4 directory items");
}

- (void) testDetermineSyncActions {
    ContentSyncActions *syncActions = [[ContentSyncActions alloc] init];
    
    ContentMetaData *currentMetaData = [self buildContentMetaData];
    ContentMetaData *latestMetaData = [self buildContentMetaDataChanges];
    
    // Expect no sync actions
    [syncActions determineSyncActions:currentMetaData updatedContentMetaData:currentMetaData];
    
    STAssertTrue([syncActions.removeContentItems count] == 0, @"Expected No Sync Actions!!");
    
    // Expect sync actions
    [syncActions determineSyncActions:currentMetaData updatedContentMetaData:latestMetaData];
  
    STAssertTrue([syncActions.removeContentItems count] == 2 
                    && [syncActions.addContentItems count] == 2
                    && [syncActions.modifyContentItems count] == 2, @"Expected Sync Actions!!");
    STAssertTrue([syncActions.downloadItemsRemaining count] == 2, @"Expected Downloads List with size %d !!", [syncActions.downloadItemsRemaining count]);
    
}

#pragma mark -
#pragma mark Private methods
- (NSString *) loadContentMetaData {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    
    NSString *path = [bundle pathForResource:@"content-original" ofType:@"json"];
    NSString *jsonString = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    
    return jsonString;
}

- (NSString *) loadContentMetaDataChanges {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    
    NSString *path = [bundle pathForResource:@"content-changes" ofType:@"json"];
    NSString *jsonString = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    
    return jsonString;
}

- (ContentMetaData *) buildContentMetaData {
    NSError *jsonError = nil;
    NSString *metadataJson = [self loadContentMetaData];
    NSDictionary *jsonData = (NSDictionary *) [[CJSONDeserializer deserializer] 
                                               deserializeAsDictionary:[metadataJson dataUsingEncoding:NSUTF8StringEncoding] error:&jsonError];
    ContentMetaData *metadata = [[ContentMetaData alloc] initWithJsonData:jsonData];
    return metadata;
}

- (ContentMetaData *) buildContentMetaDataChanges {
    NSError *jsonError = nil;
    NSString *metadataJson = [self loadContentMetaDataChanges];
    NSDictionary *jsonData = (NSDictionary *) [[CJSONDeserializer deserializer] 
                                               deserializeAsDictionary:[metadataJson dataUsingEncoding:NSUTF8StringEncoding] error:&jsonError];
    ContentMetaData *metadata = [[ContentMetaData alloc] initWithJsonData:jsonData];
    return metadata;
}

@end


