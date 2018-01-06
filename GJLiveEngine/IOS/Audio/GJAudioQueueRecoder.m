//
//  GJAudioQueueRecoder.m
//  GJCaptureTool
//
//  Created by mac on 17/1/19.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJAudioQueueRecoder.h"
#import "GJLog.h"
#import "GJRetainBufferPool.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#define NUMBER_BUFFERS 4

#define DEFAULT_MAX_SIZE 2048
#define DEFAULT_DELAY 0.2

@interface GJAudioQueueRecoder () {

    AudioQueueBufferRef _mAudioBuffers[NUMBER_BUFFERS];
    dispatch_queue_t    _recodeQueue;
}
@property (assign, nonatomic) AudioQueueRef       mAudioQueue;
@property (assign, nonatomic) GJRetainBufferPool *bufferPool;

@end
;

int get_f_index(unsigned int sampling_frequency) {
    switch (sampling_frequency) {
        case 96000:
            return 0;
        case 88200:
            return 1;
        case 64000:
            return 2;
        case 48000:
            return 3;
        case 44100:
            return 4;
        case 32000:
            return 5;
        case 24000:
            return 6;
        case 22050:
            return 7;
        case 16000:
            return 8;
        case 12000:
            return 9;
        case 11025:
            return 10;
        case 8000:
            return 11;
        case 7350:
            return 12;
        default:
            return 0;
    }
}
//static void adtsDataForPacketLength(int packetLength, uint8_t *packet, int sampleRate, int channel) {
//    /*=======adts=======
//     7字节
//     {
//     syncword -------12 bit
//     ID              -------  1 bit
//     layer         -------  2 bit
//     protection_absent - 1 bit
//     profile       -------  2 bit
//     sampling_frequency_index ------- 4 bit
//     private_bit ------- 1 bit
//     channel_configuration ------- 3bit
//     original_copy -------1bit
//     home ------- 1bit
//     }
//
//     */
//    int adtsLength = 7;
//    //profile：表示使用哪个级别的AAC，有些芯片只支持AAC LC 。在MPEG-2 AAC中定义了3种：
//    /*
//     0-------Main profile
//     1-------LC
//     2-------SSR
//     3-------保留
//     */
//    int profile = 0;
//
//    int freqIdx = get_f_index(sampleRate); //11
//    /*
//     channel_configuration: 表示声道数
//     0: Defined in AOT Specifc Config
//     1: 1 channel: front-center
//     2: 2 channels: front-left, front-right
//     3: 3 channels: front-center, front-left, front-right
//     4: 4 channels: front-center, front-left, front-right, back-center
//     5: 5 channels: front-center, front-left, front-right, back-left, back-right
//     6: 6 channels: front-center, front-left, front-right, back-left, back-right, LFE-channel
//     7: 8 channels: front-center, front-left, front-right, side-left, side-right, back-left, back-right, LFE-channel
//     8-15: Reserved
//     */
//    int        chanCfg    = channel;
//    NSUInteger fullLength = adtsLength + packetLength;
//    packet[0]             = (char) 0xFF; // 11111111      = syncword
//    packet[1]             = (char) 0xF1; // 1111 0 00 1 = syncword+id(MPEG-4) + Layer + absent
//
//    packet[2] = (char) (((profile) << 6) + (freqIdx << 2) + (chanCfg >> 2)); // profile(2)+sampling(4)+privatebit(1)+channel_config(1)
//    packet[3] = (char) (((chanCfg & 3) << 6) + (fullLength >> 11));
//    packet[4] = (char) ((fullLength & 0x7FF) >> 3);
//    packet[5] = (char) (((fullLength & 7) << 5) + 0x1F);
//    packet[6] = (char) 0xFC;
//
//#if 0
//    static const int mpeg4audio_sample_rates[16] = {
//        96000, 88200, 64000, 48000, 44100, 32000,
//        24000, 22050, 16000, 12000, 11025, 8000, 7350
//    };
//    uint8_t* adts = packet;
//    uint8_t sampleIndex = adts[2] << 2;
//    sampleIndex = sampleIndex>>4;
//    int rsampleRate = mpeg4audio_sample_rates[sampleIndex];
//    uint8_t rchannel = adts[2] & 0x1 <<2;
//    rchannel += (adts[3] & 0xc0)>>6;
//    printf("samplerate:%d,channel:%d",rsampleRate,rchannel);
//
//#endif
//}

