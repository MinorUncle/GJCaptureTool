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
GBool encodeSetup(struct _GJEncodeToAACContext* context,GJAudioFormat sourceFormat,GJAudioFormat destForamt,AACPacketOutCallback callback,GHandle userData){
    GJAssert(context->obaque == GNULL, "上一个音频解码器没有释放");
    if (sourceFormat.mType != GJAudioType_PCM) {
        GJLOG(GJ_LOGERROR, "解码音频源格式不支持");
        return GFalse;
    }
    if (destForamt.mType != GJAudioType_AAC) {
        GJLOG(GJ_LOGERROR, "解码目标音频格式不支持");
        return GFalse;
    }
    if (callback == GNULL) {
        GJLOG(GJ_LOGERROR, "回调函数不能为空");
        return GFalse;
    }
    context->encodeCompleteCallback = callback;
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
    AACEncoderFromPCM* encoder = [[AACEncoderFromPCM alloc]initWithSourceForamt:&s DestDescription:&d];
    [encoder start];
    encoder.completeCallback = ^(R_GJAACPacket *packet) {
        callback(userData,packet);
    };
    context->obaque = (__bridge_retained GHandle)(encoder);
    return GTrue;
}
GVoid encodeUnSetup(struct _GJEncodeToAACContext* context){
    if(context->obaque){
        AACEncoderFromPCM* encode = (__bridge_transfer AACEncoderFromPCM *)(context->obaque);
        [encode stop];
        context->obaque = GNULL;
    }
}
GVoid encodeFrame(struct _GJEncodeToAACContext* context,R_GJPCMFrame* frame){
    AACEncoderFromPCM* encode = (__bridge_transfer AACEncoderFromPCM *)(context->obaque);
    [encode encodeWithPacket:frame];
}
GBool encodeSetBitrate(struct _GJEncodeToAACContext* context,GInt32 bitrate){
    return GTrue;
}

GVoid GJ_AACEncodeContextCreate(GJEncodeToAACContext** encodeContext){
    if (*encodeContext == NULL) {
        *encodeContext = (GJEncodeToAACContext*)malloc(sizeof(GJEncodeToAACContext));
    }
    GJEncodeToAACContext* context = *encodeContext;
    context->encodeSetup = encodeSetup;
    context->encodeUnSetup = encodeUnSetup;
    context->encodeFrame = encodeFrame;
    context->encodeCompleteCallback = NULL;

}

GVoid GJ_AACEncodeContextDealloc(GJEncodeToAACContext** context){
    if ((*context)->obaque) {
        GJLOG(GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->encodeUnSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
