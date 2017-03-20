//
//  GJImageYUVDataInput.h
//  GJImage
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GPUImageOutput.h"
// The bytes passed into this input are not copied or retained, but you are free to deallocate them after they are used by this filter.
// The bytes are uploaded and stored within a texture, so nothing is kept locally.
// The default format for input bytes is GPUPixelFormatBGRA, unless specified with pixelFormat:
// The default type for input bytes is GPUPixelTypeUByte, unless specified with pixelType:

typedef enum {
    GJPixelFormatI420,
    GJPixelFormatYV12,
    GJPixelFormatNV12,
    GJPixelFormatNV21,
} GJYUVPixelFormat;

typedef enum {
    GJPixelTypeUByte = GL_UNSIGNED_BYTE,
    GJPixelTypeFloat = GL_FLOAT
} GJPixelType;

@interface GJImageYUVDataInput : GPUImageOutput
{
    CGSize uploadedImageSize;
    
    dispatch_semaphore_t dataUpdateSemaphore;
}

// Initialization and teardown

- (id)initPixelFormat:(GJYUVPixelFormat)pixelFormat;

/** Input data pixel format
 */
@property (readwrite, nonatomic) GJYUVPixelFormat pixelFormat;
@property (readwrite, nonatomic) GJPixelType   pixelType;

// 420p
- (void)updateDataWithImageSize:(CGSize)imageSize Y:(GLubyte *)Ybytes U:(GLubyte*)Ubytes V:(GLubyte*)Vbytes type:(GJPixelType)pixelType Timestamp:(CMTime)frameTime;
// 420sp
- (void)updateDataWithImageSize:(CGSize)imageSize Y:(GLubyte *)Ybytes CrBr:(GLubyte*)CrBrbytes type:(GJPixelType)pixelType Timestamp:(CMTime)frameTime;


-(void)updateDataWithImageBuffer:(CVImageBufferRef)imageBuffer timestamp:(CMTime)frameTime;
@end
