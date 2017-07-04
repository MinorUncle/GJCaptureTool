
//
//  IOS_AACDecode.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_AACDecode.h"
#import <Foundation/Foundation.h>
#import "GJPCMDecodeFromAAC.h"
#import "GJLog.h"
#import "GJLiveDefine+internal.h"
inline static GBool decodeSetup (struct _GJAACDecodeContext* context,GJAudioFormat sourceFormat,GJAudioFormat destForamt,AudioFrameOutCallback callback,GHandle userData){
    pthread_mutex_lock(&context->lock);
    GJAssert(context->obaque == GNULL, "上一个音频解码器没有释放");
    if (sourceFormat.mType != GJAudioType_AAC) {
        GJLOG(GJ_LOGERROR, "解码音频源格式不支持");
        return GFalse;
    }
    if (destForamt.mType != GJAudioType_PCM) {
        GJLOG(GJ_LOGERROR, "解码目标音频格式不支持");
        return GFalse;
    }
    if (callback == GNULL) {
        GJLOG(GJ_LOGERROR, "回调函数不能为空");
        return GFalse;
    }
    AudioStreamBasicDescription s = {0};
    s.mBitsPerChannel = sourceFormat.mBitsPerChannel;
    s.mFramesPerPacket = sourceFormat.mFramePerPacket;
    s.mSampleRate = sourceFormat.mSampleRate;
    s.mFormatID = kAudioFormatMPEG4AAC;
    s.mChannelsPerFrame = sourceFormat.mChannelsPerFrame;
    
    AudioStreamBasicDescription d = s;
    d.mChannelsPerFrame = destForamt.mChannelsPerFrame;
    d.mSampleRate = destForamt.mSampleRate;
    d.mFormatID = kAudioFormatLinearPCM; //PCM
    d.mBitsPerChannel = destForamt.mBitsPerChannel;
    d.mBytesPerPacket = d.mBytesPerFrame =d.mChannelsPerFrame *  d.mBitsPerChannel;
    d.mFramesPerPacket = 1;
    d.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
    GJPCMDecodeFromAAC* decode = [[GJPCMDecodeFromAAC alloc]initWithDestDescription:d SourceDescription:s];
    context->decodeeCompleteCallback = callback;
    decode.decodeCallback = ^(R_GJPCMFrame *frame){
        callback(userData,frame);
    };
    context->obaque = (__bridge_retained GHandle)decode;
    [decode start];
    GJLOG(GJ_LOGDEBUG, "aac decode decodeSetup:%p",decode);
    pthread_mutex_unlock(&context->lock);
    return GTrue;
}
inline static GVoid decodeUnSetup (struct _GJAACDecodeContext* context){
    pthread_mutex_lock(&context->lock);
    if(context->obaque){
        GJPCMDecodeFromAAC* decode = (__bridge_transfer GJPCMDecodeFromAAC *)(context->obaque);
        [decode stop];
        context->obaque = GNULL;
        GJLOG(GJ_LOGDEBUG, "aac decode unSetup:%p",decode);
        decode = nil;
    }
    pthread_mutex_unlock(&context->lock);
}
inline static GBool decodePacket (struct _GJAACDecodeContext* context,R_GJAACPacket* packet){
    pthread_mutex_lock(&context->lock);
    GJPCMDecodeFromAAC* decode = (__bridge GJPCMDecodeFromAAC *)(context->obaque);
    [decode decodePacket:packet];
    pthread_mutex_unlock(&context->lock);
    return GTrue;
}

GVoid GJ_AACDecodeContextCreate(GJAACDecodeContext** decodeContext){
    if (*decodeContext == NULL) {
        *decodeContext = (GJAACDecodeContext*)malloc(sizeof(GJAACDecodeContext));
    }
    GJAACDecodeContext* context = *decodeContext;
    pthread_mutex_init(&context->lock, GNULL);
    context->decodeSetup = decodeSetup;
    context->decodeUnSetup = decodeUnSetup;
    context->decodePacket = decodePacket;
    context->decodeeCompleteCallback = NULL;
}
GVoid GJ_AACDecodeContextDealloc(GJAACDecodeContext** context){
    if ((*context)->obaque) {
        GJLOG(GJ_LOGWARNING, "decodeUnSetup 没有调用，自动调用");
        (*context)->decodeUnSetup(*context);
        
    }
    //pthread_mutex_destroy(&(*context)->lock);
    free(*context);
    *context = GNULL;
}

