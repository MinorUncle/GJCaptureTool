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
#import "GJLog.h"
#import "GJH264Encoder.h"
#import "GJAudioQueueRecoder.h"
#import "Mp4Writer.h"
#import "AACEncoderFromPCM.h"
//#define GJPUSHAUDIOQUEUEPLAY_TEST
#ifdef GJPUSHAUDIOQUEUEPLAY_TEST
#import "GJAudioQueuePlayer.h"
#endif
//#define GJPCMDecodeFromAAC_TEST
#ifdef GJPCMDecodeFromAAC_TEST
#import "GJPCMDecodeFromAAC.h"
#endif

#ifdef GJVIDEODECODE_TEST
#import "GJH264Decoder.h"
#endif
@interface GJLivePush()<GJH264EncoderDelegate,GJAudioQueueRecoderDelegate,AACEncoderFromPCMDelegate>
{
    GPUImageVideoCamera* _videoCamera;
    NSString* _sessionPreset;
    CGSize _captureSize;
    GJImageView* _showView;
    GPUImageOutput* _lastFilter;
    GPUImageCropFilter* _cropFilter;
    GJAudioQueueRecoder* _audioRecoder;
    AACEncoderFromPCM* _audioEncoder;
    Mp4WriterContext *_mp4Recoder;
    NSTimer*        _timer;
    
    GJPushSessionStatus _pushSessionStatus;
    GJTrafficStatus        _audioInfo;
    GJTrafficStatus        _videoInfo;

    BOOL                    _isReStart;
    NSRecursiveLock*          _pushLock;
    GJPushConfig _pushConfig;
#ifdef GJPUSHAUDIOQUEUEPLAY_TEST
    GJAudioQueuePlayer* _audioTestPlayer;
#endif
#ifdef GJPCMDecodeFromAAC_TEST
    GJPCMDecodeFromAAC* _audioDecode;
#endif
#ifdef GJVIDEODECODE_TEST
    GJH264Decoder* _videoDecode;
#endif
}
@property(strong,nonatomic)GJH264Encoder* videoEncoder;
@property(copy,nonatomic)NSString* pushUrl;
@property(strong,nonatomic)GPUImageFilter* videoStreamFilter; //可能公用_cropFilter
@property(assign,nonatomic)GJRtmpPush* videoPush;

@property(assign,nonatomic)float gaterFrequency;

@property(strong,nonatomic)NSDate* startPushDate;
@property(strong,nonatomic)NSDate* connentDate;
@property(strong,nonatomic)NSDate* fristFrameDate;

@end

