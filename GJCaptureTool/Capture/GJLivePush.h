//
//  GJLivePush.h
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GJLiveDefine.h"

enum AVCaptureDevicePosition;
@class UIView;

@interface GJLivePush : NSObject
@property(nonatomic,assign)enum AVCaptureDevicePosition cameraPosition;

@property(nonatomic,strong,readonly,getter=getPreviewView)UIView* previewView;

@property(nonatomic,assign,readonly)CaptureSizeType caputreSizeType;

@property(nonatomic,assign,readonly)NSInteger captureFps;

- (bool)startCaptureWithSizeType:(CaptureSizeType)sizeType fps:(NSInteger)fps position:(enum AVCaptureDevicePosition)cameraPosition;

- (void)stopCapture;

- (void)startPreview;

- (void)stopPreview;

- (bool)startStreamPushWithConfig:(GJPushConfig)config;

- (void)stopStreamPush;



@end
