//
//  GJFFmpegPull.c
//  GJCaptureTool
//
//  Created by melot on 2017/7/11.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJBufferPool.h"
#include "GJLog.h"
#include "GJStreamPull.h"
#include "avformat.h"
#include <stdio.h>
#include "GJUtil.h"
#include "GJBridegContext.h"
struct _GJStreamPull {
    GJPipleNode pipleNode;
    AVFormatContext *formatContext;
    GChar             pullUrl[MAX_URL_LENGTH];
#if MENORY_CHECK
    GJRetainBufferPool *memoryCachePool;
#endif
    pthread_t       pullThread;
    pthread_mutex_t mutex;

    GJTrafficUnit videoPullInfo;
    GJTrafficUnit audioPullInfo;

    StreamPullMessageCallback messageCallback;
    StreamPullDataCallback    dataCallback;

    GHandle messageCallbackParm;
    GHandle dataCallbackParm;

    GBool stopRequest;
    GBool releaseRequest;
    
    GBool hasVideoKey;
    //保证有第一个关键帧才回调数据
//#ifdef NETWORK_DELAY
//    GInt32 networkDelay;
//    GInt32 delayCount;
//#endif
};
GVoid GJStreamPull_Delloc(GJStreamPull *pull);

static GBool packetBufferRelease(GJRetainBuffer *buffer) {
    if (R_BufferUserData(buffer)) {
        AVBufferRef *avbuf = R_BufferUserData(buffer);
        av_buffer_unref(&avbuf);
    } else {
        R_BufferFreeData(buffer);
    }
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8 *) buffer);
    return GTrue;
}

