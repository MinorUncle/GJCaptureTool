//
//  GJFFmpegPush.c
//  GJCaptureTool
//
//  Created by melot on 2017/7/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJBufferPool.h"
#include "GJLiveDefine+internal.h"
#include "GJLog.h"
#include "GJStreamPush.h"
#include "GJUtil.h"
#include "GJBridegContext.h"
#include "GJMessageDispatcher.h"
#include <libavformat/avformat.h>
#include <libavutil/application.h>
#include <sys/ioctl.h>

#define STREAM_PUSH_LOG GNULL
struct _GJStreamPush {
    GJPipleNode pipleNode;
    AVFormatContext *    formatContext;
    AVStream *           vStream;
    AVStream *           aStream;
    GJAudioStreamFormat *audioFormat;
    GJVideoStreamFormat *videoFormat;

    GJQueue *sendBufferQueue;
    char*     pushUrl;

    pthread_t       sendThread;
    pthread_mutex_t mutex;

    MessageHandle messageCallback;
    void *                    streamPushParm;
    int                       stopRequest;
    int                       releaseRequest;

    GJTrafficStatus audioStatus;
    GJTrafficStatus videoStatus;
    GTimeValue     startMS;
    GInt  fd;
    AVApplicationContext* app_ctx;
};

static GJTrafficStatus error_Status;

