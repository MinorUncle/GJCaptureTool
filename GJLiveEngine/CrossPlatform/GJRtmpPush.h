//
//  GJRtmpSender.h
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <stdlib.h>
#include "GJRetainBuffer.h"
#include "GJBufferPool.h"
#include "GJQueue.h"
#import "GJLiveDefine.h"
#import "GJLiveDefine+internal.h"

#define GJRTMP_PACKET_NEED_PRESIZE 5

typedef enum _GJRTMPPushMessageType{
    GJRTMPPushMessageType_connectSuccess,
    GJRTMPPushMessageType_closeComplete,

    
    GJRTMPPushMessageType_connectError,
    GJRTMPPushMessageType_urlPraseError,
    GJRTMPPushMessageType_sendPacketError,//网络错误，发送失败
}GJRTMPPushMessageType;



struct _GJRtmpPush;
typedef GVoid(*PushMessageCallback)(GHandle userData, GJRTMPPushMessageType messageType,GHandle messageParm);



GBool GJRtmpPush_Create(GJRtmpPush** push,PushMessageCallback callback,void* rtmpPushParm);
GVoid GJRtmpPush_CloseAndDealloc(GJRtmpPush** push);

/**
 发送h264

 @param push push description
 @param data data description
 */
GBool GJRtmpPush_SendH264Data(GJRtmpPush* push,R_GJPacket* data);
GBool GJRtmpPush_SendAVCSequenceHeader(GJRtmpPush* push,GUInt8* sps,GInt32 spsSize,GUInt8* pps,GInt32 ppsSize,GUInt64 dts);

GBool GJRtmpPush_SendAACData(GJRtmpPush* push,R_GJPacket* data);
GBool GJRtmpPush_SendAACSequenceHeader(GJRtmpPush* push,GInt32 aactype, GInt32 sampleRate, GInt32 channels,GUInt64 dts);
GBool GJRtmpPush_StartConnect(GJRtmpPush* push,const char* sendUrl);
GFloat32 GJRtmpPush_GetBufferRate(GJRtmpPush* push);
GJTrafficStatus GJRtmpPush_GetVideoBufferCacheInfo(GJRtmpPush* push);
GJTrafficStatus GJRtmpPush_GetAudioBufferCacheInfo(GJRtmpPush* push);
