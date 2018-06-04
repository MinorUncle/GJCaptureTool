//
//  ScreenRecorder.h
//  ScreenRecorderDemo
//
//  Created by mac on 16/11/17.
//  Copyright © 2016年 zhouguangjin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIView.h>
#import <AVFoundation/AVFoundation.h>

typedef void (^ScreenRecodeFinishBlock)(NSURL *file, NSError *error);

typedef enum ScreenRecorderStatus {
    screenRecorderStopStatus,
    screenRecorderPauseStatus,
    screenRecorderRecorderingStatus,
} GJScreenRecorderStatus;
@interface GJScreenRecorder : NSObject
@property (readonly, nonatomic, assign) NSInteger              fps;
@property (readonly, nonatomic, assign) GJScreenRecorderStatus status;

@property (assign, nonatomic, readonly) CGRect  captureFrame;
@property (strong, nonatomic, readonly) UIView *captureView;
@property (nonatomic, strong) NSURL *               destFileUrl;
@property (nonatomic, copy) ScreenRecodeFinishBlock callback;

- (instancetype)initWithDestUrl:(NSURL *)url;
- (BOOL)addAudioSourceWithFormat:(AudioStreamBasicDescription)format;
- (BOOL)addVideoSourceWithView:(UIView *)view fps:(NSInteger)fps;

- (BOOL)startRecode;

- (void)stopRecord;
- (void)pause;
- (void)resume;
- (void)addCurrentAudioSource:(uint8_t *)data size:(NSInteger)size;
- (UIImage *)captureImageWithView:(UIView *)view;

@end
