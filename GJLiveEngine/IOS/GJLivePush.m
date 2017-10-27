//
//  GJLivePush.m
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePush.h"
#import "GJLivePushContext.h"
#import "GJLog.h"

@interface GJLivePush () {

    GJLivePushContext *_livePush;
    NSTimer *          _timer;

    GJPushSessionStatus _pushSessionStatus;
    GJTrafficStatus     _audioInfo;
    GJTrafficStatus     _videoInfo;
    NSString *          _pushUrl;
    ;
}
@property (assign, nonatomic) float gaterFrequency;

@end

@implementation GJStickerAttribute

+ (instancetype)stickerAttributWithFrame:(GCRect)frame rotate:(CGFloat)rotate {
    GJStickerAttribute *attribute = [[GJStickerAttribute alloc] init];
    attribute.frame               = frame;
    attribute.rotate              = rotate;
    return attribute;
}

@end

@implementation GJLivePush
@synthesize     previewView = _previewView;

static GVoid audioMixFinishCallback(GHandle userData,const GChar* filePath, GHandle error){
    GJLivePush* self = (__bridge GJLivePush *)(userData);
    if ([self.delegate respondsToSelector:@selector(livePush:mixFileFinish:)]) {
        [self.delegate livePush:self mixFileFinish:[NSString stringWithUTF8String:filePath]];
    }
}
static GVoid livePushCallback(GHandle               userDate,
                              GJLivePushMessageType messageType,
                              GHandle               param) {
    GJLivePush *livePush = (__bridge GJLivePush *) (userDate);
    switch (messageType) {
        case GJLivePush_connectSuccess: {
            GJLOG(DEFAULT_LOG, GJ_LOGINFO, "推流连接成功");
            GLong elapsed = *(GLong *) param;
            dispatch_async(dispatch_get_main_queue(), ^{
                [livePush.delegate livePush:livePush connentSuccessWithElapsed:elapsed];
            });
        } break;
        case GJLivePush_closeComplete: {
            dispatch_async(dispatch_get_main_queue(), ^{
                GJPushSessionInfo info = {0};
                [livePush.delegate livePush:livePush
                               closeConnent:&info
                                     resion:kConnentCloce_Active];
            });
        } break;
        case GJLivePush_urlPraseError:
        case GJLivePush_connectError: {
            GJLOG(DEFAULT_LOG, GJ_LOGINFO, "推流连接失败");
            [livePush stopStreamPush];
            dispatch_async(dispatch_get_main_queue(), ^{
                [livePush.delegate livePush:livePush
                                  errorType:kLivePushConnectError
                                   infoDesc:@"rtmp连接失败"];
            });
        } break;
        case GJLivePush_sendPacketError: {
            [livePush stopStreamPush];
            dispatch_async(dispatch_get_main_queue(), ^{
                [livePush.delegate livePush:livePush
                                  errorType:kLivePushWritePacketError
                                   infoDesc:@"发送失败"];
            });
        } break;
        case GJLivePush_dynamicVideoUpdate: {
            VideoDynamicInfo info = *((VideoDynamicInfo *) param);
            dispatch_async(dispatch_get_main_queue(), ^{
                [livePush.delegate livePush:livePush
                         dynamicVideoUpdate:(VideoDynamicInfo *) &info];
            });
            break;
        }
        case GJLivePush_recodeComplete: {
            NSError *error = [((__bridge NSError *) (param)) copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                [livePush.delegate livePush:livePush UIRecodeFinish:error];
            });
            break;
        }
        default:
            break;
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _gaterFrequency      = 2.0;
        _livePush            = NULL;
        _mixFileNeedToStream = YES;
        GJLivePush_Create(&_livePush, livePushCallback, (__bridge GHandle)(self));
    }
    return self;
}

- (void)startPreview {
    GJLivePush_StartPreview(_livePush);
}

