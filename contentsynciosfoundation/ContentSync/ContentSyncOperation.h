//
//  ContentSyncOperation.h
//  ToloApp
//
//  Created by Torey Lomenda on 7/18/11.
//  Copyright 2011 Object Partners Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ContentSyncOperation : NSOperation {
    float downloadTotalBytes;
    float downloadBytesRead;
}

@property (nonatomic, assign) float downloadTotalBytes;
@property (nonatomic, assign) float downloadBytesRead;

- (float) downloadProgress;

@end
