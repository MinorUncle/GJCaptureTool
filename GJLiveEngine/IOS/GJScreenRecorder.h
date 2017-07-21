//
//  GJScreenRecorder.h
//  GJScreenRecorderDemo
//
//  Created by mac on 16/11/17.
//  Copyright © 2016年 zhouguangjin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIView.h>
#import <AVFoundation/AVFoundation.h>

#define USE_REPLAYKIT 1
#ifndef DEBUG
#define RecorderLOG(format, ...) NSLog(format,##__VA_ARGS__)
#else
#define RecorderLOG(format, ...)
#endif

@class GJScreenRecorder;
@protocol GJScreenRecorderDelegate <NSObject>
@optional
-(void)screenRecorder:(GJScreenRecorder*)recorder recorderFile:(NSURL*)fileUrl FinishWithError:(NSError*) error;
@end


typedef enum ScreenRecorderStatus{
    screenRecorderStopStatus,
    screenRecorderPauseStatus,
    screenRecorderRecorderingStatus,
}ScreenRecorderStatus;
@interface GJScreenRecorder : NSObject
@property(readonly,nonatomic,assign)NSInteger fps;
@property(readonly,nonatomic,assign)ScreenRecorderStatus status;

@property(assign,nonatomic,readonly)CGRect captureFrame;
@property(strong,nonatomic,readonly)UIView* captureView;
@property(strong,nonatomic)dispatch_queue_t captureQueue;
@property(nonatomic,copy)NSURL* destFileUrl;
@property(nonatomic,weak)id<GJScreenRecorderDelegate> delegate;

- (instancetype)initWithDestUrl:(NSURL*)url;


-(BOOL)startWithView:(UIView*)targetView fps:(NSInteger)fps;

-(void)stopRecord;
-(void)pause;
-(void)resume;
-(BOOL)setExternalAudioSourceWithFormat:(AudioStreamBasicDescription)streamFormat;
-(void)addCurrentAudioSource:(uint8_t*)data size:(int)size;
-(UIImage*)captureImageWithView:(UIView*)view;


@end
