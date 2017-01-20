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
#define NUMBER_BUFFERS 8

#define DEFAULT_MAX_SIZE 1024


@interface GJAudioQueueRecoder(){
   
    AudioQueueBufferRef          _mAudioBuffers[NUMBER_BUFFERS];
}
@property(assign,nonatomic) AudioQueueRef mAudioQueue;
@end;



static void handleInputBuffer (void *aqData, AudioQueueRef inAQ,AudioQueueBufferRef inBuffer,const AudioTimeStamp *inStartTime,UInt32 inNumPackets, const AudioStreamPacketDescription  *inPacketDesc){
    GJAudioQueueRecoder* tempSelf = (__bridge GJAudioQueueRecoder*)aqData;
//    static int times;
//    NSData* data = [NSData dataWithBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
//    NSLog(@"recoder audio times:%d data:%@",times++,data);
    AudioQueueEnqueueBuffer (tempSelf.mAudioQueue,inBuffer,0,NULL);

    return;
    
    if (tempSelf.status == kRecoderRunningStatus){
        RetainBuffer* buffer = retainBufferAlloc(inBuffer->mAudioDataByteSize, NULL, NULL);
        memcpy(buffer->data, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        [tempSelf.delegate GJAudioQueueRecoder:tempSelf streamData:buffer packetCount:inNumPackets packetDescriptions:inPacketDesc];
        AudioQueueEnqueueBuffer (tempSelf.mAudioQueue,inBuffer,0,NULL);
    }else{
        static int count;
        NSLog(@"count:%d",count++);
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
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &format);
    _format = format;
    
    OSStatus status = AudioQueueNewInput ( &format, handleInputBuffer, (__bridge void * _Nullable)(self),  NULL, 0, 0, &_mAudioQueue);
    if (status != 0) {
        NSLog(@"AudioQueueNewInput error:%d",status);
        char *formatName = (char *)&(status);
        NSLog(@"format is: %c%c%c%c     -----------", formatName[3], formatName[2], formatName[1], formatName[0]);
        _mAudioQueue = NULL;
        return NO;
    }
    UInt32 maxPacketSize = 0;
    if (format.mFormatID == kAudioFormatLinearPCM) {
        maxPacketSize = DEFAULT_MAX_SIZE;// * format.mBytesPerFrame*format.mFramesPerPacket;///
    }else{
        UInt32 parmSize = sizeof(maxPacketSize);
        status = AudioQueueGetProperty (_mAudioQueue,kAudioQueueProperty_MaximumOutputPacketSize,&maxPacketSize,&parmSize);
        if (status < 0) {
            maxPacketSize = DEFAULT_MAX_SIZE;
        }
    }

    _maxOutSize = maxPacketSize;
    
    _status = kRecoderStopStatus;
    return YES;
}

-(BOOL)startRecodeAudio{
    //    BOOL isHead = NO;
    //    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    //    for (AVAudioSessionPortDescription* desc in [route outputs]) {
    //        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
    //            isHead = YES;
    //    }
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
