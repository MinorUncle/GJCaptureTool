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
    
    pthread_t           sendThread;
    pthread_mutex_t     mutex;
//    int                 sendPacketCount;
//    int                 dropPacketCount;//不能丢帧
//    int                 sendByte;
    PullMessageCallback messageCallback;
    void*               rtmpPushParm;
    int                 stopRequest;
    int                 releaseRequest;
    
    GJTrafficStatus        audioStatus;
    GJTrafficStatus        videoStatus;
//    long                inVPts;
//    long                outVPts;
//
//    long                inAPts;
//    long                outAPts;

}GJRtmpPush;

void GJRtmpPush_Create(GJRtmpPush** push,PullMessageCallback callback,void* rtmpPushParm);

/**
 发送h264

 @param push push description
 @param data data description
 */
bool GJRtmpPush_SendH264Data(GJRtmpPush* push,R_GJH264Packet* data);
bool GJRtmpPush_SendAACData(GJRtmpPush* push,R_GJAACPacket* data);
void GJRtmpPush_Close(GJRtmpPush* push);
void GJRtmpPush_Release(GJRtmpPush* push);
void GJRtmpPush_StartConnect(GJRtmpPush* push,const char* sendUrl);
float GJRtmpPush_GetBufferRate(GJRtmpPush* push);
GJTrafficStatus GJRtmpPush_GetVideoBufferCacheInfo(GJRtmpPush* push);
GJTrafficStatus GJRtmpPush_GetAudioBufferCacheInfo(GJRtmpPush* push);
