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
    pipleNodeLock(&context->pipleNode);
    GJAssert(context->obaque == GNULL, "上一个音频解码器没有释放");
    if (sourceFormat.mType != GJAudioType_PCM) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "编码音频源格式不支持");
        return GFalse;
    }
    if (destForamt.format.mType != GJAudioType_AAC) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "编码目标音频格式不支持");
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
    NodeFlowDataFunc callFunc = pipleNodeFlowFunc(&context->pipleNode);
    encoder.completeCallback = ^(R_GJPacket *packet) {
        if (callback) {
            callback(userData, packet);
        }
        callFunc(&context->pipleNode,&packet->retain,GJMediaType_Audio);
    };
    context->obaque = (__bridge_retained GHandle)(encoder);
    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
}
GVoid encodeUnSetup(struct _GJEncodeToAACContext *context) {
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        AACEncoderFromPCM *encode = (__bridge_transfer AACEncoderFromPCM *) (context->obaque);
        [encode stop];
        context->obaque = GNULL;
    }
    pipleNodeUnLock(&context->pipleNode);
}
GVoid encodeFrame(struct _GJEncodeToAACContext *context, R_GJPCMFrame *frame) {
    pipleNodeLock(&context->pipleNode);
    AACEncoderFromPCM *encode = (__bridge AACEncoderFromPCM *) (context->obaque);
    [encode encodeWithPacket:frame];
    pipleNodeUnLock(&context->pipleNode);
}
GBool encodeSetBitrate(struct _GJEncodeToAACContext *context, GInt32 bitrate) {
    AACEncoderFromPCM *encode = (__bridge AACEncoderFromPCM *) (context->obaque);
    encode.bitrate            = bitrate;
    return encode.bitrate == bitrate;
}
GVoid encodeFlush(struct _GJEncodeToAACContext *context) {
    //    AACEncoderFromPCM* encode = (__bridge AACEncoderFromPCM *)(context->obaque);
}

inline static GBool encodeFrameFunc(GJPipleNode* context, GJRetainBuffer* data,GJMediaType dataType){
    pipleNodeLock(context);
    encodeFrame((GJEncodeToAACContext*)context,(R_GJPCMFrame*)data);
    pipleNodeUnLock(context);
    return  GTrue;
}


GVoid GJ_AACEncodeContextCreate(GJEncodeToAACContext **encodeContext) {
    if (*encodeContext == NULL) {
        *encodeContext = (GJEncodeToAACContext *) malloc(sizeof(GJEncodeToAACContext));
    }
    GJEncodeToAACContext *context   = *encodeContext;
    memset(context, 0, sizeof(GJEncodeToAACContext));
    pipleNodeInit(&context->pipleNode, encodeFrameFunc);
    context->encodeSetup            = encodeSetup;
    context->encodeUnSetup          = encodeUnSetup;
    context->encodeFrame            = GNULL;
    context->encodeFlush            = encodeFlush;
    context->encodeCompleteCallback = NULL;
}

GVoid GJ_AACEncodeContextDealloc(GJEncodeToAACContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->encodeUnSetup(*context);
    }
    pipleNodeUnInit(&(*context)->pipleNode);
    
    free(*context);
    *context = GNULL;
}