GVoid GJStreamPush_Delloc(GJStreamPush *push);
GVoid GJStreamPush_Close(GJStreamPush *sender);
static int app_func_event(AVApplicationContext *h, int message ,void *data, size_t size);
static GHandle sendRunloop(GHandle parm) {
    pthread_setname_np("Loop.GJStreamPush");
    GJStreamPush *         push    = (GJStreamPush *) parm;
    kStreamPushMessageType errType = kStreamPushMessageType_connectError;
    AVDictionary *         option  = GNULL;
    
    av_application_open(&push->app_ctx, push);
    push->app_ctx->func_on_app_event = app_func_event;
    av_dict_set_int(&option, "send_buffer_size", 30000, 0);
    av_dict_set_int(&option, "ijkapplication", (GInt64)push->app_ctx, 0);
    av_dict_set_int(&option, "dns_cache", 1, 0);

    GInt32 ret = avio_open2(&push->formatContext->pb, push->pushUrl, AVIO_FLAG_WRITE | AVIO_FLAG_NONBLOCK, GNULL, &option);
    
    av_dict_free(&option);
    if (ret < 0) {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGERROR, "avio_open2 error:%d", ret);
        errType = kStreamPushMessageType_connectError;
        goto END;
    }
    pthread_mutex_lock(&push->mutex);
    if (push->messageCallback) {
//        push->messageCallback(push, push->streamPushParm, kStreamPushMessageType_connectSuccess, GNULL);
        defauleDeliveryMessage0(push->messageCallback, push, push->streamPushParm, kStreamPushMessageType_connectSuccess);
    }
    pthread_mutex_unlock(&push->mutex);

    R_GJPacket *packet;

    if (push->videoFormat) {
        GLong index = 0;
        while (queuePeekWaitValue(push->sendBufferQueue,(GHandle) &packet,index++, GINT32_MAX)) { //过滤无效起始数据
            if (push->stopRequest) {
                goto END;
            }
            GJLOG(STREAM_PUSH_LOG, GJ_LOGINFO, "peek index:%d type:%d, pts:%lld\n", 0, packet->type, packet->pts.value);
            if (packet->type == GJMediaType_Video) {
                GUInt8 *start = packet->extendDataOffset + R_BufferStart(&packet->retain);
                if (packet->extendDataSize < 0 || (start[4] & 0x1f) != 7) {
                    GJLOG(STREAM_PUSH_LOG, GJ_LOGFORBID, "第一帧视频非关键帧,丢帧");
                    queuePop(push->sendBufferQueue, (GHandle) packet, 0);
                    push->videoStatus.leave.byte += packet->dataSize;
                    push->videoStatus.leave.count++;
                    push->videoStatus.leave.ts = packet->dts;
                    R_BufferUnRetain(&packet->retain);
                    continue;
                }

                GUInt8 *sps = start + 4, *pps;
                GUInt32 spsSize = ntohl(*(GUInt32*)start), ppsSize;
                
                if ((sps[spsSize+4] & 0x1f) == 8 ) {
                    pps = sps + spsSize + 4;
                    ppsSize = ntohl(*(GUInt32*)(pps - 4));
                }else{
                    
                    GJLOG(STREAM_PUSH_LOG, GJ_LOGFORBID, "没有sps，pps，丢弃该帧");
                    queuePop(push->sendBufferQueue, (GHandle) packet, 0);
                    push->videoStatus.leave.byte += packet->dataSize;
                    push->videoStatus.leave.count++;
                    push->videoStatus.leave.ts = packet->dts;
                    R_BufferUnRetain(&packet->retain);
                    continue;
                }

                push->vStream->codecpar->extradata_size = (GInt32)(spsSize + ppsSize + 8);
                push->vStream->codecpar->extradata      = av_malloc(push->vStream->codecpar->extradata_size);
                memcpy(push->vStream->codecpar->extradata, sps - 4, push->vStream->codecpar->extradata_size);
                memcpy(push->vStream->codecpar->extradata, "\x00\x00\x00\x01", 4);
                memcpy(push->vStream->codecpar->extradata + spsSize + 4, "\x00\x00\x00\x01", 4);
                break;
            } else {
                
                GJLOG(STREAM_PUSH_LOG, GJ_LOGWARNING, "非视频帧，丢弃该帧");
                queuePop(push->sendBufferQueue, (GHandle) &packet, 0);
                push->audioStatus.leave.byte += packet->dataSize;
                push->audioStatus.leave.count++;
                push->audioStatus.leave.ts = packet->dts;
                R_BufferUnRetain(&packet->retain);
            }
        }
    }

    if (push->audioFormat) {
        GUInt8 aactype = 2;

        push->aStream->codecpar->extradata_size = 2;
        push->aStream->codecpar->extradata      = av_malloc(2);
        ASC asc = {0};
        asc.channelConfig = push->audioFormat->format.mChannelsPerFrame;
        asc.audioType = aactype;
        asc.sampleRate = push->audioFormat->format.mSampleRate;
        writeASC(push->aStream->codecpar->extradata, 2, &asc);
    }

    ret = avformat_write_header(push->formatContext, GNULL);
    if (ret < 0) {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGERROR, "avformat_write_header error:%d", ret);
        errType = kStreamPushMessageType_connectError;
        goto END;
    }
    for (int i = 0; i < push->formatContext->nb_streams; i++) {
        av_dump_format(push->formatContext, i, push->pushUrl, GTrue);
    }
    AVPacket *sendPacket = av_mallocz(sizeof(AVPacket));
    errType              = kStreamPushMessageType_closeComplete;

    while (queuePop(push->sendBufferQueue, (GHandle *) &packet, INT32_MAX)) {
        if (push->stopRequest) {
            R_BufferUnRetain(&packet->retain);
            break;
        }
        GTimeValue pts = GTimeMSValue(packet->pts)-push->startMS;
        GTimeValue dts = GTimeMSValue(packet->dts)-push->startMS;
        av_init_packet(sendPacket);
        sendPacket->pts = (GInt64)(pts) & 0x7fffffff;
        sendPacket->dts = (GInt64)(dts) & 0x7fffffff;

        if (packet->type == GJMediaType_Video) {
            sendPacket->stream_index = push->vStream->index;
            if (packet->extendDataSize > 0 && (packet->flag & GJPacketFlag_KEY) == GJPacketFlag_KEY) {
                sendPacket->data = R_BufferStart(&packet->retain) + packet->extendDataOffset;
                sendPacket->size = packet->dataSize+packet->extendDataSize;
            }else{
                sendPacket->data = R_BufferStart(&packet->retain) + packet->dataOffset;
                sendPacket->size = packet->dataSize;
            }
            GUInt32 nalSize;
            GUInt8* start = sendPacket->data;
            GUInt8* end = sendPacket->data + sendPacket->size;
            while (end - start >= 4 ) {
                nalSize = ntohl(*(GUInt32*)(start));
                memcpy(start, "\x00\x00\x00\x01", 4);
                start += nalSize + 4;
            }
            if(G_TIME_IS_INVALID(push->videoStatus.leave.firstTs)){
                push->videoStatus.leave.firstTs = packet->dts;
                push->videoStatus.leave.firstClock = GJ_Gettime();
            }
        } else {
            sendPacket->data = R_BufferStart(&packet->retain) + packet->dataOffset;
            sendPacket->size = packet->dataSize;
            sendPacket->stream_index = push->aStream->index;
            
            if(G_TIME_IS_INVALID(push->audioStatus.leave.firstTs)){
                push->audioStatus.leave.firstTs = packet->dts;
                push->audioStatus.leave.firstClock = GJ_Gettime();
            }
        }
        if (packet->flag == GJPacketFlag_KEY) {
            sendPacket->flags = AV_PKT_FLAG_KEY;
        }
        
#ifdef DEBUG
//        static GLong preDTS[2];
//        GInt32 type = sendPacket->stream_index == push->aStream->index;
//        GJLOG(GNULL,GJ_LOGDEBUG,"send type:%d pts:%lld dts:%lld dpts:%lld size:%d isKey:%d\n",type, sendPacket->pts, sendPacket->dts,sendPacket->pts - preDTS[type], sendPacket->size,(packet->flag & GJPacketFlag_KEY)==GJPacketFlag_KEY);
//
//        preDTS[type] = sendPacket->pts;
#endif


//        if (sendPacket->stream_index == 0) {
//            static GInt32 index = 0;
//            GJLOG(DEFAULT_LOG,GJ_LOGDEBUG,"send video index:%d size:%d:",index++, sendPacket->size);
//            GJ_LogHexString(GJ_LOGDEBUG, sendPacket->data+sendPacket->size-20, (GUInt32) 20);
//
//        }
        GInt32 iRet      = av_write_frame(push->formatContext, sendPacket);
        if (iRet >= 0) {
            if (packet->type == GJMediaType_Video) {

                GJLOG(GNULL,GJ_LOGALL,"send video pts:%lld dts:%lld size:%d\n", packet->pts.value, packet->dts.value, packet->dataSize);
                push->videoStatus.leave.byte += packet->dataSize;
                push->videoStatus.leave.count++;
                push->videoStatus.leave.ts =  packet->dts;
                push->videoStatus.leave.clock = GJ_Gettime();
                
                pthread_mutex_lock(&push->mutex);
                if (push->messageCallback) {
                    //                push->messageCallback(push, push->streamPushParm,kStreamPushMessageType_packetSendSignal,&(packet->type));
                    defauleDeliveryMessage1(push->messageCallback, push, push->streamPushParm, kStreamPushMessageType_packetSendSignal,packet->type);
                }
                pthread_mutex_unlock(&push->mutex);
                
            } else {

                GJLOG(GNULL,GJ_LOGALL,"send audio pts:%lld dts:%lld size:%d\n", packet->pts.value, packet->dts.value, packet->dataSize);
                push->audioStatus.leave.byte += packet->dataSize;
                push->audioStatus.leave.count++;
                push->audioStatus.leave.ts = packet->dts;
                push->audioStatus.leave.clock = GJ_Gettime();
            }



            R_BufferUnRetain(&packet->retain);
        } else {
            switch (iRet) {
                case -22:
                    GJLOG(STREAM_PUSH_LOG, GJ_LOGFORBID, "error send video FRAME,pts乱序");
                    break;
                case -32:
                    GJLOG(STREAM_PUSH_LOG, GJ_LOGERROR, "error send video FRAME,断网拉");
                    break;
                default:
                    GJLOG(STREAM_PUSH_LOG, GJ_LOGFORBID, "error send video FRAME,未知错误");

                    break;
            }
            errType = kStreamPushMessageType_sendPacketError;
            R_BufferUnRetain(&packet->retain);
            break;
        };
    }
    av_free(sendPacket);
    GInt32 result = av_write_trailer(push->formatContext);
    if (result < 0) {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGERROR, "av_write_trailer error:%d", result);
    } else {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "av_write_trailer success");
    }

