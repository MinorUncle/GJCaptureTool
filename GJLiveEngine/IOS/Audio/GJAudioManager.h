//
//  GJAudioManager.h
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/7/1.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>


#import "GJAudioSessionCenter.h"
#import "AudioUnitCapture.h"
#import "AEAudioController.h"
#import "AEPlaythroughChannel.h"
#import "AEAudioSender.h"
#import "GJAudioMixer.h"
#import "AEBlockChannel.h"

@interface GJAudioManager : NSObject<GJAudioMixerDelegate>
{
    GJRetainBufferPool* _bufferPool;
}
@property (nonatomic, assign)BOOL mixToSream;
@property (nonatomic, retain)AEPlaythroughChannel* playthrough;
@property (nonatomic, retain)AEAudioFilePlayer* mixfilePlay;
@property (nonatomic, retain)AEAudioController *audioController;
@property (nonatomic, retain)GJAudioMixer* audioMixer;
@property (nonatomic, retain)AEBlockChannel* blockPlay;

@property (nonatomic, readonly) AEAudioReceiverCallback receiverCallback;

@property (nonatomic, copy)void(^audioCallback)(R_GJPCMFrame* frame);

+(GJAudioManager*)shareAudioManager;
-(instancetype)initWithFormat:(AudioStreamBasicDescription )audioFormat;
-(void)stopMix;
-(BOOL)mixFilePlayAtTime:(uint64_t)time;
-(BOOL)setMixFile:(NSURL*)file;
-(void)setMixToSream:(BOOL)mixToSream;
-(BOOL)enableAudioInEarMonitoring:(BOOL)enable;
-(BOOL)startRecode:(NSError**)error;
-(void)stopRecode;
@end