static GHandle pullRunloop(GHandle parm) {
    pthread_setname_np("Loop.GJStreamPull");
    GJStreamPull *         pull    = parm;
    kStreamPullMessageType message = 0;

    GInt32 result = avformat_open_input(&pull->formatContext, (const GChar*)pull->pullUrl, GNULL, GNULL);
    if (result < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "avformat_open_input error,url:%s",pull->pullUrl);
        message = kStreamPullMessageType_connectError;
        goto END;
    }
    av_format_inject_global_side_data(pull->formatContext);
    pull->formatContext->fps_probe_size = 0;
    //    pull->formatContext->max_analyze_duration = 0;
    result = avformat_find_stream_info(pull->formatContext, GNULL);
    if (result < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "avformat_find_stream_info");
        message = kStreamPullMessageType_connectError;
        goto END;
    }

    if (pull->messageCallback) {
        pull->messageCallback(pull, kStreamPullMessageType_connectSuccess, pull->messageCallbackParm, NULL);
    }

    GInt32 vsIndex = av_find_best_stream(pull->formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (vsIndex < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "not found video stream");
    } else {
        AVStream *vStream  = pull->formatContext->streams[vsIndex];
        GUInt8 *  avcc     = vStream->codecpar->extradata;
        GInt32    avccSize = vStream->codecpar->extradata_size;
        if (avccSize > 9 && (avcc[8] & 0x1f) == 7) {
            GUInt8 *sps     = avcc + 8;
            GInt32  spsSize = avcc[6] << 8;
            spsSize |= avcc[7];
            if (avccSize > spsSize + 8 + 3 && (avcc[spsSize + 8 + 3] & 0x1f) == 8) {
                GUInt8 *pps     = avcc + 8 + spsSize + 3;
                GInt32  ppsSize = avcc[8 + spsSize + 1] << 8;
                ppsSize |= avcc[8 + spsSize + 2];

                if (avccSize >= 8 + spsSize + 3 + ppsSize) {
                    R_GJPacket *avccPacket = (R_GJPacket *) GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
                    R_BufferAlloc((GJRetainBuffer **) &avccPacket, 8 + spsSize + ppsSize, packetBufferRelease, GNULL);
                    avccPacket->type = GJMediaType_Video;
                    avccPacket->flag = GJPacketFlag_KEY;

                    avccPacket->dataOffset = avccPacket->dataSize = 0;
                    avccPacket->extendDataOffset = 0;
                    avccPacket->extendDataSize   = 8 + spsSize + ppsSize;
                    GInt32  spsNsize       = htonl(spsSize);
                    GInt32  ppsNsize       = htonl(ppsSize);
                    R_BufferWrite(&avccPacket->retain, (GUInt8*)&spsNsize, 4);
                    R_BufferWrite(&avccPacket->retain, sps, spsSize);
                    R_BufferWrite(&avccPacket->retain, (GUInt8*)&ppsNsize, 4);
                    R_BufferWrite(&avccPacket->retain, pps, ppsSize);
                    pthread_mutex_lock(&pull->mutex);
                    if (!pull->releaseRequest) {
                        pull->dataCallback(pull, avccPacket, pull->dataCallbackParm);
                    }
                    pthread_mutex_unlock(&pull->mutex);
                    pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&avccPacket->retain,GJMediaType_Video);
                    R_BufferUnRetain(&avccPacket->retain);
                }
            }
        }
    }

    GInt32 asIndex = av_find_best_stream(pull->formatContext, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (asIndex < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "not found audio stream");
    } else {
        AVStream *aStream  = pull->formatContext->streams[asIndex];
        GUInt8 *  aacc     = aStream->codecpar->extradata;
        GInt32    aaccSize = aStream->codecpar->extradata_size;
        if (aaccSize >= 2) {
            R_GJPacket *aaccPacket = (R_GJPacket *) GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
            R_BufferAlloc((GJRetainBuffer **) &aaccPacket, 7, packetBufferRelease, GNULL);
            aaccPacket->type = GJMediaType_Audio;
            aaccPacket->flag = GJPacketFlag_KEY;

            GUInt8 profile = (aacc[0] & 0xF8) >> 3;
            GUInt8 freqIdx = ((aacc[0] & 0x07) << 1) | (aacc[1] >> 7);
            GUInt8 chanCfg = (aacc[1] >> 3) & 0x0f;

            int adtsLength         = 7;
            aaccPacket->dataOffset = aaccPacket->dataSize = aaccPacket->extendDataOffset = 0;
            aaccPacket->extendDataSize   = adtsLength;
            GUInt8 *adts           = R_BufferStart(&aaccPacket->retain);
            GInt32  fullLength     = adtsLength + 0;
            adts[0]                = (char) 0xFF;                                                 // 11111111  	= syncword
            adts[1]                = (char) 0xF1;                                                 // 1111 0 00 1 = syncword+id(MPEG-4) + Layer + absent
            adts[2]                = (char) (((profile) << 6) + (freqIdx << 2) + (chanCfg >> 2)); // profile(2)+sampling(4)+privatebit(1)+channel_config(1)
            adts[3]                = (char) (((chanCfg & 3) << 6) + (fullLength >> 11));
            adts[4]                = (char) ((fullLength & 0x7FF) >> 3);
            adts[5]                = (char) (((fullLength & 7) << 5) + 0x1F);
            adts[6]                = (char) 0xFC;

            pthread_mutex_lock(&pull->mutex);
            if (!pull->releaseRequest) {
                pull->dataCallback(pull, aaccPacket, pull->dataCallbackParm);
            }
            pthread_mutex_unlock(&pull->mutex);
            pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&aaccPacket->retain,GJMediaType_Audio);

            R_BufferUnRetain(&aaccPacket->retain);
        }
    }
    
    for (int i = 0; i < pull->formatContext->nb_streams; i++) {
        av_dump_format(pull->formatContext, i, (const char*)pull->pullUrl, GFalse);
    }

    AVPacket pkt;
    while (!pull->stopRequest) {
        GInt32 ret = av_read_frame(pull->formatContext, &pkt);
        if (ret < 0) {
            GJLOG(GNULL,GJ_LOGERROR,"av_read_frame error:%s\n", av_err2str(ret));
            message = kStreamPullMessageType_receivePacketError;
            goto END;
        }

#ifdef DEBUG
        GLong preDTS[2];
        GInt32 type = pkt.stream_index == asIndex;
//        GJLOG(GNULL,GJ_LOGDEBUG,"receive type:%d pts:%lld dts:%lld dpts:%d size:%d\n",type, pkt.pts, pkt.dts,pkt.pts - preDTS[type], pkt.size);
        preDTS[type] = pkt.pts;
#endif
        if (pkt.stream_index == vsIndex) {

#if MENORY_CHECK
            R_GJPacket *h264Packet = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool, pkt.size);
            h264Packet->dataOffset = 0;
            R_BufferWrite(&h264Packet->retain, pkt.data, pkt.size);
#else
            AVBufferRef *buffer     = av_buffer_ref(pkt.buf);
            R_GJPacket * h264Packet = (R_GJPacket *) GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
            R_BufferPack((GJRetainBuffer **) &h264Packet, pkt.data, pkt.size, packetBufferRelease, buffer);
            h264Packet->dataOffset = 0;
#endif

            h264Packet->dataSize = pkt.size;
            h264Packet->pts      = GTimeMake(pkt.pts, 1000);
            h264Packet->dts      = GTimeMake(pkt.dts, 1000);
            h264Packet->type     = GJMediaType_Video;
            h264Packet->flag = ((pkt.flags & AV_PKT_FLAG_KEY) == AV_PKT_FLAG_KEY);
            pull->videoPullInfo.byte += pkt.size;
            pull->videoPullInfo.count ++;
            pull->videoPullInfo.ts = GTimeMake(pkt.pts, 1000);
            if(!pull->hasVideoKey && ((pkt.flags & AV_PKT_FLAG_KEY) == AV_PKT_FLAG_KEY)){
                pull->hasVideoKey = GTrue;
            }
            h264Packet->extendDataSize = h264Packet->extendDataOffset = 0;
            pthread_mutex_lock(&pull->mutex);
            if (!pull->releaseRequest && pull->hasVideoKey){
                pull->dataCallback(pull, h264Packet, pull->dataCallbackParm);
            }
            pthread_mutex_unlock(&pull->mutex);
            pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&h264Packet->retain,GJMediaType_Video);

            R_BufferUnRetain(&h264Packet->retain);
        } else if (pkt.stream_index == asIndex) {
#if MENORY_CHECK
            R_GJPacket *aacPacket = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool, pkt.size);
            aacPacket->dataOffset = 0;
            R_BufferWrite(&aacPacket->retain, pkt.data, pkt.size);

