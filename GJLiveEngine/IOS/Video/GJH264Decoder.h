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
#import "GJLiveDefine+internal.h"
typedef void(^H264DecodeComplete)(CVImageBufferRef image,int64_t pts);

//@protocol GJH264DecoderDelegate <NSObject>
//-(void)GJH264Decoder:(GJH264Decoder*)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(int64_t)pts;
//@end

@interface GJH264Decoder : NSObject

//default kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
@property(nonatomic,assign)OSType outPutImageFormat;
@property(nonatomic,copy)H264DecodeComplete completeCallback;

-(void)decodePacket:(R_GJH264Packet *)packet;
@end
