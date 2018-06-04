//
//  GJLivePull.m
//  GJLivePull
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePull.h"
#import "GJH264Decoder.h"
#import "GJLivePlayer.h"
#import "GJLivePullContext.h"
#import "GJLog.h"
#import "GJPCMDecodeFromAAC.h"
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>

#ifdef USE_KCP
#include <xkcp_client.h>
#include <xkcp_config.h>
#endif

@interface GJLivePull () {
    NSThread *          _playThread;
    GJPullSessionStatus _pullSessionStatus;
    GJLivePullContext * _pullContext;
    NSString *          _pullUrl;
    BOOL                _shouldResume;
}
@property (strong, nonatomic) GJH264Decoder *     videoDecoder;
@property (strong, nonatomic) GJPCMDecodeFromAAC *audioDecoder;
@property (strong, nonatomic) NSRecursiveLock *   lock;

@property (assign, nonatomic) GJLivePlayer *player;
@property (assign, nonatomic) float         gaterFrequency;
@property (strong, nonatomic) NSTimer *     timer;

@property (assign, nonatomic) GJTrafficStatus videoTraffic;
@property (assign, nonatomic) GJTrafficStatus audioTraffic;

@end
@implementation GJLivePull

static GVoid livePullCallback(GHandle userDate, GJLivePullMessageType message, GHandle param);

- (instancetype)init {
    self = [super init];
    if (self) {
        GJLivePull_Create(&(_pullContext), livePullCallback, (__bridge GHandle)(self));
        _enablePreview  = YES;
        _gaterFrequency = 2.0;
        _lock           = [[NSRecursiveLock alloc] init];

#ifdef USE_KCP
        dispatch_once(&kcpOnceToken, ^{
            static dispatch_queue_t kcpQueue;
            kcpQueue = dispatch_queue_create("KCP_LOOP", DISPATCH_QUEUE_SERIAL);
            dispatch_async(kcpQueue, ^{
                struct xkcp_config *config = xkcp_get_config();
                config->main_loop          = client_main_loop;
                NSString *path             = [[NSBundle mainBundle] pathForResource:@"client" ofType:@"json"];
                if (![[NSFileManager defaultManager] fileExistsAtPath:path] || ![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
                    assert(0);
                }
                path = [NSString stringWithFormat:@"-c%@", path];
                char *arg[2];
                arg[0] = "kcpTun";
                arg[1] = (char *) path.UTF8String;
                xkcp_main(2, arg);
            });
        });
#endif
    }
    return self;
}

static void livePullCallback(GHandle pull, GJLivePullMessageType messageType, GHandle parm) {
    GJLivePull *livePull = (__bridge GJLivePull *) (pull);

    switch (messageType) {
        case GJLivePull_connectError:
        case GJLivePull_urlPraseError:
            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "pull connect error:%d", messageType);
            [livePull stopStreamPull];
            [livePull.delegate livePull:livePull errorType:kLivePullConnectError infoDesc:@"连接错误"];
            break;
        case GJLivePull_receivePacketError:
            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "pull readPacket error:%d", messageType);
            [livePull.delegate livePull:livePull errorType:kLivePullReadPacketError infoDesc:@"读取失败"];
            break;
        case GJLivePull_connectSuccess: {
            GJLOG(DEFAULT_LOG, GJ_LOGINFO, "pull connectSuccess");
            [livePull.delegate livePull:livePull connentSuccessWithElapsed:*(GInt32 *) parm];
        } break;
        case GJLivePull_closeComplete: {
            GJLOG(DEFAULT_LOG, GJ_LOGINFO, "pull closeComplete");
            [livePull.delegate livePull:livePull closeConnent:parm resion:kConnentCloce_Active];
        } break;
        case GJLivePull_bufferUpdate: {
            UnitBufferInfo *info = parm;
            if ([livePull.delegate respondsToSelector:@selector(livePull:bufferUpdatePercent:duration:)]) {
                [livePull.delegate livePull:livePull bufferUpdatePercent:info->percent duration:info->bufferDur];
            }
        } break;
        case GJLivePull_bufferStart: {
            UnitBufferInfo info = {0};
            if ([livePull.delegate respondsToSelector:@selector(livePull:bufferUpdatePercent:duration:)]) {
                [livePull.delegate livePull:livePull bufferUpdatePercent:info.percent duration:info.bufferDur];
            }
        } break;
        case GJLivePull_bufferEnd: {
            //            GJCacheInfo info;
        } break;
        case GJLivePull_decodeFristVideoFrame: {
            //                GJPullFristFrameInfo info = {0};
            //                info.size = *(GSize*)parm;
            [livePull.delegate livePull:livePull fristFrameDecode:parm];
        } break;
        case GJLivePull_dewateringUpdate: {
            if ([livePull.delegate respondsToSelector:@selector(livePull:dewaterUpdate:)]) {
                GBool dewatering = *(GBool *) parm;
                [livePull.delegate livePull:livePull dewaterUpdate:dewatering];
            }
        } break;
        case GJLivePull_netShakeUpdate: {
            if ([livePull.delegate respondsToSelector:@selector(livePull:netShakeUpdate:)]) {
                GLong time = *(GLong *) parm;
                [livePull.delegate livePull:livePull netShakeUpdate:(GLong) time];
            }
        } break;
        case GJLivePull_netShakeRangeUpdate: {
            if ([livePull.delegate respondsToSelector:@selector(livePull:netShakeRangeUpdate:)]) {
                GLong time = *(GLong *) parm;
                [livePull.delegate livePull:livePull netShakeRangeUpdate:(GLong) time];
            }
        } break;
#ifdef NETWORK_DELAY
        case GJLivePull_testNetShakeUpdate:
            if ([livePull.delegate respondsToSelector:@selector(livePull:testNetShake:)]) {
                GLong time = *(GLong *) parm;
                [livePull.delegate livePull:livePull testNetShake:(GLong) time];
            }
            break;
        case GJLivePull_testKeyDelayUpdate:
            if ([livePull.delegate respondsToSelector:@selector(livePull:testKeyDelay:)]) {
                GLong time = *(GLong *) parm;
                [livePull.delegate livePull:livePull testKeyDelay:(long) time];
            }
            break;
#endif
        case GJLivePull_decodeFristAudioFrame: {

        } break;
        default:
            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "not catch info：%d", messageType);
            break;
    }
}

