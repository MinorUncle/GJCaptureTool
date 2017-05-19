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
#import "GJLivePullContext.h"


@interface GJLivePull()
{
    GJRtmpPull* _videoPull;
    NSThread*  _playThread;
    GJPullSessionStatus _pullSessionStatus;
    
    GJLivePullContext* _pullContext;
}
@property(strong,nonatomic)GJH264Decoder* videoDecoder;
@property(strong,nonatomic)GJPCMDecodeFromAAC* audioDecoder;
@property(strong,nonatomic) NSRecursiveLock* lock;

@property(assign,nonatomic)GJLivePlayer* player;
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

static GVoid livePullCallback(GHandle userDate,GJLivePullMessageType message,GHandle param);

- (instancetype)init
{
    self = [super init];
    if (self) {
        GJLivePull_Create(_pullContext, livePullCallback, (__bridge GHandle)(self));
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
    GJTrafficStatus vCache = GJLivePull_GetVideoTrafficStatus(_pullContext);
    GJTrafficStatus aCache = GJLivePull_GetAudioTrafficStatus(_pullContext);
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
    return GJLivePull_StartPull(_pullContext, url);
}

- (void)stopStreamPull{
    return GJLivePull_StopPull(_pullContext);
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


static GBool imageReleaseCallback(GJRetainBuffer* buffer){
    CVPixelBufferRelease((CVImageBufferRef)buffer->data);
    return GFalse;
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


GVoid livePlayCallback(GHandle userDate,GJPlayMessage message,GHandle param){

}
-(void)dealloc{
    if (_videoPull) {
        GJRtmpPull_CloseAndRelease(_videoPull);
    }
}
@end
