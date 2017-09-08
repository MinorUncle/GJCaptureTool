//
//  PCMEncoderToAAC.m
//  视频录制
//
//  Created by tongguan on 16/1/8.
//  Copyright © 2016年 未成年大叔. All rights reserved.
//
#import "AACEncoderFromPCM.h"
#import "GJLog.h"
#import "GJRetainBufferPool.h"

#define PUSH_AAC_PACKET_PRE_SIZE 25
//#define AAC_GOP_FRAMES 1024
@interface AACEncoderFromPCM () {
    AudioConverterRef _encodeConvert;

    AudioStreamPacketDescription _sourcePCMPacketDescription;
    R_GJPCMFrame *               _sourceFrame;

    GJRetainBufferPool *_bufferPool;
    int                 _errorTimes;

    uint8_t *encodecBuf;
}

@end

@implementation AACEncoderFromPCM
- (instancetype)initWithSourceForamt:(const AudioStreamBasicDescription *)sFormat DestDescription:(const AudioStreamBasicDescription *)dFormat bitrate:(int)bitrate {
    self = [super init];
    if (self) {
        _sourceFormat = *sFormat;
        _destFormat   = *dFormat;
        _bitrate      = bitrate; // 64kbs

        [self initQueue];
    }
    return self;
}

- (instancetype)init {

    self = [super init];
    if (self) {
        GJAssert(0, "请使用 initWithSourceForamt");
        memset(&_destFormat, 0, sizeof(_destFormat));
        _destFormat.mChannelsPerFrame = 1;
        _destFormat.mFramesPerPacket  = 1024;
        _destFormat.mSampleRate       = 44100;
        _destFormat.mFormatID         = kAudioFormatMPEG4AAC; //aac

        [self initQueue];
    }
    return self;
}
- (void)initQueue {
}
//编码输入
static OSStatus encodeInputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    AACEncoderFromPCM *          encoder         = (__bridge AACEncoderFromPCM *) inUserData;
    R_GJPCMFrame *               buffer          = encoder->_sourceFrame;
    AudioStreamBasicDescription *baseDescription = &(encoder->_sourceFormat);

    UInt32 sourcePackets = R_BufferSize(&buffer->retain) / baseDescription->mBytesPerPacket;
    if (sourcePackets == *ioNumberDataPackets) {
        ioData->mBuffers[0].mData           = R_BufferStart(&buffer->retain);
        ioData->mBuffers[0].mNumberChannels = encoder->_sourceFormat.mChannelsPerFrame;
        ioData->mBuffers[0].mDataByteSize   = (UInt32) R_BufferSize(&buffer->retain);
        *ioNumberDataPackets                = sourcePackets;
        return noErr;
    } else {
        GJLOG(GJ_LOGFORBID, "每包帧的个数一定要等于mFramesPerPacket");
        *ioNumberDataPackets = 0;
        return -1;
    }
}
- (NSData *)fetchMagicCookie {
    UInt32 size = 0;
    AudioConverterGetPropertyInfo(_encodeConvert, kAudioConverterCompressionMagicCookie, &size, nil);
    void *magic = malloc(size);
    AudioConverterGetProperty(_encodeConvert, kAudioConverterCompressionMagicCookie, &size, magic);
    NSData *data = [NSData dataWithBytesNoCopy:magic length:size freeWhenDone:YES];
    return data;
}
- (BOOL)encodeWithBuffer:(CMSampleBufferRef)sampleBuffer {

    AudioBufferList  inBufferList;
    CMBlockBufferRef bufferRef;

    OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, nil, &inBufferList, sizeof(inBufferList), NULL, NULL, 0, &bufferRef);
    assert(!status);
    if (status != noErr) {
        NSLog(@"CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer error:%d", (int) status);
        return NO;
    }
    size_t lenth;
    char * point;
    CMBlockBufferGetDataPointer(bufferRef, 0, NULL, &lenth, &point);
    R_GJPCMFrame *packet = (R_GJPCMFrame *) malloc(sizeof(R_GJPCMFrame));
    return [self encodeWithPacket:packet];
}

//-(void)encodeWithPacket:(R_GJPCMFrame*)packet{
//   R_BufferRetain(&packet->retain);
//    if (!_isRunning || !queuePush(_resumeQueue, packet, 0)) {
//       R_BufferUnRetain(&packet->retain);
//    }
//}
- (BOOL)start {
    return [self _createEncodeConverter];
}
- (BOOL)stop {

    if (_encodeConvert) {
        GJLOG(GJ_LOGINFO, "AACEncoderFromPCM :%p", _encodeConvert);
        AudioConverterDispose(_encodeConvert);
        _encodeConvert = nil;
    }

    return YES;
}