END:
    result = avio_close(push->formatContext->pb);
    if (result < 0) {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGERROR, "avio_close error:%d", result);
    } else {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "avio_close success");
    }


    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&push->mutex);
    if (push->messageCallback) {
        defauleDeliveryMessage0(push->messageCallback, push, push->streamPushParm, errType);
//        push->messageCallback(push, push->streamPushParm, errType, errParm);
    }
    push->sendThread = GNULL;
    if (push->releaseRequest == GTrue) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&push->mutex);
    av_application_closep(&push->app_ctx);
    GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "sendRunloop end:%p",push);
    if (shouldDelloc) {
        GJStreamPush_Delloc(push);
    }
    return GNULL;
}

GBool GJStreamPush_Create(GJStreamPush **sender, MessageHandle callback, void *streamPushParm, const GJAudioStreamFormat *audioFormat, const GJVideoStreamFormat *videoFormat) {
    GJStreamPush *push = GNULL;
    if (*sender == GNULL) {
        push = (GJStreamPush *) malloc(sizeof(GJStreamPush));
    } else {
        push = *sender;
    }
    GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "GJStreamPush_Create:%p", push);

    memset(push, 0, sizeof(GJStreamPush));
    pipleNodeInit(&push->pipleNode, (NodeFlowDataFunc)GJStreamPush_NodeReceiveData);
    GInt32 ret = avformat_network_init();
    if (ret < 0) {
        return GFalse;
    }

    av_register_all();
    queueCreate(&push->sendBufferQueue, 300, GTrue, GTrue);
    push->messageCallback = callback;
    push->streamPushParm  = streamPushParm;
    push->stopRequest     = GFalse;
    push->releaseRequest  = GFalse;
    if (audioFormat) {
        push->audioFormat  = (GJAudioStreamFormat *) malloc(sizeof(GJAudioStreamFormat));
        *push->audioFormat = *audioFormat;
    }
    if (videoFormat) {
        push->videoFormat  = (GJVideoStreamFormat *) malloc(sizeof(GJVideoStreamFormat));
        *push->videoFormat = *videoFormat;
    }

    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&push->mutex, &attr);
    pthread_mutexattr_destroy(&attr);
    *sender = push;
    return GTrue;
}
static int interrupt_callback(void *parm) {
    GJStreamPush *push = (GJStreamPush *) parm;
    return push->stopRequest;
}

