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

@interface IOS_PictureDisplay:NSObject
@property(strong,nonatomic)GJImagePixelImageInput*          imageInput;
@property(strong,nonatomic)GJImageView*                     displayView;
@end
@implementation IOS_PictureDisplay
- (instancetype)initWithFormat:(GJPixelFormat)format
{
    self = [super init];
    if (self) {
        _displayView = [[GJImageView alloc]init];
        _imageInput = [[GJImagePixelImageInput alloc]initWithFormat:(GJYUVPixelImageFormat)format];
        if (_imageInput == nil) {
            GJLOG(GJ_LOGFORBID, "GJImagePixelImageInput 创建失败！");
            return nil;
        }
        [_imageInput addTarget:(GPUImageView*)_displayView];

    }
    return self;
}
-(void)displayImage:(CVImageBufferRef)image{
    [_imageInput updateDataWithImageBuffer:image timestamp:kCMTimeZero];
}
@end
static GBool IOS_PictureDisplayCreate(GJPictureDisplayContext* context,GJPixelFormat format){
    context->obaque = (__bridge GHandle)([[IOS_PictureDisplay alloc]initWithFormat:format]);
    return context->obaque != nil;
}
static GVoid IOS_PictureDisplayImage(GJPictureDisplayContext* context,GHandle image){
    IOS_PictureDisplay* display = (__bridge IOS_PictureDisplay *)(context->obaque);
    [display displayImage:image];
}
void GJ_PictureDisplayContextCreate(GJPictureDisplayContext* context){
    if (context == NULL) {
        context = (GJPictureDisplayContext*)malloc(sizeof(GJPictureDisplayContext));
    }
    context->displayInit = IOS_PictureDisplayCreate;
    context->displayView = IOS_PictureDisplayImage;
}
