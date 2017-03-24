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
#define DEFAULT_DELAY 0.1



@interface GJAudioQueueRecoder(){
   
    AudioQueueBufferRef          _mAudioBuffers[NUMBER_BUFFERS];
    dispatch_queue_t _recodeQueue;
}
@property(assign,nonatomic) AudioQueueRef mAudioQueue;
@property(assign,nonatomic) GJRetainBufferPool* bufferPool;

@end;

static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
int get_f_index(unsigned int sampling_frequency)
{
    switch (sampling_frequency)
    {
        case 96000: return 0;
        case 88200: return 1;
        case 64000: return 2;
        case 48000: return 3;
        case 44100: return 4;
        case 32000: return 5;
        case 24000: return 6;
        case 22050: return 7;
        case 16000: return 8;
        case 12000: return 9;
        case 11025: return 10;
        case 8000:  return 11;
        case 7350:  return 12;
        default:    return 0;
    }
}
static void adtsDataForPacketLength(int packetLength, uint8_t*packet,int sampleRate, int channel)
{
    /*=======adts=======
     7字节
     {
     syncword -------12 bit
     ID              -------  1 bit
     layer         -------  2 bit
     protection_absent - 1 bit
     profile       -------  2 bit
     sampling_frequency_index ------- 4 bit
     private_bit ------- 1 bit
     channel_configuration ------- 3bit
     original_copy -------1bit
     home ------- 1bit
     }
     
     */
    int adtsLength = 7;
    //profile：表示使用哪个级别的AAC，有些芯片只支持AAC LC 。在MPEG-2 AAC中定义了3种：
    /*
     0-------Main profile
     1-------LC
     2-------SSR
     3-------保留
     */
    int profile = 0;
 
    int freqIdx = get_f_index(sampleRate);//11
    /*
     channel_configuration: 表示声道数
     0: Defined in AOT Specifc Config
     1: 1 channel: front-center
     2: 2 channels: front-left, front-right
     3: 3 channels: front-center, front-left, front-right
     4: 4 channels: front-center, front-left, front-right, back-center
     5: 5 channels: front-center, front-left, front-right, back-left, back-right
     6: 6 channels: front-center, front-left, front-right, back-left, back-right, LFE-channel
     7: 8 channels: front-center, front-left, front-right, side-left, side-right, back-left, back-right, LFE-channel
     8-15: Reserved
     */
    int chanCfg = channel;
    NSUInteger fullLength = adtsLength + packetLength;
    packet[0] = (char)0xFF;	// 11111111  	= syncword
    packet[1] = (char)0xF1;	   // 1111 0 00 1 = syncword+id(MPEG-4) + Layer + absent

    packet[2] = (char)(((profile)<<6) + (freqIdx<<2) +(chanCfg>>2));// profile(2)+sampling(4)+privatebit(1)+channel_config(1)
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
}
static void handleInputBuffer (void *aqData, AudioQueueRef inAQ,AudioQueueBufferRef inBuffer,const AudioTimeStamp *inStartTime,UInt32 inNumPackets, const AudioStreamPacketDescription  *inPacketDesc){
    GJAudioQueueRecoder* tempSelf = (__bridge GJAudioQueueRecoder*)aqData;
   
    if (tempSelf.status == kRecoderRunningStatus){
        GJRetainBuffer* buffer = GJRetainBufferPoolGetData(tempSelf.bufferPool);
        int offset = 0;
        if (tempSelf.format.mFormatID == kAudioFormatMPEG4AAC) {
            offset = 7;
            adtsDataForPacketLength(inBuffer->mAudioDataByteSize, buffer->data,tempSelf.format.mSampleRate,tempSelf.format.mChannelsPerFrame);

        }
        memcpy(buffer->data+offset, inBuffer->mAudioData, inBuffer->mAudioDataByteSize+offset);
        buffer->size = inBuffer->mAudioDataByteSize+offset;
        int pts = inStartTime->mSampleTime*1000/ tempSelf.format.mSampleRate;
//        static int count ;
//        NSLog(@"send num:%d:%@",count++,[NSData dataWithBytes:buffer->data+7 length:buffer->size-7]);
        NSLog(@"audio size:%d",inBuffer->mAudioDataByteSize);
        AudioStreamPacketDescription desc = (AudioStreamPacketDescription){7,0,inBuffer->mAudioDataByteSize+7};
        [tempSelf.delegate GJAudioQueueRecoder:tempSelf streamData:buffer packetDescriptions:&desc pts:pts];
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
        if (![[NSThread currentThread]isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self _initWithSampleRate:sampleRate channel:channel formatID:formatID];
            });
        }else{
            [self _initWithSampleRate:sampleRate channel:channel formatID:formatID];
        }
    }
    
    return self;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        if (![[NSThread currentThread]isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self _initWithSampleRate:44100 channel:2 formatID:kAudioFormatLinearPCM];
            });
        }else{
            [self _initWithSampleRate:44100 channel:2 formatID:kAudioFormatLinearPCM];
        }
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
            maxPacketSize = maxPacketSize*1.0/_format.mFramesPerPacket*_format.mSampleRate*0.5+7;
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