static int app_func_event(AVApplicationContext *h, int message ,void *data, size_t size){
    if (!h || !h->opaque || !data)
        return 0;
    
    GJStreamPush *push = (GJStreamPush *)h->opaque;

    if (message == AVAPP_EVENT_IO_TRAFFIC && sizeof(AVAppIOTraffic) == size) {
        AVAppIOTraffic *event = (AVAppIOTraffic *)(intptr_t)data;

    } else if (message == AVAPP_EVENT_ASYNC_STATISTIC && sizeof(AVAppAsyncStatistic) == size) {
        AVAppAsyncStatistic *statistic =  (AVAppAsyncStatistic *) (intptr_t)data;

    }else if (message == AVAPP_CTRL_DID_TCP_OPEN) {
        AVAppTcpIOControl *realData = data;
        push->fd = realData->fd;
        printf("fd:%d\n",push->fd);
    }
    return 0;
}

GBool GJStreamPush_StartConnect(GJStreamPush *push, const char *sendUrl) {

    GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "GJStreamPush_StartConnect:%p", push);

    size_t length = strlen(sendUrl);
    memset(&push->videoStatus, 0, sizeof(GJTrafficStatus));
    memset(&push->audioStatus, 0, sizeof(GJTrafficStatus));
    push->pushUrl = realloc(push->pushUrl,length + 1);
    memcpy(push->pushUrl, sendUrl, length + 1);
    if (push->sendThread) {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGWARNING, "上一个push没有释放，开始释放并等待");
        GJStreamPush_Close(push);
        pthread_join(push->sendThread, GNULL);
        GJLOG(STREAM_PUSH_LOG, GJ_LOGWARNING, "等待push释放结束");
    }
    push->stopRequest = GFalse;
    push->startMS = 0;
    queueEnablePush(push->sendBufferQueue, GTrue);
    queueEnablePop(push->sendBufferQueue, GTrue);
    char *format = GNULL;
    char preUrl[5];
    memcpy(preUrl, sendUrl, 4);
    preUrl[4] = 0;
    if (strcasecmp(preUrl, "rtmp") == 0) {
        format = "flv";
    }
    GInt32 ret = avformat_alloc_output_context2(&push->formatContext, GNULL, format, sendUrl);
    if (ret < 0) {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGFORBID, "ffmpeg 不知道该封装格式");
        return GFalse;
    }
    AVIOInterruptCB cb = {.callback = interrupt_callback, .opaque = push};
    push->formatContext->interrupt_callback = cb;
    AVDictionary* metadata = push->formatContext->metadata;
    av_dict_set_int(&metadata, "fps", 15, 0);
    av_dict_set(&metadata, "author", "GuangJin.Zhou", AV_DICT_MATCH_CASE);

    push->formatContext->metadata = metadata;
    AVCodec *audioCode = GNULL;
    AVCodec *videoCode = GNULL;

    if (push->videoFormat) {
        switch (push->videoFormat->format.mType) {
            case GJVideoType_H264:
                videoCode = avcodec_find_encoder(AV_CODEC_ID_H264);
                break;
            default:
                break;
        }
        if (videoCode == GNULL) {
            GJLOG(STREAM_PUSH_LOG, GJ_LOGFORBID, "ffmpeg 找不到视频编码器");
            return GFalse;
        }

        AVStream *vs             = avformat_new_stream(push->formatContext, videoCode);
        vs->codecpar->bit_rate   = push->videoFormat->bitrate;
        vs->codecpar->width      = push->videoFormat->format.mWidth;
        vs->codecpar->height     = push->videoFormat->format.mHeight;
        vs->codecpar->format     = AV_PIX_FMT_YUV420P;
        vs->codecpar->codec_type = AVMEDIA_TYPE_VIDEO;
        vs->codecpar->codec_id   = AV_CODEC_ID_H264;
        vs->time_base.num        = 1;
        vs->time_base.den        = 1000;
        push->vStream            = vs;
    }

    if (push->audioFormat) {
        switch (push->audioFormat->format.mType) {
            case GJAudioType_AAC:
                audioCode = avcodec_find_encoder(AV_CODEC_ID_AAC);
                break;
            default:
                break;
        }
        if (audioCode == GNULL) {
            GJLOG(STREAM_PUSH_LOG, GJ_LOGFORBID, "ffmpeg 找不到音频编码器");
            return GFalse;
        }

        AVStream *as              = avformat_new_stream(push->formatContext, audioCode);
        as->codecpar->channels    = push->audioFormat->format.mChannelsPerFrame;
        as->codecpar->bit_rate    = push->audioFormat->bitrate;
        as->codecpar->sample_rate = push->audioFormat->format.mSampleRate;
        as->codecpar->format      = AV_SAMPLE_FMT_S16;
        as->codecpar->codec_type  = AVMEDIA_TYPE_AUDIO;
        as->codecpar->codec_id    = AV_CODEC_ID_AAC;
        as->time_base.num         = 1;
        as->time_base.den         = 1000;
        push->aStream             = as;
    }
    pthread_create(&push->sendThread, GNULL, sendRunloop, push);
    return GTrue;
}

