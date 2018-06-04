//
//  IOS_Recoder.m
//  GJCaptureTool
//
//  Created by melot on 2017/7/26.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_Recoder.h"
#import "GJLog.h"
#import "GJScreenRecorder.h"
static GBool setup(struct _GJRecodeContext *context, const GChar *fileUrl, RecodeCompleteCallback callback, GHandle userHandle) {
    if (context->obaque != GNULL) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "重复setup recoder");
        return GFalse;
    }
    NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:fileUrl]];
    if (url == nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "录制文件路径错误");
        return GFalse;
    }
    GJScreenRecorder *recoder = [[GJScreenRecorder alloc] initWithDestUrl:url];
    recoder.callback          = ^(NSURL *file, NSError *error) {
        callback(userHandle, file.path.UTF8String, (__bridge GHandle)(error));
    };
    context->obaque = (__bridge_retained GHandle) recoder;
    return context->obaque != nil;
}
static GVoid unSetup(struct _GJRecodeContext *context) {
    if (context->obaque) {
        GJScreenRecorder *recoder = (__bridge_transfer GJScreenRecorder *) (context->obaque);
        context->obaque           = GNULL;
        recoder                   = nil;
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "重复unSetup recoder");
    }
}
static GBool addVideoSource(struct _GJRecodeContext *context, GJVideoFormat format, GView targetView) {
    GJScreenRecorder *recoder = (__bridge GJScreenRecorder *) (context->obaque);

    return [recoder addVideoSourceWithView:(__bridge UIView *) (targetView) fps:format.mFps];
}
static GBool addAudioSource(struct _GJRecodeContext *context, GJAudioFormat format) {

    GJScreenRecorder *          recoder     = (__bridge GJScreenRecorder *) (context->obaque);
    AudioStreamBasicDescription audioFormat = {0};
    audioFormat.mSampleRate                 = format.mSampleRate;       // 3
    audioFormat.mChannelsPerFrame           = format.mChannelsPerFrame; // 4
    audioFormat.mFramesPerPacket            = 1;                        // 7
    audioFormat.mBitsPerChannel             = 16;                       // 5
    audioFormat.mBytesPerFrame              = audioFormat.mChannelsPerFrame * audioFormat.mBitsPerChannel / 8;
    audioFormat.mBytesPerPacket             = audioFormat.mBytesPerFrame * audioFormat.mFramesPerPacket;
    audioFormat.mFormatFlags                = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    audioFormat.mFormatID                   = kAudioFormatLinearPCM;
    return [recoder addAudioSourceWithFormat:audioFormat];
}
static GVoid sendVideoSourcePacket(struct _GJRecodeContext *context, R_GJPixelFrame *packet) {
}
static GVoid sendAudioSourcePacket(struct _GJRecodeContext *context, R_GJPCMFrame *packet) {

    GJScreenRecorder *recoder = (__bridge GJScreenRecorder *) (context->obaque);
    [recoder addCurrentAudioSource:R_BufferStart(&packet->retain) size:R_BufferSize(&packet->retain)];
}
static GBool startRecode(struct _GJRecodeContext *context) {

    GJScreenRecorder *recoder = (__bridge GJScreenRecorder *) (context->obaque);
    if (recoder.status != screenRecorderStopStatus) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "请先完成上一个录制");
        return GFalse;
    }

    return [recoder startRecode];
}
static GVoid stopRecode(struct _GJRecodeContext *context) {

    GJScreenRecorder *recoder = (__bridge GJScreenRecorder *) (context->obaque);
    [recoder stopRecord];
}

GVoid GJ_RecodeContextCreate(GJRecodeContext **recodeContext) {

    if (*recodeContext == NULL) {
        *recodeContext = (GJRecodeContext *) malloc(sizeof(GJRecodeContext));
    }

    GJRecodeContext *context       = *recodeContext;
    context->setup                 = setup;
    context->unSetup               = unSetup;
    context->addVideoSource        = addVideoSource;
    context->addAudioSource        = addAudioSource;
    context->sendVideoSourcePacket = sendVideoSourcePacket;
    context->sendAudioSourcePacket = sendAudioSourcePacket;
    context->startRecode           = startRecode;
    context->stopRecode            = stopRecode;
}
GVoid GJ_RecodeContextDealloc(GJRecodeContext **context) {

    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "videoProduceUnSetup 没有调用，自动调用");
        (*context)->unSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
