//
//  GJPictureDisplayContext.h
//  GJCaptureTool
//
//  Created by melot on 2017/5/16.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJBridegContext_h
#define GJBridegContext_h
#include "GJLiveDefine+internal.h"
#include "GJFormats.h"
#include <pthread.h>
typedef GVoid (*AudioFrameOutCallback)(GHandle userData, R_GJPCMFrame *frame);
typedef GVoid (*AACPacketOutCallback)(GHandle userData, R_GJPacket *packet);
typedef GVoid (*VideoFrameOutCallback)(GHandle userData, R_GJPixelFrame *frame);
typedef GVoid (*H264PacketOutCallback)(GHandle userData, R_GJPacket *packet);
typedef GBool (*FillDataCallback)(GHandle userData, GVoid *data, GInt32 *size);
typedef GVoid (*RecodeCompleteCallback)(GHandle userData, const GChar *filePath, GHandle error);
typedef GVoid (*GJStickerUpdateCallback)(GHandle userDate, GLong index, const GHandle ioParm, GBool *ioFinish);
typedef GVoid (*AudioMixFinishCallback)(GHandle userData, const GChar *filePath, GHandle error);

struct GJPipleNode;
typedef GBool (*NodeFlowDataFunc)(struct GJPipleNode *node, GJRetainBuffer *data, GJMediaType dataType);

typedef struct GJPipleNode {

    //    可能有多个sub，比如编码器会连接到发送器和录制器
    struct GJPipleNode **subNodes;
    GInt32               subCount;
    NodeFlowDataFunc     receiveData;
    pthread_mutex_t *    lock;
} GJPipleNode;

#define pipleNodeLock(node) pthread_mutex_lock((node)->lock)
#define pipleNodeUnLock(node) pthread_mutex_unlock((node)->lock)

/**
 初始化

 @param node node description
 @param receiveData 该node从此函数接受数据
 @return return 该node 产生的数据务必传递给此函数,也可以通过NodeFlowDataFunc 获取，
 */
NodeFlowDataFunc pipleNodeInit(GJPipleNode *node, NodeFlowDataFunc receiveData);
GBool pipleNodeUnInit(GJPipleNode *node);
GBool pipleConnectNode(GJPipleNode *superNode, GJPipleNode *subNode);

/**
 断开superNode与subNode的连接

 @param superNode superNode
 @param subNode subNode
 @return return value description
 */
GBool pipleDisConnectNode(GJPipleNode *superNode, GJPipleNode *subNode);

GBool pipleProduceDataCallback(GJPipleNode* node, GJRetainBuffer* data,GJMediaType dataType);
static inline NodeFlowDataFunc pipleNodeFlowFunc(GJPipleNode* node){
    return pipleProduceDataCallback;
}

typedef struct _GJRecodeContext {
    GHandle obaque;
    GBool (*setup)(struct _GJRecodeContext *context, const GChar *fileUrl, RecodeCompleteCallback callback, GHandle userHandle);
    GVoid (*unSetup)(struct _GJRecodeContext *context);
    GBool (*addVideoSource)(struct _GJRecodeContext *context, GJVideoFormat format, GView targetView);
    GBool (*addAudioSource)(struct _GJRecodeContext *context, GJAudioFormat format);
    GVoid (*sendVideoSourcePacket)(struct _GJRecodeContext *context, R_GJPixelFrame *packet);
    GVoid (*sendAudioSourcePacket)(struct _GJRecodeContext *context, R_GJPCMFrame *packet);
    GBool (*startRecode)(struct _GJRecodeContext *context);
    GVoid (*stopRecode)(struct _GJRecodeContext *context);

} GJRecodeContext;

typedef struct _GJPictureDisplayContext {
    GHandle obaque;
    GBool (*displaySetup)(struct _GJPictureDisplayContext *context);
    GVoid (*displayUnSetup)(struct _GJPictureDisplayContext *context);
    GVoid (*renderFrame)(struct _GJPictureDisplayContext *context, R_GJPixelFrame *image);
    GHandle (*getDispayView)(struct _GJPictureDisplayContext *context);
} GJPictureDisplayContext;

