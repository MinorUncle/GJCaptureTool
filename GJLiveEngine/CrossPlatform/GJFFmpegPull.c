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
#include <libavformat/avformat.h>
#include <stdio.h>
#include "GJUtil.h"
#include "GJBridegContext.h"
struct _GJStreamPull {
    GJPipleNode pipleNode;
    AVFormatContext *formatContext;
    GChar             pullUrl[MAX_URL_LENGTH];
    GJRetainBufferPool *memoryCachePool;
    pthread_t       pullThread;
    pthread_mutex_t mutex;

    GJTrafficUnit videoPullInfo;
    GJTrafficUnit audioPullInfo;

    MessageHandle messageCallback;
    StreamPullDataCallback    dataCallback;

    GHandle messageCallbackParm;
    GHandle dataCallbackParm;

    GBool stopRequest;
    GBool releaseRequest;
    
};
GVoid GJStreamPull_Delloc(GJStreamPull *pull);
GVoid  packetRecycleNoticeCallback(GJRetainBuffer* buffer,GHandle userData){
    R_GJPacket* packet = (R_GJPacket*)buffer;
    if ((packet->flag & GJPacketFlag_AVPacketType) == GJPacketFlag_AVPacketType) {
        AVPacket avPacket = ((AVPacket*)R_BufferStart(packet) + packet->extendDataOffset)[0];
        av_packet_unref(&avPacket);
    }
}


static GHandle pullRunloop(GHandle parm) {
    pthread_setname_np("Loop.GJStreamPull");
    GJStreamPull *         pull    = parm;
    kStreamPullMessageType message = 0;
    
    AVDictionary* options = GNULL;
    av_dict_set_int(&options, "fpsprobesize", 0, 0);
    av_dict_set(&options, "fflags", "keepside", 0);
    av_dict_set_int(&options, "fflags", pull->formatContext->flags|AVFMT_FLAG_KEEP_SIDE_DATA, 0);

    GInt32 result = avformat_open_input(&pull->formatContext, (const GChar*)pull->pullUrl, GNULL, &options);
    av_dict_free(&options);
    if (result < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "avformat_open_input error:%s,url:%s",av_err2str(result),pull->pullUrl);
        message = kStreamPullMessageType_connectError;
        goto END;
    }
//    不要用av_format_inject_global_side_data，暂时没有发现用处，倒是如果不对接受到的包不做get side data处理的话，解码会出错
    av_format_inject_global_side_data(pull->formatContext);
//    pull->formatContext->fps_probe_size = 0;
    //    pull->formatContext->max_analyze_duration = 0;
///<----ijk中的启动优化
//    framedrop 只用在ffplay，用于cpu性能太差时，视频显示延迟时是否丢帧，framedrop>0，表示丢帧，==0表示视频不为时间线时丢帧，否则不丢帧，基本无用
//    av_dict_set_int(&options, "framedrop", 1, 0);
//flush_packets,刷新缓存，只有复用的时候需要，解复用的时候不需要，
//    av_dict_set_int(&options, "flush_packets", 1, 0);
//    avformat_find_stream_info的数据包不保存。不用设置
    //    av_dict_set_int(&options, "nobuffer", 1, 0);
    
//        av_dict_set_int(&options, "max_analyze_duration", 1000, 0);

    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "start avformat_find_stream_info");

    result = avformat_find_stream_info(pull->formatContext, GNULL);
    if (result < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "avformat_find_stream_info");
        message = kStreamPullMessageType_connectError;
        goto END;
    }
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "end avformat_find_stream_info");
    pthread_mutex_lock(&pull->mutex);
    if (pull->messageCallback) {
        defauleDeliveryMessage0(pull->messageCallback, pull, pull->messageCallbackParm, kStreamPullMessageType_connectSuccess);
//        pull->messageCallback(pull, kStreamPullMessageType_connectSuccess, pull->messageCallbackParm, NULL);
    }
    pthread_mutex_unlock(&pull->mutex);
    
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "start av_find_best_stream vindex");

    GInt32 vsIndex = av_find_best_stream(pull->formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (vsIndex < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "not found video stream");
    }else{
        
        //第一次直接通过contex获得
        AVStream *vStream  = pull->formatContext->streams[vsIndex];
        R_GJPacket *streamPacket = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool, sizeof(AVStream*));
        streamPacket->type = GJMediaType_Video;
        streamPacket->flag = GJPacketFlag_P_AVStreamType;
    
        ((AVStream**)(R_BufferStart(streamPacket)))[0] = vStream;
        R_BufferUseSize(streamPacket, sizeof(vStream));
