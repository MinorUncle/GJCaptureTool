//
//  GJAudioQueueRecoder.h
//  GJCaptureTool
//
//  Created by mac on 17/1/19.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import "GJQueue.h"
@class GJAudioQueueRecoder;

typedef enum _RecoderStatus{
    kRecoderInvalidStatus = 0,
    kRecoderStopStatus,
    kRecoderRunningStatus,
    kRecoderPauseStatus,
}RecoderStatus;
@protocol GJAudioQueueRecoderDelegate <NSObject>
@optional

-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder*) recoder streamData:(RetainBuffer*)dataBuffer packetDescriptions:(const AudioStreamPacketDescription *)packetDescriptions;

@end
@interface GJAudioQueueRecoder : NSObject
@property(nonatomic,assign)int maxOutSize;
@property(nonatomic,assign,readonly)AudioStreamBasicDescription format;
@property(nonatomic,weak)id<GJAudioQueueRecoderDelegate> delegate;
@property(nonatomic,assign,readonly)RecoderStatus status;

- (instancetype)initWithStreamWithSampleRate:(Float64)sampleRate channel:(UInt32)channel formatID:(UInt32)formatID;

-(BOOL)startRecodeAudio;
-(void)stop;
@end
