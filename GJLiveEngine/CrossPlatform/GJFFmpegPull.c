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
    pthread_setname_np("Loop.GJStreamPull");
    GJStreamPull* pull = parm;
    GJStreamPullMessageType message = 0;
    
    GInt32 result = avformat_open_input(&pull->formatContext, pull->pullUrl, GNULL, GNULL);
    if (result < 0) {
        GJLOG(GJ_LOGERROR, "avformat_open_input error");
        message = GJStreamPullMessageType_connectError;
        goto END;
    }
    av_format_inject_global_side_data(pull->formatContext);
    pull->formatContext->fps_probe_size = 0;
//    pull->formatContext->max_analyze_duration = 0;
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
        AVStream* vStream = pull->formatContext->streams[vsIndex];
        GUInt8* avcc = vStream->codecpar->extradata;
        GInt32 avccSize = vStream->codecpar->extradata_size;
        if (avccSize > 9 && (avcc[8] & 0x1f) == 7) {
            GUInt8* sps = avcc+8;
            GInt32 spsSize = avcc[6] << 8;
            spsSize |= avcc[7];
            if (avccSize >spsSize + 8 + 3 && (avcc[spsSize + 8 + 3] & 0x1f) == 8) {
                GUInt8* pps = avcc+8+spsSize+3;
                GInt32 ppsSize = avcc[8+spsSize+1] << 8;
                ppsSize |= avcc[8+spsSize+2];

                if (avccSize >= 8+spsSize+3 + ppsSize) {
                    R_GJPacket* avccPacket = (R_GJPacket*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
                    retainBufferAlloc((GJRetainBuffer**)&avccPacket, 8+spsSize+ppsSize, packetBufferRelease, GNULL);
                    avccPacket->type = GJMediaType_Video;
                    avccPacket->flag = GJPacketFlag_KEY;
                    
                    avccPacket->dataOffset = 0;
                    avccPacket->dataSize = avccPacket->retain.size;
                    GUInt8* packetData = avccPacket->retain.data + avccPacket->dataOffset;
                    GInt32 spsNsize = htonl(spsSize);
                    GInt32 ppsNsize = htonl(ppsSize);
                    memcpy(packetData, &spsNsize, 4);
                    memcpy(packetData + 4, sps, spsSize);
                    memcpy(packetData+4+spsSize, &ppsNsize, 4);
                    memcpy(packetData+8+spsSize, pps, ppsSize);
                    pull->dataCallback(pull,avccPacket,pull->dataCallbackParm);
                    retainBufferUnRetain(&avccPacket->retain);

                }
            }
        }
       

        
        
    }
    
    GInt32 asIndex = av_find_best_stream(pull->formatContext, AVMEDIA_TYPE_AUDIO,-1, -1, NULL, 0);
    if (asIndex < 0) {
        GJLOG(GJ_LOGWARNING, "not found audio stream");
    }else{
        AVStream* aStream = pull->formatContext->streams[asIndex];
        GUInt8* aacc = aStream->codecpar->extradata;
        GInt32 aaccSize = aStream->codecpar->extradata_size;
        if (aaccSize >= 2) {
            R_GJPacket* aaccPacket = (R_GJPacket*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
            retainBufferAlloc((GJRetainBuffer**)&aaccPacket, 7, packetBufferRelease, GNULL);
            aaccPacket->type = GJMediaType_Audio;
            aaccPacket->flag = GJPacketFlag_KEY;
            
            
            GUInt8 profile = (aacc[0] & 0xF8)>>3;
            GUInt8 freqIdx = ((aacc[0] & 0x07) << 1) |(aacc[1] >> 7);
            GUInt8 chanCfg = (aacc[1] >> 3) & 0x0f;
            
            int adtsLength = 7;
            aaccPacket->dataOffset = 0;
            aaccPacket->dataSize = aaccPacket->retain.size;
            GUInt8* adts = aaccPacket->retain.data;
            GInt32 fullLength = adtsLength + 0;
            adts[0] = (char)0xFF;	// 11111111  	= syncword
            adts[1] = (char)0xF1;	   // 1111 0 00 1 = syncword+id(MPEG-4) + Layer + absent
            adts[2] = (char)(((profile)<<6) + (freqIdx<<2) +(chanCfg>>2));// profile(2)+sampling(4)+privatebit(1)+channel_config(1)
            adts[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
            adts[4] = (char)((fullLength&0x7FF) >> 3);
            adts[5] = (char)(((fullLength&7)<<5) + 0x1F);
            adts[6] = (char)0xFC;

            pull->dataCallback(pull,aaccPacket,pull->dataCallbackParm);
            retainBufferUnRetain(&aaccPacket->retain);

        }

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
            h264Packet->dataOffset = 0;
            h264Packet->dataSize = pkt.size;
            h264Packet->pts = pkt.pts;
            h264Packet->dts = pkt.dts;
            h264Packet->type = GJMediaType_Video;
//            printf("video pts:%lld,dts:%lld\n",pkt.pts,pkt.dts);
            pull->dataCallback(pull,h264Packet,pull->dataCallbackParm);
            retainBufferUnRetain(&h264Packet->retain);

        }else if (pkt.stream_index == asIndex){
//            printf("audio pts:%lld,dts:%lld\n",pkt.pts,pkt.dts);

            R_GJPacket* aacPacket = (R_GJPacket*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
            AVBufferRef* buffer = av_buffer_ref(pkt.buf);
            retainBufferPack((GJRetainBuffer**)&aacPacket, pkt.data, pkt.size, packetBufferRelease, buffer);
            aacPacket->dataOffset = 0;
            aacPacket->dataSize = pkt.size;
            aacPacket->pts = pkt.pts;
            aacPacket->dts = pkt.dts;
            aacPacket->type = GJMediaType_Audio;
//            printf("audio pts:%lld,dts:%lld\n",pkt.pts,pkt.dts);
            pull->dataCallback(pull,aacPacket,pull->dataCallbackParm);
            retainBufferUnRetain(&aacPacket->retain);
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

static int interrupt_callback(void* parm){
    GJStreamPull* pull = (GJStreamPull*)parm;
    return pull->stopRequest;
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
    AVIOInterruptCB cb = {.callback = interrupt_callback, .opaque = pull };
    pull->formatContext->interrupt_callback = cb;
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
