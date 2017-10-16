//
//  IOS_AACEncoder.c
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_AACEncode.h"
#import "AACEncoderFromPCM.h"
#import "GJLog.h"
GBool encodeSetup(struct _GJEncodeToAACContext *context, GJAudioFormat sourceFormat, GJAudioStreamFormat destForamt, AACPacketOutCallback callback, GHandle userData) {
    GJAssert(context->obaque == GNULL, "上一个音频解码器没有释放");
    if (sourceFormat.mType != GJAudioType_PCM) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "编码音频源格式不支持");
        return GFalse;
    }
    if (destForamt.format.mType != GJAudioType_AAC) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "编码目标音频格式不支持");
        return GFalse;
    }
    if (callback == GNULL) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "回调函数不能为空");
        return GFalse;
    }
    context->encodeCompleteCallback  = callback;
    AudioStreamBasicDescription dest = {0};
    dest.mFramesPerPacket            = destForamt.format.mFramePerPacket;
    dest.mSampleRate                 = destForamt.format.mSampleRate;
    dest.mFormatID                   = kAudioFormatMPEG4AAC;
    dest.mChannelsPerFrame           = destForamt.format.mChannelsPerFrame;

    AudioStreamBasicDescription source = dest;
    source.mChannelsPerFrame           = sourceFormat.mChannelsPerFrame;
    source.mSampleRate                 = sourceFormat.mSampleRate;
    source.mFormatID                   = kAudioFormatLinearPCM; //PCM
    source.mBitsPerChannel             = sourceFormat.mBitsPerChannel;
    source.mBytesPerPacket = source.mBytesPerFrame = source.mChannelsPerFrame * source.mBitsPerChannel;
    source.mFramesPerPacket                        = sourceFormat.mFramePerPacket;
    source.mFormatFlags                            = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
    AACEncoderFromPCM *encoder                     = [[AACEncoderFromPCM alloc] initWithSourceForamt:&source DestDescription:&dest bitrate:destForamt.bitrate];
    [encoder start];
    encoder.completeCallback = ^(R_GJPacket *packet) {
        callback(userData, packet);
    };
    context->obaque = (__bridge_retained GHandle)(encoder);
    return GTrue;
}
GVoid encodeUnSetup(struct _GJEncodeToAACContext *context) {
    if (context->obaque) {
        AACEncoderFromPCM *encode = (__bridge_transfer AACEncoderFromPCM *) (context->obaque);
        [encode stop];
        context->obaque = GNULL;
    }
}
GVoid encodeFrame(struct _GJEncodeToAACContext *context, R_GJPCMFrame *frame) {
    AACEncoderFromPCM *encode = (__bridge AACEncoderFromPCM *) (context->obaque);
    [encode encodeWithPacket:frame];
}
GBool encodeSetBitrate(struct _GJEncodeToAACContext *context, GInt32 bitrate) {
    AACEncoderFromPCM *encode = (__bridge AACEncoderFromPCM *) (context->obaque);
    encode.bitrate            = bitrate;
    return encode.bitrate == bitrate;
}
GVoid encodeFlush(struct _GJEncodeToAACContext *context) {
    //    AACEncoderFromPCM* encode = (__bridge AACEncoderFromPCM *)(context->obaque);
}
GVoid GJ_AACEncodeContextCreate(GJEncodeToAACContext **encodeContext) {
    if (*encodeContext == NULL) {
        *encodeContext = (GJEncodeToAACContext *) malloc(sizeof(GJEncodeToAACContext));
    }
    GJEncodeToAACContext *context   = *encodeContext;
    context->encodeSetup            = encodeSetup;
    context->encodeUnSetup          = encodeUnSetup;
    context->encodeFrame            = encodeFrame;
    context->encodeFlush            = encodeFlush;
    context->encodeCompleteCallback = NULL;
}

GVoid GJ_AACEncodeContextDealloc(GJEncodeToAACContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->encodeUnSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
