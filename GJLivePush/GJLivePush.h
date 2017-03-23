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
 直播信息回调，当直播类型为KKPUSH_PROTOCOL_ZEGO时，直播地址从这里回调(重要).
 
 @param livePush livePush description
 @param type 信息type，
 @param infoDesc 信息值，具体类型见LivePushInfoType
 */
-(void)livePush:(GJLivePush*)livePush messageType:(LivePushMessageType)type infoDesc:(id)infoDesc;


-(void)livePush:(GJLivePush*)livePush frameRate:(long)frameRate bitrate:(long)bitrate quality:(long)quality delay:(long)delay;

@optional

@end


@interface GJLivePush : NSObject
@property(nonatomic,assign)enum AVCaptureDevicePosition cameraPosition;

@property(nonatomic,strong,readonly,getter=getPreviewView)UIView* previewView;

@property(nonatomic,assign,readonly)CaptureSizeType caputreSizeType;

@property(nonatomic,assign,readonly)NSInteger captureFps;

@property(nonatomic,weak)id<GJLivePushDelegate> delegate;

//push status,
#define kLIVEPUSH_CONNECT 1<<0
#define kLIVEPUSH_PREVIEW 1<<1
#define kLIVEPUSH_CAPTURE 1<<2

@property(nonatomic,assign,readonly)int status;


- (bool)startCaptureWithSizeType:(CaptureSizeType)sizeType fps:(NSInteger)fps position:(enum AVCaptureDevicePosition)cameraPosition;

- (void)stopCapture;

- (void)startPreview;

- (void)stopPreview;

- (bool)startStreamPushWithConfig:(GJPushConfig)config;

- (void)stopStreamPush;



@end
