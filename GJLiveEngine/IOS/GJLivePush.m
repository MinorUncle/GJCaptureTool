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
#import <UIKit/UIApplication.h>
#import "IOS_VideoProduce.h"
#import "IOS_AudioProduce.h"

#ifdef USE_KCP
#include <xkcp_client.h>
#include <xkcp_config.h>
#endif

@interface GJLivePush () {
    GJLivePushContext *_livePush;
    NSTimer *          _timer;

    GJPushSessionStatus    _pushSessionStatus;
    GJTrafficStatus        _audioInfo;
    GJTrafficStatus        _videoInfo;
    NSString *             _pushUrl;
    GHandle                _stickerCallback;
    GJVideoProduceContext *_videoProducer;
    GJAudioProduceContext *_audioProducer;
}

@property (assign, nonatomic) float gaterFrequency;
@end

@implementation GJLivePush
@synthesize     previewView = _previewView;

- (instancetype)init {
    self = [super init];
    if (self) {
        _gaterFrequency      = 2.0;
        _livePush            = NULL;
        _mixFileNeedToStream = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:UIApplicationDidBecomeActiveNotification object:nil];

        GJ_VideoProduceContextCreate(&_videoProducer);
        GJ_AudioProduceContextCreate(&_audioProducer);

        GJLivePush_Create(&_livePush, livePushCallback, (__bridge GHandle)(self));
        _videoProducer->videoProduceSetup(_videoProducer, GNULL, GNULL);
        _audioProducer->audioProduceSetup(_audioProducer, GNULL, GNULL);

        GJLivePush_AttachAudioProducer(_livePush, _audioProducer);
        GJLivePush_AttachVideoProducer(_livePush, _videoProducer);

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

- (void)setPushConfig:(GJPushConfig)pushConfig {
    _pushConfig = pushConfig;
    GJLivePush_SetConfig(_livePush, &_pushConfig);

    GJPixelFormat format;
    format.mHeight = pushConfig.mPushSize.height;
    format.mWidth  = pushConfig.mPushSize.width;
    format.mType   = GJPixelType_YpCbCr8BiPlanar_Full;
    _videoProducer->setPixelformat(_videoProducer, &format);
    _videoProducer->setFrameRate(_videoProducer, pushConfig.mFps);

    GJAudioFormat aFormat     = {0};
    aFormat.mBitsPerChannel   = 16;
    aFormat.mType             = GJAudioType_PCM;
    aFormat.mFramePerPacket   = 1;
    aFormat.mSampleRate       = pushConfig.mAudioSampleRate;
    aFormat.mChannelsPerFrame = pushConfig.mAudioChannel;
    _audioProducer->setAudioFormat(_audioProducer, aFormat);
}

- (bool)startStreamPushWithUrl:(NSString *)url {
    @synchronized(self){
        if (_timer != nil) {
            GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "请先关闭上一个流");
            return NO;
        } else {
            GJLOG(GNULL, GJ_LOGDEBUG, "%p",self);
            memset(&_videoInfo, 0, sizeof(_videoInfo));
            memset(&_audioInfo, 0, sizeof(_audioInfo));
            memset(&_pushSessionStatus, 0, sizeof(_pushSessionStatus));
            _pushUrl = url;
            _timer = [NSTimer timerWithTimeInterval:_gaterFrequency target:self selector:@selector(updateGaterInfo:) userInfo:nil repeats:YES];
            if ([NSThread isMainThread]) {
                [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
            } else {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    if (_timer) {
                        [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
                    }
                });
            }
            _audioProducer->audioProduceStart(_audioProducer);
            _videoProducer->startProduce(_videoProducer);
            return GJLivePush_StartPush(_livePush, _pushUrl.UTF8String);
        }
    }
}

