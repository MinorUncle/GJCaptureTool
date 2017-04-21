//
//  GJLivePull.m
//  GJLivePull
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePull.h"
#import "GJRtmpPull.h"
#import "GJH264Decoder.h"
#import "GJLivePlayer.h"
#import "GJLog.h"
#import "GJPCMDecodeFromAAC.h"
#import <CoreImage/CoreImage.h>


@interface GJLivePull()<GJH264DecoderDelegate,GJPCMDecodeFromAACDelegate,GJLivePlayerDeletate>
{
    GJRtmpPull* _videoPull;
    NSThread*  _playThread;
    
    
    
    
    NSRecursiveLock* _lock;
}
@property(strong,nonatomic)GJH264Decoder* videoDecoder;
@property(strong,nonatomic)GJPCMDecodeFromAAC* audioDecoder;

@property(strong,nonatomic)GJLivePlayer* player;
@property(assign,nonatomic)long sendByte;
@property(assign,nonatomic)int unitByte;

@property(assign,nonatomic)int gaterFrequency;
@property(strong,nonatomic)NSTimer * timer;


@property(strong,nonatomic)NSDate* startPullDate;
@property(strong,nonatomic)NSDate* connentDate;
@property(strong,nonatomic)NSDate* fristVideoDate;
@property(strong,nonatomic)NSDate* fristDecodeVideoDate;
@property(strong,nonatomic)NSDate* fristAudioDate;

@end
@implementation GJLivePull
- (instancetype)init
{
    self = [super init];
    if (self) {
        
        _player = [[GJLivePlayer alloc]init];
        _player.delegate = self;
        _videoDecoder = [[GJH264Decoder alloc]init];
        _videoDecoder.delegate = self;
        _enablePreview = YES;
        _gaterFrequency = 2.0;
        _lock = [[NSRecursiveLock alloc]init];
    }
    return self;
}

static void pullMessageCallback(GJRtmpPull* pull, GJRTMPPullMessageType messageType,void* rtmpPullParm,void* messageParm){
    GJLivePull* livePull = (__bridge GJLivePull *)(rtmpPullParm);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (messageType) {
            case GJRTMPPullMessageType_connectError:
            case GJRTMPPullMessageType_urlPraseError:
                GJLOG(GJ_LOGERROR, "pull connect error:%d",messageType);
                [livePull.delegate livePull:livePull errorType:kLivePullConnectError infoDesc:@"连接错误"];
                [livePull stopStreamPull];
                break;
            case GJRTMPPullMessageType_sendPacketError:
                GJLOG(GJ_LOGERROR, "pull sendPacket error:%d",messageType);
                [livePull.delegate livePull:livePull errorType:kLivePullReadPacketError infoDesc:@"读取失败"];
                [livePull stopStreamPull];
                break;
            case GJRTMPPullMessageType_connectSuccess:
            {
                GJLOG(GJ_LOGINFO, "pull connectSuccess");
                livePull.connentDate = [NSDate date];
                [livePull.delegate livePull:livePull connentSuccessWithElapsed:[livePull.connentDate timeIntervalSinceDate:livePull.startPullDate]*1000];
                livePull.timer = [NSTimer scheduledTimerWithTimeInterval:livePull.gaterFrequency target:livePull selector:@selector(updateStatusCallback) userInfo:nil repeats:YES];
                GJLOG(GJ_LOGINFO, "NSTimer START:%s",[NSString stringWithFormat:@"%@",livePull.timer].UTF8String);

            }
                break;
            case GJRTMPPullMessageType_closeComplete:{
                GJLOG(GJ_LOGINFO, "pull closeComplete");
                NSDate* stopDate = [NSDate date];
                GJPullSessionInfo info = {0};
                info.sessionDuring = [stopDate timeIntervalSinceDate:livePull.startPullDate]*1000;
                [livePull.delegate livePull:livePull closeConnent:&info resion:kConnentCloce_Active];
            }
                break;
            default:
                GJLOG(GJ_LOGERROR,"not catch info：%d",messageType);
                break;
        }
    });
}

-(void)updateStatusCallback{
        GJCacheInfo videoCache = [_player getVideoCache];
        GJCacheInfo audioCache = [_player getAudioCache];
        GJPullStatus status = {0};
        status.bitrate = _unitByte/_gaterFrequency;
        _unitByte = 0;
        status.audioCacheCount = audioCache.cacheCount;
        status.audioCacheTime = audioCache.cacheTime;
        status.videoCacheTime = videoCache.cacheTime;
        status.videoCacheCount = videoCache.cacheCount;
        
        [self.delegate livePull:self updatePullStatus:&status];
#ifdef NETWORK_DELAY
     
        if ([self.delegate respondsToSelector:@selector(livePull:networkDelay:)]) {
            [self.delegate livePull:self networkDelay:[_player getNetWorkDelay]];
        }
#endif
}

- (bool)startStreamPullWithUrl:(char*)url{
    [_lock lock];
    _fristAudioDate = _fristVideoDate = _connentDate = _fristDecodeVideoDate = nil;
    if (_videoPull != nil) {
        GJRtmpPull_Release(_videoPull);
    }
    GJRtmpPull_Create(&_videoPull, pullMessageCallback, (__bridge void *)(self));
    GJRtmpPull_StartConnect(_videoPull, pullDataCallback, (__bridge void *)(self),(const char*) url);
    [_audioDecoder start];
    [_player start];    
    _startPullDate = [NSDate date];
    [_lock unlock];
    return YES;
}

