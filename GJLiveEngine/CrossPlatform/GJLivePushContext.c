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
//#define DROP_BITRATE_RATE 0.1     //最小码率与最大码率之间的分割比率   //修改，采用帧率
//#define NET_ADD_STEP 8 * 1024 * 5 //5KB                          //修改，context->pushConfig->mVideoBitrate/context->pushConfig->mFps)

#define NET_ADD_STEP_B  1000  //每步增加的码率
#define NET_ADD_STEP_R  0.1   //每步增加的比例
#define NET_SENSITIVITY 300   //带宽灵敏度 ms，越灵敏，检查频率越高，网速检测间隔越大，频率越高，则增速越慢，缓存变化超过此值则更新。
#define NET_MIN_CHECK_STEP 5   //带宽灵敏度 ,最少NET_MIN_CHECK_STEP检查,
#define NET_AVG_DURING 3000   //平均带宽估计所需时间
#define NET_INCERASE_DURING (NET_AVG_DURING/NET_SENSITIVITY)*1  //网速增加速度

#define MAX_DELAY -1        //in ms，最大延迟，全速丢帧，
#define RESTORE_DROP_RATE  (3/4.0)   //延迟减少到MAX_DELAY *  RESTORE_DROP_RATE后恢复连续丢帧
#ifdef RVOP
static rvop_server_p rvopserver;
#endif
#ifdef RAOP
static raop_server_p server;
#endif
static pthread_t serverThread;
static GBool     requestStopServer;
static GBool     requestDestoryServer;

//static GVoid _GJLivePush_AppendQualityWithStep(GJLivePushContext *context, GLong step, GInt32 maxLimit);
//static GVoid _GJLivePush_reduceQualityWithStep(GJLivePushContext *context, GLong step, GInt32 minLimit);
static void _GJLivePush_SetCodeBitrate(GJLivePushContext *context, GInt32 destRate);
static void _GJLivePush_GetQualityInfo(GJLivePushContext *context, GInt32* ioBitrate, GJNetworkQuality * oQuality,GRational* oVideoDropStep);


static GVoid _recodeCompleteCallback(GHandle userData, const GChar *filePath, GHandle error) {
    GJLivePushContext *context = userData;
    pthread_mutex_lock(&context->lock);
    context->recoder->unSetup(context->recoder);
    if (context->pushConfig == GNULL) { //表示已经释放了，需要自己释放
        pthread_mutex_unlock(&context->lock);

        pthread_mutex_destroy(&context->lock);
        free(context);
        return;
    }
    context->callback(context->userData, GJLivePush_recodeComplete, error);
    context->recoder = GNULL;
    pthread_mutex_unlock(&context->lock);
}

static GVoid videoCaptureFrameOutCallback(GHandle userData, R_GJPixelFrame *frame) {
    GJLivePushContext *context = userData;
    if (context->stopPushClock == G_TIME_INVALID) {
        context->operationVCount++;
        if (!context->videoMute && (context->captureVideoCount++) % context->videoDropStep.den >= context->videoDropStep.num) {
#ifdef NETWORK_DELAY
            if (NeedTestNetwork) {

                frame->pts = GJ_Gettime() / 1000;
            }else{
                frame->pts = GJ_Gettime() / 1000 - context->connentClock;
            }
#else
            frame->pts = GJ_Gettime() / 1000 - context->connentClock;
#endif
            context->videoEncoder->encodeFrame(context->videoEncoder, frame);
        } else {
            GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "丢视频帧");
            context->dropVideoCount++;
        }
        context->operationVCount--;
    }
}