- (void)stopStreamPush {
    @synchronized(self){
        if (_timer) {
            GJLOG(GNULL, GJ_LOGDEBUG, "%p",self);
            [_timer invalidate];
            _timer = nil;
            _audioProducer->audioProduceStop(_audioProducer);
            _videoProducer->stopProduce(_videoProducer);
            GJLivePush_StopPush(_livePush);
        }
    }
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

- (UIImage *_Nullable)captureFreshDisplayImage {
    GHandle image = _videoProducer->getFreshDisplayImage(_videoProducer);
    return CFBridgingRelease(image);
}

- (BOOL)startStickerWithImages:(NSArray<GJOverlayAttribute *> *)images
                           fps:(NSInteger)fps
                   updateBlock:(OverlaysUpdate)updateBlock {
    @synchronized(self) {
        GJLOG(GNULL, GJ_LOGDEBUG, "%ld", (long)fps);
        if (_stickerCallback != GNULL) {
            [self chanceSticker];
        }
        _stickerCallback = (void *) CFBridgingRetain(updateBlock);
        return _videoProducer->addSticker(_videoProducer, (__bridge_retained const GVoid *) (images), (GInt32) fps, stickerUpdateCallback, _stickerCallback);
    }
}

- (void)chanceSticker {
    @synchronized(self) {
        _videoProducer->chanceSticker(_videoProducer);
        if (_stickerCallback) {
            id tem           = CFBridgingRelease(_stickerCallback); //释放回调block
            tem              = nil;
            _stickerCallback = GNULL;
        }
    }
}

- (BOOL)startTrackingImageWithImages:(NSArray<UIImage *> *)images initFrame:(GCRect)frame {
    return _videoProducer->startTrackImage(_videoProducer, (__bridge_retained const GVoid *) (images), frame);
}

- (void)stopTracking {
    _videoProducer->stopTrackImage(_videoProducer);
}

- (void)dealloc {
    @synchronized(self) {
        if (_stickerCallback) {
            [self chanceSticker];
        }
    }

    if (_livePush) {

        GJLivePush_DetachVideoProducer(_livePush);
        GJLivePush_DetachAudioProducer(_livePush);
        GJLivePush_Dealloc(&_livePush);
    }
    if (_audioProducer) {
        _audioProducer->audioProduceUnSetup(_audioProducer);
        GJ_AudioProduceContextDealloc(&_audioProducer);
        _audioProducer = GNULL;
    }
    if (_videoProducer) {
        _videoProducer->videoProduceUnSetup(_videoProducer);
        GJ_VideoProduceContextDealloc(&_videoProducer);
        _videoProducer = GNULL;
    }
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, ":%s", self.description.UTF8String);
}
//- (bool)reStartStreamPush {
//    [self stopStreamPush];
//    return GJLivePush_StartPush(_livePush, _pushUrl.UTF8String);
//}

#pragma mark audio property

- (void)setAudioMute:(BOOL)audioMute {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", audioMute);
    _audioMute = audioMute;
    _audioProducer->setMute(_audioProducer, audioMute);
}

- (BOOL)startAudioMixWithFile:(NSURL *)fileUrl {
    GJLOG(GNULL, GJ_LOGDEBUG, "%s", fileUrl.description.UTF8String);

    GBool result = _audioProducer->setupMixAudioFile(_audioProducer, fileUrl.path.UTF8String, GFalse, audioMixFinishCallback, (__bridge GHandle)(self));
    if (result != GFalse) {
        result = _audioProducer->startMixAudioFileAtTime(_audioProducer, 0);
    }
    return result;
}

- (void)stopAudioMix {
    GJLOG(GNULL, GJ_LOGDEBUG, "%p", _audioProducer);
    _audioProducer->stopMixAudioFile(_audioProducer);
}

- (void)setEnableAec:(BOOL)enableAec {
    GJLOG(GNULL, GJ_LOGDEBUG, ":%p", _audioProducer);
    if (_audioProducer->enableAudioEchoCancellation(_audioProducer, enableAec)) {
        _enableAec = enableAec;
    }
}

- (void)setInputVolume:(float)volume {
    GJLOG(GNULL, GJ_LOGDEBUG, "%f", volume);
    if (_audioProducer->enableAudioEchoCancellation(_audioProducer, volume)) {
        _inputVolume = volume;
    }
}

- (void)setMixVolume:(float)mixVolume {
    GJLOG(GNULL, GJ_LOGDEBUG, "%f", mixVolume);

    if (_audioProducer->setMixVolume(_audioProducer, mixVolume)) {
        _mixVolume = mixVolume;
    }
}

- (void)setMasterOutVolume:(float)masterOutVolume {
    GJLOG(GNULL, GJ_LOGDEBUG, "%f", masterOutVolume);

    if (_audioProducer->setOutVolume(_audioProducer, masterOutVolume)) {
        _masterOutVolume = masterOutVolume;
    }
}

- (void)enableReverb:(BOOL)reverb {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", reverb);

    if (_audioProducer->enableReverb(_audioProducer, reverb)) {
        _reverb = reverb;
    }
}

