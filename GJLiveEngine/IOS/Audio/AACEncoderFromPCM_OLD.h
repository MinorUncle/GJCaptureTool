//
//  PCMEncoderToAAC.h
//  视频录制
//
//  Created by tongguan on 16/1/8.
//  Copyright © 2016年 未成年大叔. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import "GJLiveDefine+internal.h"
typedef void (^AACEncodeComplete)(R_GJPacket *packet);
#define MAX_PCM_LENTH 2048 + 10
//@class AACEncoderFromPCM;
//@protocol AACEncoderFromPCMDelegate<NSObject>
//-(void)AACEncoderFromPCM:(AACEncoderFromPCM*)encoder completeBuffer:(R_GJAACPacket*)buffer;
//@end
@interface AACEncoderFromPCM : NSObject
@property (nonatomic, assign, readonly) AudioStreamBasicDescription destFormat;
@property (nonatomic, assign, readonly) AudioStreamBasicDescription sourceFormat;

@property (nonatomic, assign, readonly) int destMaxOutSize;
@property (nonatomic, assign) int bitrate;

@property (nonatomic, copy) AACEncodeComplete completeCallback;

//@property(nonatomic,weak)id<AACEncoderFromPCMDelegate>delegate;

- (BOOL)start;
- (BOOL)stop;
- (void)encodeWithBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)encodeWithPacket:(R_GJPCMFrame *)packet;
- (instancetype)initWithSourceForamt:(const AudioStreamBasicDescription *)sFormat DestDescription:(const AudioStreamBasicDescription *)dFormat bitrate:(int)bitrate;

- (NSData *)fetchMagicCookie;

@end
