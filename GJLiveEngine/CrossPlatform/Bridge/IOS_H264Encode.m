//
//  IOS_H264Encoder.c
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_H264Encode.h"
#import "GJLog.h"
#import "GJH264Encoder.h"
#import <stdlib.h>
inline static GBool encodeSetup (struct _GJEncodeToH264eContext* context,GJPixelFormat format,H264PacketOutCallback callback,GHandle userData){
    GJAssert(context->obaque == GNULL, "上一个视频解码器没有释放");
    GJH264Encoder* encoder = [[GJH264Encoder alloc]initWithSourceSize:CGSizeMake((CGFloat)format.mWidth, (CGFloat)format.mHeight)];
    GJLOG(GJ_LOGINFO, "GJH264Encoder setup:%p",encoder);
    encoder.completeCallback = ^(R_GJPacket *packet) {
        callback(userData,packet);
    };
    context->obaque = (__bridge_retained GHandle)encoder;
    return GTrue;
}
inline static GVoid encodeUnSetup (GJEncodeToH264eContext* context){
    if (context->obaque) {
        GJH264Encoder* encode = (__bridge_transfer GJH264Encoder *)(context->obaque);
        GJLOG(GJ_LOGINFO, "GJH264Encoder unsetup:%p",encode);
        context->obaque = GNULL;
        encode = nil;
    }
}
inline static GBool encodeFrame (GJEncodeToH264eContext* context,R_GJPixelFrame* frame){
    GJH264Encoder* encode = (__bridge GJH264Encoder *)(context->obaque);
    CVImageBufferRef image = (CVImageBufferRef)frame->retain.data;
    return [encode encodeImageBuffer:image pts:frame->pts];
}
inline static GBool encodeSetBitrate (GJEncodeToH264eContext* context,GInt32 bitrate){
    GJH264Encoder* encode = (__bridge GJH264Encoder *)(context->obaque);
    encode.bitrate = bitrate;
    return encode.bitrate == bitrate;
}
inline static GBool encodeSetProfile (GJEncodeToH264eContext* context,ProfileLevel profile){
    GJH264Encoder* encode = (__bridge GJH264Encoder *)(context->obaque);
    encode.profileLevel = profile;
    return encode.profileLevel == profile;
}
inline static GBool encodeSetEntropy (GJEncodeToH264eContext* context,EntropyMode model){
    GJH264Encoder* encode = (__bridge GJH264Encoder *)(context->obaque);
    encode.entropyMode = model;
    return encode.entropyMode = model;
}
inline static GBool encodeSetGop (GJEncodeToH264eContext* context,GInt32 gop){
    GJH264Encoder* encode = (__bridge GJH264Encoder *)(context->obaque);
    encode.gop = gop;
    return encode.gop = gop;
}
inline static GBool encodeAllowBFrame (GJEncodeToH264eContext* context,GBool allowBframe){
    GJH264Encoder* encode = (__bridge GJH264Encoder *)(context->obaque);
    encode.allowBFrame = allowBframe;
    return encode.allowBFrame == allowBframe;
}
inline static GVoid encodeFlush (GJEncodeToH264eContext* context){
    GJH264Encoder* encode = (__bridge GJH264Encoder *)(context->obaque);
    [encode flush];
}
inline static GBool encodeGetSPS_PPS(struct _GJEncodeToH264eContext* context,GUInt8* sps,GInt32* spsSize,GUInt8* pps,GInt32* ppsSize){
    GJH264Encoder* encode = (__bridge GJH264Encoder *)(context->obaque);
    GBool result = GFalse;
    if (sps == GNULL || *spsSize < (GInt32)encode.sps.length) {
        result = GFalse;
    }else{
        memcpy(sps, encode.sps.bytes, encode.sps.length);
        result = GTrue;
    }
    if (pps == GNULL || *ppsSize < (GInt32)encode.pps.length) {
        result = GFalse;
    }else{
        memcpy(pps, encode.pps.bytes, encode.pps.length);
        result = GTrue;
    }
    if (spsSize != GNULL) {
        *spsSize = (GInt32)encode.sps.length;
        result = GTrue;
    }
    if (ppsSize != GNULL) {
        *ppsSize = (GInt32)encode.pps.length;
        result = GTrue;
    }

    return result;
}

GVoid GJ_H264EncodeContextCreate(GJEncodeToH264eContext** encodeContext){
    if (*encodeContext == NULL) {
        *encodeContext = (GJEncodeToH264eContext*)malloc(sizeof(GJEncodeToH264eContext));
    }
    GJEncodeToH264eContext* context = *encodeContext;
    context->encodeSetup = encodeSetup;
    context->encodeUnSetup = encodeUnSetup;
    context->encodeFrame = encodeFrame;
    context->encodeSetBitrate = encodeSetBitrate;
    context->encodeSetProfile = encodeSetProfile;
    context->encodeSetEntropy = encodeSetEntropy;
    context->encodeSetGop = encodeSetGop;
    context->encodeAllowBFrame = encodeAllowBFrame;
    context->encodeGetSPS_PPS = encodeGetSPS_PPS;
    context->encodeFlush = encodeFlush;
    context->encodeCompleteCallback = NULL;
}
GVoid GJ_H264EncodeContextDealloc(GJEncodeToH264eContext** context){
    if ((*context)->obaque) {
        GJLOG(GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->encodeUnSetup(*context);
        
    }
    free(*context);
    *context = GNULL;
}
