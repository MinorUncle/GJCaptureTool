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

@class ARSCNView;
typedef void(^ARUpdateBlock)();
@protocol GJImageARScene <NSObject>
@required
@property(nonatomic,retain,readonly) ARSCNView* _Nullable scene;
@property(nonatomic,assign) NSInteger updateFps;
@property(readonly, nonatomic) BOOL isRunning;
@property(nonatomic,assign) ARUpdateBlock _Nullable updateBlock;

- (AVCaptureDevicePosition)cameraPosition;
- (void)rotateCamera;

-(BOOL)startRun;
-(void)stopRun;
-(void)pause;
-(BOOL)resume;
@end

@protocol GJLivePushDelegate <NSObject>
@required

-(void)livePush:(GJLivePush*_Nonnull)livePush mixFileFinish:(NSString*_Nonnull)path;
-(void)livePush:(GJLivePush*_Nonnull)livePush updatePushStatus:(GJPushSessionStatus*_Nonnull)status;
-(void)livePush:(GJLivePush*_Nonnull)livePush closeConnent:(GJPushSessionInfo*_Nonnull)info resion:(GJConnentCloceReason)reason;
-(void)livePush:(GJLivePush*_Nonnull)livePush connentSuccessWithElapsed:(GLong)elapsed;
-(void)livePush:(GJLivePush*_Nonnull)livePush dynamicVideoUpdate:(VideoDynamicInfo*_Nonnull)elapsed;
-(void)livePush:(GJLivePush*_Nonnull)livePush recodeFinish:(NSError*_Nullable)error;
-(void)livePush:(GJLivePush*_Nonnull)livePush errorType:(GJLiveErrorType)type infoDesc:(NSString*_Nonnull)info;
//-(void)livePush:(GJLivePush*)livePush pushPacket:(R_GJH264Packet*)packet;
//-(void)livePush:(GJLivePush*)livePush pushImagebuffer:(CVImageBufferRef)packet pts:(CMTime)pts;


@optional

@end



@interface GJOverlayAttribute : NSObject
//注意，frame的origin是中点
@property(assign,nonatomic)CGRect frame;
@property(assign,nonatomic)CGFloat rotate;
//注意image更新后，每次该index循环都是更新后的图片
@property(retain,nonatomic) UIImage* _Nonnull  image;

+(instancetype _Nonnull )overlayAttributeWithImage:(UIImage* _Nonnull)image frame:(CGRect)frame rotate:(CGFloat)rotate;
@end
typedef void(^OverlaysUpdate)(NSInteger index,const GJOverlayAttribute* _Nullable ioAttr,BOOL* _Nonnull ioFinish);



@interface GJLivePush : NSObject
@property (nonatomic,assign         ) GJCameraPosition       cameraPosition;

@property (nonatomic,assign         ) BOOL       previewMirror;//预览镜像，不镜像流

@property (nonatomic,assign         ) BOOL       streamMirror;//流镜像，不影响预览

@property (nonatomic,assign         ) BOOL       cameraMirror;//相机镜像，影响预览和流

@property (nonatomic,assign         ) GJInterfaceOrientation outOrientation;

@property (nonatomic,assign         ) BOOL                   mixFileNeedToStream;


@property (nonatomic,strong,readonly) UIView                 * _Nonnull previewView;

@property (nonatomic,assign,readonly) GJPushConfig           pushConfig;

//只读，根据pushConfig中的push size自动选择最优.outOrientation 和 pushsize会改变改值，
@property (nonatomic,assign,readonly) CGSize                 captureSize;

@property (nonatomic,weak           ) id  <GJLivePushDelegate> _Nullable delegate;


@property (nonatomic,assign         ) BOOL                   videoMute;
@property (nonatomic,assign         ) BOOL                   audioMute;
@property (nonatomic,assign         ) BOOL                   measurementMode;
@property (nonatomic,assign         ) BOOL                   enableAec;//default NO

//配置ar场景，开启ar模式，预览和推流前配置。scene= nil表示取消;
@property (nonatomic,retain         ) id  <GJImageARScene> _Nullable                    ARScene;
//录屏直播
@property (nonatomic,retain         ) UIView*              _Nullable                    captureView;

//- (bool)startCaptureWithSizeType:(CaptureSizeType)sizeType fps:(NSInteger)fps position:(enum AVCaptureDevicePosition)cameraPosition;

//- (void)stopCapture;


- (void)startPreview;

- (void)stopPreview;

- (bool)startStreamPushWithUrl:(NSString *_Nonnull)url;

- (void)setPushConfig:(GJPushConfig)pushConfig;

- (void)stopStreamPush;

- (BOOL)enableAudioInEarMonitoring:(BOOL)enable;

- (BOOL)enableReverb:(BOOL)enable;

- (BOOL)startAudioMixWithFile:(NSURL*_Nonnull)fileUrl;

- (void)stopAudioMix;

- (void)setInputVolume:(float)volume;

- (void)setMixVolume:(float)volume;

- (void)setMasterOutVolume:(float)volume;

- (BOOL)startUIRecodeWithRootView:(UIView*_Nonnull)view fps:(NSInteger)fps filePath:(NSURL*_Nonnull)file;

- (void)stopUIRecode;

- (UIImage*_Nullable)captureFreshDisplayImage;

/**
 贴图，如果存在则取消已存在的

 @param images 需要贴的图片集合
 @param fps 贴图更新的帧率
 @param updateBlock 每次更新的回调，index表示当前更新的图片，ioFinish表示是否结束，输入输出值。
 @return 是否成功
 */
- (BOOL)startStickerWithImages:(NSArray<GJOverlayAttribute*>* _Nonnull)images fps:(NSInteger)fps updateBlock:(OverlaysUpdate _Nullable )updateBlock;

/**
 主动停止贴图。也可以通过addStickerWithImages的updateBlock，赋值ioFinish true来停止，不过该方法只能在更新的时候使用，可能会有延迟，fps越小延迟越大。
 */
- (void)chanceSticker;

- (BOOL)startTrackingImageWithImages:(NSArray<UIImage*>*_Nonnull)images initFrame:(GCRect)frame;

- (void)stopTracking;

//- (void)videoRecodeWithPath:(NSString*)path;

@end
