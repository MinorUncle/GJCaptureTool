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
typedef struct GJPushConfig {
    //    video 。videoFps;等于采集的fps,pushSize与capturesize不同时会保留最大裁剪缩放
    CGSize      pushSize;
    CGFloat     videoBitRate;
    
    //  audio
    NSInteger   channel;
    NSInteger   audioSampleRate;
    
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
typedef NS_ENUM(NSInteger,GJLiveStreamFlipDirection) {
    LiveStreamFlipDirection_Default = 0x1 << 0,  //恢复默认状态
    LiveStreamFlipDirection_Horizontal = 0x1 << 1,
    LiveStreamFlipDirection_Vertical = 0x1 << 2
};

//消息类型
typedef enum _LivePushMessageType{
    kLivePushUnknownMessage = 0,
    
    kLivePushConnentError,//推流失败                    info:nsstring or nil
    kLivePushStopPushError,//停止推流失败                     同上
    kLivePushConnectError,//连接失败                        同上
    kLivePushConnectTimeOutError,//连接超时                     同上
    kLivePushRecodeError,  //视频录制失败                     同上
    
    kLivePushCloseSuccess,
    kLivePushConnectSuccess , //推流成功，其他类型为nil,对KKPUSH_PROTOCOL_ZEGO， info:为NSDictionary类型,包含推流地址 ----重要
    kLivePushUpdataFps,         //视频fps更新                                info：@(float)
    kLivePushUpdataBitrate,     //视频推送码率更新                             info：@(float)  Byte/s
    kLivePushUpdataQuality,     //视频推送质量更新， 0 ~ 3 分别对应优良中差        info：@(int)
    kLivePushRecodeCompletedSuccess, //视频录制完成，                              info：nil
}LivePushMessageType;
#endif /* GJLiveDefine_h */
