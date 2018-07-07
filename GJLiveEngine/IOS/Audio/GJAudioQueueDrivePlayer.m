//
//  GJAudioQueueDrivePlayer.m
//  GJCaptureTool
//
//  Created by mac on 17/3/9.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJAudioQueueDrivePlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "GJLog.h"
#import "GJQueue.h"
#define DEFALUT_BUFFER_COUNT 3
#define DEFALUT_SAMPLE_COUNT 1024

@interface GJAudioQueueDrivePlayer () {
    AudioQueueRef _audioQueue;
}
@end
@implementation GJAudioQueueDrivePlayer
@synthesize     format = _format;
@dynamic        available;
@synthesize     volume        = _volume;
@synthesize     maxBufferSize = _maxBufferSize;

#pragma mark - init & dealloc
- (instancetype)initWithFormat:(AudioStreamBasicDescription)format maxBufferSize:(UInt32)maxBufferSize macgicCookie:(NSData *)macgicCookie {
    self = [super init];
    if (self) {
        _cacheBufferCount = DEFALUT_BUFFER_COUNT;
        _format           = format;
        _maxBufferSize    = maxBufferSize;
        _speed            = 1.0;
        [self _init];
        [self _createAudioOutputQueue:macgicCookie];

        //        if (![[NSThread currentThread] isMainThread]) {
        //            dispatch_sync(dispatch_get_main_queue(), ^{
        //                [self _createAudioOutputQueue:macgicCookie];
        //            });
        //        } else {
        //            [self _createAudioOutputQueue:macgicCookie];
        //        }
    }
    return self;
}
- (instancetype)initWithSampleRate:(Float64)sampleRate channel:(UInt32)channel formatID:(UInt32)formatID {

    AudioStreamBasicDescription format = {0};
    format.mFormatID                   = formatID;
    UInt32 maxBufferSize               = 0;
    switch (formatID) {
        case kAudioFormatLinearPCM: {
            format.mSampleRate       = sampleRate; // 3
            format.mChannelsPerFrame = channel;    // 4
            format.mFramesPerPacket  = 1;          // 7
            format.mBitsPerChannel   = 16;         // 5
            format.mBytesPerFrame    = format.mChannelsPerFrame * format.mBitsPerChannel / 8;
            format.mBytesPerPacket   = format.mBytesPerFrame * format.mFramesPerPacket;
            format.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
            maxBufferSize            = format.mBytesPerFrame * DEFALUT_SAMPLE_COUNT;
            break;
        }
        case kAudioFormatMPEG4AAC: {
            format.mSampleRate       = sampleRate;           // 3
            format.mFormatID         = kAudioFormatMPEG4AAC; // 2
            format.mChannelsPerFrame = channel;              // 4
            format.mFramesPerPacket  = DEFALUT_SAMPLE_COUNT;
            maxBufferSize            = format.mFramesPerPacket * channel * 4;
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

- (void)_init {
    _volume = 1.0f;
    _status = kPlayStatusInvalid;
}

#pragma mark - error
- (void)_errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError

{
    if (status != noErr && outError != NULL) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}

#pragma mark - audio queue
//must main
- (void)_createAudioOutputQueue:(NSData *)magicCookie {
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_format);
#ifdef DEBUG
    char *formatName = (char *) &(_format.mFormatID);
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJAudioQueueDrivePlayer format is: %c%c%c%c     -----------", formatName[3], formatName[2], formatName[1], formatName[0]);
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
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "_createAudioOutputQueue format not support");
            return;
            break;
    }
    OSStatus status = AudioQueueNewOutput(&_format, callBack, (__bridge void *) (self), GNULL, kCFRunLoopCommonModes, 0, &_audioQueue);
    if (status != noErr) {
        _audioQueue = NULL;
        return;
    }

    status = AudioQueueAddPropertyListener(_audioQueue, kAudioQueueProperty_IsRunning, MCAudioQueuePropertyCallback, (__bridge void *) (self));
    assert(!status);
    if (status != noErr) {
        AudioQueueDispose(_audioQueue, YES);
        _audioQueue = NULL;
        return;
    }

#if TARGET_OS_IPHONE
    UInt32 property = kAudioQueueHardwareCodecPolicy_PreferSoftware;
    [self setProperty:kAudioQueueProperty_HardwareCodecPolicy dataSize:sizeof(property) data:&property error:NULL];
#endif

    if (magicCookie) {
        status = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, [magicCookie bytes], (UInt32)[magicCookie length]);
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "kAudioQueueProperty_MagicCookie status:%d", status);
    }

    UInt32 propValue = 1;
    AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_EnableTimePitch, &propValue, sizeof(propValue));
    propValue = 1;
    AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_TimePitchBypass, &propValue, sizeof(propValue));
    propValue = kAudioQueueTimePitchAlgorithm_Spectral;
    AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_TimePitchAlgorithm, &propValue, sizeof(propValue));

    _status     = kPlayStatusStop;
    self.volume = 1.0;
    self.speed  = 1.0;
}