- (void)enableAudioInEarMonitoring:(BOOL)audioInEarMonitoring {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", audioInEarMonitoring);

    if (_audioProducer->enableAudioInEarMonitoring(_audioProducer, audioInEarMonitoring)) {
        _audioInEarMonitoring = audioInEarMonitoring;
    }
}

- (void)setMeasurementMode:(BOOL)measurementMode {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", measurementMode);

    if (_audioProducer->enableMeasurementMode(_audioProducer, measurementMode)) {
        _measurementMode = measurementMode;
    }
}

- (void)setMixFileNeedToStream:(BOOL)mixFileNeedToStream {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", mixFileNeedToStream);

    if (_audioProducer->setMixToStream(_audioProducer, mixFileNeedToStream)) {
        _mixFileNeedToStream = mixFileNeedToStream;
    }
}

#pragma mark video property

- (void)setVideoMute:(BOOL)videoMute {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", videoMute);

    _videoMute = videoMute;
    _audioProducer->setMute(_audioProducer, videoMute);
}

- (void)setARScene:(id<GJImageARScene>)ARScene {
    _videoProducer->setARScene(_videoProducer, (__bridge GHandle)(ARScene));
    _ARScene = ARScene;
}

- (void)setCaptureView:(UIView *)captureView {
    GJLOG(GNULL, GJ_LOGDEBUG, "%s", captureView.description.UTF8String);

    _videoProducer->setCaptureView(_videoProducer, (__bridge GView)(captureView));
    _captureView = captureView;
}

- (void)setCaptureType:(GJCaptureType)captureType {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", captureType);

    if (_videoProducer->setCaptureType(_videoProducer, captureType)) {
        _captureType = captureType;
    };
}

- (void)startPreview {
    GJLOG(GNULL, GJ_LOGDEBUG, "%p", _videoProducer);
    _videoProducer->startPreview(_videoProducer);
}

- (void)stopPreview {
    GJLOG(GNULL, GJ_LOGDEBUG, "%p", _videoProducer);

    _videoProducer->stopPreview(_videoProducer);
}

- (UIView *)previewView {

    return (__bridge UIView *) _videoProducer->getRenderView(_videoProducer);
}

- (void)setCameraMirror:(BOOL)cameraMirror {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", cameraMirror);

    if (_videoProducer->setHorizontallyMirror(_videoProducer, cameraMirror)) {
        _cameraMirror = cameraMirror;
    }
}

- (void)setStreamMirror:(BOOL)streamMirror {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", streamMirror);

    if (_videoProducer->setStreamMirror(_videoProducer, streamMirror)) {
        _streamMirror = streamMirror;
    }
}

- (void)setPreviewMirror:(BOOL)previewMirror {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", previewMirror);

    if (_videoProducer->setPreviewMirror(_videoProducer, previewMirror)) {
        _previewMirror = previewMirror;
    }
}

- (void)setCameraPosition:(GJCameraPosition)cameraPosition {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", cameraPosition);

    if (_videoProducer->setCameraPosition(_videoProducer, cameraPosition)) {
        _cameraPosition = cameraPosition;
    }
}

- (void)setOutOrientation:(GJInterfaceOrientation)outOrientation {
    GJLOG(GNULL, GJ_LOGDEBUG, "%d", outOrientation);

    if (_videoProducer->setOrientation(_videoProducer, outOrientation)) {
        _outOrientation = outOrientation;
    }
}

- (CGSize)captureSize {
    GSize size = _videoProducer->getCaptureSize(_videoProducer);
    return CGSizeMake(size.width, size.height);
}


#pragma mark VIDEO EFFECT
-(BOOL)prepareVideoEffectWithBaseData:(NSString*)dataPath{
    return _videoProducer->prepareVideoEffectWithBaseData(_videoProducer,dataPath.UTF8String);
}
-(void)chanceVideoEffect{
    _videoProducer->chanceVideoEffect(_videoProducer);
}

-(void)setBrightness:(NSInteger)brightness{
    _brightness = brightness;
    _videoProducer->brightness(_videoProducer,brightness);
}

-(void)setSkinRuddy:(NSInteger)skinRuddy{
    _skinRuddy = skinRuddy;
    _videoProducer->skinRuddy(_videoProducer,skinRuddy);
}

-(void)setSkinSoften:(NSInteger)skinSoften{
    _skinSoften = skinSoften;
    _videoProducer->skinSoften(_videoProducer,skinSoften);
}