- (void)updateStatusCallback {
    GJTrafficStatus vCache                        = GJLivePull_GetVideoTrafficStatus(_pullContext);
    GJTrafficStatus aCache                        = GJLivePull_GetAudioTrafficStatus(_pullContext);
    _pullSessionStatus.videoStatus.cacheCount     = vCache.enter.count - vCache.leave.count;
    _pullSessionStatus.videoStatus.cacheTime      = GTimeSubtractMSValue(vCache.enter.ts, vCache.leave.ts);
    _pullSessionStatus.videoStatus.bitrate        = (vCache.enter.byte - _videoTraffic.enter.byte) * 1.0 / _gaterFrequency;
    _pullSessionStatus.videoStatus.frameRate      = (vCache.leave.count - _videoTraffic.leave.count) * 1.0 / _gaterFrequency;
    _pullSessionStatus.videoStatus.lastReceivePts = vCache.enter.ts;

    _pullSessionStatus.audioStatus.cacheCount     = aCache.enter.count - aCache.leave.count;
    _pullSessionStatus.audioStatus.cacheTime      = GTimeSubtractMSValue(aCache.enter.ts, aCache.leave.ts);
    _pullSessionStatus.audioStatus.bitrate        = (aCache.enter.byte - _audioTraffic.enter.byte) * 1.0 / _gaterFrequency;
    _pullSessionStatus.audioStatus.frameRate      = (aCache.leave.count - _audioTraffic.leave.count) * 1.0 / _gaterFrequency;
    _pullSessionStatus.audioStatus.lastReceivePts = aCache.enter.ts;

    _videoTraffic = vCache;
    _audioTraffic = aCache;
    [self.delegate livePull:self updatePullStatus:&_pullSessionStatus];
#ifdef NETWORK_DELAY
    if (NeedTestNetwork) {
        if ([self.delegate respondsToSelector:@selector(livePull:networkDelay:)]) {
            [self.delegate livePull:self networkDelay:GJLivePull_GetNetWorkDelay(_pullContext)];
        }
    }
#endif
}

- (bool)startStreamPullWithUrl:(NSString *)url {
    if (_timer != nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "请先关闭上一个流");
        return NO;
    } else {
        if ([NSThread isMainThread]) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:self.gaterFrequency target:self selector:@selector(updateStatusCallback) userInfo:nil repeats:YES];
            GJLOG(DEFAULT_LOG, GJ_LOGINFO, "NSTimer PULL START:%s", [NSString stringWithFormat:@"%@", _timer].UTF8String);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                _timer = [NSTimer scheduledTimerWithTimeInterval:self.gaterFrequency target:self selector:@selector(updateStatusCallback) userInfo:nil repeats:YES];
                GJLOG(DEFAULT_LOG, GJ_LOGINFO, "NSTimer PULL START:%s", [NSString stringWithFormat:@"%@", _timer].UTF8String);
            });
        }

        _pullUrl = url;
        memset(&_videoTraffic, 0, sizeof(_videoTraffic));
        memset(&_audioTraffic, 0, sizeof(_audioTraffic));
        memset(&_pullSessionStatus, 0, sizeof(_pullSessionStatus));
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotic:) name:AVAudioSessionInterruptionNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];

        return GJLivePull_StartPull(_pullContext, url.UTF8String);
    }
}

- (void)stopStreamPull {
    if ([NSThread isMainThread]) {
        [_timer invalidate];
        _timer = nil;
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_timer invalidate];
            _timer = nil;
        });
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        GJLivePull_StopPull(_pullContext);
    });
}

- (UIView *)getPreviewView {
    return (__bridge UIView *) (GJLivePull_GetDisplayView(_pullContext));
}

- (void)setEnablePreview:(BOOL)enablePreview {
    _enablePreview = enablePreview;
}

- (void)dealloc {
    if (_pullContext) {
        GJLivePull_Dealloc(&(_pullContext));
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)receiveNotic:(NSNotification *)notic {
    if ([notic.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        AVAudioSessionInterruptionType type = [notic.userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
        //        AVAudioSessionInterruptionOptions option = [notic.userInfo[AVAudioSessionInterruptionOptionKey] integerValue];
        switch (type) {
            case AVAudioSessionInterruptionTypeBegan: {
                if (_timer != nil) {
                    GJLivePull_Pause(_pullContext);
                }
                GJLOG(GNULL, GJ_LOGDEBUG, "AVAudioSessionInterruptionTypeBegan should resulme:%d", _timer != nil);
                break;
            } break;
            case AVAudioSessionInterruptionTypeEnded:
                if (_timer != nil) {
                    if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
                        GJLivePull_Resume(_pullContext);
                    }
                }
                GJLOG(GNULL, GJ_LOGDEBUG, "AVAudioSessionInterruptionTypeEnd should resulme:%d", _timer != nil);
                break;

            default:
                break;
        }
    }
}

- (void)didBecomeActive:(NSNotification *)notic {
    if (_timer != nil) {
        GJLOG(GNULL, GJ_LOGDEBUG, "UIApplicationDidBecomeActiveNotification");
        GJLivePull_Resume(_pullContext);
    }
}

@end
