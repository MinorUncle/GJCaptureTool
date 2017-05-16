//
//  GJAudioQueueRecoder.h
//  GJCaptureTool
//
//  Created by mac on 17/1/19.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreMedia/CMTime.h>
#import "GJRetainBuffer.h"
#import "GJLiveDefine+internal.h"
@class GJAudioQueueRecoder;

typedef enum _RecoderStatus{
    kRecoderInvalidStatus = 0,
    kRecoderStopStatus,
    kRecoderRunningStatus,
    kRecoderPauseStatus,
}RecoderStatus;
@protocol GJAudioQueueRecoderDelegate <NSObject>
@optional

-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder*) recoder aacPacket:(R_GJAACPacket*)packet;
-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder*) recoder pcmPacket:(R_GJPCMPacket*)packet;


@end
@interface GJAudioQueueRecoder : NSObject
@property(nonatomic,assign)int maxOutSize;
@property(nonatomic,assign,readonly)AudioStreamBasicDescription format;
@property(nonatomic,weak)id<GJAudioQueueRecoderDelegate> delegate;
@property(nonatomic,assign,readonly)RecoderStatus status;

/**
 回调延迟，越小消耗越大，默认0.2,单位s
 */
@property(nonatomic,assign)float callbackDelay;


- (instancetype)initWithStreamWithSampleRate:(Float64)sampleRate channel:(UInt32)channel formatID:(UInt32)formatID;

-(BOOL)startRecodeAudio;
-(void)stop;
@end
