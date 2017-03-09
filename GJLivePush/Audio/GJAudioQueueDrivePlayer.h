//
//  GJAudioQueueDrivePlayer.h
//  GJCaptureTool
//
//  Created by mac on 17/3/9.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GJAudioQueuePlayer.h"

@class GJAudioQueueDrivePlayer;
/**
 类似GJAudioQueuePlayer，不过这个是主动通过代理函数拉数据，可以做同步基准作用
 */

@protocol GJAudioQueueDrivePlayerDelegate <NSObject>
@required
-(BOOL)GJAudioQueueDrivePlayer:(GJAudioQueueDrivePlayer*)player outAudioData:(void**)data outSize:(int*)size;

@end

@interface GJAudioQueueDrivePlayer : NSObject
@property (nonatomic,assign,readonly) BOOL available;
@property (nonatomic,assign,readonly) AudioStreamBasicDescription format;
@property (nonatomic,assign) float volume;
@property (nonatomic,assign) UInt32 maxBufferSize;
@property (nonatomic,assign,readonly) PlayStatus status;
@property (nonatomic,weak) id<GJAudioQueueDrivePlayerDelegate> delegate;

/**
 *  return playedTime of audioqueue, return invalidPlayedTime when error occurs.
 */
@property (nonatomic,readonly) NSTimeInterval playedTime;



/**
 must on main thread
 
 @param format format description
 @param maxBufferSize bufferSize description
 @param macgicCookie macgicCookie description
 @return return value description
 */
- (instancetype)initWithFormat:(AudioStreamBasicDescription)format maxBufferSize:(UInt32)maxBufferSize macgicCookie:(NSData *)macgicCookie;


- (instancetype)initWithSampleRate:(Float64)sampleRate channel:(UInt32)channel formatID:(UInt32)formatID;


/**
 *  pause & resume
 *
 */

- (BOOL)pause;
- (BOOL)resume;

/**
 *  Stop audioqueue
 *
 *  @param immediately if pass YES, the queue will immediately be stopped,
 *                     if pass NO, the queue will be stopped after all buffers are flushed (the same job as -flush).
 *
 *  @return whether is audioqueue successfully stopped
 */
- (BOOL)stop:(BOOL)immediately;

/**
 *  reset queue
 *  Use when seeking.
 *
 *  @return whether is audioqueue successfully reseted
 */
- (BOOL)reset;

/**
 *  flush data
 *  Use when audio data reaches eof
 *  if -stop:NO is called this method will do nothing
 *
 *  @return whether is audioqueue successfully flushed
 */
- (BOOL)flush;

-(BOOL)start;
@end
