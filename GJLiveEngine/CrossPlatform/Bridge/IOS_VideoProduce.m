//
//  IOS_VideoProduce.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_VideoProduce.h"
#import "GJBufferPool.h"
#import "GJImageBeautifyFilter.h"
#import "GJImagePictureOverlay.h"
#import "GJImageView.h"
#import "GJLiveDefine.h"
#import "GJLog.h"
#import "GPUImageVideoCamera.h"
#import "GJImageARCapture.h"
#import <stdlib.h>
typedef enum { //filter深度
    kFilterCamera = 0,
    kFilterBeauty,
    kFilterSticker,
} GJFilterDeep;
typedef void (^VideoRecodeCallback)(R_GJPixelFrame *frame);

static GVoid pixelReleaseCallBack(GJRetainBuffer *buffer, GHandle userData) {
    CVPixelBufferRef image = ((CVPixelBufferRef *) R_BufferStart(buffer))[0];
    CVPixelBufferRelease(image);
}

BOOL getCaptureInfoWithSize(CGSize size, CGSize *captureSize, NSString **sessionPreset) {
    *captureSize   = CGSizeZero;
    *sessionPreset = nil;
    return YES;
}

CGSize getCaptureSizeWithSize(CGSize size) {
    CGSize captureSize;
    if (size.width <= 352 && size.height <= 288) {
        captureSize = CGSizeMake(352, 288);
    } else if (size.width <= 640 && size.height <= 480) {
        captureSize = CGSizeMake(640, 480);
    } else if (size.width <= 1280 && size.height <= 720) {
        captureSize = CGSizeMake(1280, 720);
    } else if (size.width <= 1920 && size.height <= 1080) {
        captureSize = CGSizeMake(1920, 1080);
    } else {
        captureSize = CGSizeMake(3840, 2160);
    }
    return captureSize;
}

NSString *getCapturePresetWithSize(CGSize size) {
    NSString *capturePreset;
    if (size.width <= 353 && size.height <= 289) {
        capturePreset = AVCaptureSessionPreset352x288;
    } else if (size.width <= 641 && size.height <= 481) {
        capturePreset = AVCaptureSessionPreset640x480;
    } else if (size.width <= 1281 && size.height <= 721) {
        capturePreset = AVCaptureSessionPreset1280x720;
    } else if (size.width <= 1921 && size.height <= 1081) {
        capturePreset = AVCaptureSessionPreset1920x1080;
    } else {
        capturePreset = AVCaptureSessionPreset3840x2160;
    }
    return capturePreset;
}

NSString *getSessionPresetWithSizeType(GJCaptureSizeType sizeType) {
    NSString *preset = nil;
    switch (sizeType) {
        case kCaptureSize352_288:
            preset = AVCaptureSessionPreset352x288;
            break;
        case kCaptureSize640_480:
            preset = AVCaptureSessionPreset640x480;
            break;
        case kCaptureSize1280_720:
            preset = AVCaptureSessionPreset1280x720;
            break;
        case kCaptureSize1920_1080:
            preset = AVCaptureSessionPreset1920x1080;
            break;
        case kCaptureSize3840_2160:
            preset = AVCaptureSessionPreset3840x2160;
            break;
        default:
            preset = AVCaptureSessionPreset640x480;
            break;
    }
    return preset;
}

AVCaptureDevicePosition getPositionWithCameraPosition(GJCameraPosition cameraPosition) {
    AVCaptureDevicePosition position = AVCaptureDevicePositionUnspecified;
    switch (cameraPosition) {
        case GJCameraPositionFront:
            position = AVCaptureDevicePositionBack;
            break;
        case GJCameraPositionBack:
            position = AVCaptureDevicePositionBack;
            break;
        default:
            position = AVCaptureDevicePositionUnspecified;
            break;
    }
    return position;
}

