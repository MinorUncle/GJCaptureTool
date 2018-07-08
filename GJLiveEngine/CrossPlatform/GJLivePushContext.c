//
//  GJLivePushContext.c
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLivePushContext.h"
#include "GJLiveDefine.h"
#include "GJLog.h"
#include "GJUtil.h"

#include <unistd.h>
#define LIVEPUSH_LOG GNULL
//#define I_P_RATE 4   不需用，按照平均降码率来
//#define DROP_BITRATE_RATE 0.1     //最小码率与最大码率之间的分割比率   //修改，采用帧率,每次调整大小为当前码率除以帧率，所以当前网速越小，则码率越小，调整步伐越小。
//#define NET_ADD_STEP 8 * 1024 * 5 //5KB                          //修改，context->videoBitrate/context->pushConfig->mFps)

//#define NET_ADD_STEP_B  1000  //每步增加的码率
//#define NET_ADD_STEP_R  0.1   //每步增加的比例
#define NET_SENSITIVITY 300
#define NET_SENSITIVITY_MAX 2000

/*表示每 NET_SENSITIVITY ms检查一次网速，并计算该时间段内平均值，同时缓存允许在此阈值之内，超过此阈值则开始降码率算法。此值越小，则检查间隔越断，检查频率高，网络反应更灵敏，适用于良好网络。此值越大则检查间隔越长，检查频率低，网络反应更迟钝，适用于差网络。
    所以灵敏度会根据网络状况修改，网络变差，此值增大，但是最大值为NET_SENSITIVITY_MAX
 
 */
#define NET_MIN_CHECK_STEP 5 //最小的检查网速帧数间隔 ，默认是NET_SENSITIVITY ms检查一次网速,
#define NET_CONTINUOUS_DURING 1000
#define NET_CONTINUOUS_DURING_MIN 300
/*连续网速良好时间为NET_CONTINUOUS_DURING则增加网速,但是网络差时抖动比较厉害，同时缓存阈值也提高了，所以NET_AVG_DURING应该适当减少，防止网络差时，码率很难上升
 */
//#define NET_INCERASE_DURING (NET_AVG_DURING/NET_SENSITIVITY)*1  //网速增加速度,NET_INCERASE_DURING次连续检查网速良好时增加网速，  动态计算

#define NET_AVG_DURING 5000         //平均网速时间为最近NET_AVG_DURING ms内的发送速率。
#define NET_MIN_SENSITIVITY_FRAME 3 //类似NET_SENSITIVITY，在帧数上做最小限制，防止丢帧过多时，每一帧时间都比较长，导致就算缓存了一帧也进入降码率
#define MAX_DELAY -1                //in ms，最大延迟，全速丢帧，小于0表示没有最大限制，根据动态调整
#define RESTORE_DROP_RATE (3 / 4.0) //延迟减少到MAX_DELAY *  RESTORE_DROP_RATE后恢复连续丢帧

#define INVALID_SPEED GINT32_MIN

#ifdef RVOP
static rvop_server_p rvopserver;
#endif

#ifdef RAOP
static raop_server_p raopServer;
#endif

static pthread_t serverThread;
static GBool     requestStopServer;
static GBool     requestDestoryServer;

//static GVoid _GJLivePush_AppendQualityWithStep(GJLivePushContext *context, GLong step, GInt32 maxLimit);
//static GVoid _GJLivePush_reduceQualityWithStep(GJLivePushContext *context, GLong step, GInt32 minLimit);
static GVoid _GJLivePush_SetCodeBitrate(GJLivePushContext *context, GInt32 destRate);
static GVoid _GJLivePush_UpdateQualityInfo(GJLivePushContext *context, GInt32 bitrate);
static GVoid _livePushUpdateCongestion(GJLivePushContext *context, GInt32 netSpeed);

