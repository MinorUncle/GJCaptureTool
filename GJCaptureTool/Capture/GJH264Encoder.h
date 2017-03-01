//
//  GJH264Encoder.h
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "GJFormats.h"
#import "GJRetainBuffer.h"
#import "GJBufferPool.h"

@class GJH264Encoder;
@protocol GJH264EncoderDelegate <NSObject>
@required
-(void)GJH264Encoder:(GJH264Encoder*)encoder encodeCompleteBuffer:(GJRetainBuffer*)buffer keyFrame:(BOOL)keyFrame dts:(CMTime)dts;
@end
@interface GJH264Encoder : NSObject
@property(nonatomic,weak)id<GJH264EncoderDelegate> deleagte;
@property(assign,nonatomic)H264Format destFormat;

/**
 已经编码的数量
 */
@property(assign,nonatomic)NSInteger frameCount;

/**
 //允许的最大码率和最小码率。用于动态码率，期望正常码率在destformat中设置。
 */
@property(assign,nonatomic) int allowMinBitRate,allowMaxBitRate;


/**
 自定义输出格式，如果直接走init()则配置默认格式.输出图像像素大小等于输入图像大小。

 @param format 格式
 @return return value description
 */
-(instancetype)initWithFormat:(H264Format)format;
-(void)encodeImageBuffer:(CVImageBufferRef)imageBuffer pts:(CMTime)pts fourceKey:(BOOL)fourceKey;

@end

void praseVideoParamet(uint8_t* inparameterSet,uint8_t** inoutSetArry,int* inoutArryCount){
    
}
