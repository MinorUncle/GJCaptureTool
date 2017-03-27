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


@interface GJLivePull()<GJH264DecoderDelegate>
{
    GJRtmpPull* _videoPull;
    NSThread*  _playThread;
    
    BOOL    _pulling;
    
    NSTimer * _timer;
}
@property(strong,nonatomic)GJH264Decoder* videoDecoder;
@property(strong,nonatomic)GJPlayer* player;
@property(assign,nonatomic)long sendByte;
@property(assign,nonatomic)long unitByte;

@property(assign,nonatomic)int gaterFrequency;

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
    [_player start];
    _timer = [NSTimer scheduledTimerWithTimeInterval:_gaterFrequency repeats:YES block:^(NSTimer * _Nonnull timer) {
        [self.delegate livePull:self bitrate:_unitByte/_gaterFrequency cacheTime:_player.cacheTime];
        _unitByte=0;
    }];
    
    return YES;
}

- (void)stopStreamPull{
    if (_videoPull) {
        [_player stop];
        GJRtmpPull_CloseAndRelease(_videoPull);
        _videoPull = NULL;
        _pulling = NO;
    }
}

-(UIView *)getPreviewView{
    return _player.displayView;
}

-(void)setEnablePreview:(BOOL)enablePreview{
    _enablePreview = enablePreview;
    
}
static void pullDataCallback(GJRtmpPull* pull,GJRTMPDataType dataType,GJRetainBuffer* buffer,void* parm,uint32_t pts){
    GJLivePull* livePull = (__bridge GJLivePull *)(parm);
    
    livePull.sendByte = livePull.sendByte + buffer->size;
    livePull.unitByte = livePull.unitByte + buffer->size;
    if (dataType == GJRTMPAudioData) {
        [livePull.player addAudioDataWith:buffer pts:CMTimeMake(pts, 1000)];
    }else if (dataType == GJRTMPVideoData) {
        [livePull.videoDecoder decodeBuffer:buffer pts:CMTimeMake(pts, 1000)];
    }
}
-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(CMTime)pts{
    [_player addVideoDataWith:imageBuffer pts:pts];
    return;    
}

@end
