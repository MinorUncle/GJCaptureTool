//
//  H264Decoder.h
//  FFMpegDemo
//
//  Created by tongguan on 16/6/15.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "GJLiveDefine+internal.h"
#include "GJBridegContext.h"

typedef struct _FFDecoder FFDecoder;

GVoid GJ_FFDecodeContextCreate(GJH264DecodeContext** context);
GVoid GJ_FFDecodeContextDealloc(GJH264DecodeContext** context);

