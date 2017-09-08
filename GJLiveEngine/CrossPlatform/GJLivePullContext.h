//
//  GJLivePullContext.h
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJLivePullContext_h
#define GJLivePullContext_h

#include "GJLiveDefine+internal.h"
#include "GJLivePlayer.h"
#include "GJStreamPull.h"
#include <stdio.h>

#include "GJBridegContext.h"

typedef enum _GJLivePullMessageType {
    GJLivePull_messageInvalid,
    GJLivePull_connectSuccess,
    GJLivePull_closeComplete,
    GJLivePull_connectError,
    GJLivePull_urlPraseError,
    GJLivePull_receivePacketError,
    GJLivePull_decodeFristVideoFrame,
    GJLivePull_decodeFristAudioFrame,
    GJLivePull_bufferStart,
    GJLivePull_bufferEnd,
    GJLivePull_bufferUpdate,
} GJLivePullMessageType;
typedef GVoid (*GJLivePullCallback)(GHandle userDate, GJLivePullMessageType message, GHandle param);

typedef struct _GJLivePullContext {
    GJStreamPull *       videoPull;
    pthread_t            playThread;
    GJPullSessionStatus  pullSessionStatus;
    GJH264DecodeContext *videoDecoder;
    GJAACDecodeContext * audioDecoder;
    pthread_mutex_t      lock;
    GJLivePlayer *       player;
    GTime                startPullClock;
    GTime                connentClock;
    GTime                fristVideoPullClock;
    GTime                fristAudioPullClock;
    GTime                fristVideoDecodeClock;

    GJLivePullCallback callback;
    GHandle            userData;
    GJTrafficStatus    videoTraffic;
    GJTrafficStatus    audioTraffic;
    GLong              videoUnDecodeByte; //没有解码前的数据大小，
    GLong              audioUnDecodeByte;

} GJLivePullContext;

GBool GJLivePull_Create(GJLivePullContext **context, GJLivePullCallback callback, GHandle param);
GBool GJLivePull_StartPull(GJLivePullContext *context, const GChar *url);
GVoid GJLivePull_StopPull(GJLivePullContext *context);
GVoid GJLivePull_Dealloc(GJLivePullContext **context);
GJTrafficStatus GJLivePull_GetVideoTrafficStatus(GJLivePullContext *context);
GJTrafficStatus GJLivePull_GetAudioTrafficStatus(GJLivePullContext *context);
GHandle GJLivePull_GetDisplayView(GJLivePullContext *context);

#endif /* GJLivePullContext_h */
