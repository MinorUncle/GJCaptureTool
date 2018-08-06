//
//  FFVideoEncoder.c
//  GJLiveEngine
//
//  Created by 未成年大叔 on 2018/7/7.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#include "FFVideoEncoder.h"
#import "libavformat/avformat.h"
#import "libswscale/swscale.h"
#import "libavcodec/videotoolbox.h"
#import <CoreVideo/CVPixelBuffer.h>
#import "GJLog.h"
#import <stdlib.h>
typedef struct _FFEncoder {
    GJPixelType           pixelFormat;
    AVCodec *             codec;
    AVCodecContext *      codecContext;
    GHandle               videoDecodeQueue;
    GHandle               userData;
    GJQueue *             cacheQueue;
    AVRational            timebase;
    GLong                 bitrate;
    GLong                 gop;
    AVFrame*              (*buildFrame)(CVPixelBufferRef image);
}FFEncoder;
//AVFrame* buildYUV420Frame(CVPixelBufferRef image){}
AVFrame* buildRGBFrame(CVPixelBufferRef image){
    return GNULL;
}

inline static GBool ffEncodeSetup(struct _GJEncodeToH264eContext *context, GJPixelFormat format, H264PacketOutCallback callback, GHandle userData) {
    av_register_all();

    GJAssert(context->obaque == GNULL, "上一个视频解码器没有释放");
    FFEncoder* encoder = (FFEncoder*)malloc(sizeof(FFEncoder));
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "%p", encoder);
    encoder->codec = avcodec_find_encoder(AV_CODEC_ID_H264);
    AVCodecContext* codecContext = avcodec_alloc_context3(encoder->codec);
    codecContext->width = format.mWidth;
    codecContext->height = format.mHeight;
    encoder->codecContext = codecContext;
    encoder->codecContext->time_base = av_make_q(1,1000);
    switch (format.mType) {
        case GJPixelType_32BGRA:
            codecContext->pix_fmt = AV_PIX_FMT_BGRA;
            encoder->buildFrame = buildRGBFrame;
            break;
        default:
            GJAssert(0, "暂时不支持其他");
            break;
    }
    GInt ret = avcodec_open2(codecContext, encoder->codec, GNULL);
    NodeFlowDataFunc callFunc = pipleNodeFlowFunc(&context->pipleNode);
//    encoder.completeCallback  = ^(R_GJPacket *packet) {
//        if (callback) {
//            callback(userData, packet);
//        }
//        callFunc(&context->pipleNode, &packet->retain, GJMediaType_Video);
//    };
    context->obaque = encoder;
    return GTrue;
}

inline static GVoid ffEncodeUnSetup(GJEncodeToH264eContext *context) {
    if (context->obaque) {
        FFEncoder *encode = (FFEncoder*) (context->obaque);
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "%p", encode);
        free(encode);
        context->obaque = GNULL;
    }
}

inline static GBool ffEncodeFrame(GJEncodeToH264eContext *context, R_GJPixelFrame *frame) {
    FFEncoder *encoder = (FFEncoder *) (context->obaque);
    GJAssert((frame->flag & kGJFrameFlag_P_CVPixelBuffer) == kGJFrameFlag_P_CVPixelBuffer, "格式暂时不支持");
    CVPixelBufferRef image = ((CVPixelBufferRef *) R_BufferStart(&frame->retain))[0];
    return GTrue;
}

inline static GBool ffEncodeSetBitrate(GJEncodeToH264eContext *context, GInt32 bitrate) {
    FFEncoder *encoder = (FFEncoder *) (context->obaque);
    encoder->codecContext->bit_rate = bitrate;
    return GTrue;
}

inline static GBool ffEncodeSetProfile(GJEncodeToH264eContext *context, ProfileLevel profile) {
    FFEncoder *encoder = (FFEncoder *) (context->obaque);
    encoder->codecContext->profile = profile;
    return GTrue;
}

inline static GBool ffEncodeSetEntropy(GJEncodeToH264eContext *context, EntropyMode model) {
    FFEncoder *encoder = (FFEncoder *) (context->obaque);
    return GTrue;
}

inline static GBool ffEncodeSetGop(GJEncodeToH264eContext *context, GInt32 gop) {
    FFEncoder *encoder = (FFEncoder *) (context->obaque);
    encoder->codecContext->gop_size = gop;
    return GTrue;
}

inline static GBool ffEncodeAllowBFrame(GJEncodeToH264eContext *context, GBool allowBframe) {
    FFEncoder *encoder = (FFEncoder *) (context->obaque);
    return GTrue;
}

inline static GVoid ffEncodeFlush(GJEncodeToH264eContext *context) {
    FFEncoder *encoder = (FFEncoder *) (context->obaque);
}

inline static GBool ffEncodeGetSPS_PPS(struct _GJEncodeToH264eContext *context, GUInt8 *sps, GInt32 *spsSize, GUInt8 *pps, GInt32 *ppsSize) {
    FFEncoder *encoder = (FFEncoder *) (context->obaque);
    GBool          result = GFalse;
//    if (sps == GNULL || *spsSize < (GInt32) encode.sps.length) {
//        result = GFalse;
//    } else {
//        memcpy(sps, encode.sps.bytes, encode.sps.length);
//        result = GTrue;
//    }
//    if (pps == GNULL || *ppsSize < (GInt32) encode.pps.length) {
//        result = GFalse;
//    } else {
//        memcpy(pps, encode.pps.bytes, encode.pps.length);
//        result = GTrue;
//    }
//    if (spsSize != GNULL) {
//        *spsSize = (GInt32) encode.sps.length;
//        result   = GTrue;
//    }
//    if (ppsSize != GNULL) {
//        *ppsSize = (GInt32) encode.pps.length;
//        result   = GTrue;
//    }
    
    return result;
}

inline static GBool encodeFrameFunc(GJPipleNode *context, GJRetainBuffer *data, GJMediaType dataType) {
    ffEncodeFrame((GJEncodeToH264eContext *) context, (R_GJPixelFrame *) data);
    return GTrue;
}

GVoid GJ_FFEncodeContextCreate(GJEncodeToH264eContext **encodeContext) {
    if (*encodeContext == NULL) {
        *encodeContext = (GJEncodeToH264eContext *) malloc(sizeof(GJEncodeToH264eContext));
    }
    GJEncodeToH264eContext *context = *encodeContext;
    memset(context, 0, sizeof(GJEncodeToH264eContext));
    pipleNodeInit(&context->pipleNode, encodeFrameFunc);
    context->encodeSetup            = ffEncodeSetup;
    context->encodeUnSetup          = ffEncodeUnSetup;
    context->encodeFrame            = ffEncodeFrame;
    context->encodeSetBitrate       = ffEncodeSetBitrate;
    context->encodeSetProfile       = ffEncodeSetProfile;
    context->encodeSetEntropy       = ffEncodeSetEntropy;
    context->encodeSetGop           = ffEncodeSetGop;
    context->encodeAllowBFrame      = ffEncodeAllowBFrame;
    context->encodeGetSPS_PPS       = ffEncodeGetSPS_PPS;
    context->encodeFlush            = ffEncodeFlush;
    context->encodeCompleteCallback = NULL;
}

GVoid GJ_FFEncodeContextDealloc(GJEncodeToH264eContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->encodeUnSetup(*context);
    }
    pipleNodeUnInit(&(*context)->pipleNode);
    free(*context);
    *context = GNULL;
}
