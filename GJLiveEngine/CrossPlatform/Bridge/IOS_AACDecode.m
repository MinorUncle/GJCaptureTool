
//
//  IOS_AACDecode.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_AACDecode.h"
#import "GJLiveDefine+internal.h"
#import "GJLog.h"
#import "GJPCMDecodeFromAAC.h"
#import <Foundation/Foundation.h>
inline static GBool decodeSetup(struct _GJAACDecodeContext *context, GJAudioFormat sourceFormat, GJAudioFormat destForamt, AudioFrameOutCallback callback, GHandle userData) {
    pipleNodeLock(&context->pipleNode);
    GJAssert(context->obaque == GNULL, "上一个音频解码器没有释放");
    if (sourceFormat.mType != GJAudioType_AAC) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "解码音频源格式不支持");
        return GFalse;
    }
    if (destForamt.mType != GJAudioType_PCM) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "解码目标音频格式不支持");
        return GFalse;
    }

    AudioStreamBasicDescription s = {0};
    s.mBitsPerChannel             = sourceFormat.mBitsPerChannel;
    s.mFramesPerPacket            = sourceFormat.mFramePerPacket;
    s.mSampleRate                 = sourceFormat.mSampleRate;
    s.mFormatID                   = kAudioFormatMPEG4AAC;
    s.mChannelsPerFrame           = sourceFormat.mChannelsPerFrame;

    AudioStreamBasicDescription d = s;
    d.mChannelsPerFrame           = destForamt.mChannelsPerFrame;
    d.mSampleRate                 = destForamt.mSampleRate;
    d.mFormatID                   = kAudioFormatLinearPCM; //PCM
    d.mBitsPerChannel             = destForamt.mBitsPerChannel;
    d.mBytesPerPacket = d.mBytesPerFrame = d.mChannelsPerFrame * d.mBitsPerChannel;
    d.mFramesPerPacket                   = 1;
    d.mFormatFlags                       = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
    GJPCMDecodeFromAAC *decode           = [[GJPCMDecodeFromAAC alloc] initWithDestDescription:d SourceDescription:s];
    NodeFlowDataFunc callFunc = pipleNodeFlowFunc(&context->pipleNode);
    decode.decodeCallback                = ^(R_GJPCMFrame *frame) {
        if (callback) {
            callback(userData, frame);
        }
        callFunc(&context->pipleNode,&frame->retain,GJMediaType_Audio);
    };
    context->obaque = (__bridge_retained GHandle) decode;
    [decode start];
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "aac decode decodeSetup:%p", decode);
    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
}
inline static GVoid decodeUnSetup(struct _GJAACDecodeContext *context) {
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        GJPCMDecodeFromAAC *decode = (__bridge_transfer GJPCMDecodeFromAAC *) (context->obaque);
        [decode stop];
        context->obaque = GNULL;
        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "aac decode unSetup:%p", decode);
        decode = nil;
    }
    pipleNodeUnLock(&context->pipleNode);
}
inline static GBool decodePacket(struct _GJAACDecodeContext *context, R_GJPacket *packet) {
    pipleNodeLock(&context->pipleNode);
    GJPCMDecodeFromAAC *decode = (__bridge GJPCMDecodeFromAAC *) (context->obaque);
    [decode decodePacket:packet];
    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
}
inline static GBool decodePacketFunc(GJPipleNode* context, GJRetainBuffer* data,GJMediaType dataType){
    
    pipleNodeLock(context);
    GBool result = decodePacket((GJAACDecodeContext*)context,(R_GJPacket*)data);
    pipleNodeUnLock(context);
    return  result;
}

GVoid GJ_AACDecodeContextCreate(GJAACDecodeContext **decodeContext) {
    if (*decodeContext == NULL) {
        *decodeContext = (GJAACDecodeContext *) malloc(sizeof(GJAACDecodeContext));
    }
    GJAACDecodeContext *context = *decodeContext;
    memset(context, 0, sizeof(GJAACDecodeContext));
    pipleNodeInit(&context->pipleNode,decodePacketFunc);

    context->decodeSetup             = decodeSetup;
    context->decodeUnSetup           = decodeUnSetup;
    context->decodePacket            = GNULL;
}
GVoid GJ_AACDecodeContextDealloc(GJAACDecodeContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "decodeUnSetup 没有调用，自动调用");
        (*context)->decodeUnSetup(*context);
    }
    pipleNodeUnInit(&(*context)->pipleNode);
    free(*context);
    *context = GNULL;
}