static GVoid _GJLivePush_CheckBufferCache(GJLivePushContext *context, GJTrafficStatus vBufferStatus, GJTrafficStatus aBufferStatus) {
    //    static  int checkCount = 0;
    //    GJLOG(GNULL, GJ_LOGDEBUG,"checkCount:%d",checkCount++);
    GLong cacheInCount = vBufferStatus.enter.count - vBufferStatus.leave.count;
    //    cacheInCount = GMAX(cacheInCount,aBufferStatus.enter.count - aBufferStatus.leave.count);//只考虑视频，
    if (cacheInCount > 0) {
        context->favorableCount = 0;
        context->increaseCount  = 0;
    } else {
        context->favorableCount++;
    }
    GTime cacheTime  = GTimeSubtract(vBufferStatus.enter.ts, vBufferStatus.leave.ts);
    GLong cacheInPts = GTimeMSValue(cacheTime);
    if (context->checkCount++ % context->rateCheckStep == 0) {
        if (GTimeSubtractMSValue(GJ_Gettime(), vBufferStatus.enter.clock) < (1000.0 / context->pushConfig->mFps) / 2) {
            //如果发送间隔很短，则表示是b帧，无论是网络好还是差，都不准确，过滤不检查，同时checkCount--表示下一帧在检查。
            context->checkCount--;
        } else {
            //            GJLOG(GNULL,GJ_LOGDEBUG,"free level time:%lld enter time:%lld cache count:%ld\n",currentTime-vBufferStatus.leave.clock,currentTime-vBufferStatus.enter.clock,vBufferStatus.enter.count - vBufferStatus.leave.count);
            GLong sendCount = vBufferStatus.leave.count - context->preCheckVideoTraffic.leave.count;

            GLong sendByte        = (vBufferStatus.leave.byte - context->preCheckVideoTraffic.leave.byte);
            GLong sendUseTs       = GTimeSubtractMSValue(vBufferStatus.leave.clock, context->preCheckVideoTraffic.leave.clock);                  //发送消耗的时间
            sendUseTs             = GMIN(sendUseTs, GTimeSubtractMSValue(vBufferStatus.enter.clock, context->preCheckVideoTraffic.enter.clock)); //一定要取两个时间最小的那个
            GInt32 currentBitRate = 0;
            if (sendUseTs != 0) {
                currentBitRate = sendByte * 8 / (sendUseTs / 1000.0);
            }

            if (cacheInCount > 0) {
                //快降慢升

                context->netSpeedUnit[context->collectCount++ % context->netSpeedCheckInterval] = currentBitRate;
                //允许1帧的抖动，（会导致丢帧率大（网速低）时，rateCheckStep比较小，稍微不容易降低网速）
                if (sendCount < context->rateCheckStep - 1 && cacheInPts > context->sensitivity && cacheInCount > NET_MIN_SENSITIVITY_FRAME) {
                    GInt32 fullCount       = 0;
                    GInt32 totalCount      = 0;
                    context->videoNetSpeed = 0;
                    for (int i = 0; i < context->netSpeedCheckInterval; i++) {
                        if (context->netSpeedUnit[i] >= 0) {
                            context->videoNetSpeed += context->netSpeedUnit[i];
                            fullCount++;
                            totalCount++;
                        } else if (context->netSpeedUnit[i] != INVALID_SPEED) {
                            context->videoNetSpeed += -context->netSpeedUnit[i]; //受限网速是负数标志
                            totalCount++;
                        }
                    }
                    context->videoNetSpeed /= totalCount;
                    //count越大越准确
                    GJLOG(GNULL, GJ_LOGDEBUG, "busy status, avgRate :%f kB/s currentRate:%f sendByte:%ld cacheCount:%ld cacheTime:%ld ms speedUnitCount:%d", context->videoNetSpeed / 8.0 / 1024, currentBitRate / 8.0 / 1024, sendByte, cacheInCount, cacheInPts, fullCount);
                    GJAssert(context->videoNetSpeed >= 0, "错误");
                    GJAssert(sendUseTs > 0 || sendByte == 0, "错误");

                    if (context->videoNetSpeed > context->videoBitrate) {
                        GJLOG(LOG_DEBUG, GJ_LOGDEBUG, "警告:平均网速（%f）大于码率（%f），仍然出现缓存上升（可能出现网速突然下降）,继续降速", context->videoNetSpeed / 8.0 / 1024, context->videoBitrate / 8.0 / 1024);
                        context->videoNetSpeed = context->videoBitrate;
                    }
                    //减速的目标是比网速小，以减少缓存
                    context->videoNetSpeed -= context->videoBitrate / context->pushConfig->mFps;
                    //发送数量越少降速越快
                    GFloat ratioStep = (context->rateCheckStep - sendCount) * 1.0 / context->rateCheckStep;
                    //满速发送时间越长，网速越可靠
                    GFloat ratioFullCount = fullCount * 1.0 / context->netSpeedCheckInterval;
                    GFloat ratio          = (ratioStep + ratioFullCount) / 2;
                    GJAssert(ratio <= 1.0, "错误");

                    GInt32 bitrate = context->videoBitrate - (context->videoBitrate - context->videoNetSpeed) * ratio;
                    //bitrate = bitrate - (GInt32)(context->rateCheckStep - sendCount) * context->pushConfig->mVideoBitrate/context->pushConfig->mFps;
                    _GJLivePush_UpdateQualityInfo(context, bitrate);
                }
            } else {
                GJLOG(GNULL, GJ_LOGINFO, "favorableCount count:%d", context->favorableCount);
                GInt32 increaseStep = context->favorableCount / (context->rateCheckStep * context->increaseSpeedRate);
                if (increaseStep > context->increaseCount) {
                    //                    GJAssert(context->increaseCount+1 == increaseStep, "都是一步一步加");//好吧，不一定
                    context->increaseCount = increaseStep;

                    if (currentBitRate > context->pushConfig->mVideoBitrate) { //不能大于最大，防止误差扩散
                        currentBitRate = context->pushConfig->mVideoBitrate;
                    }
                    if (currentBitRate < context->videoBitrate) { //不能小于码率，防止误差扩散
                        currentBitRate = context->videoBitrate;
                    }
                    GJLOG(GNULL, GJ_LOGINFO, "update space speed:%0.02f kBps，count:%d", -currentBitRate / 8.0 / 1024, context->increaseCount);

                    context->netSpeedUnit[context->collectCount++ % context->netSpeedCheckInterval] = -currentBitRate;                       //更新当前的网速到当前码率
                    int collectCount                                                                = context->collectCount - 1;             //当前的collectCount，因为前面++了，所以需要-1,
                    if (collectCount > 0 && context->netSpeedUnit[(collectCount - 1) % context->netSpeedCheckInterval] != -currentBitRate) { //比较前一个码率，因为可能以前设置过,(当网络极好的时候会一直是最大码率)，可以减少重复设置

                        for (int i = 1; i < context->increaseCount - 1; i++) {
                            //因为一直有空闲，所以前面连续空闲的网速一定大于此网速，更新前面的受限满速到当前码率（不是受限情况不更新）;

                            context->netSpeedUnit[(collectCount - i) % context->netSpeedCheckInterval] = -currentBitRate;
                        }
                    }

                    if (context->videoBitrate < context->pushConfig->mVideoBitrate) {
                        GInt32 bitrate = currentBitRate + context->videoBitrate / context->pushConfig->mFps;
                        _GJLivePush_UpdateQualityInfo(context, bitrate);
                    }
                }
            }

            context->preCheckVideoTraffic = vBufferStatus;
        }
    }

    if (context->maxVideoDelay > 0 && cacheInPts >= context->maxVideoDelay && context->videoDropStep.num != context->videoDropStep.den) {
        context->videoDropStepBack = context->videoDropStep;
        context->videoDropStep     = GRationalMake(1, 1);
        GJLOG(GNULL, GJ_LOGDEBUG, "缓存大于maxVideoDelay set video drop step (1,1)\n");
    }
}

static GVoid h264PacketOutCallback(GHandle userData, R_GJPacket *packet) {

    GJLivePushContext *context = userData;
    if (G_TIME_IS_INVALID(context->firstVideoEncodeClock)) {
        if ((packet->flag & GJPacketFlag_KEY) == GJPacketFlag_KEY) {
            //            GJAssert(packet->flag && GJPacketFlag_KEY, "第一帧非关键帧");
            context->preCheckVideoTraffic  = GJStreamPush_GetVideoBufferCacheInfo(context->streamPush);
            context->firstVideoEncodeClock = GJ_Gettime();
        }
    } else {
        GJTrafficStatus vbufferStatus = GJStreamPush_GetVideoBufferCacheInfo(context->streamPush);
        GJTrafficStatus aBufferStatus = GJStreamPush_GetAudioBufferCacheInfo(context->streamPush);
        _GJLivePush_CheckBufferCache(context, vbufferStatus, aBufferStatus);
    }
}

