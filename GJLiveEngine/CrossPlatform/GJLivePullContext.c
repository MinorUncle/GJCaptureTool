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

static const GJClass LivePullContextClass = {
    .className = "live pull context",
    .dLevel    = GJ_LOGNONE,
};

static void pullMessageCallback(GJStreamPull *pull, kStreamPullMessageType messageType, GHandle rtmpPullParm, GHandle messageParm);
static GVoid livePlayCallback(GHandle userDate, GJPlayMessage message, GHandle param);
static void pullDataCallback(GJStreamPull *pull, R_GJPacket *packet, void *parm);

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
        GJLivePullContext *context = *pullContext;
        context->callback          = callback;
        context->userData          = param;
        if (!GJLivePlay_Create(&context->player, livePlayCallback, context)) {
            result = GFalse;
            break;
        };
        GJ_H264DecodeContextCreate(&context->videoDecoder);
        GJ_AACDecodeContextCreate(&context->audioDecoder);

        if (!context->videoDecoder->decodeSetup(context->videoDecoder, GJPixelType_YpCbCr8BiPlanar_Full, h264DecodeCompleteCallback, context)) {
            result = GFalse;
            break;
        }
        context->priv_class = LivePullContextClass;
        pthread_mutex_init(&context->lock, GNULL);
    } while (0);
    return result;
}
GBool GJLivePull_StartPull(GJLivePullContext *context, const GChar *url) {
    GBool result = GTrue;
    do {
        pthread_mutex_lock(&context->lock);
        if (context->streamPull != GNULL) {
            GJLOG(context, GJ_LOGERROR, "请先停止上一个流");
        } else {
            context->fristAudioPullClock = context->fristVideoPullClock = context->connentClock = context->fristVideoDecodeClock = G_TIME_INVALID;
            context->audioUnDecodeByte = context->videoUnDecodeByte = 0;
            context->audioTraffic = context->videoTraffic = (GJTrafficStatus){0};

            if (!GJStreamPull_Create(&context->streamPull, pullMessageCallback, context)) {
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
            context->startPullClock = GJ_Gettime() / 1000;
        }
        pthread_mutex_unlock(&context->lock);
    } while (0);
    return result;
}
GVoid GJLivePull_StopPull(GJLivePullContext *context) {
    pthread_mutex_lock(&context->lock);
    if (context->streamPull) {
        GJStreamPull_CloseAndRelease(context->streamPull);
        context->streamPull = GNULL;
    } else {
        GJLOG(context, GJ_LOGWARNING, "重复停止拉流");
    }
    GJLivePlay_Stop(context->player);
    context->audioDecoder->decodeUnSetup(context->audioDecoder);
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
GInt32 GJLivePull_GetNetWorkDelay(GJLivePullContext *context){
    
    return GJStreamPull_GetNetWorkDelay(context->streamPull);
}
#endif

GHandle GJLivePull_GetDisplayView(GJLivePullContext *context) {
    return GJLivePlay_GetVideoDisplayView(context->player);
}
GVoid GJLivePull_Dealloc(GJLivePullContext **pullContext) {
    GJLivePullContext *context = *pullContext;
    if (context == GNULL) {
        GJLOG(context, GJ_LOGERROR, "非法释放");
    } else {

        GJLivePlay_Dealloc(&context->player);
        context->videoDecoder->decodeUnSetup(context->videoDecoder);
        GJ_H264DecodeContextDealloc(&context->videoDecoder);
        GJ_AACDecodeContextDealloc(&context->audioDecoder);

        free(context);
        *pullContext = GNULL;
    }
}

static GVoid livePlayCallback(GHandle userDate, GJPlayMessage message, GHandle param) {
    GJLivePullContext *   livePull    = userDate;
    GJLivePullMessageType pullMessage = GJLivePull_messageInvalid;
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
        case GJPlayMessage_FristRender:
            pullMessage = GJLivePull_fristRender;
            break;
        case GJPlayMessage_NetShakeUpdate:
            pullMessage = GJLivePull_netShakeUpdate;
            break;
        case GJPlayMessage_DewateringUpdate:
            pullMessage = GJLivePull_dewateringUpdate;
            break;
        default:
            break;
    }
    livePull->callback(livePull->userData, pullMessage, param);
}
static GVoid pullMessageCallback(GJStreamPull *pull, kStreamPullMessageType messageType, GHandle rtmpPullParm, GHandle messageParm) {
    GJLivePullContext *livePull = rtmpPullParm;
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
            GJLOG(livePull, GJ_LOGINFO, "pull connectSuccess");
            livePull->connentClock = GJ_Gettime() / 1000.0;
            GTime connentDur       = livePull->connentClock - livePull->startPullClock;
            livePull->callback(livePull->userData, GJLivePull_connectSuccess, &connentDur);
        } break;
        case kStreamPullMessageType_closeComplete: {
            GJLOG(livePull, GJ_LOGINFO, "pull closeComplete");
            GJPullSessionInfo info = {0};
            info.sessionDuring     = GJ_Gettime() / 1000 - livePull->startPullClock;
            livePull->callback(livePull->userData, GJLivePull_closeComplete, (GHandle) &info);
        } break;
        default:
            GJLOG(livePull, GJ_LOGFORBID, "not catch info：%d", messageType);
            break;
    }
}
static const GInt32 mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350};