- (void)stopStreamPull{
    [_lock lock];
    [_audioDecoder stop];
    [_player stop];
    GJRtmpPull_Close(_videoPull);
    GJRtmpPull_Release(_videoPull);
    _videoPull = NULL;
    [_timer invalidate];
    GJLOG(GJ_LOGINFO, "NSTimer invalidate:%s",[NSString stringWithFormat:@"%@",_timer].UTF8String);
    [_lock unlock];
}

-(UIView *)getPreviewView{
    return _player.displayView;
}

-(void)setEnablePreview:(BOOL)enablePreview{
    _enablePreview = enablePreview;
    
}
static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};

static void pullDataCallback(GJRtmpPull* pull,GJStreamPacket streamPacket,void* parm){
    GJLivePull* livePull = (__bridge GJLivePull *)(parm);
    

    if (streamPacket.type == GJAudioType) {
        GJRetainBuffer* buffer = &streamPacket.packet.aacPacket->retain;
        livePull.sendByte = livePull.sendByte + buffer->size;
        livePull.unitByte = livePull.unitByte + buffer->size;
        if (livePull.fristAudioDate == nil) {
            livePull.fristAudioDate = [NSDate date];
            uint8_t* adts = streamPacket.packet.aacPacket->adts;
            uint8_t sampleIndex = adts[2] << 2;
            sampleIndex = sampleIndex>>4;
            int sampleRate = mpeg4audio_sample_rates[sampleIndex];
            uint8_t channel = adts[2] & 0x1 <<2;
            channel += (adts[3] & 0xc0)>>6;
            AudioStreamBasicDescription sourceformat = {0};
            sourceformat.mFormatID = kAudioFormatMPEG4AAC;
            sourceformat.mChannelsPerFrame = channel;
            sourceformat.mSampleRate = sampleRate;
            sourceformat.mFramesPerPacket = 1024;

            AudioStreamBasicDescription destformat = {0};
            destformat.mFormatID = kAudioFormatLinearPCM;
            destformat.mSampleRate       = sourceformat.mSampleRate;               // 3
            destformat.mChannelsPerFrame = sourceformat.mChannelsPerFrame;                     // 4
            destformat.mFramesPerPacket  = 1;                     // 7
            destformat.mBitsPerChannel   = 16;                    // 5
            destformat.mBytesPerFrame   = destformat.mChannelsPerFrame * destformat.mBitsPerChannel/8;
            destformat.mFramesPerPacket = destformat.mBytesPerFrame * destformat.mFramesPerPacket ;
            destformat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
            livePull.audioDecoder = [[GJPCMDecodeFromAAC alloc]initWithDestDescription:&destformat SourceDescription:&sourceformat];
            livePull.audioDecoder.delegate = livePull;
            [livePull.audioDecoder start];
            
            livePull.player.audioFormat = destformat;
        }
        [livePull.audioDecoder decodePacket:streamPacket.packet.aacPacket];
//        static int times =0;
//        NSData* audio = [NSData dataWithBytes:buffer->data length:buffer->size];
//        NSLog(@" pullaudio times:%d ,%@",times++,audio);
        
    }else if (streamPacket.type == GJVideoType) {
        GJRetainBuffer* buffer = &streamPacket.packet.h264Packet->retain;
        livePull.sendByte = livePull.sendByte + buffer->size;
        livePull.unitByte = livePull.unitByte + buffer->size;
//        static int times;
//        R_GJH264Packet* packet = streamPacket.packet.h264Packet;
//        NSData* sps = [NSData dataWithBytes:packet->sps length:packet->spsSize];
//        NSData* pps = [NSData dataWithBytes:packet->pps length:packet->ppsSize];
////        NSData* pp = [NSData dataWithBytes:packet->pp length:30];
////
//        NSLog(@"dece:%d,sps%@,pps%@,pp%d,pts:%lld",times++,sps,pps,streamPacket.packet.h264Packet->ppSize,streamPacket.packet.h264Packet->pts);

        [livePull.videoDecoder decodePacket:streamPacket.packet.h264Packet];
    }
}
-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(int64_t)pts{

    if (_fristDecodeVideoDate == nil) {
        _fristDecodeVideoDate = [NSDate date];
       size_t w = CVPixelBufferGetWidth(imageBuffer);
       size_t h=  CVPixelBufferGetHeight(imageBuffer);
        GJPullFristFrameInfo info = {0};
        info.size = CGSizeMake((float)w, (float)h);
        [self.delegate livePull:self fristFrameDecode:&info];
    }
    [_player addVideoDataWith:imageBuffer pts:pts];
    return;    
}
#ifdef TEST
-(void)pullimage:(CVImageBufferRef)streamPacket time:(CMTime)pts{
    static int s = 0;
    if (s == 0) {
        s++;
        [_player start];
    }
    [_player addVideoDataWith:streamPacket pts:pts.value];
}
-(void)pullDataCallback:(GJStreamPacket)streamPacket{
    pullDataCallback(_videoPull, streamPacket, (__bridge void *)(self));
}
#endif

-(void)pcmDecode:(GJPCMDecodeFromAAC *)decoder completeBuffer:(GJRetainBuffer *)buffer pts:(int64_t)pts{
    [_player addAudioDataWith:buffer pts:pts];
}

-(void)livePlayer:(GJLivePlayer *)livePlayer bufferUpdatePercent:(float)percent duration:(long)duration{
    if ([self.delegate respondsToSelector:@selector(livePull:bufferUpdatePercent:duration:)]) {
        [self.delegate livePull:self bufferUpdatePercent:percent duration:duration];
    }
}
-(void)dealloc{
    if (_videoPull) {
        GJRtmpPull_Release(_videoPull);
    }
}
@end