#else
            R_GJPacket * aacPacket = (R_GJPacket *) GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
            AVBufferRef *buffer    = av_buffer_ref(pkt.buf);
            R_BufferPack((GJRetainBuffer **) &aacPacket, pkt.data, pkt.size, packetBufferRelease, buffer);
            aacPacket->dataOffset = 0;
#endif
            aacPacket->dataSize = pkt.size;
            aacPacket->pts      = GTimeMake(pkt.pts, 1000);
            aacPacket->dts      = GTimeMake(pkt.dts, 1000);
            aacPacket->extendDataOffset = aacPacket->extendDataSize = 0;
            aacPacket->type     = GJMediaType_Audio;
            pull->audioPullInfo.byte += pkt.size;
            pull->audioPullInfo.count ++;
            pull->audioPullInfo.ts = GTimeMake(pkt.pts, 1000);
            //            printf("audio pts:%lld,dts:%lld\n",pkt.pts,pkt.dts);
            //            printf("receive packet pts:%lld size:%d  last data:%d\n",aacPacket->pts,aacPacket->dataSize,(aacPacket->retain.data + aacPacket->dataOffset + aacPacket->dataSize -1)[0]);
            pthread_mutex_lock(&pull->mutex);
            if (!pull->releaseRequest && pull->hasVideoKey) {
                pull->dataCallback(pull, aacPacket, pull->dataCallbackParm);
            }
            pthread_mutex_unlock(&pull->mutex);
            pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&aacPacket->retain,GJMediaType_Audio);

            R_BufferUnRetain(&aacPacket->retain);
        }

        av_packet_unref(&pkt);
    };

