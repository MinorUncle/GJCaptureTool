//
//  GJStreamPush.h
//  GJCaptureTool
//
//  Created by melot on 2017/7/11.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJStreamPush_h
#define GJStreamPush_h

#include "GJLiveDefine+internal.h"
#include "GJQueue.h"
#include <stdio.h>
#include "GJMessageDispatcher.h"
#define MAX_URL_LENGTH 100
#define PUSH_PACKET_PRE_SIZE 23
typedef struct _GJStreamPush GJStreamPush;

typedef enum _kStreamPushMessageType {
    kStreamPushMessageType_connectSuccess,
    kStreamPushMessageType_closeComplete,
    kStreamPushMessageType_packetSendSignal, // GJMediaType
    kStreamPushMessageType_connectError,
    kStreamPushMessageType_urlPraseError,
    kStreamPushMessageType_sendPacketError, //网络错误，发送失败

} kStreamPushMessageType;
//typedef GVoid (*StreamPushMessageCallback)(GJStreamPush* push, GHandle receive, kStreamPushMessageType messageType, GLong messageParm);

GBool GJStreamPush_Create(GJStreamPush **push, MessageHandle callback, GHandle streamPushParm, const GJAudioStreamFormat *audioFormat, const GJVideoStreamFormat *videoFormat);
GVoid GJStreamPush_CloseAndDealloc(GJStreamPush **push);

GBool GJStreamPush_SendVideoData(GJStreamPush *push, R_GJPacket *data);
GBool GJStreamPush_SendAudioData(GJStreamPush *push, R_GJPacket *data);

GBool GJStreamPush_SendUncodeVideoData(GJStreamPush *push, R_GJPixelFrame *data);
GBool GJStreamPush_SendUncodeAudioData(GJStreamPush *push, R_GJPCMFrame *data);

GBool GJStreamPush_StartConnect(GJStreamPush *push, const char *sendUrl);
GFloat GJStreamPush_GetBufferRate(GJStreamPush *push);
GJTrafficStatus GJStreamPush_GetVideoBufferCacheInfo(GJStreamPush *push);
GJTrafficStatus GJStreamPush_GetAudioBufferCacheInfo(GJStreamPush *push);

static inline GBool GJStreamPush_NodeReceiveData(GJStreamPush *push, R_GJPacket *data, GJMediaType type) {
    if (type == GJMediaType_Audio) {
        return GJStreamPush_SendAudioData(push, data);
    } else {
        return GJStreamPush_SendVideoData(push, data);
    }
}
#endif /* GJStreamPush_h */
