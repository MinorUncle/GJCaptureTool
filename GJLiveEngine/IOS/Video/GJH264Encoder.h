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



#if __COREFOUNDATION_CFBASE__
CFStringRef  getCFStrByLevel(ProfileLevel level){
    CFStringRef ref;
    switch (level) {
        case profileLevelBase:
            ref = kVTProfileLevel_H264_Baseline_AutoLevel;
            break;
        case profileLevelMain:
            ref = kVTProfileLevel_H264_Main_AutoLevel;
            break;
        case profileLevelHigh:
            ref = kVTProfileLevel_H264_High_AutoLevel;
            break;
        default:
            break;
    }
    return ref;
}
CFStringRef getCFStrByEntropyMode(EntropyMode model){
    CFStringRef ref;
    switch (model) {
        case EntropyMode_CABAC:
            ref = kVTH264EntropyMode_CABAC;
            break;
        case EntropyMode_CAVLC:
            ref = kVTH264EntropyMode_CAVLC;
            break;
        default:
            break;
    }
    return ref;
}



#endif
typedef void(^H264EncodeComplete)(R_GJPacket* packet);

@interface GJH264Encoder : NSObject

@property(assign,nonatomic)EntropyMode entropyMode;
@property(assign,nonatomic)ProfileLevel profileLevel;
@property(assign,nonatomic)int gop;
@property(assign,nonatomic)BOOL allowBFrame;
@property(assign,nonatomic)int bitrate;
@property(assign,nonatomic,readonly)CGSize sourceSize;
@property(nonatomic,retain)NSData* sps;
@property(nonatomic,retain)NSData* pps;

@property(nonatomic,copy)H264EncodeComplete completeCallback;

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


/**
 .den帧中丢.num帧或多发.num帧则出发敏感算法默认（4，8）,给了den帧数据，但是只发送了小于nun帧，则主动降低质量
 */

/**
 自定义输出格式，如果直接走init()则配置默认格式.输出图像像素大小等于输入图像大小。

 @param size 格式
 @return return value description
 */
-(instancetype)initWithSourceSize:(CGSize)size;
/**
 编码

 @param imageBuffer imageBuffer description
 @param pts pts in ms
 @param fourceKey fourceKey description
 @return 是否失败。可能主动丢帧，也可能编码失败
 */
-(BOOL)encodeImageBuffer:(CVImageBufferRef)imageBuffer pts:(int64_t)pts;

/**
 刷新编码器，之前的编码不会回调。
 */
-(void)flush;
//+(H264Format)defaultFormat;
@end

void praseVideoParamet(uint8_t* inparameterSet,uint8_t** inoutSetArry,int* inoutArryCount){
    
}
