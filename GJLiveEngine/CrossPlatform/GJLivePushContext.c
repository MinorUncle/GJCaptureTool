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
#define I_P_RATE 4
#define DROP_BITRATE_RATE 0.1

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

static GVoid videoCaptureFrameOutCallback (GHandle userData,R_GJPixelFrame* frame){
    GJLivePushContext* context = userData;
    if (context->stopPushClock == G_TIME_INVALID) {
        context->operationCount ++;
        if (!context->videoMute && (context->captureVideoCount++) % context->videoDropStep.den >= context->videoDropStep.num) {
            frame->pts = GJ_Gettime()/1000-context->connentClock;
            context->videoEncoder->encodeFrame(context->videoEncoder,frame,GFalse);
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
        }
        context->operationCount--;
    }
}
static GVoid h264PacketOutCallback(GHandle userData,R_GJPacket* packet){
    GJLivePushContext* context = userData;
//    packet->dts -= 1000 / context->pushConfig->mFps;
    
    
    GJStreamPush_SendVideoData(context->videoPush, packet);
    GJTrafficStatus bufferStatus = GJStreamPush_GetVideoBufferCacheInfo(context->videoPush);
    if (bufferStatus.enter.count % context->dynamicAlgorithm.den == 0) {
        GLong cacheInCount = bufferStatus.enter.count - bufferStatus.leave.count;
        if(cacheInCount == 1 && context->videoBitrate < context->pushConfig->mVideoBitrate){
            GJLOG(GJ_LOGINFO, "宏观检测出提高视频质量");
            _GJLivePush_AppendQualityWithStep(context, 1);
        }else{
            GLong diffInCount = bufferStatus.leave.count - context->preVideoTraffic.leave.count;
            if(diffInCount <= context->dynamicAlgorithm.num){//降低质量敏感检测
                GJLOG(GJ_LOGINFO, "敏感检测出降低视频质量");
                _GJLivePush_reduceQualityWithStep(context, context->dynamicAlgorithm.num - diffInCount + 1);
            }else if(diffInCount > context->dynamicAlgorithm.den + context->dynamicAlgorithm.num){//提高质量敏感检测
                GJLOG(GJ_LOGINFO, "敏感检测出提高音频质量");
                _GJLivePush_AppendQualityWithStep(context, diffInCount - context->dynamicAlgorithm.den - context->dynamicAlgorithm.num);
            }else{
                GLong cacheInPts = bufferStatus.enter.ts - bufferStatus.leave.ts;
                if (diffInCount < context->dynamicAlgorithm.den && cacheInPts > SEND_DELAY_TIME && cacheInCount > SEND_DELAY_COUNT) {
                    GJLOG(GJ_LOGWARNING, "宏观检测出降低视频质量 (很少可能会出现)");
                    _GJLivePush_reduceQualityWithStep(context, context->dynamicAlgorithm.den - diffInCount);
                }
            }
        }
        context->preVideoTraffic = bufferStatus;
    }
}
static GVoid aacPacketOutCallback(GHandle userData,R_GJPacket* packet){
    GJLivePushContext* context = userData;
    if (context->firstAudioEncodeClock == G_TIME_INVALID) {
        if (GJStreamPush_GetVideoBufferCacheInfo(context->videoPush).enter.ts > packet->dts) {
            return;
        }else{
            context->firstAudioEncodeClock = GJ_Gettime();
        }
    }
    GJStreamPush_SendAudioData(context->videoPush, packet);
}



