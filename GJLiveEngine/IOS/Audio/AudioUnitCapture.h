//
//  AudioUnitCapture.h
//  TVBAINIAN
//
//  Created by 米花 mihuasama on 16/1/14.
//  Copyright © 2016年 tongguantech. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "GJLiveDefine+internal.h"

@interface AudioUnitCapture : NSObject

@property (readonly,nonatomic) AudioComponentInstance audioUnit;
@property (readonly,nonatomic) AudioStreamBasicDescription format;

- (id)initWithSamplerate:(float)samplerate channel:(UInt32)channel;

- (void)startRecording:(void(^)(R_GJPCMFrame* frame))dataBlock;
- (void)stopRecording;
- (void)destoryBlcock;

@end