@interface IOS_VideoProduce : NSObject
@property (nonatomic, strong) GPUImageOutput<GJCameraProtocal>*    camera;
@property (nonatomic, strong) GJImageView *           imageView;
@property (nonatomic, strong) GPUImageCropFilter *    cropFilter;
@property (nonatomic, strong) GPUImageBeautifyFilter *beautifyFilter;
@property (nonatomic, strong) GPUImageFilter *        videoSender;
@property (nonatomic, assign) AVCaptureDevicePosition cameraPosition;
@property (nonatomic, assign) UIInterfaceOrientation  outputOrientation;
@property (nonatomic, assign) CGSize                  destSize;
@property (nonatomic, assign) BOOL                    horizontallyMirror;
@property (nonatomic, assign) CGSize                  captureSize;
@property (nonatomic, assign) int                     frameRate;
@property (nonatomic, assign) GJPixelFormat           pixelFormat;
@property (nonatomic, assign) GJRetainBufferPool *    bufferPool;
@property (nonatomic, strong) GJImagePictureOverlay * sticker;
@property (nonatomic, strong) id<GJImageARScene> scene;


@property (nonatomic, copy) VideoRecodeCallback callback;

@end
@implementation IOS_VideoProduce

- (instancetype)init{
    self = [super init];
    if (self) {

        _frameRate         = 15;
        _cameraPosition    = AVCaptureDevicePositionBack;
        _outputOrientation = UIInterfaceOrientationPortrait;
        GJRetainBufferPoolCreate(&_bufferPool, sizeof(CVImageBufferRef), GTrue, R_GJPixelFrameMalloc, pixelReleaseCallBack, GNULL);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:UIApplicationWillEnterForegroundNotification object:nil];
        
    }
    return self;
}

-(void)receiveNotification:(NSNotification* )notic{
    if ([notic.name isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
        self.imageView.disable = YES;
    }else if ([notic.name isEqualToString:UIApplicationWillEnterForegroundNotification]) {
        self.imageView.disable = NO;
    }
}

-(void)setPixelFormat:(GJPixelFormat)pixelFormat{
    _pixelFormat = pixelFormat;
    self.destSize = CGSizeMake((CGFloat) pixelFormat.mWidth, (CGFloat) pixelFormat.mHeight);
}

- (void)dealloc {
    GJRetainBufferPool *temPool = _bufferPool;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        GJRetainBufferPoolClean(temPool, GTrue);
        GJRetainBufferPoolFree(temPool);
    });
}

- (GPUImageOutput<GJCameraProtocal>*)camera {
    if (_camera == nil) {

        CGSize size = _destSize;
        if (_outputOrientation == UIInterfaceOrientationPortrait ||
            _outputOrientation == UIInterfaceOrientationPortraitUpsideDown) {
            size.height += size.width;
            size.width  = size.height - size.width;
            size.height = size.height - size.width;
        }
        if (_scene == nil) {
  
            NSString *preset               = getCapturePresetWithSize(size);
            _camera                        = [[GPUImageVideoCamera alloc] initWithSessionPreset:preset cameraPosition:_cameraPosition];
            //        [self.beautifyFilter addTarget:self.cropFilter];
        }else{
           _camera = [[GJImageARCapture alloc]initWithScene:_scene captureSize:size];
           _camera.frameRate              = _frameRate;
        }

        self.frameRate          = _frameRate;
        self.outputOrientation  = _outputOrientation;
        self.horizontallyMirror = _horizontallyMirror;
        self.cameraPosition     = _cameraPosition;
        GPUImageOutput *sonFilter = [self getSonFilterWithDeep:kFilterCamera];
        if (sonFilter) {
            [_camera addTarget:(id<GPUImageInput>)sonFilter];
        }
    }
    return _camera;
}

- (GJImageView *)imageView {
    if (_imageView == nil) {
        @synchronized(self) {
            if (_imageView == nil) {
                _imageView = [[GJImageView alloc] init];
            }
        }
    }
    return _imageView;
}

- (GPUImageBeautifyFilter *)beautifyFilter {
    if (_beautifyFilter == nil) {
        _beautifyFilter = [[GPUImageBeautifyFilter alloc] init];
    }
    return _beautifyFilter;
}

/**
 获取deep对应的filter，如果不存在则获取父filter,deepfang'h，直到获取到为止

 @param deep deep放回获取到的层次
 @return return value description
 */
- (GPUImageOutput *)getParentFilterWithDeep:(GJFilterDeep)deep {
    GPUImageOutput *outFiter = nil;
    switch (deep) {
        case kFilterSticker:
            if (_beautifyFilter) {
                outFiter = _beautifyFilter;
                break;
            }
        case kFilterBeauty:
            outFiter = _camera;
            break;
        default:
            GJAssert(0, "错误");
            break;
    }
    return outFiter;
}

