//
//  IOS_AudioProduce.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_AudioProduce.h"

#import "GJLog.h"

#define AMAZING_AUDIO_ENGINE
//#define AUDIO_QUEUE_RECODE

#import <CoreAudio/CoreAudioTypes.h>
#ifdef AUDIO_QUEUE_RECODE
#import "GJAudioQueueRecoder.h"
#endif

#ifdef AMAZING_AUDIO_ENGINE
#import "GJAudioManager.h"
#endif

inline static GBool audioProduceSetup(struct _GJAudioProduceContext *context, AudioFrameOutCallback callback, GHandle userData) {
    GJAssert(context->obaque == GNULL, "上一个音频生产器没有释放");

#ifdef AUDIO_QUEUE_RECODE
    GJAudioQueueRecoder *recoder = [[GJAudioQueueRecoder alloc] initWithStreamWithSampleRate:format.mSampleRate channel:format.mChannelsPerFrame formatID:formatid];
    recoder.callback             = ^(R_GJPCMFrame *frame) {
        callback(userData, frame);
    };
    context->obaque = (__bridge_retained GHandle)(recoder);
#endif

#ifdef AMAZING_AUDIO_ENGINE

    GJAudioManager *manager   = [[GJAudioManager alloc] init];
    NodeFlowDataFunc callFunc = pipleNodeFlowFunc(&context->pipleNode);
    manager.audioCallback     = ^(R_GJPCMFrame *frame) {
        if (callback) {
            callback(userData, frame);
        }
        callFunc(&context->pipleNode, &frame->retain, GJMediaType_Audio);
    };
    if (!manager) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "GJAudioManager setup ERROR");
        return GFalse;
    } else {
        context->obaque = (__bridge_retained GHandle) manager;
        return GTrue;
    }
#endif
    return GTrue;
}
inline static GVoid audioProduceUnSetup(struct _GJAudioProduceContext *context) {
    if (context->obaque) {
#ifdef AUDIO_QUEUE_RECODE
        GJAudioQueueRecoder *recode = (__bridge_transfer GJAudioQueueRecoder *) (context->obaque);
        [recode stop];
        context->obaque = GNULL;
#endif

#ifdef AMAZING_AUDIO_ENGINE
        GJAudioManager *manager = (__bridge_transfer GJAudioManager *) (context->obaque);
        [manager stopRecode];
        context->obaque = GNULL;
#endif
    }
}

inline static GBool setAudioFormat(struct _GJAudioProduceContext *context, GJAudioFormat format) {
    if (context->obaque == GNULL) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "GJAudioManager not setup");
        return GFalse;
    }
    if (format.mType != GJAudioType_PCM) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "解码音频源格式不支持");
        return GFalse;
    }
    UInt32 formatid = 0;
    switch (format.mType) {
        case GJAudioType_PCM:
            formatid = kAudioFormatLinearPCM;
            break;
        default: {
            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "解码音频源格式不支持");
            return GFalse;
            break;
        }
    }
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);

    AudioStreamBasicDescription audioFormat = {0};
    audioFormat.mSampleRate                 = format.mSampleRate;       // 3
    audioFormat.mChannelsPerFrame           = format.mChannelsPerFrame; // 4
    audioFormat.mFramesPerPacket            = 1;                        // 7
    audioFormat.mBitsPerChannel             = 16;                       // 5
    audioFormat.mBytesPerFrame              = audioFormat.mChannelsPerFrame * audioFormat.mBitsPerChannel / 8;
    audioFormat.mBytesPerPacket             = audioFormat.mBytesPerFrame * audioFormat.mFramesPerPacket;
    audioFormat.mFormatFlags                = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    audioFormat.mFormatID                   = kAudioFormatLinearPCM;
    manager.audioFormat                     = audioFormat;

#endif
    return GTrue;
}
inline static GBool audioProduceStart(struct _GJAudioProduceContext *context) {
    __block GBool result = GTrue;
#ifdef AUDIO_QUEUE_RECODE
    GJAudioQueueRecoder *recode = (__bridge GJAudioQueueRecoder *) (context->obaque);
    result                      = [recode startRecodeAudio];
#endif
#ifdef AMAZING_AUDIO_ENGINE
    if (1) {
        NSError *       error;
        GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
        if (![manager startRecode:&error]) {
            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "startRecode error:%s", error.localizedDescription.UTF8String);
            result = GFalse;
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *       error;
            GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
            if (![manager startRecode:&error]) {
                GJLOG(DEFAULT_LOG, GJ_LOGERROR, "startRecode error:%s", error.localizedDescription.UTF8String);
                result = GFalse;
            }
        });
    }

#endif
    return result;
}
inline static GVoid audioProduceStop(struct _GJAudioProduceContext *context) {
#ifdef AUDIO_QUEUE_RECODE
    GJAudioQueueRecoder *recode = (__bridge GJAudioQueueRecoder *) (context->obaque);
    [recode stop];
#endif
#ifdef AMAZING_AUDIO_ENGINE
    if (/* DISABLES CODE */ (1)) {
        GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
        [manager stopRecode];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
            [manager stopRecode];
        });
    }
