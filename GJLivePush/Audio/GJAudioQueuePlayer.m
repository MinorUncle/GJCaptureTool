//
//  MCAudioOutputQueue.m
//  MCAudioQueue
//
//  Created by Chengyin on 14-7-27.
//  Copyright (c) 2014年 Chengyin. All rights reserved.
//

#import "GJAudioQueuePlayer.h"
#import <pthread.h>
#import "GJQueue.h"
#import "GJRetainBuffer.h"
const int MCAudioQueueBufferCount = 8;

@interface GJAudioQueuePlayer ()
{
    GJQueue* _reusableQueue;
@private
    AudioQueueRef _audioQueue;
    
//    NSMutableArray *_reusableBuffers;
    dispatch_queue_t _playQueue;

}
@end

@implementation GJAudioQueuePlayer
@synthesize format = _format;
@dynamic available;
@synthesize volume = _volume;
@synthesize bufferSize = _bufferSize;

#pragma mark - init & dealloc
- (instancetype)initWithFormat:(AudioStreamBasicDescription)format  bufferSize:(UInt32)bufferSize macgicCookie:(NSData *)macgicCookie
{
    self = [super init];
    if (self)
    {
        _format = format;
        _bufferSize = bufferSize;
        [self _init];
        if (![[NSThread currentThread]isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self _createAudioOutputQueue:macgicCookie];
            });
        }else{
            [self _createAudioOutputQueue:macgicCookie];
        }
    }
    return self;
}
- (instancetype)initWithSampleRate:(Float64)sampleRate channel:(UInt32)channel formatID:(UInt32)formatID{
    self = [super init];
    if (self)
    {
        AudioStreamBasicDescription format = {0};
        format.mFormatID         = formatID;
        switch (formatID) {
            case kAudioFormatLinearPCM:
            {
                format.mSampleRate       = sampleRate;               // 3
                format.mChannelsPerFrame = channel;                     // 4
                format.mFramesPerPacket  = 1;                     // 7
                format.mBitsPerChannel   = 16;                    // 5
                format.mBytesPerFrame   = format.mChannelsPerFrame * format.mBitsPerChannel/8;
                format.mFramesPerPacket = format.mBytesPerFrame * format.mFramesPerPacket ;
                format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
                break;
            }
            case kAudioFormatMPEG4AAC:
            {
                format.mSampleRate       = sampleRate;               // 3
                format.mFormatID         = kAudioFormatMPEG4AAC; // 2
                format.mChannelsPerFrame = channel;                     // 4
                format.mFramesPerPacket  = 1024;
                break;
            }
            default:
                break;
        }
        UInt32 size = sizeof(AudioStreamBasicDescription);
        AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &format);
        _format = format;
        _volume = 1.0f;
#define BYTE_PER_CHANNEL 3
        _bufferSize = _format.mFramesPerPacket*format.mChannelsPerFrame*BYTE_PER_CHANNEL;
        if (![[NSThread currentThread]isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self _createAudioOutputQueue:NULL];
            });
        }else{
            [self _createAudioOutputQueue:NULL];
        }
    }
    return self;
}

