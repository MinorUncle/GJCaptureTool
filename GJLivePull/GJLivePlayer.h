//
//  GJLivePlayer.h
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
#import "GJLiveDefine.h"
@class UIView;
@class GJLivePlayer;
typedef enum _GJPlayStatus{
    kPlayStatusStop,
    kPlayStatusRunning,
    kPlayStatusPause,
    kPlayStatusBuffering,
}GJPlayStatus;


@protocol GJLivePlayerDeletate <NSObject>

-(void)livePlayer:(GJLivePlayer*)livePlayer bufferUpdatePercent:(float)percent duration:(long)duration;

@end



@interface GJLivePlayer : NSObject
@property(readonly,nonatomic)UIView* displayView;
@property(weak,nonatomic)id<GJLivePlayerDeletate> delegate;


@property(assign,nonatomic)AudioStreamBasicDescription audioFormat;

-(void)start;
-(void)stop;
-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(int64_t)pts;
-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(int64_t)pts;
-(GJCacheInfo)getVideoCache;
-(GJCacheInfo)getAudioCache;
#ifdef NETWORK_DELAY
-(long)getNetWorkDelay;
#endif

@end

