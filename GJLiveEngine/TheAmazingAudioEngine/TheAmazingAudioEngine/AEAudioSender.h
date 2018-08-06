//
//  AEAudioSender.h
//  TheAmazingAudioEngine
//
//  Created by lbzhao on 2017/5/8.
//  Copyright © 2017年 A Tasty Pixel. All rights reserved.
//

#ifdef __cplusplus
extern "C" {
#endif
    
#import <Foundation/Foundation.h>
#import "TheAmazingAudioEngine.h"
    
@protocol AEAudioSenderDelegate<NSObject>
- (void)AEAudioSenderPushData:(AudioBufferList*)pData withTime:(const AudioTimeStamp*)lAudioTime;
@end

    
@interface AEAudioSender : NSObject <AEAudioReceiver>
- (id)initWithAudioController:(AEAudioController*)audioController;

@property(assign,nonatomic)id<AEAudioSenderDelegate> delegate;
@end