- (void)stopPreview {
    GJLivePush_StopPreview(_livePush);
}
- (UIView *)previewView {
    return (__bridge UIView *) (GJLivePush_GetDisplayView(_livePush));
}

- (void)setPushConfig:(GJPushConfig)pushConfig {
    _pushConfig = pushConfig;
    GJLivePush_SetConfig(_livePush, &_pushConfig);
}

- (bool)startStreamPushWithUrl:(NSString *)url {
    if (_timer != nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "请先关闭上一个流");
        return NO;
    } else {
        memset(&_videoInfo, 0, sizeof(_videoInfo));
        memset(&_audioInfo, 0, sizeof(_audioInfo));
        memset(&_pushSessionStatus, 0, sizeof(_pushSessionStatus));
        _pushUrl = url;
        if ([NSThread isMainThread]) {
            _timer   = [NSTimer scheduledTimerWithTimeInterval:_gaterFrequency
                                                        target:self
                                                      selector:@selector(updateGaterInfo:)
                                                      userInfo:nil
                                                       repeats:YES];
        }else{
            dispatch_async(dispatch_get_main_queue(), ^{
                _timer   = [NSTimer scheduledTimerWithTimeInterval:_gaterFrequency
                                                            target:self
                                                          selector:@selector(updateGaterInfo:)
                                                          userInfo:nil
                                                           repeats:YES];
            });
        }
       
        return GJLivePush_StartPush(_livePush, _pushUrl.UTF8String);
    }
}

- (void)stopStreamPush {
    if ([NSThread isMainThread]) {
        [_timer invalidate];
        _timer = nil;
    }else{
        dispatch_async(dispatch_get_main_queue(), ^{
            [_timer invalidate];
            _timer = nil;
        });
    }

    GJLivePush_StopPush(_livePush);
}

//- (bool)reStartStreamPush {
//    [self stopStreamPush];
//    return GJLivePush_StartPush(_livePush, _pushUrl.UTF8String);
//}

- (void)setAudioMute:(BOOL)audioMute {
    _audioMute = audioMute;
    GJLivePush_SetAudioMute(_livePush, audioMute);
}

- (void)setVideoMute:(BOOL)videoMute {
    _videoMute = videoMute;
    GJLivePush_SetVideoMute(_livePush, videoMute);
}

- (BOOL)startAudioMixWithFile:(NSURL *)fileUrl {
    return GJLivePush_StartMixFile(_livePush, fileUrl.path.UTF8String,audioMixFinishCallback);
}

- (void)stopAudioMix {
    GJLivePush_StopAudioMix(_livePush);
}

- (void)setInputVolume:(float)volume {
    GJLivePush_SetInputGain(_livePush, volume);
}

- (void)setMixVolume:(float)volume {
    GJLivePush_SetMixVolume(_livePush, volume);
}

- (void)setMasterOutVolume:(float)volume {
    GJLivePush_SetOutVolume(_livePush, volume);
}

- (BOOL)enableAudioInEarMonitoring:(BOOL)enable {
    return GJLivePush_EnableAudioInEarMonitoring(_livePush, enable);
}

- (BOOL)enableReverb:(BOOL)enable {
    return GJLivePush_EnableReverb(_livePush, enable);
}

- (void)setMeasurementMode:(BOOL)measurementMode {
    GBool ret = GJLivePush_SetMeasurementMode(_livePush, measurementMode);
    if (ret) {
        _measurementMode = measurementMode;
    }
}

