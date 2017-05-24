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
#define I_P_RATE 4
#define DROP_BITRATE_RATE 0.1

static GVoid _GJLivePush_AppendQualityWithStep(GJLivePushContext* context, GLong step);
static GVoid _GJLivePush_reduceQualityWithStep(GJLivePushContext* context, GLong step);

static GVoid videoCaptureFrameOutCallback (GHandle userData,R_GJPixelFrame* frame){
    GJLivePushContext* context = userData;
    if ((context->captureVideoCount++) % context->videoDropStep.den >= context->videoDropStep.num) {
        frame->pts = GJ_Gettime()/1000-context->connentClock;
        context->videoEncoder->encodeFrame(context->videoEncoder,frame,GFalse);
    }else{
        GJLOG(GJ_LOGWARNING, "丢视频帧");
        context->dropVideoCount++;
    }
}
static GVoid audioCaptureFrameOutCallback (GHandle userData,R_GJPCMFrame* frame){
    GJLivePushContext* context = userData;
    frame->pts = GJ_Gettime()/1000-context->connentClock;
    context->audioEncoder->encodeFrame(context->audioEncoder,frame);
}
static GVoid h264PacketOutCallback(GHandle userData,R_GJH264Packet* packet){
    GJLivePushContext* context = userData;
    GJRtmpPush_SendH264Data(context->videoPush, packet);
    GJTrafficStatus bufferStatus = GJRtmpPush_GetVideoBufferCacheInfo(context->videoPush);
    if (bufferStatus.enter.count % context->dynamicAlgorithm.den == 0) {
        GLong cacheInCount = bufferStatus.enter.count - bufferStatus.leave.count;
        if(cacheInCount == 1 && context->videoBitrate < context->pushConfig.mVideoBitrate){
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
    GJRtmpPush_SendAACData(context->videoPush, packet);
}



GVoid rtmpPushMessageCallback(GHandle userData, GJRTMPPushMessageType messageType,GHandle messageParm){
    GJLivePushContext* context = userData;
    switch (messageType) {
        case GJRTMPPushMessageType_connectSuccess:
        {
            GJLOG(GJ_LOGINFO, "推流连接成功");
            context->connentClock = GJ_Gettime()/1000;
            context->audioProducer->audioProduceStart(context->audioProducer);
            context->videoProducer->startProduce(context->videoProducer);
        }
            break;
        case GJRTMPPushMessageType_closeComplete:{
            GJPushSessionInfo info = {0};
            context->disConnentClock = GJ_Gettime()/1000;
            info.sessionDuring = context->disConnentClock - context->connentClock;
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
            bitrate += context->videoMinBitrate/context->pushConfig.mFps*I_P_RATE;
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
            bitrate += bitrate/context->pushConfig.mFps*(1-GRationalValue(context->videoDropStep))*I_P_RATE;
            quality = GJNetworkQualitybad;
            GJLOG(GJ_LOGINFO, "appendQuality by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);
        }
    }
    if(leftStep > 0){
        if (bitrate < context->pushConfig.mVideoBitrate) {
            bitrate += (context->pushConfig.mVideoBitrate - context->videoMinBitrate)*leftStep*DROP_BITRATE_RATE;
            bitrate = GMIN(bitrate, context->pushConfig.mVideoBitrate);
            quality = GJNetworkQualityGood;
        }else{
            quality = GJNetworkQualityExcellent;
            bitrate = context->pushConfig.mVideoBitrate;
            GJLOG(GJ_LOGINFO, "appendQuality to full speed:%f",bitrate/1024.0/8.0);
        }
    }
    if (context->videoBitrate != bitrate) {
        if(context->videoEncoder->encodeSetBitrate(context->videoEncoder,bitrate)){
            context->videoBitrate = bitrate;
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
        bitrate -= (context->pushConfig.mVideoBitrate - context->videoMinBitrate)*leftStep*DROP_BITRATE_RATE;
        leftStep = 0;
        if (bitrate < context->videoMinBitrate) {
            leftStep = (currentBitRate - bitrate)/((context->pushConfig.mVideoBitrate - context->videoMinBitrate)*DROP_BITRATE_RATE);
            bitrate = context->pushConfig.mVideoBitrate;
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
            bitrate += bitrate/context->pushConfig.mFps*(1-GRationalValue(context->videoDropStep))*I_P_RATE;
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
        bitrate += bitrate/context->pushConfig.mFps*(1-GRationalValue(context->videoDropStep))*I_P_RATE;
        quality = GJNetworkQualityTerrible;
        GJLOG(GJ_LOGINFO, "reduceQuality2 by reduce to drop frame:num %d,den %d",context->videoDropStep.num,context->videoDropStep.den);
    }
    
    if (context->videoBitrate != bitrate) {
        if(context->videoEncoder->encodeSetBitrate(context->videoEncoder,bitrate)){
            context->videoBitrate = bitrate;
        }
        context->callback(context->userData,GJLivePush_updateNetQuality,&quality);
    }
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
        
        GJVideoFormat vFormat = {0};
        vFormat.mFps = 15;
        vFormat.mHeight = 640;
        vFormat.mWidth = 480;
        vFormat.mType = GJPixelType_YpCbCr8BiPlanar_Full;
        context->videoProducer->videoProduceSetup(context->videoProducer,vFormat,videoCaptureFrameOutCallback,context);
        pthread_mutex_init(&context->lock, GNULL);
    }while (0);
    return result;
}
GVoid GJLivePush_SetConfig(GJLivePushContext* context,const GJPushConfig* config){
    context->pushConfig = *config;
    context->videoProducer->setProduceSize(context->videoProducer,config->mPushSize);
    context->videoProducer->setFrameRate(context->videoProducer,config->mFps);
}

GBool GJLivePush_StartPush(GJLivePushContext* context,const GChar* url){
    GBool result = GTrue;
    do{
        pthread_mutex_lock(&context->lock);
        if (context->videoPush != GNULL) {
            GJLOG(GJ_LOGERROR, "请先停止上一个流");
        }else{
            context->connentClock = context->disConnentClock = G_TIME_INVALID;
            context->startPushClock = GJ_Gettime()/1000;
            GJPixelFormat vformat = {0};
            vformat.mHeight = context->pushConfig.mPushSize.height;
            vformat.mWidth = context->pushConfig.mPushSize.width;
            vformat.mType = GJPixelType_YpCbCr8BiPlanar_Full;
            context->videoEncoder->encodeSetup(context->videoEncoder,vformat,h264PacketOutCallback,context);
            
            GJAudioFormat aFormat = {0};
            aFormat.mBitsPerChannel = 16;
            aFormat.mType = GJAudioType_PCM;
            aFormat.mFramePerPacket = 1;
            aFormat.mSampleRate = context->pushConfig.mAudioSampleRate;
            aFormat.mChannelsPerFrame = context->pushConfig.mAudioChannel;
            context->audioProducer->audioProduceSetup(context->audioProducer,aFormat,audioCaptureFrameOutCallback,context);
            GJAudioFormat aDFormat = aFormat;
            aDFormat.mFramePerPacket = 1024;
            aDFormat.mType = GJAudioType_AAC;
            context->audioEncoder->encodeSetup(context->audioEncoder,aFormat,aDFormat,aacPacketOutCallback,context);
            
            if(!GJRtmpPush_Create(&context->videoPush, rtmpPushMessageCallback, (GHandle)context)){
                result = GFalse;
                break;
            };
        }
        pthread_mutex_unlock(&context->lock);
    }while (0);
    return result;
}
GVoid GJLivePush_StopPush(GJLivePushContext* context){
    pthread_mutex_lock(&context->lock);
    if (context->videoPush) {
        GJRtmpPush_CloseAndDealloc(&context->videoPush);
        context->audioProducer->audioProduceStop(context->audioProducer);
        context->audioProducer->audioProduceUnSetup(context->audioProducer);
        context->videoProducer->stopProduce(context->videoProducer);
        context->audioEncoder->encodeUnSetup(context->audioEncoder);
        context->videoEncoder->encodeUnSetup(context->videoEncoder);
    }else{
        GJLOG(GJ_LOGWARNING, "重复停止拉流");
    }
    pthread_mutex_unlock(&context->lock);
}
GBool GJLivePush_StartPreview(GJLivePushContext* context){
    return context->videoProducer->startPreview(context->videoProducer);
}
GVoid GJLivePush_StopPreview(GJLivePushContext* context){
    return context->videoProducer->stopPreview(context->videoProducer);
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
        pthread_mutex_destroy(&context->lock);
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
    return context->videoProducer->getRenderView(context->videoProducer);
}
