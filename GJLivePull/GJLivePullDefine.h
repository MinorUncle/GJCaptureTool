//
//  GJLivePullDefine.h
//  GJCaptureTool
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJLivePullDefine_h
#define GJLivePullDefine_h





//消息类型
typedef enum _LivePullMessageType{
    kLivePullMessageUnknown,
    
    kLivePullUnknownError = 0,
    kLivePullStopPullError,//停止推流失败
    kLivePullConnectError,//连接失败
    kLivePullRecodeError,  //视频录制失败
    
    kLivePullConnectSuccess , //推流成功，其他类型为nil,对KKPull_PROTOCOL_ZEGO， info:为NSDictionary类型,包含推流地址 ----重要
    kLivePullPullUpdataFps,         //视频fps更新                                info：@(float)
    kLivePullPullUpdataBitrate,     //视频推送码率更新                             info：@(float)  Byte/s
    kLivePullPullUpdataQuality,     //视频推送质量更新， 0 ~ 3 分别对应优良中差        info：@(int)
    kLivePullRecodeCompletedSuccess, //视频录制完成，                              info：nil
}LivePullMessageType;

#endif /* GJLivePullDefine_h */