- (void)_disposeAudioOutputQueue {
    if (_audioQueue != NULL) {
        AudioQueueDispose(_audioQueue, true);
        _audioQueue = NULL;
    }
}

- (BOOL)start {
    //    if (![NSThread isMainThread]) {
    //        dispatch_async(dispatch_get_main_queue(), ^{
    //            [self start];
    //        });
    //        return YES;
    //    }
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "AudioQueueStart");
    if (_status != kPlayStatusRunning) {
        _status = kPlayStatusRunning;

        if (_format.mFormatID == kAudioFormatLinearPCM) {
            for (int i = 0; i < _cacheBufferCount - 1; ++i) {
                AudioQueueBufferRef buffer;
                OSStatus            status = AudioQueueAllocateBuffer(_audioQueue, _maxBufferSize, &buffer);
                buffer->mAudioDataByteSize = _format.mBytesPerFrame * DEFALUT_SAMPLE_COUNT;
                memset(buffer->mAudioData, 0, buffer->mAudioDataByteSize);
                status = AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
                if (status != noErr) {
                    _status = kPlayStatusStop;
                    AudioQueueDispose(_audioQueue, YES);
                    _audioQueue = NULL;
                    GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueAllocateBuffer faile");
                    assert(!status);
                    return false;
                }
            }
        } else {
            for (int i = 0; i < _cacheBufferCount - 1; ++i) {
                AudioQueueBufferRef buffer;
                OSStatus            status = AudioQueueAllocateBuffer(_audioQueue, _maxBufferSize, &buffer);
                int                 size;

                if (self.fillDataCallback(buffer->mAudioData, &size)) {
                    buffer->mAudioDataByteSize = size;
                } else {
                    _status = kPlayStatusStop;
                    GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "audio player get aac faile");
                    return NO;
                };
                AudioStreamPacketDescription packet = {0};
                packet.mDataByteSize                = buffer->mAudioDataByteSize;
                packet.mStartOffset                 = 0;
                packet.mVariableFramesInPacket      = 0;

                status = AudioQueueEnqueueBuffer(_audioQueue, buffer, 1, &packet);
                if (status != noErr) {
                    _status = kPlayStatusStop;
                    AudioQueueDispose(_audioQueue, YES);
                    _audioQueue = NULL;
                    GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueAllocateBuffer faile");
                    assert(!status);
                    return false;
                }
            }
        }
        //        UInt32 numPrepared = 0;
        //        OSStatus status = AudioQueuePrime(_audioQueue, 0, &numPrepared);
        OSStatus status = AudioQueueStart(_audioQueue, NULL);
        if (status != 0) {
            char *codeChar = (char *) &status;
            _status        = kPlayStatusStop;
            AudioQueueDispose(_audioQueue, false);
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "播放失败 Error：%c%c%c%c CODE:%d", codeChar[3], codeChar[2], codeChar[1], codeChar[0], status);
            return NO;
        }
    }
    return YES;
}

- (BOOL)resume {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "audioplay resume");
    if (_status == kPlayStatusPause) {
        _status         = kPlayStatusRunning;
        OSStatus status = AudioQueueStart(_audioQueue, NULL);
        if (status != 0) {
            char *codeChar = (char *) &status;
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueStartError：%c%c%c%c CODE:%d", codeChar[3], codeChar[2], codeChar[1], codeChar[0], status);
            _status = kPlayStatusPause;
            return NO;
        }
    }
    return YES;
}

- (BOOL)pause {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "audioplay pause");
    if (_status != kPlayStatusPause) {
        _status         = kPlayStatusPause;
        OSStatus status = AudioQueuePause(_audioQueue);
        if (status != noErr) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "pause error:%d", status);
            return NO;
        }
    }
    return YES;
}

- (BOOL)reset {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "AudioQueuereset");
    OSStatus status = AudioQueueReset(_audioQueue);
    if (status != noErr) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueReset error:%d", status);
        return NO;
    }
    return YES;
}

- (BOOL)flush {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "AudioQueueFlush");
    OSStatus status = AudioQueueFlush(_audioQueue);
    if (status != noErr) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueFlush error:%d", status);
        return NO;
    }
    return YES;
}

- (BOOL)stop:(BOOL)immediately {
    //    if (![NSThread isMainThread]) {
    //        if (immediately) {
    //            dispatch_sync(dispatch_get_main_queue(), ^{
    //                [self stop:immediately];
    //            });
    //        }else{
    //            dispatch_async(dispatch_get_main_queue(), ^{
    //                [self stop:immediately];
    //            });
    //        }
    //        return YES;
    //    }
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "AudioQueuestop");

    GJPlayStatus pre = _status; //防止监听部分重启
    _status          = kPlayStatusStop;
    OSStatus status  = AudioQueueStop(_audioQueue, immediately);
    if (status != noErr) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueStop error:%d", status);
        _status = pre;

        return NO;
    }
    return YES;
}

