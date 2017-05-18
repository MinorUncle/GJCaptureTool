//
//  GJLiveDefine.h
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJLiveDefine_h
#define GJLiveDefine_h
#import <CoreGraphics/CGGeometry.h>
#import "GJRetainBuffer.h"

//网络延迟收集，只有在同一收集同时推拉流才准确
//#define NETWORK_DELAY

//#define GJVIDEODECODE_TEST

typedef struct GJPushConfig {
    //    video 。videoFps;等于采集的fps,pushSize与capturesize不同时会保留最大裁剪缩放
    CGSize      pushSize;
    CGFloat     videoBitRate;
    
    //  audio
    int   channel;
    int   audioSampleRate;
    
    char       *pushUrl;
}GJPushConfig;
typedef enum _CaptureSizeType
{
    kCaptureSize352_288,
    kCaptureSize640_480,
    kCaptureSize1280_720,
    kCaptureSize1920_1080,
    kCaptureSize3840_2160
}CaptureSizeType;

//视频流的翻转角度
typedef enum LiveStreamFlipDirection {
    kLiveStreamFlipDirection_Default = 0x1 << 0,  //恢复默认状态
    kLiveStreamFlipDirection_Horizontal = 0x1 << 1,
    kLiveStreamFlipDirection_Vertical = 0x1 << 2
}GJLiveStreamFlipDirection;

//消息类型
typedef enum _LiveInfoType{
    kLivePushUnknownInfo = 0,
    
    kLivePushCloseSuccess,
   kLivePushConnectSuccess , //推流成功，
    //推流信息
    //(GJPushStatus*)
    kLivePushUpdateStatus,
    kLivePushDecodeFristFrame,
    
    kLivePullCloseSuccess,
    kLivePullConnectSuccess , //推流成功，
    kLivePullDecodeFristFrame,
    //拉流信息
    //(GJPullStatus*)
    kLivePullUpdateStatus,
}GJLiveInfoType;

typedef enum _LiveErrorType{
    kLivePushUnknownError = 0,
    
    kLivePushConnectError,//推流失败                    info:nsstring or nil
    kLivePushWritePacketError,

    kLivePullConnectError,//拉流连接失败                    
    kLivePullReadPacketError,//
}GJLiveErrorType;


typedef enum _GJNetworkQuality{
    GJNetworkQualityExcellent=0,
    GJNetworkQualityGood,
    GJNetworkQualitybad,
    GJNetworkQualityTerrible,
}GJNetworkQuality;
typedef struct PushInfo{
    float bitrate;//byte/s
    float frameRate;//
    long  cacheTime;
    long  cacheCount;
}GJPushInfo;
typedef struct PullInfo{
    float bitrate;//byte/s
    float frameRate;//
    long  cacheTime;
    long  cacheCount;
}GJPullInfo;

typedef struct PushSessionStatus{
    GJPushInfo videoStatus;
    GJPushInfo audioStatus;
    GJNetworkQuality netWorkQuarity;
   
}GJPushSessionStatus;
typedef struct PullSessionStatus{
    GJPullInfo videoStatus;
    GJPullInfo audioStatus;
}GJPullSessionStatus;
typedef struct _PushSessionInfo{
    long sendFrameCount;
    long dropFrameCount;
    long sessionDuring;
}GJPushSessionInfo;
typedef enum _ConnentCloceReason{
    kConnentCloce_Active,//主动关闭
    kConnentCloce_Drop,//掉线
}GJConnentCloceReason;
typedef struct _PullSessionInfo{
    long pullFrameCount;
    long dropFrameCount;
    long sessionDuring;
    long buffingTimes;
    long buffingCount;
}GJPullSessionInfo;

typedef struct _PullFristFrameInfo{
    CGSize size;
}GJPullFristFrameInfo;

typedef enum {
    GJPixelType_32BGRA                   ,
    GJPixelType_YpCbCr8Planar            ,                  //yyyyyyyyuuvv
    GJPixelType_YpCbCr8BiPlanar          ,      //yyyyyyyyuvuv
    GJPixelType_YpCbCr8Planar_Full       ,         //yyyyyyyyuuvv
    GJPixelType_YpCbCr8BiPlanar_Full     ,       //yyyyyyyyuvuv
} GJPixelType;
typedef enum {
    GJAudioType_AAC,
    GJAudioType_PCM,
}GJAudioType;
typedef struct _GJAudioFormat{
    GJAudioType         mType;
    GUInt32             mSampleRate;
    GUInt32             mChannelsPerFrame;
    GUInt32             mBitsPerChannel;
    GUInt32             mFramePerPacket;
    GUInt32             mFormatFlags;
}GJAudioFormat;
typedef struct _GJPixelFormat{
    GJPixelType         mType;
    GUInt32             mHeight;
    GUInt32             mWidth;
}GJPixelFormat;
#endif /* GJLiveDefine_h */
