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

typedef GVoid (*AACDecodeCompleteCallback) (GHandle userData,R_GJPCMFrame* frame);
typedef GVoid (*AACEncodeCompleteCallback) (GHandle userData,R_GJAACPacket* packet);

typedef GVoid (*H264DecodeCompleteCallback) (GHandle userData,R_GJPixelFrame* frame);
typedef GVoid (*H264EncodeCompleteCallback) (GHandle userData,R_GJH264Packet* packet);

typedef struct _GJPictureDisplayContext{
    GHandle obaque;
    GBool (*displaySetup) (struct _GJPictureDisplayContext* context);
    GBool (*displaySetFormat) (struct _GJPictureDisplayContext* context,GJPixelType format);
    GVoid (*displayDealloc) (struct _GJPictureDisplayContext* context);
    GVoid (*displayView) (struct _GJPictureDisplayContext* context,GJRetainBuffer* image);
    GHandle (*getDispayView) (struct _GJPictureDisplayContext* context);

}GJPictureDisplayContext;

typedef struct _GJAudioPlayContext{
    GHandle obaque;
    GBool (*audioPlaySetup) (struct _GJAudioPlayContext* context,GJAudioFormat format);
    GVoid (*audioPlayDealloc) (struct _GJAudioPlayContext* context);
    GVoid (*audioPlayCallback) (struct _GJAudioPlayContext* context,GHandle audioData,GInt32 size);
    GVoid (*audioStop)(struct _GJAudioPlayContext* context);
    GBool (*audioStart)(struct _GJAudioPlayContext* context);
    GVoid (*audioPause)(struct _GJAudioPlayContext* context);
    GBool (*audioResume)(struct _GJAudioPlayContext* context);
    GBool (*audioSetSpeed)(struct _GJAudioPlayContext* context,GFloat32 speed);
    GFloat32 (*audioGetSpeed)(struct _GJAudioPlayContext* context);
}GJAudioPlayContext;
typedef struct _GJEncodeToAACContext{
    GHandle obaque;
    GBool (*encodeSetup) (struct _GJEncodeToAACContext* context,GJPixelFormat format);
    GBool (*encodeRelease) (struct _GJEncodeToAACContext* context);
    GVoid (*encodeFrame) (struct _GJEncodeToAACContext* context,R_GJPCMFrame* frame);
    GBool (*encodeSetBitrate) (struct _GJEncodeToAACContext* context,GInt32 bitrate);
    AACEncodeCompleteCallback encodeCompleteCallback;
}GJEncodeToAACContext;
typedef struct _GJAACDecodeContext{
    GHandle obaque;
    GBool (*decodeSetup) (struct _GJAACDecodeContext* context,GJAudioFormat sourceFormat,GJAudioFormat destForamt,AACDecodeCompleteCallback callback,GHandle userData);
    GVoid (*decodeRelease) (struct _GJAACDecodeContext* context);
    GBool (*decodePacket) (struct _GJAACDecodeContext* context,R_GJAACPacket* packet);
    AACDecodeCompleteCallback decodeeCompleteCallback;
}GJAACDecodeContext;
typedef struct _GJH264DecodeContext{
    GHandle obaque;
    GBool (*decodeSetup) (struct _GJH264DecodeContext* context,GJPixelType format,H264DecodeCompleteCallback callback,GHandle userData);
    GVoid (*decodeRelease) (struct _GJH264DecodeContext* context);
    GBool (*decodePacket) (struct _GJH264DecodeContext* context,R_GJH264Packet* packet);
    H264DecodeCompleteCallback decodeeCompleteCallback;
}GJH264DecodeContext;
typedef struct _GJEncodeToH264eContext{
    GHandle obaque;
    GBool (*encodeSetup) (struct _GJEncodeToH264eContext* context,GJPixelFormat format);
    GBool (*encodeRelease) (struct _GJEncodeToH264eContext* context);
    GBool (*encodePacket) (struct _GJEncodeToH264eContext* context,R_GJH264Packet* packet);
    H264EncodeCompleteCallback encodeCompleteCallback;
    GBool (*encodeSetBitrate) (struct _GJEncodeToH264eContext* context,GInt32 bitrate);

}GJEncodeToH264eContext;
#endif /* GJPictureDisplayContext_h */
