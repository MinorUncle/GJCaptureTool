//
//  H264Decoder.h
//  FFMpegDemo
//
//  Created by tongguan on 16/6/15.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
typedef enum _H264DecoderStatus{
    H264DecoderPlaying,
    H264DecoderStopped
}H264DecoderStatus;
@class H264Decoder;
@protocol H264DecoderDelegate <NSObject>
-(void)H264Decoder:(H264Decoder*)decoder GetYUV:(char*)data size:(int)size width:(float)width height:(float)height;
@end

@interface H264Decoder : NSObject
@property(assign,nonatomic)H264DecoderStatus status;
@property(weak,nonatomic)id<H264DecoderDelegate> decoderDelegate;
@property(assign,nonatomic,readonly)int width;
@property(assign,nonatomic,readonly)int height;
- (instancetype)initWithWidth:(int)width height:(int)height;

-(void)decodeData:(uint8_t*)data lenth:(int)lenth;

-(void)start;
-(void)stop;

@end

