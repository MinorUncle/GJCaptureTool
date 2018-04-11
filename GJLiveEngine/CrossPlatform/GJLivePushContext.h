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
//#define RVOP

#ifdef RAOP
#include "raopserver.h"
#endif
#ifdef RVOP
#include "rvopserver.h"
#endif
#include "GJBridegContext.h"
#include "GJPlatformHeader.h"
#include "GJStreamPush.h"
#include <stdio.h>
typedef enum _GJLivePushMessageType {
    GJLivePush_messageInvalid,
    GJLivePush_connectSuccess, //data，到start time的延时
    GJLivePush_recodeSuccess,
    GJLivePush_recodeFaile,
    GJLivePush_closeComplete,
    GJLivePush_dynamicVideoUpdate,
    GJLivePush_connectError,
    GJLivePush_urlPraseError,
    GJLivePush_sendPacketError,
    GJLivePush_updateNetQuality,
} GJLivePushMessageType;
typedef GVoid (*GJLivePushCallback)(GHandle userDate, GJLivePushMessageType message, GHandle param);

typedef struct _GJLivePushContext {
    GJStreamPush *          streamPush;
    GJStreamPush *          streamRecode;
    GJEncodeToH264eContext *videoEncoder;
    GJEncodeToAACContext *  audioEncoder;
    GJVideoProduceContext * videoProducer;
    GJAudioProduceContext * audioProducer;

    pthread_mutex_t lock;

    GTime  startPushClock;
    GTime  stopPushClock;
    GTime  firstVideoEncodeClock;
    GTime  firstAudioEncodeClock;
    GTime  connentClock;
    GTime  disConnentClock;

    GJLivePushCallback callback;
    GHandle            userData;

    GJPushConfig *   pushConfig;
    GJNetworkQuality netQuality;
    GJTrafficStatus  preCheckVideoTraffic;
    // 网速检查速率单元，默认等于fps，表示1s检查一次。（越大越准确，但是越迟钝，越小越敏感）
    GInt32 rateCheckStep;
//    敏感参数，
    GInt32 sensitivity;
    

    GRational videoDropStep; //每den帧丢num帧
    //     表示允许的最大丢帧频率，每den帧丢num帧。 allowDropStep 一定小于1.0/DEFAULT_MAX_DROP_STEP,当num大于1时，den只能是num+1，
    GRational videoMaxDropRate; //默认fps-1/fps.表示1s至少有1帧数据
    GRational videoDropStepBack; //保存丢帧率，用于连续丢帧时保存，恢复时候恢复到此丢帧率
    GInt32    videoBitrate;     //当前编码码率
    GInt32    maxVideoDelay;     //默认最大的延时，超过此延时，则启动连续丢帧，直到延迟恢复到3/4,默认500ms；
    //不丢帧情况下允许的最小码率,主要用来控制质量，实际码率可能低于此。用于动态码率
    GInt32  videoMinBitrate;
    GInt32  videoNetSpeed;         //最近netSpeedCheckInterval次rateCheck网速为平均网速
    GFloat32  increaseSpeedRate; //连续检查网络空闲次数大于rateCheckStep的increaseSpeedRate倍，则增加码率

    GInt32 *netSpeedUnit;//表示当前发送码率bps，（负数表示受码率限制的发送速率，正数表示不受码率限制的满速速率）
    GInt32  netSpeedCheckInterval; //netSpeedUnit数组长度
    GInt32  collectCount; //已经收集的个数
    GInt32  favorableCount;//连续良好网速的帧数
    GInt32  increaseCount;//连续增加网速的个数
    GInt32  checkCount;//用于控制检查间隔
    GInt32  captureVideoCount;
    GInt32  dropVideoCount;

    GBool audioMute;
    GBool videoMute;
} GJLivePushContext;

