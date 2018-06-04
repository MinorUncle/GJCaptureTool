//
//  GJPCMDecodeFromAAC.h
//  视频录制
//
//  Created by tongguan on 16/1/8.
//  Copyright © 2016年 未成年大叔. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AudioToolbox/AudioToolbox.h>
#import "GJRetainBuffer.h"
#import "GJLiveDefine+internal.h"
typedef void (^DecodeComplete)(R_GJPCMFrame *frame);

@interface GJPCMDecodeFromAAC : NSObject
@property (nonatomic, assign, readonly) AudioStreamBasicDescription sourceFormat;
@property (nonatomic, assign, readonly) AudioStreamBasicDescription destFormat;

@property (nonatomic, assign, readonly) UInt32 bitRate;
@property (nonatomic, assign, readonly) UInt32 destMaxOutSize;
@property (nonatomic, copy) DecodeComplete decodeCallback;

- (void)start;
- (void)stop;

- (void)decodePacket:(R_GJPacket *)packet;

@end