typedef struct _GJVideoProduceContext {
    GJPipleNode pipleNode;
    GHandle     obaque;
    GBool (*videoProduceSetup)(struct _GJVideoProduceContext *context, VideoFrameOutCallback callback, GHandle userData);
    GVoid (*videoProduceUnSetup)(struct _GJVideoProduceContext *context);
    GBool (*startProduce)(struct _GJVideoProduceContext *context);
    GVoid (*stopProduce)(struct _GJVideoProduceContext *context);
    GBool (*startPreview)(struct _GJVideoProduceContext *context);
    GBool (*setARScene)(struct _GJVideoProduceContext *context, GHandle scene);
    GBool (*setCaptureView)(struct _GJVideoProduceContext *context, GView view);
    GBool (*setCaptureType)(struct _GJVideoProduceContext *context, GJCaptureType type);

    GVoid (*stopPreview)(struct _GJVideoProduceContext *context);
    GHandle (*getRenderView)(struct _GJVideoProduceContext *context);
    GSize (*getCaptureSize)(struct _GJVideoProduceContext *context);
    GBool (*setCameraPosition)(struct _GJVideoProduceContext *context, GJCameraPosition cameraPosition);
    GBool (*setOrientation)(struct _GJVideoProduceContext *context, GJInterfaceOrientation outOrientation);
    GBool (*setHorizontallyMirror)(struct _GJVideoProduceContext *context, GBool mirror);
    GBool (*setPreviewMirror)(struct _GJVideoProduceContext *context, GBool mirror);
    GBool (*setStreamMirror)(struct _GJVideoProduceContext *context, GBool mirror);

    GBool (*setFrameRate)(struct _GJVideoProduceContext *context, GInt32 fps);
    GHandle (*getFreshDisplayImage)(struct _GJVideoProduceContext *context);

    GBool (*addSticker)(struct _GJVideoProduceContext *context, const GVoid *overlays, GInt32 fps, GJStickerUpdateCallback callback, const GVoid *userData);
    GVoid (*chanceSticker)(struct _GJVideoProduceContext *context);

    GBool (*startTrackImage)(struct _GJVideoProduceContext *context, const GVoid *images, GCRect initFrame);
    GVoid (*stopTrackImage)(struct _GJVideoProduceContext *context);
    GVoid (*setDropStep)(struct _GJVideoProduceContext *context, GRational videoDropStep);
    GBool (*setMute)(struct _GJVideoProduceContext *context, GBool enable);
    GBool (*setPixelformat)(struct _GJVideoProduceContext *context,const GJPixelFormat* format);
    GJPixelFormat (*getPixelformat)(struct _GJVideoProduceContext *context);

} GJVideoProduceContext;

typedef struct _GJAudioProduceContext {
    GJPipleNode pipleNode;
    GHandle     obaque;
    GBool (*audioProduceSetup)(struct _GJAudioProduceContext *context, AudioFrameOutCallback callback, GHandle userData);
    GVoid (*audioProduceUnSetup)(struct _GJAudioProduceContext *context);
    GBool (*setAudioFormat)(struct _GJAudioProduceContext *context, GJAudioFormat format);
    GBool (*audioProduceStart)(struct _GJAudioProduceContext *context);
    GVoid (*audioProduceStop)(struct _GJAudioProduceContext *context);
    GBool (*enableAudioInEarMonitoring)(struct _GJAudioProduceContext *context, GBool enable);
    GBool (*enableAudioEchoCancellation)(struct _GJAudioProduceContext *context, GBool enable);
    GBool (*setupMixAudioFile)(struct _GJAudioProduceContext *context, const GChar *file, GBool loop, AudioMixFinishCallback callback, GHandle userData);
    GBool (*startMixAudioFileAtTime)(struct _GJAudioProduceContext *context, GUInt64 time);
    GBool (*setInputGain)(struct _GJAudioProduceContext *context, GFloat inputGain);
    GBool (*setMixVolume)(struct _GJAudioProduceContext *context, GFloat volume);
    GBool (*setOutVolume)(struct _GJAudioProduceContext *context, GFloat volume);
    GVoid (*stopMixAudioFile)(struct _GJAudioProduceContext *context);
    GBool (*setMixToStream)(struct _GJAudioProduceContext *context, GBool should);
    GBool (*enableReverb)(struct _GJAudioProduceContext *context, GBool enable);
    GBool (*enableMeasurementMode)(struct _GJAudioProduceContext *context, GBool enable);
    GBool (*setMute)(struct _GJAudioProduceContext *context, GBool enable);

} GJAudioProduceContext;

typedef struct _GJAudioPlayContext {
    GHandle obaque;
    GBool (*audioPlaySetup)(struct _GJAudioPlayContext *context, GJAudioFormat format, FillDataCallback dataCallback, GHandle userData);
    GVoid (*audioPlayUnSetup)(struct _GJAudioPlayContext *context);
    GVoid (*audioPlayCallback)(struct _GJAudioPlayContext *context, GHandle audioData, GInt32 size);
    GVoid (*audioStop)(struct _GJAudioPlayContext *context);
    GBool (*audioStart)(struct _GJAudioPlayContext *context);
    GVoid (*audioPause)(struct _GJAudioPlayContext *context);
    GBool (*audioResume)(struct _GJAudioPlayContext *context);
    GBool (*audioSetSpeed)(struct _GJAudioPlayContext *context, GFloat speed);
    GFloat (*audioGetSpeed)(struct _GJAudioPlayContext *context);
    GJPlayStatus (*audioGetStatus)(struct _GJAudioPlayContext *context);
} GJAudioPlayContext;

typedef struct _GJEncodeToAACContext {
    GJPipleNode pipleNode;
    GHandle     obaque;
    GBool (*encodeSetup)(struct _GJEncodeToAACContext *context, GJAudioFormat sourceFormat, GJAudioStreamFormat destForamt, AACPacketOutCallback callback, GHandle userData);
    GVoid (*encodeUnSetup)(struct _GJEncodeToAACContext *context);
    GVoid (*encodeFlush)(struct _GJEncodeToAACContext *context);
    GVoid (*encodeFrame)(struct _GJEncodeToAACContext *context, R_GJPCMFrame *frame);
    AACPacketOutCallback encodeCompleteCallback;
} GJEncodeToAACContext;

