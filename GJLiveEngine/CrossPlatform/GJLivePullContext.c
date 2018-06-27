//
//  GJLivePullContext.c
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLivePullContext.h"
#include "GJLog.h"
#include "GJUtil.h"
#include <string.h>
#include <libavformat/avformat.h>

static const GJClass LivePullContextClass = {
    .className = "live pull context",
    .dLevel    = GJ_LOGDEBUG,
};

static GVoid pullMessageCallback(GJStreamPull *pull, GHandle receiver, kStreamPullMessageType messageType, GLong messageParm);
static GVoid livePlayCallback(GHandle userDate, GJPlayMessage message, GHandle param);
static GVoid pullDataCallback(GJStreamPull *pull, R_GJPacket *packet, void *parm);

static GVoid aacDecodeCompleteCallback(GHandle userData, R_GJPCMFrame *frame);
static GVoid h264DecodeCompleteCallback(GHandle userData, R_GJPixelFrame *frame);

GBool GJLivePull_Create(GJLivePullContext **pullContext, GJLivePullCallback callback, GHandle param) {
    GBool result = GFalse;
    do {
        if (*pullContext == GNULL) {
            *pullContext = (GJLivePullContext *) calloc(1, sizeof(GJLivePullContext));
            if (*pullContext == GNULL) {
                result = GFalse;
                break;
            }
        }
        GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePull_Create:%p", *pullContext);
        GJLivePullContext *context = *pullContext;
        context->callback          = callback;
        context->userData          = param;
        if (!GJLivePlay_Create(&context->player, livePlayCallback, context)) {
            result = GFalse;
            break;
        };
        //        GJ_FFDecodeContextCreate(&context->videoDecoder);
        GJ_H264DecodeContextCreate(&context->videoDecoder);
        GJ_AACDecodeContextCreate(&context->audioDecoder);

        if (!context->videoDecoder->decodeSetup(context->videoDecoder, GJPixelType_YpCbCr8BiPlanar_Full, h264DecodeCompleteCallback, context)) {
            result = GFalse;
            break;
        }
        GJAudioFormat destformat = {0};
        //内部根据包自己初始化
        if (!context->audioDecoder->decodeSetup(context->audioDecoder, destformat, aacDecodeCompleteCallback, context)) {
            result = GFalse;
            break;
        }
        context->priv_class = LivePullContextClass;
        pthread_mutex_init(&context->lock, GNULL);
    } while (0);
    return result;
}

GBool GJLivePull_StartPull(GJLivePullContext *context, const GChar *url) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePull_StartPull:%p", context);
    GBool result = GTrue;
    pthread_mutex_lock(&context->lock);
    do {
        if (context->streamPull != GNULL) {
            GJLOG(context, GJ_LOGERROR, "请先停止上一个流");
        } else {
            context->firstAudioDecodeClock = G_TIME_INVALID;
            context->firstAudioPullClock   = G_TIME_INVALID;
            context->firstVideoPullClock   = G_TIME_INVALID;
            context->connentClock          = G_TIME_INVALID;
            context->firstVideoDecodeClock = G_TIME_INVALID;
            context->audioUnDecodeByte = context->videoUnDecodeByte = 0;
            context->audioTraffic = context->videoTraffic = (GJTrafficStatus){0};

            if (!GJStreamPull_Create(&context->streamPull, (MessageHandle) pullMessageCallback, context)) {
                result = GFalse;
                break;
            };
            if (!GJStreamPull_StartConnect(context->streamPull, pullDataCallback, context, (const GChar *) url)) {
                result = GFalse;
                break;
            };
            if (!GJLivePlay_Start(context->player)) {
                result = GFalse;
                break;
            }
            context->startPullClock = GJ_Gettime();
            context->videoDecoder->decodeStart(context->videoDecoder);
            context->audioDecoder->decodeStart(context->audioDecoder);

            pipleConnectNode((GJPipleNode *) context->streamPull, &context->videoDecoder->pipleNode);
            pipleConnectNode((GJPipleNode *) context->streamPull, &context->audioDecoder->pipleNode);
        }
    } while (0);
    pthread_mutex_unlock(&context->lock);
    return result;
}
GVoid GJLivePull_StopPull(GJLivePullContext *context) {
    pthread_mutex_lock(&context->lock);
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePull_StartPull:%p", context);
    if (context->streamPull) {
        context->videoDecoder->decodeStop(context->videoDecoder);
        context->audioDecoder->decodeStop(context->audioDecoder);
        //先stop，再disconnect防止decoder queue满了，无法，streampull在阻塞状态
        pipleDisConnectNode((GJPipleNode *) context->streamPull, &context->audioDecoder->pipleNode);
        pipleDisConnectNode((GJPipleNode *) context->streamPull, &context->videoDecoder->pipleNode);
        GJStreamPull_CloseAndRelease(context->streamPull);
        context->streamPull = GNULL;
    } else {
        GJLOG(context, GJ_LOGWARNING, "重复停止拉流");
    }
    pipleDisConnectNode(&context->videoDecoder->pipleNode, &context->player->pipleNode);
    pipleDisConnectNode(&context->audioDecoder->pipleNode, &context->player->pipleNode);
    GJLivePlay_Stop(context->player);
    pthread_mutex_unlock(&context->lock);
}

