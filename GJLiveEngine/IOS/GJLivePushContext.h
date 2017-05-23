//
//  GJLivePushContext.h
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJLivePushContext_h
#define GJLivePushContext_h

#include <stdio.h>
#include "GJPlatformHeader.h"
#include "GJRtmpPush.h"
#include "GJBridegContext.h"
typedef enum _GJLivePushMessageType{
    GJLivePush_messageInvalid,
    GJLivePush_connectSuccess,
    GJLivePush_closeComplete,
    GJLivePush_connectError,
    GJLivePush_urlPraseError,
    GJLivePush_sendPacketError,
    GJLivePush_encodeFristVideoFrame,
    GJLivePush_encodeFristAudioFrame,
}GJLivePushMessageType;
typedef GVoid (*GJLivePushCallback)(GHandle userDate,GJLivePushMessageType message,GHandle param);
typedef struct _GJLivePushContext{
    GJRtmpPush*             videoPush;
//    GJPushSessionStatus     PushSessionStatus;
    GJEncodeToH264eContext*    videoEncoder;
    GJEncodeToAACContext*     audioEncoder;
    GJVideoProduceContext*      videoProducer;
    GJAudioProduceContext*      audioProducer;

    pthread_mutex_t         lock;
    GTime                   startPushClock;
    GTime                   connentClock;
    GTime                   fristVideoEncodeClock;
    GTime                   fristAudioEncodeClock;
//
    GJLivePushCallback      callback;
    GHandle                 userData;
    GJTrafficStatus         videoTraffic;
    GJTrafficStatus         audioTraffic;    
}GJLivePushContext;

GBool GJLivePush_Create(GJLivePushContext** context,GJLivePushCallback callback,GHandle param);
GBool GJLivePush_StartPush(GJLivePushContext* context,GChar* url);
GVoid GJLivePush_StopPush(GJLivePushContext* context);
GBool GJLivePush_StartPreview(GJLivePushContext* context,GChar* url);
GVoid GJLivePush_StopPreview(GJLivePushContext* context);
GVoid GJLivePush_Dealloc(GJLivePushContext** context);
GJTrafficStatus GJLivePush_GetVideoTrafficStatus(GJLivePushContext* context);
GJTrafficStatus GJLivePush_GetAudioTrafficStatus(GJLivePushContext* context);
GHandle GJLivePush_GetDisplayView(GJLivePushContext* context);
#endif /* GJLivePushContext_h */
