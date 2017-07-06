//
//  GJFFmpegPush.c
//  GJCaptureTool
//
//  Created by melot on 2017/7/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJFFmpegPush.h"
#include "GJLiveDefine+internal.h"
#include "GJLog.h"


GBool GJStreamPush_Create(GJStreamPush** sender,StreamPushMessageCallback callback,void* streamPushParm,GJAudioStreamFormat audioFormat,GJVideoStreamFormat videoFormat){
    GJStreamPush* push = GNULL;
    if (*sender == GNULL) {
        push = (GJStreamPush*)malloc(sizeof(GJStreamPush));
    }else{
        push = *sender;
    }
    memset(push, 0, sizeof(GJStreamPush));
    GInt32 ret = avformat_network_init();
    if (ret < 0) {
        return GFalse;
    }
 
    av_register_all();
    queueCreate(&push->sendBufferQueue, 300, GTrue, GTrue);
    push->messageCallback = callback;
    push->streamPushParm = streamPushParm;
    push->stopRequest = GFalse;
    push->releaseRequest = GFalse;
    push->audioFormat = audioFormat;
    push->videoFormat = videoFormat;
    pthread_mutex_init(&push->mutex, GNULL);
    *sender = push;
    return GTrue;

}
GBool GJStreamPush_StartConnect(GJStreamPush* push,const char* sendUrl){
    GInt32 ret = avformat_alloc_output_context2(&push->formatContext, GNULL, GNULL, sendUrl);
    if (ret < 0) {
        GJLOG(GJ_LOGFORBID, "ffmpeg 不知道该封装格式");
        return GFalse;
    }
    memcpy(push->pushUrl, sendUrl, strlen(sendUrl)+1);
    AVCodec* audioCode = GNULL;
    AVCodec* videoCode = GNULL;
    switch (push->audioFormat.format.mType) {
        case GJAudioType_AAC:
            audioCode = avcodec_find_encoder(AV_CODEC_ID_AAC);
            break;
        default:
            break;
    }
    if(audioCode == GNULL){
        GJLOG(GJ_LOGFORBID, "ffmpeg 找不到音频编码器");
        return GFalse;
    }
    switch (push->videoFormat.format.mType) {
        case GJVideoType_H264:
            audioCode = avcodec_find_encoder(AV_CODEC_ID_H264);
            break;
        default:
            break;
    }
    if(videoCode == GNULL){
        GJLOG(GJ_LOGFORBID, "ffmpeg 找不到视频编码器");
        return GFalse;
    }
    AVStream* vs = avformat_new_stream(push->formatContext, videoCode);
    AVStream* as = avformat_new_stream(push->formatContext, audioCode);
    ret = avio_open2(&push->formatContext->pb, sendUrl, 0, GNULL, GNULL);
    if (ret < 0) {
        GJLOG(GJ_LOGFORBID, "avio_open2 error:%d",ret);
        return GFalse;
    }
    return GTrue;
}

GVoid GJStreamPush_Delloc(GJStreamPush* push){
    
    queueFree(&push->sendBufferQueue);
    free(push);
    GJLOG(GJ_LOGDEBUG, "GJRtmpPush_Delloc:%p",push);
    
}
GVoid GJStreamPush_Release(GJStreamPush* push){
    GJLOG(GJ_LOGINFO,"GJRtmpPush_Release::%p",push);
    
    GBool shouldDelloc = GFalse;
    push->messageCallback = GNULL;
    pthread_mutex_lock(&push->mutex);
    push->releaseRequest = GTrue;
    if (push->sendThread == GNULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&push->mutex);
    if (shouldDelloc) {
        GJStreamPush_Delloc(push);
    }
}
GVoid GJStreamPush_Close(GJStreamPush* sender){
    if (sender->stopRequest) {
        GJLOG(GJ_LOGINFO,"GJRtmpPush_Close：%p  重复关闭",sender);
    }else{
        GJLOG(GJ_LOGINFO,"GJRtmpPush_Close:%p",sender);
        sender->stopRequest = GTrue;
        queueEnablePush(sender->sendBufferQueue, GFalse);
        queueBroadcastPop(sender->sendBufferQueue);
        
    }
}
GVoid GJStreamPush_CloseAndDealloc(GJStreamPush** push){
    GJStreamPush_Close(*push);
    GJStreamPush_Release(*push);
    *push = GNULL;

}
GBool GJStreamPush_SendVideoData(GJStreamPush* push,R_GJH264Packet* data){
    return GTrue;
}
GBool GJStreamPush_SendAudioData(GJStreamPush* push,R_GJAACPacket* data){
    return GTrue;
}
GFloat32 GJStreamPush_GetBufferRate(GJStreamPush* push){
    return 1.0;
}
GJTrafficStatus GJStreamPush_GetVideoBufferCacheInfo(GJStreamPush* push){
    return push->videoStatus;
}
GJTrafficStatus GJStreamPush_GetAudioBufferCacheInfo(GJStreamPush* push){
    return push->audioStatus;
}
