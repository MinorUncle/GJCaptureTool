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

@interface GJStickerAttribute : NSObject
@property(assign,nonatomic)GCRect frame;
@property(assign,nonatomic)CGFloat rotate;//绕frame的center旋转,0-360

+(instancetype)stickerAttributWithFrame:(GCRect)frame rotate:(CGFloat)rotate;
@end
typedef GJStickerAttribute*(^StickersUpdate)(NSInteger index,BOOL* ioFinish);



@interface GJLivePush : NSObject
@property(nonatomic,assign)GJCameraPosition cameraPosition;

@property(nonatomic,assign)GJInterfaceOrientation outOrientation;

@property(nonatomic,assign)BOOL mixFileNeedToStream;


@property(nonatomic,strong,readonly,getter=getPreviewView)UIView* previewView;

//@property(nonatomic,assign,readonly)CaptureSizeType caputreSizeType;

@property(nonatomic,assign,readonly)GJPushConfig pushConfig;

//只读，根据pushConfig中的push size自动选择最优.outOrientation 和 pushsize会改变改值，
@property(nonatomic,assign,readonly)CGSize captureSize;

@property(nonatomic,weak)id<GJLivePushDelegate> delegate;

@property(nonatomic,assign)BOOL videoMute;
@property(nonatomic,assign)BOOL audioMute;
@property(nonatomic,assign)BOOL measurementMode;


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



/**
 贴图，如果存在则取消已存在的

 @param images 需要贴的图片集合
 @param attribure 用于整体的的属性，每帧可以通过updateBlock更新
 @param fps 贴图更新的帧率
 @param updateBlock 每次更新的回调，index表示当前更新的图片，ioFinish表示是否结束，输入输出值。
 @return 是否成功
 */
- (BOOL)startStickerWithImages:(NSArray<UIImage*>*)images attribure:(GJStickerAttribute*)attribure fps:(NSInteger)fps updateBlock:(StickersUpdate)updateBlock;


/**
 主动停止贴图。也可以通过addStickerWithImages的updateBlock，赋值ioFinish true来停止，不过该方法只能在更新的时候使用，可能会有延迟，fps越小延迟越大。
 */
- (void)chanceSticker;
//- (void)videoRecodeWithPath:(NSString*)path;



@end
