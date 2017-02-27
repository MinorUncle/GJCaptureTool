//
//  GJRtmpSender.h
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <stdlib.h>
#include "GJRetainBuffer.h"
#include "rtmp.h"
#include "GJBufferPool.h"
typedef struct _GJRtmpPush{
    RTMP* rtmp;
    
    const RTMPPacket* videoPacket;
    const RTMPPacket* audioPacket;

    
    
    
}GJRtmpPush;

void GJRtmpPush_Create(GJRtmpPush** sender);
void GJRtmpPush_Release(GJRtmpPush** sender);
void GJRtmpPush_SendH264Data(GJRtmpPush* sender,GJRetainBuffer* data,double dts);
void GJRtmpPush_SendAACData(GJRtmpPush* sender,GJRetainBuffer* data,double dts);
void GJRtmpPush_StopConnect(GJRtmpPush* sender);
int  GJRtmpPush_StartConnect(GJRtmpPush* sender,char* sendUrl);