- (BOOL)_createEncodeConverter {

    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_destFormat);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_sourceFormat);

    AudioClassDescription audioClass;
    OSStatus              status = [self _getAudioClass:&audioClass WithType:_destFormat.mFormatID fromManufacturer:kAppleSoftwareAudioCodecManufacturer];
    assert(!status);
    status = AudioConverterNewSpecific(&_sourceFormat, &_destFormat, 1, &audioClass, &_encodeConvert);
    assert(!status);

    AudioConverterGetProperty(_encodeConvert, kAudioConverterCurrentInputStreamDescription, &size, &_sourceFormat);

    AudioConverterGetProperty(_encodeConvert, kAudioConverterCurrentOutputStreamDescription, &size, &_destFormat);

    [self setBitrate:_bitrate];
    if (_destFormat.mFormatID == kAudioFormatMPEG4AAC) { //VCR
        UInt32   size;
        OSStatus status = AudioConverterGetProperty(_encodeConvert, kAudioConverterPropertyMaximumOutputPacketSize, &size, &_destMaxOutSize);
        _destMaxOutSize += PUSH_AAC_PACKET_PRE_SIZE + 7; //7字节aac头
        assert(!status);
    }
    if (_bufferPool) {
        GJRetainBufferPool *pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, GTrue);
            GJRetainBufferPoolFree(pool);
        });
        _bufferPool = NULL;
    }
    GJRetainBufferPoolCreate(&_bufferPool, _destMaxOutSize, true, R_GJPacketMalloc, GNULL, GNULL);
    GJLOG(GJ_LOGDEBUG, "AudioConverterNewSpecific success:%p", _encodeConvert);
    return YES;
}
- (void)setBitrate:(int)bitrate {
    if (bitrate <= 100) {
        return;
    }
    _bitrate = bitrate;

    UInt32 propSize = 0;

    OSStatus result = AudioConverterGetPropertyInfo(_encodeConvert, kAudioConverterApplicableEncodeBitRates, &propSize, NULL);
    if (result != noErr || propSize <= 0) {
        return;
    }

    AudioValueRange *arry = (AudioValueRange *) malloc(propSize);
    result                = AudioConverterGetProperty(_encodeConvert, kAudioConverterApplicableEncodeBitRates, &propSize, arry);
    if (result != noErr) {
        free(arry);
        return;
    }
    int     availableCount = propSize / sizeof(AudioValueRange);
    Float64 current        = arry[0].mMinimum;
    for (int i = 0; i < availableCount; i++) {
        if (arry[i].mMinimum > bitrate) {
            break;
        } else {
            current = arry[i].mMinimum;
        }
    }

    UInt32 outputBitRate = (UInt32) current;
    propSize             = sizeof(outputBitRate);
    result               = AudioConverterSetProperty(_encodeConvert, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
    if (result == noErr) {
        _bitrate = (int) outputBitRate;
        GJLOG(GJ_LOGDEBUG, "AAC Encode Bitrate: %u kbps\n", (unsigned int) outputBitRate / 1000);
    } else {
        GJLOG(GJ_LOGDEBUG, "AAC Encode Bitrate: %u kbps error:%d\n", (unsigned int) outputBitRate / 1000, result);
    }
    free(arry);
}
- (OSStatus)_getAudioClass:(AudioClassDescription *)audioClass WithType:(UInt32)type fromManufacturer:(UInt32)manufacturer {
    UInt32   audioClassSize;
    OSStatus status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(type), &type, &audioClassSize);
    if (status != noErr) {
        GJLOG(GJ_LOGFORBID, "AudioFormatGetPropertyInfo error:%d", status);
        return status;
    }
    int                   count = audioClassSize / sizeof(AudioClassDescription);
    AudioClassDescription audioList[count];
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(type), &type, &audioClassSize, audioList);
    if (status != noErr) {
        GJLOG(GJ_LOGFORBID, "AudioFormatGetPropertyInfo error2:%d", status);
        return status;
    }
    int i = 0;
    for (i = 0; i < count; i++) {
        if (type == audioList[i].mSubType && manufacturer == audioList[i].mManufacturer) {
            *audioClass = audioList[i];
            break;
        }
    }
    if (i >= count) {
        GJLOG(GJ_LOGFORBID, "not find audio encoder");
    }

    return noErr;
}

