//
//  PCMEncoderToAAC.m
//  视频录制
//
//  Created by tongguan on 16/1/8.
//  Copyright © 2016年 未成年大叔. All rights reserved.
//
#import "AACEncoderFromPCM.h"
#import "GJDebug.h"
#import "GJRetainBufferPool.h"

#define PUSH_AAC_PACKET_PRE_SIZE 25

@interface AACEncoderFromPCM ()
{
    AudioConverterRef _encodeConvert;
    GJQueue* _resumeQueue;

    BOOL _isRunning;//状态，是否运行
    dispatch_queue_t _encoderQueue;
    AudioStreamPacketDescription _sourcePCMPacketDescription;
    R_GJPCMPacket* _preBlockBuffer;
    
    GJRetainBufferPool* _bufferPool;
    GInt64 _currentPts;
}
@end

@implementation AACEncoderFromPCM
- (instancetype)initWithSourceForamt:(const AudioStreamBasicDescription*)sFormat DestDescription:(const AudioStreamBasicDescription*)dFormat
{
    self = [super init];
    if (self) {
        _sourceFormat = *sFormat;
        _destFormat = *dFormat;
        [self initQueue];
    }
    return self;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        
        memset(&_destFormat, 0, sizeof(_destFormat));
        _destFormat.mChannelsPerFrame = 1;
        _destFormat.mFramesPerPacket = 1024;
        _destFormat.mSampleRate = 44100;
        _destFormat.mFormatID = kAudioFormatMPEG4AAC;  //aac

        [self initQueue];

    }
    return self;
}
-(void)initQueue{
    queueCreate(&_resumeQueue, 10,true,false);


    _encoderQueue = dispatch_queue_create("audioEncodeQueue", DISPATCH_QUEUE_CONCURRENT);
}
//编码输入
static OSStatus encodeInputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData,AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AACEncoderFromPCM* encoder = (__bridge AACEncoderFromPCM*)inUserData;
    
    if (encoder->_preBlockBuffer) {
        retainBufferUnRetain(&encoder->_preBlockBuffer->retain);
        encoder->_preBlockBuffer = NULL;
    }
    GJQueue* blockQueue =   encoder->_resumeQueue;
    R_GJPCMPacket* buffer;
    if (queuePop(blockQueue, (void**)&buffer,GINT32_MAX)) {
        
        ioData->mBuffers[0].mData = buffer->retain.data+buffer->pcmOffset;
        ioData->mBuffers[0].mNumberChannels =encoder.sourceFormat.mChannelsPerFrame;
        ioData->mBuffers[0].mDataByteSize = (UInt32)buffer->pcmSize;
        AudioStreamBasicDescription* baseDescription = &(encoder->_sourceFormat);
        *ioNumberDataPackets = ioData->mBuffers[0].mDataByteSize / baseDescription->mBytesPerPacket;
        encoder->_preBlockBuffer = buffer;
        *ioNumberDataPackets = 1;
        if (encoder->_currentPts <=0) {
            encoder->_currentPts = buffer->pts;
        }
        return noErr;
    }else{
        *ioNumberDataPackets = 0;
        return -1;
    }
}
- (NSData *)fetchMagicCookie{
    UInt32 size=0;
    AudioConverterGetPropertyInfo(_encodeConvert, kAudioConverterCompressionMagicCookie, &size, nil);
    void* magic = malloc(size);
    AudioConverterGetProperty(_encodeConvert, kAudioConverterCompressionMagicCookie, &size, magic);
    NSData * data = [NSData dataWithBytesNoCopy:magic length:size freeWhenDone:YES];
    return data;
}

-(void)encodeWithPacket:(R_GJPCMPacket*)packet{
    retainBufferRetain(&packet->retain);
    if (!_isRunning || !queuePush(_resumeQueue, packet, 0)) {
        retainBufferUnRetain(&packet->retain);
    }
}
-(BOOL)start{
    [self _createEncodeConverter];
    _currentPts = -1;
    return YES;
}
-(BOOL)stop{
    _isRunning = NO;
    if (_preBlockBuffer) {
        retainBufferUnRetain(&_preBlockBuffer->retain);
    }
    queueBroadcastPop(_resumeQueue);
    GJRetainBuffer* buffer;
    while (queuePop(_resumeQueue, (void**)&buffer, 0)) {
        retainBufferUnRetain(buffer);
    }
    return YES;
}

-(BOOL)_createEncodeConverter{
    
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_destFormat);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_sourceFormat);

    AudioClassDescription audioClass;
   OSStatus status = [self _getAudioClass:&audioClass WithType:_destFormat.mFormatID fromManufacturer:kAppleSoftwareAudioCodecManufacturer];
    assert(!status);
    status = AudioConverterNewSpecific(&_sourceFormat, &_destFormat, 1, &audioClass, &_encodeConvert);
    assert(!status);
    
    AudioConverterGetProperty(_encodeConvert, kAudioConverterCurrentInputStreamDescription, &size, &_sourceFormat);
    
    AudioConverterGetProperty(_encodeConvert, kAudioConverterCurrentOutputStreamDescription, &size, &_destFormat);
    
    if (_destFormat.mFormatID == kAudioFormatMPEG4AAC) {//VCR
        UInt32 size;
       OSStatus status = AudioConverterGetProperty(_encodeConvert, kAudioConverterPropertyMaximumOutputPacketSize, &size, &_destMaxOutSize);
        _destMaxOutSize += PUSH_AAC_PACKET_PRE_SIZE + 7;//7字节aac头
        assert(!status);

        UInt32 outputBitRate = 64000; // 64kbs
        UInt32 propSize = sizeof(outputBitRate);
        
        if (_destFormat.mSampleRate >= 44100) {
            outputBitRate = 192000; // 192kbs
        } else if (_destFormat.mSampleRate < 22000) {
            outputBitRate = 32000; // 32kbs
        }
        
        // set the bit rate depending on the samplerate chosen
        AudioConverterSetProperty(_encodeConvert, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
        
        // get it back and print it out
        AudioConverterGetProperty(_encodeConvert, kAudioConverterEncodeBitRate, &propSize, &outputBitRate);
        GJLOG(@"AAC Encode Bitrate: %u\n", (unsigned int)outputBitRate);
    }
    if (_bufferPool) {
        __block GJRetainBufferPool* tempPool = _bufferPool;
        _bufferPool = NULL;
        GUInt32 maxOutSize = _destMaxOutSize;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolCreate(&tempPool, maxOutSize,true,R_GJAACPacketMalloc,GNULL);
        });
    }