- (void)setMixFileNeedToStream:(BOOL)mixFileNeedToStream {
    _mixFileNeedToStream = mixFileNeedToStream;
    GJLivePush_ShouldMixAudioToStream(_livePush, mixFileNeedToStream);
}
static int restartCount;
- (void)updateGaterInfo:(NSTimer *)timer {
    GJTrafficStatus vInfo = GJLivePush_GetVideoTrafficStatus(_livePush);
    GJTrafficStatus aInfo = GJLivePush_GetAudioTrafficStatus(_livePush);

    _pushSessionStatus.videoStatus.cacheTime = vInfo.enter.ts - vInfo.leave.ts;
    _pushSessionStatus.videoStatus.frameRate =
        (vInfo.leave.count - _videoInfo.leave.count) / _gaterFrequency;
    _pushSessionStatus.videoStatus.bitrate =
        (vInfo.leave.byte - _videoInfo.leave.byte) / _gaterFrequency;
    _pushSessionStatus.videoStatus.cacheCount =
        vInfo.enter.count - vInfo.leave.count;
    _videoInfo = vInfo;

    _pushSessionStatus.audioStatus.cacheTime = aInfo.enter.ts - aInfo.leave.ts;
    _pushSessionStatus.audioStatus.frameRate =
        (aInfo.leave.count - _audioInfo.leave.count) * 1024.0 / _gaterFrequency;
    _pushSessionStatus.audioStatus.bitrate =
        (aInfo.leave.byte - _audioInfo.leave.byte) / _gaterFrequency;
    _pushSessionStatus.audioStatus.cacheCount =
        aInfo.enter.count - aInfo.leave.count;
    _audioInfo = aInfo;

    [_delegate livePush:self updatePushStatus:&_pushSessionStatus];
    if (vInfo.enter.ts - vInfo.leave.ts > MAX_SEND_DELAY) {//延迟过多重启
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "推流缓存过多，重新启动推流");
        restartCount++;
        [self stopStreamPush];
        [self startStreamPushWithUrl:_pushUrl];
    }
}

- (void)setCameraPosition:(GJCameraPosition)cameraPosition {
    _cameraPosition = cameraPosition;
    GJLivePush_SetCameraPosition(_livePush, cameraPosition);
}

- (void)setOutOrientation:(GJInterfaceOrientation)outOrientation {
    _outOrientation = outOrientation;
    GJLivePush_SetOutOrientation(_livePush, outOrientation);
}

- (BOOL)startUIRecodeWithRootView:(UIView *)view
                              fps:(NSInteger)fps
                         filePath:(NSURL *)file {
    return GJLivePush_StartRecode(_livePush, (__bridge GView)(view), (GInt32) fps,
                                  file.path.UTF8String);
}

- (void)stopUIRecode {
    GJLivePush_StopRecode(_livePush);
}

static GStickerParm stickerUpdateCallback(const GHandle userDate, GLong index,
                                          GBool *ioFinsh) {

    StickersUpdate      block = (__bridge StickersUpdate)(userDate);
    GJStickerAttribute *attr  = block(index, (BOOL *) ioFinsh);
    GStickerParm        parm;
    parm.frame    = attr.frame;
    parm.rotation = attr.rotate;
    if (*ioFinsh) {
        id tem = CFBridgingRelease(userDate); //释放
        tem    = nil;
    }
    return parm;
}

- (BOOL)startStickerWithImages:(NSArray<UIImage *> *)images
                     attribure:(GJStickerAttribute *)attribure
                           fps:(NSInteger)fps
                   updateBlock:(StickersUpdate)updateBlock {
    GStickerParm parm;
    parm.frame    = attribure.frame;
    parm.rotation = attribure.rotate;
    return GJLivePush_StartSticker(_livePush, CFBridgingRetain(images), parm,
                                   (GInt32) fps, stickerUpdateCallback,
                                   (GVoid*)CFBridgingRetain(updateBlock));
}

- (void)chanceSticker {
    GJLivePush_StopSticker(_livePush);
}

- (CGSize)captureSize {
    GSize size = GJLivePush_GetCaptureSize(_livePush);
    return CGSizeMake(size.width, size.height);
}
#pragma mark rtmp callback

#pragma mark delegate

- (void)dealloc {
    if (_livePush) {
        GJLivePush_Dealloc(&_livePush);
    }
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJLivePush");
}
@end
