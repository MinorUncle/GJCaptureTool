//
//  GJLivePushContext.h
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJLivePushContext_h
#define GJLivePushContext_h
#include "webserver.h"
#define RAOP

#ifdef RAOP
#include "raopserver.h"
#endif
#ifdef RVOP
#include "rvopserver.h"
#endif
#include <stdio.h>
#include "GJPlatformHeader.h"
#include "GJStreamPush.h"
#include "GJBridegContext.h"
typedef enum _GJLivePushMessageType{
    GJLivePush_messageInvalid,
    GJLivePush_connectSuccess,   //data，到start time的延时
    GJLivePush_recodeComplete,
    GJLivePush_closeComplete,
    GJLivePush_dynamicVideoUpdate,
    GJLivePush_connectError,
    GJLivePush_urlPraseError,
    GJLivePush_sendPacketError,
    GJLivePush_updateNetQuality,
}GJLivePushMessageType;
typedef GVoid (*GJLivePushCallback)(GHandle userDate,GJLivePushMessageType message,GHandle param);
typedef struct _GJLivePushContext{
    GJStreamPush*               videoPush;
    GJEncodeToH264eContext*     videoEncoder;
    GJEncodeToAACContext*       audioEncoder;
    GJVideoProduceContext*      videoProducer;
    GJAudioProduceContext*      audioProducer;
    GJRecodeContext*            recoder;


    pthread_mutex_t             lock;
    
    GTime                       startPushClock;
    GTime                       stopPushClock;
    GTime                       firstVideoEncodeClock;
    GTime                       firstAudioEncodeClock;
    GTime                       connentClock;
    GTime                       disConnentClock;
    GInt32                      operationCount;//用来避免使用线程锁
    
    GJLivePushCallback          callback;
    GHandle                     userData;
    
    GJPushConfig*               pushConfig;
    GJNetworkQuality            netQuality;
    GJTrafficStatus             preVideoTraffic;
    //     .den帧中丢.num帧或多发.num帧则出发敏感算法默认（4，8）,给了den帧数据，但是只发送了小于nun帧，则主动降低质量
    GInt32                      rateCheckStep;
    GInt32                      dropStepPrecision;//发送速率大于DROP_STEP_PRECISION，则开始减速

    GRational                   videoDropStep;//每den帧丢num帧
    //     表示允许的最大丢帧频率，每den帧丢num帧。 allowDropStep 一定小于1.0/DEFAULT_MAX_DROP_STEP,当num大于1时，den只能是num+1，
    GRational                   videoMaxDropRate;//
    GInt32                      videoBitrate;  //当前码率
    //不丢帧情况下允许的最小码率。用于动态码率
    GInt32                      videoMinBitrate;
    GInt32                      videoNetSpeed;//当前视频网络速度
    GInt32                      netSpeedCheckInterval;//最大netSpeedCheckInterval次rateCheckStep后更新网速
    GInt32*                     netSpeedUnit;
    GInt32                      collectCount;//已经收集的个数
    GInt32                      captureVideoCount;
    GInt32                      dropVideoCount;
    
    GBool                       audioMute;
    GBool                       videoMute;
}GJLivePushContext;

GBool GJLivePush_Create(GJLivePushContext** context,GJLivePushCallback callback,GHandle param);
GBool GJLivePush_StartPush(GJLivePushContext* context,const GChar* url);
GVoid GJLivePush_StopPush(GJLivePushContext* context);
GVoid GJLivePush_SetConfig(GJLivePushContext* context,const GJPushConfig* config);
GBool GJLivePush_StartPreview(GJLivePushContext* context);
GVoid GJLivePush_StopPreview(GJLivePushContext* context);
GBool GJLivePush_SetAudioMute(GJLivePushContext* context,GBool mute);
GBool GJLivePush_SetVideoMute(GJLivePushContext* context,GBool mute);

GVoid GJLivePush_SetCameraPosition(GJLivePushContext* context,GJCameraPosition position);
GVoid GJLivePush_SetOutOrientation(GJLivePushContext* context,GJInterfaceOrientation orientation);
GVoid GJLivePush_SetPreviewHMirror(GJLivePushContext* context,GBool preViewMirror);


GVoid GJLivePush_Dealloc(GJLivePushContext** context);
GJTrafficStatus GJLivePush_GetVideoTrafficStatus(GJLivePushContext* context);
GJTrafficStatus GJLivePush_GetAudioTrafficStatus(GJLivePushContext* context);
GHandle GJLivePush_GetDisplayView(GJLivePushContext* context);

GBool GJLivePush_EnableAudioInEarMonitoring(GJLivePushContext* context,GBool enable);
GBool GJLivePush_EnableReverb(GJLivePushContext* context,GBool enable);
GVoid GJLivePush_StopAudioMix(GJLivePushContext* context);
GBool GJLivePush_StartMixFile(GJLivePushContext* context,const GChar* fileName);
GBool GJLivePush_SetMixVolume(GJLivePushContext* context,GFloat32 volume);
GBool GJLivePush_ShouldMixAudioToStream(GJLivePushContext* context,GBool should);
GBool GJLivePush_SetOutVolume(GJLivePushContext* context,GFloat32 volume);
GBool GJLivePush_SetInputGain(GJLivePushContext* context,GFloat32 gain);
GBool GJLivePush_StartRecode(GJLivePushContext* context,GView view, GInt32 fps,const GChar* fileUrl);
GVoid GJLivePush_StopRecode(GJLivePushContext* context);

#endif /* GJLivePushContext_h */
