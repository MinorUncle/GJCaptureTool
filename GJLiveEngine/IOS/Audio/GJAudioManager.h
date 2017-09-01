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
#import "AEReverbFilter.h"
//#define AUDIO_SEND_TEST
#ifdef AUDIO_SEND_TEST
#import "AEAudioSender.h"
#else
#import "GJAudioMixer.h"
#endif

#import "AEBlockChannel.h"
#ifdef AUDIO_SEND_TEST
@interface GJAudioManager : NSObject<AEAudioSenderDelegate>
#else
@interface GJAudioManager : NSObject<GJAudioMixerDelegate>
#endif
{
    GJRetainBufferPool* _bufferPool;
}
@property (nonatomic, assign)BOOL mixToSream;
@property (nonatomic, retain)AEPlaythroughChannel* playthrough;
@property (nonatomic, retain)AEAudioFilePlayer* mixfilePlay;
@property (nonatomic, retain)AEAudioController *audioController;
@property (nonatomic, retain)AEReverbFilter *reverb;

#ifdef AUDIO_SEND_TEST
@property (nonatomic, retain)AEAudioSender* audioMixer;
#else
@property (nonatomic, retain)GJAudioMixer* audioMixer;
#endif
@property (nonatomic, retain)AEBlockChannel* blockPlay;

@property (nonatomic, readonly) AEAudioReceiverCallback receiverCallback;

@property (nonatomic, copy)void(^audioCallback)(R_GJPCMFrame* frame);

//+(GJAudioManager*)shareAudioManager;
-(instancetype)initWithFormat:(AudioStreamBasicDescription )audioFormat;
-(void)stopMix;
-(BOOL)mixFilePlayAtTime:(uint64_t)time;
-(BOOL)setMixFile:(NSURL*)file;
-(void)setMixToSream:(BOOL)mixToSream;
-(BOOL)enableAudioInEarMonitoring:(BOOL)enable;
-(BOOL)enableReverb:(BOOL)enable;
-(BOOL)startRecode:(NSError**)error;
-(void)stopRecode;
@end
