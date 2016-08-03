//
//  GJH264Encoder.h
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

@class GJH264Encoder;
@protocol GJH264EncoderDelegate <NSObject>
-(void)GJH264Encoder:(GJH264Encoder*)encoder encodeCompleteBuffer:(uint8_t*)buffer withLenth:(long)totalLenth;
@end




@interface GJH264Encoder : NSObject
@property(nonatomic,weak)id<GJH264EncoderDelegate> deleagte;
@property(nonatomic,readonly,retain)NSData* parameterSet;
@property(assign,nonatomic) int32_t currentWidth;
@property(assign,nonatomic) int32_t currentHeight;
-(void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;
-(void)stop;
@end