-(void)setEyeEnlargement:(NSInteger)eyeEnlargement{
    _eyeEnlargement = eyeEnlargement;
    _videoProducer->eyeEnlargement(_videoProducer,eyeEnlargement);
}

-(void)setFaceSlender:(NSInteger)faceSlender{
    _faceSlender = faceSlender;
    _videoProducer->faceSlender(_videoProducer,faceSlender);
}

- (BOOL) updateFaceStickTemplatePath:(NSString*)dataPath{
   return _videoProducer->updateFaceStickTemplatePath(_videoProducer,dataPath.UTF8String);
}
#pragma mark GJLIvePush callback
static GVoid audioMixFinishCallback(GHandle userData, const GChar *filePath, GHandle error) {
    GJLivePush *self = (__bridge GJLivePush *) (userData);
    if ([self.delegate respondsToSelector:@selector(livePush:mixFileFinish:)]) {
        NSString* path = [NSString stringWithUTF8String:filePath];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate livePush:self mixFileFinish:path];
        });
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
            // [livePush stopStreamPush];//底层已经停止了，这里不需要重复
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
        case GJLivePush_recodeSuccess: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [livePush.delegate livePush:livePush recodeFinish:nil];
            });
            break;
        }
        case GJLivePush_recodeFaile: {
            NSError *error = [[NSError alloc] init];
            dispatch_async(dispatch_get_main_queue(), ^{
                [livePush.delegate livePush:livePush recodeFinish:error];
            });
            break;
        }
        default:
            break;
    }
}

- (void)updateGaterInfo:(NSTimer *)timer {
    GJTrafficStatus vInfo                    = GJLivePush_GetVideoTrafficStatus(_livePush);
    GJTrafficStatus aInfo                    = GJLivePush_GetAudioTrafficStatus(_livePush);
    GTime           vTime                    = GTimeSubtract(vInfo.enter.ts, vInfo.leave.ts);
    _pushSessionStatus.videoStatus.cacheTime = (GLong)(GTimeMSValue(vTime));
    _pushSessionStatus.videoStatus.frameRate =
        (vInfo.leave.count - _videoInfo.leave.count) / _gaterFrequency;
    _pushSessionStatus.videoStatus.bitrate =
        (vInfo.leave.byte - _videoInfo.leave.byte) / _gaterFrequency;
    _pushSessionStatus.videoStatus.cacheCount =
        vInfo.enter.count - vInfo.leave.count;
    _videoInfo = vInfo;

    GTime aTime                              = GTimeSubtract(aInfo.enter.ts, aInfo.leave.ts);
    _pushSessionStatus.audioStatus.cacheTime = (GLong)(GTimeMSValue(aTime));
    _pushSessionStatus.audioStatus.frameRate =
        (aInfo.leave.count - _audioInfo.leave.count) * 1024.0 / _gaterFrequency;
    _pushSessionStatus.audioStatus.bitrate =
        (aInfo.leave.byte - _audioInfo.leave.byte) / _gaterFrequency;
    _pushSessionStatus.audioStatus.cacheCount =
        aInfo.enter.count - aInfo.leave.count;
    _audioInfo = aInfo;

    [_delegate livePush:self updatePushStatus:&_pushSessionStatus];
    if (GTimeMSValue(vTime) > MAX_SEND_DELAY &&      //延迟过多重启
        vInfo.enter.count - vInfo.leave.count > 2) { //防止初始ts不为0导致一直重启
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "推流缓存过多，重新启动推流");
        [self stopStreamPush];
        [self startStreamPushWithUrl:_pushUrl];
    }
}

static void stickerUpdateCallback(const GHandle userDate, GLong index, const GHandle parm,
                                  GBool *ioFinsh) {

    OverlaysUpdate block = GNULL;
    if (userDate != GNULL) {
        block = (__bridge OverlaysUpdate)(userDate);
    }

    if (block) {
        const GJOverlayAttribute *attr = (__bridge const GJOverlayAttribute *) parm;
        block(index, attr, (BOOL *) ioFinsh);
        if (*ioFinsh) {
            id tem = CFBridgingRelease(userDate); //释放回调block
            tem    = nil;
        }
    }
}

- (void)receiveNotification:(NSNotification *)notic {
    if ([notic.name isEqualToString:UIApplicationWillResignActiveNotification]) {

    }else if([notic.name isEqualToString:UIApplicationDidBecomeActiveNotification]){
        
    }
}


@end
