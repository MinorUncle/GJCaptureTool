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
typedef struct _GJPictureDisplayContext{
    GHandle obaque;
    GBool (*displayCreate) (struct _GJPictureDisplayContext* context,GJPixelFormat format);
    GBool (*displayRelease) (struct _GJPictureDisplayContext* context);
    GVoid (*displayView) (struct _GJPictureDisplayContext* context,GJRetainBuffer* image);
}GJPictureDisplayContext;

typedef struct _GJAudioPlayContext{
    GHandle obaque;
    GBool (*audioPlayCreate) (struct _GJAudioPlayContext* context,GJAudioFormat format);
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
    GBool (*encodeCreate) (struct _GJEncodeToAACContext* context,GJPixelFormat format);
    GBool (*encodeRelease) (struct _GJEncodeToAACContext* context);
    GVoid (*encodeFrame) (struct _GJEncodeToAACContext* context,R_GJFrame* frame);
    GVoid (*encodeComplete) (struct _GJEncodeToAACContext* context,R_GJAACPacket* packet);
    GBool (*encodeSetBitrate) (struct _GJEncodeToAACContext* context,GInt32 bitrate);
}GJEncodeToAACContext;
typedef struct _GJAACDecodeContext{
    GHandle obaque;
    GBool (*decodeCreate) (struct _GJAACDecodeContext* context,GJPixelFormat format);
    GVoid (*decodeRelease) (struct _GJAACDecodeContext* context);
    GBool (*decodePacket) (struct _GJAACDecodeContext* context,R_GJAACPacket* packet);
    GVoid (*decodeComplete) (struct _GJAACDecodeContext* context,R_GJFrame* frame);
}GJAACDecodeContext;
typedef struct _GJH264DecodeContext{
    GHandle obaque;
    GBool (*decodeCreate) (struct _GJH264DecodeContext* context,GJPixelFormat format);
    GVoid (*decodeRelease) (struct _GJH264DecodeContext* context);
    GBool (*decodePacket) (struct _GJH264DecodeContext* context,R_GJH264Packet* packet);
    GVoid (*decodeComplete) (struct _GJH264DecodeContext* context,R_GJFrame* frame);
}GJH264DecodeContext;
typedef struct _GJEncodeToH264eContext{
    GHandle obaque;
    GBool (*encodeCreate) (struct _GJEncodeToH264eContext* context,GJPixelFormat format);
    GBool (*encodeRelease) (struct _GJEncodeToH264eContext* context);
    GBool (*encodePacket) (struct _GJEncodeToH264eContext* context,R_GJH264Packet* packet);
    GVoid (*encodeComplete) (struct _GJEncodeToH264eContext* context,R_GJFrame* frame);
    GBool (*encodeSetBitrate) (struct _GJEncodeToH264eContext* context,GInt32 bitrate);

}GJEncodeToH264eContext;
#endif /* GJPictureDisplayContext_h */
