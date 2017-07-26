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


typedef enum _GJStreamPushMessageType{
    GJStreamPushMessageType_connectSuccess,
    GJStreamPushMessageType_closeComplete,
    
    
    GJStreamPushMessageType_connectError,
    GJStreamPushMessageType_urlPraseError,
    GJStreamPushMessageType_sendPacketError,//网络错误，发送失败
}GJStreamPushMessageType;
typedef GVoid(*StreamPushMessageCallback)(GHandle userData, GJStreamPushMessageType messageType,GHandle messageParm);


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
