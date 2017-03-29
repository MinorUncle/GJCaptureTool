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

//#define GJPUSHAUDIOQUEUEPLAY_TEST
#ifdef GJPUSHAUDIOQUEUEPLAY_TEST
#import "GJAudioQueuePlayer.h"
#endif
@interface GJLivePush()<GJH264EncoderDelegate,GJAudioQueueRecoderDelegate>
{
    GPUImageVideoCamera* _videoCamera;
    NSString* _sessionPreset;
    CGSize _captureSize;
    GJImageView* _showView;
    GPUImageOutput* _lastFilter;
    GPUImageCropFilter* _cropFilter;
    GJAudioQueueRecoder* _audioRecoder;
    NSTimer*        _timer;
    
    int            _sendByte;
    int            _unitByte;
    
    int             _sendFrame;
    int              _unitFrame;
    NSLock*          _pushLock;
#ifdef GJPUSHAUDIOQUEUEPLAY_TEST
    GJAudioQueuePlayer* _audioTestPlayer;
#endif
}
@property(strong,nonatomic)GJH264Encoder* videoEncoder;
@property(copy,nonatomic)NSString* pushUrl;
@property(strong,nonatomic)GPUImageFilter* videoStreamFilter; //可能公用_cropFilter
@property(assign,nonatomic)GJRtmpPush* videoPush;

@property(assign,nonatomic)int gaterFrequency;

@property(strong,nonatomic)NSDate* startPushDate;
@property(strong,nonatomic)NSDate* connentDate;
@property(strong,nonatomic)NSDate* fristVideoDate;
@property(strong,nonatomic)NSDate* fristAudioDate;

@end

@implementation GJLivePush
@synthesize previewView = _previewView;

- (bool)startCaptureWithSizeType:(CaptureSizeType)sizeType fps:(NSInteger)fps position:(enum AVCaptureDevicePosition)cameraPosition{
    _gaterFrequency = 2.0;
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
    
    _startPushDate = [NSDate date];
    GJRtmpPush_StartConnect(self.videoPush, self.pushUrl.UTF8String);
    
    _timer = [NSTimer scheduledTimerWithTimeInterval:_gaterFrequency repeats:YES block:^(NSTimer * _Nonnull timer) {
        GJCacheInfo info = GJRtmpPush_GetBufferCacheInfo(_videoPush);
        GJPushStatus status = {0};
        status.bitrate = _unitByte / _gaterFrequency;
        status.frameRate =  _unitFrame / _gaterFrequency;
        status.cacheTime = info.cacheTime;
        status.cacheCount = info.cacheCount;
        _unitByte = 0;
        _unitFrame = 0;
        [self.delegate livePush:self updatePushStatus:&status ];
    }];
    if (_audioRecoder == nil) {
        _audioRecoder = [[GJAudioQueueRecoder alloc]initWithStreamWithSampleRate:config.audioSampleRate channel:config.channel formatID:kAudioFormatMPEG4AAC];
        _audioRecoder.delegate = self;
    }
    return true;
}

-(void)pushRun{

    [_audioRecoder startRecodeAudio];
    __weak GJLivePush* wkSelf = self;
    wkSelf.videoStreamFilter.frameProcessingCompletionBlock =  ^(GPUImageOutput * output, CMTime time){
        CVPixelBufferRef pixel_buffer = [output framebufferForOutput].pixelBuffer;
        uint64_t pts = [[NSDate date]timeIntervalSinceDate:wkSelf.connentDate]*1000;
        [wkSelf.videoEncoder encodeImageBuffer:pixel_buffer pts:pts fourceKey:false];
    };
}

- (void)stopStreamPush{
    if (_videoPush) {
        [_lastFilter removeTarget:_videoStreamFilter];
        [_audioRecoder stop];
        [_videoEncoder flush];
        GJRtmpPush_CloseAndRelease(_videoPush);
        _videoPush = nil;
        [_timer invalidate];
    }
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
            livePush.connentDate = [NSDate date];
            [livePush.delegate livePush:livePush connentSuccessWithElapsed:[livePush.connentDate timeIntervalSinceDate:livePush.startPushDate]*1000];
            [livePush pushRun];
            break;
        case GJRTMPPushMessageType_closeComplete:{
            GJPushSessionInfo info = {0};
            NSDate* stopDate = [NSDate date];
            info.sessionDuring = [stopDate timeIntervalSinceDate:livePush.startPushDate]*1000;
            [livePush.delegate livePush:livePush closeConnent:&info resion:kConnentCloce_Active];
        }
            break;
        case GJRTMPPushMessageType_urlPraseError:
        case GJRTMPPushMessageType_connectError:
            GJLOG(@"连接失败\n");
            [livePush.delegate livePush:livePush errorType:kLivePushConnectError infoDesc:@"rtmp连接失败"];
            [livePush stopStreamPush];
            break;
        case GJRTMPPushMessageType_sendPacketError:
            [livePush.delegate livePush:livePush errorType:kLivePushWritePacketError infoDesc:@"发送失败"];
            [livePush stopStreamPush];
            break;
        default:
            break;
    }
}

#pragma mark delegate
-(float)GJH264Encoder:(GJH264Encoder*)encoder encodeCompleteBuffer:(GJRetainBuffer*)buffer keyFrame:(BOOL)keyFrame pts:(int64_t)pts{
//    printf("video Pts:%d\n",(int)pts.value*1000/pts.timescale);
    GJRtmpPush_SendH264Data(_videoPush, buffer, (int)pts);
    _unitFrame++;
    _sendFrame++;
    _sendByte += buffer->size;
    _unitByte += buffer->size;
    return GJRtmpPush_GetBufferRate(_videoPush);
}
-(void)GJH264Encoder:(GJH264Encoder *)encoder qualityQarning:(GJEncodeQuality)quality{

}
-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder*) recoder streamData:(GJRetainBuffer*)dataBuffer packetDescriptions:(const AudioStreamPacketDescription *)packetDescriptions pts:(int)pts{
//    static int times =0;
//    NSData* audio = [NSData dataWithBytes:dataBuffer->data length:dataBuffer->size];
//    NSLog(@"pushaudio times:%d ,%@",times++,audio);
    _sendByte += dataBuffer->size;
    _unitByte += dataBuffer->size;
    int cpts = [[NSDate date]timeIntervalSinceDate:_connentDate]*1000;
#ifdef GJPUSHAUDIOQUEUEPLAY_TEST
    if (_audioTestPlayer == nil) {
        _audioTestPlayer = [[GJAudioQueuePlayer alloc]initWithFormat:recoder.format maxBufferSize:2000 macgicCookie:nil];
        [_audioTestPlayer start];
    }else{
        retainBufferMoveDataPoint(dataBuffer, 7);
        [_audioTestPlayer playData:dataBuffer packetDescriptions:packetDescriptions];
    }
#else
    GJRtmpPush_SendAACData(_videoPush, dataBuffer, cpts);
#endif
}
-(void)dealloc{
    if (_videoPush) {
        GJRtmpPush_CloseAndRelease(_videoPush);
    }
}
@end
