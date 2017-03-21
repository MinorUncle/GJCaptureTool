//
//  GJLivePush.m
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePush.h"
#import "GJImageFilters.h"
#import "GJRtmpPush.h"
#import "GJDebug.h"
#import "GJH264Encoder.h"
#import "GJAudioQueueRecoder.h"
@interface GJLivePush()<GJH264EncoderDelegate,GJAudioQueueRecoderDelegate>
{
    GPUImageVideoCamera* _videoCamera;
    NSString* _sessionPreset;
    CGSize _captureSize;
    GJImageView* _showView;
    GPUImageOutput* _lastFilter;
    GPUImageCropFilter* _cropFilter;
    GJAudioQueueRecoder* _audioRecoder;
}
@property(strong,nonatomic)GJH264Encoder* videoEncoder;
@property(copy,nonatomic)NSString* pushUrl;
@property(strong,nonatomic)GPUImageFilter* videoStreamFilter; //可能公用_cropFilter
@property(assign,nonatomic)GJRtmpPush* videoPush;
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
    _videoCamera.frameRate = (int)_captureFps;
    _videoCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
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
    _status |= kLIVEPUSH_PREVIEW;
    [_lastFilter addTarget:_showView];
}

- (void)stopPreview{
    [_lastFilter removeTarget:_showView];
    _status &= !kLIVEPUSH_PREVIEW;

}

- (bool)startStreamPushWithConfig:(GJPushConfig)config{
    if (_cropFilter) {
        if (_cropFilter == _videoStreamFilter) {
            _videoStreamFilter = nil;
        }
        [_lastFilter removeTarget:_cropFilter];
        _cropFilter = nil;
    }
    
    if (_videoStreamFilter) {
        [_lastFilter removeTarget:_videoStreamFilter];
        _videoStreamFilter = nil;
    }
  
    if (!CGSizeEqualToSize(config.pushSize, _captureSize)) {
        float scaleX = config.pushSize.width / _captureSize.width;
        float scaleY = config.pushSize.height / _captureSize.height;
        if (scaleY - scaleX < -0.00001 || scaleY - scaleX > 0.00001) {//比例不相同，先裁剪，
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
            _videoStreamFilter = _cropFilter;
        }else{
            _videoStreamFilter = [[GPUImageFilter alloc]init];
            [_lastFilter addTarget:_videoStreamFilter];
        }
    }else{
        _videoStreamFilter = [[GPUImageFilter alloc]init];
        [_lastFilter addTarget:_videoStreamFilter];
    }
    
    if (_videoEncoder == nil) {
        H264Format format = [GJH264Encoder defaultFormat];
        format.baseFormat.bitRate = config.videoBitRate;
        _videoEncoder = [[GJH264Encoder alloc]initWithFormat:format];
        _videoEncoder.allowMinBitRate = format.baseFormat.bitRate * 0.6;
        _videoEncoder.deleagte = self;
    }
    _pushUrl = [NSString stringWithUTF8String:config.pushUrl];
    if (_videoPush == nil) {
        GJRtmpPush_Create(&_videoPush, rtmpCallback, (__bridge void *)(self));
    }
    [_videoStreamFilter forceProcessingAtSize:config.pushSize];
    _videoStreamFilter.frameProcessingCompletionBlock = nil;
    GJRtmpPush_StartConnect(self.videoPush, self.pushUrl.UTF8String);
    


    return true;
}

-(void)pushRun{
    if (_audioRecoder == nil) {
        _audioRecoder = [[GJAudioQueueRecoder alloc]initWithStreamWithSampleRate:44100 channel:2 formatID:kAudioFormatMPEG4AAC];
        _audioRecoder.delegate = self;
    }
    [_audioRecoder startRecodeAudio];
    __weak GJLivePush* wkSelf = self;
    wkSelf.videoStreamFilter.frameProcessingCompletionBlock =  ^(GPUImageOutput * output, CMTime time){
        CVPixelBufferRef pixel_buffer = [output framebufferForOutput].pixelBuffer;
        
        [wkSelf.videoEncoder encodeImageBuffer:pixel_buffer pts:CMTimeMake(wkSelf.videoEncoder.frameCount, (int32_t)wkSelf.captureFps) fourceKey:false];
    };
}

- (void)stopStreamPush{
    [_lastFilter removeTarget:_videoStreamFilter];
    [_audioRecoder stop];
    [_videoEncoder flush];
    if(_videoPush){
        GJRtmpPush_CloseAndRelease(_videoPush);
    }
    _videoPush = nil;
}

-(UIView *)getPreviewView{
    if (_previewView == nil) {
        _previewView = [[GJImageView alloc]init];
    }
    return _previewView;
}

#pragma mark rtmp callback
static void rtmpCallback(GJRtmpPush* rtmpPush, GJRTMPPushMessageType messageType,void* rtmpPushParm,void* messageParm){
    GJLivePush* livePush = (__bridge GJLivePush *)(rtmpPushParm);
    switch (messageType) {
        case GJRTMPPushMessageType_connectSuccess:
            GJLOG(@"连接成功\n");
            [livePush.delegate livePush:livePush messageType:kLivePushConnectSuccess infoDesc:nil];
            
            [livePush pushRun];
            break;
        case GJRTMPPushMessageType_closeComplete:
            [livePush.delegate livePush:livePush messageType:kLivePushCloseSuccess infoDesc:nil];
            break;
        case GJRTMPPushMessageType_connectError:
            GJLOG(@"连接失败\n");
            [livePush.delegate livePush:livePush messageType:kLivePushConnentError infoDesc:@"rtmp连接失败"];
            if (livePush.videoPush) {
                [livePush stopStreamPush];
            }
            
            break;
        case GJRTMPPushMessageType_urlPraseError:
            
            break;
        case GJRTMPPushMessageType_sendPacketError:
            break;
        default:
            break;
    }
}

#pragma mark delegate
-(float)GJH264Encoder:(GJH264Encoder*)encoder encodeCompleteBuffer:(GJRetainBuffer*)buffer keyFrame:(BOOL)keyFrame pts:(CMTime)pts{
//    printf("video Pts:%d\n",(int)pts.value*1000/pts.timescale);
    GJRtmpPush_SendH264Data(_videoPush, buffer, (int)pts.value*1000/pts.timescale);
    return GJRtmpPush_GetBufferRate(_videoPush);
}
-(void)GJH264Encoder:(GJH264Encoder *)encoder qualityQarning:(GJEncodeQuality)quality{

}
-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder*) recoder streamData:(GJRetainBuffer*)dataBuffer packetDescriptions:(const AudioStreamPacketDescription *)packetDescriptions pts:(CMTime)pts{
//    printf("audio Pts:%d\n",(int)pts.value*1000/pts.timescale);
//    static int times =0;
//    NSData* audio = [NSData dataWithBytes:dataBuffer->data length:dataBuffer->size];
//    NSLog(@"audio times:%d ,%@",times++,audio);
    GJRtmpPush_SendAACData(_videoPush, dataBuffer, (int)pts.value*1000/pts.timescale);
}
-(void)dealloc{
    if (_videoPush) {
        GJRtmpPush_CloseAndRelease(_videoPush);
    }
}
@end