GVoid GJLivePull_Pause(GJLivePullContext *context) {
    GJAssert(context != GNULL, "GJLivePullContext nil");
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePull_Pause:%p", context);
    pthread_mutex_lock(&context->lock);
    GJLivePlay_Pause(context->player);
    pthread_mutex_unlock(&context->lock);
}

GVoid GJLivePull_Resume(GJLivePullContext *context) {
    GJAssert(context != GNULL, "GJLivePullContext nil");
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePull_Resume:%p", context);
    pthread_mutex_lock(&context->lock);
    GJLivePlay_Resume(context->player);
    pthread_mutex_unlock(&context->lock);
}

GJTrafficStatus GJLivePull_GetVideoTrafficStatus(GJLivePullContext *context) {
    GJTrafficStatus status = GJLivePlay_GetVideoCacheInfo(context->player);
    status.enter.byte      = context->videoUnDecodeByte;
    return status;
}

GJTrafficStatus GJLivePull_GetAudioTrafficStatus(GJLivePullContext *context) {
    GJTrafficStatus status = GJLivePlay_GetAudioCacheInfo(context->player);
    status.enter.byte      = context->audioUnDecodeByte;
    return status;
}

#ifdef NETWORK_DELAY
GInt32 GJLivePull_GetNetWorkDelay(GJLivePullContext *context) {

    return (GInt32) GJLivePlay_GetNetWorkDelay(context->player);
}
#endif

GHandle GJLivePull_GetDisplayView(GJLivePullContext *context) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePull_GetDisplayView:%p", context);
    return GJLivePlay_GetVideoDisplayView(context->player);
}
GVoid GJLivePull_Dealloc(GJLivePullContext **pullContext) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePull_Dealloc:%p", *pullContext);
    GJLivePullContext *context = *pullContext;
    if (context == GNULL) {
        GJLOG(context, GJ_LOGERROR, "非法释放");
    } else {

        GJLivePlay_Dealloc(&context->player);
        context->videoDecoder->decodeUnSetup(context->videoDecoder);
        context->audioDecoder->decodeUnSetup(context->audioDecoder);

        GJ_H264DecodeContextDealloc(&context->videoDecoder);
        //        GJ_FFDecodeContextDealloc(&context->videoDecoder);
        GJ_AACDecodeContextDealloc(&context->audioDecoder);
        free(context);
        *pullContext = GNULL;
    }
}

static GVoid livePlayCallback(GHandle userDate, GJPlayMessage message, GHandle param) {
    GJLivePullContext *   livePull    = userDate;
    GJLivePullMessageType pullMessage = GJLivePull_messageInvalid;
    
    GJPullFirstFrameInfo info = {0};
    switch (message) {
        case GJPlayMessage_BufferStart:
            pullMessage = GJLivePull_bufferStart;
            break;
        case GJPlayMessage_BufferUpdate:
            pullMessage = GJLivePull_bufferUpdate;
            break;
        case GJPlayMessage_BufferEnd:
            pullMessage = GJLivePull_bufferEnd;
            break;
        case GJPlayMessage_FirstRender:
        {
            R_GJPixelFrame* frame = param;
            info.delay = GTimeSubtractMSValue(GJ_Gettime(), livePull->startPullClock);
            info.size.width = frame->width;
            info.size.height = frame->height;
            param = &info;
            pullMessage = GJLivePull_firstRender;
            break;
        }
        case GJPlayMessage_NetShakeUpdate:
            pullMessage = GJLivePull_netShakeUpdate;
            break;
        case GJPlayMessage_NetShakeRangeUpdate:
            pullMessage = GJLivePull_netShakeRangeUpdate;
            break;
#ifdef NETWORK_DELAY
        case GJPlayMessage_TestNetShakeUpdate:
            pullMessage = GJLivePull_testNetShakeUpdate;
            break;
        case GJPlayMessage_TestKeyDelayUpdate:
            pullMessage = GJLivePull_testKeyDelayUpdate;
            break;
#endif
        case GJPlayMessage_DewateringUpdate:
            pullMessage = GJLivePull_dewateringUpdate;
            break;

        default:
            break;
    }
    livePull->callback(livePull->userData, pullMessage, param);
}
static GVoid pullMessageCallback(GJStreamPull *pull, GHandle receiver, kStreamPullMessageType messageType, GLong messageParm) {
    GJLivePullContext *livePull = receiver;
    if (pull != livePull->streamPull) {
        return;
    }
    switch (messageType) {
        case kStreamPullMessageType_connectError:
        case kStreamPullMessageType_urlPraseError:
            GJLOG(livePull, GJ_LOGERROR, "pull connect error:%d", messageType);
            GJLivePull_StopPull(livePull);
            livePull->callback(livePull->userData, GJLivePull_connectError, "连接错误");
            break;
        case kStreamPullMessageType_receivePacketError:
            GJLOG(livePull, GJ_LOGERROR, "pull receivePacket error:%d", messageType);
            GJLivePull_StopPull(livePull);
            livePull->callback(livePull->userData, GJLivePull_receivePacketError, "读取失败");
            break;
        case kStreamPullMessageType_connectSuccess: {
            GJLOG(livePull, GJ_LOGDEBUG, "pull connectSuccess");
            livePull->connentClock = GJ_Gettime();
            GLong connentDur       = GTimeMSValue(GTimeSubtract(livePull->connentClock, livePull->startPullClock));

            livePull->callback(livePull->userData, GJLivePull_connectSuccess, &connentDur);
        } break;
        case kStreamPullMessageType_closeComplete: {
            GJLOG(livePull, GJ_LOGDEBUG, "pull closeComplete");
            GJPullSessionInfo info = {0};
            info.sessionDuring     = GTimeMSValue(GTimeSubtract(GJ_Gettime(), livePull->startPullClock));
            livePull->callback(livePull->userData, GJLivePull_closeComplete, (GHandle) &info);
        } break;
        case kStreamPullMessageType_receiveStream: {
            GJAssert(0, "不支持");
            AVStream *stream = (AVStream *) messageParm;
            if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                GJAssert(livePull->videoDecoder == GNULL, "视频解码器管理错误");
                GJ_FFDecodeContextCreate(&livePull->videoDecoder);

            } else if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {

            } else {
                GJAssert(0, "收到不支持的流格式");
            }
        } break;
        default:
            GJLOG(livePull, GJ_LOGFORBID, "not catch info：%d", messageType);
            break;
    }
}
//static const GInt32 mpeg4audio_sample_rates[16] = {
//    96000, 88200, 64000, 48000, 44100, 32000,
//    24000, 22050, 16000, 12000, 11025, 8000, 7350};

