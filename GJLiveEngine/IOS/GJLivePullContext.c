//
//  GJLivePullContext.c
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLivePullContext.h"
#include "GJUtil.h"
#include "GJLog.h"
#include <string.h>
static void pullMessageCallback(GJRtmpPull* pull, GJRTMPPullMessageType messageType,void* rtmpPullParm,void* messageParm);
static GVoid livePlayCallback(GHandle userDate,GJPlayMessage message,GHandle param);
static void pullDataCallback(GJRtmpPull* pull,R_GJStreamPacket streamPacket,void* parm);
static GVoid aacDecodeCompleteCallback(GHandle userData,R_GJPCMFrame* frame);
static GVoid h264DecodeCompleteCallback(GHandle userData,R_GJPixelFrame* frame);

GBool GJLivePull_Create(GJLivePullContext* context,GJLivePullCallback callback,GHandle param){
    GBool result = GFalse;
    do{
        if (context == GNULL) {
            context = (GJLivePullContext*)calloc(1,sizeof(GJLivePullContext));
            if (context == NULL) {
                result = GFalse;
                break;
            }
            memset((GHandle)context, 0, sizeof(GJLivePullContext));
        }
        if(!GJLivePlay_Create(context->player, livePlayCallback, context)){
            result = GFalse;
            break;
        };
        GJ_H264DecodeContextSetup(context->videoDecoder);
        GJ_AACDecodeContextSetup(context->audioDecoder);
        
        if(!context->videoDecoder->decodeCreate(context->videoDecoder,GJPixelType_YpCbCr8BiPlanar_Full,h264DecodeCompleteCallback,context)){
            result = GFalse;
            break;
        }
        pthread_mutex_init(&context->lock, GNULL);
    }while (0);
    return result;
}
GBool GJLivePull_StartPull(GJLivePullContext* context,char* url){
    GBool result = GTrue;
    do{
    pthread_mutex_lock(&context->lock);
    context->fristAudioClock = context->fristVideoClock = context->connentClock = context->fristVideoDecodeClock = 0;
    if (context->videoPull != GNULL) {
        GJRtmpPull_CloseAndRelease(context->videoPull);
    }
    if(!GJRtmpPull_Create(&context->videoPull, pullMessageCallback, context)){
        result = GFalse;
        break;
    };
    if(!GJRtmpPull_StartConnect(context->videoPull, pullDataCallback,context,(const char*) url)){
        result = GFalse;
        break;
    };
    if (!GJLivePlay_Start(context->player)) {
        result = GFalse;
        break;
    }
    context->startPullClock = GJ_Gettime()/1000;
    pthread_mutex_unlock(&context->lock);
    }while (0);
    return result;
}
GVoid GJLivePull_StopPull(GJLivePullContext* context){
    pthread_mutex_lock(&context->lock);
    if (context->videoPull) {
        GJRtmpPull_CloseAndRelease(context->videoPull);
        context->videoPull = GNULL;
    }
    GJLivePlay_Stop(context->player);
    context->audioDecoder->decodeRelease(context->audioDecoder);
    free(context->audioDecoder);
    context->audioDecoder = GNULL;
    pthread_mutex_unlock(&context->lock);
}
GVoid GJLivePull_Dealloc(GJLivePullContext* context);

