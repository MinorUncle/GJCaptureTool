//
//  GJAudioManager.m
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/7/1.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJAudioManager.h"
#import <AVFoundation/AVFoundation.h>
#import "GJLog.h"
#import "GJUtil.h"
#import "AutoLock.h"

#define PCM_FRAME_COUNT 1024

//static GJAudioManager* _staticManager;
@interface GJAudioManager () {
    R_GJPCMFrame *_alignCacheFrame;
    GInt32        _sizePerPacket;
    GLong         _sendFrameCount;
    GLong         _startTime; //ms
    NSMutableDictionary<id, id<AEAudioPlayable>> *_mixPlayers;
    BOOL _needResumeEarMonitoring;
}
@property (nonatomic, retain) NSRecursiveLock *lock;
@end
static AEAudioController *shareAudioController;
@implementation           GJAudioManager
//+(GJAudioManager*)shareAudioManager{
//    return nil;
//};
- (instancetype)init {
    self = [super init];
    if (self) {
        _mixToSream = YES;
        _lock       = [[NSRecursiveLock alloc] init];
        _mixPlayers = [NSMutableDictionary dictionaryWithCapacity:2];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotific:) name:AVAudioSessionRouteChangeNotification object:nil];
        GJRetainBufferPoolCreate(&_bufferPool, 1, GTrue, R_GJPCMFrameMalloc, GNULL, GNULL);
    }
    return self;
}

- (void)receiveNotific:(NSNotification *)notific {
    if ([notific.name isEqualToString:AVAudioSessionRouteChangeNotification]) {
        AVAudioSessionRouteChangeReason reson = [notific.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
        switch (reson) {
            case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
                //插入耳机
                if (self.audioInEarMonitoring) {
                    [self setAudioInEarMonitoring:NO];
                    _needResumeEarMonitoring = YES;
                }
                break;
            case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: {
                if (_needResumeEarMonitoring) {
                    [self setAudioInEarMonitoring:YES];
                }
                break;
            }
            default: {

                if ([AVAudioSession sharedInstance].currentRoute.outputs.count > 0 &&
                    [[AVAudioSession sharedInstance].currentRoute.outputs[0].portType isEqualToString:AVAudioSessionPortBuiltInReceiver]) {
                    GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "Fource AVAudioSessionPortBuiltInReceiver to AVAudioSessionPortOverrideSpeaker");
                    [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
                }
            } break;
        }
    }
}

- (instancetype)initWithFormat:(AudioStreamBasicDescription)audioFormat {
    //    self = [super init];
    //    if (self) {
    //
    //
    //
    //        //        _blockPlay = [AEBlockChannel channelWithBlock:^(const AudioTimeStamp *time, UInt32 frames, AudioBufferList *audio) {
    //        //            for (int i = 0 ; i<audio->mNumberBuffers; i++) {
    //        //                memset(audio->mBuffers[i].mData, 20, audio->mBuffers[i].mDataByteSize);
    //        //            }
    //        //            NSLog(@"block play time:%f",time->mSampleTime);
    //        //        }];
    //        //        [_audioController addChannels:@[_blockPlay]];
    //    }
    return [self init];
}

- (void)setAudioFormat:(AudioStreamBasicDescription)audioFormat {
    AUTO_LOCK(_lock);
    if (_audioController && _audioController.running) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "运行状态无法修改格式");
        return;
    }
    if ((int64_t) audioFormat.mSampleRate == (int64_t) _audioFormat.mSampleRate &&
        audioFormat.mChannelsPerFrame == _audioFormat.mChannelsPerFrame &&
        audioFormat.mFormatID == _audioFormat.mFormatID &&
        audioFormat.mBytesPerFrame == _audioFormat.mBytesPerFrame &&
        audioFormat.mFormatFlags == _audioFormat.mFormatFlags &&
        audioFormat.mBitsPerChannel == _audioFormat.mBitsPerChannel &&
        audioFormat.mBytesPerPacket == _audioFormat.mBytesPerPacket &&
        audioFormat.mFramesPerPacket == _audioFormat.mFramesPerPacket) {
        //无需修改
        return;
    }
    _audioFormat = audioFormat;
    NSError *error;
    if (_audioController) {
        [_audioController setAudioDescription:_audioFormat error:&error];
        if (error) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "setAudioDescription error");
        } else {
            _audioFormat = audioFormat;
        }
    }
    _sizePerPacket = PCM_FRAME_COUNT * audioFormat.mBytesPerFrame;
}