static GVoid streamRecodeMessageCallback(GJStreamPush *push, GHandle userData, kStreamPushMessageType messageType, GHandle messageParm) {
    GJLivePushContext *context = userData;
    switch (messageType) {
        case kStreamPushMessageType_connectSuccess: {
            pipleConnectNode((GJPipleNode *) context->audioEncoder, (GJPipleNode *) context->streamRecode); //录制是生产器和编码器已经连接好了，如果没有，则无法录制，连接成功后再连接到录制器
            pipleConnectNode((GJPipleNode *) context->videoEncoder, (GJPipleNode *) context->streamRecode);
            break;
        }
        case kStreamPushMessageType_closeComplete: {
            pthread_mutex_lock(&context->lock);
            context->callback(context->userData, GJLivePush_recodeSuccess, GNULL);
            pthread_mutex_unlock(&context->lock);
            break;
        }
        case kStreamPushMessageType_urlPraseError: {
            pthread_mutex_lock(&context->lock);
            GJLivePush_StopRecode(context);
            context->callback(context->userData, GJLivePush_recodeFaile, GNULL);
            pthread_mutex_unlock(&context->lock);
            break;
        }
        case kStreamPushMessageType_sendPacketError: {
            pthread_mutex_lock(&context->lock);
            GJLivePush_StopRecode(context);
            context->callback(context->userData, GJLivePush_recodeFaile, GNULL);
            pthread_mutex_unlock(&context->lock);
            break;
        }
        default:
            break;
    }
}
static GVoid streamPushMessageCallback(GJStreamPush *sender, GJLivePushContext *receive, kStreamPushMessageType messageType, GLong messageParm) {

    GJLivePushContext *context = receive;
    if (sender != context->streamPush) return;

    switch (messageType) {
        case kStreamPushMessageType_connectSuccess: {
            context->connentClock = GJ_Gettime(); //推流是先连接流与解码器管道，连接成功后再连接生产器和编码器
            pipleConnectNode((GJPipleNode *) context->videoProducer, (GJPipleNode *) context->videoEncoder);
            pipleConnectNode((GJPipleNode *) context->audioProducer, (GJPipleNode *) context->audioEncoder);

            GTime time   = GTimeSubtract(context->connentClock, context->startPushClock);
            GLong during = (GLong) GTimeMSValue(time);
            context->callback(context->userData, GJLivePush_connectSuccess, &during);
        } break;
        case kStreamPushMessageType_closeComplete: {
            GJPushSessionInfo info   = {0};
            context->disConnentClock = GJ_Gettime();
            GTime time               = GTimeSubtract(context->disConnentClock, context->connentClock);
            info.sessionDuring       = (GLong) GTimeMSValue(time);
            context->callback(context->userData, GJLivePush_closeComplete, &info);
        } break;
        case kStreamPushMessageType_urlPraseError:
        case kStreamPushMessageType_connectError:
            GJLivePush_StopPush(context);
            context->callback(context->userData, GJLivePush_connectError, "rtmp连接失败");
            break;
        case kStreamPushMessageType_sendPacketError:
            GJLivePush_StopPush(context);
            context->callback(context->userData, GJLivePush_sendPacketError, "发送失败");
            break;
        case kStreamPushMessageType_packetSendSignal: {
            GJMediaType packetType = (GJMediaType) messageParm;
            if (packetType == GJMediaType_Video && GRationalValue(context->videoDropStep) >= 0.9999) {
                GJTrafficStatus vbufferStatus = GJStreamPush_GetVideoBufferCacheInfo(context->streamPush);
                GJTrafficStatus abufferStatus = GJStreamPush_GetAudioBufferCacheInfo(context->streamPush);

                GLong cacheInPts   = GTimeSubtractMSValue(vbufferStatus.enter.ts, vbufferStatus.leave.ts);
                GLong cacheInCount = vbufferStatus.enter.count - vbufferStatus.leave.count;
                GJLOG(GNULL, GJ_LOGDEBUG, "cacheInPts:%ld,cacheInCount:%ld", cacheInPts, cacheInCount);
                if (cacheInPts < context->maxVideoDelay * RESTORE_DROP_RATE || cacheInCount <= 1) {
                    context->videoDropStep = context->videoDropStepBack;
                    context->videoProducer->setDropStep(context->videoProducer, context->videoDropStep);
                    GJLOG(GNULL, GJ_LOGDEBUG, "set video drop step (%d,%d)\n", context->videoDropStep.num, context->videoDropStep.den);
                } else {
                    _GJLivePush_CheckBufferCache(context, vbufferStatus, abufferStatus);
                }
            }
        }
        default:
            break;
    }
}
static void _GJLivePush_SetCodeBitrate(GJLivePushContext *context, GInt32 destRate) {
    if (context->videoBitrate - destRate > 10 || context->videoBitrate - destRate < 10) {

        if (context->videoEncoder->encodeSetBitrate(context->videoEncoder, destRate)) {
            GJLOG(GNULL, GJ_LOGDEBUG, "Set Video Bitrate:%0.2f kB/s", destRate / 8.0 / 1024);

            context->videoBitrate = destRate;

            VideoDynamicInfo info;
            info.sourceFPS     = context->pushConfig->mFps;
            info.sourceBitrate = context->pushConfig->mVideoBitrate;
            if (context->videoDropStep.den > 0) {
                info.currentFPS = info.sourceFPS * (1 - GRationalValue(context->videoDropStep));
            } else {
                info.currentFPS = info.sourceFPS;
            }
            info.currentBitrate = destRate;
            context->callback(context->userData, GJLivePush_dynamicVideoUpdate, &info);
        }
    }
}

static void _GJLivePush_UpdateQualityInfo(GJLivePushContext *context, GInt32 destRate) {
    if (destRate <= 0) {
        destRate = 2 * 8000;
    }
    GJNetworkQuality quality       = GJNetworkQualityGood;
    GRational        videoDropStep = GRationalMake(0, 1);
    if (destRate >= context->pushConfig->mVideoBitrate - 0.001) {

        quality  = GJNetworkQualityExcellent;
        destRate = context->pushConfig->mVideoBitrate;
    } else if (destRate >= context->videoMinBitrate) { //大于不丢帧最小允许码率

        //        if (destRate * 2 >= context->videoMinBitrate + context->pushConfig->mVideoBitrate) {
        //            quality = GJNetworkQualityGood;
        //        }else{
        //            quality = GJNetworkQualitybad;
        //        }
        //修改为不丢帧则是good
        quality = GJNetworkQualityGood;
    } else {
        GInt32 minLimit                   = context->videoMinBitrate * (1 - GRationalValue(context->videoMaxDropRate));
        if (destRate < minLimit) destRate = minLimit;
        if (destRate <= 0.00001) {
            //表示一直丢帧，Terrible
            videoDropStep.den = videoDropStep.num = 1;
            quality                               = GJNetworkQualityTerrible;
        } else if (destRate <= context->videoMinBitrate * 0.5) {
            videoDropStep.den = context->videoMinBitrate / destRate;
            videoDropStep.num = videoDropStep.den - 1;
            //丢帧大于一半，Terrible
            quality = GJNetworkQualityTerrible;
        } else {
            videoDropStep = GRationalMake(1, 1.0 / (1.0 - destRate * 1.0 / context->videoMinBitrate));
            //丢帧小于一半，bad，
            quality = GJNetworkQualitybad;
        }
    }

    if (quality != context->netQuality) {
        context->callback(context->userData, GJLivePush_updateNetQuality, &quality);
        context->netQuality = quality;
    }
    if (context->videoBitrate != destRate) {
        context->videoBitrate = destRate;
        _GJLivePush_SetCodeBitrate(context, destRate);
    }
    if (!GRationalEqual(videoDropStep, context->videoDropStep)) {
        if (videoDropStep.num == videoDropStep.den && context->videoDropStep.num != context->videoDropStep.den) {
            context->videoDropStepBack = context->videoDropStep;
        }
        context->videoDropStep = videoDropStep;
        GJLOG(LOG_DEBUG, GJ_LOGDEBUG, "update drop step num:%d,den:%d", videoDropStep.num, videoDropStep.den);
        context->videoProducer->setDropStep(context->videoProducer, videoDropStep);
    }
    _livePushUpdateCongestion(context, context->videoBitrate);
}

