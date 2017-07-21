//
//  GJFFmpegPull.c
//  GJCaptureTool
//
//  Created by melot on 2017/7/11.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include <stdio.h>
#include "GJStreamPull.h"
#include "avformat.h"
#include "GJBufferPool.h"
#include "GJLog.h"
struct _GJStreamPull{
    AVFormatContext*                   formatContext;
    char                    pullUrl[MAX_URL_LENGTH];
    
    GJRetainBufferPool*      memoryCachePool;
    pthread_t               pullThread;
    pthread_mutex_t          mutex;
    
    GJTrafficUnit           videoPullInfo;
    GJTrafficUnit           audioPullInfo;
    
    StreamPullMessageCallback     messageCallback;
    StreamPullDataCallback        dataCallback;
    
    GHandle                   messageCallbackParm;
    GHandle                   dataCallbackParm;
    
    int                     stopRequest;
    int                     releaseRequest;
    
    
};
GVoid GJStreamPull_Delloc(GJStreamPull* pull);

static GBool packetBufferRelease(GJRetainBuffer* buffer){
    
    AVBufferRef* avbuf = buffer->parm;
    av_buffer_unref(&avbuf);
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)buffer);
    return GTrue;
}

static GHandle pullRunloop(GHandle parm){
    GJStreamPull* pull = parm;
    GJStreamPullMessageType message = 0;
    GInt32 result = avformat_open_input(&pull->formatContext, pull->pullUrl, GNULL, GNULL);
    if (result < 0) {
        GJLOG(GJ_LOGERROR, "avformat_open_input error");
        message = GJStreamPullMessageType_connectError;
        goto END;
    }
    av_format_inject_global_side_data(pull->formatContext);

    result = avformat_find_stream_info(pull->formatContext, GNULL);
    if (result < 0) {
        GJLOG(GJ_LOGERROR, "avformat_find_stream_info");
        message = GJStreamPullMessageType_connectError;
        goto END;
    }
    
    if(pull->messageCallback){
        pull->messageCallback(pull, GJStreamPullMessageType_connectSuccess,pull->messageCallbackParm,NULL);
    }
    
    GInt32 vsIndex = av_find_best_stream(pull->formatContext, AVMEDIA_TYPE_VIDEO,-1, -1, NULL, 0);
    if (vsIndex < 0) {
        GJLOG(GJ_LOGWARNING, "not found video stream");
    }else{
        R_GJPacket* packet = NULL;
        AVStream* vStream = pull->formatContext->streams[vsIndex];
        pull->dataCallback(pull,packet,pull->dataCallbackParm);
        
    }
    GInt32 asIndex = av_find_best_stream(pull->formatContext, AVMEDIA_TYPE_AUDIO,
                                         -1, -1, NULL, 0);
    if (asIndex < 0) {
        GJLOG(GJ_LOGWARNING, "not found audio stream");
        R_GJPacket* packet = NULL;
        AVStream* aStream = pull->formatContext->streams[asIndex];

        pull->dataCallback(pull,packet,pull->dataCallbackParm);
    }
    AVPacket pkt;
    while (!pull->stopRequest) {
        GInt32 ret = av_read_frame(pull->formatContext, &pkt);
        if (ret < 0) {
            message = GJStreamPullMessageType_receivePacketError;
            goto END;
        }
        
        if (pkt.stream_index == vsIndex) {
            AVBufferRef* buffer = av_buffer_ref(pkt.buf);
            R_GJPacket* h264Packet = (R_GJPacket*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
            retainBufferPack((GJRetainBuffer**)&h264Packet, pkt.data, pkt.size, packetBufferRelease, buffer);
            h264Packet->pts = pkt.dts;
            h264Packet->type = GJMediaType_Video;
            pull->dataCallback(pull,h264Packet,pull->dataCallbackParm);

        }else if (pkt.stream_index == asIndex){
            R_GJPacket* aacPacket = (R_GJPacket*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
            AVBufferRef* buffer = av_buffer_ref(pkt.buf);
            retainBufferPack((GJRetainBuffer**)&aacPacket, pkt.data, pkt.size, packetBufferRelease, buffer);
            aacPacket->pts = pkt.dts;
            aacPacket->type = GJMediaType_Audio;
            pull->dataCallback(pull,aacPacket,pull->dataCallbackParm);
        }
        
            av_packet_unref(&pkt);
        
        
    };

END:
    if (pull->messageCallback) {
        pull->messageCallback(pull, message,pull->messageCallbackParm,pull->messageCallbackParm);
    }
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->pullThread = NULL;
    if (pull->releaseRequest == GTrue) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJStreamPull_Delloc(pull);
    }
    GJLOG(GJ_LOGDEBUG, "pullRunloop end");
    return GNULL;
}
//所有不阻塞
GBool GJStreamPull_Create(GJStreamPull** pullP,StreamPullMessageCallback callback,GHandle streamPullParm){
    GJStreamPull* pull = NULL;
    if (*pullP == NULL) {
        pull = (GJStreamPull*)malloc(sizeof(GJStreamPull));
    }else{
        pull = *pullP;
    }
    GInt32 ret = avformat_network_init();
    if (ret < 0) {
        return GFalse;
    }
    av_register_all();

    memset(pull, 0, sizeof(GJStreamPull));
    pull->formatContext = avformat_alloc_context();
    
    pull->messageCallback = callback;
    pull->messageCallbackParm = streamPullParm;
    pull->stopRequest = GFalse;
    pthread_mutex_init(&pull->mutex, NULL);
    *pullP = pull;
    return GTrue;
}
GVoid GJStreamPull_Delloc(GJStreamPull* pull){
    if (pull) {
        avformat_free_context(pull->formatContext);
        free(pull);
        GJLOG(GJ_LOGDEBUG, "GJStreamPull_Delloc:%p",pull);
    }else{
        GJLOG(GJ_LOGWARNING, "GJStreamPull_Delloc NULL PULL");
    }
}
GVoid GJStreamPull_Release(GJStreamPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJStreamPull_Release:%p",pull);
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->messageCallback = NULL;
    pull->releaseRequest = GTrue;
    if (pull->pullThread == NULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJStreamPull_Delloc(pull);
    }
}
GVoid GJStreamPull_Close(GJStreamPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJStreamPull_Close:%p",pull);
    pull->stopRequest = GTrue;
    
}

GVoid GJStreamPull_CloseAndRelease(GJStreamPull* pull){
    GJStreamPull_Close(pull);
    GJStreamPull_Release(pull);
}

GBool GJStreamPull_StartConnect(GJStreamPull* pull,StreamPullDataCallback dataCallback,GHandle callbackParm,const GChar* pullUrl){
    GJLOG(GJ_LOGDEBUG, "GJStreamPull_StartConnect:%p",pull);
    
    if (pull->pullThread != NULL) {
        GJStreamPull_Close(pull);
        pthread_join(pull->pullThread, NULL);
    }
    size_t length = strlen(pullUrl);
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(pull->pullUrl, pullUrl, length+1);
    pull->stopRequest = GFalse;
    pull->dataCallback = dataCallback;
    pull->dataCallbackParm = callbackParm;
    pthread_create(&pull->pullThread, NULL, pullRunloop, pull);
    
    return GTrue;
}
GJTrafficUnit GJStreamPull_GetVideoPullInfo(GJStreamPull* pull);
GJTrafficUnit GJStreamPull_GetAudioPullInfo(GJStreamPull* pull);
