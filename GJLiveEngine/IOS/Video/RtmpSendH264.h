//
//  RtmpSendH264.h
//  GJCaptureTool
//
//  Created by tongguan on 16/7/29.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <VideoToolbox/VideoToolbox.h>
#import "GJRetainBuffer.h"

@interface RtmpSendH264 : NSObject
@property (nonatomic, assign) AudioStreamBasicDescription audioStreamFormat;
@property (nonatomic, assign) CMVideoFormatDescriptionRef videoStreamFormat;

@property (nonatomic, assign) int audioBitRate;
@property (nonatomic, assign) int videoBitRate;

@property (nonatomic, assign) int     width;
@property (nonatomic, assign) int     height;
@property (nonatomic, retain) NSData *pps;
@property (nonatomic, retain) NSData *sps;

@property (nonatomic, retain) NSMutableData *videoExtradata;

//default yes
@property (nonatomic, assign) BOOL hasBFrame;

- (instancetype)initWithOutUrl:(NSString *)outUrl;
- (void)sendH264Buffer:(uint8_t *)buffer lengh:(int)lenth pts:(int64_t)pts dts:(int64_t)dts eof:(BOOL)isEof;
- (void)sendAACBuffer:(uint8_t *)buffer lenth:(int)lenth pts:(int64_t)pts dts:(int64_t)dts eof:(BOOL)isEof;
@end
