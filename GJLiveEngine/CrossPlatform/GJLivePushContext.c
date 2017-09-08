//
//  GJLivePushContext.c
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLivePushContext.h"
#include "GJLog.h"
#include "GJUtil.h"
#include "GJLiveDefine.h"

#include <unistd.h>
//#define I_P_RATE 4   不需用，按照平均降码率来
#define DROP_BITRATE_RATE 0.1  //最小码率与最大码率之间的分割比率
#define NET_ADD_STEP 8*1024*5  //5KB
#ifdef RVOP
static rvop_server_p           rvopserver;
#endif
#ifdef RAOP
static raop_server_p           server;
#endif
static pthread_t               serverThread;
static GBool                   requestStopServer;
static GBool                   requestDestoryServer;

static GVoid _GJLivePush_AppendQualityWithStep(GJLivePushContext* context, GLong step);
static GVoid _GJLivePush_reduceQualityWithStep(GJLivePushContext* context, GLong step);

static GVoid _recodeCompleteCallback(GHandle userData,const GChar* filePath, GHandle error){
    GJLivePushContext* context = userData;
    pthread_mutex_lock(&context->lock);
    context->recoder->unSetup(context->recoder);
    if (context->pushConfig == GNULL) {//表示已经释放了，需要自己释放
        pthread_mutex_unlock(&context->lock);
        
        pthread_mutex_destroy(&context->lock);
        free(context);
        return;
    }
    context->callback(context->userData,GJLivePush_recodeComplete,error);
    context->recoder = GNULL;
    pthread_mutex_unlock(&context->lock);
    
}


static GVoid videoCaptureFrameOutCallback (GHandle userData,R_GJPixelFrame* frame){
    GJLivePushContext* context = userData;
    if (context->stopPushClock == G_TIME_INVALID) {
        context->operationCount ++;
        if (!context->videoMute && (context->captureVideoCount++) % context->videoDropStep.den >= context->videoDropStep.num) {
            frame->pts = GJ_Gettime()/1000-context->connentClock;
            context->videoEncoder->encodeFrame(context->videoEncoder,frame);
        }else{
            GJLOG(GJ_LOGWARNING, "丢视频帧");
            context->dropVideoCount++;
        }
        context->operationCount--;
    }
}

static GVoid audioCaptureFrameOutCallback (GHandle userData,R_GJPCMFrame* frame){
    GJLivePushContext* context = userData;
    if (context->stopPushClock == G_TIME_INVALID) {
        context->operationCount ++;
        
        if (!context->audioMute) {
            frame->pts = GJ_Gettime()/1000-context->connentClock;
            context->audioEncoder->encodeFrame(context->audioEncoder,frame);
            if (context->recoder) {
                pthread_mutex_lock(&context->lock);
                if (context->recoder) {
                    context->recoder->sendAudioSourcePacket(context->recoder,frame);
                }
                pthread_mutex_unlock(&context->lock);
                
            }
        }
        context->operationCount--;
    }
}