void pullDataCallback(GJStreamPull *pull, R_GJPacket *packet, void *parm) {
    GJLivePullContext *livePull = parm;
    if (pull != livePull->streamPull) {
        return;
    }
    if ((packet->flag & GJPacketFlag_AVPacketType) == GJPacketFlag_AVPacketType) {
        AVPacket avpacket = ((AVPacket *) R_BufferStart(packet))[0];
        if (packet->type == GJMediaType_Video) {

            livePull->videoUnDecodeByte += avpacket.size;
        } else {

            livePull->audioUnDecodeByte += avpacket.size;
        }
    } else {
        if (packet->type == GJMediaType_Video) {

            livePull->videoUnDecodeByte += R_BufferSize(&packet->retain);
        } else {

            livePull->audioUnDecodeByte += R_BufferSize(&packet->retain);
        }
    }
}
static GVoid aacDecodeCompleteCallback(GHandle userData, R_GJPCMFrame *frame) {
    GJLivePullContext *livePull = userData;
    if (G_TIME_IS_INVALID(livePull->firstAudioDecodeClock)) {
        GJAudioFormat destformat = livePull->audioDecoder->decodeGetDestFormat(livePull->audioDecoder);
        if (destformat.mSampleRate > 0) {
            //            pthread_mutex_lock(&livePull->lock);//调用stopAudio时，使用了信号机制，会等到此回调结束，所以不用锁
            if (livePull->streamPull) { //没有停止
                GJLivePlay_AddAudioSourceFormat(livePull->player, destformat);
                livePull->firstAudioDecodeClock = GJ_Gettime();

                pipleConnectNode(&livePull->audioDecoder->pipleNode, &livePull->player->pipleNode);
            }
            //            pthread_mutex_unlock(&livePull->lock);
        }
    }
}
static GVoid h264DecodeCompleteCallback(GHandle userData, R_GJPixelFrame *frame) {

    GJLivePullContext *pullContext = userData;
    if (unlikely(G_TIME_IS_INVALID(pullContext->firstVideoDecodeClock))) {
        GJLivePlay_AddVideoSourceFormat(pullContext->player, frame->type);
        pullContext->firstVideoDecodeClock = GJ_Gettime();
        GJPullFirstFrameInfo info = {0};
        info.delay = GTimeSubtractMSValue(pullContext->firstVideoDecodeClock, pullContext->startPullClock);
        info.size.width           = (GFloat) frame->width; //CGSizeMake((float)frame->width, (float)frame->height);
        info.size.height          = (GFloat) frame->height;
        pullContext->callback(pullContext->userData, GJLivePull_decodeFirstVideoFrame, &info);
        pipleConnectNode(&pullContext->videoDecoder->pipleNode, &pullContext->player->pipleNode);
    }
    return;
}