static void *thread_pthread_head(void *ctx) {
    pthread_setname_np("Loop.GJ_RAOP");
#ifdef RAOP
    struct raop_server_settings_t setting;
    setting.name                 = GNULL;
    setting.password             = GNULL;
    setting.ignore_source_volume = GFalse;

    if (raopServer == GNULL) {

        raopServer = raop_server_create(setting, ctx);
    }

    if (!raop_server_is_running(raopServer)) {

        uint16_t port = 5000;
        while (port < 5010 && !raop_server_start(raopServer, port++))
            ;
    }

    if (requestStopServer) {

        raop_server_stop(raopServer);
    }
    serverThread = GNULL;

#endif

#ifdef RVOP
    struct rvop_server_settings_t setting;
    setting.name                 = GNULL;
    setting.password             = GNULL;
    setting.ignore_source_volume = GFalse;
    if (rvopserver == GNULL) {
        rvopserver = rvop_server_create(setting);
    }

    if (!rvop_server_is_running(rvopserver)) {

        uint16_t port = 5000;
        while (port < 5010 && !rvop_server_start(rvopserver, port++))
            ;
    }
    if (requestStopServer) {
        rvop_server_stop(rvopserver);
        rvopserver = NULL;
    }
#endif
    serverThread = GNULL;
    pthread_exit(0);
}

GBool GJLivePush_Create(GJLivePushContext **pushContext, GJLivePushCallback callback, GHandle param) {
    GBool result = GFalse;
    do {
        if (*pushContext == GNULL) {
            *pushContext = (GJLivePushContext *) calloc(1, sizeof(GJLivePushContext));
            if (*pushContext == GNULL) {
                result = GFalse;
                break;
            }
        }
        GJLivePushContext *context = *pushContext;
        context->callback          = callback;
        context->userData          = param;
        GJ_H264EncodeContextCreate(&context->videoEncoder);
        GJ_AACEncodeContextCreate(&context->audioEncoder);

        pthread_mutex_init(&context->lock, GNULL);
        context->maxVideoDelay = MAX_DELAY;

#ifdef RAOP
        requestStopServer = GFalse;
        if (serverThread == GNULL) {
            pthread_create(&serverThread, GNULL, thread_pthread_head, context);
        }
#endif
    } while (0);
    return result;
}

GVoid GJLivePush_AttachAudioProducer(GJLivePushContext *context, GJAudioProduceContext *audioProducer) {
    GJAssert(context->audioEncoder != GNULL && context->audioProducer == GNULL && audioProducer != GNULL, "状态错误");
    context->audioProducer = audioProducer;
}
GVoid GJLivePush_DetachAudioProducer(GJLivePushContext *context) {
    if (context->audioProducer) {
        context->audioProducer = GNULL;
    }
}
GVoid GJLivePush_AttachVideoProducer(GJLivePushContext *context, GJVideoProduceContext *videoProducer) {
    GJAssert(context->videoEncoder != GNULL && context->videoProducer == GNULL && videoProducer != GNULL, "状态错误");
    context->videoProducer = videoProducer;
}
GVoid GJLivePush_DetachVideoProducer(GJLivePushContext *context) {
    if (context->videoProducer) {
        context->videoProducer = GNULL;
    }
}

GVoid GJLivePush_SetConfig(GJLivePushContext *context, const GJPushConfig *config) {
    if (context == GNULL) {
        return;
    }

    pthread_mutex_lock(&context->lock);
    if (context->streamPush != GNULL) {
        GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "推流期间不能配置pushconfig");
    } else {
        if (context->pushConfig == GNULL) {
            context->pushConfig = (GJPushConfig *) malloc(sizeof(GJPushConfig));
        } else {

            if (config->mAudioChannel != context->pushConfig->mAudioChannel ||
                config->mAudioSampleRate != context->pushConfig->mAudioSampleRate) {
                if (context->audioEncoder) {
                    context->audioEncoder->encodeUnSetup(context->audioEncoder);
                }

            } else if (config->mAudioBitrate != context->pushConfig->mAudioBitrate) {
                if (context->audioEncoder) {
                    context->audioEncoder->encodeUnSetup(context->audioEncoder);
                }
            }

            if (config->mVideoBitrate != context->pushConfig->mVideoBitrate ||
                !GSizeEqual(config->mPushSize, context->pushConfig->mPushSize)) {
                if (context->videoEncoder) {
                    context->videoEncoder->encodeUnSetup(context->videoEncoder);
                }
            }
        }

        //        GJPixelFormat format;
        //        format.mHeight = config->mPushSize.height;
        //        format.mWidth = config->mPushSize.width;
        //        format.mType =  GJPixelType_YpCbCr8BiPlanar_Full;
        //        context->videoProducer->setVideoFormat(context->videoProducer,format);
        //        context->videoProducer->setFrameRate(context->videoProducer,config->mFps);
        //
        //        GJAudioFormat aFormat     = {0};
        //        aFormat.mBitsPerChannel   = 16;
        //        aFormat.mType             = GJAudioType_PCM;
        //        aFormat.mFramePerPacket   = 1;
        //        aFormat.mSampleRate       = config->mAudioSampleRate;
        //        aFormat.mChannelsPerFrame = config->mAudioChannel;
        //        context->audioProducer->setAudioFormat(context->audioProducer,aFormat);

        *(context->pushConfig) = *config;
    }
    pthread_mutex_unlock(&context->lock);
}

GBool _livePushSetupAudioEncodeIfNeed(GJLivePushContext *context) {
    GBool         result      = GTrue;
    GJAudioFormat aFormat     = {0};
    aFormat.mBitsPerChannel   = 16;
    aFormat.mType             = GJAudioType_PCM;
    aFormat.mFramePerPacket   = 1;
    aFormat.mSampleRate       = context->pushConfig->mAudioSampleRate;
    aFormat.mChannelsPerFrame = context->pushConfig->mAudioChannel;

    GJAudioStreamFormat aDFormat;
    aDFormat.bitrate                = context->pushConfig->mAudioBitrate;
    aDFormat.format                 = aFormat;
    aDFormat.format.mFramePerPacket = 1024;
    aDFormat.format.mType           = GJAudioType_AAC;

    GJLOG(LIVEPUSH_LOG, GJ_LOGDEBUG, "SetupAudioEncode");
    if (context->audioEncoder->obaque == GNULL) {
        context->audioEncoder->encodeSetup(context->audioEncoder, aFormat, aDFormat, GNULL, context);
    }
    return result;
}

