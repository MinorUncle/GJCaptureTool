//
//  IOS_AudioProduce.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_AudioProduce.h"
#import "GJAudioQueueRecoder.h"
#import "GJLog.h"

inline static GBool audioProduceSetup(struct _GJAudioProduceContext* context,GJAudioFormat format,AudioFrameOutCallback callback,GHandle userData){
    GJAssert(context->obaque == GNULL, "上一个音频生产器没有释放");
    if (format.mType != GJAudioType_PCM) {
        GJLOG(GJ_LOGERROR, "解码音频源格式不支持");
        return GFalse;
    }
    UInt32 formatid = 0;
    switch (format.mType) {
        case GJAudioType_PCM:
            formatid = kAudioFormatLinearPCM;
            break;
        default:
        {
            GJLOG(GJ_LOGERROR, "解码音频源格式不支持");
            return GFalse;
            break;
        }
    }
    if (callback == GNULL) {
        GJLOG(GJ_LOGERROR, "回调函数不能为空");
        return GFalse;
    }
    GJAudioQueueRecoder* recoder = [[GJAudioQueueRecoder alloc]initWithStreamWithSampleRate:format.mSampleRate channel:format.mChannelsPerFrame formatID:formatid];
    recoder.callback = ^(R_GJPCMFrame *frame) {
        callback(userData,frame);
    };
    context->obaque = (__bridge_retained GHandle)(recoder);
    return GTrue;
}
inline static GVoid audioProduceUnSetup(struct _GJAudioProduceContext* context){
    if(context->obaque){
        GJAudioQueueRecoder* recode = (__bridge_transfer GJAudioQueueRecoder *)(context->obaque);
        [recode stop];
        context->obaque = GNULL;
    }
}
inline static GBool audioProduceStart(struct _GJAudioProduceContext* context){
    GJAudioQueueRecoder* recode = (__bridge GJAudioQueueRecoder *)(context->obaque);
    return  [recode startRecodeAudio];
}
inline static GVoid audioProduceStop(struct _GJAudioProduceContext* context){
    GJAudioQueueRecoder* recode = (__bridge GJAudioQueueRecoder *)(context->obaque);
    [recode stop];
}

GVoid GJ_AudioProduceContextCreate(GJAudioProduceContext** recodeContext){
    if (*recodeContext == NULL) {
        *recodeContext = (GJAudioProduceContext*)malloc(sizeof(GJAudioProduceContext));
    }
    GJAudioProduceContext* context = *recodeContext;
    context->audioProduceSetup = audioProduceSetup;
    context->audioProduceUnSetup = audioProduceUnSetup;
    context->audioProduceStart = audioProduceStart;
    context->audioProduceStop = audioProduceStop;
    
}
GVoid GJ_AudioProduceContextDealloc(GJAudioProduceContext** context){
    if ((*context)->obaque) {
        GJLOG(GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->audioProduceUnSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