static GVoid livePlayCallback(GHandle userDate,GJPlayMessage message,GHandle param){
}
static void pullMessageCallback(GJRtmpPull* pull, GJRTMPPullMessageType messageType,void* rtmpPullParm,void* messageParm){
    GJLivePullContext* livePull = rtmpPullParm;
    
        switch (messageType) {
            case GJRTMPPullMessageType_connectError:
            case GJRTMPPullMessageType_urlPraseError:
                GJLOG(GJ_LOGERROR, "pull connect error:%d",messageType);
                livePull->callback(livePull->userData,GJLivePullMessageType_urlPraseError,"连接错误");
                GJLivePull_StopPull(livePull);
                break;
            case GJRTMPPullMessageType_receivePacketError:
                GJLOG(GJ_LOGERROR, "pull sendPacket error:%d",messageType);
                livePull->callback(livePull->userData,GJLivePullMessageType_receivePacketError,"读取失败");
                GJLivePull_StopPull(livePull);
                break;
            case GJRTMPPullMessageType_connectSuccess:
            {
                GJLOG(GJ_LOGINFO, "pull connectSuccess");
                livePull->connentClock = GJ_Gettime()/1000.0;
                livePull->callback(livePull->userData,GJLivePullMessageType_connectSuccess,"连接成功");
            }
                break;
            case GJRTMPPullMessageType_closeComplete:{
                GJLOG(GJ_LOGINFO, "pull closeComplete");

                GJPullSessionInfo info = {0};
                info.sessionDuring = GJ_Gettime()/1000 - livePull->startPullClock;

                livePull->callback(livePull->userData,GJLivePullMessageType_closeComplete,(GHandle)&info);
            }
                break;
            default:
                GJLOG(GJ_LOGFORBID,"not catch info：%d",messageType);
                break;
        }
}
static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
static void pullDataCallback(GJRtmpPull* pull,R_GJStreamPacket streamPacket,void* parm){
    GJLivePullContext* livePull = parm;
    
    
    if (streamPacket.type == GJMediaType_Audio) {
        GJRetainBuffer* buffer = &streamPacket.packet.aacPacket->retain;
        if (livePull->fristAudioClock == G_TIME_INVALID) {
            livePull->fristAudioClock = GJ_Gettime()/1000.0;
            uint8_t* adts = streamPacket.packet.aacPacket->adtsOffset+streamPacket.packet.aacPacket->retain.data;
            uint8_t sampleIndex = adts[2] << 2;
            sampleIndex = sampleIndex>>4;
            int sampleRate = mpeg4audio_sample_rates[sampleIndex];
            uint8_t channel = adts[2] & 0x1 <<2;
            channel += (adts[3] & 0xc0)>>6;
            
            GJAudioFormat sourceformat = {0};
            sourceformat.mType = GJAudioType_AAC;
            sourceformat.mChannelsPerFrame = channel;
            sourceformat.mSampleRate = sampleRate;
            sourceformat.mFramePerPacket = 1024;
            
//            AudioStreamBasicDescription sourceformat = {0};
//            sourceformat.mFormatID = kAudioFormatMPEG4AAC;
//            sourceformat.mChannelsPerFrame = channel;
//            sourceformat.mSampleRate = sampleRate;
//            sourceformat.mFramesPerPacket = 1024;
            GJAudioFormat destformat = sourceformat;
            destformat.mBitsPerChannel = 16;
            destformat.mFramePerPacket = 1;
            
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
            livePull->audioDecoder->decodeCreate(livePull->audioDecoder,sourceformat,destformat,aacDecodeCompleteCallback,livePull);
            GJLivePlay_SetAudioFormat(livePull->player, destformat);
//            livePull.audioDecoder = [[GJPCMDecodeFromAAC alloc]initWithDestDescription:&destformat SourceDescription:&sourceformat];
//            livePull.audioDecoder.delegate = livePull;
//            [livePull.audioDecoder start];
//            livePull.player.audioFormat = destformat;
            pthread_mutex_unlock(&livePull->lock);
        }
        livePull->audioDecoder->decodePacket(livePull->audioDecoder,streamPacket.packet.aacPacket);
    }else if (streamPacket.type == GJMediaType_Video) {
        livePull->videoDecoder->decodePacket(livePull->videoDecoder,streamPacket.packet.h264Packet);
    }
}
static GVoid aacDecodeCompleteCallback(GHandle userData,R_GJPCMFrame* frame){
    GJLivePullContext* pullContext = userData;
    GJLivePlay_AddAudioData(pullContext->player, frame);
}
static GVoid h264DecodeCompleteCallback(GHandle userData,R_GJPixelFrame* frame){
    
    GJLivePullContext* pullContext = userData;
    
    if (pullContext->fristAudioClock == G_TIME_INVALID) {
        pullContext->fristAudioClock = GJ_Gettime()/1000.0;
       
        GJPullFristFrameInfo info = {0};
        info.size = CGSizeMake((float)frame->width, (float)frame->height);
//        pullContext->callback();
    }
    GJLivePlay_AddVideoData(pullContext->player, frame);
    return;
}
