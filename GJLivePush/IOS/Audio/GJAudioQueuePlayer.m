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
static const int MCAudioQueueBufferCount = 3;

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
@synthesize maxBufferSize = _maxBufferSize;

#pragma mark - init & dealloc
- (instancetype)initWithFormat:(AudioStreamBasicDescription)format  maxBufferSize:(UInt32)maxBufferSize macgicCookie:(NSData *)macgicCookie
{
    self = [super init];
    if (self)
    {
        _format = format;
        _maxBufferSize = maxBufferSize;
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
        [self _init];
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
                _maxBufferSize =format.mBytesPerFrame * format.mChannelsPerFrame*sampleRate * 0.4;

                break;
            }
            case kAudioFormatMPEG4AAC:
            {
                format.mSampleRate       = sampleRate;               // 3
                format.mFormatID         = kAudioFormatMPEG4AAC; // 2
                format.mChannelsPerFrame = channel;                     // 4
                format.mFramesPerPacket  = 1024;
                _maxBufferSize = format.mFramesPerPacket * format.mChannelsPerFrame *2;
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
    _status = kPlayAInvalidStatus;

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
        NSLog(@"kAudioQueueProperty_MagicCookie status:%d",(int)status);
    }
        
    _status = kPlayAStopStatus;
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
        AudioQueueBufferRef inBuffer;
        OSStatus status = AudioQueueAllocateBufferWithPacketDescriptions(_audioQueue, _maxBufferSize, 1, &inBuffer);
        inBuffer->mAudioDataByteSize = _maxBufferSize;
        memset(inBuffer->mAudioData, 0, inBuffer->mAudioDataByteSize);
        inBuffer->mPacketDescriptionCount = 1;
        inBuffer->mPacketDescriptions[0].mDataByteSize = inBuffer->mAudioDataByteSize;
        inBuffer->mPacketDescriptions[0].mStartOffset  = 0;
        inBuffer->mPacketDescriptions[0].mVariableFramesInPacket = 0;
        status = AudioQueueEnqueueBuffer(_audioQueue, inBuffer, 0, NULL);
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
        NSLog(@"AudioQueueStartError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],(int)status);
        NSLog(@"播放失败");
        return NO;
    }
    
    UInt32 isRunning = 0;
    UInt32 size = sizeof(isRunning);
    AudioQueueGetProperty(_audioQueue, kAudioQueueProperty_IsRunning, &isRunning, &size);
    
    _status = kPlayARunningStatus;
//    assert(!status);
    return YES;
}

- (BOOL)resume
{
    return [self start];
}

- (BOOL)pause
{
    _status = kPlayAPauseStatus;
    OSStatus status = AudioQueuePause(_audioQueue);
    if (status != noErr) {
        NSLog(@"pause error:%d",(int)status);
        return NO;
    }
    return YES;
}

- (BOOL)reset
{
    OSStatus status = AudioQueueReset(_audioQueue);
    if (status != noErr) {
        NSLog(@"AudioQueueReset error:%d",(int)status);
        return NO;
    }
    return YES;
}

- (BOOL)flush
{
    OSStatus status = AudioQueueFlush(_audioQueue);
    if (status != noErr) {
        NSLog(@"AudioQueueFlush error:%d",(int)status);
        return NO;
    }
    return YES;
}

- (BOOL)stop:(BOOL)immediately
{
    PlayStatus pre = _status; //防止监听部分重启
    _status = kPlayAStopStatus;
    OSStatus status = AudioQueueStop(_audioQueue, immediately);
    if (status != noErr) {
        NSLog(@"AudioQueueStop error:%d",(int)status);
        _status = pre;

        return NO;
    }
    GJRetainBuffer* buffer = NULL;
    while (queuePop(_reusableQueue, (void*)&buffer, 0)) {
        retainBufferUnRetain(buffer);
    }
    return YES;
}

- (BOOL)playData:(GJRetainBuffer*)bufferData packetDescriptions:(const AudioStreamPacketDescription *)packetDescriptions{
    if (_status != kPlayARunningStatus)
    {
        static int count;
        NSLog(@"play innnnnnnnnnnnnnn error count:%d",count++);

        return NO;
    }
    
    retainBufferRetain(bufferData);
    if (!queuePush(_reusableQueue, bufferData, 1000)) {
        retainBufferUnRetain(bufferData);
    }
    
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
    if(queuePop(player->_reusableQueue, (void**)&bufferData, 0) && player.status == kPlayARunningStatus){
         memcpy(inBuffer->mAudioData, bufferData->data, bufferData->size);
        inBuffer->mAudioDataByteSize = bufferData->size;
        retainBufferUnRetain(bufferData);
        NSLog(@"AudioQueueEnqueueBuffer SIZE:%D",(int)inBuffer->mAudioDataByteSize);

    }else{
        if (player.status != kPlayARunningStatus) {
            AudioQueueFreeBuffer(inAQ, inBuffer);
            return;
        }
        memset(inBuffer->mAudioData, 0, inBuffer->mAudioDataByteSize);
    }


    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    if (status < 0) {
        NSLog(@"AudioQueueEnqueueBuffer error:%d",(int)status);
    }
}
static void aacAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer){
    static int count;
    NSLog(@"aac buffer out:%d",count++);
    GJAudioQueuePlayer *player = (__bridge GJAudioQueuePlayer *)inClientData;
    GJRetainBuffer* buffer;
    if(queuePop(player->_reusableQueue, (void**)&buffer, 0) && player.status == kPlayARunningStatus){
        memcpy(inBuffer->mAudioData, buffer->data, buffer->size);
        inBuffer->mAudioDataByteSize = buffer->size;
        retainBufferUnRetain(buffer);
    }else{
        
        if (player.status == kPlayAStopStatus) {
            AudioQueueFreeBuffer(inAQ, inBuffer);
            return;
        }else{
            NSLog(@"没有数据，重复播放");
        }
    }
    inBuffer->mPacketDescriptionCount = 1;
    inBuffer->mPacketDescriptions[0].mDataByteSize = inBuffer->mAudioDataByteSize;
    inBuffer->mPacketDescriptions[0].mStartOffset  = 0;
    inBuffer->mPacketDescriptions[0].mVariableFramesInPacket = 0;
    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    if (status < 0) {
        AudioQueueFreeBuffer(inAQ, inBuffer);
        NSLog(@"AudioQueueEnqueueBuffer error:%d",(int)status);
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
        if (player.status == kPlayARunningStatus && !isRunning) {
            [player start];
            NSLog(@"warnning ...... auto start");
        }
    }
}



- (void)dealloc
{
    queueFree(&_reusableQueue);
    [self _disposeAudioOutputQueue];
}
@end
