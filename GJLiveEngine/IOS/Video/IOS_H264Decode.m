//
//  IOS_H264Decoder.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_H264Decode.h"
#import "GJH264Decoder.h"
#import "GJBufferPool.h"
#import "GJLog.h"
#import <stdlib.h>
inline static GBool cvImagereleaseCallBack(GJRetainBuffer * retain){
    CVImageBufferRef image = (CVImageBufferRef)retain->data;
    CVPixelBufferRelease(image);
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)retain);
    return GTrue;
}
inline static GBool decodeSetup (struct _GJH264DecodeContext* context,GJPixelType format,VideoFrameOutCallback callback,GHandle userData)
{
    GJAssert(context->obaque == GNULL, "上一个视频解码器没有释放");
  
    GJH264Decoder* decode = [[GJH264Decoder alloc]init];
    decode.completeCallback = ^(CVImageBufferRef image, int64_t pts){
        R_GJPixelFrame* frame = (R_GJPixelFrame*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPixelFrame));
        frame->height = (GInt32)CVPixelBufferGetHeight(image);
        frame->width = (GInt32)CVPixelBufferGetWidth(image);
        frame->pts = pts;
        frame->type = CVPixelBufferGetPixelFormatType(image);
        CVPixelBufferRetain(image);
        retainBufferPack((GJRetainBuffer**)&frame, image, sizeof(image), cvImagereleaseCallBack, GNULL);
        callback(userData,frame);
        retainBufferUnRetain(&frame->retain);
    };
    context->obaque = (__bridge_retained GHandle)decode;
    return GTrue;
}
inline static GVoid decodeUnSetup (struct _GJH264DecodeContext* context){
    if (context->obaque) {
        GJH264Decoder* decode = (__bridge_transfer GJH264Decoder *)(context->obaque);
        decode = nil;
        context->obaque = GNULL;
    }
}
inline static GBool decodePacket (struct _GJH264DecodeContext* context,R_GJH264Packet* packet){
    GJH264Decoder* decode = (__bridge GJH264Decoder *)(context->obaque);
    [decode decodePacket:packet];
    
    return GTrue;
}

GVoid GJ_H264DecodeContextCreate(GJH264DecodeContext** decodeContext){
    if (*decodeContext == NULL) {
        *decodeContext = (GJH264DecodeContext*)malloc(sizeof(GJH264DecodeContext));
    }
    GJH264DecodeContext* context = *decodeContext;
    context->decodeSetup = decodeSetup;
    context->decodeUnSetup = decodeUnSetup;
    context->decodePacket = decodePacket;
    context->decodeeCompleteCallback = NULL;
}
GVoid GJ_H264DecodeContextDealloc(GJH264DecodeContext** context){
    if ((*context)->obaque) {
        GJLOG(GJ_LOGWARNING, "decodeUnSetup 没有调用，自动调用");
        (*context)->decodeUnSetup(*context);
        
    }
    free(*context);
    *context = GNULL;
}