- (BOOL)encodeWithPacket:(R_GJPCMFrame *)frame {
    _sourceFrame                                      = frame;
    UInt32                       outputDataPacketSize = 1;
    AudioStreamPacketDescription packetDesc;
    AudioBufferList              outCacheBufferList;
    outCacheBufferList.mNumberBuffers              = 1;
    outCacheBufferList.mBuffers[0].mNumberChannels = _sourceFormat.mChannelsPerFrame;

    R_GJPacket *    packet      = (R_GJPacket *) GJRetainBufferPoolGetData(_bufferPool);
    GJRetainBuffer *audioBuffer = &packet->retain;
    if (R_BufferFrontSize(&packet->retain) < PUSH_AAC_PACKET_PRE_SIZE) {
        R_BufferMoveDataPoint(audioBuffer, PUSH_AAC_PACKET_PRE_SIZE, GFalse);
    }
    outCacheBufferList.mBuffers[0].mData         = R_BufferStart(&packet->retain) + 7;
    outCacheBufferList.mBuffers[0].mDataByteSize = _destMaxOutSize - 7;
    OSStatus status                              = AudioConverterFillComplexBuffer(_encodeConvert, encodeInputDataProc, (__bridge void *) self, &outputDataPacketSize, &outCacheBufferList, &packetDesc);

    if (status != noErr) {
        R_BufferUnRetain(audioBuffer);
        GJLOG(GJ_LOGERROR, "running状态编码错误 times:%d", _errorTimes++);
        return NO;
    }
    R_BufferSetSize(audioBuffer, outCacheBufferList.mBuffers[0].mDataByteSize + 7);
    //    audioBuffer->size = outCacheBufferList.mBuffers[0].mDataByteSize+7;
    adtsDataForPacketLength(outCacheBufferList.mBuffers[0].mDataByteSize, R_BufferStart(&packet->retain), _destFormat.mSampleRate, _destFormat.mChannelsPerFrame);

    packet->type       = GJMediaType_Audio;
    packet->dataOffset = 7;
    packet->dataSize   = outCacheBufferList.mBuffers[0].mDataByteSize;
    packet->pts        = frame->pts;
    packet->dts        = frame->pts;
    self.completeCallback(packet);
    R_BufferUnRetain(audioBuffer);
    return YES;
}
#pragma - mark == == == = ADTS == == == =
static void adtsDataForPacketLength(int packetLength, uint8_t *packet, int sampleRate, int channel) {
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

    int freqIdx = get_f_index(sampleRate); //11
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
    int        chanCfg    = channel;
    NSUInteger fullLength = adtsLength + packetLength;
    packet[0]             = (char) 0xFF; // 11111111  	= syncword
    packet[1]             = (char) 0xF1; // 1111 0 00 1 = syncword+id(MPEG-4) + Layer + absent

    packet[2] = (char) (((profile) << 6) + (freqIdx << 2) + (chanCfg >> 2)); // profile(2)+sampling(4)+privatebit(1)+channel_config(1)
    packet[3] = (char) (((chanCfg & 3) << 6) + (fullLength >> 11));
    packet[4] = (char) ((fullLength & 0x7FF) >> 3);
    packet[5] = (char) (((fullLength & 7) << 5) + 0x1F);
    packet[6] = (char) 0xFC;

#if 0
    static const int mpeg4audio_sample_rates[16] = {
        96000, 88200, 64000, 48000, 44100, 32000,
        24000, 22050, 16000, 12000, 11025, 8000, 7350
    };
    uint8_t* adts = packet;
    uint8_t sampleIndex = adts[2] << 2;
    sampleIndex = sampleIndex>>4;
    int rsampleRate = mpeg4audio_sample_rates[sampleIndex];
    uint8_t rchannel = adts[2] & 0x1 <<2;
    rchannel += (adts[3] & 0xc0)>>6;
    printf("samplerate:%d,channel:%d",rsampleRate,rchannel);

#endif
}

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
- (void)dealloc {
    if (_bufferPool) {
        GJRetainBufferPool *pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, GTrue);
            GJRetainBufferPoolFree(pool);
        });
    }

    GJLOG(GJ_LOGINFO, "AACEncoderFromPCM");
}
#pragma mark - mutex

@end