GBool _livePushSetupVideoEncodeIfNeed(GJLivePushContext *context) {
    GBool result = GTrue;
    GJLOG(LIVEPUSH_LOG, GJ_LOGDEBUG, "SetupVideoEncode");
    GJPixelFormat vFormat = context->videoProducer->getPixelformat(context->videoProducer);
    GJAssert(vFormat.mHeight == (GUInt32) context->pushConfig->mPushSize.height, "产生的大小要等于推流大小");
    GJAssert(vFormat.mWidth == (GUInt32) context->pushConfig->mPushSize.width, "产生的大小要等于推流大小");
    
    if (context->videoEncoder->obaque == GNULL) {
        context->videoEncoder->encodeSetup(context->videoEncoder, vFormat, h264PacketOutCallback, context);
    }
    context->videoEncoder->encodeSetProfile(context->videoEncoder, profileLevelMain);
    context->videoEncoder->encodeSetGop(context->videoEncoder, context->pushConfig->mFps * 4);
    context->videoEncoder->encodeAllowBFrame(context->videoEncoder, GTrue);
    context->videoEncoder->encodeSetEntropy(context->videoEncoder, kEntropyMode_CABAC);
    context->videoEncoder->encodeSetBitrate(context->videoEncoder, context->pushConfig->mVideoBitrate);
    VideoDynamicInfo info;
    info.sourceFPS = info.currentFPS = context->pushConfig->mFps;
    info.sourceBitrate = info.currentBitrate = context->pushConfig->mVideoBitrate;
    context->callback(context->userData, GJLivePush_dynamicVideoUpdate, &info);
    return result;
}

GBool _livePushSetupAudioRecodeIfNeed(GJLivePushContext *context) {
    GBool result = GTrue;
    GJLOG(LIVEPUSH_LOG, GJ_LOGDEBUG, "SetupAudioEncode");

    return result;
}
GVoid _livePushUpdateCongestion(GJLivePushContext *context, GInt32 netSpeed) {

    netSpeed = GMIN(netSpeed, context->pushConfig->mVideoBitrate);

    GInt32 minBitrate = context->videoMinBitrate * (1 - GRationalValue(context->videoMaxDropRate));
    //等式 (netSpeed - minBitrate) / (context->pushConfig->mVideoBitrate - minBitrate) == (NET_SENSITIVITY_MAX - sensitivity) / (NET_SENSITIVITY_MAX - NET_SENSITIVITY) ;
    GInt32 sensitivity   = (GInt32)(NET_SENSITIVITY_MAX - (netSpeed - minBitrate) * 1.0 / (context->pushConfig->mVideoBitrate - minBitrate) * (NET_SENSITIVITY_MAX - NET_SENSITIVITY));
    context->sensitivity = sensitivity;

    //等式 (netSpeed - minBitrate) / (context->pushConfig->mVideoBitrate - minBitrate) == (continousDuring - NET_CONTINUOUS_DURING_MIN) / (NET_CONTINUOUS_DURING - NET_CONTINUOUS_DURING_MIN) ;

    GInt32 continousDuring = (GInt32)(NET_CONTINUOUS_DURING_MIN + (netSpeed - minBitrate) * 1.0 / (context->pushConfig->mVideoBitrate - minBitrate) * (NET_CONTINUOUS_DURING - NET_CONTINUOUS_DURING_MIN));

    //increaseSpeedStep修改之后favorableCount也需要复原。
    GInt32 step                = (GInt32)(context->increaseSpeedRate * context->rateCheckStep);
    context->favorableCount    = context->favorableCount % step;
    context->increaseSpeedRate = continousDuring * 1.0 / sensitivity;
    context->favorableCount += context->increaseCount * step;

    context->rateCheckStep = context->pushConfig->mFps * sensitivity / 1000 * (1 - GRationalValue(context->videoMaxDropRate)); //算上丢帧的帧数
    if (context->rateCheckStep < NET_MIN_CHECK_STEP) {
        context->rateCheckStep = NET_MIN_CHECK_STEP;
    }
    GJLOG(GNULL, GJ_LOGDEBUG, "update sensitivity to sensitivity:%d ms,rateCheckStep:%d,increaseSpeedStep:%0.2f", sensitivity, context->rateCheckStep, context->increaseSpeedRate);
}
GBool GJLivePush_StartPush(GJLivePushContext *context, const GChar *url) {

    GJLOG(LIVEPUSH_LOG, GJ_LOGDEBUG, "GJLivePush_StartPush url:%s", url);
    GBool result = GTrue;
    pthread_mutex_lock(&context->lock);
    do {
        if (context->streamPush != GNULL) {
            GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "请先停止上一个流");
        } else {
            if (context->pushConfig == GNULL) {
                GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "请先配置推流参数");
                return GFalse;
            }

            context->firstAudioEncodeClock = context->firstVideoEncodeClock = G_TIME_INVALID;
            context->connentClock = context->disConnentClock = context->stopPushClock = G_TIME_INVALID;
            context->startPushClock                                                   = GJ_Gettime();
            memset(&context->preCheckVideoTraffic, 0, sizeof(context->preCheckVideoTraffic));
            //            dynamicAlgorithm init
            context->videoDropStep = GRationalMake(0, 1);
            context->videoProducer->setDropStep(context->videoProducer, context->videoDropStep);
            context->videoMaxDropRate = GRationalMake(context->pushConfig->mFps - 1, context->pushConfig->mFps);
            context->videoMinBitrate  = context->pushConfig->mVideoBitrate * 0.6;
            context->videoBitrate     = context->pushConfig->mVideoBitrate;
            context->videoNetSpeed    = context->pushConfig->mVideoBitrate;

            context->collectCount          = 0;
            context->netSpeedCheckInterval = NET_AVG_DURING / NET_SENSITIVITY;
            if (context->netSpeedUnit != GNULL) {
                context->netSpeedUnit = realloc(context->netSpeedUnit, context->netSpeedCheckInterval * sizeof(GInt32));
            } else {
                context->netSpeedUnit = malloc(context->netSpeedCheckInterval * sizeof(GInt32));
            }
            for (int i = 0; i < context->netSpeedCheckInterval; i++) {
                context->netSpeedUnit[i] = INVALID_SPEED;
            }
            //不能直接用memset，会涉及到大小端问题
            //            memset(context->netSpeedUnit, INVALID_SPEED, context->netSpeedCheckInterval * sizeof(GInt32));

            _livePushUpdateCongestion(context, GINT32_MAX);

            _livePushSetupAudioEncodeIfNeed(context);
            _livePushSetupVideoEncodeIfNeed(context);

            context->videoEncoder->encodeFlush(context->videoEncoder);
            context->audioEncoder->encodeFlush(context->audioEncoder);

            GJAudioFormat aFormat     = {0};
            aFormat.mBitsPerChannel   = 16;
            aFormat.mType             = GJAudioType_PCM;
            aFormat.mFramePerPacket   = 1;
            aFormat.mSampleRate       = context->pushConfig->mAudioSampleRate;
            aFormat.mChannelsPerFrame = context->pushConfig->mAudioChannel;

            GJAudioStreamFormat aDFormat;
            aDFormat.bitrate                = context->pushConfig->mAudioBitrate;
            aDFormat.format                 = aFormat;
            aDFormat.format.mFramePerPacket = 1024;
            aDFormat.format.mType           = GJAudioType_AAC;

//            GJPixelFormat vFormat = {0};
//            vFormat.mHeight       = (GUInt32) context->pushConfig->mPushSize.height;
//            vFormat.mWidth        = (GUInt32) context->pushConfig->mPushSize.width;
//            vFormat.mType         = GJPixelType_YpCbCr8BiPlanar_Full;

            GJVideoStreamFormat vf;
            vf.format.mFps    = context->pushConfig->mFps;
            vf.format.mWidth  = context->pushConfig->mPushSize.width;
            vf.format.mHeight = context->pushConfig->mPushSize.height;
            vf.format.mType   = GJVideoType_H264;
            vf.bitrate        = context->pushConfig->mVideoBitrate;

            if (!GJStreamPush_Create(&context->streamPush, (MessageHandle) streamPushMessageCallback, (GHandle) context, &aDFormat, &vf)) {
                GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "GJStreamPush_Create error");
                result = GFalse;
                break;
            };

            pipleConnectNode((GJPipleNode *) context->audioEncoder, (GJPipleNode *) context->streamPush);
            pipleConnectNode((GJPipleNode *) context->videoEncoder, (GJPipleNode *) context->streamPush);

            if (!GJStreamPush_StartConnect(context->streamPush, url)) {
                GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "GJStreamPush_StartConnect error");
                result = GFalse;
                GJLivePush_StopPush(context);
                break;
            };

            requestStopServer = GFalse;
            if (serverThread == GNULL) {
                pthread_create(&serverThread, GNULL, thread_pthread_head, context);
            }
        }
    } while (0);
    pthread_mutex_unlock(&context->lock);
    return result;
}

