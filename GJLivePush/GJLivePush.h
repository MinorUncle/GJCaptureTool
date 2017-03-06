//
//  GJLivePush.h
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GJLivePushDefine.h"

enum AVCaptureDevicePosition;
@class UIView;
@class GJLivePush;

@protocol GJLivePushDelegate <NSObject>
@required
/**
 推流停止错误回调
 
 @param type 错误类型
 @param errorDesc 描述
 */
-(void)livePush:(GJLivePush*)livePush errorType:(LivePushErrorType)type errorDesc:(NSString*)errorDesc;



/**
 直播信息回调，当直播类型为KKPUSH_PROTOCOL_ZEGO时，直播地址从这里回调(重要).
 
 @param livePush livePush description
 @param type 信息type，
 @param infoDesc 信息值，具体类型见LivePushInfoType
 */
-(void)livePush:(GJLivePush*)livePush infoType:(LivePushInfoType)type infoDesc:(id)infoDesc;

@optional

@end


@interface GJLivePush : NSObject
@property(nonatomic,assign)enum AVCaptureDevicePosition cameraPosition;

@property(nonatomic,strong,readonly,getter=getPreviewView)UIView* previewView;

@property(nonatomic,assign,readonly)CaptureSizeType caputreSizeType;

@property(nonatomic,assign,readonly)NSInteger captureFps;

@property(nonatomic,weak)id<GJLivePushDelegate> delegate;


- (bool)startCaptureWithSizeType:(CaptureSizeType)sizeType fps:(NSInteger)fps position:(enum AVCaptureDevicePosition)cameraPosition;

- (void)stopCapture;

- (void)startPreview;

- (void)stopPreview;

- (bool)startStreamPushWithConfig:(GJPushConfig)config;

- (void)stopStreamPush;



@end
