//
//  GJAudioMixer.h
//  TheAmazingAudioEngine
//
//  Created by melot on 2017/6/27.
//  Copyright © 2017年 A Tasty Pixel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AEAudioController.h"


//#define ENABLE_IGNORE
@protocol GJAudioMixerDelegate <NSObject>

-(void)audioMixerProduceFrameWith:(AudioBufferList*)frame time:(int64_t)time;

@end

@interface GJAudioMixer : NSObject <AEAudioReceiver>
@property (nonatomic, readonly) AEAudioReceiverCallback receiverCallback;
@property (nonatomic, weak)id<GJAudioMixerDelegate> delegate;

#ifdef ENABLE_IGNORE
-(void)addIgnoreSource:(void*)source;
-(void)removeIgnoreSource:(void*)source;
#endif
@end
