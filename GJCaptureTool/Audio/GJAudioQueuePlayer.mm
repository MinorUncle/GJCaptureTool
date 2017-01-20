//
//  MCAudioOutputQueue.m
//  MCAudioQueue
//
//  Created by Chengyin on 14-7-27.
//  Copyright (c) 2014年 Chengyin. All rights reserved.
//

#import "GJAudioQueuePlayer.h"
#import <pthread.h>

const int MCAudioQueueBufferCount = 4;
typedef struct _AACRetainBuffer{
    RetainBuffer* bufferData;
    UInt32 packetCount;
    AudioStreamPacketDescription* packetDescriptions;
}AACRetainBuffer;


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
        _volume = 1.0f;
        _bufferSize = bufferSize;
        queueCreate(&_reusableQueue, MCAudioQueueBufferCount);
        _reusableQueue->autoResize = NO;
        _status = kPlayInvalidStatus;
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
    if (_format.mChannelsPerFrame == 2) {
        AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Pan,-1);
        AudioQueueSetParameter(_audioQueue, kAudioQueueParam_VolumeRampTime,0.5);
    }
    else
    {
        AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Pan,0);
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
        NSLog(@"kAudioQueueProperty_MagicCookie status:%d",status);
    }
        
    for (int i = 0; i < MCAudioQueueBufferCount; ++i)
    {
        AudioQueueBufferRef buffer;
        status = AudioQueueAllocateBuffer(_audioQueue, _bufferSize, &buffer);
        status = AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
        if (status != noErr)
        {
            AudioQueueDispose(_audioQueue, YES);
            _audioQueue = NULL;
            NSLog(@"AudioQueueAllocateBuffer faile");
            assert(!status);
            return ;
        }
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
    
    OSStatus status = AudioQueueStart(_audioQueue, NULL);
    if (status != 0) {
        char* codeChar = (char*)&status;
        NSLog(@"AudioQueueStartError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
        NSLog(@"播放失败");
        return NO;
    }
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
    OSStatus status = AudioQueuePause(_audioQueue);
    if (status != noErr) {
        NSLog(@"pause error:%d",status);
        return NO;
    }
    _status = kPlayPauseStatus;
    return YES;
}

- (BOOL)reset
{
    OSStatus status = AudioQueueReset(_audioQueue);
    if (status != noErr) {
        NSLog(@"AudioQueueReset error:%d",status);
        return NO;
    }
    _status = kPlayStopStatus;
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
    OSStatus status = AudioQueueStop(_audioQueue, immediately);
    if (status != noErr) {
        NSLog(@"AudioQueueStop error:%d",status);
        return NO;
    }
    _status = kPlayStopStatus;
    return YES;
}

- (BOOL)playData:(RetainBuffer*)bufferData packetCount:(UInt32)packetCount packetDescriptions:(const AudioStreamPacketDescription *)packetDescriptions isEof:(BOOL)isEof{
    if (_status != kPlayRunningStatus)
    {
        return NO;
    }
    retainBufferRetain(bufferData);
    if (_format.mFormatID == kAudioFormatLinearPCM) {
        queuePush(_reusableQueue, bufferData, 1000);
    }else if (_format.mFormatID == kAudioFormatMPEG4AAC){
        AACRetainBuffer* buffer = new AACRetainBuffer;
        buffer->bufferData = bufferData;
        buffer->packetCount = packetCount;
        buffer->packetDescriptions = (AudioStreamPacketDescription*)malloc(packetCount*sizeof(AudioStreamPacketDescription));
        memcpy(buffer->packetDescriptions, packetDescriptions, packetCount*sizeof(AudioStreamPacketDescription));
        queuePush(_reusableQueue, buffer, 1000);
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
    RetainBuffer* bufferData;
    if(queuePop(player->_reusableQueue, (void**)bufferData, 0)){
         memcpy(inBuffer->mAudioData, bufferData->data, bufferData->size);
        inBuffer->mAudioDataByteSize = bufferData->size;
        retainBufferUnRetain(bufferData);
    }else{
        if (player.status != kPlayRunningStatus) {
            return;
        }
        inBuffer->mAudioDataByteSize = 0;
    }
    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
#ifdef DEBUG
    if (status < 0) {
        NSLog(@"AudioQueueEnqueueBuffer error:%d",status);
    }
#endif
}
static void aacAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer){
    GJAudioQueuePlayer *player = (__bridge GJAudioQueuePlayer *)inClientData;
    AACRetainBuffer* buffer;
    if(queuePop(player->_reusableQueue, (void**)buffer, 0)){
        memcpy(inBuffer->mAudioData, buffer->bufferData, buffer->bufferData->size);
        inBuffer->mAudioDataByteSize = buffer->bufferData->size;
        retainBufferUnRetain(buffer->bufferData);
        free(buffer);
    }else{
        if (player.status != kPlayRunningStatus) {
            return;
        }
        inBuffer->mAudioDataByteSize = 0;
    }
    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
#ifdef DEBUG
    if (status < 0) {
        NSLog(@"AudioQueueEnqueueBuffer error:%d",status);
    }
#endif

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
    queueRelease(&_reusableQueue);
    [self _disposeAudioOutputQueue];
}
@end
