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
#import "GJQueue.h"

#define MAX_PCM_LENTH 2048+10
@class AACEncoderFromPCM;
@protocol AACEncoderFromPCMDelegate<NSObject>
-(void)AACEncoderFromPCM:(AACEncoderFromPCM*)encoder encodeCompleteBuffer:(RetainBuffer*)buffer packetDesc:(AudioStreamPacketDescription*)packet;
@end
@interface AACEncoderFromPCM : NSObject
@property(nonatomic,assign,readonly)AudioStreamBasicDescription destFormatDescription;
@property(nonatomic,assign,readonly)AudioStreamBasicDescription sourceFormatDescription;

@property(nonatomic,assign,readonly)int destMaxOutSize;

@property(nonatomic,weak)id<AACEncoderFromPCMDelegate>delegate;

-(void)encodeWithBuffer:(CMSampleBufferRef)buffer;
- (instancetype)initWithDestDescription:(AudioStreamBasicDescription)description;

- (NSData *)fetchMagicCookie;

@end