@implementation GJLivePush
@synthesize previewView = _previewView;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _gaterFrequency = 2.0;
        _pushLock = [[NSRecursiveLock alloc]init];
    }
    return self;
}
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
- (bool)startStreamPushWithConfig:(const GJPushConfig*)config{
    return [self startStreamPushWithConfig:config reStart:NO];
}
- (bool)startStreamPushWithConfig:(const GJPushConfig*)config reStart:(BOOL)isReStart{
    [_pushLock lock];
    
    _isReStart = isReStart;
    if (config != &_pushConfig) {
        if (_pushConfig.pushUrl != NULL) {
            free(_pushConfig.pushUrl);
            _pushConfig.pushUrl = NULL;
        }
        _pushConfig = *config;
        _pushConfig.pushUrl = (char*)malloc(strlen(config->pushUrl)+1);
        memcpy(_pushConfig.pushUrl, config->pushUrl, strlen(config->pushUrl)+1);
    }

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
    GFloat32 dw = _pushConfig.pushSize.width - _captureSize.width;
    GFloat32 dh = _pushConfig.pushSize.height - _captureSize.height;
    if (dw > 0.1 ||dw < 0.1 || dh > 0.1 ||dh < 0.1 ) {
        float scaleX = _pushConfig.pushSize.width / _captureSize.width;
        float scaleY = _pushConfig.pushSize.height / _captureSize.height;
        if (scaleY - scaleX < -0.00001 || scaleY - scaleX > 0.00001) {//比例不相同，先裁剪，
            float scale = MIN(scaleX, scaleY);
            CGSize scaleSize = CGSizeMake(_captureSize.width * scale, _captureSize.height * scale);
            CGRect region =CGRectZero;
            if (scaleX > scaleY) {
                region.origin.x = 0;
                region.origin.y = (scaleSize.height - _pushConfig.pushSize.height)*0.5;
            }else{
                region.origin.y = 0;
                region.origin.x = (scaleSize.width - _pushConfig.pushSize.width)*0.5;
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
        format.baseFormat.bitRate = _pushConfig.videoBitRate;
        _videoEncoder = [[GJH264Encoder alloc]initWithFormat:format];
        _videoEncoder.allowMinBitRate = format.baseFormat.bitRate * 0.6;
        _videoEncoder.deleagte = self;
    }
    _pushUrl = [NSString stringWithUTF8String:_pushConfig.pushUrl];
    if (_videoPush != nil) {
        GJRtmpPush_CloseAndRelease(_videoPush);
        _videoPush = NULL;
    }
    GJRtmpPush_Create(&_videoPush, rtmpCallback, (__bridge void *)(self));
    CGSize pushSize ;
    pushSize.height = _pushConfig.pushSize.height;
    pushSize.width = _pushConfig.pushSize.width;
    [_videoStreamFilter forceProcessingAtSize:pushSize];
    _videoStreamFilter.frameProcessingCompletionBlock = nil;
    
    _startPushDate = [NSDate date];
    GJRtmpPush_StartConnect(self.videoPush, self.pushUrl.UTF8String);
    [self setupMicrophoneWithSampleRate:_pushConfig.audioSampleRate channel:_pushConfig.channel];
    [_pushLock unlock];
    return true;
}

-(BOOL)setupMicrophoneWithSampleRate:(int)sampleRate channel:(int)channel{
    if (_audioRecoder != nil || _audioRecoder.format.mChannelsPerFrame != channel || _audioRecoder.format.mSampleRate != sampleRate){
        _audioRecoder = [[GJAudioQueueRecoder alloc]initWithStreamWithSampleRate:sampleRate channel:channel formatID:kAudioFormatLinearPCM];
        _audioRecoder.delegate = self;
    
        AudioStreamBasicDescription source = _audioRecoder.format;
        AudioStreamBasicDescription desc = {0};
        desc.mFormatID = kAudioFormatMPEG4AAC;
        desc.mChannelsPerFrame = source.mChannelsPerFrame;
        desc.mFramesPerPacket = 1024;
        desc.mSampleRate = source.mSampleRate;
        _audioEncoder = [[AACEncoderFromPCM alloc]initWithSourceForamt:&source DestDescription:&desc];
        _audioEncoder.delegate = self;
        [_audioEncoder start];
#ifdef GJPCMDecodeFromAAC_TEST
        _audioDecode = [[GJPCMDecodeFromAAC alloc]initWithDestDescription:&source SourceDescription:&desc];
        [_audioDecode start];
#endif
    }
    if (_audioRecoder) {
        GJLOG(GJ_LOGINFO, "GJAudioQueueRecoder 初始化成功");
        return YES;
    }else{
        GJLOG(GJ_LOGFORBID, "GJAudioQueueRecoder CREATE ERROR");
        return NO;
    }
}

-(void)pushRun{
    if(_timer){[_timer invalidate];}
    _timer = [NSTimer scheduledTimerWithTimeInterval:_gaterFrequency repeats:YES block:^(NSTimer * _Nonnull timer) {
        GJTrafficStatus vInfo = GJRtmpPush_GetVideoBufferCacheInfo(_videoPush);
        GJTrafficStatus aInfo = GJRtmpPush_GetAudioBufferCacheInfo(_videoPush);

        _pushSessionStatus.videoStatus.cacheTime = vInfo.enter.pts - vInfo.leave.pts;
        _pushSessionStatus.videoStatus.frameRate = (vInfo.leave.count - _videoInfo.leave.count)/_gaterFrequency;
        _pushSessionStatus.videoStatus.bitrate = (vInfo.leave.byte - _videoInfo.leave.byte)/_gaterFrequency;
        _videoInfo = vInfo;
        
        _pushSessionStatus.audioStatus.cacheTime = aInfo.enter.pts - aInfo.leave.pts;
        _pushSessionStatus.audioStatus.frameRate = (aInfo.leave.count - _audioInfo.leave.count)*1024.0/_gaterFrequency;
        _pushSessionStatus.audioStatus.bitrate = (aInfo.leave.byte - _audioInfo.leave.byte)/_gaterFrequency;
        _audioInfo = aInfo;        
        [_delegate livePush:self updatePushStatus:&_pushSessionStatus];
    }];
    _fristFrameDate = [NSDate date];
//    [_audioRecoder startRecodeAudio];
    __weak GJLivePush* wkSelf = self;
    wkSelf.videoStreamFilter.frameProcessingCompletionBlock =  ^(GPUImageOutput * output, CMTime time){
        CVPixelBufferRef pixel_buffer = [output framebufferForOutput].pixelBuffer;
        int pts = [[NSDate date]timeIntervalSinceDate:wkSelf.fristFrameDate]*1000;
        [wkSelf.videoEncoder encodeImageBuffer:pixel_buffer pts:pts fourceKey:false];
    };
}

- (void)stopStreamPush{
    [_pushLock lock];
    if (_videoPush) {
        if (_mp4Recoder) {
            mp4WriterClose(&(_mp4Recoder));
            _mp4Recoder = NULL;
        }
        
        [_lastFilter removeTarget:_videoStreamFilter];
        [_audioRecoder stop];
        [_audioEncoder stop];
        [_videoEncoder flush];
        [_timer invalidate];
        _timer = nil;
        
        GJRtmpPush_CloseAndRelease(_videoPush);
        _videoPush = NULL;
        memset(&_videoInfo, 0, sizeof(_videoInfo));
        memset(&_audioInfo, 0, sizeof(_audioInfo));
        GJLOG(GJ_LOGINFO, "推流停止");
    }else{
        GJLOG(GJ_LOGWARNING, "推流重复停止");
    }
    [_pushLock unlock];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (messageType) {
            case GJRTMPPushMessageType_connectSuccess:
            {
                GJLOG(GJ_LOGINFO, "推流连接成功");
                livePush.connentDate = [NSDate date];
                [livePush.delegate livePush:livePush connentSuccessWithElapsed:[livePush.connentDate timeIntervalSinceDate:livePush.startPushDate]*1000];
                [livePush pushRun];
            }
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
                GJLOG(GJ_LOGINFO, "推流连接失败");
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
    });
    
}


- (void)videoRecodeWithPath:(NSString*)path{
    if(_mp4Recoder == nil){
        mp4WriterCreate(&_mp4Recoder, path.UTF8String, _captureFps);
    }
}

#pragma mark delegate
#ifdef GJVIDEODECODE_TEST
-(GJLivePlayer *)player{
    if (_player == nil) {
        _player = [[GJLivePlayer alloc]init];
        [_player start];
    }
    return _player;
}
-(void)GJH264Decoder:(GJH264Decoder*)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(int64_t)pts{
    if (_player == nil) {
        _player = [[GJLivePlayer alloc]init];
    }
    GJLOGFREQ("encode complete pts:%lld",pts);
    [_player addVideoDataWith:imageBuffer pts:pts];
}
#endif
GJQueue* h264Queue ;
-(GJTrafficStatus)GJH264Encoder:(GJH264Encoder *)encoder encodeCompletePacket:(R_GJH264Packet *)packet{
#ifdef GJVIDEODECODE_TEST
    if (_videoDecode == nil) {
        _videoDecode = [[GJH264Decoder alloc]init];
        _videoDecode.delegate = self;
        
        queueCreate(&h264Queue, 100, GTrue, GTrue);
        dispatch_async(dispatch_get_main_queue(), ^{
            while (_videoDecode) {
                R_GJH264Packet* hPacket;
                if (queuePop(h264Queue, (void**)&hPacket, GINT8_MAX)) {
                    [_videoDecode decodePacket:packet];
                    retainBufferUnRetain(&hPacket->retain);
                }
            }
        });
    }
    retainBufferRetain(&packet->retain);
    queuePush(h264Queue, packet, 0);
    return 0.0;
#endif
    if (_mp4Recoder) {
        uint8_t* frame;long size=0;
        if (packet->spsSize > 0) {
            frame = packet->spsOffset + packet->retain.data;
            size = packet->ppsSize+packet->ppSize + packet->spsSize + packet->seiSize;
        }else{
            frame = packet->ppOffset + packet->retain.data;
            size = packet->ppSize;
        }
        mp4WriterAddVideo(_mp4Recoder, frame, size, (double)packet->pts);
    }
    
    GJRtmpPush_SendH264Data(_videoPush, packet);
    
    GJTrafficStatus status = GJRtmpPush_GetVideoBufferCacheInfo(_videoPush);
    GLong cache = status.enter.pts - status.leave.pts;
    if(cache > MAX_SEND_DELAY){
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJLOG(GJ_LOGERROR, "推送缓存过多，导致重连");
            [_pushLock lock];
            [self stopStreamPush];
            [self startStreamPushWithConfig:&_pushConfig reStart:YES];
            [_pushLock unlock];
        });
    }
    return status;
}

