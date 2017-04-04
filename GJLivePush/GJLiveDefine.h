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
#define NETWORK_DELAY



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


typedef struct PushStatus{
    int cacheTime;//ms,包括音频和视频，下同
    int cacheCount;
    int netWorkQuarity;
    int bitrate;//kB/s
    int frameRate;//fps,video
}GJPushStatus;
typedef struct PullStatus{
    int videoCacheTime;//ms
    int videoCacheCount;
    int audioCacheTime;//ms
    int audioCacheCount;
    int bitrate;//kB/s
}GJPullStatus;
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

typedef struct CacheInfo{
    int cacheTime;//ms
    int cacheCount;
}GJCacheInfo;

typedef struct H264Packet{
    GJRetainBuffer* memBlock;
    int pts;
    uint8_t* sps;
    int spsSize;
    uint8_t* pps;
    int ppsSize;
    uint8_t* pp;
    int ppSize;
    uint8_t* sei;
    int seiSize;
}GJH264Packet;
typedef struct AACPacket{
    GJRetainBuffer* memBlock;
    int pts;
    uint8_t* adts;
    int adtsSize;
}GJAACPacket;
#endif /* GJLiveDefine_h */
