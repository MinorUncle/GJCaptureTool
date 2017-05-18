//
//  GJLivePullContext.h
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJLivePullContext_h
#define GJLivePullContext_h

#include <stdio.h>
#include "GJLiveDefine+internal.h"
#include "GJRtmpPull.h"
#include "GJLivePlayer.h"


#include "IOS_AACDecode.h"
#include "IOS_H264Decoder.h"
typedef enum _GJLivePullMessageType{
    GJLivePullMessageType_connectSuccess,
    GJLivePullMessageType_closeComplete,
    GJLivePullMessageType_connectError,
    GJLivePullMessageType_urlPraseError,
    GJLivePullMessageType_receivePacketError
}GJLivePullMessageType;
typedef GVoid (*GJLivePullCallback)(GHandle userDate,GJLivePullMessageType message,GHandle param);

typedef struct _GJLivePullContext{
    GJRtmpPull*             videoPull;
    pthread_t               playThread;
    GJPullSessionStatus     pullSessionStatus;
    GJH264DecodeContext*    videoDecoder;
    GJAACDecodeContext*     audioDecoder;
    pthread_mutex_t         lock;
    GJLivePlayer*      player;
    GLong                   startPullClock;
    GLong                   connentClock;
    GLong                   fristVideoClock;
    GLong                   fristVideoDecodeClock;
    GLong                   fristAudioClock;
    
    GJLivePullCallback      callback;
    GHandle                 userData;
    
    GJTrafficStatus         videoTraffic;
    GJTrafficStatus         audioTraffic;
}GJLivePullContext;

GBool GJLivePull_Create(GJLivePullContext* context,GJLivePullCallback callback,GHandle param);
GBool GJLivePull_StartPull(GJLivePullContext* context,char* url);
GVoid GJLivePull_StopPull(GJLivePullContext* context);
GVoid GJLivePull_Dealloc(GJLivePullContext* context);
GJTrafficStatus GJLivePull_GetVideoTrafficStatus(GJLivePullContext* context);
GJTrafficStatus GJLivePull_GetAudioTrafficStatus(GJLivePullContext* context);


#endif /* GJLivePullContext_h */
