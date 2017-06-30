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

static GVoid _GJLivePush_AppendQualityWithStep(GJLivePushContext* context, GLong step);
static GVoid _GJLivePush_reduceQualityWithStep(GJLivePushContext* context, GLong step);

static GVoid videoCaptureFrameOutCallback (GHandle userData,R_GJPixelFrame* frame){
    GJLivePushContext* context = userData;
    if (context->stopPushClock == G_TIME_INVALID) {
        context->operationCount ++;
        if (!context->videoMute && (context->captureVideoCount++) % context->videoDropStep.den >= context->videoDropStep.num) {
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
            context->audioEncoder->encodeFrame(context->audioEncoder,frame);
        }
        context->operationCount--;
    }
}
static GVoid h264PacketOutCallback(GHandle userData,R_GJH264Packet* packet){
    GJLivePushContext* context = userData;
    packet->pts = GJ_Gettime()/1000-context->connentClock;
    if (context->firstVideoEncodeClock == G_TIME_INVALID) {
        context->firstVideoEncodeClock = GJ_Gettime()/1000;
        GUInt8* sps,*pps;
        GInt32 spsSize,ppsSize;
        sps = pps = GNULL;
        
        context->videoEncoder->encodeGetSPS_PPS(context->videoEncoder,sps,&spsSize,pps,&ppsSize);
        if (spsSize <= 0 || ppsSize <= 0) {
            GJLOG(GJ_LOGERROR, "无法获得sps,pps2");
            context->firstVideoEncodeClock = G_TIME_INVALID;
            return;
        }else{
            sps = (GUInt8*)malloc(spsSize);
            pps = (GUInt8*)malloc(ppsSize);
            context->videoEncoder->encodeGetSPS_PPS(context->videoEncoder,sps,&spsSize,pps,&ppsSize);
            if (sps == GNULL || pps == GNULL) {
                GJLOG(GJ_LOGERROR, "无法获得sps,pps2");
                context->firstVideoEncodeClock = G_TIME_INVALID;
                free(sps);
                free(pps);
                return;
            }else{
                if(!GJRtmpPush_SendAVCSequenceHeader(context->videoPush, sps, spsSize, pps, ppsSize, packet->pts)){
                    if (context->videoPush != GNULL) {
                        GJLOG(GJ_LOGERROR, "SendAVCSequenceHeader 失败");
                    }
                    context->firstVideoEncodeClock = G_TIME_INVALID;
                    free(sps);
                    free(pps);
                    return;
                }else{
                    free(sps);
                    free(pps);
                }
            }
        }
    }
    GJRtmpPush_SendH264Data(context->videoPush, packet);
    GJTrafficStatus bufferStatus = GJRtmpPush_GetVideoBufferCacheInfo(context->videoPush);
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
                GLong cacheInPts = bufferStatus.enter.pts - bufferStatus.leave.pts;
                if (diffInCount < context->dynamicAlgorithm.den && cacheInPts > SEND_DELAY_TIME && cacheInCount > SEND_DELAY_COUNT) {
                    GJLOG(GJ_LOGWARNING, "宏观检测出降低视频质量 (很少可能会出现)");
                    _GJLivePush_reduceQualityWithStep(context, context->dynamicAlgorithm.den - diffInCount);
                }
            }
        }
        context->preVideoTraffic = bufferStatus;
    }
}
static GVoid aacPacketOutCallback(GHandle userData,R_GJAACPacket* packet){
    GJLivePushContext* context = userData;
    packet->pts = GJ_Gettime()/1000-context->connentClock;
    if (context->firstAudioEncodeClock == G_TIME_INVALID) {
        context->firstAudioEncodeClock = GJ_Gettime();
        if (!GJRtmpPush_SendAACSequenceHeader(context->videoPush, 2, context->pushConfig->mAudioSampleRate,  context->pushConfig->mAudioChannel, packet->pts)) {
            if (context->videoPush!= GNULL) {
                GJLOG(GJ_LOGFORBID, "SendAACSequenceHeader 失败");
            }
            context->firstAudioEncodeClock = G_TIME_INVALID;
            return;
        }
    }
    GJRtmpPush_SendAACData(context->videoPush, packet);
}