static GVoid audioCaptureFrameOutCallback(GHandle userData, R_GJPCMFrame *frame) {

    GJLivePushContext *context = userData;
    if (context->stopPushClock == G_TIME_INVALID) {

        context->operationACount++;
        if (!context->audioMute) {
#ifdef NETWORK_DELAY
            if (NeedTestNetwork) {
                frame->pts = GJ_Gettime() / 1000;
            }else{
                frame->pts = GJ_Gettime() / 1000 - context->connentClock;
            }
#else
            frame->pts = GJ_Gettime() / 1000 - context->connentClock;
#endif
            context->audioEncoder->encodeFrame(context->audioEncoder, frame);
            if (context->recoder) {

                pthread_mutex_lock(&context->lock);
                if (context->recoder) {

                    context->recoder->sendAudioSourcePacket(context->recoder, frame);
                }
                pthread_mutex_unlock(&context->lock);
            }
        }
        context->operationACount--;
    }
}
static GVoid _GJLivePush_CheckBufferCache(GJLivePushContext *context,GJTrafficStatus vBufferStatus,GJTrafficStatus aBufferStatus) {
//    static  int checkCount = 0;
//    GJLOG(GNULL, GJ_LOGDEBUG,"checkCount:%d",checkCount++);
    GLong cacheInCount = vBufferStatus.enter.count - vBufferStatus.leave.count;
    cacheInCount = GMAX(cacheInCount,aBufferStatus.enter.count - aBufferStatus.leave.count);
    //同时考虑音频，更加精确
    if(cacheInCount > 0){
        // 一定要清零，不然有积累后，会降低编码率，然后测得的网速普遍在低速，就很难提高了
//        if (context->favorableCount != 0) {
//            for (int i = 0; i < context->netSpeedCheckInterval; i++) {
//                context->netSpeedUnit[i] = -1;
//            }
//        }
        context->favorableCount = 0;
        context->increaseCount = 0;
    }else{
        context->favorableCount ++;
    }
   
    GLong cacheInPts = vBufferStatus.enter.ts - vBufferStatus.leave.ts;
    if (context->checkCount++ % context->rateCheckStep == 0) {
        GTime currentTime = GJ_Gettime()/1000;
        if (currentTime-vBufferStatus.enter.clock < 1000.0/context->pushConfig->mFps-10) {
            //如果发送间隔很短，则表示是b帧，无论是网络好还是差，都不准确，过滤不检查，同时checkCount--表示下一帧在检查。
            context->checkCount--;
        }else{
//            GJLOG(GNULL,GJ_LOGDEBUG,"free level time:%lld enter time:%lld cache count:%ld\n",currentTime-vBufferStatus.leave.clock,currentTime-vBufferStatus.enter.clock,vBufferStatus.enter.count - vBufferStatus.leave.count);
            GLong sendCount = vBufferStatus.leave.count - context->preCheckVideoTraffic.leave.count;

            if (cacheInCount > 0) {
                //快降慢升
                GLong sendByte = (vBufferStatus.leave.byte - context->preCheckVideoTraffic.leave.byte);
                GLong sendTs   =  vBufferStatus.leave.clock - context->preCheckVideoTraffic.leave.clock;
                GInt32 currentBitRate = 0;
                if (sendTs != 0) {
                    currentBitRate = sendByte * 8  / (sendTs / 1000.0);
                }
                context->netSpeedUnit[context->collectCount++ % context->netSpeedCheckInterval] = currentBitRate;
                if (sendCount < context->rateCheckStep && cacheInPts > NET_SENSITIVITY) {
                    int fullCount              = 0;
                    context->videoNetSpeed = 0;
                    for (int i = 0; i < context->netSpeedCheckInterval; i++) {
                        if (context->netSpeedUnit[i] >= 0) {
                            context->videoNetSpeed += context->netSpeedUnit[i];
                            fullCount++;
                        }
                    }
                    context->videoNetSpeed /= fullCount;
                    //count越大越准确
                    GJLOG(GNULL, GJ_LOGDEBUG,"busy status, avgRate :%f kB/s currentRate:%f sendCount:%d sendByte:%ld cacheCount:%d cacheTime:%d ms speedUnitCount:%d",context->videoNetSpeed / 8.0 / 1024,currentBitRate / 8.0 / 1024, fullCount,sendByte,cacheInCount,cacheInPts,fullCount);
                    GJAssert(context->videoNetSpeed >= 0, "错误");
                    GJAssert(sendTs > 0 || sendByte == 0 , "错误");
                    GJAssert(cacheInPts <= 50000, "错误");

                    if (context->videoNetSpeed > context->videoBitrate) {
                        GJLOG(LOG_DEBUG, GJ_LOGDEBUG,"警告:平均网速（%f）大于码率（%f），仍然出现缓存上升,继续降速", context->videoNetSpeed / 8.0 / 1024,context->videoBitrate / 8.0 / 1024);
                        context->videoNetSpeed = context->videoBitrate;
                    }
                    //减速的目标是比网速小，以减少缓存
                    context->videoNetSpeed -= context->videoBitrate/context->pushConfig->mFps;
                    //发送数量越少降速越快
                    GFloat32 ratio =  context->rateCheckStep - sendCount;
                    //满速发送时间越长，网速越可靠
                    ratio = ( fullCount + ratio ) *1.0 / context->netSpeedCheckInterval;
                    
                    GInt32 bitrate = context->videoBitrate - (context->videoBitrate - context->videoNetSpeed) * ratio;
                    //bitrate = bitrate - (GInt32)(context->rateCheckStep - sendCount) * context->pushConfig->mVideoBitrate/context->pushConfig->mFps;
                    
                    GJNetworkQuality quality = GJNetworkQualityGood;
                    GRational videoDropStep = GRationalMake(0, 1);
                    _GJLivePush_GetQualityInfo(context, &bitrate, &quality, &videoDropStep);
                    if (quality != context->netQuality) {
                        context->callback(context->userData, GJLivePush_updateNetQuality, &quality);
                    }
                    _GJLivePush_SetCodeBitrate(context, bitrate);

                    if (context->videoDropStep.num != context->videoDropStep.den) {
                        context->videoDropStep = videoDropStep;
                    }else{
                        context->videoDropStepBack = videoDropStep;
                    }
                }
            } else{
                GJLOG(GNULL, GJ_LOGDEBUG,"favorableCount count:%d",context->favorableCount);
                if (context->favorableCount / context->increaseSpeedStep > context->increaseCount &&
                    context->videoBitrate < context->pushConfig->mVideoBitrate) {
                    context->increaseCount = context->favorableCount / context->increaseSpeedStep;
                    int collectCount = context->collectCount++;
                    for (int i = 0; i < context->increaseCount; i++) {
                        //因为一直有空闲，所以前面连续空闲的网速一定大于此网速，更新
                        context->netSpeedUnit[collectCount-- % context->netSpeedCheckInterval] = context->videoBitrate;
                    }

                    GInt32 bitrate = context->videoBitrate + context->pushConfig->mVideoBitrate/context->pushConfig->mFps;
                    
                    GJNetworkQuality quality = GJNetworkQualityGood;
                    GRational videoDropStep = GRationalMake(0, 1);
                    _GJLivePush_GetQualityInfo(context, &bitrate, &quality, &videoDropStep);
                    if (quality != context->netQuality) {
                        context->callback(context->userData, GJLivePush_updateNetQuality, &quality);
                    }
                    _GJLivePush_SetCodeBitrate(context, bitrate);
                    if (context->videoDropStep.num != context->videoDropStep.den) {
                        context->videoDropStep = videoDropStep;
                    }else{
                        context->videoDropStepBack = videoDropStep;
                    }
                }
            }
        
            context->preCheckVideoTraffic = vBufferStatus;
        }
    }
    
    if (context->maxVideoDelay > 0 && cacheInPts >= context->maxVideoDelay && context->videoDropStep.num != context->videoDropStep.den) {
        context->videoDropStepBack = context->videoDropStep;
        context->videoDropStep = GRationalMake(1, 1);
        GJLOG(GNULL, GJ_LOGDEBUG,"set video drop step (1,1)\n");
    }
}

static GVoid h264PacketOutCallback(GHandle userData, R_GJPacket *packet) {

    GJLivePushContext *context = userData;
    if (context->firstVideoEncodeClock == G_TIME_INVALID) {

        GJAssert(packet->flag && GJPacketFlag_KEY, "第一帧非关键帧");
        context->preCheckVideoTraffic = GJStreamPush_GetVideoBufferCacheInfo(context->videoPush);
        context->firstVideoEncodeClock = GJ_Gettime() / 1000;
        GJStreamPush_SendVideoData(context->videoPush, packet);

    } else {
        GJTrafficStatus vbufferStatus = GJStreamPush_GetVideoBufferCacheInfo(context->videoPush);
        GJTrafficStatus aBufferStatus = GJStreamPush_GetAudioBufferCacheInfo(context->videoPush);
        GJStreamPush_SendVideoData(context->videoPush, packet);
        _GJLivePush_CheckBufferCache(context,vbufferStatus,aBufferStatus);
    }
}