- (void)audioMixerProduceFrameWith:(AudioBufferList *)frame time:(int64_t)time {
    //time 为一帧结束时间，pts为一帧开始时间

    int64_t timeCount = (time - _startTime) * _audioFormat.mSampleRate / 1000;
    if (timeCount < _sendFrameCount - PCM_FRAME_COUNT) {
        GJLOG(GNULL, GJ_LOGWARNING, "采集数据过多，丢帧");
        return;
    }
    if (_mute) {
        memset(frame->mBuffers[0].mData, 0, frame->mBuffers[0].mDataByteSize);
    }
    if (_alignWithBlack) {
        while (timeCount > _sendFrameCount + 2 * PCM_FRAME_COUNT) {
            R_BufferWriteConst(&_alignCacheFrame->retain, 0, PCM_FRAME_COUNT * _audioFormat.mBytesPerFrame - R_BufferSize(&_alignCacheFrame->retain));
            _alignCacheFrame->channel = frame->mBuffers[0].mNumberChannels;
            _alignCacheFrame->pts     = GTimeMake(_sendFrameCount * 1000 / _audioFormat.mSampleRate + _startTime, 1000);
            self.audioCallback(_alignCacheFrame);
            R_BufferUnRetain(&_alignCacheFrame->retain);
            _sendFrameCount += PCM_FRAME_COUNT;
            _alignCacheFrame = (R_GJPCMFrame *) GJRetainBufferPoolGetSizeData(_bufferPool, _sizePerPacket);
            GJLOG(GNULL, GJ_LOGINFO, "采集延迟，填充空白帧");
        }
    }

    int blackSize = _sizePerPacket - R_BufferSize(&_alignCacheFrame->retain);
    int leftSize  = frame->mBuffers[0].mDataByteSize;
    while (leftSize >= blackSize) {
        R_BufferWrite(&_alignCacheFrame->retain, frame->mBuffers[0].mData + frame->mBuffers[0].mDataByteSize - leftSize, blackSize);
        _alignCacheFrame->channel = frame->mBuffers[0].mNumberChannels;
        if (_alignWithBlack) {
            _alignCacheFrame->pts = GTimeMake(_sendFrameCount * 1000 / _audioFormat.mSampleRate + _startTime, 1000);

        } else {
            _alignCacheFrame->pts = GTimeMake(time, 1000);
        }
        self.audioCallback(_alignCacheFrame);
        R_BufferUnRetain(&_alignCacheFrame->retain);
        _sendFrameCount += PCM_FRAME_COUNT;
        _alignCacheFrame = (R_GJPCMFrame *) GJRetainBufferPoolGetSizeData(_bufferPool, _sizePerPacket);
        leftSize         = leftSize - blackSize;
        blackSize        = _sizePerPacket;
    }
    if (leftSize > 0) {
        R_BufferWrite(&_alignCacheFrame->retain, frame->mBuffers[0].mData + frame->mBuffers[0].mDataByteSize - leftSize, leftSize);
    }
}

- (void)addMixPlayer:(id<AEAudioPlayable>)player key:(id<NSCopying>)key {
    AUTO_LOCK(_lock);
    if (![_mixPlayers.allKeys containsObject:key]) {
        [_mixPlayers setObject:player forKey:key];
        [_audioController addChannels:@[ player ]];
        if (_mixPlayers.count == 1) {
            [_audioController addOutputReceiver:_audioMixer];
        }
    }
}

- (void)removeMixPlayerWithkey:(id<NSCopying>)key {
    AUTO_LOCK(_lock);
    if ([_mixPlayers.allKeys containsObject:key]) {
        id<AEAudioPlayable> player = _mixPlayers[key];
        [_mixPlayers removeObjectForKey:key];
        if (_mixPlayers.count == 0) {
            [_audioController removeOutputReceiver:_audioMixer];
        }
        [player teardown];
        [_audioController removeChannels:@[ player ]];
    }
}