GVoid rtmpPushMessageCallback(GHandle userData, GJRTMPPushMessageType messageType,GHandle messageParm){
    GJLivePushContext* context = userData;
    switch (messageType) {
        case GJRTMPPushMessageType_connectSuccess:
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
        case GJRTMPPushMessageType_closeComplete:{
            GJPushSessionInfo info = {0};
            context->disConnentClock = GJ_Gettime()/1000;
            info.sessionDuring = (GLong)(context->disConnentClock - context->connentClock);
            context->callback(context->userData,GJLivePush_closeComplete,&info);
        }
            break;
        case GJRTMPPushMessageType_urlPraseError:
        case GJRTMPPushMessageType_connectError:
            GJLOG(GJ_LOGINFO, "推流连接失败");
            context->callback(context->userData,GJLivePush_connectError,"rtmp连接失败");
            GJLivePush_StopPush(context);
            break;
        case GJRTMPPushMessageType_sendPacketError:
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
    
    GJLivePushContext* context = ctx;
    
    struct raop_server_settings_t setting;
    setting.name = GNULL;
    setting.password = GNULL;
    setting.ignore_source_volume = GFalse;
    context->server = raop_server_create(setting);
    if (!raop_server_is_running(context->server)) {
        
        uint16_t port = 5000;
        while (port < 5010 && !raop_server_start(context->server, port++));
    }
    context->serverThread = GNULL;
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
        
      
        pthread_create(&context->serverThread, GNULL, thread_pthread_head, context);
        pthread_mutex_init(&context->lock, GNULL);
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
            
            if(context->videoProducer->obaque == GNULL){
                GJVideoFormat vFormat = {0};
                vFormat.mFps = context->pushConfig->mFps;
                vFormat.mHeight = (GUInt32)context->pushConfig->mPushSize.height;
                vFormat.mWidth = (GUInt32)context->pushConfig->mPushSize.width;
                vFormat.mType = GJPixelType_YpCbCr8BiPlanar_Full;
                context->videoProducer->videoProduceSetup(context->videoProducer,vFormat,videoCaptureFrameOutCallback,context);
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
            
            GJAudioFormat aDFormat = aFormat;
            aDFormat.mFramePerPacket = 1024;
            aDFormat.mType = GJAudioType_AAC;
            context->audioEncoder->encodeSetup(context->audioEncoder,aFormat,aDFormat,aacPacketOutCallback,context);
            context->audioEncoder->encodeSetBitrate(context->audioEncoder,context->pushConfig->mAudioBitrate);
            GJPixelFormat vformat = {0};
            vformat.mHeight = context->pushConfig->mPushSize.height;
            vformat.mWidth = context->pushConfig->mPushSize.width;
            vformat.mType = GJPixelType_YpCbCr8BiPlanar_Full;
            context->videoEncoder->encodeSetup(context->videoEncoder,vformat,h264PacketOutCallback,context);
            context->videoEncoder->encodeSetBitrate(context->videoEncoder,context->pushConfig->mVideoBitrate);
            context->videoEncoder->encodeSetProfile(context->videoEncoder,profileLevelMain);
            context->videoEncoder->encodeSetGop(context->videoEncoder,10);
            context->videoEncoder->encodeAllowBFrame(context->videoEncoder,GTrue);
            context->videoEncoder->encodeSetEntropy(context->videoEncoder,EntropyMode_CABAC);
            if(!GJRtmpPush_Create(&context->videoPush, rtmpPushMessageCallback, (GHandle)context)){
                result = GFalse;
                break;
            };
            if(!GJRtmpPush_StartConnect(context->videoPush, url)){
                result = GFalse;
                break;
            };
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
        GJRtmpPush_CloseAndDealloc(&context->videoPush);
        context->audioProducer->audioProduceStop(context->audioProducer);
        context->videoProducer->stopProduce(context->videoProducer);
        context->audioEncoder->encodeUnSetup(context->audioEncoder);
        context->videoEncoder->encodeUnSetup(context->videoEncoder);
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
        if (context->serverThread) {
            pthread_join(context->serverThread, GNULL);
        }
        free(context);
        *pushContext = GNULL;
    }
}
GJTrafficStatus GJLivePush_GetVideoTrafficStatus(GJLivePushContext* context){
    return GJRtmpPush_GetVideoBufferCacheInfo(context->videoPush);
}
GJTrafficStatus GJLivePush_GetAudioTrafficStatus(GJLivePushContext* context){
    return GJRtmpPush_GetAudioBufferCacheInfo(context->videoPush);
}
GHandle GJLivePush_GetDisplayView(GJLivePushContext* context){
    if (context->videoProducer->obaque == GNULL) {
        if (context->pushConfig != GNULL) {
            GJVideoFormat vFormat = {0};
            vFormat.mFps = context->pushConfig->mFps;
            vFormat.mHeight = (GUInt32)context->pushConfig->mPushSize.height;
            vFormat.mWidth = (GUInt32)context->pushConfig->mPushSize.width;
            vFormat.mType = GJPixelType_YpCbCr8BiPlanar_Full;
            context->videoProducer->videoProduceSetup(context->videoProducer,vFormat,videoCaptureFrameOutCallback,context);
        }else{
            GJLOG(GJ_LOGERROR, "请先配置pushConfig");
        }
    }
    return context->videoProducer->getRenderView(context->videoProducer);
}