#endif
}

GBool enableReverb(struct _GJAudioProduceContext *context, GBool enable) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
    manager.enableReverb    = enable;
    return manager.enableReverb == enable;
#endif
    return GFalse;
}

GBool enableAudioEchoCancellation(struct _GJAudioProduceContext *context, GBool enable) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
    [manager setAce:enable];
    return manager.ace == enable;
#endif
    return GFalse;
}

GBool enableMeasurementMode(struct _GJAudioProduceContext *context, GBool enable) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
    [manager setUseMeasurementMode:enable];
    return manager.useMeasurementMode == enable;
#endif
    return GFalse;
}

GBool enableAudioInEarMonitoring(struct _GJAudioProduceContext *context, GBool enable) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager      = (__bridge GJAudioManager *) (context->obaque);
    manager.audioInEarMonitoring = enable;
    return manager.audioInEarMonitoring == enable;
#endif
    return GFalse;
}
GBool setupMixAudioFile(struct _GJAudioProduceContext *context, const GChar *file, GBool loop, AudioMixFinishCallback callback, GHandle userData) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
    NSURL *         url     = [NSURL fileURLWithPath:[NSString stringWithUTF8String:file]];
    GBool           result  = [manager setMixFile:url
                                finish:^(GBool finish) {
                                    if (callback) {
                                        callback(userData, url.path.UTF8String, GNULL);
                                    }
                                }];
    return result;
#endif
    return GFalse;
}
GBool startMixAudioFileAtTime(struct _GJAudioProduceContext *context, GUInt64 time) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
    return [manager mixFilePlayAtTime:time];
#endif
    return GTrue;
}
GVoid stopMixAudioFile(struct _GJAudioProduceContext *context) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
    return [manager stopMix];
#endif
}
GBool setInputGain(struct _GJAudioProduceContext *context, GFloat inputGain) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager           = (__bridge GJAudioManager *) (context->obaque);
    manager.audioController.inputGain = inputGain;
    GFloat gain                     = manager.audioController.inputGain;
    return GFloatEqual(gain, inputGain);
#endif
    return GFalse;
}
GBool setMixVolume(struct _GJAudioProduceContext *context, GFloat volume) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager    = (__bridge GJAudioManager *) (context->obaque);
    manager.mixfilePlay.volume = volume;

    return GFloatEqual(manager.mixfilePlay.volume, volume);
#endif
    return GFalse;
}
GBool setOutVolume(struct _GJAudioProduceContext *context, GFloat volume) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager                    = (__bridge GJAudioManager *) (context->obaque);
    manager.audioController.masterOutputVolume = volume;
    return GFloatEqual(manager.audioController.masterOutputVolume, volume);
#endif
    return GFalse;
}
GBool setMixToStream(struct _GJAudioProduceContext *context, GBool should) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
    manager.mixToSream      = should;
#endif
    return GTrue;
}

GBool setMute(struct _GJAudioProduceContext *context, GBool mute) {
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager *manager = (__bridge GJAudioManager *) (context->obaque);
    manager.mute            = mute;
#endif
    return GTrue;
}

GVoid GJ_AudioProduceContextCreate(GJAudioProduceContext **recodeContext) {
    if (*recodeContext == NULL) {
        *recodeContext = (GJAudioProduceContext *) malloc(sizeof(GJAudioProduceContext));
    }
    GJAudioProduceContext *context = *recodeContext;
    memset(context, 0, sizeof(GJAudioProduceContext));
    pipleNodeInit(&context->pipleNode, GNULL);
    context->audioProduceSetup   = audioProduceSetup;
    context->audioProduceUnSetup = audioProduceUnSetup;
    context->setAudioFormat      = setAudioFormat;
    context->audioProduceStart   = audioProduceStart;
    context->audioProduceStop    = audioProduceStop;

    context->enableAudioInEarMonitoring = enableAudioInEarMonitoring;
    context->setupMixAudioFile          = setupMixAudioFile;
    context->startMixAudioFileAtTime    = startMixAudioFileAtTime;
    context->stopMixAudioFile           = stopMixAudioFile;

    context->setInputGain                = setInputGain;
    context->setMixVolume                = setMixVolume;
    context->setOutVolume                = setOutVolume;
    context->setMixToStream              = setMixToStream;
    context->enableReverb                = enableReverb;
    context->enableMeasurementMode       = enableMeasurementMode;
    context->enableAudioEchoCancellation = enableAudioEchoCancellation;
    context->setMute                     = setMute;
}
GVoid GJ_AudioProduceContextDealloc(GJAudioProduceContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->audioProduceUnSetup(*context);
    }
    pipleNodeUnInit(&(*context)->pipleNode);
    free(*context);
    *context = GNULL;
}
