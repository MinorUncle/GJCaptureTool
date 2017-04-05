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
#import "GJLiveDefine.h"
#import "GJLiveDefine+internal.h"

typedef enum _GJRTMPPushMessageType{
    GJRTMPPushMessageType_connectSuccess,
    GJRTMPPushMessageType_closeComplete,

    
    GJRTMPPushMessageType_connectError,
    GJRTMPPushMessageType_urlPraseError,
    GJRTMPPushMessageType_sendPacketError,//网络错误，发送失败
}GJRTMPPushMessageType;

struct _GJRtmpPush;
typedef void(*PullMessageCallback)(struct _GJRtmpPush* rtmpPush, GJRTMPPushMessageType messageType,void* rtmpPullParm,void* messageParm);

#define MAX_URL_LENGTH 100
typedef struct _GJRtmpPush{
    RTMP*               rtmp;
    GJQueue*            sendBufferQueue;
    char                pushUrl[MAX_URL_LENGTH];
    
    GJBufferPool*       memoryCachePool;
    pthread_t           sendThread;
    pthread_mutex_t     mutex;
    int                 sendPacketCount;
    int                 dropPacketCount;
    int                 sendByte;
    PullMessageCallback messageCallback;
    void*               rtmpPushParm;
    int                 stopRequest;
    int                 releaseRequest;
    
    long                inPts;
    long                outPts;


}GJRtmpPush;

void GJRtmpPush_Create(GJRtmpPush** push,PullMessageCallback callback,void* rtmpPushParm);

/**
 发送h264

 @param push push description
 @param data data description
 @param pts pts description，以ms为单位
 */
void GJRtmpPush_SendH264Data(GJRtmpPush* push,R_GJH264Packet* data,uint32_t pts);
void GJRtmpPush_SendAACData(GJRtmpPush* push,R_GJAACPacket* data,uint32_t dts);
void GJRtmpPush_Close(GJRtmpPush* push);
void GJRtmpPush_Release(GJRtmpPush* push);
void GJRtmpPush_StartConnect(GJRtmpPush* push,const char* sendUrl);
float GJRtmpPush_GetBufferRate(GJRtmpPush* push);
GJCacheInfo GJRtmpPush_GetBufferCacheInfo(GJRtmpPush* push);
