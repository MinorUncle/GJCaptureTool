//
//  GJLivePush+advanced.h
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GJLivePush.h"

@interface GJLivePush (advanced)
- (void)setStreamFlipDirection:(GJLiveStreamFlipDirection)direction;

- (BOOL)startRecordWithPath:(NSURL*)path;

- (void)stopRecord;
@end
