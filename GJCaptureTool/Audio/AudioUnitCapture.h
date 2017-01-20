//
//  AudioUnitCapture.h
//  TVBAINIAN
//
//  Created by 米花 mihuasama on 16/1/14.
//  Copyright © 2016年 tongguantech. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AudioUnitCapture : NSObject

@property (readonly,nonatomic) AudioComponentInstance audioUnit;
@property (readonly,nonatomic) float samplerate;

- (id)initWithSamplerate:(float)samplerate;

- (void)startRecording:(void(^)(uint8_t* pcmData, int size))dataBlock;
- (void)stopRecording;
- (void)destoryBlcock;

@end
