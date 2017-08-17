//
//  GJImagePixelImageInput.h
//  GJImage
//
//  Created by melot on 2017/3/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GPUImageOutput.h"
typedef enum {
    GJPixelImageFormat_32RGBA                   = kCVPixelFormatType_32RGBA,
    GJPixelImageFormat_32BGRA                   = kCVPixelFormatType_32BGRA,
    GJPixelImageFormat_YpCbCr8Planar            = kCVPixelFormatType_420YpCbCr8Planar,                  //yyyyyyyyuuvv
    GJPixelImageFormat_YpCbCr8BiPlanar          = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,      //yyyyyyyyuvuv
    GJPixelImageFormat_YpCbCr8Planar_Full       = kCVPixelFormatType_420YpCbCr8PlanarFullRange,         //yyyyyyyyuuvv
    GJPixelImageFormat_YpCbCr8BiPlanar_Full     = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,       //yyyyyyyyuvuv
} GJYUVPixelImageFormat;
@interface GJImagePixelImageInput : GPUImageOutput
@property(assign,nonatomic,readonly)GJYUVPixelImageFormat imageFormat;
- (instancetype)initWithFormat:(GJYUVPixelImageFormat)format;
-(void)updateDataWithImageBuffer:(CVImageBufferRef)imageBuffer timestamp:(CMTime)frameTime;
@end