GVoid GJLivePush_StopPush(GJLivePushContext *context) {
    pthread_mutex_lock(&context->lock);
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StopPush:%p", context);
    if (context->streamRecode) {
        GJLivePush_StopRecode(context);
    }
    if (context->streamPush) {
        context->stopPushClock = GJ_Gettime();

        //确保没有下一帧数据到发送模块
        pipleDisConnectNode((GJPipleNode *) context->audioEncoder, (GJPipleNode *) context->streamPush);
        pipleDisConnectNode((GJPipleNode *) context->videoEncoder, (GJPipleNode *) context->streamPush);

        //停止推流也需要停止编码器
        pipleDisConnectNode((GJPipleNode *) context->videoProducer, (GJPipleNode *) context->videoEncoder);
        pipleDisConnectNode((GJPipleNode *) context->audioProducer, (GJPipleNode *) context->audioEncoder);
        context->videoEncoder->encodeFlush(context->videoEncoder);
        if (context->streamRecode) {
            GJLivePush_StopRecode(context);
        }
        GJStreamPush_CloseAndDealloc(&context->streamPush);
    } else {
        GJLOG(LIVEPUSH_LOG, GJ_LOGWARNING, "重复停止推流流");
    }
    pthread_mutex_unlock(&context->lock);
}

GVoid GJLivePush_Dealloc(GJLivePushContext **pushContext) {
    GJLivePushContext *context = *pushContext;
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_Dealloc:%p", context);

    if (context == GNULL) {
        GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "非法释放");
    } else {

        if (context->audioEncoder) {
            context->audioEncoder->encodeUnSetup(context->audioEncoder);
            GJ_AACEncodeContextDealloc(&context->audioEncoder);
        }
        if (context->videoEncoder) {
            context->videoEncoder->encodeUnSetup(context->videoEncoder);
            GJ_H264EncodeContextDealloc(&context->videoEncoder);
        }
        if (context->audioProducer) {
            GJLivePush_DetachAudioProducer(context);
        }
        if (context->videoProducer) {
            GJLivePush_DetachVideoProducer(context);
        }

        if (serverThread != GNULL) {
#ifdef RAOP
            if (raopServer) {
                raop_server_stop(raopServer);
                raop_server_destroy(raopServer);
                raopServer = GNULL;
            }
#endif
#ifdef RVOP
            if (rvopserver) {
                rvop_server_stop(rvopserver);
                rvop_server_destroy(rvopserver);
                rvopserver = NULL;
            }
#endif
        } else {
                        requestStopServer    = GTrue;
                        requestDestoryServer = GTrue;
        }

        pthread_mutex_lock(&context->lock);
        if (context->pushConfig) {
            free(context->pushConfig);
            context->pushConfig = GNULL;
        }
        if (context->netSpeedUnit != GNULL) {
            free(context->netSpeedUnit);
            context->netSpeedUnit = GNULL;
        }
        pthread_mutex_unlock(&context->lock);
        pthread_mutex_destroy(&context->lock);

        free(context);
        *pushContext = GNULL;
    }
}

GJTrafficStatus GJLivePush_GetVideoTrafficStatus(GJLivePushContext *context) {
    return GJStreamPush_GetVideoBufferCacheInfo(context->streamPush);
}

GJTrafficStatus GJLivePush_GetAudioTrafficStatus(GJLivePushContext *context) {
    return GJStreamPush_GetAudioBufferCacheInfo(context->streamPush);
}