- (BOOL)setProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError *__autoreleasing *)outError {
    OSStatus status = AudioQueueSetProperty(_audioQueue, propertyID, data, dataSize);
    [self _errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)getProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32 *)dataSize data:(void *)data error:(NSError *__autoreleasing *)outError {
    OSStatus status = AudioQueueGetProperty(_audioQueue, propertyID, data, dataSize);
    [self _errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)setParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue)value error:(NSError *__autoreleasing *)outError {
    OSStatus status = AudioQueueSetParameter(_audioQueue, parameterId, value);
    [self _errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)getParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue *)value error:(NSError *__autoreleasing *)outError {
    OSStatus status = AudioQueueGetParameter(_audioQueue, parameterId, value);
    [self _errorForOSStatus:status error:outError];
    return status == noErr;
}

#pragma mark - property

- (BOOL)available {
    return _audioQueue != NULL;
}

- (void)setVolume:(float)volume {
    _volume = volume;
    [self setParameter:kAudioQueueParam_Volume value:_volume error:NULL];
}

- (void)setSpeed:(float)speed {
    //    return;
    if (speed > 2.0) {
        speed = 2.0;
    } else if (speed < 0.5) {
        speed = 0.5;
    }
    OSStatus error;
    if (fabsf(speed - 1.0f) <= 0.000001) {
        UInt32 propValue = 1;
        error            = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_TimePitchBypass, &propValue, sizeof(propValue));
        error            = AudioQueueSetParameter(_audioQueue, kAudioQueueParam_PlayRate, 1.0f);
    } else {
        UInt32 propValue = 0;
        error            = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_TimePitchBypass, &propValue, sizeof(propValue));
        error            = AudioQueueSetParameter(_audioQueue, kAudioQueueParam_PlayRate, speed);
    }
    if (error != noErr) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "audio speed set error:%d", error);
    } else {
        _speed = speed;
    }
}

#pragma mark - call back
static void pcmAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {

    GJAudioQueueDrivePlayer *player   = (__bridge GJAudioQueueDrivePlayer *) inClientData;
    int                      dataSize = inBuffer->mAudioDataByteSize;

    if (player.fillDataCallback(inBuffer->mAudioData, &dataSize)) {
        inBuffer->mAudioDataByteSize = dataSize;
    } else {
        inBuffer->mAudioDataByteSize = player.format.mBytesPerFrame * DEFALUT_SAMPLE_COUNT;
        memset(inBuffer->mAudioData, 0, inBuffer->mAudioDataByteSize);
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "play silence audio");
    }
    if (player.status == kPlayStatusStop) {
        AudioQueueFreeBuffer(inAQ, inBuffer);
        return;
    }
    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    if (status < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueEnqueueBuffer error:%d", (int) status);
        AudioQueueFreeBuffer(inAQ, inBuffer);
    }
}
static void aacAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
    static int               count;
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *) inClientData;
    NSLog(@"aac buffer out:%d  status:%d", count++, player.status);

    int dataSize = 0;

    if (player.status == kPlayStatusRunning && player.fillDataCallback(inBuffer->mAudioData, &dataSize)) {
        inBuffer->mAudioDataByteSize = dataSize;
    } else {

        if (player.status == kPlayStatusStop) {

            AudioQueueFreeBuffer(inAQ, inBuffer);
            return;
        }
    }
    AudioStreamPacketDescription packet = {0};
    packet.mDataByteSize                = inBuffer->mAudioDataByteSize;
    packet.mStartOffset                 = 0;
    packet.mVariableFramesInPacket      = 0;
    OSStatus status                     = AudioQueueEnqueueBuffer(inAQ, inBuffer, 1, &packet);
    if (status < 0) {
        AudioQueueFreeBuffer(inAQ, inBuffer);
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueEnqueueBuffer error:%d", (int) status);
    }
}

static void MCAudioQueuePropertyCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID) {
    GJAudioQueuePlayer *player = (__bridge GJAudioQueuePlayer *) inUserData;
    if (inID == kAudioQueueProperty_IsRunning) {
        UInt32 isRunning = 0;
        UInt32 size      = sizeof(isRunning);
        AudioQueueGetProperty(inAQ, inID, &isRunning, &size);
        if (player.status == kPlayStatusRunning && !isRunning) {
            [player start];
            GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "warnning ...... auto start");
        }
    }
}

- (void)dealloc {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJAudioQueueDrivePlayer dealloc");
    [self _disposeAudioOutputQueue];
}
@end

