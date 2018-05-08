//
//  IOS_VideoProduce.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_VideoProduce.h"
#import "GJBufferPool.h"
#import "GJImageFilters.h"
#import "GJLiveDefine.h"
#import "GJLog.h"
#import "GPUImageVideoCamera.h"
#import <stdlib.h>
typedef enum { //filter深度
    kFilterCamera = 0,
    kFilterFaceSticker,
    kFilterBeauty,
    kFilterTrack,
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

static NSString *getCapturePresetWithSize(CGSize size) {
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

@interface IOS_VideoProduce : NSObject{
}
@property (nonatomic, strong) GPUImageOutput<GJCameraProtocal>*    camera;
@property (nonatomic, strong) GJImageView *           imageView;
@property (nonatomic, strong) GPUImageCropFilter *    cropFilter;
@property (nonatomic, strong) ARCSoftFaceHandle *     faceHandle;
@property (nonatomic, strong) ARCSoftFaceSticker *    faceSticker;


@property (nonatomic, strong) GPUImageBeautifyFilter *beautifyFilter;
@property (nonatomic, strong) GPUImageFilter *        videoSender;
@property (nonatomic, assign) AVCaptureDevicePosition cameraPosition;
@property (nonatomic, assign) UIInterfaceOrientation  outputOrientation;
@property (nonatomic, assign) CGSize                  destSize;
@property (nonatomic, assign) BOOL                    horizontallyMirror;
@property (nonatomic, assign) BOOL                    streamMirror;
@property (nonatomic, assign) BOOL                    previewMirror;
@property (nonatomic, assign) int                     frameRate;
@property (nonatomic, assign) GJPixelFormat           pixelFormat;
@property (nonatomic, assign) GJRetainBufferPool *    bufferPool;
@property (nonatomic, strong) GJImagePictureOverlay * sticker;
@property (nonatomic, strong) GJImageTrackImage *     trackImage;
@property (nonatomic, assign) GJCaptureType           captureType;
@property (nonatomic, strong) id<GJImageARScene>      scene;
@property (nonatomic, strong) UIView*                 captureView;
@property (nonatomic, assign) GRational               dropStep;
@property (nonatomic, assign) long                  captureCount;
@property (nonatomic, assign) long                  dropCount;

#pragma mark 美颜参数设置，请先开启任意一种美颜
/**
 美白：0-100
 */
@property(assign,nonatomic)NSInteger brightness;

/**
 磨皮：0-100
 */
@property(assign,nonatomic)NSInteger skinSoften;

/**
 皮肤红润：0--100
 */
@property(nonatomic,assign)NSInteger skinRuddy;

/**
 瘦脸：0--100
 */
@property(nonatomic,assign)NSInteger faceSlender;     //

/**
 大眼：0--100
 */
@property(nonatomic,assign)NSInteger eyeEnlargement;  //


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

-(void)setScene:(id<GJImageARScene>)scene{
    _captureView = nil;
    _scene = scene;
}

-(void)setCaptureView:(UIView *)captureView{
    _scene = nil;
    _captureView = captureView;
}

-(void)setCaptureType:(GJCaptureType)captureType{
    if(_camera != nil){
        GJLOG(GNULL, GJ_LOGWARNING, "setCaptureType 无效，请先停止预览和推流");
    }
    _captureType = captureType;
}

- (void)dealloc {
    if (_sticker) {
        [_sticker stop];
    }
    if (_trackImage) {
        [_trackImage stop];
    }
    if (_camera && _camera.isRunning) {
        [_camera stopCameraCapture];
        [self deleteCamera];
    }
    GJRetainBufferPool *temPool = _bufferPool;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        GJRetainBufferPoolClean(temPool, GTrue);
        GJRetainBufferPoolFree(temPool);
    });
}

