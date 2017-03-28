//
//  GJPlayer.h
//  GJCaptureTool
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CMTime.h>
#import <CoreVideo/CVImageBuffer.h>
#import <AVFoundation/AVFoundation.h>
#import "GJRetainBuffer.h"
@class UIView;
typedef enum _GJPlayStatus{
    kPlayStatusStop,
    kPlayStatusRunning,
    kPlayStatusPause,
    kPlayStatusBuffering,
}GJPlayStatus;

typedef struct CacheInfo{
    int cacheTime;//ms
    int cacheCount;
}CacheInfo;

@interface GJPlayer : NSObject
@property(readonly,nonatomic)UIView* displayView;
@property(readonly,nonatomic)CacheInfo cache;


@property(assign,nonatomic)AudioStreamBasicDescription audioFormat;

-(void)start;
-(void)stop;
-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(uint64_t)pts;
-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(uint64_t)pts;
@end
 