- (GPUImageOutput *)getFilterWithDeep:(GJFilterDeep)deep {
    GPUImageOutput *outFiter = nil;
    switch (deep) {
        case kFilterSticker:
            outFiter = _sticker;
            break;
        case kFilterBeauty:
            outFiter = _beautifyFilter;
            break;
        case kFilterCamera:
            outFiter = _camera;
            break;
        default:
            GJAssert(0, "错误");
            break;
    }
    return outFiter;
}

- (GPUImageOutput *)getSonFilterWithDeep:(GJFilterDeep)deep {
    GPUImageOutput *outFiter = nil;
    switch (deep) {
        case kFilterCamera:
            if (_beautifyFilter) {
                outFiter = _beautifyFilter;
                break;
            }
            
        case kFilterBeauty:
            if (_sticker) {
                deep    = kFilterSticker;
                break;
            }
            break;
        default:
            GJAssert(0, "错误");
            break;
    }
    return outFiter;
}
- (void)removeFilterWithdeep:(GJFilterDeep)deep {
    GPUImageOutput *deleteFilter = [self getFilterWithDeep:deep];
    if (deleteFilter) {
        if (deep > 0) {
            GPUImageOutput *parentFilter = [self getParentFilterWithDeep:deep];
            if (parentFilter) {
                for (id<GPUImageInput> input in deleteFilter.targets) {
                    [parentFilter addTarget:input];
                }
                [parentFilter removeTarget:(id<GPUImageInput>) deleteFilter];
                [deleteFilter removeAllTargets];
            }
        }else{
            [_camera removeAllTargets];
        }
        
    }
}
- (void)addFilter:(GPUImageFilter *)filter deep:(GJFilterDeep)deep {
    GPUImageOutput *parentFilter = [self getParentFilterWithDeep:deep];
    if (parentFilter) {
        for (id<GPUImageInput> input in parentFilter.targets) {
            [filter addTarget:input];
        }
        [parentFilter removeAllTargets];
        [parentFilter addTarget:filter];
    }else{
        [[self getSonFilterWithDeep:deep] addTarget:filter];
    }
}

- (BOOL)startStickerWithImages:(NSArray<UIImage *> *)images attribure:(GJOverlayAttribute *)attribure fps:(NSInteger)fps updateBlock:(OverlaysUpdate)updateBlock {
    
    if (_camera != nil) {
        runAsynchronouslyOnVideoProcessingQueue(^{
            GJImagePictureOverlay *newSticker = [[GJImagePictureOverlay alloc] init];
            [self addFilter:newSticker deep:kFilterSticker];
            self.sticker = newSticker;
            if (updateBlock) {
                [newSticker startOverlaysWithImages:images
                                              frame:attribure.frame
                                                fps:fps
                                        updateBlock:^GJOverlayAttribute *(NSInteger index, BOOL *ioFinish) {
                                            return updateBlock(index, ioFinish);
                                        }];
            } else {
                [newSticker startOverlaysWithImages:images frame:attribure.frame fps:fps updateBlock:nil];
            }
        });
        return YES;
    }else{
        return NO;
    }

}
- (void)chanceSticker {
    //使用同步线程，防止chance后还会有回调
    runSynchronouslyOnVideoProcessingQueue(^{
        if (self.sticker == nil) { return; }
        [self removeFilterWithdeep:kFilterSticker];
        self.sticker = nil;
    });
}
- (GPUImageCropFilter *)cropFilter {
    if (_cropFilter == nil) {
        _cropFilter = [[GPUImageCropFilter alloc] init];
    }
    return _cropFilter;
}