-(void)deleteCamera{
    if ([_camera isKindOfClass:[GJPaintingCamera class]]) {
        [_camera removeObserver:self forKeyPath:@"captureSize"];
    }
    _camera = nil;
}
- (GPUImageOutput<GJCameraProtocal>*)camera {
    if (_camera == nil) {

        CGSize size = _destSize;

        switch (_captureType) {
            case kGJCaptureTypeCamera:
            {
                if (_outputOrientation == UIInterfaceOrientationPortrait ||
                    _outputOrientation == UIInterfaceOrientationPortraitUpsideDown) {
                    size.height += size.width;
                    size.width  = size.height - size.width;
                    size.height = size.height - size.width;
                }
                NSString *preset               = getCapturePresetWithSize(size);
                _camera                        = [[GPUImageVideoCamera alloc] initWithSessionPreset:preset cameraPosition:_cameraPosition];
            }
                break;
            case kGJCaptureTypeView:{
                GJAssert(_captureView != nil, "请先设置直播的视图");
                _camera = [[GJImageUICapture alloc]initWithView:_captureView];
                break;
            }
            case kGJCaptureTypePaint:{
                _camera = [[GJPaintingCamera alloc]init];
                [_camera addObserver:self forKeyPath:@"captureSize" options:NSKeyValueObservingOptionNew context:nil];
                break;
            }
            case kGJCaptureTypeAR:{
                GJAssert(_scene != nil, "请先设置ARScene");
                _camera = [[GJImageARCapture alloc]initWithScene:_scene captureSize:size];
                break;
            }
            default:
                break;
        }
        if (_scene != nil) {
            //            [self.imageView addSubview:_scene.scene];
        }else if(_captureView != nil){
        }else{
           
            //        [self.beautifyFilter addTarget:self.cropFilter];
        }

        self.frameRate          = _frameRate;
        self.outputOrientation  = _outputOrientation;
        self.horizontallyMirror = _horizontallyMirror;
        self.cameraPosition     = _cameraPosition;
        GPUImageOutput *sonFilter = [self getSonFilterWithDeep:kFilterCamera];
        if (sonFilter) {
            [_camera addTarget:(id<GPUImageInput>)sonFilter];
        }
        [self updateCropSize];
    }
    return _camera;
}

-(void)setSkinRuddy:(NSInteger)skinRuddy{
    _faceHandle.skinRuddy = skinRuddy;
}
-(NSInteger)skinRuddy{
    return _faceHandle.skinRuddy;
}

-(void)setSkinSoften:(NSInteger)skinSoften{
    _faceHandle.skinSoftn = skinSoften;
}
-(NSInteger)skinSoften{
    return _faceHandle.skinSoftn;
}

-(void)setBrightness:(NSInteger)brightness{
    _faceHandle.skinBright = brightness;
}
-(NSInteger)brightness{
    return _faceHandle.skinBright;
}

-(void)setEyeEnlargement:(NSInteger)eyeEnlargement{
    _faceHandle.eyesEnlargement = eyeEnlargement;
}
-(NSInteger)eyeEnlargement{
    return _faceHandle.eyesEnlargement;
}