- (BOOL)startRecode:(NSError **)error {
    AUTO_LOCK(_lock);
    GJLOG(GNULL, GJ_LOGDEBUG, "%p", self);
    _sendFrameCount = 0;
    _startTime      = GTimeMSValue(GJ_Gettime());
    NSError *configError;
    [[GJAudioSessionCenter shareSession] lockBeginConfig];
    [[GJAudioSessionCenter shareSession] requestPlay:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] requestRecode:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] requestDefaultToSpeaker:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] requestAllowAirPlay:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] unLockApplyConfig:&configError];
    if (configError) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "Apply audio session Config error:%s", configError.description.UTF8String);
    }

#ifdef AUDIO_SEND_TEST
    _audioMixer = [[AEAudioSender alloc] init];

#else
    if (_audioMixer == nil) {
        _audioMixer          = [[GJAudioMixer alloc] init];
        _audioMixer.delegate = self;
    }
#endif
    if (_audioController == nil) {
        //第一次需要的时候才申请，并初始化所有参数
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            shareAudioController = [[AEAudioController alloc] initWithAudioDescription:_audioFormat inputEnabled:YES];
        });
        _audioController = shareAudioController;
        [self setAudioFormat:_audioFormat];
        [_audioController addInputReceiver:_audioMixer];
        [self setAudioInEarMonitoring:_audioInEarMonitoring];
        [self setMixToSream:_mixToSream];
        [self setEnableReverb:_enableReverb];
        [self setAce:_ace];
        [self setUseMeasurementMode:_useMeasurementMode];
    } else {
        //其他的每次配置参数的时候已经应用了,无需再配置
    }

    if (_alignCacheFrame) {
        R_BufferUnRetain(&_alignCacheFrame->retain);
    }
    _alignCacheFrame = (R_GJPCMFrame *) GJRetainBufferPoolGetSizeData(_bufferPool, _sizePerPacket);

    NSTimeInterval preferredBufferDuration = _sizePerPacket / _audioFormat.mBytesPerFrame / _audioFormat.mSampleRate;
    if (preferredBufferDuration - _audioController.preferredBufferDuration > 0.01 || preferredBufferDuration - _audioController.preferredBufferDuration < -0.01) {
        [_audioController setPreferredBufferDuration:preferredBufferDuration];
    }

    if (![_audioController start:error]) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "AEAudioController start error:%s", (*error).description.UTF8String);
    }

    return *error == nil;
}

- (void)stopRecode {
    AUTO_LOCK(_lock);

    GJLOG(GNULL, GJ_LOGDEBUG, "%p", self);
    if (_mixfilePlay) {
        [self stopMix];
    }
    [_audioController stop];

    NSError *configError;
    [[GJAudioSessionCenter shareSession] lockBeginConfig];
    [[GJAudioSessionCenter shareSession] requestPlay:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] requestRecode:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] requestDefaultToSpeaker:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] requestAllowAirPlay:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] unLockApplyConfig:&configError];
    if (configError) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "Apply audio session Config error:%s", configError.description.UTF8String);
    }
    if (_alignCacheFrame) {
        R_BufferUnRetain(&_alignCacheFrame->retain);
        _alignCacheFrame = GNULL;
    }
}

- (AEPlaythroughChannel *)playthrough {
    if (_playthrough == nil) {
        _playthrough = [[AEPlaythroughChannel alloc] init];
    }
    return _playthrough;
}

- (BOOL)isHeadphones {
    AVAudioSessionRouteDescription *route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription *desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
            return YES;
    }
    return NO;
}

- (void)setUseMeasurementMode:(BOOL)useMeasurementMode {
    AUTO_LOCK(_lock);

    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "setUseMeasurementMode:%d", useMeasurementMode);
    _useMeasurementMode = useMeasurementMode;
    if (_audioController) {
        if (_audioController.useMeasurementMode != useMeasurementMode) {
            _audioController.useMeasurementMode = useMeasurementMode;
        }
    }
}

- (void)setAce:(BOOL)ace {
    AUTO_LOCK(_lock);

    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "setAce:%d", ace);
    _ace = ace;
    if (_audioController) {
        if (_audioController.voiceProcessingEnabled != ace) {
            [_audioController setVoiceProcessingEnabled:ace];
        }
    }
}