CGRect getCropRectWithSourceSize(CGSize sourceSize, CGSize destSize) {
    //裁剪，
    CGSize targetSize = sourceSize;
    float  scaleX     = targetSize.width / destSize.width;
    float  scaleY     = targetSize.height / destSize.height;
    CGRect region     = CGRectZero;
    if (scaleX <= scaleY) {
        float  scale       = scaleX;
        CGSize scaleSize   = CGSizeMake(destSize.width * scale, destSize.height * scale);
        region.origin.x    = 0;
        region.size.width  = 1.0;
        region.origin.y    = (targetSize.height - scaleSize.height) * 0.5 / targetSize.height;
        region.size.height = 1 - 2 * region.origin.y;
    } else {
        float  scale       = scaleY;
        CGSize scaleSize   = CGSizeMake(destSize.width * scale, destSize.height * scale);
        region.origin.y    = 0;
        region.size.height = 1.0;
        region.origin.x    = (targetSize.width - scaleSize.width) * 0.5 / targetSize.width;
        region.size.width  = 1 - 2 * region.origin.x;
    }

    return region;
}

- (BOOL)startProduce {
    __weak IOS_VideoProduce *wkSelf = self;
    runSynchronouslyOnVideoProcessingQueue(^{
        GPUImageOutput *parentFilter = _sticker;
        if (parentFilter == nil) {
            parentFilter = [self getParentFilterWithDeep:kFilterSticker];
        }
        [parentFilter addTarget:self.cropFilter];
        self.cropFilter.frameProcessingCompletionBlock = ^(GPUImageOutput *imageOutput, CMTime time) {
            CVPixelBufferRef pixel_buffer = [imageOutput framebufferForOutput].pixelBuffer;
            CVPixelBufferRetain(pixel_buffer);
            R_GJPixelFrame *frame                                   = (R_GJPixelFrame *) GJRetainBufferPoolGetData(wkSelf.bufferPool);
            ((CVPixelBufferRef *) R_BufferStart(&frame->retain))[0] = pixel_buffer;
            frame->height                                           = (GInt32) wkSelf.destSize.height;
            frame->width                                            = (GInt32) wkSelf.destSize.width;
            wkSelf.callback(frame);
            R_BufferUnRetain((GJRetainBuffer *) frame);
        };
        [self updateCropSize];
    });
    if (![self.camera isRunning]) {
        [self.camera startCameraCapture];
    }
    return YES;
}

- (void)stopProduce {
    runAsynchronouslyOnVideoProcessingQueue(^{
        GPUImageOutput *parentFilter = _sticker;
        if (parentFilter == nil) {
            parentFilter = [self getParentFilterWithDeep:kFilterSticker];
        }
        if (![parentFilter.targets containsObject:_imageView]) {
            [_camera stopCameraCapture];
        }

        [parentFilter removeTarget:_cropFilter];
        _cropFilter.frameProcessingCompletionBlock = nil;
    });
}

- (void)setDestSize:(CGSize)destSize {
    _destSize = destSize;
    if (_camera) {
        [self updateCropSize];
    }
}

- (void)updateCropSize {
    CGSize size = _destSize;
    if (_outputOrientation == UIInterfaceOrientationPortrait ||
        _outputOrientation == UIInterfaceOrientationPortraitUpsideDown) {
//        preset在此状况下做过转换
        size.height += size.width;
        size.width  = size.height - size.width;
        size.height = size.height - size.width;
    }
    NSString *preset = getCapturePresetWithSize(size);
    if (![preset isEqualToString:self.camera.captureSessionPreset]) {
        self.camera.captureSessionPreset = preset;
    }

    CGSize capture = getCaptureSizeWithSize(size);
    if (_outputOrientation == UIInterfaceOrientationPortrait ||
        _outputOrientation == UIInterfaceOrientationPortraitUpsideDown) {
//        实际获得的大小，需要转换回来
        capture.height += capture.width;
        capture.width  = capture.height - capture.width;
        capture.height = capture.height - capture.width;
    }
    _captureSize               = capture;
    CGRect region              = getCropRectWithSourceSize(capture, _destSize);
    self.cropFilter.cropRegion = region;
    [_cropFilter forceProcessingAtSize:_destSize];
}

- (void)setOutputOrientation:(UIInterfaceOrientation)outputOrientation {
    _outputOrientation             = outputOrientation;
    if (_camera) {
        self.camera.outputImageOrientation = outputOrientation;
        [self updateCropSize];
    }
}

- (void)setHorizontallyMirror:(BOOL)horizontallyMirror {
    _horizontallyMirror                            = horizontallyMirror;
    if (_camera) {
        self.camera.horizontallyMirrorRearFacingCamera = self.camera.horizontallyMirrorFrontFacingCamera = _horizontallyMirror;
    }
}