-(void)_init{
    _volume = 1.0f;
    queueCreate(&_reusableQueue, MCAudioQueueBufferCount,true,false);
    _status = kPlayInvalidStatus;

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
//must main
- (void)_createAudioOutputQueue:(NSData *)magicCookie
{
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_format);
#ifdef DEBUG
    char *formatName = (char *)&(_format.mFormatID);
    NSLog(@"format is: %c%c%c%c     -----------", formatName[3], formatName[2], formatName[1], formatName[0]);
#endif
    AudioQueueOutputCallback callBack = pcmAudioQueueOutputCallback;
    switch (_format.mFormatID) {
        case kAudioFormatLinearPCM:
            callBack = pcmAudioQueueOutputCallback;
            break;
        case kAudioFormatMPEG4AAC:
            callBack = aacAudioQueueOutputCallback;
            break;
        default:
            return;
            break;
    }
    OSStatus status = AudioQueueNewOutput(&_format,callBack, (__bridge void *)(self),CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 0, &_audioQueue);
    if (status != noErr)
    {
        _audioQueue = NULL;
        return;
    }
//    if (_format.mChannelsPerFrame == 2) {
//        AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Pan,-1);
//        AudioQueueSetParameter(_audioQueue, kAudioQueueParam_VolumeRampTime,0.5);
//    }
//    else
//    {
//        AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Pan,0);
//    }

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
        NSLog(@"kAudioQueueProperty_MagicCookie status:%d",status);
    }
        
    _status = kPlayStopStatus;
    self.volume = 1.0;
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
    for (int i = 0; i < MCAudioQueueBufferCount-1; ++i)
    {
        AudioQueueBufferRef buffer;
        OSStatus status = AudioQueueAllocateBuffer(_audioQueue, _bufferSize, &buffer);
        buffer->mAudioDataByteSize = _bufferSize;
        memset(buffer->mAudioData, 0, buffer->mAudioDataByteSize);
        status = AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
        if (status != noErr)
        {
            AudioQueueDispose(_audioQueue, YES);
            _audioQueue = NULL;
            NSLog(@"AudioQueueAllocateBuffer faile");
            assert(!status);
            return false;
        }
    }
    UInt32 numPrepared = 0;
    OSStatus status = AudioQueuePrime(_audioQueue, 0, &numPrepared);
    status = AudioQueueStart(_audioQueue, NULL);
    if (status != 0) {
        char* codeChar = (char*)&status;
        NSLog(@"AudioQueueStartError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
        NSLog(@"播放失败");
        return NO;
    }
    
    UInt32 isRunning = 0;
    UInt32 size = sizeof(isRunning);
    AudioQueueGetProperty(_audioQueue, kAudioQueueProperty_IsRunning, &isRunning, &size);
    
    _status = kPlayRunningStatus;
//    assert(!status);
    return YES;
}

- (BOOL)resume
{
    return [self start];
}

- (BOOL)pause
{
    _status = kPlayPauseStatus;
    OSStatus status = AudioQueuePause(_audioQueue);
    if (status != noErr) {
        NSLog(@"pause error:%d",status);
        return NO;
    }
    return YES;
}

- (BOOL)reset
{
    OSStatus status = AudioQueueReset(_audioQueue);
    if (status != noErr) {
        NSLog(@"AudioQueueReset error:%d",status);
        return NO;
    }
    return YES;
}

- (BOOL)flush
{
    OSStatus status = AudioQueueFlush(_audioQueue);
    if (status != noErr) {
        NSLog(@"AudioQueueFlush error:%d",status);
        return NO;
    }
    return YES;
}

- (BOOL)stop:(BOOL)immediately
{
    PlayStatus pre = _status; //防止监听部分重启
    _status = kPlayStopStatus;
    OSStatus status = AudioQueueStop(_audioQueue, immediately);
    if (status != noErr) {
        NSLog(@"AudioQueueStop error:%d",status);
        _status = pre;

        return NO;
    }
    return YES;
}

