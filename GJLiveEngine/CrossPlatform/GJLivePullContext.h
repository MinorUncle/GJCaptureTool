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
#include "GJLog.h"

#include "GJBridegContext.h"

typedef enum _GJLivePullMessageType {
    GJLivePull_messageInvalid,
    GJLivePull_connectSuccess,//GLONG
    GJLivePull_closeComplete,
    GJLivePull_connectError,
    GJLivePull_urlPraseError,
    GJLivePull_receivePacketError,
    GJLivePull_decodeFristVideoFrame,
    GJLivePull_decodeFristAudioFrame,
    GJLivePull_bufferStart,
    GJLivePull_bufferEnd,
    GJLivePull_bufferUpdate,//UnitBufferInfo
    GJLivePull_fristRender,
#ifdef NETWORK_DELAY
    GJLivePull_testNetShakeUpdate,//GTime
    GJLivePull_testKeyDelayUpdate,//GTime
#endif
    GJLivePull_netShakeUpdate,//GTime
    GJLivePull_dewateringUpdate,//GFloat
} GJLivePullMessageType;
typedef GVoid (*GJLivePullCallback)(GHandle userDate, GJLivePullMessageType message, GHandle param);

typedef struct _GJLivePullContext {
    GJClass              priv_class;
    GJStreamPull *       streamPull;
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
GVoid GJLivePull_Pause(GJLivePullContext *context);
GVoid GJLivePull_Resume(GJLivePullContext *context);

GVoid GJLivePull_Dealloc(GJLivePullContext **context);
GJTrafficStatus GJLivePull_GetVideoTrafficStatus(GJLivePullContext *context);
GJTrafficStatus GJLivePull_GetAudioTrafficStatus(GJLivePullContext *context);
GHandle GJLivePull_GetDisplayView(GJLivePullContext *context);
#ifdef NETWORK_DELAY
GInt32 GJLivePull_GetNetWorkDelay(GJLivePullContext *context);
#endif

#endif /* GJLivePullContext_h */
