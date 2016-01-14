//
//  UpackContentOperation.h
//  ToloApp
//
//  Created by Torey Lomenda on 7/11/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZipArchive.h"

#import "ContentSyncManager.h"

@interface UnpackContentOperation : NSOperation<ZipArchiveDelegate> {
    id<ContentUnpackDelegate> __weak delegate;
    
    BOOL doUnpackInitial;
}

@property (nonatomic, weak) id<ContentUnpackDelegate> delegate;
@property (nonatomic, assign, getter=isDoUnpackInitial) BOOL doUnpackInitial;

@end
