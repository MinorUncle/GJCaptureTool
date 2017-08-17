//
//  GJImageFramebuffer.h
//  GJImage
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GPUImageFramebuffer.h"

@interface GJImageFramebuffer : GPUImageFramebuffer
{
    CVOpenGLESTextureRef overriddenGLTexture;
}
- (id)initWithSize:(CGSize)framebufferSize overriddenGLTexture:(CVOpenGLESTextureRef)inputTexture;

@end