- (void)setFrameRate:(int)frameRate {
    _frameRate        = frameRate;
    if (_camera) {
        self.camera.frameRate = frameRate;
    }
}

- (void)setCameraPosition:(AVCaptureDevicePosition)cameraPosition {
    _cameraPosition = cameraPosition;
    if (_camera && self.camera.cameraPosition != _cameraPosition) {
        [_camera rotateCamera];
    }
}

- (BOOL)startPreview {
    if (![self.camera isRunning]) {
        [self.camera startCameraCapture];
    }
    runAsynchronouslyOnVideoProcessingQueue(^{

        GPUImageOutput *parentFilter = _sticker;
        if (parentFilter == nil) {
            parentFilter = [self getParentFilterWithDeep:kFilterSticker];
        }
        [parentFilter addTarget:self.imageView];

    });
    return YES;
}
- (void)stopPreview {

    runAsynchronouslyOnVideoProcessingQueue(^{
        if (_cropFilter.frameProcessingCompletionBlock == nil && [_camera isRunning]) {
            [_camera stopCameraCapture];
        }

        GPUImageOutput *parentFilter = _sticker;
        if (parentFilter == nil) {
            parentFilter = [self getParentFilterWithDeep:kFilterSticker];
        }

        [parentFilter removeTarget:_imageView];
    });
}


- (UIView *)getPreviewView {
    return self.imageView;
}



@end
inline static GBool videoProduceSetup(struct _GJVideoProduceContext *context, VideoFrameOutCallback callback, GHandle userData) {
    GJAssert(context->obaque == GNULL, "上一个视频生产器没有释放");
    IOS_VideoProduce *recode = [[IOS_VideoProduce alloc] init];
    recode.callback          = ^(R_GJPixelFrame *frame) {
        callback(userData, frame);
    };

    context->obaque = (__bridge_retained GHandle) recode;
    return GTrue;
}

inline static GVoid videoProduceUnSetup(struct _GJVideoProduceContext *context) {
    if (context->obaque) {
        IOS_VideoProduce *recode = (__bridge_transfer IOS_VideoProduce *) (context->obaque);
        [recode stopProduce];
        context->obaque = GNULL;
    }
}

inline static GBool videoProduceSetVideoFormat(struct _GJVideoProduceContext *context, GJPixelFormat format) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    
    [recode setPixelFormat:format];
    return GTrue;
}

inline static GBool videoProduceStart(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    return [recode startProduce];
}

inline static GVoid videoProduceStop(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    return [recode stopProduce];
}

inline static GHandle videoProduceGetRenderView(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    return (__bridge GHandle)([recode getPreviewView]);
}

//inline static GBool videoProduceSetProduceSize(struct _GJVideoProduceContext *context, GSize size) {
//    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
//    [recode setDestSize:CGSizeMake(size.width, size.height)];
//    return GTrue;
//}

inline static GBool videoProduceSetCameraPosition(struct _GJVideoProduceContext *context, GJCameraPosition cameraPosition) {
    IOS_VideoProduce *      recode   = (__bridge IOS_VideoProduce *) (context->obaque);
    AVCaptureDevicePosition position = AVCaptureDevicePositionUnspecified;
    switch (cameraPosition) {
        case GJCameraPositionBack:
            position = AVCaptureDevicePositionBack;
            break;
        case GJCameraPositionFront:
            position = AVCaptureDevicePositionFront;
            break;
        default:
            break;
    }
    [recode setCameraPosition:position];
    return GTrue;
}

inline static GBool videoProduceSetOutputOrientation(struct _GJVideoProduceContext *context, GJInterfaceOrientation outOrientation) {
    IOS_VideoProduce *     recode      = (__bridge IOS_VideoProduce *) (context->obaque);
    UIInterfaceOrientation orientation = UIInterfaceOrientationUnknown;
    switch (outOrientation) {
        case kGJInterfaceOrientationPortrait:
            orientation = UIInterfaceOrientationPortrait;
            break;
        case kGJInterfaceOrientationPortraitUpsideDown:
            orientation = UIInterfaceOrientationPortraitUpsideDown;
            break;
        case kGJInterfaceOrientationLandscapeLeft:
            orientation = UIInterfaceOrientationLandscapeLeft;
            break;
        case kGJInterfaceOrientationLandscapeRight:
            orientation = UIInterfaceOrientationLandscapeRight;
            break;
        default:
            break;
    }
    [recode setOutputOrientation:orientation];
    return GTrue;
}

