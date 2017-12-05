//
//  GJAudioManager.m
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/7/1.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJAudioManager.h"
#import "GJLog.h"

#define PCM_FRAME_COUNT 1024

//static GJAudioManager* _staticManager;
@interface GJAudioManager () {
    R_GJPCMFrame *_alignCacheFrame;
    GInt32        _sizePerPacket;
    float         _durPerSize;
    NSMutableDictionary<id,id<AEAudioPlayable>>* _mixPlayers;
}
@end

@implementation GJAudioManager
//+(GJAudioManager*)shareAudioManager{
//    return nil;
//};

- (instancetype)initWithFormat:(AudioStreamBasicDescription)audioFormat {
    self = [super init];
    if (self) {
        NSError *error;
        _mixToSream = YES;
        _mixPlayers = [NSMutableDictionary dictionaryWithCapacity:2];
        if (audioFormat.mFramesPerPacket > 1) {
            _sizePerPacket               = audioFormat.mFramesPerPacket * audioFormat.mBytesPerFrame;
            audioFormat.mFramesPerPacket = 0;
        } else {
            _sizePerPacket = PCM_FRAME_COUNT * audioFormat.mBytesPerFrame;
        }
        [[GJAudioSessionCenter shareSession] setPrefferSampleRate:audioFormat.mSampleRate error:&error];

        if (error != nil) {
            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "setPrefferSampleRate error:%s", error.description.UTF8String);
        }

        _audioController                    = [[AEAudioController alloc] initWithAudioDescription:audioFormat inputEnabled:YES];
        _audioController.useMeasurementMode = YES;
        //        [_audioController setPreferredBufferDuration:0.023];

        _durPerSize = 1000.0 / _audioController.audioDescription.mSampleRate / _audioController.audioDescription.mBytesPerFrame;
#ifdef AUDIO_SEND_TEST
        _audioMixer = [[AEAudioSender alloc] init];

#else
        _audioMixer = [[GJAudioMixer alloc] init];
#endif
        _audioMixer.delegate = self;
        [_audioController addInputReceiver:_audioMixer];
        //        _staticManager = self;
        self.mixToSream = YES;

        //        _blockPlay = [AEBlockChannel channelWithBlock:^(const AudioTimeStamp *time, UInt32 frames, AudioBufferList *audio) {
        //            for (int i = 0 ; i<audio->mNumberBuffers; i++) {
        //                memset(audio->mBuffers[i].mData, 20, audio->mBuffers[i].mDataByteSize);
        //            }
        //            NSLog(@"block play time:%f",time->mSampleTime);
        //        }];
        //        [_audioController addChannels:@[_blockPlay]];
    }
    return self;
}

- (void)audioMixerProduceFrameWith:(AudioBufferList *)frame time:(int64_t)time {
    //    R_GJPCMFrame* pcmFrame = NULL;
    //    printf("audio size:%d chchesize:%d pts:%lld\n",frame->mBuffers[0].mDataByteSize,_alignCacheFrame->retain.size,time);
    int needSize = _sizePerPacket - R_BufferSize(&_alignCacheFrame->retain);
    int leftSize = frame->mBuffers[0].mDataByteSize;
    while (leftSize >= needSize) {
        R_BufferWriteAppend(&_alignCacheFrame->retain, frame->mBuffers[0].mData + frame->mBuffers[0].mDataByteSize - leftSize, needSize);
        _alignCacheFrame->channel = frame->mBuffers[0].mNumberChannels;
        _alignCacheFrame->pts     = time - (GInt64)(R_BufferSize(&_alignCacheFrame->retain) * _durPerSize);

        static int64_t pre;
        if (pre == 0) {
            pre = _alignCacheFrame->pts;
        }
        //        printf("audio pts:%lld,size:%d dt:%lld\n",_alignCacheFrame->pts,_alignCacheFrame->retain.size,_alignCacheFrame->pts-pre);
        pre = _alignCacheFrame->pts;
        self.audioCallback(_alignCacheFrame);
        R_BufferUnRetain(&_alignCacheFrame->retain);
        time             = time + needSize / _durPerSize;
        _alignCacheFrame = (R_GJPCMFrame *) GJRetainBufferPoolGetSizeData(_bufferPool, _sizePerPacket);
        leftSize         = leftSize - needSize;
        needSize         = _sizePerPacket;
    }
    if (leftSize > 0) {
        _alignCacheFrame->pts = (GInt64) time;
        R_BufferWriteAppend(&_alignCacheFrame->retain, frame->mBuffers[0].mData + frame->mBuffers[0].mDataByteSize - leftSize, leftSize);
    }
}

-(void)addMixPlayer:(id<AEAudioPlayable>)player key:(id <NSCopying>)key{
    if (![_mixPlayers.allKeys containsObject:key]) {
        [_mixPlayers setObject:player forKey:key];
        [_audioController addChannels:@[player]];
        if (_mixPlayers.count == 1) {
            [_audioController addOutputReceiver:_audioMixer];
        }
    }
}
-(void)removeMixPlayerWithkey:(id <NSCopying>)key{
    if ([_mixPlayers.allKeys containsObject:key]) {
        id<AEAudioPlayable> player = _mixPlayers[key];
        [_mixPlayers removeObjectForKey:key];
        if (_mixPlayers.count == 0) {
            [_audioController removeOutputReceiver:_audioMixer];
        }
        [_audioController removeChannels:@[player]];
    }
}

