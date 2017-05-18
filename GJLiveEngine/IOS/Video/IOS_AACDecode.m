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
GBool decodeCreate (struct _GJAACDecodeContext* context,GJAudioFormat sourceFormat,GJAudioFormat destForamt,DecodeCompleteCallback callback,GHandle userData){
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
    
    AudioStreamBasicDescription d = s;
    d.mChannelsPerFrame = destForamt.mChannelsPerFrame;
    d.mSampleRate = destForamt.mSampleRate;
    d.mFormatID = kAudioFormatLinearPCM; //PCM
    d.mBitsPerChannel = destForamt.mBitsPerChannel;
    d.mBytesPerPacket = d.mBytesPerFrame =d.mChannelsPerFrame *  d.mBitsPerChannel;
    d.mFramesPerPacket = 1;
    d.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
    GJPCMDecodeFromAAC* decode = [[GJPCMDecodeFromAAC alloc]initWithDestDescription:d SourceDescription:s];
    decode.decodeCallback = ^(R_GJFrame *frame){
        callback(frame,userData);
    };
    [decode start];
    context->obaque = (__bridge_retained GHandle)decode;
    return GTrue;
}
GVoid decodeRelease (struct _GJAACDecodeContext* context){
    GJPCMDecodeFromAAC* decode = (__bridge_transfer GJPCMDecodeFromAAC *)(context->obaque);
    [decode stop];
    decode = nil;
}
GBool decodePacket (struct _GJAACDecodeContext* context,R_GJAACPacket* packet){
    GJPCMDecodeFromAAC* decode = (__bridge_transfer GJPCMDecodeFromAAC *)(context->obaque);
    [decode decodePacket:packet];
    return GTrue;
}

GVoid GJ_AACDecodeContextSetup(GJAACDecodeContext* context){
    if (context == NULL) {
        context = (GJAACDecodeContext*)malloc(sizeof(GJAACDecodeContext));
    }
    context->decodeCreate = decodeCreate;
    context->decodeRelease = decodeRelease;
    context->decodePacket = decodePacket;
    context->decodeeCompleteCallback = NULL;
}