inline static GBool videoProduceSetARScene(struct _GJVideoProduceContext *context, GHandle scene) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    recode.scene = (__bridge id<GJImageARScene>)(scene);
    return GTrue;
}

inline static GBool videoProduceSetHorizontallyMirror(struct _GJVideoProduceContext *context, GBool mirror) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    [recode setHorizontallyMirror:mirror];
    return GTrue;
}

inline static GBool videoProduceSetFrameRate(struct _GJVideoProduceContext *context, GInt32 fps) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    [recode setFrameRate:fps];
    return recode.frameRate = fps;
}

inline static GBool videoProduceStartPreview(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    return [recode startPreview];
}

inline static GVoid videoProduceStopPreview(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    [recode stopPreview];
}

inline static GBool addSticker(struct _GJVideoProduceContext *context, const GVoid *images, GStickerParm parm, GInt32 fps, GJStickerUpdateCallback callback, const GVoid *userData) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    CGRect            rect   = CGRectMake(parm.frame.center.x, parm.frame.center.y, parm.frame.size.width, parm.frame.size.height);
    if (callback == GNULL) {
        [recode startStickerWithImages:(__bridge NSArray<UIImage *> *)(images) attribure:[GJOverlayAttribute overlayAttributeWithImage:nil frame:rect rotate:parm.rotation] fps:fps updateBlock:nil];
    } else {
        [recode startStickerWithImages:(__bridge NSArray<UIImage *> *)(images)
                             attribure:[GJOverlayAttribute overlayAttributeWithImage:nil frame:rect rotate:parm.rotation]
                                   fps:fps
                           updateBlock:^GJOverlayAttribute *(NSInteger index, BOOL *ioFinish) {
                               GStickerParm rParm = callback((GHandle) userData, index, (GBool *) ioFinish);
                               CGRect       rRect = CGRectMake(rParm.frame.center.x, rParm.frame.center.y, rParm.frame.size.width, rParm.frame.size.height);
                               return [GJOverlayAttribute overlayAttributeWithImage:(__bridge_transfer UIImage *)(rParm.image) frame:rRect rotate:rParm.rotation];
                           }];
    }
    return GTrue;
}

inline static GVoid chanceSticker(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    [recode chanceSticker];
}

inline static GSize getCaptureSize(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    GSize             size;
    size.width  = recode.captureSize.width;
    size.height = recode.captureSize.height;
    return size;
}

GVoid GJ_VideoProduceContextCreate(GJVideoProduceContext **produceContext) {
    if (*produceContext == NULL) {
        *produceContext = (GJVideoProduceContext *) malloc(sizeof(GJVideoProduceContext));
    }
    GJVideoProduceContext *context = *produceContext;
    context->videoProduceSetup     = videoProduceSetup;
    context->videoProduceUnSetup   = videoProduceUnSetup;
    context->startProduce          = videoProduceStart;
    context->stopProduce           = videoProduceStop;
    context->startPreview          = videoProduceStartPreview;
    context->stopPreview           = videoProduceStopPreview;
//    context->setProduceSize        = videoProduceSetProduceSize;
    context->setCameraPosition     = videoProduceSetCameraPosition;
    context->setOrientation        = videoProduceSetOutputOrientation;
    context->setHorizontallyMirror = videoProduceSetHorizontallyMirror;
    context->getRenderView         = videoProduceGetRenderView;
    context->getCaptureSize        = getCaptureSize;
    context->setFrameRate          = videoProduceSetFrameRate;
    context->addSticker            = addSticker;
    context->chanceSticker         = chanceSticker;
    context->setARScene            = videoProduceSetARScene;
    context->setVideoFormat        = videoProduceSetVideoFormat;
}

GVoid GJ_VideoProduceContextDealloc(GJVideoProduceContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "videoProduceUnSetup 没有调用，自动调用");
        (*context)->videoProduceUnSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