typedef struct _FFAudioDecodeContext {
    GJPipleNode pipleNode;
    GHandle     obaque;

    GBool (*decodeSetup)(struct _FFAudioDecodeContext *context, GJAudioFormat destForamt, AudioFrameOutCallback callback, GHandle userData);
    GVoid (*decodeUnSetup)(struct _FFAudioDecodeContext *context);
    GBool (*decodeStart)(struct _FFAudioDecodeContext *context);
    GVoid (*decodeStop)(struct _FFAudioDecodeContext *context);
    GBool (*decodePacket)(struct _FFAudioDecodeContext *context, R_GJPacket *packet);
    GJAudioFormat (*decodeGetDestFormat)(struct _FFAudioDecodeContext *context);

} FFAudioDecodeContext;

typedef struct _FFVideoDecodeContext {
    GJPipleNode           pipleNode;
    GHandle               obaque;
    VideoFrameOutCallback callback;
    GHandle               userData;
    GBool (*decodeSetup)(struct _FFVideoDecodeContext *context, GJPixelType format, VideoFrameOutCallback callback, GHandle userData);
    GVoid (*decodeUnSetup)(struct _FFVideoDecodeContext *context);
    GBool (*decodeStart)(struct _FFVideoDecodeContext *context);
    GVoid (*decodeStop)(struct _FFVideoDecodeContext *context);
    GVoid (*decodeFlush)(struct _FFVideoDecodeContext *context);
    GBool (*decodePacket)(struct _FFVideoDecodeContext *context, R_GJPacket *packet);
} FFVideoDecodeContext;

typedef struct _GJEncodeToH264eContext {
    GJPipleNode pipleNode;
    GHandle     obaque;
    GBool (*encodeSetup)(struct _GJEncodeToH264eContext *context, GJPixelFormat format, H264PacketOutCallback callback, GHandle userData);
    GVoid (*encodeUnSetup)(struct _GJEncodeToH264eContext *context);
    GBool (*encodeFrame)(struct _GJEncodeToH264eContext *context, R_GJPixelFrame *frame);
    GBool (*encodeSetBitrate)(struct _GJEncodeToH264eContext *context, GInt32 bitrate);
    GBool (*encodeSetProfile)(struct _GJEncodeToH264eContext *context, ProfileLevel profile);
    GBool (*encodeSetEntropy)(struct _GJEncodeToH264eContext *context, EntropyMode model);
    GBool (*encodeSetGop)(struct _GJEncodeToH264eContext *context, GInt32 gop);
    GBool (*encodeAllowBFrame)(struct _GJEncodeToH264eContext *context, GBool allowBframe);
    GBool (*encodeGetSPS_PPS)(struct _GJEncodeToH264eContext *context, GUInt8 *sps, GInt32 *spsSize, GUInt8 *pps, GInt32 *ppsSize);
    GVoid (*encodeFlush)(struct _GJEncodeToH264eContext *context);

    H264PacketOutCallback encodeCompleteCallback;
} GJEncodeToH264eContext;

extern GVoid GJ_AudioProduceContextCreate(GJAudioProduceContext **context);
extern GVoid GJ_VideoProduceContextCreate(GJVideoProduceContext **context);
extern GVoid GJ_AACDecodeContextCreate(FFAudioDecodeContext **context);
extern GVoid GJ_H264DecodeContextCreate(FFVideoDecodeContext **context);
extern GVoid GJ_AACEncodeContextCreate(GJEncodeToAACContext **context);
extern GVoid GJ_H264EncodeContextCreate(GJEncodeToH264eContext **context);
extern GVoid GJ_FFDecodeContextCreate(FFVideoDecodeContext **context);
extern GVoid GJ_AudioPlayContextCreate(GJAudioPlayContext **context);
extern GVoid GJ_PictureDisplayContextCreate(GJPictureDisplayContext **context);

extern GVoid GJ_AudioProduceContextDealloc(GJAudioProduceContext **context);
extern GVoid GJ_VideoProduceContextDealloc(GJVideoProduceContext **context);
extern GVoid GJ_AACDecodeContextDealloc(FFAudioDecodeContext **context);
extern GVoid GJ_H264DecodeContextDealloc(FFVideoDecodeContext **context);
extern GVoid GJ_FFDecodeContextDealloc(FFVideoDecodeContext **context);
extern GVoid GJ_AACEncodeContextDealloc(GJEncodeToAACContext **context);
extern GVoid GJ_H264EncodeContextDealloc(GJEncodeToH264eContext **context);
extern GVoid GJ_AudioPlayContextDealloc(GJAudioPlayContext **context);
extern GVoid GJ_PictureDisplayContextDealloc(GJPictureDisplayContext** context);

#endif /* GJPictureDisplayContext_h */
