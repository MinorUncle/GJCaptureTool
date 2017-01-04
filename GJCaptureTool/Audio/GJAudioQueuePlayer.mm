//
//  MCAudioOutputQueue.m
//  MCAudioQueue
//
//  Created by Chengyin on 14-7-27.
//  Copyright (c) 2014年 Chengyin. All rights reserved.
//

#import "GJAudioQueuePlayer.h"
#import <pthread.h>
#import "GJQueue+cplus.h"

const int MCAudioQueueBufferCount = 20;

@interface MCAudioQueueBuffer : NSObject
@property (nonatomic,assign) AudioQueueBufferRef buffer;
@end
@implementation MCAudioQueueBuffer
@end

@interface GJAudioQueuePlayer ()
{
@private
    AudioQueueRef _audioQueue;
    GJQueue<AudioQueueBufferRef>* _reusableQueue;
    
//    NSMutableArray *_reusableBuffers;
    dispatch_queue_t _playQueue;
    BOOL _isRunning;
    BOOL _started;
    NSTimeInterval _playedTime;

}
@end

@implementation GJAudioQueuePlayer
@synthesize format = _format;
@dynamic available;
@synthesize volume = _volume;
@synthesize bufferSize = _bufferSize;
@synthesize isRunning = _isRunning;

#pragma mark - init & dealloc
- (instancetype)initWithFormat:(AudioStreamBasicDescription)format  bufferSize:(UInt32)bufferSize macgicCookie:(NSData *)macgicCookie
{
    self = [super init];
    if (self)
    {
        _format = format;
        _volume = 1.0f;
        _bufferSize = bufferSize;
        
        _reusableQueue = new GJQueue<AudioQueueBufferRef>(MCAudioQueueBufferCount);

        _reusableQueue->autoResize = NO;

        [self _createAudioOutputQueue:macgicCookie];
    }
    return self;
}



#pragma mark - error
- (void)_errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError

{
    if (status != noErr && outError != NULL)
    {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}

#pragma mark - audio queue
- (void)_createAudioOutputQueue:(NSData *)magicCookie
{
    char *formatName = (char *)&(_format.mFormatID);
            NSLog(@"format is: %c%c%c%c     -----------", formatName[3], formatName[2], formatName[1], formatName[0]);
    
    _playQueue = dispatch_queue_create("playQueue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(_playQueue, ^{
        OSStatus status = AudioQueueNewOutput(&_format,MCAudioQueueOutputCallback, (__bridge void *)(self),CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 0, &_audioQueue);
        assert(!status);
        if (status != noErr)
        {
            _audioQueue = NULL;
            return;
        }
        
        status = AudioQueueAddPropertyListener(_audioQueue, kAudioQueueProperty_IsRunning, MCAudioQueuePropertyCallback, (__bridge void *)(self));
        assert(!status);
        if (status != noErr)
        {
            AudioQueueDispose(_audioQueue, YES);
            _audioQueue = NULL;
            return;
        }
        
        
#if TARGET_OS_IPHONE
        UInt32 property = kAudioQueueHardwareCodecPolicy_PreferSoftware;
        [self setProperty:kAudioQueueProperty_HardwareCodecPolicy dataSize:sizeof(property) data:&property error:NULL];
#endif
        
        if (magicCookie)
        {
            status = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, [magicCookie bytes], (UInt32)[magicCookie length]);
            NSLog(@"status:%d",status);
        }
        
        
        if (_reusableQueue->currentLenth() == 0)
        {
            for (int i = 0; i < MCAudioQueueBufferCount; ++i)
            {
                AudioQueueBufferRef buffer;
                status = AudioQueueAllocateBuffer(_audioQueue, _bufferSize, &buffer);
                if (status != noErr)
                {
                    AudioQueueDispose(_audioQueue, YES);
                    _audioQueue = NULL;
                    NSLog(@"AudioQueueAllocateBuffer faile");
                    assert(!status);
                    return ;
                }
                _reusableQueue->queuePush(buffer,1000);
            }
        }

        
        [self setVolumeParameter];
        [self start];
        CFRunLoopRun();
    });
   
}

- (void)_disposeAudioOutputQueue
{
    if (_audioQueue != NULL)
    {
        AudioQueueDispose(_audioQueue,true);
        _audioQueue = NULL;
    }
}

