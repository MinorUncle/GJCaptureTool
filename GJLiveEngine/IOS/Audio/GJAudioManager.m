 //
//  GJAudioManager.m
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/7/1.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJAudioManager.h"
#import "GJLog.h"

static GJAudioManager* _staticManager;
@implementation GJAudioManager
+(GJAudioManager*)shareAudioManager{
    return _staticManager;
};

-(instancetype)initWithFormat:(AudioStreamBasicDescription )audioFormat{
    self = [super init];
    if (self) {
        NSError* error;
        _mixToSream = YES;
        [[GJAudioSessionCenter shareSession] setPrefferSampleRate:audioFormat.mSampleRate error:&error];
       
        if (error != nil) {
            GJLOG(GJ_LOGERROR, "setPrefferSampleRate error:%s",error.description.UTF8String);
        }
        _audioController = [[AEAudioController alloc]initWithAudioDescription:audioFormat inputEnabled:YES];
        _audioController.useMeasurementMode = YES;
        [_audioController setPreferredBufferDuration:0.023];
        _audioMixer = [[GJAudioMixer alloc]init];
        _audioMixer.delegate = self;
        [_audioController addInputReceiver:_audioMixer];
        _staticManager = self;
        self.mixToSream = YES;
        
        //        _blockPlay = [AEBlockChannel channelWithBlock:^(const AudioTimeStamp *time, UInt32 frames, AudioBufferList *audio) {
        //            for (int i = 0 ; i<audio->mNumberBuffers; i++) {
        //                memset(audio->mBuffers[i].mData, 20, audio->mBuffers[i].mDataByteSize);
        //            }
        //            NSLog(@"block play time:%f",time->mSampleTime);
        //        }];
        //        [_audioController addChannels:@[_blockPlay]];
        GJRetainBufferPoolCreate(&_bufferPool, 0, GTrue, R_GJPCMFrameMalloc, GNULL);
    }
    return self;
}

-(void)audioMixerProduceFrameWith:(AudioBufferList *)frame time:(int64_t)time{
    static int64_t p;
    if (p == 0) {
        p = time;
    }
    p = time;
    R_GJPCMFrame* pcmFrame = (R_GJPCMFrame*)GJRetainBufferPoolGetSizeData(_bufferPool, frame->mBuffers[0].mDataByteSize);
    memcpy(pcmFrame->retain.data, frame->mBuffers[0].mData, frame->mBuffers[0].mDataByteSize);
    pcmFrame->channel = frame->mBuffers[0].mNumberChannels;
    pcmFrame->pts = (GInt64)time;
    pcmFrame->retain.size = frame->mBuffers[0].mDataByteSize;
    self.audioCallback(pcmFrame);
    retainBufferUnRetain(&pcmFrame->retain);
}

-(BOOL)startRecode:(NSError**)error{
    NSError* configError;
    [[GJAudioSessionCenter shareSession] lockBeginConfig];
    [[GJAudioSessionCenter shareSession]requestPlay:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession]requestRecode:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession]requestDefaultToSpeaker:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession]requestAllowAirPlay:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] unLockApplyConfig:&configError];
    if (configError) {
        GJLOG(GJ_LOGERROR, "Apply audio session Config error:%@",configError.description.UTF8String);
    }
    if (![_audioController start:error]) {
        GJLOG(GJ_LOGERROR, "AEAudioController start error:%@",(*error).description.UTF8String);
    }
    return *error == nil;
}
-(void)stopRecode{
    [_audioController stop];
    NSError* configError;
    [[GJAudioSessionCenter shareSession] lockBeginConfig];
    [[GJAudioSessionCenter shareSession]requestPlay:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession]requestRecode:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession]requestDefaultToSpeaker:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession]requestAllowAirPlay:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] unLockApplyConfig:&configError];
    if (configError) {
        GJLOG(GJ_LOGERROR, "Apply audio session Config error:%@",configError.description.UTF8String);
    }
}
-(AEPlaythroughChannel *)playthrough{
    if (_playthrough == nil) {
        _playthrough = [[AEPlaythroughChannel alloc]init];
    }
    return _playthrough;
}

-(BOOL)enableAudioInEarMonitoring:(BOOL)enable{
    if (enable) {
        [_audioController addInputReceiver:self.playthrough];
        [_audioController addChannels:@[self.playthrough]];
    }else{
        [_audioController removeChannels:@[self.playthrough]];
        [_audioController removeInputReceiver:self.playthrough];
    }
    return GTrue;
}
-(void)setMixToSream:(BOOL)mixToSream{
    _mixToSream = mixToSream;
    if (_mixToSream) {
        [_audioMixer removeIgnoreSource:_audioController.topGroup];
    }else{
        [_audioMixer addIgnoreSource:_audioController.topGroup];
    }
}
-(BOOL)setMixFile:(NSURL*)file{
    if (_mixfilePlay != nil) {
        GJLOG(GJ_LOGWARNING, "上一个文件没有关闭，自动关闭");
        [_audioController removeChannels:@[_mixfilePlay]];
        _mixfilePlay = nil;
    }
    NSError* error;
    _mixfilePlay = [[AEAudioFilePlayer alloc]initWithURL:file error:&error];
    if (_mixfilePlay == nil) {
        GJLOG(GJ_LOGERROR, "AEAudioFilePlayer alloc error:%s",error.localizedDescription.UTF8String);
        return GFalse;
    }else{
        __weak AEAudioController * wkAE = _audioController;
        __weak GJAudioMixer *wkM = _audioMixer;
        _mixfilePlay.completionBlock = ^{
            [wkAE removeOutputReceiver:wkM];
        };
        [_audioController addChannels:@[_mixfilePlay]];
        [_audioController addOutputReceiver:_audioMixer];
        return GTrue;
    }
}
-(BOOL)mixFilePlayAtTime:(uint64_t)time{
    if (_mixfilePlay) {
        [_mixfilePlay playAtTime:time];
        return YES;
    }else{
        GJLOG(GJ_LOGERROR, "请先设置minx file");
        return NO;
    }
}
-(void)stopMix{
    if (_mixfilePlay == nil) {
        GJLOG(GJ_LOGWARNING, "重复stop mix");
    }else{
        [_audioController removeChannels:@[_mixfilePlay]];
        [_audioController removeOutputReceiver:_audioMixer];
        _mixfilePlay = nil;
    }
}
-(void)dealloc{
    GJLOG(GJ_LOGDEBUG, "GJAudioManager dealloc");
    [_audioController removeInputReceiver:_audioMixer];
    NSMutableArray* play = [NSMutableArray arrayWithCapacity:2];
    
    if (_mixfilePlay) {
        [play addObject:_mixfilePlay];
        [_audioController removeOutputReceiver:_audioMixer];
    }
    if (_playthrough) {
        [play addObject:_playthrough];
        [_audioController removeInputReceiver:_playthrough];
    }
    [_audioController removeChannels:play];
    
 
}
@end
