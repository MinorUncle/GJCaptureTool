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
#import "GJRetainBuffer.h"
@class UIView;
typedef enum _GJPlayStatus{
    kPlayStatusStop,
    kPlayStatusRunning,
    kPlayStatusPause,
    kPlayStatusBuffering,
}GJPlayStatus;
@interface GJPlayer : NSObject
@property(readonly,nonatomic)UIView* displayView;
@property(readonly,nonatomic)long cacheTime;

-(void)start;
-(void)stop;
-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(CMTime)pts;
-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(CMTime)pts;
@end
 
