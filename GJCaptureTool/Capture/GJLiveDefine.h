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
    //    video 。videoFps;等于采集的fps
    CGSize      pushSize;
    CGFloat     videoBitRate;
    
    //  audio
    NSInteger   channel;
    NSInteger   audioSampleRate;
    
    char       pushUrl[100];
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
#endif /* GJLiveDefine_h */
