//
//  IOS_PictureDisplay.m
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/5/16.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_PictureDisplay.h"
#import "GJImagePixelImageInput.h"
#import "GJImageView.h"
#import "GJLog.h"
#import "libavformat/avformat.h"
#import <GPUImageRawDataInput.h>
#import "GJImageYUVDataInput.h"

@interface IOS_PictureDisplay : NSObject
@property (strong, nonatomic) GPUImageOutput *imageInput;
@property (strong, nonatomic) GJImageView *   displayView;
@property (assign, nonatomic) BOOL            enableRender;
@end
@implementation IOS_PictureDisplay
- (instancetype)init {
    self = [super init];
    if (self) {
        _displayView  = [[GJImageView alloc] init];
        _enableRender = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    return self;
}
- (void)receiveNotification:(NSNotification *)notic {
    if ([notic.name isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
        _enableRender = NO;
        runSynchronouslyOnVideoProcessingQueue(^{
            [_imageInput removeTarget:_displayView];
        });
    } else if ([notic.name isEqualToString:UIApplicationWillEnterForegroundNotification]) {
        runSynchronouslyOnVideoProcessingQueue(^{
            [_imageInput addTarget:_displayView];
        });
        _enableRender = YES;
    }
}

- (void)displayImage:(R_GJPixelFrame *)frame {
    if (!_enableRender) {
        return;
    }
    if ((frame->flag & kGJFrameFlag_P_CVPixelBuffer) == kGJFrameFlag_P_CVPixelBuffer) {
        CVImageBufferRef image = ((CVImageBufferRef *) R_BufferStart(frame))[0];

        if (![_imageInput isKindOfClass:[GJImagePixelImageInput class]]) {
            OSType format = CVPixelBufferGetPixelFormatType(image);
            _imageInput   = [[GJImagePixelImageInput alloc] initWithFormat:(GJYUVPixelImageFormat) format];
            if (_enableRender) {
                [_imageInput addTarget:_displayView];
            }
        }
        [(GJImagePixelImageInput *) _imageInput updateDataWithImageBuffer:image timestamp:kCMTimeZero];
    } else if ((frame->flag & kGJFrameFlag_P_AVFrame) == kGJFrameFlag_P_AVFrame) {
        AVFrame *          image  = ((AVFrame **) R_BufferStart(frame))[0];
        enum AVPixelFormat format = image->format;

        GPUPixelFormat   pixelFormat = GPUPixelFormatBGRA;
        GJYUVPixelFormat yuvFormat   = GJPixelFormatI420;

        BOOL isRGB = GFalse;
        BOOL isYUV = GFalse;
        switch (format) {
            case AV_PIX_FMT_RGBA:
                pixelFormat = GPUPixelFormatRGBA;
                isRGB       = GTrue;
                break;
            case AV_PIX_FMT_BGRA:
                pixelFormat = GPUPixelFormatBGRA;
                isRGB       = GTrue;
                break;
            case AV_PIX_FMT_RGB24:
                pixelFormat = GPUPixelFormatRGB;
                isRGB       = GTrue;
                break;
            case AV_PIX_FMT_YUV420P:
            case AV_PIX_FMT_YUVJ420P:
                yuvFormat = GJPixelFormatI420;
                isYUV     = GTrue;
                break;
            case AV_PIX_FMT_NV12:
                yuvFormat = GJPixelFormatNV12;
                isYUV     = GTrue;
                break;
            case AV_PIX_FMT_NV21:
                yuvFormat = GJPixelFormatNV21;
                isYUV     = GTrue;
                break;
            default:
                GJAssert(0, "不支持");
                break;
        }
        if (isRGB) {
            if (![_imageInput isKindOfClass:[GPUImageRawDataInput class]]) {
                _imageInput = [[GPUImageRawDataInput alloc] initWithBytes:image->data[0] size:CGSizeMake(image->width, image->height) pixelFormat:pixelFormat];
                if (_enableRender) {
                    [_imageInput addTarget:_displayView];
                }
            }
            [(GPUImageRawDataInput *) _imageInput processData];
        } else {
            if (![_imageInput isKindOfClass:[GJImageYUVDataInput class]]) {
                _imageInput = [[GJImageYUVDataInput alloc] initWithImageSize:CGSizeMake(image->width, image->height) pixelFormat:yuvFormat];
                if (_enableRender) {
                    [_imageInput addTarget:_displayView];
                }
            }
            if (yuvFormat == GJPixelFormatI420) {
                [(GJImageYUVDataInput *) _imageInput updateDataWithY:image->data[0] U:image->data[1] V:image->data[2] type:GJPixelTypeUByte Timestamp:kCMTimeZero];
            } else {
                [(GJImageYUVDataInput *) _imageInput updateDataWithY:image->data[0] CrBr:image->data[1] type:GJPixelTypeUByte Timestamp:kCMTimeZero];
            }
        }
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end
static GBool IOS_PictureDisplaySetup(GJPictureDisplayContext *context) {
    if (context->obaque != GNULL) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "重复setup video play");
        return GFalse;
    }
    context->obaque = (__bridge_retained GHandle)([[IOS_PictureDisplay alloc] init]);
    return context->obaque != nil;
}

static GVoid displayUnSetup(GJPictureDisplayContext *context) {
    if (context->obaque) {
        IOS_PictureDisplay *display = (__bridge_transfer IOS_PictureDisplay *) (context->obaque);
        context->obaque             = GNULL;
        display                     = nil;
    }
}
static GVoid IOS_PictureDisplayImage(GJPictureDisplayContext *context, R_GJPixelFrame *frame) {
    IOS_PictureDisplay *display = (__bridge IOS_PictureDisplay *) (context->obaque);
    [display displayImage:frame];
}
static GHandle IOS_PictureDisplayGetView(GJPictureDisplayContext *context) {
    IOS_PictureDisplay *display = (__bridge IOS_PictureDisplay *) (context->obaque);
    return (__bridge GHandle)(display.displayView);
}
GVoid GJ_PictureDisplayContextCreate(GJPictureDisplayContext **disPlayContext) {
    if (*disPlayContext == NULL) {
        *disPlayContext = (GJPictureDisplayContext *) calloc(1, sizeof(GJPictureDisplayContext));
    }
    GJPictureDisplayContext *context = *disPlayContext;
    context->displaySetup            = IOS_PictureDisplaySetup;
    context->renderFrame             = IOS_PictureDisplayImage;
    context->displayUnSetup          = displayUnSetup;
    context->getDispayView           = IOS_PictureDisplayGetView;
}
GVoid GJ_PictureDisplayContextDealloc(GJPictureDisplayContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "displayUnSetup 没有调用，自动调用");
        (*context)->displayUnSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
