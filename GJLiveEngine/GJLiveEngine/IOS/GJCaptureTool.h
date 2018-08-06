//
//  GJCapture.h
//  GJCaptureTool
//
//  Created by tongguan on 16/6/27.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
typedef enum _GJCaptureType {
    GJCaptureTypeVideoStream = 0x1 << 0,
    GJCaptureTypeAudioStream = 0x1 << 1,
    GJCaptureTypeFile        = 0x1 << 2, //视频是否文件存储；
    GJCaptureTypeImage       = 0x1 << 3  //视频是否文件存储；
} GJCaptureType;
@class GJCaptureTool;
@protocol GJCaptureToolDelegate <NSObject>
@optional
- (void)GJCaptureTool:(GJCaptureTool *)captureTool recodeVideoYUVData:(CMSampleBufferRef)sampleBufferRef;
- (void)GJCaptureTool:(GJCaptureTool *)captureTool recodeAudioPCMData:(CMSampleBufferRef)sampleBufferRef;
- (void)GJCaptureTool:(GJCaptureTool *)captureTool didRecodeFile:(NSURL *)fileUrl;

@end

@interface GJCaptureTool : NSObject

@property (assign, nonatomic, readonly) GJCaptureType captureType;
@property (assign, nonatomic) int fps;
@property (strong, nonatomic, readonly) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer; //相机拍摄预览图层
@property (strong, nonatomic) AVCaptureMovieFileOutput * captureMovieFileOutput;              //视频输出流
@property (strong, nonatomic) AVCaptureVideoDataOutput * captureDataOutput;                   //视频输出流
@property (strong, nonatomic) AVCaptureStillImageOutput *captureImageOutput;                  //音频输出流
@property (strong, nonatomic) AVCaptureAudioDataOutput * captureAudioOutput;                  //音频输出流
@property (weak, nonatomic) id<GJCaptureToolDelegate>    delegate;                            //
@property (copy, nonatomic) NSString *                   sessionPreset;                       //default = AVCaptureSessionPreset640x480

- (instancetype)initWithType:(GJCaptureType)type fps:(int)fps layer:(CALayer *)layer;

- (void)setFocusCursorWithPoint:(CGPoint)point;
- (void)setFocusMode:(AVCaptureFocusMode)focusMode;
- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposureMode:(AVCaptureExposureMode)exposureMode atPoint:(CGPoint)point;
- (void)startRunning;
- (void)stopRunning;
- (void)startRecodeing;
- (void)captureImageWithBlock:(void (^)(UIImage *))resultBlock;
-(void)stopRecode;
-(void)adjustOrientation;
- (void)changeCapturePosition;
@end
