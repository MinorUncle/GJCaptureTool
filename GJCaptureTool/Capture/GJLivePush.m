//
//  GJLivePush.m
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePush.h"
#import "GJImageFilters.h"
#import "RtmpSendH264.h"
@interface GJLivePush()
{
    GPUImageVideoCamera* _videoCamera;
    NSString* _sessionPreset;
    CGSize _captureSize;
    GJImageView* _showView;
    GPUImageOutput* _lastFilter;
    GPUImageFilter* _videoStreamFilter;
    GPUImageCropFilter* _cropFilter;
}
@end
@implementation GJLivePush
@synthesize previewView = _previewView;



- (bool)startCaptureWithSizeType:(CaptureSizeType)sizeType fps:(NSInteger)fps position:(enum AVCaptureDevicePosition)cameraPosition{
    _caputreSizeType = sizeType;
    _cameraPosition = cameraPosition;
    _captureFps = fps;
    switch (_caputreSizeType) {
        case kCaptureSize352_288:
            _sessionPreset = AVCaptureSessionPreset352x288;
            _captureSize = CGSizeMake(288, 352);
            break;
        case kCaptureSize640_480:
            _sessionPreset = AVCaptureSessionPreset640x480;
            _captureSize = CGSizeMake(480, 640);
            break;
        case kCaptureSize1280_720:
            _sessionPreset = AVCaptureSessionPreset1280x720;
            _captureSize = CGSizeMake(720, 1280);
            break;
        case kCaptureSize1920_1080:
            _sessionPreset = AVCaptureSessionPreset1920x1080;
            _captureSize = CGSizeMake(1080, 1920);
            break;
        case kCaptureSize3840_2160:
            _sessionPreset = AVCaptureSessionPreset3840x2160;
            _captureSize = CGSizeMake(2160, 3840);
            break;
    }
    _videoCamera = [[GPUImageVideoCamera alloc]initWithSessionPreset:_sessionPreset cameraPosition:_cameraPosition];
    if (_videoCamera == nil) {
        return false;
    }
    [_videoCamera startCameraCapture];
    _lastFilter = _videoCamera;
    return true;
}

- (void)stopCapture{
    [_videoCamera stopCameraCapture];
}

- (void)startPreview{
    if (_showView == nil) {
        _showView = (GJImageView*)self.previewView;
    }
    [_lastFilter addTarget:_showView];
}

- (void)stopPreview{
    [_lastFilter removeTarget:_showView];
}

- (bool)startStreamPushWithConfig:(GJPushConfig)config{
    
    if (_videoStreamFilter == nil) {
        _videoStreamFilter = [[GPUImageFilter alloc]init];
    }
    if (!CGSizeEqualToSize(config.pushSize, _captureSize)) {
        float scaleX = config.pushSize.width / _captureSize.width;
        float scaleY = config.pushSize.height / _captureSize.height;
        if (scaleY - scaleX < -0.00001 || scaleY - scaleX > 0.00001) {//比例不相同，先裁剪，裁剪之后显示，避免与收流端不同画面
            float scale = MIN(scaleX, scaleY);

            CGSize scaleSize = CGSizeMake(_captureSize.width * scale, _captureSize.height * scale);
            CGRect region =CGRectZero;
            if (scaleX > scaleY) {
                region.origin.x = 0;
                region.origin.y = (scaleSize.height - config.pushSize.height)*0.5;
            }else{
                region.origin.y = 0;
                region.origin.x = (scaleSize.width - config.pushSize.width)*0.5;
            }
            _cropFilter = [[GPUImageCropFilter alloc]initWithCropRegion:region];
            [_lastFilter addTarget:_cropFilter];
        }
        if (_videoStreamFilter == nil) {
            _videoStreamFilter = [[GPUImageFilter alloc]init];
        }
        [_videoStreamFilter forceProcessingAtSize:config.pushSize];
        [_lastFilter addTarget:_videoStreamFilter];
    }
    
    return true;
}

- (void)stopStreamPush{
    [_lastFilter removeTarget:_videoStreamFilter];
}

-(UIView *)getPreviewView{
    if (_previewView == nil) {
        _previewView = [[GJImageView alloc]init];
        [_previewView addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
    }
    return _previewView;
}
@end
