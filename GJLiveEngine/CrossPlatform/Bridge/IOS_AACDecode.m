
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
inline static GBool decodeSetup(struct _FFAudioDecodeContext *context, GJAudioFormat destForamt, AudioFrameOutCallback callback, GHandle userData) {
    pipleNodeLock(&context->pipleNode);
    GJAssert(context->obaque == GNULL, "上一个音频解码器没有释放");

    GJPCMDecodeFromAAC *decode           = [[GJPCMDecodeFromAAC alloc] init];
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
inline static GVoid decodeUnSetup(struct _FFAudioDecodeContext *context) {
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
inline static GBool decodePacket(struct _FFAudioDecodeContext *context, R_GJPacket *packet) {
//    pipleNodeLock(&context->pipleNode);
    GJPCMDecodeFromAAC *decode = (__bridge GJPCMDecodeFromAAC *) (context->obaque);
    [decode decodePacket:packet];
//    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
}
GJAudioFormat decodeGetDestFormat(struct _FFAudioDecodeContext *context) {
    GJPCMDecodeFromAAC *decode = (__bridge GJPCMDecodeFromAAC *) (context->obaque);
    AudioStreamBasicDescription dest = decode.destFormat;
    GJAudioFormat format = {0};
    format.mBitsPerChannel = dest.mBitsPerChannel;
    format.mChannelsPerFrame = dest.mChannelsPerFrame;
    format.mType      = GJAudioType_PCM;
    format.mFramePerPacket  = dest.mFramesPerPacket;
    format.mSampleRate = dest.mSampleRate;
    format.mFormatFlags = dest.mFormatFlags;
    return format;
}
inline static GBool decodePacketFunc(GJPipleNode* context, GJRetainBuffer* data,GJMediaType dataType){
    GBool result = GFalse;
    if (dataType == GJMediaType_Audio) {
        result = decodePacket((FFAudioDecodeContext*)context,(R_GJPacket*)data);
    }
    return  result;
}

GVoid GJ_AACDecodeContextCreate(FFAudioDecodeContext **decodeContext) {
    if (*decodeContext == NULL) {
        *decodeContext = (FFAudioDecodeContext *) malloc(sizeof(FFAudioDecodeContext));
    }
    FFAudioDecodeContext *context = *decodeContext;
    memset(context, 0, sizeof(FFAudioDecodeContext));
    pipleNodeInit(&context->pipleNode,decodePacketFunc);

    context->decodeSetup             = decodeSetup;
    context->decodeUnSetup           = decodeUnSetup;
    context->decodeGetDestFormat    = decodeGetDestFormat;
    context->decodePacket            = GNULL;
}
GVoid GJ_AACDecodeContextDealloc(FFAudioDecodeContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "decodeUnSetup 没有调用，自动调用");
        (*context)->decodeUnSetup(*context);
    }
    pipleNodeUnInit(&(*context)->pipleNode);
    free(*context);
    *context = GNULL;
}
