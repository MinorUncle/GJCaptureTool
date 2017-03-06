//
//  GJOpenALPlayer.h
//  BTDemo
//
//  Created by rainbownight on 13-8-16.
//  Copyright (c) 2013年 Shadow. All rights reserved.
//

//  功能说明:
//  简单的实现了播放流式PCM数据的功能



#import <Foundation/Foundation.h>
#import <OpenAL/al.h>
#import <OpenAL/alc.h>



typedef enum {
    OpenalStatePlay,
    OpenalStatePause,
    OpenalStateStop
}OpenalState;
@interface GJOpenALPlayer : NSObject

@property (nonatomic, assign) float volume;
/**
 *  Default OpenalStatePlay,
 */
@property (nonatomic, assign)OpenalState state;

- (instancetype)initWithSamplerate:(int)samplerate bitPerFrame:(int)bitPerFrame channels:(int)channels;
//添加音频数据到队列内
- (void)insertPCMDataToQueue:(unsigned char *)data size:(UInt32)size samplerate:(long)samplerate bitPerFrame:(long)bitPerFrame channels:(long)channels;
//播放声音
- (void)play;
//停止播放
- (void)stop;
- (void)pause;
//debug, 打印队列内缓存区数量和已播放的缓存区数量
- (void)getInfo;

+ (void)setPlayBackToSpeaker;
@end
