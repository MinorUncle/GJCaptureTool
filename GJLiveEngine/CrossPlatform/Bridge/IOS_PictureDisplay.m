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

@interface IOS_PictureDisplay : NSObject
@property (strong, nonatomic) GJImagePixelImageInput *imageInput;
@property (strong, nonatomic) GJImageView *           displayView;
@property (assign, nonatomic) BOOL enableRender;
@end
@implementation IOS_PictureDisplay
- (instancetype)init {
    self = [super init];
    if (self) {
        _displayView = [[GJImageView alloc] init];
        _enableRender = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:UIApplicationWillEnterForegroundNotification object:nil];

    }
    return self;
}
-(void)receiveNotification:(NSNotification* )notic{
    if ([notic.name isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
        _enableRender = NO;
    }else if ([notic.name isEqualToString:UIApplicationWillEnterForegroundNotification]) {
        _enableRender = YES;
    }
}
- (BOOL)displaySetFormat:(GJPixelType)format {
    _imageInput = [[GJImagePixelImageInput alloc] initWithFormat:(GJYUVPixelImageFormat) format];
    if (_imageInput == nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "GJImagePixelImageInput 创建失败！");
        return NO;
    }
    [_imageInput addTarget:(GPUImageView *) _displayView];
    return YES;
}
- (void)displayImage:(CVImageBufferRef)image {
    if (_enableRender) {
        [_imageInput updateDataWithImageBuffer:image timestamp:kCMTimeZero];
    }
}

-(void)dealloc{
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
static GBool displaySetFormat(GJPictureDisplayContext *context, GJPixelType format) {
    IOS_PictureDisplay *display = (__bridge IOS_PictureDisplay *) (context->obaque);
    return [display displaySetFormat:format];
}

static GVoid displayUnSetup(GJPictureDisplayContext *context) {
    if (context->obaque) {
        IOS_PictureDisplay *display = (__bridge_transfer IOS_PictureDisplay *) (context->obaque);
        context->obaque             = GNULL;
        display                     = nil;
    }
}
static GVoid IOS_PictureDisplayImage(GJPictureDisplayContext *context, GJRetainBuffer *image) {
    IOS_PictureDisplay *display = (__bridge IOS_PictureDisplay *) (context->obaque);
    [display displayImage:((CVImageBufferRef *) R_BufferStart(image))[0]];
}
static GHandle IOS_PictureDisplayGetView(GJPictureDisplayContext *context) {
    IOS_PictureDisplay *display = (__bridge IOS_PictureDisplay *) (context->obaque);
    return (__bridge GHandle)(display.displayView);
}
GVoid GJ_PictureDisplayContextCreate(GJPictureDisplayContext **disPlayContext) {
    if (*disPlayContext == NULL) {
        *disPlayContext = (GJPictureDisplayContext *) malloc(sizeof(GJPictureDisplayContext));
    }
    GJPictureDisplayContext *context = *disPlayContext;
    context->displaySetup            = IOS_PictureDisplaySetup;
    context->displaySetFormat        = displaySetFormat;
    context->displayView             = IOS_PictureDisplayImage;
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
