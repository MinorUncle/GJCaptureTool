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

@class GJPCMDecodeFromAAC;
@protocol GJPCMDecodeFromAACDelegate <NSObject>
-(void)pcmDecode:(GJPCMDecodeFromAAC*)decoder completeBuffer:(GJRetainBuffer*)buffer pts:(int64_t)pts;
@end
@interface GJPCMDecodeFromAAC : NSObject
@property (nonatomic,assign,readonly) AudioStreamBasicDescription sourceFormat;
@property (nonatomic,assign,readonly)AudioStreamBasicDescription destFormat;


@property (nonatomic,assign,readonly) UInt32 bitRate;
@property (nonatomic,weak) id<GJPCMDecodeFromAACDelegate>delegate;
@property (nonatomic,assign,readonly) UInt32 destMaxOutSize;

-(void)start;
-(void)stop;

-(void)decodePacket:(R_GJAACPacket*)packet;


- (instancetype)initWithDestDescription:(AudioStreamBasicDescription*)description SourceDescription:(AudioStreamBasicDescription*)sourceDescription;
@end
