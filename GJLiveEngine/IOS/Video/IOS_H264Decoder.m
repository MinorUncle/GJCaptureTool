//
//  IOS_H264Decoder.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_H264Decoder.h"
#import "GJH264Decoder.h"

GBool decodeCreate (struct _GJH264DecodeContext* context,GJPixelFormat format){
    context->obaque = (__bridge_retained GHandle)[[GJH264Decoder alloc]init];
    return GTrue;
}
GVoid decodeRelease (struct _GJH264DecodeContext* context){
    GJH264Decoder* decode = (__bridge_transfer GJH264Decoder *)(context->obaque);
    decode = nil;
}
GBool decodePacket (struct _GJH264DecodeContext* context,R_GJH264Packet* packet){
    GJH264Decoder* decode = (__bridge_transfer GJH264Decoder *)(context->obaque);
    [decode decodePacket:packet];
    return GTrue;
}

GVoid GJ_H264DecodeContextSetup(GJH264DecodeContext* context){
    if (context == NULL) {
        context = (GJH264DecodeContext*)malloc(sizeof(GJH264DecodeContext));
    }
    context->decodeCreate = decodeCreate;
    context->decodeRelease = decodeRelease;
    context->decodePacket = decodePacket;
    context->decodeComplete = NULL;
}