GVoid GJStreamPush_Delloc(GJStreamPush *push) {
    GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "GJStreamPush_Delloc:%p", push);

    GInt32 length = queueGetLength(push->sendBufferQueue);
    if (length > 0) {
        R_GJPacket **packet = (R_GJPacket **) malloc(sizeof(R_GJPacket *) * length);
        //queuepop已经关闭
        if (queueClean(push->sendBufferQueue, (GHandle *) packet, &length)) {
            for (GInt32 i = 0; i < length; i++) {
                R_BufferUnRetain(&packet[i]->retain);
            }
        }
        free(packet);
    }
    queueFree(&push->sendBufferQueue);
    _Pragma("GCC diagnostic ignored \"-Wdeprecated-declarations\"")
        avcodec_close(push->vStream->codec);
    avcodec_close(push->aStream->codec);
    _Pragma("GCC diagnostic warning \"-Wdeprecated-declarations\"")
    if (push->formatContext) {
        avformat_free_context(push->formatContext);
    }
    if (push->videoFormat) free(push->videoFormat);
    if (push->audioFormat) free(push->audioFormat);
    pipleNodeUnInit(&push->pipleNode);
    if (push->pushUrl != GNULL) {
        free(push->pushUrl);
    }
    free(push);
    GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "GJStreamPush_Delloc end:%p", push);
}
GVoid GJStreamPush_Release(GJStreamPush *push) {
    GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "GJStreamPush_Delloc::%p", push);

    GBool shouldDelloc    = GFalse;
    pthread_mutex_lock(&push->mutex);
    push->messageCallback = GNULL;
    push->releaseRequest = GTrue;
    if (push->sendThread == GNULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&push->mutex);
    if (shouldDelloc) {
        GJStreamPush_Delloc(push);
    }
}
GVoid GJStreamPush_Close(GJStreamPush *sender) {
    if (sender->stopRequest) {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "GJRtmpPush_Close：%p  重复关闭", sender);
    } else {
        GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "GJRtmpPush_Close:%p", sender);
        sender->stopRequest = GTrue;
        queueEnablePush(sender->sendBufferQueue, GFalse);
        queueEnablePop(sender->sendBufferQueue, GFalse);
    }
}
GVoid GJStreamPush_CloseAndDealloc(GJStreamPush **push) {
    GJLOG(STREAM_PUSH_LOG, GJ_LOGDEBUG, "GJStreamPush_CloseAndDealloc:%p", *push);
    GJStreamPush_Close(*push);
    GJStreamPush_Release(*push);
    *push = GNULL;
}
GBool GJStreamPush_SendVideoData(GJStreamPush *push, R_GJPacket *packet) {

    if (push == GNULL) return GFalse;
    
    if (G_TIME_IS_INVALID(push->videoStatus.enter.firstTs)) {
        if (packet->extendDataSize <= 0) {
            GJLOG(GNULL, GJ_LOGWARNING, "第一帧非关键帧 丢帧");
            return GTrue;
        }else{
            push->videoStatus.enter.firstTs = packet->dts;
            push->videoStatus.enter.firstClock = GJ_Gettime();
        }
#ifndef NETWORK_DELAY
        if (push->startMS <= 0) {
            push->startMS = GTimeMSValue(packet->dts);
        }
#endif
    }
    R_BufferRetain(&packet->retain);
    if (queuePush(push->sendBufferQueue, packet, 0)) {
        
        push->videoStatus.enter.ts = packet->dts;
        push->videoStatus.enter.count++;
        push->videoStatus.enter.byte += packet->dataSize;
        push->videoStatus.enter.clock = GJ_Gettime();

    } else {
        R_BufferUnRetain(&packet->retain);
    }

    return GTrue;
}
GBool GJStreamPush_SendAudioData(GJStreamPush *push, R_GJPacket *packet) {
    if (push == GNULL || G_TIME_IS_INVALID(push->videoStatus.enter.firstTs))return GFalse;

    if (G_TIME_IS_INVALID(push->audioStatus.enter.firstTs)) {
        if (GTimeMSValue(packet->dts) < GTimeMSValue(push->videoStatus.enter.firstTs)) {
            return GFalse;
        }else{
            push->audioStatus.enter.firstTs = packet->dts;
            push->audioStatus.enter.firstClock = GJ_Gettime();
        }
    }
    
    R_BufferRetain(&packet->retain);
    if (queuePush(push->sendBufferQueue, packet, 0)) {

        push->audioStatus.enter.ts = packet->dts;
        push->audioStatus.enter.count++;
        push->audioStatus.enter.byte += packet->dataSize;
    } else {
        R_BufferUnRetain(&packet->retain);
    }
    return GTrue;
}
GBool GJStreamPush_SendUncodeVideoData(GJStreamPush *push, R_GJPixelFrame *data) {
    return GTrue;
}
GBool GJStreamPush_SendUncodeAudioData(GJStreamPush *push, R_GJPCMFrame *data) {
    return GTrue;
}
GFloat32 GJStreamPush_GetBufferRate(GJStreamPush *push) {
    return 1.0;
}
GJTrafficStatus GJStreamPush_GetVideoBufferCacheInfo(GJStreamPush *push) {
    if (!push) return error_Status;

    GJTrafficStatus status = push->videoStatus;
    if(G_TIME_IS_INVALID(status.leave.ts)){
        status.leave = status.enter;
    }
    return status;
}
GJTrafficStatus GJStreamPush_GetAudioBufferCacheInfo(GJStreamPush *push) {
    if (!push) return error_Status;
    GJTrafficStatus status = push->audioStatus;
    if(G_TIME_IS_INVALID(status.leave.ts)){
        status.leave = status.enter;
    }
    return status;
    
}
