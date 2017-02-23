//
//  PCMDecodeFromAAC.h
//  视频录制
//
//  Created by tongguan on 16/1/8.
//  Copyright © 2016年 未成年大叔. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AudioToolbox/AudioToolbox.h>
#import "GJRetainBuffer.h"

@class PCMDecodeFromAAC;
@protocol PCMDecodeFromAACDelegate <NSObject>
-(void)pcmDecode:(PCMDecodeFromAAC*)decoder completeBuffer:(GJRetainBuffer*)buffer packetDesc:(AudioStreamPacketDescription*)packetDesc;
@end
@interface PCMDecodeFromAAC : NSObject
@property (nonatomic,assign,readonly) UInt32 destMaxOutSize;
@property (nonatomic,assign,readonly) AudioStreamBasicDescription sourceFormatDescription;
@property (nonatomic,assign,readonly)AudioStreamBasicDescription destFormatDescription;


@property (nonatomic,assign,readonly) UInt32 bitRate;
@property (nonatomic,weak) id<PCMDecodeFromAACDelegate>delegate;


-(void)decodeBuffer:(GJRetainBuffer*)buffer packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins;


- (instancetype)initWithDestDescription:(AudioStreamBasicDescription*)description SourceDescription:(AudioStreamBasicDescription*)sourceDescription sourceMaxBufferLenth:(int)maxLenth;
@end
