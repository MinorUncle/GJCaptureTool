//
//  RtmpSendH264.m
//  media
//
//  Created by tongguan on 16/7/29.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import "RtmpSendH264.h"
extern "C"{
#import "avcodec.h"
#import "swscale.h"
#import "imgutils.h"
}
@interface RtmpSendH264()

@end
@implementation RtmpSendH264

-(void)sendH264Buffer:(int8_t*)buffer lengh:(int)lenth pts:(int)pts dts:(int)dts{


}
@end
