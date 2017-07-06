//
//  GJFFmpegPush.h
//  GJCaptureTool
//
//  Created by melot on 2017/7/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJFFmpegPush_h
#define GJFFmpegPush_h

#include <stdio.h>
#include "GJQueue.h"
#include "avformat.h"
#include "GJLiveDefine+internal.h"
typedef enum _GJStreamPushMessageType{
    GJStreamPushMessageType_connectSuccess,
    GJStreamPushMessageType_closeComplete,
    
    
    GJStreamPushMessageType_connectError,
    GJStreamPushMessageType_urlPraseError,
    GJStreamPushMessageType_sendPacketError,//网络错误，发送失败
}GJStreamPushMessageType;
typedef GVoid(*StreamPushMessageCallback)(GHandle userData, GJStreamPushMessageType messageType,GHandle messageParm);

typedef struct _GJStreamPush{
    AVFormatContext*        formatContext;
    GJAudioStreamFormat           audioFormat;
    GJVideoStreamFormat           videoFormat;
    
    GJQueue*                sendBufferQueue;
    char                    pushUrl[100];
    
    pthread_t                sendThread;
    pthread_mutex_t          mutex;
    
    StreamPushMessageCallback      messageCallback;
    void*                   streamPushParm;
    int                     stopRequest;
    int                     releaseRequest;
    
    GJTrafficStatus         audioStatus;
    GJTrafficStatus         videoStatus;
}GJStreamPush;

GBool GJStreamPush_Create(GJStreamPush** push,StreamPushMessageCallback callback,void* streamPushParm,GJAudioStreamFormat audioFormat,GJVideoStreamFormat videoFormat);
GVoid GJStreamPush_CloseAndDealloc(GJStreamPush** push);
GBool GJStreamPush_SendVideoData(GJStreamPush* push,R_GJH264Packet* data);
GBool GJStreamPush_SendAudioData(GJStreamPush* push,R_GJAACPacket* data);
GBool GJStreamPush_StartConnect(GJStreamPush* push,const char* sendUrl);
GFloat32 GJStreamPush_GetBufferRate(GJStreamPush* push);
GJTrafficStatus GJStreamPush_GetVideoBufferCacheInfo(GJStreamPush* push);
GJTrafficStatus GJStreamPush_GetAudioBufferCacheInfo(GJStreamPush* push);

#endif /* GJFFmpegPush_h */