GBool GJLivePush_Create(GJLivePushContext **context, GJLivePushCallback callback, GHandle param);
GBool GJLivePush_StartPush(GJLivePushContext *context, const GChar *url);
GVoid GJLivePush_StopPush(GJLivePushContext *context);
GVoid GJLivePush_SetConfig(GJLivePushContext *context, const GJPushConfig *config);
GBool GJLivePush_SetARScene(GJLivePushContext *context,GHandle scene);
GBool GJLivePush_SetCaptureView(GJLivePushContext *context,GView view);
GBool GJLivePush_SetCaptureType(GJLivePushContext *context, GJCaptureType type);
GBool GJLivePush_StartPreview(GJLivePushContext *context);
GVoid GJLivePush_StopPreview(GJLivePushContext *context);
GBool GJLivePush_SetAudioMute(GJLivePushContext *context, GBool mute);
GBool GJLivePush_SetVideoMute(GJLivePushContext *context, GBool mute);

/**
 是否禁止编码器,与GJLivePush_SetVideoMute类似，但是GJLivePush_SetVideoMute更轻量级，不会销毁编码器，此函数会，iOS进入后台时会使用。

 @param context context description
 @param disable disable description
 @return return value description
 */
GBool GJLivePush_SetVideoCodeDisable(GJLivePushContext *context, GBool disable);



GVoid GJLivePush_Dealloc(GJLivePushContext **context);
GJTrafficStatus GJLivePush_GetVideoTrafficStatus(GJLivePushContext *context);
GJTrafficStatus GJLivePush_GetAudioTrafficStatus(GJLivePushContext *context);
GHandle GJLivePush_GetDisplayView(GJLivePushContext *context);

#pragma mark 音频
GBool GJLivePush_EnableAudioEchoCancellation(GJLivePushContext *context, GBool enable);
GBool GJLivePush_EnableAudioInEarMonitoring(GJLivePushContext *context, GBool enable);
GBool GJLivePush_EnableReverb(GJLivePushContext *context, GBool enable);
GVoid GJLivePush_StopAudioMix(GJLivePushContext *context);
GBool GJLivePush_StartMixFile(GJLivePushContext *context, const GChar *fileName,AudioMixFinishCallback finishCallback);
GBool GJLivePush_SetMixVolume(GJLivePushContext *context, GFloat32 volume);
GBool GJLivePush_ShouldMixAudioToStream(GJLivePushContext *context, GBool should);
GBool GJLivePush_SetOutVolume(GJLivePushContext *context, GFloat32 volume);
GBool GJLivePush_SetInputGain(GJLivePushContext *context, GFloat32 gain);

#pragma mark 视频
GVoid GJLivePush_SetCameraPosition(GJLivePushContext *context, GJCameraPosition position);
GVoid GJLivePush_SetOutOrientation(GJLivePushContext *context, GJInterfaceOrientation orientation);
GVoid GJLivePush_SetPreviewHMirror(GJLivePushContext *context, GBool preViewMirror);
GBool GJLivePush_SetCameraMirror(GJLivePushContext *context, GBool mirror);
GBool GJLivePush_SetStreamMirror(GJLivePushContext *context, GBool mirror);
GBool GJLivePush_SetPreviewMirror(GJLivePushContext *context, GBool mirror);

GBool GJLivePush_StartRecode(GJLivePushContext *context, GView view, GInt32 fps, const GChar *fileUrl);
GVoid GJLivePush_StopRecode(GJLivePushContext *context);

GHandle GJLivePush_CaptureFreshDisplayImage(GJLivePushContext *context);
GBool GJLivePush_StartSticker(GJLivePushContext *context, const GVoid *images, GInt32 fps, GJStickerUpdateCallback callback, const GHandle userData);
GVoid GJLivePush_StopSticker(GJLivePushContext *context);

GBool GJLivePush_StartTrackImage(GJLivePushContext *context, const GVoid *images, GCRect initFrame);
GVoid GJLivePush_StopTrack(GJLivePushContext *context);

GSize GJLivePush_GetCaptureSize(GJLivePushContext *context);

GBool GJLivePush_SetMeasurementMode(GJLivePushContext *context, GBool measurementMode);

#endif /* GJLivePushContext_h */
