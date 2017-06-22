//
//  GJLivePush.m
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePush.h"
#import "GJLog.h"
#import "GJLivePushContext.h"

@interface GJLivePush()
{
    
    GJLivePushContext* _livePush;
    NSTimer*        _timer;
    
    GJPushSessionStatus _pushSessionStatus;
    GJTrafficStatus        _audioInfo;
    GJTrafficStatus        _videoInfo;
    NSString* _pushUrl;;
}
@property(assign,nonatomic)float gaterFrequency;
@end

@implementation GJLivePush
@synthesize previewView = _previewView;
static GVoid livePushCallback(GHandle userDate,GJLivePushMessageType messageType,GHandle param){
    GJLivePush* livePush = (__bridge GJLivePush *)(userDate);
        switch (messageType) {
            case GJLivePush_connectSuccess:
            {
                GJLOG(GJ_LOGINFO, "推流连接成功");
                GLong elapsed = *(GLong*)param;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [livePush.delegate livePush:livePush connentSuccessWithElapsed:elapsed];
                });
            }
                break;
            case GJLivePush_closeComplete:
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    GJPushSessionInfo info = {0};
                    [livePush.delegate livePush:livePush closeConnent:&info resion:kConnentCloce_Active];
                });
            }
                break;
            case GJLivePush_urlPraseError:
            case GJLivePush_connectError:
            {
                GJLOG(GJ_LOGINFO, "推流连接失败");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [livePush.delegate livePush:livePush errorType:kLivePushConnectError infoDesc:@"rtmp连接失败"];
                    [livePush stopStreamPush];
                });
            }
                break;
            case GJLivePush_sendPacketError:
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [livePush.delegate livePush:livePush errorType:kLivePushWritePacketError infoDesc:@"发送失败"];
                    [livePush stopStreamPush];
                });
            }
                break;
            case GJLivePush_dynamicVideoUpdate:
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [livePush.delegate livePush:livePush dynamicVideoUpdate:param];
                });
                break;
            }
            default:
                break;
        }
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        
        _gaterFrequency = 2.0;
        _livePush = NULL;
        GJLivePush_Create(&_livePush, livePushCallback, (__bridge GHandle)(self));
    }
    return self;
}


- (void)startPreview{
    GJLivePush_StartPreview(_livePush);
}

- (void)stopPreview{
    GJLivePush_StopPreview(_livePush);
}
-(UIView *)getPreviewView{
    return (__bridge UIView *)(GJLivePush_GetDisplayView(_livePush));
}

-(void)setPushConfig:(GJPushConfig)pushConfig{
    _pushConfig = pushConfig;
    GJLivePush_SetConfig(_livePush, &_pushConfig);
}
- (bool)startStreamPushWithUrl:(NSString *)url{
    if (_timer != nil) {
        GJLOG(GJ_LOGFORBID, "请先关闭上一个流");
        return NO;
    }else{
        _pushUrl = url;
        _timer = [NSTimer scheduledTimerWithTimeInterval:_gaterFrequency target:self selector:@selector(updateGaterInfo:) userInfo:nil repeats:YES];
        return GJLivePush_StartPush(_livePush, _pushUrl.UTF8String);
    }
}
- (void)stopStreamPush{
    [_timer invalidate];
    _timer = nil;
    GJLivePush_StopPush(_livePush);
}

- (bool)reStartStreamPush{
    [self stopStreamPush];
    return GJLivePush_StartPush(_livePush, _pushUrl.UTF8String);
}

