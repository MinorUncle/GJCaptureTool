//
//  GJAudioQueueDrivePlayer.m
//  GJCaptureTool
//
//  Created by mac on 17/3/9.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJAudioQueueDrivePlayer.h"
#import "GJLog.h"
#define DEFALUT_BUFFER_COUNT 8

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
        _cacheBufferCount = DEFALUT_BUFFER_COUNT;
        _format = format;
        _maxBufferSize = maxBufferSize;
        _speed = 1.0;
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
    GJLOG(GJ_LOGINFO,"GJAudioQueueDrivePlayer format is: %c%c%c%c     -----------", formatName[3], formatName[2], formatName[1], formatName[0]);
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
        GJLOG(GJ_LOGINFO,"kAudioQueueProperty_MagicCookie status:%d",status);
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
    if (_status != kPlayARunningStatus) {
        _status = kPlayARunningStatus;

        if (_format.mFormatID == kAudioFormatLinearPCM) {
            for (int i = 0; i < _cacheBufferCount-1; ++i)
            {
                AudioQueueBufferRef buffer;
                OSStatus status = AudioQueueAllocateBuffer(_audioQueue, _maxBufferSize, &buffer);
                buffer->mAudioDataByteSize = _maxBufferSize;
                memset(buffer->mAudioData, 0, buffer->mAudioDataByteSize);
                status = AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
                if (status != noErr)
                {
                    _status = kPlayAStopStatus;

                    AudioQueueDispose(_audioQueue, YES);
                    _audioQueue = NULL;
                    GJLOG(GJ_LOGERROR,"AudioQueueAllocateBuffer faile");
                    assert(!status);
                    return false;
                }
            }
        }else{
            for (int i = 0; i < _cacheBufferCount-1; ++i)
            {
                AudioQueueBufferRef buffer;
                OSStatus status = AudioQueueAllocateBuffer(_audioQueue, _maxBufferSize, &buffer);
                int size;
                if([self.delegate GJAudioQueueDrivePlayer:self outAudioData:buffer->mAudioData outSize:&size]){
                    buffer->mAudioDataByteSize = size;
                }else{
                    _status = kPlayAStopStatus;
                    GJLOG(GJ_LOGERROR,"audio player get aac faile");
                };
                status = AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
                if (status != noErr)
                {
                    _status = kPlayAStopStatus;

                    AudioQueueDispose(_audioQueue, YES);
                    _audioQueue = NULL;
                    GJLOG(GJ_LOGERROR,"AudioQueueAllocateBuffer faile");
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
            _status = kPlayAStopStatus;
            AudioQueueDispose(_audioQueue, false);
            GJLOG(GJ_LOGERROR,"播放失败 Error：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
            return NO;
        }
    }

    return YES;
}

- (BOOL)resume
{
    OSStatus status = AudioQueueStart(_audioQueue, NULL);
    if (status != 0) {
        char* codeChar = (char*)&status;
        GJLOG(GJ_LOGERROR,"AudioQueueStartError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
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
        GJLOG(GJ_LOGERROR,"pause error:%d",status);
        return NO;
    }
    return YES;
}

- (BOOL)reset
{
    OSStatus status = AudioQueueReset(_audioQueue);
    if (status != noErr) {
        GJLOG(GJ_LOGERROR,"AudioQueueReset error:%d",status);
        return NO;
    }
    return YES;
}

- (BOOL)flush
{
    OSStatus status = AudioQueueFlush(_audioQueue);
    if (status != noErr) {
        GJLOG(GJ_LOGERROR,"AudioQueueFlush error:%d",status);
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
        GJLOG(GJ_LOGERROR,"AudioQueueStop error:%d",status);
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
-(void)setSpeed:(float)speed{
    if (speed > 2.0) {
        speed = 2.0;
    }else if (speed < 0.5){
        speed = 0.5;
    }
    NSError* error;
    [self setParameter:kAudioQueueParam_PlayRate value:speed error:&error];
    if (error) {
        GJLOG(GJ_LOGERROR, "audio speed set error:%d",error.code);
    }else{
        _speed = speed;
    }
}



#pragma mark - call back
static void pcmAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *)inClientData;
    int dataSize;
    if([player.delegate GJAudioQueueDrivePlayer:player outAudioData:inBuffer->mAudioData outSize:&dataSize]
       && player.status == kPlayARunningStatus){
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
        GJLOG(GJ_LOGERROR,"AudioQueueEnqueueBuffer error:%d",(int)status);
    }
#endif
}
static void aacAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer){
    static int count;
    NSLog(@"aac buffer out:%d",count++);
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *)inClientData;
    int dataSize;
    if([player.delegate GJAudioQueueDrivePlayer:player outAudioData:inBuffer->mAudioData outSize:&dataSize]
       && player.status == kPlayARunningStatus){
        inBuffer->mAudioDataByteSize = dataSize;

    }else{
        
        if (player.status != kPlayARunningStatus) {
            
#ifdef DEBUG
            static int freeCount;
            GJLOG(GJ_LOGDEBUG,"AudioQueueEnqueueBuffer frees:%d",freeCount);

#endif
            AudioQueueFreeBuffer(inAQ, inBuffer);
            return;
        }
    }
    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    if (status < 0) {
        AudioQueueFreeBuffer(inAQ, inBuffer);
        GJLOG(GJ_LOGERROR,"AudioQueueEnqueueBuffer error:%d",(int)status);
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
            GJLOG(GJ_LOGWARNING,"warnning ...... auto start");
        }
    }
}



- (void)dealloc
{
    [self _disposeAudioOutputQueue];
}
@end