- (BOOL)startRecode:(NSError **)error {
    GJRetainBufferPoolCreate(&_bufferPool, 1, GTrue, R_GJPCMFrameMalloc, GNULL, GNULL);
    _alignCacheFrame = (R_GJPCMFrame *) GJRetainBufferPoolGetSizeData(_bufferPool, _sizePerPacket);

    NSError *configError;
    [[GJAudioSessionCenter shareSession] lockBeginConfig];
    [[GJAudioSessionCenter shareSession] requestPlay:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] requestRecode:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] requestDefaultToSpeaker:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] requestAllowAirPlay:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] unLockApplyConfig:&configError];
    if (configError) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "Apply audio session Config error:%@", configError.description.UTF8String);
    }
    if (![_audioController start:error]) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "AEAudioController start error:%@", (*error).description.UTF8String);
    }

    return *error == nil;
}
- (void)stopRecode {

    [_audioController stop];
    NSError *configError;
    [[GJAudioSessionCenter shareSession] lockBeginConfig];
    [[GJAudioSessionCenter shareSession] requestPlay:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] requestRecode:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] requestDefaultToSpeaker:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] requestAllowAirPlay:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] unLockApplyConfig:&configError];
    if (configError) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "Apply audio session Config error:%@", configError.description.UTF8String);
    }

    if (_alignCacheFrame) {
        R_BufferUnRetain(&_alignCacheFrame->retain);
        _alignCacheFrame = GNULL;
    }
    if (_bufferPool) {
        GJRetainBufferPool *pool = _bufferPool;
        _bufferPool              = GNULL;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, GTrue);
            GJRetainBufferPoolFree(pool);
        });
    }
}

- (AEPlaythroughChannel *)playthrough {
    if (_playthrough == nil) {
        _playthrough = [[AEPlaythroughChannel alloc] init];
    }
    return _playthrough;
}

- (BOOL)enableAudioInEarMonitoring:(BOOL)enable {
    if (enable) {
        //关闭麦克风接受，打开播放接受
        [_audioController removeInputReceiver:_audioMixer];
        [_audioController addInputReceiver:self.playthrough];
        [self addMixPlayer:self.playthrough key:self.playthrough.description];
    } else {
        [self removeMixPlayerWithkey:self.playthrough.description];
        [_audioController addInputReceiver:_audioMixer];
        [_audioController removeInputReceiver:self.playthrough];
    }
    return GTrue;
}

- (BOOL)enableReverb:(BOOL)enable {
    if (_reverb == nil) {
        _reverb           = [[AEReverbFilter alloc] init];
        _reverb.dryWetMix = 80;
    }

    if (enable) {
        [_audioController addFilter:_reverb];
    }
    {
        [_audioController removeFilter:_reverb];
    }
    return NO;
}

- (void)setMixToSream:(BOOL)mixToSream {
    _mixToSream = mixToSream;
#ifndef AUDIO_SEND_TEST
    if (_mixToSream) {
        [_audioMixer removeIgnoreSource:_audioController.topGroup];
    } else {
        [_audioMixer addIgnoreSource:_audioController.topGroup];
    }
#endif
}
- (BOOL)setMixFile:(NSURL*)file finish:(MixFinishBlock)finishBlock {
    if (_mixfilePlay != nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "上一个文件没有关闭，自动关闭");
        [self removeMixPlayerWithkey:_mixfilePlay.description];
        _mixfilePlay = nil;
    }
    NSError *error;
    _mixfilePlay = [[AEAudioFilePlayer alloc] initWithURL:file error:&error];
    if (_mixfilePlay == nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "AEAudioFilePlayer alloc error:%s", error.localizedDescription.UTF8String);
        return GFalse;
    } else {
        __weak GJAudioManager* wkSelf = self;
        _mixfilePlay.completionBlock   = ^{
            if (finishBlock) {
                finishBlock(GTrue);
            }
            [wkSelf removeMixPlayerWithkey:wkSelf.mixfilePlay.description];
            wkSelf.mixfilePlay.completionBlock = nil;
        };
        [self addMixPlayer:_mixfilePlay key:_mixfilePlay.description];
        return GTrue;
    }
}
- (BOOL)mixFilePlayAtTime:(uint64_t)time {
    if (_mixfilePlay) {
        [_mixfilePlay playAtTime:time];
        return YES;
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "请先设置minx file");
        return NO;
    }
}
- (void)stopMix {
    if (_mixfilePlay == nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "重复stop mix");
    } else {
        [self removeMixPlayerWithkey:_mixfilePlay.description];
        _mixfilePlay = nil;
    }
}
- (void)dealloc {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJAudioManager dealloc");
    if (_bufferPool) {
        [self stopRecode];
    }
    [_audioController removeInputReceiver:_audioMixer];
    [_audioController removeChannels:_mixPlayers.allValues];
}
@end