GBool GJLivePush_StartRecode(GJLivePushContext *context, GView view, GInt32 fps, const GChar *fileUrl) {
    GBool result = GFalse;
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StartRecode:%p", context);

    pthread_mutex_lock(&context->lock);
    do {
        if (context->streamRecode) {
            result = GFalse;
            GJLOG(GNULL, GJ_LOGFORBID, "请先停止上一个录制");
            break;
        }
        GJAudioFormat aFormat     = {0};
        aFormat.mBitsPerChannel   = 16;
        aFormat.mType             = GJAudioType_PCM;
        aFormat.mFramePerPacket   = 1;
        aFormat.mSampleRate       = context->pushConfig->mAudioSampleRate;
        aFormat.mChannelsPerFrame = context->pushConfig->mAudioChannel;

        GJAudioStreamFormat aDFormat;
        aDFormat.bitrate                = context->pushConfig->mAudioBitrate;
        aDFormat.format                 = aFormat;
        aDFormat.format.mFramePerPacket = 1024;
        aDFormat.format.mType           = GJAudioType_AAC;

        GJVideoStreamFormat vf;
        vf.format.mFps    = context->pushConfig->mFps;
        vf.format.mWidth  = (GUInt32) context->pushConfig->mPushSize.width;
        vf.format.mHeight = (GUInt32) context->pushConfig->mPushSize.height;
        vf.format.mType   = GJVideoType_H264;
        vf.bitrate        = context->pushConfig->mVideoBitrate;

        if (!GJStreamPush_Create(&context->streamRecode, (MessageHandle) streamRecodeMessageCallback, context, &aDFormat, &vf)) {
            GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "Recode_Create error");
            result = GFalse;
            break;
        };

        if (!GJStreamPush_StartConnect(context->streamRecode, fileUrl)) {
            GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "Recode_Connect error");
            result = GFalse;
            GJLivePush_StopRecode(context);
            break;
        };
        result = GTrue;
    } while (0);
    pthread_mutex_unlock(&context->lock);

    return result;
}

GVoid GJLivePush_StopRecode(GJLivePushContext *context) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StopRecode:%p", context);
    pthread_mutex_lock(&context->lock);
    if (context->streamRecode) {
        pipleConnectNode((GJPipleNode *) context->audioEncoder, (GJPipleNode *) context->streamRecode);
        pipleConnectNode((GJPipleNode *) context->videoEncoder, (GJPipleNode *) context->streamRecode);
        GJStreamPush_CloseAndDealloc(&context->streamRecode);
    }
    pthread_mutex_unlock(&context->lock);
}

