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
#include "GJQueue.h"

typedef enum _GJRTMPMessageType{
    GJRTMPMessageType_connectSuccess,
    GJRTMPMessageType_closeComplete,

    
    GJRTMPMessageType_connectError,
    GJRTMPMessageType_urlPraseError,
    GJRTMPMessageType_sendPacketError,
}GJRTMPMessageType;

#define MAX_URL_LENGTH 100
typedef struct _GJRtmpPush{
    RTMP*               rtmp;
    GJQueue*            sendBufferQueue;
    char                pushUrl[MAX_URL_LENGTH];
    
    GJBufferPool*       memoryCachePool;
    pthread_t           sendThread;
    int                 sendPacketCount;
    int                 dropPacketCount;
    int                 sendByte;
    void                (*messageCallback)(GJRTMPMessageType messageType,void* rtmpPushParm,void* messageParm);
    void*               rtmpPushParm;
    
    int                 stopRequest;
}GJRtmpPush;

void GJRtmpPush_Create(GJRtmpPush** sender,void(*callback)(GJRTMPMessageType,void*,void*),void* rtmpPushParm);
void GJRtmpPush_Release(GJRtmpPush* sender);
void GJRtmpPush_SendH264Data(GJRtmpPush* sender,GJRetainBuffer* data,double dts);
void GJRtmpPush_SendAACData(GJRtmpPush* sender,GJRetainBuffer* data,double dts);
void GJRtmpPush_Close(GJRtmpPush* sender);
void GJRtmpPush_StartConnect(GJRtmpPush* sender,const char* sendUrl);
float GJRtmpPush_GetBufferRate(GJRtmpPush* sender);
