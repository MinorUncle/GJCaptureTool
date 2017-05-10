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
#import "GJLiveDefine+internal.h"

typedef enum _GJEncodeQuality{
    GJEncodeQualityExcellent=0,
    GJEncodeQualityGood,
    GJEncodeQualitybad,
    GJEncodeQualityTerrible,
}GJEncodeQuality;

@class GJH264Encoder;
@protocol GJH264EncoderDelegate <NSObject>
@required

/**
 数据压缩完成时回调。

 @param encoder encoder description
 @param packet 引用用数据

 @return 可以理解为下一级数据缓存的比例，用于动态编码。
 */
-(GLong)GJH264Encoder:(GJH264Encoder*)encoder encodeCompletePacket:(R_GJH264Packet*)packet;

/**
 编码质量回调

 @param encoder encoder description
 @param quality 0优。1，一般，码率降低。2，差，码率降低且丢帧，3，非常差，码率为允许正常最小，且丢一半帧以上。
 */
-(void)GJH264Encoder:(GJH264Encoder*)encoder qualityQarning:(GJEncodeQuality)quality;
@end
@interface GJH264Encoder : NSObject
@property(nonatomic,weak)id<GJH264EncoderDelegate> deleagte;
@property(assign,nonatomic)H264Format destFormat;

/**
 已经编码的数量,不包括丢帧的数量
 */
@property(assign,nonatomic)NSInteger encodeframeCount;


/**
 总共的数量，包括丢帧的数量
 */
@property(assign,nonatomic)NSInteger frameCount;

/**
 //不丢帧情况下允许的最小码率。用于动态码率，期望正常码率在destformat中设置
 */
@property(assign,nonatomic) int allowMinBitRate;


/**
 表示允许的最大丢帧频率，每den帧丢num帧。 allowDropStep 一定小于1.0/DEFAULT_MAX_DROP_STEP,当num大于1时，den只能是num+1，
 */
@property(assign,nonatomic) GRational allowDropStep;


/**
 自定义输出格式，如果直接走init()则配置默认格式.输出图像像素大小等于输入图像大小。

 @param format 格式
 @return return value description
 */
-(instancetype)initWithFormat:(H264Format)format;

/**
 编码

 @param imageBuffer imageBuffer description
 @param pts pts in ms
 @param fourceKey fourceKey description
 @return 是否失败。可能主动丢帧，也可能编码失败
 */
-(BOOL)encodeImageBuffer:(CVImageBufferRef)imageBuffer pts:(int64_t)pts fourceKey:(BOOL)fourceKey;

/**
 刷新编码器，之前的编码不会回调。
 */
-(void)flush;
+(H264Format)defaultFormat;
@end

void praseVideoParamet(uint8_t* inparameterSet,uint8_t** inoutSetArry,int* inoutArryCount){
    
}