static GVoid h264PacketOutCallback(GHandle userData,R_GJPacket* packet){
    GJLivePushContext* context = userData;
    if (context->firstVideoEncodeClock == G_TIME_INVALID) {
        GJAssert(packet->flag && GJPacketFlag_KEY, "");
        context->firstVideoEncodeClock = GJ_Gettime()/1000;
        GJStreamPush_SendVideoData(context->videoPush, packet);
        context->preVideoTraffic = GJStreamPush_GetVideoBufferCacheInfo(context->videoPush);
        
    }else{
        GJTrafficStatus bufferStatus = GJStreamPush_GetVideoBufferCacheInfo(context->videoPush);
        GJStreamPush_SendVideoData(context->videoPush, packet);
        
        if (bufferStatus.enter.count % context->rateCheckStep == 0) {
            
            GLong cacheInCount = bufferStatus.enter.count - bufferStatus.leave.count;
            //            GLong cacheInPts = bufferStatus.enter.ts - bufferStatus.leave.ts;
            GLong sendCount = bufferStatus.leave.count - context->preVideoTraffic.leave.count;
            
            if(cacheInCount > 2 ){
                
                ///<<<考虑丢帧算法
                //                if (context->videoDropStep.den != 0 && context->videoDropStep.num !=0 ) {
                //                    GInt32 count = (GInt32)(context->rateCheckStep / (1-GRationalValue(context->videoDropStep)));
                //                    if (sendCount < count) {
                //                        GJLOG(GJ_LOGINFO, "局部检测出降低视频质量");
                //                        _GJLivePush_reduceQualityWithStep(context, (count - sendCount)/2);
                //                    }
                //                }else{
                //                    if (sendCount < context->rateCheckStep) {
                //                        GJLOG(GJ_LOGINFO, "局部检测出降低视频质量");
                //                        _GJLivePush_reduceQualityWithStep(context, (context->rateCheckStep - sendCount)/2);
                //                    }
                //                }
                
                //                <<不考虑丢帧算法
                if (sendCount < context->rateCheckStep ) {
                    GJLOG(GJ_LOGINFO, "局部检测出降低视频质量");
                    _GJLivePush_reduceQualityWithStep(context, (context->rateCheckStep - sendCount)/2);
                }
                context->netSpeedUnit[context->collectCount++ % context->netSpeedCheckInterval] = (bufferStatus.leave.byte - context->preVideoTraffic.leave.byte)*8*1000.0/(bufferStatus.enter.ts-context->preVideoTraffic.enter.ts);
                printf("net rate :%f\n",context->netSpeedUnit[(context->collectCount-1) % context->netSpeedCheckInterval]/8.0/1024);
                
            }else if(context->videoBitrate < context->pushConfig->mVideoBitrate){
                if (context->collectCount > 0) {
                    int count = GMIN(context->collectCount, context->netSpeedCheckInterval);
                    context->videoNetSpeed = 0;
                    
                    for (int i = 0; i<count; i++) {
                        context->videoNetSpeed += context->netSpeedUnit[i];
                    }
                    
                    context->videoNetSpeed /= count;
                    context->collectCount = 0;
                    
                    printf("net last rate :%f\n",context->videoNetSpeed/8.0/1024);
                    
                }
                context->videoNetSpeed = GMAX(context->videoNetSpeed, context->videoBitrate);
                if (cacheInCount == 0) {
                    context->videoNetSpeed += NET_ADD_STEP;
                    _GJLivePush_AppendQualityWithStep(context, 100);
                }else{
                    if (sendCount > context->rateCheckStep ) {
                        GJLOG(GJ_LOGINFO, "宏观检测出提高视频质量");
                        _GJLivePush_AppendQualityWithStep(context, sendCount - context->rateCheckStep );
                    }
                }
            }
            //
            //        {
            //            GLong diffInCount = bufferStatus.leave.count - context->preVideoTraffic.leave.count;
            ////            diffInCount *= 1 - GRationalValue(context->videoDropStep);
            //            if(diffInCount <= context->dynamicAlgorithm.num){//降低质量敏感检测
            //                GJLOG(GJ_LOGINFO, "敏感检测出降低视频质量");
            //                _GJLivePush_reduceQualityWithStep(context, context->dynamicAlgorithm.num - diffInCount + 1);
            //            }else if(diffInCount > context->dynamicAlgorithm.den + context->dynamicAlgorithm.num){//提高质量敏感检测
            //                GJLOG(GJ_LOGINFO, "敏感检测出提高音频质量");
            //                _GJLivePush_AppendQualityWithStep(context, diffInCount - context->dynamicAlgorithm.den - context->dynamicAlgorithm.num);
            //            }else{
            //                GLong cacheInPts = bufferStatus.enter.ts - bufferStatus.leave.ts;
            //                if (diffInCount < context->dynamicAlgorithm.den && cacheInPts > SEND_DELAY_TIME && cacheInCount > SEND_DELAY_COUNT) {
            //                    GJLOG(GJ_LOGWARNING, "宏观检测出降低视频质量 (很少可能会出现)");
            //                    _GJLivePush_reduceQualityWithStep(context, 1);
            //                }else if(cacheInCount <= 2 && context->videoBitrate < context->pushConfig->mVideoBitrate){
            //                    GJLOG(GJ_LOGINFO, "宏观检测出提高视频质量");
            //                    _GJLivePush_AppendQualityWithStep(context, 1);
            //                }
            //            }
            //        }
            context->preVideoTraffic = bufferStatus;
        }
    }
    
}

static GVoid aacPacketOutCallback(GHandle userData,R_GJPacket* packet){
    GJLivePushContext* context = userData;
    GJStreamPush_SendAudioData(context->videoPush, packet);
}

