//
//  GJLivePush.h
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GJLiveDefine.h"
#import <CoreVideo/CVImageBuffer.h>
#import <CoreMedia/CMTime.h>
#import "GJLiveDefine+internal.h"
#import <AVFoundation/AVFoundation.h>
@class UIView;
@class GJLivePush;
@protocol GJLivePushDelegate <NSObject>
@required


-(void)livePush:(GJLivePush*)livePush updatePushStatus:(GJPushSessionStatus*)status;
-(void)livePush:(GJLivePush*)livePush closeConnent:(GJPushSessionInfo*)info resion:(GJConnentCloceReason)reason;
-(void)livePush:(GJLivePush*)livePush connentSuccessWithElapsed:(GLong)elapsed;
-(void)livePush:(GJLivePush*)livePush dynamicVideoUpdate:(VideoDynamicInfo*)elapsed;
-(void)livePush:(GJLivePush*)livePush UIRecodeFinish:(NSError*)error;
-(void)livePush:(GJLivePush*)livePush errorType:(GJLiveErrorType)type infoDesc:(NSString*)info;
//-(void)livePush:(GJLivePush*)livePush pushPacket:(R_GJH264Packet*)packet;
//-(void)livePush:(GJLivePush*)livePush pushImagebuffer:(CVImageBufferRef)packet pts:(CMTime)pts;


@optional

@end

#import "GJLivePlayer.h"

@interface GJLivePush : NSObject
@property(nonatomic,assign)GJCameraPosition cameraPosition;

@property(nonatomic,assign)GJInterfaceOrientation outOrientation;

@property(nonatomic,assign)BOOL mixFileNeedToStream;


@property(nonatomic,strong,readonly,getter=getPreviewView)UIView* previewView;

//@property(nonatomic,assign,readonly)CaptureSizeType caputreSizeType;

@property(nonatomic,assign,readonly)GJPushConfig pushConfig;

@property(nonatomic,weak)id<GJLivePushDelegate> delegate;

@property(nonatomic,assign)BOOL videoMute;
@property(nonatomic,assign)BOOL audioMute;

//- (bool)startCaptureWithSizeType:(CaptureSizeType)sizeType fps:(NSInteger)fps position:(enum AVCaptureDevicePosition)cameraPosition;

//- (void)stopCapture;

- (void)startPreview;

- (void)stopPreview;

- (bool)startStreamPushWithUrl:(NSString *)url;

- (void)setPushConfig:(GJPushConfig)pushConfig;

- (void)stopStreamPush;

- (BOOL)enableAudioInEarMonitoring:(BOOL)enable;

- (BOOL)enableReverb:(BOOL)enable;

- (BOOL)startAudioMixWithFile:(NSURL*)fileUrl;

- (void)stopAudioMix;

- (void)setInputVolume:(float)volume;

- (void)setMixVolume:(float)volume;

- (void)setMasterOutVolume:(float)volume;

- (BOOL)startUIRecodeWithRootView:(UIView*)view fps:(NSInteger)fps filePath:(NSURL*)file;

- (void)stopUIRecode;


//- (void)videoRecodeWithPath:(NSString*)path;



@end
