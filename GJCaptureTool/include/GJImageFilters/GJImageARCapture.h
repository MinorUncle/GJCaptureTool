//
//  GJImageARCapture.h
//  GJLiveEngine
//
//  Created by melot on 2017/10/19.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GPUImagePicture.h"
#import "GPUImageVideoCamera.h"
@class ARSCNView;
typedef void(^ARUpdateBlock)();




@protocol GJImageARScene <NSObject>
@required
@property(nonatomic,retain,readonly) ARSCNView* scene;
@property(nonatomic,assign) NSInteger updateFps;
@property(readonly, nonatomic) BOOL isRunning;
@property(nonatomic,assign) ARUpdateBlock updateBlock;
- (AVCaptureDevicePosition)cameraPosition;
- (void)rotateCamera;
-(BOOL)startRun;
-(void)stopRun;
-(void)pause;
-(void)resume;
@end
@interface GJImageARCapture : GPUImageOutput <GJCameraProtocal>
@property id<GJImageARScene> scene;
/// Whether or not the underlying AVCaptureSession is running
@property(readonly, nonatomic) BOOL isRunning;

/// The AVCaptureSession used to capture from the camera
@property(readonly, retain, nonatomic) AVCaptureSession *captureSession;
@property (nonatomic,assign) CGFloat zoomFactor;

/// This enables the capture session preset to be changed on the fly
//@property (readwrite, nonatomic, copy) NSString *captureSessionPreset;
@property(readwrite, nonatomic) UIInterfaceOrientation outputImageOrientation;

/// This sets the frame rate of the camera (iOS 5 and above only)
/**
 Setting this to 0 or below will set the frame rate back to the default setting for a particular preset.
 */
@property (readwrite,nonatomic,assign) int32_t frameRate;
@property(assign, nonatomic) CGSize captureSize;

@property (nonatomic,assign) CGPoint focusPoint;


/// Easy way to tell which cameras are present on device
@property (readonly, getter = isFrontFacingCameraPresent) BOOL frontFacingCameraPresent;
@property (readonly, getter = isBackFacingCameraPresent) BOOL backFacingCameraPresent;


/// These properties determine whether or not the two camera orientations should be mirrored. By default, both are NO.
@property(readwrite, nonatomic) BOOL horizontallyMirrorFrontFacingCamera, horizontallyMirrorRearFacingCamera;

@property(nonatomic, weak) id<GPUImageVideoCameraDelegate> delegate;

@property (nonatomic,getter = getTorchOn,setter= setTorchOn:) BOOL torchOn;

@property (nonatomic,readonly) BOOL torchSupport;

/// @name Manage the camera video stream

/** Start camera capturing
 */
- (void)startCameraCapture;

/** Stop camera capturing
 */
- (void)stopCameraCapture;

/** Pause camera capturing
 */
- (void)pauseCameraCapture;

/** Resume camera capturing
 */
- (void)resumeCameraCapture;

- (AVCaptureDevicePosition)cameraPosition;

- (void)rotateCamera;
-(instancetype)initWithScene:(id<GJImageARScene>) scene captureSize:(CGSize)size;
@end
