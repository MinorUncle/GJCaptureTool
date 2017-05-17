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


@interface GJLivePull()<GJH264DecoderDelegate,GJPCMDecodeFromAACDelegate>
{
    GJRtmpPull* _videoPull;
    NSThread*  _playThread;
    GJPullSessionStatus _pullSessionStatus;
    
    
    
   
}
@property(strong,nonatomic)GJH264Decoder* videoDecoder;
@property(strong,nonatomic)GJPCMDecodeFromAAC* audioDecoder;
@property(strong,nonatomic) NSRecursiveLock* lock;

@property(assign,nonatomic)GJLivePlayContext* player;
@property(assign,nonatomic)long pullVByte;
@property(assign,nonatomic)int unitVByte;
@property(assign,nonatomic)int  unitVPacketCount;
@property(assign,nonatomic)long pullAByte;
@property(assign,nonatomic)int unitAByte;
@property(assign,nonatomic)int  unitAPacketCount;

@property(assign,nonatomic)float gaterFrequency;
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
        GJLivePlay_Create(&_player, <#GJLivePlayCallback callback#>, <#GHandle userData#>)
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
            case GJRTMPPullMessageType_receivePacketError:
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
                GJLOG(GJ_LOGFORBID,"not catch info：%d",messageType);
                break;
        }
    });
}

-(void)updateStatusCallback{
    GJTrafficStatus vCache = [_player getVideoCache];
    GJTrafficStatus aCache = [_player getAudioCache];
    _pullSessionStatus.videoStatus.cacheCount = vCache.enter.count - vCache.leave.count;
    _pullSessionStatus.videoStatus.cacheTime = vCache.enter.pts - vCache.leave.pts;
    _pullSessionStatus.videoStatus.bitrate = _unitVByte / _gaterFrequency;
    _unitVByte = 0;
    _pullSessionStatus.videoStatus.frameRate = _unitVPacketCount / _gaterFrequency;
    _unitVPacketCount = 0;

    _pullSessionStatus.audioStatus.cacheCount = aCache.enter.count - aCache.leave.count;
    _pullSessionStatus.audioStatus.cacheTime = aCache.enter.pts - aCache.leave.pts;
    _pullSessionStatus.audioStatus.bitrate = _unitAByte / _gaterFrequency;
    _unitAByte = 0;
    _pullSessionStatus.audioStatus.frameRate = _unitAByte / _gaterFrequency;
    _unitAPacketCount = 0;


        
    [self.delegate livePull:self updatePullStatus:&_pullSessionStatus];
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
        GJRtmpPull_CloseAndRelease(_videoPull);
    }
    GJRtmpPull_Create(&_videoPull, pullMessageCallback, (__bridge void *)(self));
    GJRtmpPull_StartConnect(_videoPull, pullDataCallback, (__bridge void *)(self),(const char*) url);
    [_player start];    
    _startPullDate = [NSDate date];
    [_lock unlock];
    return YES;
}

- (void)stopStreamPull{
    [_lock lock];
    [_timer invalidate];
    if (_videoPull) {
        GJRtmpPull_CloseAndRelease(_videoPull);
        _videoPull = NULL;
    }
    [_player stop];
    [_audioDecoder stop];
    _audioDecoder = nil;
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
    

    if (streamPacket.type == GJMediaType_Audio) {
        GJRetainBuffer* buffer = &streamPacket.packet.aacPacket->retain;
        livePull.pullAByte += buffer->size;
        livePull.unitAByte += buffer->size;
        livePull.unitAPacketCount ++;
        if (livePull.fristAudioDate == nil) {
            livePull.fristAudioDate = [NSDate date];
            uint8_t* adts = streamPacket.packet.aacPacket->adtsOffset+streamPacket.packet.aacPacket->retain.data;
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

            if (channel>2) {
                GJLOG(GJ_LOGFORBID, "音频channel不支持");
            }
            
            AudioStreamBasicDescription destformat = {0};
            destformat.mFormatID = kAudioFormatLinearPCM;
            destformat.mSampleRate       = sourceformat.mSampleRate;               // 3
            destformat.mChannelsPerFrame = sourceformat.mChannelsPerFrame;                     // 4
            destformat.mFramesPerPacket  = 1;                     // 7
            destformat.mBitsPerChannel   = 16;                    // 5
            destformat.mBytesPerFrame   = destformat.mChannelsPerFrame * destformat.mBitsPerChannel/8;
            destformat.mFramesPerPacket = destformat.mBytesPerFrame * destformat.mFramesPerPacket ;
            destformat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
            [livePull.lock lock];
            livePull.audioDecoder = [[GJPCMDecodeFromAAC alloc]initWithDestDescription:&destformat SourceDescription:&sourceformat];
            livePull.audioDecoder.delegate = livePull;
            [livePull.audioDecoder start];
            livePull.player.audioFormat = destformat;
            [livePull.lock unlock];
        }
        
 
        
        [livePull.audioDecoder decodePacket:streamPacket.packet.aacPacket];
    }else if (streamPacket.type == GJMediaType_Video) {
        GJRetainBuffer* buffer = &streamPacket.packet.h264Packet->retain;
        livePull.pullVByte += buffer->size;
        livePull.unitVByte += buffer->size;
        livePull.unitVPacketCount ++;



        [livePull.videoDecoder decodePacket:streamPacket.packet.h264Packet];
    }
}
static GBool imageReleaseCallback(GJRetainBuffer* buffer){
    CVPixelBufferRelease((CVImageBufferRef)buffer->data);
    return GFalse;
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
    CVPixelBufferRetain(imageBuffer);
    GJRetainBuffer* retainBuffer = NULL;
    retainBufferPack(&retainBuffer, imageBuffer, sizeof(imageBuffer), imageReleaseCallback, GNULL);
    [_player addVideoDataWith:retainBuffer pts:pts];
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
    GJLivePlay_AddAudioData(_player, <#R_GJFrame *audioFrame#>)
    [_player addAudioDataWith:buffer pts:pts];
}

-(void)livePlayer:(GJLivePlayer *)livePlayer bufferUpdatePercent:(float)percent duration:(long)duration{
    if ([self.delegate respondsToSelector:@selector(livePull:bufferUpdatePercent:duration:)]) {
        [self.delegate livePull:self bufferUpdatePercent:percent duration:duration];
    }
}
GVoid livePlayCallback(GHandle userDate,GJPlayMessage message,GHandle param){

}
-(void)dealloc{
    if (_videoPull) {
        GJRtmpPull_CloseAndRelease(_videoPull);
    }
}
@end