GVoid streamPushMessageCallback(GHandle userData, GJStreamPushMessageType messageType,GHandle messageParm){
    GJLivePushContext* context = userData;
    switch (messageType) {
        case GJStreamPushMessageType_connectSuccess:
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
        case GJStreamPushMessageType_closeComplete:{
            GJPushSessionInfo info = {0};
            context->disConnentClock = GJ_Gettime()/1000;
            info.sessionDuring = (GLong)(context->disConnentClock - context->connentClock);
            context->callback(context->userData,GJLivePush_closeComplete,&info);
        }
            break;
        case GJStreamPushMessageType_urlPraseError:
        case GJStreamPushMessageType_connectError:
            GJLOG(GJ_LOGINFO, "推流连接失败");
            context->callback(context->userData,GJLivePush_connectError,"rtmp连接失败");
            GJLivePush_StopPush(context);
            break;
        case GJStreamPushMessageType_sendPacketError:
            context->callback(context->userData,GJLivePush_sendPacketError,"发送失败");
            GJLivePush_StopPush(context);
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
    GJLOG(GJ_LOGINFO, "appendQualityWithStep：%d",step);
    if (leftStep > 0 && GRationalValue(context->videoDropStep) > 0.5) {
//        _dropStep += _allowDropStep-1+leftStep;
        GJAssert(context->videoDropStep.den - context->videoDropStep.num == 1, "管理错误1");

        context->videoDropStep.num -= leftStep;
        context->videoDropStep.den -= leftStep;
        leftStep = 0;
        if (context->videoDropStep.num < 1) {
            leftStep = 1 - context->videoDropStep.num;
            context->videoDropStep = GRationalMake(1,2);
        }else{
            bitrate = context->videoMinBitrate*(1-GRationalValue(context->videoDropStep));
            bitrate += context->videoMinBitrate/context->pushConfig->mFps*I_P_RATE;
            quality = GJNetworkQualityTerrible;
            GJLOG(GJ_LOGINFO, "appendQuality by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);
        }
    }
    if (leftStep > 0 && context->videoDropStep.num != 0) {
        //        _dropStep += _allowDropStep-1+leftStep;
        GJAssert(context->videoDropStep.num == 1, "管理错误2");
        context->videoDropStep.num = 1;
        context->videoDropStep.den += leftStep;
        leftStep = 0;
        if (context->videoDropStep.den > DEFAULT_MAX_DROP_STEP) {
            leftStep = DEFAULT_MAX_DROP_STEP - context->videoDropStep.den;
            context->videoDropStep = GRationalMake(0,DEFAULT_MAX_DROP_STEP);
            bitrate = context->videoMinBitrate;
        }else{
            bitrate = context->videoMinBitrate*(1-GRationalValue(context->videoDropStep));
            bitrate += bitrate/context->pushConfig->mFps*(1-GRationalValue(context->videoDropStep))*I_P_RATE;
            quality = GJNetworkQualitybad;
            GJLOG(GJ_LOGINFO, "appendQuality by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);
        }
    }
    if(leftStep > 0){
        if (bitrate < context->pushConfig->mVideoBitrate) {
            bitrate += (context->pushConfig->mVideoBitrate - context->videoMinBitrate)*leftStep*DROP_BITRATE_RATE;
            bitrate = GMIN(bitrate, context->pushConfig->mVideoBitrate);
            quality = GJNetworkQualityGood;
        }else{
            quality = GJNetworkQualityExcellent;
            bitrate = context->pushConfig->mVideoBitrate;
            GJLOG(GJ_LOGINFO, "appendQuality to full speed:%f",bitrate/1024.0/8.0);
        }
    }
    if (context->videoBitrate != bitrate) {
        if(context->videoEncoder->encodeSetBitrate(context->videoEncoder,bitrate)){
            context->videoBitrate = bitrate;
            
            VideoDynamicInfo info ;
            info.sourceFPS = context->pushConfig->mFps;
            info.sourceBitrate = context->pushConfig->mVideoBitrate;
            info.currentFPS = info.sourceFPS - GRationalValue(context->videoDropStep);
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

    if (currentBitRate > context->videoMinBitrate) {
        bitrate -= (context->pushConfig->mVideoBitrate - context->videoMinBitrate)*leftStep*DROP_BITRATE_RATE;
        leftStep = 0;
        if (bitrate < context->videoMinBitrate) {
            leftStep = (currentBitRate - bitrate)/((context->pushConfig->mVideoBitrate - context->videoMinBitrate)*DROP_BITRATE_RATE);
            bitrate = context->pushConfig->mVideoBitrate;
        }
        quality = GJNetworkQualityGood;
    }
    if (leftStep > 0 && GRationalValue(context->videoDropStep) <= 0.50001 && GRationalValue(context->videoDropStep) < GRationalValue(context->videoMinDropStep)){
        if(context->videoDropStep.num == 0)context->videoDropStep = GRationalMake(1, DEFAULT_MAX_DROP_STEP);
        context->videoDropStep.num = 1;
        context->videoDropStep.den -= leftStep;
        leftStep = 0;

        GRational tempR = GRationalMake(1, 2);
        if (GRationalValue(context->videoMinDropStep) < 0.5) {
            tempR = context->videoMinDropStep;
        }
        if (context->videoDropStep.den < tempR.den) {
            leftStep = tempR.den - context->videoDropStep.den;
            context->videoDropStep.den = tempR.den;
        }else{

            bitrate = context->videoMinBitrate*(1-GRationalValue(context->videoDropStep));
            bitrate += bitrate/context->pushConfig->mFps*(1-GRationalValue(context->videoDropStep))*I_P_RATE;
            quality = GJNetworkQualitybad;
            GJLOG(GJ_LOGINFO, "reduceQuality1 by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);

        }
    }
    if (leftStep > 0 && GRationalValue(context->videoDropStep) < GRationalValue(context->videoMinDropStep)){
        context->videoDropStep.num += leftStep;
        context->videoDropStep.den += leftStep;
        if(context->videoDropStep.den > context->videoMinDropStep.den){
            context->videoDropStep.num -= context->videoDropStep.den - context->videoMinDropStep.den;
            context->videoDropStep.den = context->videoMinDropStep.den;
        }
        bitrate = context->videoMinBitrate*(1-GRationalValue(context->videoDropStep));
        bitrate += bitrate/context->pushConfig->mFps*(1-GRationalValue(context->videoDropStep))*I_P_RATE;
        quality = GJNetworkQualityTerrible;
        GJLOG(GJ_LOGINFO, "reduceQuality2 by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);
    }
    
    if (context->videoBitrate != bitrate) {
        if(context->videoEncoder->encodeSetBitrate(context->videoEncoder,bitrate)){
            context->videoBitrate = bitrate;
            VideoDynamicInfo info ;
            info.sourceFPS = context->pushConfig->mFps;
            info.sourceBitrate = context->pushConfig->mVideoBitrate;
            info.currentFPS = info.sourceFPS - GRationalValue(context->videoDropStep);
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
        server = raop_server_create(setting);
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
    serverThread = GNULL;
#endif
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
    pthread_mutex_lock(&context->lock);
    if (context->videoPush != GNULL) {
        GJLOG(GJ_LOGERROR, "推流期间不能配置pushconfig");
    }else{
        if (context->pushConfig == GNULL) {
            context->pushConfig = (GJPushConfig*)malloc(sizeof(GJPushConfig));
        }else{

            if (context->videoProducer->obaque != GNULL) {
                if (context->pushConfig->mFps != config->mFps) {
                    context->videoProducer->setFrameRate(context->videoProducer,config->mFps);
                }
                if (!GSizeEqual(context->pushConfig->mPushSize, config->mPushSize)) {
                    context->videoProducer->setProduceSize(context->videoProducer,config->mPushSize);
                }
            }
            if (context->audioProducer->obaque != GNULL) {
                if (context->pushConfig->mAudioChannel != config->mAudioChannel ||
                    context->pushConfig->mAudioSampleRate != config->mAudioSampleRate) {
                    context->audioProducer->audioProduceUnSetup(context->audioProducer);
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
            context->audioEncoder->encodeSetup(context->audioEncoder,aFormat,aDFormat,aacPacketOutCallback,context);
//            context->audioEncoder->encodeSetBitrate(context->audioEncoder,context->pushConfig->mAudioBitrate);

            context->videoEncoder->encodeSetup(context->videoEncoder,vFormat,h264PacketOutCallback,context);
            context->videoEncoder->encodeSetBitrate(context->videoEncoder,context->pushConfig->mVideoBitrate);
            context->videoEncoder->encodeSetProfile(context->videoEncoder,profileLevelMain);
            context->videoEncoder->encodeSetGop(context->videoEncoder,10);
            context->videoEncoder->encodeAllowBFrame(context->videoEncoder,GTrue);
            context->videoEncoder->encodeSetEntropy(context->videoEncoder,EntropyMode_CABAC);
            
            GJVideoStreamFormat vf ;
            vf.format.mFps = context->pushConfig->mFps;
            vf.format.mWidth = vFormat.mWidth;
            vf.format.mHeight = vFormat.mHeight;
            vf.format.mType = GJVideoType_H264;
            vf.bitrate = context->pushConfig->mVideoBitrate;
            

            if(!GJStreamPush_Create(&context->videoPush, streamPushMessageCallback, (GHandle)context,aDFormat,vf)){
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
        while (context->operationCount) {
            GJLOG(GJ_LOGDEBUG, "GJLivePush_StopPush wait 10 us");
            usleep(10);
        }
        GJStreamPush_CloseAndDealloc(&context->videoPush);
        context->audioProducer->audioProduceStop(context->audioProducer);
        context->videoProducer->stopProduce(context->videoProducer);
        context->audioEncoder->encodeUnSetup(context->audioEncoder);
        context->videoEncoder->encodeUnSetup(context->videoEncoder);
        
        if (serverThread == GNULL) {
#ifdef RAOP
            raop_server_stop(server);
#endif
            
#ifdef RVOP
            rvop_server_stop(rvopserver);

#endif
        }else{
            requestStopServer = GTrue;
        }
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
        GJ_H264EncodeContextDealloc(&context->videoEncoder);
        GJ_AACEncodeContextDealloc(&context->audioEncoder);
        GJ_VideoProduceContextDealloc(&context->videoProducer);
        GJ_AudioProduceContextDealloc(&context->audioProducer);
        if (context->pushConfig) {
            free(context->pushConfig);
        }
        pthread_mutex_destroy(&context->lock);
        if (serverThread == GNULL) {
#ifdef RAOP
            raop_server_destroy(server);
#endif
#ifdef RVOP
            rvop_server_destroy(rvopserver);
#endif
        }else{
            requestDestoryServer = GTrue;
        }
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
