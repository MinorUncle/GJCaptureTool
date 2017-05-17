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
typedef GVoid (*GJLivePullCallback)(GHandle userDate,GJPlayMessage message,GHandle param);

typedef struct _GJLivePullContext{
    GJRtmpPull* _videoPull;
    pthread_t  _playThread;
    GJPullSessionStatus _pullSessionStatus;
    GJH264DecodeContext* videoDecoder;
    GJAACDecodeContext* audioDecoder;
    pthread_mutex_t lock;
    GJLivePlayContext* player;
    GLong startPullClock;
    GLong connentClock;
    GLong fristVideoClock;
    GLong fristVideoDecodeClock;
    GLong fristAudioClock;
    
    GJLivePullCallback callback;
    GHandle userData;
}GJLivePullContext;

GVoid GJLivePull_Create(GJLivePullContext* context,GJLivePullCallback callback,GHandle param);
GVoid GJLivePull_StartPull(GJLivePullContext* context,char* url);
GBool GJLivePull_StopPull(GJLivePullContext* context);
GVoid GJLivePull_StopDealloc(GJLivePullContext* context);


#endif /* GJLivePullContext_h */
