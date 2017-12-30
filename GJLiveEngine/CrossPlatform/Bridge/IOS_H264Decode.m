//
//  IOS_H264Decoder.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_H264Decode.h"
#import "GJBufferPool.h"
#import "GJH264Decoder.h"
#import "GJLog.h"
#import <stdlib.h>

inline static GBool decodeSetup(struct _GJH264DecodeContext *context, GJPixelType format, VideoFrameOutCallback callback, GHandle userData) {
    pipleNodeLock(&context->pipleNode);
    GJAssert(context->obaque == GNULL, "上一个视频解码器没有释放");
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder setup");

    GJH264Decoder *decode   = [[GJH264Decoder alloc] init];
    NodeFlowDataFunc callFunc = pipleNodeFlowFunc(&context->pipleNode);
    decode.completeCallback = ^(R_GJPixelFrame *frame) {
        if (callback) {
            callback(userData, frame);
        }
        callFunc(&context->pipleNode,&frame->retain,GJMediaType_Video);
    };
    context->obaque = (__bridge_retained GHandle) decode;
    pipleNodeUnLock(&context->pipleNode);

    return GTrue;
}
inline static GVoid decodeUnSetup(struct _GJH264DecodeContext *context) {
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        GJH264Decoder *decode = (__bridge_transfer GJH264Decoder *) (context->obaque);
        context->obaque       = GNULL;
        decode                = nil;
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder unsetup");
    }
    pipleNodeUnLock(&context->pipleNode);

}
inline static GBool decodePacket(struct _GJH264DecodeContext *context, R_GJPacket *packet) {
    pipleNodeLock(&context->pipleNode);
    GJH264Decoder *decode = (__bridge GJH264Decoder *) (context->obaque);
    [decode decodePacket:packet];
    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
}

inline static GBool decodePacketFunc(GJPipleNode* context, GJRetainBuffer* data,GJMediaType dataType){
    pipleNodeLock(context);
    GBool result = decodePacket((GJH264DecodeContext*)context,(R_GJPacket*)data);
    pipleNodeUnLock(context);
    return  result;
}

GVoid GJ_H264DecodeContextCreate(GJH264DecodeContext **decodeContext) {
    if (*decodeContext == NULL) {
        *decodeContext = (GJH264DecodeContext *) malloc(sizeof(GJH264DecodeContext));
    }
    GJH264DecodeContext *context     = *decodeContext;
    memset(context, 0, sizeof(GJH264DecodeContext));
    pipleNodeInit(&context->pipleNode, decodePacketFunc);
    context->decodeSetup             = decodeSetup;
    context->decodeUnSetup           = decodeUnSetup;
    context->decodePacket            = GNULL;
}
GVoid GJ_H264DecodeContextDealloc(GJH264DecodeContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "decodeUnSetup 没有调用，自动调用");
        (*context)->decodeUnSetup(*context);
    }
    pipleNodeUnInit(&(*context)->pipleNode);
    free(*context);
    *context = GNULL;
}
