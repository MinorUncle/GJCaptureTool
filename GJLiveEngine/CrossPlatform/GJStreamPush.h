//
//  GJStreamPush.h
//  GJCaptureTool
//
//  Created by melot on 2017/7/11.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJStreamPush_h
#define GJStreamPush_h


#include <stdio.h>
#include "GJQueue.h"
#include "avformat.h"
#include "GJLiveDefine+internal.h"

#define MAX_URL_LENGTH 100
#define PUSH_PACKET_PRE_SIZE 23


typedef enum _kStreamPushMessageType{
    kStreamPushMessageType_connectSuccess,
    kStreamPushMessageType_closeComplete,
    
    
    kStreamPushMessageType_connectError,
    kStreamPushMessageType_urlPraseError,
    kStreamPushMessageType_sendPacketError,//网络错误，发送失败
}kStreamPushMessageType;
typedef GVoid(*StreamPushMessageCallback)(GHandle userData, kStreamPushMessageType messageType,GHandle messageParm);


typedef struct _GJStreamPush GJStreamPush;


GBool GJStreamPush_Create(GJStreamPush** push,StreamPushMessageCallback callback,GHandle streamPushParm,const GJAudioStreamFormat* audioFormat,const GJVideoStreamFormat* videoFormat);
GVoid GJStreamPush_CloseAndDealloc(GJStreamPush** push);
GBool GJStreamPush_SendVideoData(GJStreamPush* push,R_GJPacket* data);
GBool GJStreamPush_SendAudioData(GJStreamPush* push,R_GJPacket* data);

GBool GJStreamPush_SendUncodeVideoData(GJStreamPush* push,R_GJPixelFrame* data);
GBool GJStreamPush_SendUncodeAudioData(GJStreamPush* push,R_GJPCMFrame* data);

GBool GJStreamPush_StartConnect(GJStreamPush* push,const char* sendUrl);
GFloat32 GJStreamPush_GetBufferRate(GJStreamPush* push);
GJTrafficStatus GJStreamPush_GetVideoBufferCacheInfo(GJStreamPush* push);
GJTrafficStatus GJStreamPush_GetAudioBufferCacheInfo(GJStreamPush* push);

#endif /* GJStreamPush_h */