//        R_BufferWrite(&streamPacket->retain, (GHandle)&vStream, sizeof(vStream));
        streamPacket->extendDataSize = sizeof(vStream);
        
        pthread_mutex_lock(&pull->mutex);
        if (!pull->releaseRequest) {
            pull->dataCallback(pull, streamPacket, pull->dataCallbackParm);
        }
        pthread_mutex_unlock(&pull->mutex);
        pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&streamPacket->retain,GJMediaType_Video);
        R_BufferUnRetain(&streamPacket->retain);
    }
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "start av_find_best_stream aindex");

    GInt32 asIndex = av_find_best_stream(pull->formatContext, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);

    if (asIndex < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "not found audio stream");
    } else {
        AVStream *aStream  = pull->formatContext->streams[asIndex];
        R_GJPacket *streamPacket = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool, sizeof(AVStream*));
        streamPacket->type = GJMediaType_Audio;
        streamPacket->flag = GJPacketFlag_P_AVStreamType;
        
        ((AVStream**)(R_BufferStart(streamPacket)))[0] = aStream;
        R_BufferUseSize(streamPacket, sizeof(aStream));
        streamPacket->extendDataSize = sizeof(aStream);
        
        pthread_mutex_lock(&pull->mutex);
        if (!pull->releaseRequest) {
            pull->dataCallback(pull, streamPacket, pull->dataCallbackParm);
        }
        pthread_mutex_unlock(&pull->mutex);
        pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&streamPacket->retain,GJMediaType_Audio);
        R_BufferUnRetain(&streamPacket->retain);
    }
    
    for (int i = 0; i < pull->formatContext->nb_streams; i++) {
        av_dump_format(pull->formatContext, i, (const char*)pull->pullUrl, GFalse);
    }

    while (!pull->stopRequest) {
        AVPacket pkt;
        av_init_packet(&pkt);
        pkt.data = GNULL; pkt.size = 0;
        R_GJPacket* packet = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool, sizeof(AVPacket));
        packet->flag = GJPacketFlag_AVPacketType;
        GInt32 ret = av_read_frame(pull->formatContext, &pkt);
        av_packet_split_side_data(&pkt);
        AVPacket* pktRef = (AVPacket*)R_BufferStart(packet);
        av_init_packet(pktRef);
        av_packet_ref(pktRef, &pkt);
//        ((AVPacket*)(R_BufferStart(packet)))[0] = pkt;//转移了内存引用，所以不用了av_packet_unref;
        R_BufferUseSize(packet, sizeof(AVPacket));
        packet->extendDataSize = sizeof(AVPacket);
        
        if (ret < 0) {
            R_BufferUnRetain(packet);
            GJLOG(GNULL,GJ_LOGERROR,"av_read_frame error:%s\n", av_err2str(ret));
            av_packet_unref(&pkt);
            message = kStreamPullMessageType_receivePacketError;
            goto END;
        }
        
        AVStream* stream = pull->formatContext->streams[pkt.stream_index];
        packet->pts            = GTimeMake(pkt.pts*1.0*stream->time_base.num/stream->time_base.den*1000, 1000);
        packet->dts            = GTimeMake(pkt.dts*1.0*stream->time_base.num/stream->time_base.den*1000, 1000);
        packet->type = pkt.stream_index == asIndex;
        pthread_mutex_lock(&pull->mutex);
        if (!pull->releaseRequest){
            pull->dataCallback(pull, packet, pull->dataCallbackParm);
        }
        pthread_mutex_unlock(&pull->mutex);
        if (pkt.stream_index == vsIndex) {
            pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&packet->retain,GJMediaType_Video);
        }else if (pkt.stream_index == asIndex){
            pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&packet->retain,GJMediaType_Audio);
        }else{
            GJLOG(GNULL, GJ_LOGDEBUG, "receive unknow stream type:%d",stream->codecpar->codec_type);
        }
        R_BufferUnRetain(packet);
        
#ifdef DEBUG
        GLong preDTS[2],prePTS[2];
        GInt32 type = pkt.stream_index == asIndex;
        GJLOG(GNULL,GJ_LOGDEBUG,"receive type:%d pts:%lld dts:%lld dpts:%lld ddts:%lld size:%d\n",type, pkt.pts, pkt.dts,pkt.pts - prePTS[type],pkt.dts - preDTS[type], pkt.size);
        preDTS[type] = pkt.dts;
        prePTS[type] = pkt.pts;

#endif
        av_packet_unref(&pkt);

    };

END:
    avformat_close_input(&pull->formatContext);

    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    if (pull->messageCallback) {
        defauleDeliveryMessage0(pull->messageCallback, pull, pull->messageCallbackParm, message);
        //        pull->messageCallback(pull, message, pull->messageCallbackParm, pull->messageCallbackParm);
    }
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
GBool GJStreamPull_Create(GJStreamPull **pullP, MessageHandle callback, GHandle streamPullParm) {
    GJStreamPull *pull = NULL;
    if (*pullP == NULL) {
        pull = (GJStreamPull *) malloc(sizeof(GJStreamPull));
    } else {
        pull = *pullP;
    }
    GJLOG(GNULL, GJ_LOGDEBUG, "GJStreamPull_Create:%p",pull);
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
    GJRetainBufferPoolCreate(&pull->memoryCachePool, 1, GTrue, R_GJPacketMalloc,packetRecycleNoticeCallback, GNULL);
    pthread_mutex_init(&pull->mutex, NULL);
    *pullP = pull;
    return GTrue;
}
GVoid GJStreamPull_Delloc(GJStreamPull *pull) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJStreamPull_Delloc:%p",pull);
    if (pull) {
        GJRetainBufferPoolClean(pull->memoryCachePool, GTrue);
        GJRetainBufferPoolFree(pull->memoryCachePool);

        avformat_free_context(pull->formatContext);
        pipleNodeUnInit(&pull->pipleNode);
        free(pull);
        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPull_Delloc:%p", pull);
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "GJStreamPull_Delloc NULL PULL");
    }
}
GVoid GJStreamPull_Release(GJStreamPull *pull) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJStreamPull_Release:%p",pull);
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
    GJLOG(GNULL, GJ_LOGDEBUG, "GJStreamPull_Close:%p",pull);
    pull->stopRequest = GTrue;
}

GVoid GJStreamPull_CloseAndRelease(GJStreamPull *pull) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJStreamPull_CloseAndRelease:%p",pull);
    GJStreamPull_Close(pull);
    GJStreamPull_Release(pull);
}

GBool GJStreamPull_StartConnect(GJStreamPull *pull, StreamPullDataCallback dataCallback, GHandle callbackParm, const GChar *pullUrl) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJStreamPull_StartConnect:%p",pull);
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