static GVoid aacPacketOutCallback(GHandle userData, R_GJPacket *packet) {
    GJLivePushContext *context = userData;
    GJStreamPush_SendAudioData(context->videoPush, packet);
}

GVoid streamPushMessageCallback(GHandle userData, kStreamPushMessageType messageType, GHandle messageParm) {
    GJLivePushContext *context = userData;
    switch (messageType) {
        case kStreamPushMessageType_connectSuccess: {
            GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "推流连接成功");
            context->connentClock = GJ_Gettime() / 1000;
            pthread_mutex_lock(&context->lock);
            context->audioProducer->audioProduceStart(context->audioProducer);
            context->videoProducer->startProduce(context->videoProducer);
            pthread_mutex_unlock(&context->lock);
            GLong during = (GLong)(context->connentClock - context->startPushClock);
            context->callback(context->userData, GJLivePush_connectSuccess, &during);
        } break;
        case kStreamPushMessageType_closeComplete: {
            GJPushSessionInfo info   = {0};
            context->disConnentClock = GJ_Gettime() / 1000;
            info.sessionDuring       = (GLong)(context->disConnentClock - context->connentClock);
            context->callback(context->userData, GJLivePush_closeComplete, &info);
        } break;
        case kStreamPushMessageType_urlPraseError:
        case kStreamPushMessageType_connectError:
            GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "推流连接失败");
            GJLivePush_StopPush(context);
            context->callback(context->userData, GJLivePush_connectError, "rtmp连接失败");
            break;
        case kStreamPushMessageType_sendPacketError:
            GJLivePush_StopPush(context);
            context->callback(context->userData, GJLivePush_sendPacketError, "发送失败");
            break;
        case kStreamPushMessageType_packetSendSignal:{
            GJMediaType packetType = *(GJMediaType*)messageParm;
            if (packetType == GJMediaType_Video && GRationalValue(context->videoDropStep) >= 0.9999) {
                GJTrafficStatus vbufferStatus = GJStreamPush_GetVideoBufferCacheInfo(context->videoPush);
                GJTrafficStatus abufferStatus = GJStreamPush_GetAudioBufferCacheInfo(context->videoPush);

                GLong cacheInPts = vbufferStatus.enter.ts - vbufferStatus.leave.ts;
                GLong cacheInCount = vbufferStatus.enter.count - vbufferStatus.leave.count;
                printf("cacheInPts:%ld\n",cacheInPts);
                if (cacheInPts < context->maxVideoDelay * RESTORE_DROP_RATE || cacheInCount <= 1) {
                    context->videoDropStep = context->videoDropStepBack;
                    GJLOG(GNULL, GJ_LOGDEBUG,"set video drop step (%d,%d)\n",context->videoDropStep.num,context->videoDropStep.den);
                }else{
                    _GJLivePush_CheckBufferCache(context, vbufferStatus, abufferStatus);
                }
            }
        }
        default:
            break;
    }
}
static void _GJLivePush_SetCodeBitrate(GJLivePushContext *context, GInt32 destRate){
    if (context->videoBitrate - destRate > 10 || context->videoBitrate - destRate < 10) {
        
        if (context->videoEncoder->encodeSetBitrate(context->videoEncoder, destRate)) {
            GJLOG(GNULL, GJ_LOGDEBUG, "Set Video Bitrate:%d",destRate/8/1024);
            
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

static void _GJLivePush_GetQualityInfo(GJLivePushContext *context, GInt32* ioBitrate, GJNetworkQuality * oQuality,GRational* oVideoDropStep){
    GJNetworkQuality quality = GJNetworkQualityGood;
    GInt32 destRate = *ioBitrate;
    GRational videoDropStep = GRationalMake(0, 1);
    if (destRate >= context->pushConfig->mVideoBitrate - 0.001) {
        quality = GJNetworkQualityExcellent;
        destRate = context->pushConfig->mVideoBitrate;
        videoDropStep = GRationalMake(0, 1);
    }else if(destRate >= context->videoMinBitrate){
        if (destRate * 2 >= context->videoMinBitrate + context->pushConfig->mVideoBitrate) {
            quality = GJNetworkQualityGood;
        }else{
            quality = GJNetworkQualitybad;
        }
        videoDropStep = GRationalMake(0, 1);

    }else{
        GInt32 minLimit = context->videoMinBitrate * (1 - GRationalValue(context->videoMaxDropRate));
        if(destRate < minLimit)destRate = minLimit;
        if (destRate <= context->videoMinBitrate * 0.5) {
            videoDropStep.den = context->videoMinBitrate/destRate;
            videoDropStep.num = videoDropStep.den - 1;
        }else{
            videoDropStep = GRationalMake(1, 1.0/(1.0-destRate*1.0/context->videoMinBitrate));
        }
        quality = GJNetworkQualityTerrible;
    }
    *oQuality = quality;
    *oVideoDropStep = videoDropStep;
    *ioBitrate = destRate;
    
    
    
}

//快降慢升，最高升到GMIN(context->pushConfig->mVideoBitrate, context->videoNetSpeed)
//static void _GJLivePush_AppendQualityWithStep(GJLivePushContext *context, GLong step, GInt32 maxLimit) {
//    GLong            leftStep   = step;
//    GJNetworkQuality quality    = GJNetworkQualityGood;
//    GInt32          bitrate     = context->videoBitrate;
//    GInt32           maxBitRate = GMIN(maxLimit, context->pushConfig->mVideoBitrate);
//    GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "appendQualityWithStep：%d current:%0.2f maxlimit:%0.2f", step,bitrate/8.0/1024.0,maxLimit/8.0/1024.0);
//
//    if (leftStep > 0 && (context->videoDropStep.den != 0 && GRationalValue(context->videoDropStep) > 0.5)) {
//
//        GJAssert(context->videoDropStep.den - context->videoDropStep.num == 1, "管理错误1");
//
//        context->videoDropStep.num -= leftStep;
//        context->videoDropStep.den -= leftStep;
//        leftStep = 0;
//        if (context->videoDropStep.num < 1) { //丢一半帧
//            leftStep               = 1 - context->videoDropStep.num;
//            context->videoDropStep = GRationalMake(1, 2);
//            bitrate                = context->videoMinBitrate * 0.5;
//            quality = GJNetworkQualitybad;
//
//        } else {
//
//            bitrate = context->videoMinBitrate * (1 - GRationalValue(context->videoDropStep));
//            quality = GJNetworkQualityTerrible;
//            GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "appendQuality1 by reduce to drop frame:num %d,den %d", context->videoDropStep.num, context->videoDropStep.den);
//        }
//
//        //            <<<--处理网速过小的情况
//
//
//
//
//        if (maxBitRate < bitrate) {
//            //网速限制
//            bitrate = maxBitRate;
//            context->videoDropStep.den = context->videoMinBitrate/maxBitRate;
//            if (context->videoDropStep.den < 2) {
//                context->videoDropStep.den =  context->videoDropStep.den * 10 -5;
//            }
//            context->videoDropStep.num = context->videoDropStep.den - 1;
//            bitrate  = maxBitRate;
//            leftStep = 0;
//            GJAssert(context->videoDropStep.den >= 2, "videoDropStep管理错误");
////
////            GFloat32 dropRate = (context->videoMinBitrate - maxBitRate) / context->videoMinBitrate; //丢包率，一定大于0.5
////
////            GFloat32 dr                = 1 - dropRate;
////            context->videoDropStep.den = (GInt32)(1 / dr);
////            context->videoDropStep.num = context->videoDropStep.den - 1;
////            if (context->videoDropStep.num < 1) {
////                context->videoDropStep = GRationalMake(1, 2);
////            } else if (context->videoDropStep.num > context->videoMaxDropRate.num) {
////                context->videoDropStep = context->videoMaxDropRate;
////            }
////            bitrate  = maxBitRate;
////            leftStep = 0;
//        }
//    }
//
//    if (leftStep > 0 && context->videoDropStep.den != 0) {
//
//        GJAssert(context->videoDropStep.num == 1, "管理错误2");
//        context->videoDropStep.num = 1;
//        context->videoDropStep.den += leftStep;
//        leftStep = 0;
//        if (context->videoDropStep.den > DEFAULT_MAX_DROP_STEP) {
//            leftStep               = DEFAULT_MAX_DROP_STEP - context->videoDropStep.den;
//            context->videoDropStep = GRationalMake(0, 0);
//            bitrate                = context->videoMinBitrate;
//        } else {
//            bitrate = context->videoMinBitrate * (1 - GRationalValue(context->videoDropStep));
//            quality = GJNetworkQualitybad;
//            GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "appendQuality2 by reduce to drop frame:num %d,den %d", context->videoDropStep.num, context->videoDropStep.den);
//        }
//
//        //            <<<--处理网速过小的情况
//        if (maxBitRate < bitrate) {
//            GFloat32 dropRate = (context->videoMinBitrate - maxBitRate) * 0.5 / context->videoMinBitrate; //丢包率，一定小于0.5
//            if (dropRate <= 0.5) {
//                context->videoDropStep = GRationalMake(1, (GInt32)(1 / dropRate));
//            }
//            bitrate  = maxBitRate;
//            leftStep = 0;
//        }
//    }
//
//    if (leftStep > 0) {
//
//        if (bitrate < context->pushConfig->mVideoBitrate) {
//            bitrate += (context->pushConfig->mVideoBitrate - context->videoMinBitrate) * leftStep / context->pushConfig->mFps;
//            quality = GJNetworkQualityGood;
//        } else {
//            quality = GJNetworkQualityExcellent;
//            GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "appendQuality to full speed:%f", bitrate / 1024.0 / 8.0);
//        }
//        bitrate = GMIN(bitrate, maxBitRate);
//    }
//
//    if (context->videoBitrate != bitrate) {
//
//        if (context->videoEncoder->encodeSetBitrate(context->videoEncoder, bitrate)) {
//            context->videoBitrate = bitrate;
//
//            VideoDynamicInfo info;
//            info.sourceFPS     = context->pushConfig->mFps;
//            info.sourceBitrate = context->pushConfig->mVideoBitrate;
//            if (context->videoDropStep.den > 0) {
//                info.currentFPS = info.sourceFPS * (1 - GRationalValue(context->videoDropStep));
//            } else {
//                info.currentFPS = info.sourceFPS;
//            }
//            info.currentBitrate = bitrate;
//            context->callback(context->userData, GJLivePush_dynamicVideoUpdate, &info);
//        }
//        context->callback(context->userData, GJLivePush_updateNetQuality, &quality);
//    }
//}
//
//GVoid _GJLivePush_reduceQualityWithStep(GJLivePushContext *context, GLong step, GInt32 minLimit) {
//    GLong            leftStep       = step;
//    GJNetworkQuality quality        = GJNetworkQualityGood;
//    GInt32           bitrate        = context->videoBitrate;
//
//    GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "reduceQualityWithStep：%d current:%0.2f minLimit:%f", step,bitrate/8.0/1024.0,minLimit/8.0/1024.0);
//
//    if (bitrate > context->videoMinBitrate) {
//        bitrate -= (context->pushConfig->mVideoBitrate - context->videoMinBitrate) * leftStep / context->pushConfig->mFps;
//        leftStep = 0;
//        if (bitrate < minLimit) {
//            bitrate = minLimit;
//        }
//        if (bitrate < context->videoMinBitrate) {
//            leftStep = (context->videoMinBitrate - bitrate) / ((context->pushConfig->mVideoBitrate - context->videoMinBitrate) / context->pushConfig->mFps);
//            bitrate  = context->videoMinBitrate;
//        }
//        quality = GJNetworkQualityGood;
//    }
//
//    if (leftStep > 0 &&
//        context->videoMaxDropRate.den > 0 &&                                                      //允许丢帧
//        (context->videoDropStep.den == 0 || (GRationalValue(context->videoDropStep) <= 0.50001 && // 小于1/2.
//                                             GRationalValue(context->videoDropStep) < GRationalValue(context->videoMaxDropRate)))) {
//        if (context->videoDropStep.num == 0) context->videoDropStep = GRationalMake(1, DEFAULT_MAX_DROP_STEP);
//        context->videoDropStep.num                                  = 1;
//        context->videoDropStep.den -= leftStep;
//        leftStep = 0;
//
//        GRational tempR = GRationalMake(1, 2); //此阶段最大降低到1/2.0
//        if (GRationalValue(context->videoMaxDropRate) < 0.5) {
//            //超过最大丢帧率
//            tempR = context->videoMaxDropRate;
//        }
//
//        if (context->videoDropStep.den < tempR.den) {
//            if(minLimit > context->videoMinBitrate){
//                //网速限制
//                leftStep = 0;
//                context->videoDropStep = GRationalMake(1, 1.0/(1.0-minLimit*1.0/context->videoMinBitrate));
//                GJAssert(context->videoDropStep.den >= 2, "videoDropStep管理错误");
//                quality = GJNetworkQualitybad;
//            }else{
//                leftStep                   = tempR.den - context->videoDropStep.den;
//                context->videoDropStep.den = tempR.den;
//            }
//        } else {
//
//
//            bitrate = context->videoMinBitrate * (1 - GRationalValue(context->videoDropStep));
//            if(minLimit > bitrate){
//                //网速限制
//                context->videoDropStep = GRationalMake(1, 1.0/(1.0-minLimit*1.0/context->videoMinBitrate));
//                GJAssert(context->videoDropStep.den >= 2, "videoDropStep管理错误");
//                bitrate = minLimit;
//            }
//            quality = GJNetworkQualitybad;
//            GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "reduceQuality1 by reduce to drop frame:num %d,den %d", context->videoDropStep.num, context->videoDropStep.den);
//        }
//    }
//    if (leftStep > 0 && GRationalValue(context->videoDropStep) < GRationalValue(context->videoMaxDropRate)) {
//
//        context->videoDropStep.num += leftStep;
//        context->videoDropStep.den += leftStep;
//        if (context->videoDropStep.den > context->videoMaxDropRate.den) {
//            context->videoDropStep = context->videoMaxDropRate;
//        }
//        bitrate = context->videoMinBitrate * (1 - GRationalValue(context->videoDropStep));
//        quality = GJNetworkQualityTerrible;
//        if(minLimit > bitrate){
//            //网速限制
//            bitrate = minLimit;
//            context->videoDropStep.den = context->videoMinBitrate/minLimit;
//            if (context->videoDropStep.den < 2) {
//                context->videoDropStep.den =  context->videoDropStep.den * 10 -5;
//            }
//            context->videoDropStep.num = context->videoDropStep.den - 1;
//            GJAssert(context->videoDropStep.den >= 2, "videoDropStep管理错误");
//        }
//        GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "reduceQuality2 by reduce to drop frame:num %d,den %d", context->videoDropStep.num, context->videoDropStep.den);
//    }
//
//    if (context->videoBitrate != bitrate) {
//
//        if (context->videoEncoder->encodeSetBitrate(context->videoEncoder, bitrate)) {
//
//            context->videoBitrate = bitrate;
//            VideoDynamicInfo info;
//            info.sourceFPS     = context->pushConfig->mFps;
//            info.sourceBitrate = context->pushConfig->mVideoBitrate;
//            if (context->videoDropStep.den > 0) {
//                info.currentFPS = info.sourceFPS * (1 - GRationalValue(context->videoDropStep));
//            } else {
//                info.currentFPS = info.sourceFPS;
//            }
//            info.currentBitrate = bitrate;
//            context->callback(context->userData, GJLivePush_dynamicVideoUpdate, &info);
//        }
//        context->callback(context->userData, GJLivePush_updateNetQuality, &quality);
//    }
//}

static void *thread_pthread_head(void *ctx) {
    pthread_setname_np("RAOP RUN THREAD");
#ifdef RAOP
    struct raop_server_settings_t setting;
    setting.name                 = GNULL;
    setting.password             = GNULL;
    setting.ignore_source_volume = GFalse;

    if (server == GNULL) {

        server = raop_server_create(setting, ctx);
    }

    if (!raop_server_is_running(server)) {

        uint16_t port = 5000;
        while (port < 5010 && !raop_server_start(server, port++))
            ;
    }

    if (requestStopServer) {

        raop_server_stop(server);
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
        GJ_VideoProduceContextCreate(&context->videoProducer);
        context->videoProducer->videoProduceSetup(context->videoProducer, videoCaptureFrameOutCallback, context);
        
        GJ_AudioProduceContextCreate(&context->audioProducer);
        pthread_mutex_init(&context->lock, GNULL);
        context->maxVideoDelay = MAX_DELAY;
        
        requestStopServer = GFalse;
        if (serverThread == GNULL) {
            pthread_create(&serverThread, GNULL, thread_pthread_head, context);
        }
    } while (0);
    return result;
}

GVoid GJLivePush_SetConfig(GJLivePushContext *context, const GJPushConfig *config) {
    if (context == GNULL) {
        return;
    }

    pthread_mutex_lock(&context->lock);
    if (context->videoPush != GNULL) {
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
                if (context->audioProducer) {
                    context->audioProducer->audioProduceUnSetup(context->audioProducer);
                }
            } else if (config->mAudioBitrate != context->pushConfig->mAudioBitrate) {
                if (context->audioEncoder) {
                    context->audioEncoder->encodeUnSetup(context->audioEncoder);
                }
            }

            if (config->mVideoBitrate != context->pushConfig->mVideoBitrate ||
                !GSizeEqual(config->mPushSize, context->pushConfig->mPushSize)) {
                if (context->audioEncoder) {
                    context->videoEncoder->encodeUnSetup(context->videoEncoder);
                }
            }
        }

        GJPixelFormat format;
        format.mHeight = config->mPushSize.height;
        format.mWidth = config->mPushSize.width;
        format.mType =  GJPixelType_YpCbCr8BiPlanar_Full;
        context->videoProducer->setVideoFormat(context->videoProducer,format);
        context->videoProducer->setFrameRate(context->videoProducer,config->mFps);

        *(context->pushConfig) = *config;
    }
    pthread_mutex_unlock(&context->lock);
}

GBool GJLivePush_StartPush(GJLivePushContext *context, const GChar *url) {

    GJLOG(LIVEPUSH_LOG, GJ_LOGINFO, "GJLivePush_StartPush url:%s", url);
    GBool result = GTrue;
    pthread_mutex_lock(&context->lock);
    do {
        if (context->videoPush != GNULL) {
            GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "请先停止上一个流");
        } else {
            if (context->pushConfig == GNULL) {
                GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "请先配置推流参数");
                return GFalse;
            }

            context->firstAudioEncodeClock = context->firstVideoEncodeClock = G_TIME_INVALID;
            context->connentClock = context->disConnentClock = context->stopPushClock = G_TIME_INVALID;
            context->startPushClock                                                   = GJ_Gettime() / 1000;
            memset(&context->preCheckVideoTraffic, 0, sizeof(context->preCheckVideoTraffic));
            //            dynamicAlgorithm init
            context->videoDropStep         = GRationalMake(0, 1);
            context->videoMaxDropRate      = GRationalMake(context->pushConfig->mFps-1, context->pushConfig->mFps);
            context->videoMinBitrate       = context->pushConfig->mVideoBitrate * 0.6;
            context->videoBitrate          = context->pushConfig->mVideoBitrate;
            context->videoNetSpeed         = context->pushConfig->mVideoBitrate;
            context->rateCheckStep         = context->pushConfig->mFps * NET_SENSITIVITY / 1000;
            if (context->rateCheckStep < NET_MIN_CHECK_STEP) {
                context->rateCheckStep = NET_MIN_CHECK_STEP;
            }
           
            context->netSpeedCheckInterval = NET_AVG_DURING / NET_SENSITIVITY ;
            context->increaseSpeedStep = NET_INCERASE_DURING;
            context->collectCount          = 0;
            if (context->netSpeedUnit != GNULL) {
                context->netSpeedUnit = realloc(context->netSpeedUnit, context->netSpeedCheckInterval * sizeof(GInt32));
            } else {
                context->netSpeedUnit = malloc(context->netSpeedCheckInterval * sizeof(GInt32));
            }
            for (int i = 0; i<context->netSpeedCheckInterval; i++) {
                context->netSpeedUnit[i] = -1;
            }

            if (context->audioProducer->obaque == GNULL) {
                GJAudioFormat aFormat     = {0};
                aFormat.mBitsPerChannel   = 16;
                aFormat.mType             = GJAudioType_PCM;
                aFormat.mFramePerPacket   = 1;
                aFormat.mSampleRate       = context->pushConfig->mAudioSampleRate;
                aFormat.mChannelsPerFrame = context->pushConfig->mAudioChannel;
                context->audioProducer->audioProduceSetup(context->audioProducer, aFormat, audioCaptureFrameOutCallback, context);
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
            if (context->audioEncoder->obaque == GNULL) {
                context->audioEncoder->encodeSetup(context->audioEncoder, aFormat, aDFormat, aacPacketOutCallback, context);
            }

            GJPixelFormat vFormat = {0};
            vFormat.mHeight       = (GUInt32) context->pushConfig->mPushSize.height;
            vFormat.mWidth        = (GUInt32) context->pushConfig->mPushSize.width;
            vFormat.mType         = GJPixelType_YpCbCr8BiPlanar_Full;
            if (context->videoEncoder->obaque == GNULL) {
                context->videoEncoder->encodeSetup(context->videoEncoder, vFormat, h264PacketOutCallback, context);
            }
            context->videoEncoder->encodeSetProfile(context->videoEncoder, profileLevelMain);
            context->videoEncoder->encodeSetGop(context->videoEncoder, context->pushConfig->mFps*4);
            context->videoEncoder->encodeAllowBFrame(context->videoEncoder, GTrue);
            context->videoEncoder->encodeSetEntropy(context->videoEncoder, EntropyMode_CABAC);
            context->videoEncoder->encodeSetBitrate(context->videoEncoder, context->pushConfig->mVideoBitrate);
            VideoDynamicInfo info;
            info.sourceFPS     = info.currentFPS = context->pushConfig->mFps;
            info.sourceBitrate = info.currentBitrate = context->pushConfig->mVideoBitrate;
            context->callback(context->userData, GJLivePush_dynamicVideoUpdate, &info);

            GJVideoStreamFormat vf;
            vf.format.mFps    = context->pushConfig->mFps;
            vf.format.mWidth  = vFormat.mWidth;
            vf.format.mHeight = vFormat.mHeight;
            vf.format.mType   = GJVideoType_H264;
            vf.bitrate        = context->pushConfig->mVideoBitrate;

            if (!GJStreamPush_Create(&context->videoPush, streamPushMessageCallback, (GHandle) context, &aDFormat, &vf)) {
                GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "GJStreamPush_Create error");
                result = GFalse;
                break;
            };

            if (!GJStreamPush_StartConnect(context->videoPush, url)) {
                GJLOG(LIVEPUSH_LOG, GJ_LOGERROR, "GJStreamPush_StartConnect error");
                result = GFalse;
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
    if (context->videoPush) {
        context->stopPushClock = GJ_Gettime() / 1000;
        context->audioProducer->audioProduceStop(context->audioProducer);
        context->videoProducer->stopProduce(context->videoProducer);
        context->videoEncoder->encodeFlush(context->videoEncoder);
        context->audioEncoder->encodeFlush(context->audioEncoder);
        while (context->operationACount) {
            GJLOG(LIVEPUSH_LOG, GJ_LOGDEBUG, "GJLivePush_StopPush wait A 100 us");
            usleep(100);
        }
        while (context->operationVCount) {
            GJLOG(LIVEPUSH_LOG, GJ_LOGDEBUG, "GJLivePush_StopPush wait V 100 us");
            usleep(100);
        }
        GJStreamPush_CloseAndDealloc(&context->videoPush);
    } else {
        GJLOG(LIVEPUSH_LOG, GJ_LOGWARNING, "重复停止推流流");
    }
    pthread_mutex_unlock(&context->lock);
}

GBool GJLivePush_SetARScene(GJLivePushContext *context,GHandle scene){
    pthread_mutex_lock(&context->lock);
    GBool result = context->videoProducer->setARScene(context->videoProducer,scene);
    pthread_mutex_unlock(&context->lock);
    return result;
}

GBool GJLivePush_StartPreview(GJLivePushContext *context) {
    pthread_mutex_lock(&context->lock);

    GBool result = context->videoProducer->startPreview(context->videoProducer);
    pthread_mutex_unlock(&context->lock);
    
    return result;
}

GVoid GJLivePush_StopPreview(GJLivePushContext *context) {
    
    pthread_mutex_lock(&context->lock);
    context->videoProducer->stopPreview(context->videoProducer);
    pthread_mutex_unlock(&context->lock);
}

GBool GJLivePush_SetAudioMute(GJLivePushContext *context, GBool mute) {
    
    pthread_mutex_lock(&context->lock);
    context->audioMute = mute;
    pthread_mutex_unlock(&context->lock);

    return GTrue;
}

GBool GJLivePush_SetVideoMute(GJLivePushContext *context, GBool mute) {
    
    pthread_mutex_lock(&context->lock);
    context->videoMute = mute;
    pthread_mutex_unlock(&context->lock);
    return GTrue;
}

GBool GJLivePush_StartMixFile(GJLivePushContext *context, const GChar *fileName,AudioMixFinishCallback finishCallback) {
    
    pthread_mutex_lock(&context->lock);
    GBool result = context->audioProducer->setupMixAudioFile(context->audioProducer, fileName, GFalse,finishCallback,context->userData);
    if (result != GFalse) {
        result = context->audioProducer->startMixAudioFileAtTime(context->audioProducer, 0);
    }
    pthread_mutex_unlock(&context->lock);

    return result;
}

GBool GJLivePush_SetMixVolume(GJLivePushContext *context, GFloat32 volume) {
    return GJCheckBool(context->audioProducer->setMixVolume(context->audioProducer, volume), "setMixVolume");
}

GBool GJLivePush_ShouldMixAudioToStream(GJLivePushContext *context, GBool should) {
    return GJCheckBool(context->audioProducer->setMixToStream(context->audioProducer, should), "setMixToStream");
}

GBool GJLivePush_SetOutVolume(GJLivePushContext *context, GFloat32 volume) {
    return GJCheckBool(context->audioProducer->setOutVolume(context->audioProducer, volume), "setOutVolume");
}

GBool GJLivePush_SetInputGain(GJLivePushContext *context, GFloat32 gain) {
    return GJCheckBool(context->audioProducer->setInputGain(context->audioProducer, gain), "setInputGain");
}

GBool GJLivePush_SetCameraMirror(GJLivePushContext *context, GBool mirror){
    GBool result = GFalse;
    pthread_mutex_lock(&context->lock);
    result = context->videoProducer->setHorizontallyMirror(context->videoProducer, mirror);
    pthread_mutex_unlock(&context->lock);
    return result;
}
GBool GJLivePush_SetStreamMirror(GJLivePushContext *context, GBool mirror){
    GBool result = GFalse;
    pthread_mutex_lock(&context->lock);
    result = context->videoProducer->setStreamMirror(context->videoProducer, mirror);
    pthread_mutex_unlock(&context->lock);
    return result;
}
GBool GJLivePush_SetPreviewMirror(GJLivePushContext *context, GBool mirror){
    GBool result = GFalse;
    pthread_mutex_lock(&context->lock);
    result = context->videoProducer->setPreviewMirror(context->videoProducer, mirror);
    pthread_mutex_unlock(&context->lock);
    return result;
}

GBool GJLivePush_EnableAudioInEarMonitoring(GJLivePushContext *context, GBool enable) {
    
    GBool result = GFalse;
    
    pthread_mutex_lock(&context->lock);
    if (context->audioProducer->obaque == GNULL) {
        result = GFalse;
    } else {
        result = context->audioProducer->enableAudioInEarMonitoring(context->audioProducer, enable);
    }
    pthread_mutex_unlock(&context->lock);
    
    return result;
}

GBool GJLivePush_EnableReverb(GJLivePushContext *context, GBool enable) {
    GBool result = GFalse;
    
    pthread_mutex_lock(&context->lock);
    if (context->audioProducer->obaque == GNULL) {
         result = GFalse;
    } else {
         result = context->audioProducer->enableReverb(context->audioProducer, enable);
    }
    pthread_mutex_unlock(&context->lock);
    
    return result;

}
GVoid GJLivePush_StopAudioMix(GJLivePushContext *context) {
    pthread_mutex_lock(&context->lock);

    context->audioProducer->stopMixAudioFile(context->audioProducer);
    pthread_mutex_unlock(&context->lock);

}

GVoid GJLivePush_SetCameraPosition(GJLivePushContext *context, GJCameraPosition position) {
    
    pthread_mutex_lock(&context->lock);
    context->videoProducer->setCameraPosition(context->videoProducer, position);
    pthread_mutex_unlock(&context->lock);

}

GVoid GJLivePush_SetOutOrientation(GJLivePushContext *context, GJInterfaceOrientation orientation) {
    
    pthread_mutex_lock(&context->lock);
    context->videoProducer->setOrientation(context->videoProducer, orientation);
    pthread_mutex_unlock(&context->lock);

}

GVoid GJLivePush_SetPreviewHMirror(GJLivePushContext *context, GBool preViewMirror) {
    
    pthread_mutex_lock(&context->lock);
    context->videoProducer->setHorizontallyMirror(context->videoProducer, preViewMirror);
    pthread_mutex_unlock(&context->lock);
    
}

GVoid GJLivePush_Dealloc(GJLivePushContext **pushContext) {
    GJLivePushContext *context = *pushContext;
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
            context->audioProducer->audioProduceUnSetup(context->audioProducer);
            GJ_AudioProduceContextDealloc(&context->audioProducer);
        }
        if (context->videoProducer) {
            context->videoProducer->videoProduceUnSetup(context->videoProducer);
            GJ_VideoProduceContextDealloc(&context->videoProducer);
        }

        if (serverThread == GNULL) {
#ifdef RAOP
            raop_server_stop(server);
            raop_server_destroy(server);
#endif
#ifdef RVOP
            rvop_server_stop(rvopserver);
            rvop_server_destroy(rvopserver);
            rvopserver = NULL;
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
        if (context->recoder) { //让录制结束后自己释放
            pthread_mutex_unlock(&context->lock);
            return;
        }
        pthread_mutex_unlock(&context->lock);
        pthread_mutex_destroy(&context->lock);

        free(context);
        *pushContext = GNULL;
    }
}

GJTrafficStatus GJLivePush_GetVideoTrafficStatus(GJLivePushContext *context) {
    return GJStreamPush_GetVideoBufferCacheInfo(context->videoPush);
}

GJTrafficStatus GJLivePush_GetAudioTrafficStatus(GJLivePushContext *context) {
    return GJStreamPush_GetAudioBufferCacheInfo(context->videoPush);
}

GHandle GJLivePush_GetDisplayView(GJLivePushContext *context) {
    pthread_mutex_lock(&context->lock);
    GHandle result = NULL;
    if (context->videoProducer->obaque != GNULL) {
        result = context->videoProducer->getRenderView(context->videoProducer);
    }
    pthread_mutex_unlock(&context->lock);

    return result;
}

GBool GJLivePush_StartRecode(GJLivePushContext *context, GView view, GInt32 fps, const GChar *fileUrl) {
    GBool result = GFalse;

    pthread_mutex_lock(&context->lock);
    do {
        if (context->recoder) {
            GJLOG(LIVEPUSH_LOG, GJ_LOGFORBID, "上一个录制还未完成");
            result = GFalse;
            break;
        } else {
            if (context->pushConfig == GNULL || context->pushConfig->mAudioSampleRate <= 0 || context->pushConfig->mAudioChannel <= 0) {
                GJLOG(LIVEPUSH_LOG, GJ_LOGFORBID, "请先配置正确pushConfig");
                result = GFalse;
                break;
            }
            GJAudioFormat format     = {0};
            format.mChannelsPerFrame = context->pushConfig->mAudioChannel;
            format.mSampleRate       = context->pushConfig->mAudioSampleRate;
            format.mType             = GJAudioType_PCM;
            format.mBitsPerChannel   = 16;
            format.mFramePerPacket   = 1;
            GJ_RecodeContextCreate(&context->recoder);
            context->recoder->setup(context->recoder, fileUrl, _recodeCompleteCallback, context);
            
            GJVideoFormat vFormat = {0};
            vFormat.mFps = fps;
            
            context->recoder->addAudioSource(context->recoder, format);
            context->recoder->addVideoSource(context->recoder,vFormat,view);
            result = context->recoder->startRecode(context->recoder);
            if (!result) {
                GJLivePush_StopRecode(context);
            }
        }
    } while (0);
    pthread_mutex_unlock(&context->lock);

    return result;
}

GVoid GJLivePush_StopRecode(GJLivePushContext *context) {
    pthread_mutex_lock(&context->lock);
    if (context->recoder) {
        context->recoder->stopRecode(context->recoder);
    }
    pthread_mutex_unlock(&context->lock);
}

GHandle GJLivePush_CaptureFreshDisplayImage(GJLivePushContext *context){
    GHandle image = GNULL;
    pthread_mutex_lock(&context->lock);
    if (context->videoProducer) {
        image = context->videoProducer->getFreshDisplayImage(context->videoProducer);
    }
    pthread_mutex_unlock(&context->lock);
    return image;
}

GBool GJLivePush_StartSticker(GJLivePushContext *context, const GVoid *images, GInt32 fps, GJStickerUpdateCallback callback, const GHandle userData) {
    GBool result = GFalse;
    pthread_mutex_lock(&context->lock);
    if (context->videoProducer) {
        result = context->videoProducer->addSticker(context->videoProducer, images, fps, callback, userData);
    }
    pthread_mutex_unlock(&context->lock);
    return result;
}
GVoid GJLivePush_StopSticker(GJLivePushContext *context) {
    pthread_mutex_lock(&context->lock);
    if (context->videoProducer) {
        context->videoProducer->chanceSticker(context->videoProducer);
    }
    pthread_mutex_unlock(&context->lock);
}

GBool GJLivePush_StartTrackImage(GJLivePushContext *context, const GVoid *images, GCRect initFrame){
    GBool result = GFalse;
    pthread_mutex_lock(&context->lock);
    if (context->videoProducer) {
        result = context->videoProducer->startTrackImage(context->videoProducer,images,initFrame);
    }
    pthread_mutex_unlock(&context->lock);
    return result;
}

GVoid GJLivePush_StopTrack(GJLivePushContext *context){
    pthread_mutex_lock(&context->lock);
    if (context->videoProducer) {
        context->videoProducer->stopTrackImage(context->videoProducer);
    }
    pthread_mutex_unlock(&context->lock);
}

GSize GJLivePush_GetCaptureSize(GJLivePushContext *context) {
    GSize size = {0};
    pthread_mutex_lock(&context->lock);

    if (context->videoProducer) {
        size = context->videoProducer->getCaptureSize(context->videoProducer);
    }
    pthread_mutex_unlock(&context->lock);

    return size;
}

GBool GJLivePush_SetMeasurementMode(GJLivePushContext *context, GBool measurementMode) {
    GBool ret = GFalse;
    pthread_mutex_lock(&context->lock);
    if (context->audioProducer) {
        ret = context->audioProducer->enableMeasurementMode(context->audioProducer, measurementMode);
    }
    pthread_mutex_unlock(&context->lock);
    return ret;
}
