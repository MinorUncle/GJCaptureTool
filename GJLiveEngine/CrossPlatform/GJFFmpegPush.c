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
#include "GJBufferPool.h"
GVoid GJStreamPush_Delloc(GJStreamPush* push);
GVoid GJStreamPush_Close(GJStreamPush* sender);

static GHandle sendRunloop(GHandle parm){
    pthread_setname_np("FFMPEGPushLoop");
    GJStreamPush* push = (GJStreamPush*)parm;
    GJStreamPushMessageType errType = GJStreamPushMessageType_connectError;
    GHandle errParm = GNULL;
  
    GInt32 ret = avio_open2(&push->formatContext->pb, push->pushUrl,  AVIO_FLAG_WRITE | AVIO_FLAG_NONBLOCK, GNULL, GNULL);
    if (ret < 0) {
        GJLOG(GJ_LOGERROR, "avio_open2 error:%d",ret);
        return GFalse;
    }
    ret = avformat_write_header(push->formatContext, GNULL);
    if (ret < 0) {
        GJLOG(GJ_LOGERROR, "avformat_write_header error:%d",ret);
        return GFalse;
    }
    
    R_GJPacket* packet;
    while (!push->stopRequest && queuePop(push->sendBufferQueue, (GHandle*)&packet, INT32_MAX)) {
#ifdef NETWORK_DELAY
        packet->packet.m_nTimeStamp -= startPts;
#endif
        AVPacket* sendPacket =  av_mallocz(sizeof(AVPacket));
        sendPacket->pts = packet->pts;
        if (packet->flag == GJPacketFlag_KEY) {
            sendPacket->flags = AV_PKT_FLAG_KEY;
        }
        sendPacket->stream_index = packet->type;
        sendPacket->data = packet->retain.data + packet->dataOffset;
        sendPacket->size = packet->dataSize;
        
        GInt32 iRet = av_write_frame(push->formatContext, sendPacket);
        if (iRet) {
//            if (packet->packet.m_packetType == RTMP_PACKET_TYPE_VIDEO) {
//                GJLOGFREQ("send video pts:%d size:%d",packet->packet.m_nTimeStamp,packet->packet.m_nBodySize);
//                push->videoStatus.leave.byte+=packet->packet.m_nBodySize;
//                push->videoStatus.leave.count++;
//                push->videoStatus.leave.pts = packet->packet.m_nTimeStamp;
//            }else{
//                GJLOGFREQ("send audio pts:%d size:%d",packet->packet.m_nTimeStamp,packet->packet.m_nBodySize);
//                push->audioStatus.leave.byte+=packet->packet.m_nBodySize;
//                push->audioStatus.leave.count++;
//                push->audioStatus.leave.pts = packet->packet.m_nTimeStamp;
//            }
//            retainBufferUnRetain(packet->retainBuffer);
//            GJBufferPoolSetData(defauleBufferPool(), (GHandle)packet);
        }else{
            GJLOG(GJ_LOGFORBID, "error send video FRAME");
            errType = GJStreamPushMessageType_sendPacketError;
            retainBufferUnRetain(&packet->retain);
            GJBufferPoolSetData(defauleBufferPool(), (GHandle)packet);
            goto ERROR;
        };
    }

    
    errType = GJStreamPushMessageType_closeComplete;
ERROR:
    
    if (push->messageCallback) {
        push->messageCallback(push->streamPushParm, errType,errParm);
    }
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&push->mutex);
    push->sendThread = GNULL;
    if (push->releaseRequest == GTrue) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&push->mutex);
    if (shouldDelloc) {
        GJStreamPush_Delloc(push);
    }
    GJLOG(GJ_LOGINFO,"sendRunloop end");
    
    return GNULL;
}


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
    
    GJLOG(GJ_LOGINFO,"GJRtmpPush_StartConnect:%p",push);
    
    size_t length = strlen(sendUrl);
    memset(&push->videoStatus, 0, sizeof(GJTrafficStatus));
    memset(&push->audioStatus, 0, sizeof(GJTrafficStatus));
    GJAssert(length <= 100-1, "sendURL 长度不能大于：%d",100-1);
    memcpy(push->pushUrl, sendUrl, length+1);
    if (push->sendThread) {
        GJLOG(GJ_LOGWARNING,"上一个push没有释放，开始释放并等待");
        GJStreamPush_Close(push);
        pthread_join(push->sendThread, GNULL);
        GJLOG(GJ_LOGWARNING,"等待push释放结束");
    }
    push->stopRequest = GFalse;
    
    
    GInt32 ret = avformat_alloc_output_context2(&push->formatContext, GNULL, "flv", sendUrl);
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
            videoCode = avcodec_find_encoder(AV_CODEC_ID_H264);
            break;
        default:
            break;
    }
    if(videoCode == GNULL){
        GJLOG(GJ_LOGFORBID, "ffmpeg 找不到视频编码器");
        return GFalse;
    }
    AVStream* vs = avformat_new_stream(push->formatContext, videoCode);
    vs->codecpar->bit_rate = push->videoFormat.bitrate;
    vs->codecpar->width = push->videoFormat.format.mWidth;
    vs->codecpar->height = push->videoFormat.format.mHeight;
    vs->codecpar->format = AV_PIX_FMT_YUV420P;
    vs->codecpar->codec_type = AVMEDIA_TYPE_VIDEO;
    vs->codecpar->codec_id = AV_CODEC_ID_H264;
    vs->time_base.num = 1;
    vs->time_base.den = 1000;
    push->vStream = vs;
    
    AVStream* as = avformat_new_stream(push->formatContext, audioCode);
    as->codecpar->channels = push->audioFormat.format.mChannelsPerFrame;
    as->codecpar->bit_rate = push->audioFormat.bitrate;
    as->codecpar->sample_rate = push->audioFormat.format.mSampleRate;
    as->codecpar->format = AV_SAMPLE_FMT_S16;
    as->codecpar->codec_type = AVMEDIA_TYPE_AUDIO;
    as->codecpar->codec_id = AV_CODEC_ID_AAC;
    as->time_base.num = 1;
    as->time_base.den = 1000;
    push->aStream = as;
    AVDictionary *option = GNULL;
    av_dict_set_int(&option, "timeout", 2000, 0);

    
    pthread_create(&push->sendThread, GNULL, sendRunloop, push);
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
GBool GJStreamPush_SendVideoData(GJStreamPush* push,R_GJPacket* data){
    data->type = push->vStream->index;
    queuePush(push->sendBufferQueue, data, 0);
    
    return GTrue;
}
GBool GJStreamPush_SendAudioData(GJStreamPush* push,R_GJPacket* data){
    data->type = push->aStream->index;
    queuePush(push->sendBufferQueue, data, 0);
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
