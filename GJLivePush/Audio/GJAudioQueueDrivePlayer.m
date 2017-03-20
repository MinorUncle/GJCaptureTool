//
//  GJAudioQueueDrivePlayer.m
//  GJCaptureTool
//
//  Created by mac on 17/3/9.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJAudioQueueDrivePlayer.h"
static const int MCAudioQueueBufferCount = 8;

@interface GJAudioQueueDrivePlayer()
{
    AudioQueueRef _audioQueue;

}
@end
@implementation GJAudioQueueDrivePlayer
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
 
    AudioStreamBasicDescription format = {0};
    format.mFormatID         = formatID;
    UInt32 maxBufferSize = 0;
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
            maxBufferSize = format.mFramesPerPacket*format.mBytesPerFrame;
            break;
        }
        case kAudioFormatMPEG4AAC:
        {
            format.mSampleRate       = sampleRate;               // 3
            format.mFormatID         = kAudioFormatMPEG4AAC; // 2
            format.mChannelsPerFrame = channel;                     // 4
            format.mFramesPerPacket  = 1024;
            maxBufferSize = format.mFramesPerPacket*channel*4;
            break;
        }
        default:
            break;
    }
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &format);

    self = [self initWithFormat:format maxBufferSize:maxBufferSize macgicCookie:nil];
    return self;
}

-(void)_init{
    _volume = 1.0f;
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
        NSLog(@"kAudioQueueProperty_MagicCookie status:%d",status);
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
    if (_format.mFormatID == kAudioFormatLinearPCM) {
        for (int i = 0; i < MCAudioQueueBufferCount-1; ++i)
        {
            AudioQueueBufferRef buffer;
            OSStatus status = AudioQueueAllocateBuffer(_audioQueue, _maxBufferSize, &buffer);
            buffer->mAudioDataByteSize = _maxBufferSize;
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
    }else{
        for (int i = 0; i < MCAudioQueueBufferCount-1; ++i)
        {
            AudioQueueBufferRef buffer;
            OSStatus status = AudioQueueAllocateBuffer(_audioQueue, _maxBufferSize, &buffer);
            void* data;
            int size;
            if([self.delegate GJAudioQueueDrivePlayer:self outAudioData:&data outSize:&size]){
                buffer->mAudioDataByteSize = size;
                memcpy(buffer->mAudioData, data, size);
            }else{
                buffer->mAudioDataByteSize = _maxBufferSize;
                memset(buffer->mAudioData, 0, _maxBufferSize);
            };
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
    
//    UInt32 isRunning = 0;
//    UInt32 size = sizeof(isRunning);
//    AudioQueueGetProperty(_audioQueue, kAudioQueueProperty_IsRunning, &isRunning, &size);
    
    _status = kPlayARunningStatus;
    //    assert(!status);
    return YES;
}

- (BOOL)resume
{
    OSStatus status = AudioQueueStart(_audioQueue, NULL);
    if (status != 0) {
        char* codeChar = (char*)&status;
        NSLog(@"AudioQueueStartError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
        NSLog(@"播放失败");
        return NO;
    }
    _status = kPlayARunningStatus;
    return YES;
}

- (BOOL)pause
{
    _status = kPlayAPauseStatus;
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
    _status = kPlayAStopStatus;
    OSStatus status = AudioQueueStop(_audioQueue, immediately);
    if (status != noErr) {
        NSLog(@"AudioQueueStop error:%d",status);
        _status = pre;
        
        return NO;
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
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *)inClientData;
    void* data;
    int dataSize;
    if([player.delegate GJAudioQueueDrivePlayer:player outAudioData:&data outSize:&dataSize]
       && player.status == kPlayARunningStatus){
        memcpy(inBuffer->mAudioData, data, dataSize);
        inBuffer->mAudioDataByteSize = dataSize;
    }else{
        if (player.status != kPlayARunningStatus) {
            AudioQueueFreeBuffer(inAQ, inBuffer);
            return;
        }
        memset(inBuffer->mAudioData, 0, inBuffer->mAudioDataByteSize);
    }
    
    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
#ifdef DEBUG
    if (status < 0) {
        NSLog(@"AudioQueueEnqueueBuffer error:%d",(int)status);
    }
#endif
}
static void aacAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer){
    static int count;
    NSLog(@"aac buffer out:%d",count++);
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *)inClientData;
    void* data;
    int dataSize;
    if([player.delegate GJAudioQueueDrivePlayer:player outAudioData:&data outSize:&dataSize]
       && player.status == kPlayARunningStatus){
        memcpy(inBuffer->mAudioData, data, dataSize);
        inBuffer->mAudioDataByteSize = dataSize;

    }else{
        
        if (player.status != kPlayARunningStatus) {
            AudioQueueFreeBuffer(inAQ, inBuffer);
            return;
        }
        inBuffer->mAudioDataByteSize = 0;
        NSLog(@"play out00000000000000:%d",count);
    }
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
    [self _disposeAudioOutputQueue];
}
@end