- (BOOL)start
{
//    UInt32 isRunning;
//    [self getProperty:kAudioQueueProperty_IsRunning dataSize:&isRunning data:&isRunning error:nil];
//    if (isRunning) {
//        return YES;
//    }
    OSStatus status = AudioQueueStart(_audioQueue, NULL);
    _started = status == noErr;
    if (status != 0) {
        char* codeChar = (char*)&status;
        NSLog(@"AudioQueueStartError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
        NSLog(@"播放失败");
    }
//    assert(!status);
    return _started;
}

- (BOOL)resume
{
    return [self start];
}

- (BOOL)pause
{
    OSStatus status = AudioQueuePause(_audioQueue);
    _started = NO;
    return status == noErr;
}

- (BOOL)reset
{
    OSStatus status = AudioQueueReset(_audioQueue);
    return status == noErr;
}

- (BOOL)flush
{
    OSStatus status = AudioQueueFlush(_audioQueue);
    return status == noErr;
}

- (BOOL)stop:(BOOL)immediately
{
    _started = NO;
    _playedTime = 0;
    OSStatus status = noErr;
    if (immediately)
    {
        status = AudioQueueStop(_audioQueue, true);
    }
    else
    {
        status = AudioQueueStop(_audioQueue, false);
    }

    return status == noErr;
}

- (BOOL)playData:(const void *)data lenth:(int)lenth packetCount:(UInt32)packetCount packetDescriptions:(const AudioStreamPacketDescription *)packetDescriptions isEof:(BOOL)isEof{
    if (!_started)
    {
        return NO;
    }
        AudioQueueBufferRef bufferObj;
        _reusableQueue->queuePop(&bufferObj,1000);
        
#pragma warning 后期优化 针对多包问题，但是效率更低
        SInt64 offset = packetCount >= 1 ? packetDescriptions[0].mStartOffset : 0;
        memcpy(bufferObj->mAudioData, (char*)data +  offset, lenth-offset);
        bufferObj->mAudioDataByteSize = (uint32_t)(lenth-offset);
//        AudioStreamPacketDescription desc = packetDescriptions[i];
//        desc.mStartOffset = 0;
//        desc.mDataByteSize -= packetDescriptions->mStartOffset;
        //AudioStreamPacketDescription->mStartOffset 一定要等于0，，郁闷；
        OSStatus status = AudioQueueEnqueueBuffer(_audioQueue, bufferObj, packetCount, packetDescriptions);
        assert(!status);

    
    
    
//    for (int i = 0; i<packetCount; i++) {
//        AudioQueueBufferRef bufferObj;
//        _reusableQueue->queuePop(&bufferObj);
//        
//#pragma warning 后期优化 针对多包问题，但是效率更低
//        memcpy(bufferObj->mAudioData, (char*)data + packetDescriptions[i].mStartOffset, lenth-packetDescriptions[i].mStartOffset);
//        bufferObj->mAudioDataByteSize = lenth;
//        AudioStreamPacketDescription desc = packetDescriptions[i];
//        desc.mStartOffset = 0;
//        desc.mDataByteSize -= packetDescriptions->mStartOffset;
//        //AudioStreamPacketDescription->mStartOffset 一定要等于0，，郁闷；
//        AudioQueueEnqueueBuffer(_audioQueue, bufferObj, 1, packetDescriptions);
//        //    assert(!status);
//    }
    
    
    
    return YES;
}

- (BOOL)setProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueSetProperty(_audioQueue, propertyID, data, dataSize);
    [self _errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)getProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32 *)dataSize data:(void *)data error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueGetProperty(_audioQueue, propertyID, data, dataSize);
    [self _errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)setParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue)value error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueSetParameter(_audioQueue, parameterId, value);
    [self _errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)getParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue *)value error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueGetParameter(_audioQueue, parameterId, value);
    [self _errorForOSStatus:status error:outError];
    return status == noErr;
}


#pragma mark - property
- (NSTimeInterval)playedTime
{
    if (_format.mSampleRate == 0)
    {
        return 0;
    }
    
    AudioTimeStamp time;
    OSStatus status = AudioQueueGetCurrentTime(_audioQueue, NULL, &time, NULL);
    if (status == noErr)
    {
        _playedTime = time.mSampleTime / _format.mSampleRate;
    }
    
    return _playedTime;
}

- (BOOL)available
{
    return _audioQueue != NULL;
}

- (void)setVolume:(float)volume
{
    _volume = volume;
    [self setVolumeParameter];
}

- (void)setVolumeParameter
{
    [self setParameter:kAudioQueueParam_Volume value:_volume error:NULL];
}

#pragma mark - call back
static void MCAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
	GJAudioQueuePlayer *audioOutputQueue = (__bridge GJAudioQueuePlayer *)inClientData;
	[audioOutputQueue handleAudioQueueOutputCallBack:inAQ buffer:inBuffer];
}

- (void)handleAudioQueueOutputCallBack:(AudioQueueRef)audioQueue buffer:(AudioQueueBufferRef)buffer
{
    _reusableQueue->queuePush(buffer,1000);
}

static void MCAudioQueuePropertyCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
	GJAudioQueuePlayer *audioQueue = (__bridge GJAudioQueuePlayer *)inUserData;
	[audioQueue handleAudioQueuePropertyCallBack:inAQ property:inID];
}

- (void)handleAudioQueuePropertyCallBack:(AudioQueueRef)audioQueue property:(AudioQueuePropertyID)property
{
    if (property == kAudioQueueProperty_IsRunning)
    {
        UInt32 isRunning = 0;
        UInt32 size = sizeof(isRunning);
        AudioQueueGetProperty(audioQueue, property, &isRunning, &size);
        _isRunning = isRunning;
    }
}

- (void)dealloc
{
    free(_reusableQueue);
    [self _disposeAudioOutputQueue];
}
@end