//    [self performSelectorInBackground:@selector(_converterStart) withObject:nil];
    dispatch_async(_encoderQueue, ^{
        [self _converterStart];
    });
    GJLOG(@"AudioConverterNewSpecific success");
    return YES;
}
-(OSStatus)_getAudioClass:(AudioClassDescription*)audioClass WithType:(UInt32)type fromManufacturer:(UInt32)manufacturer{
    UInt32 audioClassSize;
    OSStatus status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(type), &type, &audioClassSize);
    if (status != noErr) {
        return status;
    }
    int count = audioClassSize / sizeof(AudioClassDescription);
    AudioClassDescription audioList[count];
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(type), &type, &audioClassSize, audioClass);
    if (status != noErr) {
        return status;
    }
    for (int i= 0; i < count; i++) {
        if (type == audioList[i].mSubType  && manufacturer == audioList[i].mManufacturer) {
            *audioClass = audioList[i];
            break;
        }
    }
    return noErr;
}

-(void)_converterStart{
    
    _isRunning = YES;
    UInt32 outputDataPacketSize               = 1;
    AudioStreamPacketDescription packetDesc;
    AudioBufferList outCacheBufferList;
    outCacheBufferList.mNumberBuffers = 1;
    outCacheBufferList.mBuffers[0].mNumberChannels = _sourceFormat.mChannelsPerFrame;
   

    while (_isRunning) {
        memset(&packetDesc, 0, sizeof(packetDesc));
        outCacheBufferList.mBuffers[0].mDataByteSize = _destMaxOutSize;
        R_GJAACPacket* packet = (R_GJAACPacket*)GJRetainBufferPoolGetData(_bufferPool);
        GJRetainBuffer* audioBuffer = &packet->retain;
        retainBufferMoveDataPoint(audioBuffer, PUSH_AAC_PACKET_PRE_SIZE);
        outCacheBufferList.mBuffers[0].mData = audioBuffer->data+7;

        OSStatus status = AudioConverterFillComplexBuffer(_encodeConvert, encodeInputDataProc, (__bridge void*)self, &outputDataPacketSize, &outCacheBufferList, &packetDesc);

        if (status != noErr ) {
            retainBufferUnRetain(audioBuffer);
            _isRunning = NO;
            GJAssert(0,"AudioConverterFillComplexBuffer error:%d",(int)status);
            return;
        }
        
        
//        AACEncoderFromPCM_DEBUG("datalenth:%ld",[data length]);
       
        audioBuffer->size = outCacheBufferList.mBuffers[0].mDataByteSize+7;
        GJAssert(audioBuffer->size+audioBuffer->frontSize <= audioBuffer->capacity, "ratainbuffer内存管理错误");
        [self adtsDataForPacketLength:audioBuffer->size data:audioBuffer->data];
        packet->adtsOffset = 0;
        packet->adtsSize = 7;
        packet->aacOffset = 7;
        packet->aacSize = outCacheBufferList.mBuffers[0].mDataByteSize;
        packet->pts = _currentPts;
        _currentPts = -1;
//        [self.delegate AACEncoderFromPCM:self completeBuffer:packet];
        retainBufferUnRetain(audioBuffer);
    }
}
#pragma -mark =======ADTS=======
- (void)adtsDataForPacketLength:(NSUInteger)packetLength data:(uint8_t*)packet
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
    /*
     sampling_frequency_index：表示使用的采样率下标，通过这个下标在 Sampling Frequencies[ ]数组中查找得知采样率的值。
     There are 13 supported frequencies:
     0: 96000 Hz
     1: 88200 Hz
     2: 64000 Hz
     3: 48000 Hz
     4: 44100 Hz
     5: 32000 Hz
     6: 24000 Hz
     7: 22050 Hz
     8: 16000 Hz
     9: 12000 Hz
     10: 11025 Hz
     11: 8000 Hz
     12: 7350 Hz
     13: Reserved
     14: Reserved
     15: frequency is written explictly
     */
    int freqIdx = get_f_index(_destFormat.mSampleRate);//11
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
    int chanCfg = 1;
    NSUInteger fullLength = adtsLength + packetLength;
    packet[0] = (char)0xFF;	// 11111111  	= syncword
    packet[1] = (char)0xF1;	   // 1111 0 00 1 = syncword+id(MPEG-4) + Layer + absent
    //00 1000 0000
    //          01 0000
    //                    0001
    //==============
    //      1001 0000
    packet[2] = (char)(((profile)<<6) + (freqIdx<<4) +(chanCfg>>2));// profile(2)+sampling(4)+privatebit(1)+channel_config(1)
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
}

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
-(void)dealloc{
    queueFree(&(_resumeQueue));
    if (_bufferPool) {
        GJRetainBufferPoolClean(_bufferPool, GTrue);
        GJRetainBufferPoolFree(&_bufferPool);
    }


    
}
#pragma mark - mutex

@end
