//
//  IOS_AACDecode.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_AACDecode.h"
#import <Foundation/Foundation.h>
#import "GJPCMDecodeFromAAC.h"

GBool decodeCreate (struct _GJAACDecodeContext* context,GJPixelFormat format){
    context->obaque = (__bridge_retained GHandle)[[GJPCMDecodeFromAAC alloc]init];
    return GTrue;
}
GVoid decodeRelease (struct _GJAACDecodeContext* context){
    GJPCMDecodeFromAAC* decode = (__bridge_transfer GJPCMDecodeFromAAC *)(context->obaque);
    decode = nil;
}
GBool decodePacket (struct _GJAACDecodeContext* context,R_GJAACPacket* packet){
    GJPCMDecodeFromAAC* decode = (__bridge_transfer GJPCMDecodeFromAAC *)(context->obaque);
    [decode decodePacket:packet];
    return GTrue;
}

GVoid GJ_H264DecodeContextSetup(GJAACDecodeContext* context){
    if (context == NULL) {
        context = (GJAACDecodeContext*)malloc(sizeof(GJAACDecodeContext));
    }
    context->decodeCreate = decodeCreate;
    context->decodeRelease = decodeRelease;
    context->decodePacket = decodePacket;
    context->decodeComplete = NULL;
}
