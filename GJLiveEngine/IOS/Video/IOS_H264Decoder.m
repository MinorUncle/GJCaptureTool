//
//  IOS_H264Decoder.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_H264Decoder.h"
#import "GJH264Decoder.h"
#import "GJBufferPool.h"
static GBool cvImagereleaseCallBack(GJRetainBuffer * retain){
    CVImageBufferRef image = (CVImageBufferRef)retain->data;
    CVPixelBufferRelease(image);
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)retain);
    return GTrue;
}
static GBool decodeSetup (struct _GJH264DecodeContext* context,GJPixelType format,H264DecodeCompleteCallback callback,GHandle userData)
{
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
static GVoid decodeRelease (struct _GJH264DecodeContext* context){
    GJH264Decoder* decode = (__bridge_transfer GJH264Decoder *)(context->obaque);
    decode = nil;
}
static GBool decodePacket (struct _GJH264DecodeContext* context,R_GJH264Packet* packet){
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
    context->decodeRelease = decodeRelease;
    context->decodePacket = decodePacket;
    context->decodeeCompleteCallback = NULL;
}
