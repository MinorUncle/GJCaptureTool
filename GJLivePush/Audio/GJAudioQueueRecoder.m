//
//  GJAudioQueueRecoder.m
//  GJCaptureTool
//
//  Created by mac on 17/1/19.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJAudioQueueRecoder.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "GJRetainBufferPool.h"

#define NUMBER_BUFFERS 8

#define DEFAULT_MAX_SIZE 2048
#define DEFAULT_DELAY 0.05



@interface GJAudioQueueRecoder(){
   
    AudioQueueBufferRef          _mAudioBuffers[NUMBER_BUFFERS];
    dispatch_queue_t _recodeQueue;
}
@property(assign,nonatomic) AudioQueueRef mAudioQueue;
@property(assign,nonatomic) GJRetainBufferPool* bufferPool;

@end;



static void handleInputBuffer (void *aqData, AudioQueueRef inAQ,AudioQueueBufferRef inBuffer,const AudioTimeStamp *inStartTime,UInt32 inNumPackets, const AudioStreamPacketDescription  *inPacketDesc){
    GJAudioQueueRecoder* tempSelf = (__bridge GJAudioQueueRecoder*)aqData;
   
    if (tempSelf.status == kRecoderRunningStatus){
        GJRetainBuffer* buffer = GJRetainBufferPoolGetData(tempSelf.bufferPool);
        memcpy(buffer->data, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        NSData* data = [NSData dataWithBytes:buffer->data length:buffer->size];
        static int times = 0;
        NSLog(@"times:%d,lenth:%ld,data:%@",times++,data.length,data);
        [tempSelf.delegate GJAudioQueueRecoder:tempSelf streamData:buffer packetDescriptions:inPacketDesc];
        retainBufferUnRetain(buffer);
        AudioQueueEnqueueBuffer (tempSelf.mAudioQueue,inBuffer,0,NULL);
    }else{
        AudioQueueFreeBuffer(inAQ, inBuffer);
    }
};


@implementation GJAudioQueueRecoder
- (instancetype)initWithStreamWithSampleRate:(Float64)sampleRate channel:(UInt32)channel formatID:(UInt32)formatID{
    self = [super init];
    if (self) {
        [self _initWithSampleRate:sampleRate channel:channel formatID:formatID];
    }
    
    return self;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        [self _initWithSampleRate:44100 channel:2 formatID:kAudioFormatLinearPCM];
    }
    return self;
}
-(BOOL)_initWithSampleRate:(Float64)sampleRate channel:(UInt32)channel formatID:(UInt32)formatID{
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
    OSStatus status  = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &format);
    _format = format;
    _recodeQueue = dispatch_queue_create("recodequeue", DISPATCH_QUEUE_SERIAL);
    _callbackDelay = DEFAULT_DELAY;
    status = AudioQueueNewInput ( &format, handleInputBuffer, (__bridge void * _Nullable)(self),  NULL, 0, 0, &_mAudioQueue);
    if (status != 0) {
#ifdef DEBUG
        NSLog(@"AudioQueueNewInput error:%d",status);
        char *formatName = (char *)&(status);
        NSLog(@"error is: %c%c%c%c     -----------", formatName[3], formatName[2], formatName[1], formatName[0]);
#endif
        _mAudioQueue = NULL;
        
        return NO;
    }
    UInt32 maxPacketSize = 0;
    if (format.mFormatID == kAudioFormatLinearPCM) {
        maxPacketSize = _format.mBytesPerFrame * _format.mSampleRate * _callbackDelay;//
    }else{
        UInt32 parmSize = sizeof(maxPacketSize);
        status = AudioQueueGetProperty (_mAudioQueue,kAudioQueueProperty_MaximumOutputPacketSize,&maxPacketSize,&parmSize);
        if (status < 0) {
            maxPacketSize = _format.mChannelsPerFrame*_format.mFramesPerPacket*2;
        }else{
            maxPacketSize = maxPacketSize*1.0/_format.mFramesPerPacket*_format.mSampleRate*0.5;
        }
    }
    
    GJRetainBufferPoolCreate(&_bufferPool, maxPacketSize,true);
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(receiveNotification:) name:AVAudioSessionInterruptionNotification object:nil];

    _maxOutSize = maxPacketSize;
    _status = kRecoderStopStatus;
    return YES;
}
-(void)receiveNotification:(NSNotification*)notifica{
    
    NSLog(@"noti:%@",notifica);
    
    if ([notifica.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        AVAudioSessionInterruptionType type = [notifica.userInfo[AVAudioSessionInterruptionTypeKey] longValue];
        AVAudioSessionInterruptionOptions options = [notifica.userInfo[AVAudioSessionInterruptionOptionKey] longValue];
        
        if (type == AVAudioSessionInterruptionTypeEnded&& options == AVAudioSessionInterruptionOptionShouldResume && self.status == kRecoderRunningStatus) {
            [self reStart];
        }
    }
    
}
-(void)reStart{
    _status = kRecoderStopStatus;
    AudioQueueReset(_mAudioQueue);
    [self startRecodeAudio];
}
-(BOOL)startRecodeAudio{

    if (_status == kRecoderRunningStatus || _status == kRecoderInvalidStatus) {
        return NO;
    }
    NSError* error;
    [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    [[AVAudioSession sharedInstance]overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker  error:NULL];
    if (error) {
        NSLog(@"setCategory error:%@",error);
    }
    [[AVAudioSession sharedInstance]setActive:YES error:&error];
    if (error) {
        NSLog(@"setActive error:%@",error);
    }
    NSArray<AVAudioSessionPortDescription*>* inputs = [AVAudioSession sharedInstance].availableInputs;
    for (AVAudioSessionPortDescription* input in inputs) {//设置非内置麦克风
        if (![input.portType isEqualToString:AVAudioSessionPortBuiltInMic]) {
            [[AVAudioSession sharedInstance]setPreferredInput:input error:NULL];
            break;
        }
    }
    
    for (int i = 0; i < NUMBER_BUFFERS; ++i) {           // 1
        OSStatus  status = AudioQueueAllocateBuffer (_mAudioQueue,_maxOutSize,&_mAudioBuffers[i]);
        if (status < 0) {
            NSLog(@"AudioQueueAllocateBuffer error:%d",status);
            return NO;
        }
        status = AudioQueueEnqueueBuffer (_mAudioQueue,_mAudioBuffers[i],0,NULL);
        if (status < 0) {
            NSLog(@"AudioQueueEnqueueBuffer error:%d",status);
            return NO;
        }
    }

    
    OSStatus status = AudioQueueStart(_mAudioQueue,NULL);
    if (status < 0) {
        NSLog(@"start error:%d",status);
        return NO;
    }else{
        _status = kRecoderRunningStatus;
        return YES;
    }
};
-(void)stop{
    if (_status == kRecoderRunningStatus) {
        _status = kRecoderStopStatus;
        AudioQueueStop(_mAudioQueue,true);
        
    }
}
-(void)pause{
    if (_status == kRecoderRunningStatus) {
        _status = kRecoderPauseStatus;
        AudioQueuePause(_mAudioQueue);
    }
}
-(void)dealloc{
    AudioQueueDispose(_mAudioQueue, true);

}
@end
