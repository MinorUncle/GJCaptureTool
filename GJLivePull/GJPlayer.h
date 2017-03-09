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

@interface GJPlayer : NSObject
@property(readonly,nonatomic)UIView* displayView;

-(void)start;
-(void)stop;
-(void)addVideoDataWith:(CVImageBufferRef)imageData pts:(CMTime)pts;
-(void)addAudioDataWith:(GJRetainBuffer*)audioData pts:(CMTime)pts;
@end
 
