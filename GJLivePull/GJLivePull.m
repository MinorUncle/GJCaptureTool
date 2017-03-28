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
#import "GJPlayer.h"
#import "GJDebug.h"
#import "GJPCMDecodeFromAAC.h"
#import <CoreImage/CoreImage.h>


@interface GJLivePull()<GJH264DecoderDelegate,GJPCMDecodeFromAACDelegate>
{
    GJRtmpPull* _videoPull;
    NSThread*  _playThread;
    
    BOOL    _pulling;
    
    NSTimer * _timer;
    
}
@property(strong,nonatomic)GJH264Decoder* videoDecoder;
@property(strong,nonatomic)GJPCMDecodeFromAAC* audioDecoder;

@property(strong,nonatomic)GJPlayer* player;
@property(assign,nonatomic)long sendByte;
@property(assign,nonatomic)long unitByte;

@property(assign,nonatomic)int gaterFrequency;


@property(strong,nonatomic)NSDate* startPullDate;
@property(strong,nonatomic)NSDate* connentDate;
@property(strong,nonatomic)NSDate* fristVideoDate;
@property(strong,nonatomic)NSDate* fristAudioDate;

@end
@implementation GJLivePull
- (instancetype)init
{
    self = [super init];
    if (self) {
        _player = [[GJPlayer alloc]init];
        _videoDecoder = [[GJH264Decoder alloc]init];
        _videoDecoder.delegate = self;
        _enablePreview = YES;
        _gaterFrequency = 2.0;
    }
    return self;
}

static void pullMessageCallback(GJRtmpPull* pull, GJRTMPPullMessageType messageType,void* rtmpPullParm,void* messageParm){
    GJLivePull* livePull = (__bridge GJLivePull *)(rtmpPullParm);
    LivePullMessageType message = kLivePullUnknownError;
    switch (messageType) {
        case GJRTMPPullMessageType_connectError:
        case GJRTMPPullMessageType_urlPraseError:
            message = kLivePullConnectError;
            [livePull stopStreamPull];
            break;
        case GJRTMPPullMessageType_sendPacketError:
            [livePull stopStreamPull];
            break;
            
        case GJRTMPPullMessageType_connectSuccess:
            livePull.connentDate = [NSDate date];
            message = kLivePullConnectSuccess;
            break;
        case GJRTMPPullMessageType_closeComplete:
            message = kLivePullCloseSuccess;
            break;
        default:
            break;
    }
    [livePull.delegate livePull:livePull messageType:message infoDesc:nil];
}



- (BOOL)startStreamPullWithUrl:(char*)url{
    
    GJAssert(_videoPull == NULL, "请先关闭上一个流\n");
    _pulling = true;
    GJRtmpPull_Create(&_videoPull, pullMessageCallback, (__bridge void *)(self));
    GJRtmpPull_StartConnect(_videoPull, pullDataCallback, (__bridge void *)(self),(const char*) url);
    [_audioDecoder start];
    _timer = [NSTimer scheduledTimerWithTimeInterval:_gaterFrequency repeats:YES block:^(NSTimer * _Nonnull timer) {
        CacheInfo info = _player.cache;
        [self.delegate livePull:self bitrate:_unitByte/_gaterFrequency cacheTime:info.cacheTime cacheFrame:info.cacheCount];
        _unitByte=0;
    }];
    _startPullDate = [NSDate date];
    return YES;
}

- (void)stopStreamPull{
    if (_videoPull) {
        [_audioDecoder stop];
        [_player stop];
        GJRtmpPull_CloseAndRelease(_videoPull);
        _videoPull = NULL;
        _pulling = NO;
    }
    _fristAudioDate = _fristVideoDate = _startPullDate = _connentDate = nil;
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
static void pullDataCallback(GJRtmpPull* pull,GJRTMPDataType dataType,GJRetainBuffer* buffer,void* parm,uint64_t pts){
    GJLivePull* livePull = (__bridge GJLivePull *)(parm);
    
    livePull.sendByte = livePull.sendByte + buffer->size;
    livePull.unitByte = livePull.unitByte + buffer->size;
    if (dataType == GJRTMPAudioData) {
        if (livePull.fristAudioDate == nil) {
            livePull.fristAudioDate = [NSDate date];
            uint8_t* adts = buffer->data;
            uint8_t sampleIndex = adts[2] << 2;
            sampleIndex = sampleIndex>>4;
            int sampleRate = mpeg4audio_sample_rates[sampleIndex];
            uint8_t channel = adts[2] & 0x1 <<2;
            channel += (adts[3] & 0xb0)>>6;
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
            [livePull.player start];
        }
        AudioStreamPacketDescription format;
        format.mDataByteSize = buffer->size;
        format.mStartOffset = 7;
        format.mVariableFramesInPacket = 0;
        [livePull.audioDecoder decodeBuffer:buffer packetDescriptions:&format pts:pts];
    }else if (dataType == GJRTMPVideoData) {
        [livePull.videoDecoder decodeBuffer:buffer pts:pts];
    }
}
-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(uint64_t)pts{
    [_player addVideoDataWith:imageBuffer pts:pts];
    return;    
}

-(void)pcmDecode:(GJPCMDecodeFromAAC *)decoder completeBuffer:(GJRetainBuffer *)buffer pts:(int)pts{
    [_player addAudioDataWith:buffer pts:pts];
}

@end