//static GBool R_BufferRelease(GJRetainBuffer* buffer){
//    GJRetainBufferPool* pool = buffer->parm;
//
//    GJBufferPoolSetData(pool, buffer->data+buffer->frontSize);
//    GJBufferPoolSetData(defauleBufferPool(), (void*)buffer);
//    return GTrue;
//}
static void pcmHandleInputBuffer(void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer, const AudioTimeStamp *inStartTime, UInt32 inNumPackets, const AudioStreamPacketDescription *inPacketDesc) {
    GJAudioQueueRecoder *tempSelf = (__bridge GJAudioQueueRecoder *) aqData;

    if (tempSelf.status == kRecoderRunningStatus) {
        R_GJPCMFrame *buffer = (R_GJPCMFrame *) GJRetainBufferPoolGetData(tempSelf.bufferPool);
        R_BufferWrite(&buffer->retain, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        //        memcpy(buffer->retain.data, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        //        buffer->retain.size = inBuffer->mAudioDataByteSize;
        buffer->pts = GTimeMake(CACurrentMediaTime()*1000, 1000);
        tempSelf.callback(buffer);

        R_BufferUnRetain(&buffer->retain);
        AudioQueueEnqueueBuffer(tempSelf.mAudioQueue, inBuffer, 0, NULL);
    } else {
        AudioQueueFreeBuffer(inAQ, inBuffer);
    }
};

static void aacHandleInputBuffer(void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer, const AudioTimeStamp *inStartTime, UInt32 inNumPackets, const AudioStreamPacketDescription *inPacketDesc){
    //    GJAudioQueueRecoder* tempSelf = (__bridge GJAudioQueueRecoder*)aqData;

    //    if (tempSelf.status == kRecoderRunningStatus){
    //        GJRetainBuffer* buffer = GJRetainBufferPoolGetData(tempSelf.bufferPool);
    //        memcpy(buffer->data, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
    //        #define PUSH_AAC_PACKET_PRE_SIZE 25
    //                uint8_t* aacData = data+PUSH_AAC_PACKET_PRE_SIZE;
    //
    //                R_GJAACPacket* packet = (R_GJAACPacket*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJAACPacket));
    //                GJRetainBuffer* buffer = &packet->retain;
    //               R_BufferPack(&buffer, data, tempSelf.maxOutSize, R_BufferRelease, tempSelf.bufferPool);
    //                int offset = 0;
    //                if (tempSelf.format.mFormatID == kAudioFormatMPEG4AAC) {
    //                    offset = 7;
    //                    adtsDataForPacketLength(inBuffer->mAudioDataByteSize, aacData,tempSelf.format.mSampleRate,tempSelf.format.mChannelsPerFrame);
    //                    packet->adts = aacData;
    //                    packet->adtsSize = offset;
    //                }
    //                packet->aac = aacData+offset;
    //                packet->aacSize = inBuffer->mAudioDataByteSize;
    //                memcpy(packet->aac, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
    //                packet->pts = [[NSDate date]timeIntervalSince1970]*1000;
    //
    //        //        NSLog(@"recode adtssize:%d size:%d",packet->adtsSize,packet->aacSize);
    //
    //        //        static int count ;
    //        //        NSLog(@"send num:%d:%@",count++,[NSData dataWithBytes:buffer->data+7 length:buffer->size-7]);
    //        NSLog(@"recode audio size:%d",inBuffer->mAudioDataByteSize);
    //        [tempSelf.delegate GJAudioQueueRecoder:tempSelf packet:buffer];
    //       R_BufferUnRetain(buffer);
    //        AudioQueueEnqueueBuffer (tempSelf.mAudioQueue,inBuffer,0,NULL);
    //    }else{
    //        AudioQueueFreeBuffer(inAQ, inBuffer);
    //    }
};

@implementation GJAudioQueueRecoder
- (instancetype)initWithStreamWithSampleRate:(Float64)sampleRate channel:(UInt32)channel formatID:(UInt32)formatID {
    self = [super init];
    if (self) {
        if (![[NSThread currentThread] isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self _initWithSampleRate:sampleRate channel:channel formatID:formatID];
            });
        } else {
            [self _initWithSampleRate:sampleRate channel:channel formatID:formatID];
        }
    }

    return self;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        if (![[NSThread currentThread] isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self _initWithSampleRate:44100 channel:2 formatID:kAudioFormatLinearPCM];
            });
        } else {
            [self _initWithSampleRate:44100 channel:2 formatID:kAudioFormatLinearPCM];
        }
    }
    return self;
}
- (BOOL)_initWithSampleRate:(Float64)sampleRate channel:(UInt32)channel formatID:(UInt32)formatID {
    AudioStreamBasicDescription format = {0};
    format.mFormatID                   = formatID;
    AudioQueueInputCallback callback   = pcmHandleInputBuffer;
    switch (formatID) {
        case kAudioFormatLinearPCM: {
            format.mSampleRate       = sampleRate; // 3
            format.mChannelsPerFrame = channel;    // 4
            format.mFramesPerPacket  = 1;          // 7
            format.mBitsPerChannel   = 16;         // 5
            format.mBytesPerFrame    = format.mChannelsPerFrame * format.mBitsPerChannel / 8;
            format.mBytesPerPacket   = format.mBytesPerFrame * format.mFramesPerPacket;
            format.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
            callback                 = pcmHandleInputBuffer;
            break;
        }
        case kAudioFormatMPEG4AAC: {
            format.mSampleRate       = sampleRate;           // 3
            format.mFormatID         = kAudioFormatMPEG4AAC; // 2
            format.mChannelsPerFrame = channel;              // 4
            format.mFramesPerPacket  = 1024;
            callback                 = aacHandleInputBuffer;
            break;
        }
        default:
            GJAssert(0, "录制格式不支持");
            break;
    }
    UInt32   size   = sizeof(AudioStreamBasicDescription);
    OSStatus status = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &format);
    _format         = format;
    _recodeQueue    = dispatch_queue_create("recodequeue", DISPATCH_QUEUE_SERIAL);
    _callbackDelay  = DEFAULT_DELAY;
    status          = AudioQueueNewInput(&format, callback, (__bridge void *_Nullable)(self), NULL, 0, 0, &_mAudioQueue);
    if (status != 0) {
        char *formatName = (char *) &(status);
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueNewInput error:%d: %c%c%c%c---------",status, formatName[3], formatName[2], formatName[1], formatName[0]);
        _mAudioQueue = NULL;

        return NO;
    }
    UInt32 maxPacketSize = 0;
    if (format.mFormatID == kAudioFormatLinearPCM) {
        //        maxPacketSize = _format.mBytesPerFrame * _format.mSampleRate * _callbackDelay;//
        maxPacketSize = _format.mBytesPerFrame * 1024;
        GJRetainBufferPoolCreate(&_bufferPool, maxPacketSize, true, R_GJPCMFrameMalloc, GNULL, GNULL);

    } else {
        UInt32 parmSize = sizeof(maxPacketSize);
        status          = AudioQueueGetProperty(_mAudioQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &parmSize);
        if (status < 0) {
            maxPacketSize = _format.mChannelsPerFrame * _format.mFramesPerPacket * 2;
        } else {
            maxPacketSize = maxPacketSize * 1.0 / _format.mFramesPerPacket * _format.mSampleRate * 0.5 + 7;
        }
        GJRetainBufferPoolCreate(&_bufferPool, maxPacketSize, true, R_GJPacketMalloc, GNULL, GNULL);
    }
    _maxOutSize = maxPacketSize;
    _status     = kRecoderStopStatus;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:AVAudioSessionInterruptionNotification object:nil];

    return YES;
}
- (void)receiveNotification:(NSNotification *)notifica {

    if ([notifica.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        AVAudioSessionInterruptionType    type    = [notifica.userInfo[AVAudioSessionInterruptionTypeKey] longValue];
        AVAudioSessionInterruptionOptions options = [notifica.userInfo[AVAudioSessionInterruptionOptionKey] longValue];

        if (type == AVAudioSessionInterruptionTypeEnded && options == AVAudioSessionInterruptionOptionShouldResume && self.status == kRecoderRunningStatus) {
            [self reStart];
        }
    }
}
- (void)reStart {
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "reStart");
    _status = kRecoderStopStatus;
    AudioQueueReset(_mAudioQueue);
    [self startRecodeAudio];
}
- (BOOL)startRecodeAudio {

    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "startRecodeAudio");
    if (_status == kRecoderRunningStatus || _status == kRecoderInvalidStatus) {
        return NO;
    }
    NSError *error;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AVAudioSession setCategory error:%s", error.localizedDescription.UTF8String);
    }
    error = NULL;
    //    [[AVAudioSession sharedInstance]overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker  error:NULL];
    //    if (error) {
    //        GJLOG(DEFAULT_LOG, GJ_LOGFORBID,"AVAudioSession overrideOutputAudioPort error:%s",error.localizedDescription);
    //    }
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AVAudioSession setActive error:%s", error.localizedDescription.UTF8String);
    }
    NSArray<AVAudioSessionPortDescription *> *inputs = [AVAudioSession sharedInstance].availableInputs;
    for (AVAudioSessionPortDescription *input in inputs) { //设置非内置麦克风
        if (![input.portType isEqualToString:AVAudioSessionPortBuiltInMic]) {
            [[AVAudioSession sharedInstance] setPreferredInput:input error:NULL];
            break;
        }
    }

    for (int i = 0; i < NUMBER_BUFFERS; ++i) { // 1
        OSStatus status = AudioQueueAllocateBuffer(_mAudioQueue, _maxOutSize, &_mAudioBuffers[i]);
        if (status < 0) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueAllocateBuffer error:%d", status);
            return NO;
        }
        status = AudioQueueEnqueueBuffer(_mAudioQueue, _mAudioBuffers[i], 0, NULL);
        if (status < 0) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueEnqueueBuffer error:%d", status);
            return NO;
        }
    }

    OSStatus status = AudioQueueStart(_mAudioQueue, NULL);
    if (status < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioQueueStart error:%d", status);
        return NO;
    } else {
        _status = kRecoderRunningStatus;
        return YES;
    }
};
- (void)stop {
    if (_status == kRecoderRunningStatus) {
        _status = kRecoderStopStatus;
        AudioQueueStop(_mAudioQueue, true);
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "AudioQueueStop");
    }
}
- (void)pause {
    if (_status == kRecoderRunningStatus) {
        _status = kRecoderPauseStatus;
        AudioQueuePause(_mAudioQueue);
    }
}
- (void)dealloc {
    if (_mAudioQueue) {
        AudioQueueDispose(_mAudioQueue, true);
    }
    if (_bufferPool) {
        GJRetainBufferPool *pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, YES);
            GJRetainBufferPoolFree(pool);
        });
    }
}
@end
