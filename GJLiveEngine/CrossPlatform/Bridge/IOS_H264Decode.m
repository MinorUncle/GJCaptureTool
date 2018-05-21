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

inline static GBool decodeSetup(struct _FFVideoDecodeContext *context, GJPixelType format, VideoFrameOutCallback callback, GHandle userData) {
    pipleNodeLock(&context->pipleNode);
    GJAssert(context->obaque == GNULL, "上一个视频解码器没有释放");
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder setup");

    GJH264Decoder *decode   = [[GJH264Decoder alloc] init];
    switch (format) {
        case GJPixelType_32BGRA:
            decode.outPutImageFormat = kCVPixelFormatType_32BGRA;
            break;
        case GJPixelType_YpCbCr8BiPlanar:
            decode.outPutImageFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            break;
        case GJPixelType_YpCbCr8BiPlanar_Full:
            decode.outPutImageFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
            break;
        default:
            GJLOG(GNULL, GJ_LOGFORBID, "格式不支持");
            break;
    }
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
inline static GVoid decodeUnSetup(struct _FFVideoDecodeContext *context) {
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        GJH264Decoder *decode = (__bridge_transfer GJH264Decoder *) (context->obaque);
        if (decode.isRunning) {
            [decode stopDecode];
        }
        context->obaque       = GNULL;
        decode                = nil;
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder unsetup");
    }
    pipleNodeUnLock(&context->pipleNode);
}

inline static  GBool  decodeStart(struct _FFVideoDecodeContext* context){
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        GJH264Decoder *decode = (__bridge GJH264Decoder *) (context->obaque);
        [decode startDecode];
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder decodeStart");
    }
    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
};

//stop前一定要断开管道的连接。
inline static  GVoid  decodeStop(struct _FFVideoDecodeContext* context){
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        GJH264Decoder *decode = (__bridge GJH264Decoder *) (context->obaque);
        if (decode.isRunning) {
            [decode stopDecode];
        }
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder decodeStart");
    }
    pipleNodeUnLock(&context->pipleNode);
};

inline static GBool decodePacket(struct _FFVideoDecodeContext *context, R_GJPacket *packet) {
//    pipleNodeLock(&context->pipleNode);
    GJH264Decoder *decode = (__bridge GJH264Decoder *) (context->obaque);
    [decode decodePacket:packet];
//    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
}

inline static GBool decodePacketFunc(GJPipleNode* context, GJRetainBuffer* data,GJMediaType dataType){
    GBool result = GFalse;
    if (dataType == GJMediaType_Video) {
        result = decodePacket((FFVideoDecodeContext*)context,(R_GJPacket*)data);
    }
    return  result;
    
}

GVoid GJ_H264DecodeContextCreate(FFVideoDecodeContext **decodeContext) {
    if (*decodeContext == NULL) {
        *decodeContext = (FFVideoDecodeContext *) malloc(sizeof(FFVideoDecodeContext));
    }
    FFVideoDecodeContext *context     = *decodeContext;
    memset(context, 0, sizeof(FFVideoDecodeContext));
    pipleNodeInit(&context->pipleNode, decodePacketFunc);
    context->decodeSetup             = decodeSetup;
    context->decodeUnSetup           = decodeUnSetup;
    context->decodeStart             = decodeStart;
    context->decodeStop              = decodeStop;
    context->decodePacket            = GNULL;
}
GVoid GJ_H264DecodeContextDealloc(FFVideoDecodeContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "decodeUnSetup 没有调用，自动调用");
        (*context)->decodeUnSetup(*context);
    }
    pipleNodeUnInit(&(*context)->pipleNode);
    free(*context);
    *context = GNULL;
}
