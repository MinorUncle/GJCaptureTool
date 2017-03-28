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
#import "GJLivePushDefine.h"
@class UIView;
typedef enum _GJPlayStatus{
    kPlayStatusStop,
    kPlayStatusRunning,
    kPlayStatusPause,
    kPlayStatusBuffering,
}GJPlayStatus;



@interface GJPlayer : NSObject
@property(readonly,nonatomic)UIView* displayView;
@property(readonly,nonatomic)GJCacheInfo cache;


@property(assign,nonatomic)AudioStreamBasicDescription audioFormat;

-(void)start;
-(void)stop;
-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(int64_t)pts;
-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(int64_t)pts;
@end
 
