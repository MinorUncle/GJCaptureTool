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
#include "GJLiveDefine+internal.h"

typedef enum _GJRTMPPullMessageType{
    GJRTMPPullMessageType_connectSuccess,
    GJRTMPPullMessageType_closeComplete,
    
    
    GJRTMPPullMessageType_connectError,
    GJRTMPPullMessageType_urlPraseError,
    GJRTMPPullMessageType_sendPacketError,
}GJRTMPPullMessageType;


struct _GJRtmpPull;

typedef void(*PullMessageCallback)(struct _GJRtmpPull* rtmpPull, GJRTMPPullMessageType messageType,void* rtmpPullParm,void* messageParm);
typedef void(*PullDataCallback)(struct _GJRtmpPull* rtmpPull,GJStreamPacket packet,void* rtmpPullParm);

#define MAX_URL_LENGTH 100
typedef struct _GJRtmpPull{
    RTMP*                   rtmp;
    GJQueue*                pullBufferQueue;
    char                    pullUrl[MAX_URL_LENGTH];
    
    GJRetainBufferPool*           memoryCachePool;
    pthread_t               pullThread;
    pthread_mutex_t          mutex;

    int                     pullPacketCount;
    int                     dropPacketCount;
    int                     pullByte;
    PullMessageCallback     messageCallback;
    PullDataCallback        dataCallback;
    void*                   messageCallbackParm;
    void*                   dataCallbackParm;

    int                     stopRequest;
    int                     releaseRequest;

}GJRtmpPull;

//所有不阻塞
void GJRtmpPull_Create(GJRtmpPull** pull,PullMessageCallback callback,void* rtmpPullParm);
void GJRtmpPull_Close(GJRtmpPull* pull);
void GJRtmpPull_Release(GJRtmpPull* pull);

void GJRtmpPull_StartConnect(GJRtmpPull* pull,PullDataCallback dataCallback,void* callbackParm,const char* pullUrl);
float GJRtmpPull_GetBufferRate(GJRtmpPull* pull);



#endif /* GJRtmpPull_h */
