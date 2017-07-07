//
//  GJRtmpPull.h
//  GJCaptureTool
//
//  Created by 未成年大叔 on 17/3/4.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJRtmpPull_h
#define GJRtmpPull_h

#include <stdio.h>
#include <stdlib.h>
#include "GJRetainBuffer.h"
#include "rtmp.h"
#include "GJRetainBufferPool.h"
#include "GJLiveDefine+internal.h"

typedef enum _GJRTMPPullMessageType{
    GJRTMPPullMessageType_connectSuccess,
    GJRTMPPullMessageType_closeComplete,
    
    
    GJRTMPPullMessageType_connectError,
    GJRTMPPullMessageType_urlPraseError,
    GJRTMPPullMessageType_receivePacketError
}GJRTMPPullMessageType;


struct _GJRtmpPull;

typedef GVoid(*PullMessageCallback)(struct _GJRtmpPull* rtmpPull, GJRTMPPullMessageType messageType,GHandle rtmpPullParm,GHandle messageParm);
typedef GVoid(*PullVideoDataCallback)(struct _GJRtmpPull* rtmpPull,R_GJPacket* packet,GHandle rtmpPullParm);
typedef GVoid(*PullAudioDataCallback)(struct _GJRtmpPull* rtmpPull,R_GJPacket* packet,GHandle rtmpPullParm);




#define MAX_URL_LENGTH 100
typedef struct _GJRtmpPull{
    RTMP*                   rtmp;
    char                    pullUrl[MAX_URL_LENGTH];
    
    GJRetainBufferPool*      memoryCachePool;
    pthread_t               pullThread;
    pthread_mutex_t          mutex;

    GJTrafficUnit           videoPullInfo;
    GJTrafficUnit           audioPullInfo;

    PullMessageCallback     messageCallback;
    PullVideoDataCallback        videoCallback;
    PullAudioDataCallback        audioCallback;

    GHandle                   messageCallbackParm;
    GHandle                   dataCallbackParm;

    int                     stopRequest;
    int                     releaseRequest;

}GJRtmpPull;

//所有不阻塞
GBool GJRtmpPull_Create(GJRtmpPull** pull,PullMessageCallback callback,GHandle rtmpPullParm);
GVoid GJRtmpPull_CloseAndRelease(GJRtmpPull* pull);

GBool GJRtmpPull_StartConnect(GJRtmpPull* pull,PullVideoDataCallback videoCallback,PullAudioDataCallback audioCallback,GHandle callbackParm,const GChar* pullUrl);
GJTrafficUnit GJRtmpPull_GetVideoPullInfo(GJRtmpPull* pull);
GJTrafficUnit GJRtmpPull_GetAudioPullInfo(GJRtmpPull* pull);



#endif /* GJRtmpPull_h */