- (BOOL)playData:(GJRetainBuffer*)bufferData packetDescriptions:(const AudioStreamPacketDescription *)packetDescriptions isEof:(BOOL)isEof{
    if (_status != kPlayRunningStatus)
    {
        static int count;
        NSLog(@"play innnnnnnnnnnnnnn error count:%d",count++);

        return NO;
    }
    
    UInt32 isRunning = 0;
    UInt32 size = sizeof(isRunning);
    AudioQueueGetProperty(_audioQueue, kAudioQueueProperty_IsRunning, &isRunning, &size);

    
    static long total = 0;
    total += bufferData->size;
    NSLog(@"play innnnnnnnnnnnnnn:%ld",total);
    retainBufferRetain(bufferData);
    if (!queuePush(_reusableQueue, bufferData, 1000)) {
        retainBufferUnRetain(bufferData);
    }

    
//        AudioQueueBufferRef bufferObj;
//        _reusableQueue->queuePop(&bufferObj,1000);
//        
//#pragma warning 后期优化 针对多包问题，但是效率更低
//        SInt64 offset = packetCount >= 1 ? packetDescriptions[0].mStartOffset : 0;
//        memcpy(bufferObj->mAudioData, (char*)data +  offset, lenth-offset);
//        bufferObj->mAudioDataByteSize = (uint32_t)(lenth-offset);
////        AudioStreamPacketDescription desc = packetDescriptions[i];
////        desc.mStartOffset = 0;
////        desc.mDataByteSize -= packetDescriptions->mStartOffset;
//        //AudioStreamPacketDescription->mStartOffset 一定要等于0，，郁闷；
//        OSStatus status = AudioQueueEnqueueBuffer(_audioQueue, bufferObj, packetCount, packetDescriptions);
//        assert(!status);
//
//    
    
    
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


- (BOOL)available
{
    return _audioQueue != NULL;
}

- (void)setVolume:(float)volume
{
    _volume = volume;
    [self setParameter:kAudioQueueParam_Volume value:_volume error:NULL];

}



#pragma mark - call back
static void pcmAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
	GJAudioQueuePlayer *player = (__bridge GJAudioQueuePlayer *)inClientData;
    GJRetainBuffer* bufferData;
    if(queuePop(player->_reusableQueue, (void**)&bufferData, 0) && player.status == kPlayRunningStatus){
         memcpy(inBuffer->mAudioData, bufferData->data, bufferData->size);
        inBuffer->mAudioDataByteSize = bufferData->size;
        retainBufferUnRetain(bufferData);
        
    }else{
        if (player.status != kPlayRunningStatus) {
            AudioQueueFreeBuffer(inAQ, inBuffer);
            return;
        }
        memset(inBuffer->mAudioData, 0, inBuffer->mAudioDataByteSize);
    }

    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
#ifdef DEBUG
    if (status < 0) {
        NSLog(@"AudioQueueEnqueueBuffer error:%d",status);
    }
#endif
}
static void aacAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer){
    static int count;
    NSLog(@"aac buffer out:%d",count++);
    GJAudioQueuePlayer *player = (__bridge GJAudioQueuePlayer *)inClientData;
    GJRetainBuffer* buffer;
    if(queuePop(player->_reusableQueue, (void**)&buffer, 0) && player.status == kPlayRunningStatus){
        memcpy(inBuffer->mAudioData, buffer->data, buffer->size);
        inBuffer->mAudioDataByteSize = buffer->size;
        retainBufferUnRetain(buffer);
        
        static int times;
        NSData* data = [NSData dataWithBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
        NSLog(@"player audio times:%d data:%@",times++,data);
        
        NSLog(@"play outttttttttttttttttttt:%d",count);
        
        

    }else{
        
        if (player.status != kPlayRunningStatus) {
            AudioQueueFreeBuffer(inAQ, inBuffer);
            return;
        }
        memset(inBuffer->mAudioData, 0, inBuffer->mAudioDataByteSize);
        NSLog(@"play out00000000000000:%d",count);
    }
    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    if (status < 0) {
        AudioQueueFreeBuffer(inAQ, inBuffer);
        NSLog(@"AudioQueueEnqueueBuffer error:%d",status);
    }

}

static void MCAudioQueuePropertyCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
	GJAudioQueuePlayer *player = (__bridge GJAudioQueuePlayer *)inUserData;
    if (inID == kAudioQueueProperty_IsRunning)
    {
        UInt32 isRunning = 0;
        UInt32 size = sizeof(isRunning);
        AudioQueueGetProperty(inAQ, inID, &isRunning, &size);
        if (player.status == kPlayRunningStatus && !isRunning) {
            [player start];
            NSLog(@"warnning ...... auto start");
        }
    }
}



- (void)dealloc
{
    queueCleanAndFree(&_reusableQueue);
    [self _disposeAudioOutputQueue];
}
@end
