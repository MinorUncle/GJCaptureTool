//
//  GJRtmpPull.h
//  GJCaptureTool
//
//  Created by 未成年大叔 on 17/3/4.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJRtmpPull_h
#define GJRtmpPull_h

#include <stdio.h>
#include <stdlib.h>
#include "GJRetainBuffer.h"
#include "rtmp.h"
#include "GJRetainBufferPool.h"
#include "GJQueue.h"
#include <Foundation/Foundation.h>

typedef enum _GJRTMPPullMessageType{
    GJRTMPPullMessageType_connectSuccess,
    GJRTMPPullMessageType_closeComplete,
    
    
    GJRTMPPullMessageType_connectError,
    GJRTMPPullMessageType_urlPraseError,
    GJRTMPPullMessageType_sendPacketError,
}GJRTMPPullMessageType;

typedef enum _GJRTMPDataType{
    GJRTMPVideoData,
    GJRTMPAudioData,
}GJRTMPDataType;

struct _GJRtmpPull;

typedef void(*PullMessageCallback)(struct _GJRtmpPull* rtmpPull, GJRTMPPullMessageType messageType,void* rtmpPullParm,void* messageParm);
typedef void(*PullDataCallback)(struct _GJRtmpPull* rtmpPull,GJRTMPDataType dataType,GJRetainBuffer* buffer,void* rtmpPullParm,uint32_t pts);

#define MAX_URL_LENGTH 100
typedef struct _GJRtmpPull{
    RTMP*                   rtmp;
    GJQueue*                pullBufferQueue;
    char                    pullUrl[MAX_URL_LENGTH];
    
    GJRetainBufferPool*           memoryCachePool;
    pthread_t               pullThread;
    pthread_t               callbackThread;
    int                     pullPacketCount;
    int                     dropPacketCount;
    int                     pullByte;
    PullMessageCallback     messageCallback;
    PullDataCallback        dataCallback;
    void*                   messageCallbackParm;
    void*                   dataCallbackParm;

    int                     stopRequest;
}GJRtmpPull;

void GJRtmpPull_Create(GJRtmpPull** pull,PullMessageCallback callback,void* rtmpPullParm);
void GJRtmpPull_CloseAndRelease(GJRtmpPull* pull);
void GJRtmpPull_StartConnect(GJRtmpPull* pull,PullDataCallback dataCallback,void* callbackParm,const char* pullUrl);
float GJRtmpPull_GetBufferRate(GJRtmpPull* pull);



#endif /* GJRtmpPull_h */