END:
    avformat_close_input(&pull->formatContext);

    if (pull->messageCallback) {
        pull->messageCallback(pull, message, pull->messageCallbackParm, pull->messageCallbackParm);
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
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "pullRunloop end");
    return GNULL;
}

static int interrupt_callback(void *parm) {
    GJStreamPull *pull = (GJStreamPull *) parm;
    return pull->stopRequest;
}
//所有不阻塞
GBool GJStreamPull_Create(GJStreamPull **pullP, StreamPullMessageCallback callback, GHandle streamPullParm) {
    GJStreamPull *pull = NULL;
    if (*pullP == NULL) {
        pull = (GJStreamPull *) malloc(sizeof(GJStreamPull));
    } else {
        pull = *pullP;
    }
    GInt32 ret = avformat_network_init();
    if (ret < 0) {
        return GFalse;
    }
    av_register_all();

    memset(pull, 0, sizeof(GJStreamPull));
    pipleNodeInit(&pull->pipleNode, GNULL);
    pull->formatContext = avformat_alloc_context();
    AVIOInterruptCB cb = {.callback = interrupt_callback, .opaque = pull};
    pull->formatContext->interrupt_callback = cb;
    pull->messageCallback                   = callback;
    pull->messageCallbackParm               = streamPullParm;
    pull->stopRequest                       = GFalse;
#if MENORY_CHECK
    GJRetainBufferPoolCreate(&pull->memoryCachePool, 1, GTrue, R_GJPacketMalloc, GNULL, GNULL);
#endif
    pthread_mutex_init(&pull->mutex, NULL);
    *pullP = pull;
    return GTrue;
}
GVoid GJStreamPull_Delloc(GJStreamPull *pull) {
    if (pull) {
#if MENORY_CHECK
        GJRetainBufferPoolClean(pull->memoryCachePool, GTrue);
        GJRetainBufferPoolFree(pull->memoryCachePool);
#endif
        avformat_free_context(pull->formatContext);
        pipleNodeUnInit(&pull->pipleNode);
        free(pull);
        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPull_Delloc:%p", pull);
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "GJStreamPull_Delloc NULL PULL");
    }
}
GVoid GJStreamPull_Release(GJStreamPull *pull) {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPull_Release:%p", pull);
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->messageCallback = NULL;
    pull->releaseRequest  = GTrue;
    if (pull->pullThread == NULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJStreamPull_Delloc(pull);
    }
}
GVoid GJStreamPull_Close(GJStreamPull *pull) {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPull_Close:%p", pull);
    pull->stopRequest = GTrue;
}

GVoid GJStreamPull_CloseAndRelease(GJStreamPull *pull) {
    GJStreamPull_Close(pull);
    GJStreamPull_Release(pull);
}

GBool GJStreamPull_StartConnect(GJStreamPull *pull, StreamPullDataCallback dataCallback, GHandle callbackParm, const GChar *pullUrl) {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPull_StartConnect:%p", pull);

    if (pull->pullThread != NULL) {
        GJStreamPull_Close(pull);
        pthread_join(pull->pullThread, NULL);
    }
    size_t length = strlen(pullUrl);
    GJAssert(length <= MAX_URL_LENGTH - 1, "sendURL 长度不能大于：%d", MAX_URL_LENGTH - 1);
    memcpy(pull->pullUrl, pullUrl, length + 1);
    pull->stopRequest      = GFalse;
    pull->dataCallback     = dataCallback;
    pull->dataCallbackParm = callbackParm;
    pthread_create(&pull->pullThread, NULL, pullRunloop, pull);

    return GTrue;
}
//#ifdef NETWORK_DELAY
//GInt32 GJStreamPull_GetNetWorkDelay(GJStreamPull *pull){
//    GInt32 delay = 0;
//    if (pull->delayCount > 0) {
//        delay = pull->networkDelay/pull->delayCount;
//    }
//    pull->delayCount = 0;
//    pull->networkDelay = 0;
//    return delay;
//}
//#endif
GJTrafficUnit GJStreamPull_GetVideoPullInfo(GJStreamPull *pull);
GJTrafficUnit GJStreamPull_GetAudioPullInfo(GJStreamPull *pull);