-(void)deleteShowImage{
    [_imageView removeObserver:self forKeyPath:@"frame"];
    _imageView = nil;
}
- (GJImageView *)imageView {
    if (_imageView == nil) {
        @synchronized(self) {
            if (_imageView == nil) {
                if (_captureType != kGJCaptureTypePaint) {
                    _imageView = [[GJImageView alloc] init];
                }else{
                    _imageView = ((GJPaintingCamera*)self.camera).paintingView;
                }
                [_imageView addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
                if (_previewMirror) {
                    [self setPreviewMirror:_previewMirror];
                }
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
 获取deep对应的filter，如果不存在则获取父filter,则递归继续向上，直到获取到为止

 @param deep deep放回获取到的层次
 @return return value description
 */
- (GPUImageOutput *)getParentFilterWithDeep:(GJFilterDeep)deep {
    GPUImageOutput *outFiter = nil;
    switch (deep) {
        case kFilterSticker:
            if(_trackImage){
                outFiter = _trackImage;
                break;
            }
        case kFilterTrack:
            if (_beautifyFilter) {
                outFiter = _beautifyFilter;
                break;
            }
        case kFilterBeauty:
            if (_faceSticker) {
                outFiter = _faceSticker;
                break;
            }
            break;
        case kFilterFaceSticker:
            GJAssert(_camera != nil, "camera还没有创建");
            outFiter = _camera;
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
        case kFilterTrack:
            outFiter = _trackImage;
            break;
        case kFilterBeauty:
            outFiter = _beautifyFilter;
            break;
        case kFilterFaceSticker:
            outFiter = _faceSticker;
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

//一直获取子滤镜，直到获取到为止
- (GPUImageOutput *)getSonFilterWithDeep:(GJFilterDeep)deep {
    GPUImageOutput *outFiter = nil;
    switch (deep) {
        case kFilterCamera:
            if (_faceSticker) {
                outFiter = _faceSticker;
                break;
            }
        case kFilterFaceSticker:
            if (_beautifyFilter) {
                outFiter = _beautifyFilter;
                break;
            }
        case kFilterBeauty:
            if (_trackImage) {
                outFiter    = _trackImage;
                break;
            }
        case kFilterTrack:
            if (_sticker) {
                outFiter    = _sticker;
                break;
            }
            break;//可能为空
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
        assert(0);
        [[self getSonFilterWithDeep:deep] addTarget:filter];
    }
}


- (BOOL)startStickerWithImages:(NSArray<GJOverlayAttribute *> *)images fps:(NSInteger)fps updateBlock:(OverlaysUpdate)updateBlock {
    
    if (_camera != nil) {
        runAsynchronouslyOnVideoProcessingQueue(^{
            GJImagePictureOverlay *newSticker = [[GJImagePictureOverlay alloc] init];
            [self addFilter:newSticker deep:kFilterSticker];
            self.sticker = newSticker;
            if (updateBlock) {
                [newSticker startOverlaysWithImages:images fps:fps updateBlock:^(NSInteger index, GJOverlayAttribute * _Nonnull ioAttr, BOOL * _Nonnull ioFinish) {
                    updateBlock(index,ioAttr, ioFinish);
                }];
      
            } else {
                [newSticker startOverlaysWithImages:images fps:fps updateBlock:nil];
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
        [self.sticker stop];
        self.sticker = nil;
    });
}

-(BOOL)prepareVideoEffectWithBaseData:(NSString *)baseDataPath{
    runAsynchronouslyOnVideoProcessingQueue(^{
        _faceHandle = [[ARCSoftFaceHandle alloc]initWithDataPath:baseDataPath];
        self.camera.delegate = _faceHandle;
        _faceSticker = [[ARCSoftFaceSticker alloc]init];
        [self addFilter:_faceSticker deep:kFilterFaceSticker];
    });
    return YES;
}
/**
 取消视频处理
 */
-(void)chanceVideoEffect{
    self.camera.delegate = nil;
    _faceHandle = nil;
    runSynchronouslyOnVideoProcessingQueue(^{
        [self removeFilterWithdeep:kFilterFaceSticker];
    });
}

-(BOOL)updateFaceStickerWithTemplatePath:(NSString*)path{
    return [_faceSticker updateTemplatePath:path];
}

- (BOOL)startTrackingImageWithImages:(NSArray<GJOverlayAttribute*>*)images{
    if (_camera == nil) {
        return NO;
    }
    
    runAsynchronouslyOnVideoProcessingQueue(^{
        GJImageTrackImage *newTrack = [[GJImageTrackImage alloc] init];
        [self addFilter:newTrack deep:kFilterTrack];
        self.trackImage = newTrack;
        [newTrack startOverlaysWithImages:images fps:-1 updateBlock:nil];

    });
    return YES;
}

- (void)stopTracking{
    [self.trackImage stop];
    runSynchronouslyOnVideoProcessingQueue(^{
        if (self.trackImage == nil) { return; }
        [self removeFilterWithdeep:kFilterTrack];
        self.trackImage = nil;
    });
}

- (GPUImageCropFilter *)cropFilter {
    if (_cropFilter == nil) {
        _cropFilter = [[GPUImageCropFilter alloc] init];
        if (_streamMirror) {
            [self setStreamMirror:_streamMirror];
        }
    }
    return _cropFilter;
}

/**
 根据原图片大小，限制在imageview的比例之内，再缩放到targetSize，保证获得的图片一定全部限制在显示视图的中间上，

 @param originSize 原图片大小
 @param targetSize 目标图片大小
 @return 裁剪的比例
 */
-(CGRect) getCropRectWithSourceSize:(CGSize) originSize target:(CGSize)targetSize {
    CGSize sourceSize = originSize;
    CGSize previewSize = _imageView.bounds.size;
    CGRect region =CGRectZero;
    
    if (_imageView && _imageView.superview != nil) {
        switch (_imageView.contentMode) {
            case UIViewContentModeScaleAspectFill://显示在显示视图内
            {
                float scaleX =  sourceSize.width / previewSize.width;
                float scaleY =  sourceSize.height / previewSize.height;
                if (scaleX <= scaleY) {
                    float scale = scaleX;
                    CGSize scaleSize = CGSizeMake(previewSize.width * scale, previewSize.height * scale);
                    region.origin.x = 0;
                    region.origin.y = (sourceSize.height - scaleSize.height)/2;
                    sourceSize.height -= region.origin.y*2;
                }else{
                    float scale = scaleY;
                    CGSize scaleSize = CGSizeMake(previewSize.width * scale, previewSize.height * scale);
                    region.origin.x = (sourceSize.width - scaleSize.width)/2;
                    region.origin.y = 0;
                    sourceSize.width -= region.origin.x*2;
                }
            }
                break;
                
            default:
                break;
        }
    }

    
    float scaleX =  sourceSize.width / targetSize.width;
    float scaleY =  sourceSize.height / targetSize.height;
    if (scaleX <= scaleY) {
        float scale = scaleX;
        CGSize scaleSize = CGSizeMake(targetSize.width * scale, targetSize.height * scale);
        region.origin.y += (sourceSize.height - scaleSize.height)/2;
    }else{
        float scale = scaleY;
        CGSize scaleSize = CGSizeMake(targetSize.width * scale, targetSize.height * scale);
        region.origin.x += (sourceSize.width - scaleSize.width)/2;
    }
    if (region.origin.y < 0) {
        if (region.origin.y > -0.0001) {
            region.origin.y = 0;
        }
    }
    if (region.origin.x < 0) {
        if (region.origin.x > -0.0001) {
            region.origin.x = 0;
        }
    }
    region.origin.x /= originSize.width;
    region.origin.y /= originSize.height;
    region.size.width = 1-2*region.origin.x;
    region.size.height = 1-2*region.origin.y;
    
//    //裁剪，
//    CGSize targetSize = sourceSize;
//    float  scaleX     = targetSize.width / destSize.width;
//    float  scaleY     = targetSize.height / destSize.height;
//    CGRect region     = CGRectZero;
//    if (scaleX <= scaleY) {
//        float  scale       = scaleX;
//        CGSize scaleSize   = CGSizeMake(destSize.width * scale, destSize.height * scale);
//        region.origin.x    = 0;
//        region.size.width  = 1.0;
//        region.origin.y    = (targetSize.height - scaleSize.height) * 0.5 / targetSize.height;
//        region.size.height = 1 - 2 * region.origin.y;
//    } else {
//        float  scale       = scaleY;
//        CGSize scaleSize   = CGSizeMake(destSize.width * scale, destSize.height * scale);
//        region.origin.y    = 0;
//        region.size.height = 1.0;
//        region.origin.x    = (targetSize.width - scaleSize.width) * 0.5 / targetSize.width;
//        region.size.width  = 1 - 2 * region.origin.x;
//    }

    return region;
}

- (BOOL)startProduce {
    __weak IOS_VideoProduce *wkSelf = self;
    _dropCount = 0;
    _captureCount = 0;
    runSynchronouslyOnVideoProcessingQueue(^{
        GPUImageOutput *parentFilter = _sticker;
        if (parentFilter == nil) {
            parentFilter = [self getParentFilterWithDeep:kFilterSticker];
        }
        [parentFilter addTarget:self.cropFilter];
        self.cropFilter.frameProcessingCompletionBlock = ^(GPUImageOutput *imageOutput, CMTime time) {
            CVPixelBufferRef pixel_buffer = [imageOutput framebufferForOutput].newPixelBufferFromFramebufferContents;
//            CVPixelBufferRetain(pixel_buffer);

            R_GJPixelFrame *frame                                   = (R_GJPixelFrame *) GJRetainBufferPoolGetData(wkSelf.bufferPool);
            R_BufferWrite(&frame->retain, (GUInt8*)&pixel_buffer, sizeof(CVPixelBufferRef));
            frame->height                                           = (GInt32) wkSelf.destSize.height;
            frame->width                                            = (GInt32) wkSelf.destSize.width;
            frame->pts = GTimeMake(time.value, time.timescale);
            if (wkSelf.captureCount++ % wkSelf.dropStep.den >= wkSelf.dropStep.num) {
                wkSelf.callback(frame);
            }else{
                wkSelf.dropCount ++;
            }
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
    GPUImageOutput *parentFilter = _sticker;
    if (parentFilter == nil) {
        parentFilter = [self getParentFilterWithDeep:kFilterSticker];
    }
    if (![parentFilter.targets containsObject:_imageView]) {
        [_camera stopCameraCapture];
        [self deleteCamera];
        if (_trackImage) {
            [self stopTracking];
        }
    }
    runAsynchronouslyOnVideoProcessingQueue(^{
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
    runSynchronouslyOnVideoProcessingQueue(^{
        if(_camera == nil)return ;
        CGSize size = _destSize;
        CGSize capture = self.camera.captureSize;
        if (capture.height < 2 || capture.width < 2) {
            return;
        }
        if (capture.height - size.height > 0.001 ||
            size.height - capture.height > 0.001 ||
            capture.width - size.width > 0.001 ||
            size.width - capture.width > 0.001) {
            if (![self.camera isKindOfClass:[GJPaintingCamera class]]) {
                self.camera.captureSize = size;
            }
            capture = self.camera.captureSize;
        }
        
        CGRect region              = [self getCropRectWithSourceSize:capture target:_destSize];
        self.cropFilter.cropRegion = region;
        [_cropFilter forceProcessingAtSize:_destSize];
    });
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

- (void)setPreviewMirror:(BOOL)previewMirror{
    _previewMirror                            = previewMirror;
    if (_imageView) {
        [_imageView setInputRotation:kGPUImageFlipHorizonal atIndex:0];
    }
}

-(void)setStreamMirror:(BOOL)streamMirror{
    _streamMirror = streamMirror;
    if (_cropFilter) {
        [_cropFilter setInputRotation:kGPUImageFlipHorizonal atIndex:0];
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
    runSynchronouslyOnVideoProcessingQueue(^{

        GPUImageOutput *parentFilter = _sticker;
        if (parentFilter == nil) {
            parentFilter = [self getParentFilterWithDeep:kFilterSticker];
        }
        [parentFilter addTarget:self.imageView];

    });
    return YES;
}
- (void)stopPreview {
    if (_cropFilter.frameProcessingCompletionBlock == nil && [_camera isRunning]) {
        [_camera stopCameraCapture];
        [self deleteCamera];
        if (_trackImage) {
            [self stopTracking];
        }
    }
    runAsynchronouslyOnVideoProcessingQueue(^{
        GPUImageOutput *parentFilter = _sticker;
        if (parentFilter == nil) {
            parentFilter = [self getParentFilterWithDeep:kFilterSticker];
        }

        [parentFilter removeTarget:_imageView];
        [self deleteShowImage];
    });
}


- (UIView *)getPreviewView {
    return self.imageView;
}

-(UIImage*)getFreshDisplayImage{
    return [((GJImageView*)self.imageView) captureFreshImage];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    if (object == _imageView) {
        if ([keyPath isEqualToString:@"frame"]) {
            [self updateCropSize];
        }
    }else if (object == _camera){
        if ([keyPath isEqualToString:@"captureSize"]) {
            [self updateCropSize];
        }
    }
}


@end
inline static GBool videoProduceSetup(struct _GJVideoProduceContext *context, VideoFrameOutCallback callback, GHandle userData) {
    GJAssert(context->obaque == GNULL, "上一个视频生产器没有释放");
    IOS_VideoProduce *recode = [[IOS_VideoProduce alloc] init];
    NodeFlowDataFunc callFunc = pipleNodeFlowFunc(&context->pipleNode);
    recode.callback          = ^(R_GJPixelFrame *frame) {
        if (callback) {
            callback(userData, frame);
        }
        callFunc(&context->pipleNode,&frame->retain,GJMediaType_Video);
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

inline static GBool videoProduceSetCaptureView(struct _GJVideoProduceContext *context, GView view) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    recode.captureView = (__bridge UIView*)(view);
    return GTrue;
}

inline static GBool videoProduceSetCaptureType(struct _GJVideoProduceContext *context, GJCaptureType type) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    recode.captureType = type;
    return GTrue;
}

inline static GBool videoProduceSetHorizontallyMirror(struct _GJVideoProduceContext *context, GBool mirror) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    [recode setHorizontallyMirror:mirror];
    return GTrue;
}

inline static GBool setPreviewMirror (struct _GJVideoProduceContext* context, GBool mirror){
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    recode.previewMirror = mirror;
    return recode.previewMirror == mirror;
}
inline static GBool setStreamMirror (struct _GJVideoProduceContext* context, GBool mirror){
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    recode.streamMirror = mirror;
    return recode.streamMirror == mirror;
}

inline static GVoid setDropStep (struct _GJVideoProduceContext* context, GRational step){
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    recode.dropStep = step;
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

inline static GHandle getFreshDisplayImage(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    return (GHandle)CFBridgingRetain([recode getFreshDisplayImage]);
}

inline static GBool addSticker(struct _GJVideoProduceContext *context, const GVoid *overlays,  GInt32 fps, GJStickerUpdateCallback callback, const GVoid *userData) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    
    if (callback == GNULL) {
        [recode startStickerWithImages:(__bridge_transfer NSArray<GJOverlayAttribute *> *)(overlays) fps:fps updateBlock:nil];
    } else {
        [recode startStickerWithImages:(__bridge_transfer NSArray<GJOverlayAttribute *> *)(overlays) fps:fps updateBlock:^(NSInteger index, GJOverlayAttribute * _Nonnull ioAttr, BOOL * _Nonnull ioFinish) {
            callback((GHandle) userData, index,(__bridge GHandle)(ioAttr), (GBool *) ioFinish);
        }];
    }
    return GTrue;
}

inline static GVoid chanceSticker(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    [recode chanceSticker];
}

inline static GBool startTrackImage(struct _GJVideoProduceContext *context, const GVoid *images, GCRect frame) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    NSArray<UIImage *> * imageArry = (__bridge_transfer NSArray<UIImage *> *)(images);
    NSMutableArray* overlays = [NSMutableArray arrayWithCapacity:imageArry.count];
    for (UIImage* image in imageArry) {
        [overlays addObject:[GJOverlayAttribute overlayAttributeWithImage:image frame:makeGCRectToCGRect(frame) rotate:0]];
    }
    BOOL result =  [recode startTrackingImageWithImages:overlays];
    return result;
}

inline static GVoid stopTrackImage(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    [recode stopTracking];
}

inline static GSize getCaptureSize(struct _GJVideoProduceContext *context) {
    IOS_VideoProduce *recode = (__bridge IOS_VideoProduce *) (context->obaque);
    GSize             size;
    CGSize capture = recode.camera.captureSize;
    size.width = capture.width;
    size.height = capture.height;
    return size;
}

GBool   setMute(struct _GJVideoProduceContext* context, GBool enable){
    setDropStep(context, GRationalMake(enable == GTrue, 1));
    return GTrue;
}

GVoid GJ_VideoProduceContextCreate(GJVideoProduceContext **produceContext) {
    if (*produceContext == NULL) {
        *produceContext = (GJVideoProduceContext *) malloc(sizeof(GJVideoProduceContext));
    }
    GJVideoProduceContext *context = *produceContext;
    memset(context, 0, sizeof(GJVideoProduceContext));
    pipleNodeInit(&context->pipleNode, GNULL);
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
    context->setPreviewMirror      = setPreviewMirror;
    context->setStreamMirror       = setStreamMirror;
    context->getRenderView         = videoProduceGetRenderView;
    context->getCaptureSize        = getCaptureSize;
    context->setFrameRate          = videoProduceSetFrameRate;
    context->addSticker            = addSticker;
    context->chanceSticker         = chanceSticker;
    context->setARScene            = videoProduceSetARScene;
    context->setCaptureView        = videoProduceSetCaptureView;
    context->setCaptureType        = videoProduceSetCaptureType;
    context->setVideoFormat        = videoProduceSetVideoFormat;
    context->startTrackImage       = startTrackImage;
    context->stopTrackImage        = stopTrackImage;
    context->getFreshDisplayImage  = getFreshDisplayImage;
    context->setDropStep           = setDropStep;
    context->setMute               = setMute;
}

GVoid GJ_VideoProduceContextDealloc(GJVideoProduceContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "videoProduceUnSetup 没有调用，自动调用");
        (*context)->videoProduceUnSetup(*context);
    }
    pipleNodeUnInit(&(*context)->pipleNode);
    free(*context);
    *context = GNULL;
}