GVoid streamPushMessageCallback(GHandle userData, kStreamPushMessageType messageType,GHandle messageParm){
    GJLivePushContext* context = userData;
    switch (messageType) {
        case kStreamPushMessageType_connectSuccess:
        {
            GJLOG(GJ_LOGINFO, "推流连接成功");
            context->connentClock = GJ_Gettime()/1000;
            pthread_mutex_lock(&context->lock);
            context->audioProducer->audioProduceStart(context->audioProducer);
            context->videoProducer->startProduce(context->videoProducer);
            pthread_mutex_unlock(&context->lock);
            GLong during = (GLong)(context->connentClock - context->startPushClock);
            context->callback(context->userData,GJLivePush_connectSuccess,&during);
        }
            break;
        case kStreamPushMessageType_closeComplete:{
            GJPushSessionInfo info = {0};
            context->disConnentClock = GJ_Gettime()/1000;
            info.sessionDuring = (GLong)(context->disConnentClock - context->connentClock);
            context->callback(context->userData,GJLivePush_closeComplete,&info);
        }
            break;
        case kStreamPushMessageType_urlPraseError:
        case kStreamPushMessageType_connectError:
            GJLOG(GJ_LOGINFO, "推流连接失败");
            GJLivePush_StopPush(context);
            context->callback(context->userData,GJLivePush_connectError,"rtmp连接失败");
            break;
        case kStreamPushMessageType_sendPacketError:
            GJLivePush_StopPush(context);
            context->callback(context->userData,GJLivePush_sendPacketError,"发送失败");
            break;
        default:
            break;
    }
}

