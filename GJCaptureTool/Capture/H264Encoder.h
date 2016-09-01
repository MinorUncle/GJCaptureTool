//
//  H264Encoder.h
//  FFMpegDemo
//
//  Created by tongguan on 16/7/12.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CMSampleBuffer.h>
@class H264Encoder;
@protocol H264EncoderDelegate <NSObject>
-(void)H264Encoder:(H264Encoder*)decoder h264:(uint8_t *)data size:(int)size pts:(int64_t)pts dts:(int64_t)dts;
@end
@interface H264Encoder : NSObject
- (instancetype)initWithWidth:(int)width height:(int)height;
-(void)encoderData:(CMSampleBufferRef)sampleBufferRef;
@property(assign,nonatomic,readonly)NSData* extendata;


@property(weak,nonatomic)id<H264EncoderDelegate> delegate;
@property(assign,nonatomic,readonly)int gop_size;
@property(assign,nonatomic,readonly)int max_b_frames;
@property(assign,nonatomic,readonly)int bit_rate;




@property(assign,nonatomic,readonly)int width;
@property(assign,nonatomic,readonly)int height;


@end
