//
//  GJH264Decoder.h
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "GJFormats.h"
#import "GJQueue.h"
#import "GJRetainBuffer.h"
@class GJH264Decoder;
@protocol GJH264DecoderDelegate <NSObject>
-(void)GJH264Decoder:(GJH264Decoder*)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(uint64_t)pts;
@end

@interface GJH264Decoder : NSObject

@property(nonatomic,weak)id<GJH264DecoderDelegate> delegate;
//default kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
@property(nonatomic,assign)OSType outPutImageFormat;
-(void)decodeBuffer:(GJRetainBuffer *)buffer pts:(uint64_t)pts;
@end