void pullDataCallback(GJStreamPull *pull, R_GJPacket *packet, void *parm) {
    GJLivePullContext *livePull = parm;
    if (pull != livePull->streamPull) {
        return;
    }
    
    if (packet->type == GJMediaType_Video) {

        livePull->videoUnDecodeByte += R_BufferSize(&packet->retain);
        livePull->videoDecoder->decodePacket(livePull->videoDecoder, packet);
    } else {

        livePull->audioUnDecodeByte += R_BufferSize(&packet->retain);
        if (livePull->fristAudioPullClock == G_TIME_INVALID) {
            if (packet->extendDataSize > 0 && packet->flag == GJPacketFlag_KEY) {
                livePull->fristAudioPullClock = GJ_Gettime() / 1000.0;
                uint8_t *adts                 = packet->extendDataOffset + R_BufferStart(&packet->retain);
                uint8_t  sampleIndex          = adts[2] << 2;
                sampleIndex                   = sampleIndex >> 4;
                int     sampleRate            = mpeg4audio_sample_rates[sampleIndex];
                uint8_t channel               = (adts[2] & 0x1) << 2;
                channel += (adts[3] & 0xc0) >> 6;

                GJAudioFormat sourceformat     = {0};
                sourceformat.mType             = GJAudioType_AAC;
                sourceformat.mChannelsPerFrame = channel;
                sourceformat.mSampleRate       = sampleRate;
                sourceformat.mFramePerPacket   = 1024;

                //            AudioStreamBasicDescription sourceformat = {0};
                //            sourceformat.mFormatID = kAudioFormatMPEG4AAC;
                //            sourceformat.mChannelsPerFrame = channel;
                //            sourceformat.mSampleRate = sampleRate;
                //            sourceformat.mFramesPerPacket = 1024;
                GJAudioFormat destformat   = sourceformat;
                destformat.mBitsPerChannel = 16;
                destformat.mFramePerPacket = 1;
                destformat.mType           = GJAudioType_PCM;

                //            AudioStreamBasicDescription destformat = {0};
                //            destformat.mFormatID = kAudioFormatLinearPCM;
                //            destformat.mSampleRate       = sourceformat.mSampleRate;               // 3
                //            destformat.mChannelsPerFrame = sourceformat.mChannelsPerFrame;                     // 4
                //            destformat.mFramesPerPacket  = 1;                     // 7
                //            destformat.mBitsPerChannel   = 16;                    // 5
                //            destformat.mBytesPerFrame   = destformat.mChannelsPerFrame * destformat.mBitsPerChannel/8;
                //            destformat.mFramesPerPacket = destformat.mBytesPerFrame * destformat.mFramesPerPacket ;
                //            destformat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
                pthread_mutex_lock(&livePull->lock);
                if (livePull->streamPull) {
                    livePull->audioDecoder->decodeSetup(livePull->audioDecoder, sourceformat, destformat, aacDecodeCompleteCallback, livePull);
                    GJLivePlay_SetAudioFormat(livePull->player, destformat);
                }

                pthread_mutex_unlock(&livePull->lock);
                return;
            } else {
                GJLOG(livePull, GJ_LOGFORBID, "音频没有adts");
                return;
            }
        }
        livePull->audioDecoder->decodePacket(livePull->audioDecoder, packet);
    }
}
static GVoid aacDecodeCompleteCallback(GHandle userData, R_GJPCMFrame *frame) {
    GJLivePullContext *pullContext = userData;
    GJLivePlay_AddAudioData(pullContext->player, frame);
}
static GVoid h264DecodeCompleteCallback(GHandle userData, R_GJPixelFrame *frame) {

    GJLivePullContext *pullContext = userData;
    if (pullContext->fristVideoPullClock == G_TIME_INVALID) {
        pullContext->fristVideoPullClock = GJ_Gettime() / 1000.0;
        GJLivePlay_SetVideoFormat(pullContext->player, frame->type);
        GJPullFristFrameInfo info = {0};
        info.size.width           = (GFloat32) frame->width; //CGSizeMake((float)frame->width, (float)frame->height);
        info.size.height          = (GFloat32) frame->height;
        pullContext->callback(pullContext->userData, GJLivePull_decodeFristVideoFrame, &info);

        //        pullContext->callback();
    }
    GJLivePlay_AddVideoData(pullContext->player, frame);
        return;
}