//GHandle GJLivePush_GetDisplayView(GJLivePushContext *context) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_GetDisplayView:%p",context);
//
//    pthread_mutex_lock(&context->lock);
//    GHandle result = NULL;
//    if (context->videoProducer->obaque != GNULL) {
//        result = context->videoProducer->getRenderView(context->videoProducer);
//    }
//    pthread_mutex_unlock(&context->lock);
//
//    return result;
//}
//GHandle GJLivePush_CaptureFreshDisplayImage(GJLivePushContext *context){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_CaptureFreshDisplayImage:%p",context);
//    GHandle image = GNULL;
//    pthread_mutex_lock(&context->lock);
//    if (context->videoProducer) {
//        image = context->videoProducer->getFreshDisplayImage(context->videoProducer);
//    }
//    pthread_mutex_unlock(&context->lock);
//    return image;
//}
//
//GBool GJLivePush_StartSticker(GJLivePushContext *context, const GVoid *images, GInt32 fps, GJStickerUpdateCallback callback, const GHandle userData) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StartSticker:%p",context);
//    GBool result = GFalse;
//    pthread_mutex_lock(&context->lock);
//    if (context->videoProducer) {
//        result = context->videoProducer->addSticker(context->videoProducer, images, fps, callback, userData);
//    }
//    pthread_mutex_unlock(&context->lock);
//    return result;
//}
//GVoid GJLivePush_StopSticker(GJLivePushContext *context) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StopSticker:%p",context);
//    pthread_mutex_lock(&context->lock);
//    if (context->videoProducer) {
//        context->videoProducer->chanceSticker(context->videoProducer);
//    }
//    pthread_mutex_unlock(&context->lock);
//}
//
//GBool GJLivePush_StartTrackImage(GJLivePushContext *context, const GVoid *images, GCRect initFrame){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StartTrackImage:%p",context);
//    GBool result = GFalse;
//    pthread_mutex_lock(&context->lock);
//    if (context->videoProducer) {
//        result = context->videoProducer->startTrackImage(context->videoProducer,images,initFrame);
//    }
//    pthread_mutex_unlock(&context->lock);
//    return result;
//}
//
//GVoid GJLivePush_StopTrack(GJLivePushContext *context){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StopTrack:%p",context);
//
//    pthread_mutex_lock(&context->lock);
//    if (context->videoProducer) {
//        context->videoProducer->stopTrackImage(context->videoProducer);
//    }
//    pthread_mutex_unlock(&context->lock);
//}
//
//GSize GJLivePush_GetCaptureSize(GJLivePushContext *context) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_GetCaptureSize:%p",context);
//    GSize size = {0};
//    pthread_mutex_lock(&context->lock);
//
//    if (context->videoProducer) {
//        size = context->videoProducer->getCaptureSize(context->videoProducer);
//    }
//    pthread_mutex_unlock(&context->lock);
//
//    return size;
//}
//
//GBool GJLivePush_SetMeasurementMode(GJLivePushContext *context, GBool measurementMode) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetMeasurementMode:%p",context);
//    GBool ret = GFalse;
//    pthread_mutex_lock(&context->lock);
//    if (context->audioProducer) {
//        ret = context->audioProducer->enableMeasurementMode(context->audioProducer, measurementMode);
//    }
//    pthread_mutex_unlock(&context->lock);
//    return ret;
//}
//
//GBool GJLivePush_SetARScene(GJLivePushContext *context,GHandle scene){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetARScene:%p",context);
//    pthread_mutex_lock(&context->lock);
//    GBool result = context->videoProducer->setARScene(context->videoProducer,scene);
//    pthread_mutex_unlock(&context->lock);
//    return result;
//}
//
//GBool GJLivePush_SetCaptureView(GJLivePushContext *context,GView view){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetCaptureView:%p",context);
//    pthread_mutex_lock(&context->lock);
//    GBool result = context->videoProducer->setCaptureView(context->videoProducer,view);
//    pthread_mutex_unlock(&context->lock);
//    return result;
//}
//
//GBool GJLivePush_SetCaptureType(GJLivePushContext *context, GJCaptureType type){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetCaptureType:%p",context);
//    pthread_mutex_lock(&context->lock);
//    GBool result = context->videoProducer->setCaptureType(context->videoProducer,type);
//    pthread_mutex_unlock(&context->lock);
//    return result;
//}
//
//GBool GJLivePush_StartPreview(GJLivePushContext *context) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StartPreview:%p",context);
//    pthread_mutex_lock(&context->lock);
//    GBool result = context->videoProducer->startPreview(context->videoProducer);
//    pthread_mutex_unlock(&context->lock);
//
//    return result;
//}
//
//GVoid GJLivePush_StopPreview(GJLivePushContext *context) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StopPreview:%p",context);
//    pthread_mutex_lock(&context->lock);
//    context->videoProducer->stopPreview(context->videoProducer);
//    pthread_mutex_unlock(&context->lock);
//}
//
//GBool GJLivePush_SetAudioMute(GJLivePushContext *context, GBool mute) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetAudioMute:%p",context);
//
//    pthread_mutex_lock(&context->lock);
//    context->audioMute = mute;
//    if(mute){
//        pipleDisConnectNode(&context->audioProducer->pipleNode, &context->audioEncoder->pipleNode);
//    }else{
//        pipleConnectNode(&context->audioProducer->pipleNode, &context->audioEncoder->pipleNode);
//    }
//    pthread_mutex_unlock(&context->lock);
//
//    return GTrue;
//}
//
//GBool GJLivePush_SetVideoMute(GJLivePushContext *context, GBool mute) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetVideoMute:%p",context);
//
//    pthread_mutex_lock(&context->lock);
//    context->videoMute = mute;
//    if(mute){
//        pipleDisConnectNode(&context->videoProducer->pipleNode, &context->videoEncoder->pipleNode);
//    }else{
//        pipleConnectNode(&context->videoProducer->pipleNode, &context->videoEncoder->pipleNode);
//    }
//    pthread_mutex_unlock(&context->lock);
//    return GTrue;
//}
//
//GBool GJLivePush_StartMixFile(GJLivePushContext *context, const GChar *fileName,AudioMixFinishCallback finishCallback) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StartMixFile:%p",context);
//
//    pthread_mutex_lock(&context->lock);
//    GBool result = context->audioProducer->setupMixAudioFile(context->audioProducer, fileName, GFalse,finishCallback,context->userData);
//    if (result != GFalse) {
//        result = context->audioProducer->startMixAudioFileAtTime(context->audioProducer, 0);
//    }
//    pthread_mutex_unlock(&context->lock);
//
//    return result;
//}
//
//GBool GJLivePush_SetMixVolume(GJLivePushContext *context, GFloat volume) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetMixVolume:%p",context);
//
//    return GJCheckBool(context->audioProducer->setMixVolume(context->audioProducer, volume), "setMixVolume");
//}
//
//GBool GJLivePush_ShouldMixAudioToStream(GJLivePushContext *context, GBool should) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_ShouldMixAudioToStream:%p",context);
//
//    return GJCheckBool(context->audioProducer->setMixToStream(context->audioProducer, should), "setMixToStream");
//}
//
//GBool GJLivePush_SetOutVolume(GJLivePushContext *context, GFloat volume) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetOutVolume:%p",context);
//    return GJCheckBool(context->audioProducer->setOutVolume(context->audioProducer, volume), "setOutVolume");
//}
//
//GBool GJLivePush_SetInputGain(GJLivePushContext *context, GFloat gain) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetInputGain:%p",context);
//    return GJCheckBool(context->audioProducer->setInputGain(context->audioProducer, gain), "setInputGain");
//}
//
//GBool GJLivePush_SetCameraMirror(GJLivePushContext *context, GBool mirror){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetCameraMirror:%p",context);
//    GBool result = GFalse;
//    pthread_mutex_lock(&context->lock);
//    result = context->videoProducer->setHorizontallyMirror(context->videoProducer, mirror);
//    pthread_mutex_unlock(&context->lock);
//    return result;
//}
//GBool GJLivePush_SetStreamMirror(GJLivePushContext *context, GBool mirror){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetStreamMirror:%p",context);
//    GBool result = GFalse;
//    pthread_mutex_lock(&context->lock);
//    result = context->videoProducer->setStreamMirror(context->videoProducer, mirror);
//    pthread_mutex_unlock(&context->lock);
//    return result;
//}
//GBool GJLivePush_SetPreviewMirror(GJLivePushContext *context, GBool mirror){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetPreviewMirror:%p",context);
//    GBool result = GFalse;
//    pthread_mutex_lock(&context->lock);
//    result = context->videoProducer->setPreviewMirror(context->videoProducer, mirror);
//    pthread_mutex_unlock(&context->lock);
//    return result;
//}
//
//GBool GJLivePush_EnableAudioEchoCancellation(GJLivePushContext *context, GBool enable){
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_EnableAudioEchoCancellation:%p",context);
//    GBool result = GFalse;
//
//    pthread_mutex_lock(&context->lock);
//    if (context->audioProducer->obaque == GNULL) {
//        result = GFalse;
//    } else {
//        result = context->audioProducer->enableAudioEchoCancellation(context->audioProducer, enable);
//    }
//    pthread_mutex_unlock(&context->lock);
//
//    return result;
//}
//
//GBool GJLivePush_EnableAudioInEarMonitoring(GJLivePushContext *context, GBool enable) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_EnableAudioInEarMonitoring:%p",context);
//
//    GBool result = GFalse;
//
//    pthread_mutex_lock(&context->lock);
//    if (context->audioProducer->obaque == GNULL) {
//        result = GFalse;
//    } else {
//        result = context->audioProducer->enableAudioInEarMonitoring(context->audioProducer, enable);
//    }
//    pthread_mutex_unlock(&context->lock);
//
//    return result;
//}
//
//GBool GJLivePush_EnableReverb(GJLivePushContext *context, GBool enable) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_EnableReverb:%p",context);
//
//    GBool result = GFalse;
//
//    pthread_mutex_lock(&context->lock);
//    if (context->audioProducer->obaque == GNULL) {
//        result = GFalse;
//    } else {
//        result = context->audioProducer->enableReverb(context->audioProducer, enable);
//    }
//    pthread_mutex_unlock(&context->lock);
//
//    return result;
//
//}
//GVoid GJLivePush_StopAudioMix(GJLivePushContext *context) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_StopAudioMix:%p",context);
//
//    pthread_mutex_lock(&context->lock);
//
//    context->audioProducer->stopMixAudioFile(context->audioProducer);
//    pthread_mutex_unlock(&context->lock);
//
//}
//
//GVoid GJLivePush_SetCameraPosition(GJLivePushContext *context, GJCameraPosition position) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetCameraPosition:%p",context);
//
//    pthread_mutex_lock(&context->lock);
//    context->videoProducer->setCameraPosition(context->videoProducer, position);
//    pthread_mutex_unlock(&context->lock);
//
//}
//
//GVoid GJLivePush_SetOutOrientation(GJLivePushContext *context, GJInterfaceOrientation orientation) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetOutOrientation:%p",context);
//
//    pthread_mutex_lock(&context->lock);
//    context->videoProducer->setOrientation(context->videoProducer, orientation);
//    pthread_mutex_unlock(&context->lock);
//
//}
//
//GVoid GJLivePush_SetPreviewHMirror(GJLivePushContext *context, GBool preViewMirror) {
//    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePush_SetPreviewHMirror:%p",context);
//
//    pthread_mutex_lock(&context->lock);
//    context->videoProducer->setHorizontallyMirror(context->videoProducer, preViewMirror);
//    pthread_mutex_unlock(&context->lock);
//
//}