-(void)setAudioMute:(BOOL)audioMute{
    _audioMute = audioMute;
    GJLivePush_SetAudioMute(_livePush, audioMute);
}
-(void)setVideoMute:(BOOL)videoMute{
    _videoMute = videoMute;
    GJLivePush_SetVideoMute(_livePush, videoMute);
}
-(BOOL)startAudioMixWithFile:(NSURL*)fileUrl{
    return GJLivePush_StartMixFile(_livePush, fileUrl.path.UTF8String);
}
-(void)stopAudioMix{
    GJLivePush_StopAudioMix(_livePush);
}
-(BOOL)enableAudioInEarMonitoring:(BOOL)enable{
    return GJLivePush_EnableAudioInEarMonitoring(_livePush, enable);
}
-(void)updateGaterInfo:(NSTimer*)timer{
    GJTrafficStatus vInfo = GJLivePush_GetVideoTrafficStatus(_livePush);
    GJTrafficStatus aInfo = GJLivePush_GetAudioTrafficStatus(_livePush);
    
    _pushSessionStatus.videoStatus.cacheTime = vInfo.enter.pts - vInfo.leave.pts;
    _pushSessionStatus.videoStatus.frameRate = (vInfo.leave.count - _videoInfo.leave.count)/_gaterFrequency;
    _pushSessionStatus.videoStatus.bitrate = (vInfo.leave.byte - _videoInfo.leave.byte)/_gaterFrequency;
    _videoInfo = vInfo;
    
    _pushSessionStatus.audioStatus.cacheTime = aInfo.enter.pts - aInfo.leave.pts;
    _pushSessionStatus.audioStatus.frameRate = (aInfo.leave.count - _audioInfo.leave.count)*1024.0/_gaterFrequency;
    _pushSessionStatus.audioStatus.bitrate = (aInfo.leave.byte - _audioInfo.leave.byte)/_gaterFrequency;
    _audioInfo = aInfo;
    [_delegate livePush:self updatePushStatus:&_pushSessionStatus];
    if (vInfo.enter.pts - vInfo.leave.pts > MAX_SEND_DELAY) {
        [self reStartStreamPush];
    }
}
-(void)setCameraPosition:(GJCameraPosition)cameraPosition{
    GJLivePush_SetCameraPosition(_livePush, cameraPosition);
}
-(void)setOutOrientation:(GJInterfaceOrientation)outOrientation{
    GJLivePush_SetOutOrientation(_livePush, outOrientation);
}
#pragma mark rtmp callback

#pragma mark delegate



//-(float)GJH264Encoder:(GJH264Encoder*)encoder encodeCompleteBuffer:(GJRetainBuffer*)buffer keyFrame:(BOOL)keyFrame pts:(int64_t)pts{
////    printf("video Pts:%d\n",(int)pts.value*1000/pts.timescale);
//}
//-(void)GJH264Encoder:(GJH264Encoder *)encoder qualityQarning:(GJEncodeQuality)quality{
//    _pushSessionStatus.netWorkQuarity = (GJNetworkQuality)quality;
//}
//-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder *)recoder pcmPacket:(R_GJPCMFrame *)packet{
//    packet->pts = [[NSDate date]timeIntervalSinceDate:_fristFrameDate] * 1000;
//    [_audioEncoder encodeWithPacket:packet];
//}
//-(void)AACEncoderFromPCM:(AACEncoderFromPCM *)encoder completeBuffer:(R_GJAACPacket *)packet{
//#ifdef GJPUSHAUDIOQUEUEPLAY_TEST
//    if (_audioTestPlayer == nil) {
//        _audioTestPlayer = [[GJAudioQueuePlayer alloc]initWithFormat:recoder.format maxBufferSize:2000 macgicCookie:nil];
//        [_audioTestPlayer start];
//    }else{
//        retainBufferMoveDataPoint(dataBuffer, 7);
//        [_audioTestPlayer playData:dataBuffer packetDescriptions:packetDescriptions];
//    }
//    return;
//#endif
//    
////    static int times;
////    NSData* audio = [NSData dataWithBytes:packet->aacOffset+packet->retain.data length:packet->aacSize];
////    NSData* adts = [NSData dataWithBytes:packet->adtsOffset+packet->retain.data length:packet->adtsSize];
////    NSLog(@"pushaudio times:%d,audioSize:%d,adts%@,audio:%@",times++,packet->aacSize,adts,audio);
//
//#ifdef GJPCMDecodeFromAAC_TEST
//    [_audioDecode decodePacket:packet];
//    return;
//#endif
//    GJRtmpPush_SendAACData(_videoPush, packet);
//
//}

//-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder*) recoder streamPacket:(R_GJAACPacket *)packet{
////    static int times =0;
////    NSData* audio = [NSData dataWithBytes:packet->aac length:MIN(packet->aacSize,10)];
////    NSData* adts = [NSData dataWithBytes:packet->adts length:packet->adtsSize];
////    NSLog(@"pushaudio times:%d ,adts%@,audio:%@,audioSize:%d",times++,adts,audio,packet->aacSize);
//
//}
-(void)dealloc{
    if (_livePush) {
        GJLivePush_Dealloc(&_livePush);
    }
    GJLOG(GJ_LOGDEBUG, "GJLivePush");
}
@end
