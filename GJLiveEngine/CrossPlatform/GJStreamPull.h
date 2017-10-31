//
//  GJStreamPull.h
//  GJCaptureTool
//
//  Created by melot on 2017/7/11.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJStreamPull_h
#define GJStreamPull_h

#include "GJLiveDefine+internal.h"
#include <stdlib.h>
typedef enum _kStreamPullMessageType {
    kStreamPullMessageType_connectSuccess,
    kStreamPullMessageType_closeComplete,
    kStreamPullMessageType_connectError,
    kStreamPullMessageType_urlPraseError,
    kStreamPullMessageType_receivePacketError
} kStreamPullMessageType;

typedef struct _GJStreamPull GJStreamPull;

typedef GVoid (*StreamPullMessageCallback)(GJStreamPull *StreamPull, kStreamPullMessageType messageType, GHandle StreamPullParm, GHandle messageParm);
typedef GVoid (*StreamPullDataCallback)(GJStreamPull *StreamPull, R_GJPacket *packet, GHandle StreamPullParm);

#define MAX_URL_LENGTH 100

//所有不阻塞
GBool GJStreamPull_Create(GJStreamPull **pull, StreamPullMessageCallback callback, GHandle StreamPullParm);

GVoid GJStreamPull_CloseAndRelease(GJStreamPull *pull);

GBool GJStreamPull_StartConnect(GJStreamPull *pull, StreamPullDataCallback dataCallback, GHandle callbackParm, const GChar *pullUrl);

GJTrafficUnit GJStreamPull_GetVideoPullInfo(GJStreamPull *pull);

GJTrafficUnit GJStreamPull_GetAudioPullInfo(GJStreamPull *pull);

#ifdef NETWORK_DELAY
GInt32 GJStreamPull_GetNetWorkDelay(GJStreamPull *pull);
#endif

#endif /* GJStreamPull_h */