//快降慢升
static void _GJLivePush_AppendQualityWithStep(GJLivePushContext* context, GLong step){
    GLong leftStep = step;
    GJNetworkQuality quality = GJNetworkQualityGood;
    int32_t bitrate = context->videoBitrate;
    GInt32 maxBitRate = GMIN(context->pushConfig->mVideoBitrate, context->videoNetSpeed);
    GJLOG(GJ_LOGINFO, "appendQualityWithStep：%d",step);
    
    if (leftStep > 0 && (context->videoDropStep.den != 0 && GRationalValue(context->videoDropStep) > 0.5)) {
        
        GJAssert(context->videoDropStep.den - context->videoDropStep.num == 1, "管理错误1");
        
        context->videoDropStep.num -= leftStep;
        context->videoDropStep.den -= leftStep;
        leftStep = 0;
        if (context->videoDropStep.num < 1) { //丢一半帧
            leftStep = 1 - context->videoDropStep.num;
            context->videoDropStep = GRationalMake(1,2);
            bitrate = context->videoMinBitrate*0.5;
            
        }else{
            
            bitrate = context->videoMinBitrate*(1-GRationalValue(context->videoDropStep));
            quality = GJNetworkQualityTerrible;
            GJLOG(GJ_LOGINFO, "appendQuality1 by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);
        }
        
        //            <<<--处理网速过小的情况
        if (maxBitRate < bitrate) {
            GFloat32 dropRate = (context->videoMinBitrate - maxBitRate)*0.5/context->videoMinBitrate;//丢包率，一定大于0.5
            
            GFloat32 dr = 1 - dropRate;
            context->videoDropStep.den = (GInt32)(1/dr);
            context->videoDropStep.num = context->videoDropStep.den-1;
            if (context->videoDropStep.num < 1) {
                context->videoDropStep = GRationalMake(1, 2);
            }else if (context->videoDropStep.num > context->videoMaxDropRate.num){
                context->videoDropStep = context->videoMaxDropRate;
            }
            bitrate = maxBitRate;
            leftStep = 0;
            
        }
    }
    
    if (leftStep > 0 && context->videoDropStep.den != 0) {
        
        GJAssert(context->videoDropStep.num == 1, "管理错误2");
        context->videoDropStep.num = 1;
        context->videoDropStep.den += leftStep;
        leftStep = 0;
        if (context->videoDropStep.den > DEFAULT_MAX_DROP_STEP) {
            leftStep = DEFAULT_MAX_DROP_STEP - context->videoDropStep.den;
            context->videoDropStep = GRationalMake(0,0);
            bitrate = context->videoMinBitrate;
        }else{
            bitrate = context->videoMinBitrate*(1-GRationalValue(context->videoDropStep));
            quality = GJNetworkQualitybad;
            GJLOG(GJ_LOGINFO, "appendQuality2 by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);
        }
        
        //            <<<--处理网速过小的情况
        if (maxBitRate < bitrate) {
            GFloat32 dropRate = (context->videoMinBitrate - maxBitRate)*0.5/context->videoMinBitrate;//丢包率，一定小于0.5
            if (dropRate <= 0.5) {
                context->videoDropStep = GRationalMake(1, (GInt32)(1/dropRate));
            }
            bitrate = maxBitRate;
            leftStep = 0;
        }
    }
    
    if(leftStep > 0){
        
        if (bitrate < context->pushConfig->mVideoBitrate) {
            bitrate += (context->pushConfig->mVideoBitrate - context->videoMinBitrate)*leftStep*DROP_BITRATE_RATE;
            quality = GJNetworkQualityGood;
        }else{
            quality = GJNetworkQualityExcellent;
            GJLOG(GJ_LOGINFO, "appendQuality to full speed:%f",bitrate/1024.0/8.0);
        }
        bitrate = GMIN(bitrate, maxBitRate);
    }
    
    if (context->videoBitrate != bitrate) {
        
        if(context->videoEncoder->encodeSetBitrate(context->videoEncoder,bitrate)){
            context->videoBitrate = bitrate;
            
            VideoDynamicInfo info ;
            info.sourceFPS = context->pushConfig->mFps;
            info.sourceBitrate = context->pushConfig->mVideoBitrate;
            if (context->videoDropStep.den > 0) {
                info.currentFPS = info.sourceFPS * (1 -GRationalValue(context->videoDropStep));
            }else{
                info.currentFPS = info.sourceFPS;
            }
            info.currentBitrate = bitrate;
            context->callback(context->userData,GJLivePush_dynamicVideoUpdate,&info);
        }
        context->callback(context->userData,GJLivePush_updateNetQuality,&quality);
        
    }
}

GVoid _GJLivePush_reduceQualityWithStep(GJLivePushContext* context, GLong step){
    GLong leftStep = step;
    int currentBitRate = context->videoBitrate;
    GJNetworkQuality quality = GJNetworkQualityGood;
    int32_t bitrate = currentBitRate;
    
    GJLOG(GJ_LOGINFO, "reduceQualityWithStep：%d",step);
    
    if (bitrate > context->videoMinBitrate) {
        bitrate -= (context->pushConfig->mVideoBitrate - context->videoMinBitrate)*leftStep*DROP_BITRATE_RATE;
        leftStep = 0;
        if (bitrate < context->videoMinBitrate) {
            leftStep = (context->videoMinBitrate - bitrate)/((context->pushConfig->mVideoBitrate - context->videoMinBitrate)*DROP_BITRATE_RATE);
            bitrate = context->videoMinBitrate;
        }
        quality = GJNetworkQualityGood;
    }
    
    if (leftStep > 0 &&
        context->videoMaxDropRate.den > 0 &&//允许丢帧
        (context->videoDropStep.den == 0 || (GRationalValue(context->videoDropStep) <= 0.50001 &&// 小于1/2.
                                             GRationalValue(context->videoDropStep) < GRationalValue(context->videoMaxDropRate))))
    {
        if(context->videoDropStep.num == 0)context->videoDropStep = GRationalMake(1, DEFAULT_MAX_DROP_STEP);
        context->videoDropStep.num = 1;
        context->videoDropStep.den -= leftStep;
        leftStep = 0;
        
        GRational tempR = GRationalMake(1, 2);//此阶段最大降低到1/2.0
        if (GRationalValue(context->videoMaxDropRate) < 0.5) {
            tempR = context->videoMaxDropRate;
        }
        
        if (context->videoDropStep.den < tempR.den) {
            
            leftStep = tempR.den - context->videoDropStep.den;
            context->videoDropStep.den = tempR.den;
            
        }else{
            
            bitrate = context->videoMinBitrate*(1-GRationalValue(context->videoDropStep));
            quality = GJNetworkQualitybad;
            GJLOG(GJ_LOGINFO, "reduceQuality1 by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);
            
        }
        
    }
    if (leftStep > 0 && GRationalValue(context->videoDropStep) < GRationalValue(context->videoMaxDropRate)){
        
        context->videoDropStep.num += leftStep;
        context->videoDropStep.den += leftStep;
        if(context->videoDropStep.den > context->videoMaxDropRate.den){
            context->videoDropStep = context->videoMaxDropRate;
        }
        bitrate = context->videoMinBitrate*(1-GRationalValue(context->videoDropStep));
        quality = GJNetworkQualityTerrible;
        GJLOG(GJ_LOGINFO, "reduceQuality2 by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);
        
    }
    
    if (context->videoBitrate != bitrate) {
        
        if(context->videoEncoder->encodeSetBitrate(context->videoEncoder,bitrate)){
            
            context->videoBitrate = bitrate;
            VideoDynamicInfo info ;
            info.sourceFPS = context->pushConfig->mFps;
            info.sourceBitrate = context->pushConfig->mVideoBitrate;
            if (context->videoDropStep.den > 0) {
                info.currentFPS = info.sourceFPS * (1-GRationalValue(context->videoDropStep));
            }else{
                info.currentFPS = info.sourceFPS;
            }
            info.currentBitrate = bitrate;
            context->callback(context->userData,GJLivePush_dynamicVideoUpdate,&info);
            
        }
        context->callback(context->userData,GJLivePush_updateNetQuality,&quality);
    }
}

static void* thread_pthread_head(void* ctx) {
    
#ifdef RAOP
    struct raop_server_settings_t setting;
    setting.name = GNULL;
    setting.password = GNULL;
    setting.ignore_source_volume = GFalse;
    
    if (server == GNULL) {
        
        server = raop_server_create(setting,ctx);
        
    }
    
    if (!raop_server_is_running(server)) {
        
        uint16_t port = 5000;
        while (port < 5010 && !raop_server_start(server, port++));
        
    }
    
    if (requestStopServer) {
        
        raop_server_stop(server);
        
    }
    serverThread = GNULL;
    
#endif
    
#ifdef RVOP
    struct rvop_server_settings_t setting;
    setting.name = GNULL;
    setting.password = GNULL;
    setting.ignore_source_volume = GFalse;
    if (rvopserver == GNULL) {
        rvopserver = rvop_server_create(setting);
    }
    
    if (!rvop_server_is_running(rvopserver)) {
        
        uint16_t port = 5000;
        while (port < 5010 && !rvop_server_start(rvopserver, port++));
    }
    if (requestStopServer) {
        rvop_server_stop(rvopserver);
    }
#endif
    serverThread = GNULL;
    pthread_exit(0);
    
}

GBool GJLivePush_Create(GJLivePushContext** pushContext,GJLivePushCallback callback,GHandle param){
    GBool result = GFalse;
    do{
        if (*pushContext == GNULL) {
            *pushContext = (GJLivePushContext*)calloc(1,sizeof(GJLivePushContext));
            if (*pushContext == GNULL) {
                result = GFalse;
                break;
            }
        }
        GJLivePushContext* context = *pushContext;
        context->callback = callback;
        context->userData = param;
        GJ_H264EncodeContextCreate(&context->videoEncoder);
        GJ_AACEncodeContextCreate(&context->audioEncoder);
        GJ_VideoProduceContextCreate(&context->videoProducer);
        GJ_AudioProduceContextCreate(&context->audioProducer);
        pthread_mutex_init(&context->lock, GNULL);
        
        
        requestStopServer = GFalse;
        if (serverThread == GNULL) {
            pthread_create(&serverThread, GNULL, thread_pthread_head, context);
        }
    }while (0);
    return result;
}

GVoid GJLivePush_SetConfig(GJLivePushContext* context,const GJPushConfig* config){
    if (context == GNULL) {return;}
    
    pthread_mutex_lock(&context->lock);
    if (context->videoPush != GNULL) {
        GJLOG(GJ_LOGERROR, "推流期间不能配置pushconfig");
    }else{
        if (context->pushConfig == GNULL) {
            context->pushConfig = (GJPushConfig*)malloc(sizeof(GJPushConfig));
        }else{
            
            if (config->mAudioChannel != context->pushConfig->mAudioChannel ||
                config->mAudioSampleRate != context->pushConfig->mAudioSampleRate) {
                if (context->audioEncoder) {
                    context->audioEncoder->encodeUnSetup(context->audioEncoder);
                }
                if (context->audioProducer) {
                    context->audioProducer->audioProduceUnSetup(context->audioProducer);
                }
            }else if (config->mAudioBitrate != context->pushConfig->mAudioBitrate){
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
            
            if (context->videoProducer->obaque != GNULL) {
                if (context->pushConfig->mFps != config->mFps) {
                    context->videoProducer->setFrameRate(context->videoProducer,config->mFps);
                }
                if (!GSizeEqual(context->pushConfig->mPushSize, config->mPushSize)) {
                    context->videoProducer->setProduceSize(context->videoProducer,config->mPushSize);
                }
            }
            
        }
        *(context->pushConfig) = *config;
    }
    pthread_mutex_unlock(&context->lock);
}

GBool GJLivePush_StartPush(GJLivePushContext* context,const GChar* url){
    
    GJLOG(GJ_LOGINFO, "GJLivePush_StartPush url:%s",url);
    GBool result = GTrue;
    pthread_mutex_lock(&context->lock);
    do{
        if (context->videoPush != GNULL) {
            GJLOG(GJ_LOGERROR, "请先停止上一个流");
        }else{
            if (context->pushConfig == GNULL) {
                GJLOG(GJ_LOGERROR, "请先配置推流参数");
                return GFalse;
            }
            context->firstAudioEncodeClock = context->firstVideoEncodeClock = G_TIME_INVALID;
            context->connentClock = context->disConnentClock = context->stopPushClock = G_TIME_INVALID;
            context->startPushClock = GJ_Gettime()/1000;
            memset(&context->preVideoTraffic, 0, sizeof(context->preVideoTraffic));
            
            //            dynamicAlgorithm init
            context->videoDropStep = GRationalMake(0, 0);
            context->videoMaxDropRate = GRationalMake(context->pushConfig->mFps-1, context->pushConfig->mFps);
            context->videoMinBitrate = context->pushConfig->mVideoBitrate*0.6;
            context->videoBitrate = context->pushConfig->mVideoBitrate;
            context->videoNetSpeed = context->pushConfig->mVideoBitrate;
            context->rateCheckStep = context->pushConfig->mFps;
            context->dropStepPrecision = context->rateCheckStep/5.0;
            context->netSpeedCheckInterval = 5;
            context->collectCount = 0;
            if (context->netSpeedUnit != GNULL) {
                context->netSpeedUnit = realloc(context->netSpeedUnit, context->netSpeedCheckInterval*sizeof(GInt32));
            }else{
                context->netSpeedUnit = malloc(context->netSpeedCheckInterval*sizeof(GInt32));
            }
            
            GJPixelFormat vFormat = {0};
            vFormat.mHeight = (GUInt32)context->pushConfig->mPushSize.height;
            vFormat.mWidth = (GUInt32)context->pushConfig->mPushSize.width;
            vFormat.mType = GJPixelType_YpCbCr8BiPlanar_Full;
            if(context->videoProducer->obaque == GNULL){
                context->videoProducer->videoProduceSetup(context->videoProducer,vFormat,context->pushConfig->mFps,videoCaptureFrameOutCallback,context);
            }
            
            
            if (context->audioProducer->obaque == GNULL) {
                GJAudioFormat aFormat = {0};
                aFormat.mBitsPerChannel = 16;
                aFormat.mType = GJAudioType_PCM;
                aFormat.mFramePerPacket = 1;
                aFormat.mSampleRate = context->pushConfig->mAudioSampleRate;
                aFormat.mChannelsPerFrame = context->pushConfig->mAudioChannel;
                context->audioProducer->audioProduceSetup(context->audioProducer,aFormat,audioCaptureFrameOutCallback,context);
            }
            
            GJAudioFormat aFormat = {0};
            aFormat.mBitsPerChannel = 16;
            aFormat.mType = GJAudioType_PCM;
            aFormat.mFramePerPacket = 1;
            aFormat.mSampleRate = context->pushConfig->mAudioSampleRate;
            aFormat.mChannelsPerFrame = context->pushConfig->mAudioChannel;
            
            GJAudioStreamFormat aDFormat;
            aDFormat.bitrate = context->pushConfig->mAudioBitrate;
            aDFormat.format= aFormat;
            aDFormat.format.mFramePerPacket = 1024;
            aDFormat.format.mType = GJAudioType_AAC;
            if (context->audioEncoder->obaque == GNULL) {
                context->audioEncoder->encodeSetup(context->audioEncoder,aFormat,aDFormat,aacPacketOutCallback,context);
            }
            
            if (context->videoEncoder->obaque == GNULL) {
                context->videoEncoder->encodeSetup(context->videoEncoder,vFormat,h264PacketOutCallback,context);
                context->videoEncoder->encodeSetBitrate(context->videoEncoder,context->pushConfig->mVideoBitrate);
                context->videoEncoder->encodeSetProfile(context->videoEncoder,profileLevelMain);
                context->videoEncoder->encodeSetGop(context->videoEncoder,10);
                context->videoEncoder->encodeAllowBFrame(context->videoEncoder,GTrue);
                context->videoEncoder->encodeSetEntropy(context->videoEncoder,EntropyMode_CABAC);
            }
            
            GJVideoStreamFormat vf ;
            vf.format.mFps = context->pushConfig->mFps;
            vf.format.mWidth = vFormat.mWidth;
            vf.format.mHeight = vFormat.mHeight;
            vf.format.mType = GJVideoType_H264;
            vf.bitrate = context->pushConfig->mVideoBitrate;
            
            
            if(!GJStreamPush_Create(&context->videoPush, streamPushMessageCallback, (GHandle)context,&aDFormat,&vf)){
                GJLOG(GJ_LOGERROR, "GJStreamPush_Create error");
                result = GFalse;
                break;
            };
            
            if(!GJStreamPush_StartConnect(context->videoPush, url)){
                GJLOG(GJ_LOGERROR, "GJStreamPush_StartConnect error");
                result = GFalse;
                break;
            };
            
            requestStopServer = GFalse;
            if (serverThread == GNULL) {
                pthread_create(&serverThread, GNULL, thread_pthread_head, context);
            }
        }
    }while (0);
    pthread_mutex_unlock(&context->lock);
    return result;
}

GVoid GJLivePush_StopPush(GJLivePushContext* context){
    pthread_mutex_lock(&context->lock);
    if (context->videoPush) {
        context->stopPushClock = GJ_Gettime()/1000;
        context->audioProducer->audioProduceStop(context->audioProducer);
        context->videoProducer->stopProduce(context->videoProducer);
        context->videoEncoder->encodeFlush(context->videoEncoder);
        context->audioEncoder->encodeFlush(context->audioEncoder);
        while (context->operationCount) {
            GJLOG(GJ_LOGDEBUG, "GJLivePush_StopPush wait 100 us");
            usleep(100);
        }
        GJStreamPush_CloseAndDealloc(&context->videoPush);
    }else{
        GJLOG(GJ_LOGWARNING, "重复停止推流流");
    }
    pthread_mutex_unlock(&context->lock);
}

GBool GJLivePush_StartPreview(GJLivePushContext* context){
    return context->videoProducer->startPreview(context->videoProducer);
}

GVoid GJLivePush_StopPreview(GJLivePushContext* context){
    return context->videoProducer->stopPreview(context->videoProducer);
}

GBool GJLivePush_SetAudioMute(GJLivePushContext* context,GBool mute){
    context->audioMute = mute;
    return GTrue;
}

GBool GJLivePush_SetVideoMute(GJLivePushContext* context,GBool mute){
    context->videoMute = mute;
    return GTrue;
}

GBool GJLivePush_StartMixFile(GJLivePushContext* context,const GChar* fileName){
    GBool result = context->audioProducer->setupMixAudioFile(context->audioProducer,fileName,GFalse);
    if (result == GFalse) {
        return result;
    }
    result = context->audioProducer->startMixAudioFileAtTime(context->audioProducer,0);
    return result;
}

GBool GJLivePush_SetMixVolume(GJLivePushContext* context,GFloat32 volume){
    return GJCheckBool(context->audioProducer->setMixVolume(context->audioProducer,volume),"setMixVolume");
}

GBool GJLivePush_ShouldMixAudioToStream(GJLivePushContext* context,GBool should){
    return GJCheckBool(context->audioProducer->setMixToStream(context->audioProducer,should),"setMixToStream");
}

GBool GJLivePush_SetOutVolume(GJLivePushContext* context,GFloat32 volume){
    return GJCheckBool(context->audioProducer->setOutVolume(context->audioProducer,volume),"setOutVolume");
}

GBool GJLivePush_SetInputGain(GJLivePushContext* context,GFloat32 gain){
    return GJCheckBool(context->audioProducer->setInputGain(context->audioProducer,gain),"setInputGain");
}

GBool GJLivePush_EnableAudioInEarMonitoring(GJLivePushContext* context,GBool enable){
    if (context->audioProducer->obaque == GNULL) {
        return GFalse;
    }else{
        return context->audioProducer->enableAudioInEarMonitoring(context->audioProducer,enable);
    }
}

GBool GJLivePush_EnableReverb(GJLivePushContext* context,GBool enable){
    if (context->audioProducer->obaque == GNULL) {
        return GFalse;
    }else{
        return context->audioProducer->enableReverb(context->audioProducer,enable);
    }
}
GVoid GJLivePush_StopAudioMix(GJLivePushContext* context){
    context->audioProducer->stopMixAudioFile(context->audioProducer);
}

GVoid GJLivePush_SetCameraPosition(GJLivePushContext* context,GJCameraPosition position){
    context->videoProducer->setCameraPosition(context->videoProducer,position);
}

GVoid GJLivePush_SetOutOrientation(GJLivePushContext* context,GJInterfaceOrientation orientation){
    context->videoProducer->setOrientation(context->videoProducer,orientation);
}

GVoid GJLivePush_SetPreviewHMirror(GJLivePushContext* context,GBool preViewMirror){
    context->videoProducer->setHorizontallyMirror(context->videoProducer,preViewMirror);
}

GVoid GJLivePush_Dealloc(GJLivePushContext** pushContext){
    GJLivePushContext* context = *pushContext;
    if (context == GNULL) {
        GJLOG(GJ_LOGERROR, "非法释放");
    }else{
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
#endif
        }else{
            requestStopServer = GTrue;
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
        if (context->recoder) {//让录制结束后自己释放
            pthread_mutex_unlock(&context->lock);
            return;
        }
        pthread_mutex_unlock(&context->lock);
        pthread_mutex_destroy(&context->lock);
        
        free(context);
        *pushContext = GNULL;
    }
}

GJTrafficStatus GJLivePush_GetVideoTrafficStatus(GJLivePushContext* context){
    return GJStreamPush_GetVideoBufferCacheInfo(context->videoPush);
}

GJTrafficStatus GJLivePush_GetAudioTrafficStatus(GJLivePushContext* context){
    return GJStreamPush_GetAudioBufferCacheInfo(context->videoPush);
}

GHandle GJLivePush_GetDisplayView(GJLivePushContext* context){
    if (context->videoProducer->obaque == GNULL) {
        if (context->pushConfig != GNULL) {
            GJPixelFormat vFormat = {0};
            vFormat.mHeight = (GUInt32)context->pushConfig->mPushSize.height;
            vFormat.mWidth = (GUInt32)context->pushConfig->mPushSize.width;
            vFormat.mType = GJPixelType_YpCbCr8BiPlanar_Full;
            context->videoProducer->videoProduceSetup(context->videoProducer,vFormat,context->pushConfig->mFps,videoCaptureFrameOutCallback,context);
        }else{
            GJLOG(GJ_LOGERROR, "请先配置pushConfig");
        }
    }
    return context->videoProducer->getRenderView(context->videoProducer);
}

GBool GJLivePush_StartRecode(GJLivePushContext* context,GView view, GInt32 fps,const GChar* fileUrl){
    GBool result = GFalse;
    
    pthread_mutex_lock(&context->lock);
    do{
        if (context->recoder) {
            GJLOG(GJ_LOGFORBID, "上一个录制还未完成");
            result = GFalse;
            break;
        }else{
            if (context->pushConfig == GNULL || context->pushConfig->mAudioSampleRate <= 0 || context->pushConfig->mAudioChannel <= 0) {
                GJLOG(GJ_LOGFORBID, "请先配置正确pushConfig");
                result = GFalse;
                break;
            }
            GJAudioFormat format = {0};
            format.mChannelsPerFrame = context->pushConfig->mAudioChannel;
            format.mSampleRate = context->pushConfig->mAudioSampleRate;
            format.mType = GJAudioType_PCM;
            format.mBitsPerChannel = 16;
            format.mFramePerPacket = 1;
            GJ_RecodeContextCreate(&context->recoder);
            context->recoder->setup(context->recoder,fileUrl,_recodeCompleteCallback,context);
            context->recoder->addAudioSource(context->recoder,format);
            result = context->recoder->startRecode(context->recoder,view,fps);
        }
    }while(0);
    pthread_mutex_unlock(&context->lock);
    
    return result;
}

GVoid GJLivePush_StopRecode(GJLivePushContext* context){
    pthread_mutex_lock(&context->lock);
    if (context->recoder) {
        context->recoder->stopRecode(context->recoder);
    }
    pthread_mutex_unlock(&context->lock);
}
GBool GJLivePush_StartSticker(GJLivePushContext* context,const GVoid* images,GStickerParm parm,GInt32 fps,GJStickerUpdateCallback callback,const GVoid* userData){
    GBool result = GFalse;
    pthread_mutex_lock(&context->lock);
    if (context->videoProducer) {
        result = context->videoProducer->addSticker(context->videoProducer,images,parm,fps,callback,userData);
    }
    pthread_mutex_unlock(&context->lock);
    return result;
}
GVoid GJLivePush_StopSticker(GJLivePushContext* context){
    pthread_mutex_lock(&context->lock);
    if (context->videoProducer) {
        context->videoProducer->chanceSticker(context->videoProducer);
    }
    pthread_mutex_unlock(&context->lock);
}

GSize GJLivePush_GetCaptureSize(GJLivePushContext* context){
    GSize size = {0};
    
    if (context->videoProducer) {
        size = context->videoProducer->getCaptureSize(context->videoProducer);
    }
    
    return size;
}

GBool GJLivePush_SetMeasurementMode(GJLivePushContext* context,GBool measurementMode){
    GBool ret = GFalse;
    pthread_mutex_lock(&context->lock);
    if (context->audioProducer) {
        ret = context->audioProducer->enableMeasurementMode(context->audioProducer,measurementMode);
    }
    pthread_mutex_unlock(&context->lock);
    return ret;
}