//-(float)GJH264Encoder:(GJH264Encoder*)encoder encodeCompleteBuffer:(GJRetainBuffer*)buffer keyFrame:(BOOL)keyFrame pts:(int64_t)pts{
////    printf("video Pts:%d\n",(int)pts.value*1000/pts.timescale);
//}
-(void)GJH264Encoder:(GJH264Encoder *)encoder qualityQarning:(GJEncodeQuality)quality{
    _pushSessionStatus.netWorkQuarity = (GJNetworkQuality)quality;
}
-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder *)recoder pcmPacket:(R_GJPCMFrame *)packet{
    packet->pts = [[NSDate date]timeIntervalSinceDate:_fristFrameDate] * 1000;
    [_audioEncoder encodeWithPacket:packet];
}
-(void)AACEncoderFromPCM:(AACEncoderFromPCM *)encoder completeBuffer:(R_GJAACPacket *)packet{
#ifdef GJPUSHAUDIOQUEUEPLAY_TEST
    if (_audioTestPlayer == nil) {
        _audioTestPlayer = [[GJAudioQueuePlayer alloc]initWithFormat:recoder.format maxBufferSize:2000 macgicCookie:nil];
        [_audioTestPlayer start];
    }else{
        retainBufferMoveDataPoint(dataBuffer, 7);
        [_audioTestPlayer playData:dataBuffer packetDescriptions:packetDescriptions];
    }
    return;
#endif
    
//    static int times;
//    NSData* audio = [NSData dataWithBytes:packet->aacOffset+packet->retain.data length:packet->aacSize];
//    NSData* adts = [NSData dataWithBytes:packet->adtsOffset+packet->retain.data length:packet->adtsSize];
//    NSLog(@"pushaudio times:%d,audioSize:%d,adts%@,audio:%@",times++,packet->aacSize,adts,audio);

#ifdef GJPCMDecodeFromAAC_TEST
    [_audioDecode decodePacket:packet];
    return;
#endif
    GJRtmpPush_SendAACData(_videoPush, packet);

}

//-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder*) recoder streamPacket:(R_GJAACPacket *)packet{
////    static int times =0;
////    NSData* audio = [NSData dataWithBytes:packet->aac length:MIN(packet->aacSize,10)];
////    NSData* adts = [NSData dataWithBytes:packet->adts length:packet->adtsSize];
////    NSLog(@"pushaudio times:%d ,adts%@,audio:%@,audioSize:%d",times++,adts,audio,packet->aacSize);
//
//}
-(void)dealloc{
    if (_videoPush) {
        GJRtmpPush_CloseAndRelease(_videoPush);
    }
    if (_pushConfig.pushUrl != NULL) {
        free(_pushConfig.pushUrl);
        _pushConfig.pushUrl = NULL;
    }
    GJLOG(GJ_LOGDEBUG, "GJLivePush");
}
@end