- (void)setAudioInEarMonitoring:(BOOL)audioInEarMonitoring {
    AUTO_LOCK(_lock);

    if (![self isHeadphones]) {
        _needResumeEarMonitoring = audioInEarMonitoring;

    } else {
        _needResumeEarMonitoring = NO;
        [self _setAudioInEarMonitoring:audioInEarMonitoring];
    }
}

- (void)_setAudioInEarMonitoring:(BOOL)audioInEarMonitoring {

    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "_setAudioInEarMonitoring:%d", audioInEarMonitoring);
    _audioInEarMonitoring = audioInEarMonitoring;
    if (_audioController == nil) {
        return;
    }
    if (audioInEarMonitoring) {
        //关闭麦克风接受，打开播放接受
        [_audioController removeInputReceiver:_audioMixer];
        if (![_audioController.inputReceivers containsObject:self.playthrough]) {
            [_audioController addInputReceiver:self.playthrough];
        }
        [self addMixPlayer:self.playthrough key:self.playthrough.description];
    } else {
        [self removeMixPlayerWithkey:self.playthrough.description];
        if (![_audioController.inputReceivers containsObject:_audioMixer]) {
            [_audioController addInputReceiver:_audioMixer];
        }
        [_audioController removeInputReceiver:self.playthrough];
    }
}

- (void)setEnableReverb:(BOOL)enable {
    AUTO_LOCK(_lock);

    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "setEnableReverb:%d", enable);
    _enableReverb = enable;
    if (_reverb == nil) {
        _reverb           = [[AEReverbFilter alloc] init];
        _reverb.dryWetMix = 80;
    }
    if (_audioController) {
        if (enable) {
            if (![_audioController.filters containsObject:_reverb] && _reverb) {
                [_audioController addFilter:_reverb];
            }
        } else {
            [_audioController removeFilter:_reverb];
        }
    }
}

- (void)setMixToSream:(BOOL)mixToSream {
    AUTO_LOCK(_lock);

    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "setMixToSream:%d", mixToSream);
    _mixToSream = mixToSream;

    if (_audioMixer) {
#ifndef AUDIO_SEND_TEST
        if (_mixToSream) {
            [_audioMixer removeIgnoreSource:_audioController.topGroup];
        } else {
            [_audioMixer addIgnoreSource:_audioController.topGroup];
        }
#endif
    }
}

- (BOOL)setMixFile:(NSURL *)file finish:(MixFinishBlock)finishBlock {
    AUTO_LOCK(_lock);

    if (_mixfilePlay != nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "上一个文件没有关闭，自动关闭");
        [self removeMixPlayerWithkey:_mixfilePlay.description];
        _mixfilePlay = nil;
    }

    if (_audioController == nil || !_audioController.running) {
        return NO;
    }

    NSError *error;
    _mixfilePlay = [[AEAudioFilePlayer alloc] initWithURL:file error:&error];
    if (_mixfilePlay == nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "AEAudioFilePlayer alloc error:%s", error.localizedDescription.UTF8String);
        return GFalse;
    } else {
        __weak GJAudioManager *wkSelf = self;
        _mixfilePlay.completionBlock  = ^{
            AUTO_LOCK(wkSelf.lock);
            GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "mixfile finsh callback");

            if (finishBlock) {
                finishBlock(GTrue);
            }
            [wkSelf removeMixPlayerWithkey:wkSelf.mixfilePlay.description];
            wkSelf.mixfilePlay.completionBlock = nil;
            wkSelf.mixfilePlay                 = nil;
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
    AUTO_LOCK(_lock);
    if (_mixfilePlay == nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "重复stop mix");
    } else {
        [self removeMixPlayerWithkey:_mixfilePlay.description];
        _mixfilePlay.completionBlock();
        _mixfilePlay.completionBlock = nil;
        _mixfilePlay                 = nil;
    }
}

- (void)dealloc {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJAudioManager dealloc");
    if (_audioController.running) {
        [self stopRecode];
    }
    if (_alignCacheFrame) {
        R_BufferUnRetain(&_alignCacheFrame->retain);
    }
    if (_bufferPool) {
        GJRetainBufferPool *pool = _bufferPool;
        _bufferPool              = GNULL;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, GTrue);
            GJRetainBufferPoolFree(pool);
        });
    }
    [_audioController removeInputReceiver:_audioMixer];
    [_audioController removeChannels:_mixPlayers.allValues];
}
@end
