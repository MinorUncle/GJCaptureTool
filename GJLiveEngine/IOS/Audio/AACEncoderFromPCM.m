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

@interface AACEncoderFromPCM ()
{
    AudioConverterRef _encodeConvert;
    GJQueue* _resumeQueue;

    dispatch_queue_t _encoderQueue;
    AudioStreamPacketDescription _sourcePCMPacketDescription;
    R_GJPCMFrame* _preBlockBuffer;
    
    GJRetainBufferPool* _bufferPool;
    GInt64 _currentPts;
}
@property (nonatomic,assign) BOOL isRunning;

@end

@implementation AACEncoderFromPCM
- (instancetype)initWithSourceForamt:(const AudioStreamBasicDescription*)sFormat DestDescription:(const AudioStreamBasicDescription*)dFormat
{
    self = [super init];
    if (self) {
        _sourceFormat = *sFormat;
        _destFormat = *dFormat;
        _bitrate = 64000; // 64kbs
        
        if (_destFormat.mSampleRate >= 44100) {
            _bitrate = 192000; // 192kbs
        } else if (_destFormat.mSampleRate < 22000) {
            _bitrate = 32000; // 32kbs
        }

        [self initQueue];
    }
    return self;
}

- (instancetype)init
{
    
    self = [super init];
    if (self) {
        GJAssert(0, "请使用 initWithSourceForamt");
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
    _encoderQueue = dispatch_queue_create("audioEncodeQueue", DISPATCH_QUEUE_SERIAL);
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
    R_GJPCMFrame* buffer;
    if (encoder.isRunning && queuePop(blockQueue, (void**)&buffer,GINT32_MAX)) {
        
        ioData->mBuffers[0].mData = buffer->retain.data;
        ioData->mBuffers[0].mNumberChannels =encoder.sourceFormat.mChannelsPerFrame;
        ioData->mBuffers[0].mDataByteSize = (UInt32)buffer->retain.size;
        AudioStreamBasicDescription* baseDescription = &(encoder->_sourceFormat);
        *ioNumberDataPackets = ioData->mBuffers[0].mDataByteSize / baseDescription->mBytesPerPacket;
        encoder->_preBlockBuffer = buffer;
        if (encoder->_currentPts <=0) {
            encoder->_currentPts = buffer->pts;
        }
        return noErr;
    }else{
        *ioNumberDataPackets = 0;
        GJLOG(GJ_LOGWARNING, "encodeInputDataProc 0 faile");
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
-(void)encodeWithBuffer:(CMSampleBufferRef)sampleBuffer{
    
    AudioBufferList inBufferList;
    CMBlockBufferRef bufferRef;
    
    OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, nil, &inBufferList, sizeof(inBufferList), NULL, NULL, 0, &bufferRef);
    assert(!status);
    if (status != noErr) {
        NSLog(@"CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer error:%d",(int)status);
        return;
    }
    size_t lenth;
    char* point;
    CMBlockBufferGetDataPointer(bufferRef, 0, NULL, &lenth, &point);
    R_GJPCMFrame* packet = (R_GJPCMFrame*)malloc(sizeof(R_GJPCMFrame));
    [self encodeWithPacket:packet];
    retainBufferUnRetain(&packet->retain);
}
    
-(void)encodeWithPacket:(R_GJPCMFrame*)packet{
    retainBufferRetain(&packet->retain);
    if (!_isRunning || !queuePush(_resumeQueue, packet, 0)) {
        retainBufferUnRetain(&packet->retain);
    }
}
-(BOOL)start{
    _isRunning = YES;
    [self _createEncodeConverter];
    _currentPts = -1;
    return YES;
}
-(BOOL)stop{
    _isRunning = NO;

    queueBroadcastPop(_resumeQueue);
    if(_encodeConvert){
        AudioConverterDispose(_encodeConvert);
        _encodeConvert = nil;
    }
    GJRetainBuffer* buffer;
    while (queuePop(_resumeQueue, (void**)&buffer, 0)) {
        retainBufferUnRetain(buffer);
    }
    if (_preBlockBuffer) {
        retainBufferUnRetain(&_preBlockBuffer->retain);
        _preBlockBuffer = NULL;
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

        UInt32 outputBitRate = _bitrate; // 64kbs
        UInt32 propSize = sizeof(outputBitRate);
        
        // set the bit rate depending on the samplerate chosen
        AudioConverterSetProperty(_encodeConvert, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
        
        // get it back and print it out
        AudioConverterGetProperty(_encodeConvert, kAudioConverterEncodeBitRate, &propSize, &outputBitRate);
        GJLOG(GJ_LOGDEBUG,"AAC Encode Bitrate: %u kbps\n", (unsigned int)outputBitRate/1000);
    }
    if (_bufferPool) {
        GJRetainBufferPool* pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, GTrue);
            GJRetainBufferPoolFree(pool);
        });
        _bufferPool = NULL;
    }
    GJRetainBufferPoolCreate(&_bufferPool, _destMaxOutSize,true,R_GJAACPacketMalloc,GNULL);
//    [self performSelectorInBackground:@selector(_converterStart) withObject:nil];
    dispatch_async(_encoderQueue, ^{
        [self _converterStart];
    });
    GJLOG(GJ_LOGDEBUG, "AudioConverterNewSpecific success");
    return YES;
}
-(void)setBitrate:(int)bitrate{
    _bitrate = bitrate;
    UInt32 propSize = 0;
    // set the bit rate depending on the samplerate chosen
//    AudioConverterSetProperty(_encodeConvert, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
//    // get it back and print it out
//    AudioConverterGetProperty(_encodeConvert, kAudioConverterEncodeBitRate, &propSize, &outputBitRate);
    OSStatus result = AudioConverterGetPropertyInfo(_encodeConvert, kAudioConverterApplicableEncodeBitRates, &propSize, NULL);
    if (result != noErr || propSize <= 0) {
        return;
    }
    
    AudioValueRange* arry = (AudioValueRange*)malloc(propSize);
    result = AudioConverterGetProperty(_encodeConvert, kAudioConverterApplicableEncodeBitRates, &propSize, arry);
    if (result != noErr) {
        free(arry);
        return;
    }
    int availableCount = propSize / sizeof(AudioValueRange);
    Float64 current = arry[0].mMinimum;
    for (int i = 0; i<availableCount; i++) {
        if (arry[i].mMinimum > bitrate) {
            break;
        }else{
            current = arry[i].mMinimum;
        }
    }
    
    UInt32 outputBitRate = (UInt32)current;
    propSize = sizeof(outputBitRate);
    result = AudioConverterSetProperty(_encodeConvert, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
    if(result == noErr){
        _bitrate = (int)outputBitRate;
        GJLOG(GJ_LOGDEBUG,"AAC Encode Bitrate: %u kbps\n", (unsigned int)outputBitRate/1000);
    }else{
        GJLOG(GJ_LOGDEBUG,"AAC Encode Bitrate: %u kbps error:%d\n", (unsigned int)outputBitRate/1000,result);
    }
    free(arry);
}
-(OSStatus)_getAudioClass:(AudioClassDescription*)audioClass WithType:(UInt32)type fromManufacturer:(UInt32)manufacturer{
    UInt32 audioClassSize;
    OSStatus status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(type), &type, &audioClassSize);
    if (status != noErr) {
        GJLOG(GJ_LOGFORBID, "AudioFormatGetPropertyInfo error:%d",status);
        return status;
    }
    int count = audioClassSize / sizeof(AudioClassDescription);
    AudioClassDescription audioList[count];
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(type), &type, &audioClassSize, audioList);
    if (status != noErr) {
        GJLOG(GJ_LOGFORBID, "AudioFormatGetPropertyInfo error2:%d",status);
        return status;
    }
    int i = 0;
    for (i= 0; i < count; i++) {
        if (type == audioList[i].mSubType  && manufacturer == audioList[i].mManufacturer) {
            *audioClass = audioList[i];
            break;
        }
    }
    if (i >= count) {
        GJLOG(GJ_LOGFORBID, "not find audio encoder");

    }
    
    return noErr;
}

-(void)_converterStart{
    GJLOG(GJ_LOGDEBUG,"_converterStart");
    UInt32 outputDataPacketSize               = 1;
    AudioStreamPacketDescription packetDesc;
    AudioBufferList outCacheBufferList;
    outCacheBufferList.mNumberBuffers = 1;
    outCacheBufferList.mBuffers[0].mNumberChannels = _sourceFormat.mChannelsPerFrame;
   

    while (_isRunning) {
//        memset(&packetDesc, 0, sizeof(packetDesc));
        R_GJAACPacket* packet = (R_GJAACPacket*)GJRetainBufferPoolGetData(_bufferPool);
        GJRetainBuffer* audioBuffer = &packet->retain;
        if(audioBuffer->frontSize<PUSH_AAC_PACKET_PRE_SIZE){
            retainBufferMoveDataPoint(audioBuffer, PUSH_AAC_PACKET_PRE_SIZE,GFalse);
        }
        outCacheBufferList.mBuffers[0].mData = audioBuffer->data+7;
        outCacheBufferList.mBuffers[0].mDataByteSize = _destMaxOutSize;

        OSStatus status = AudioConverterFillComplexBuffer(_encodeConvert, encodeInputDataProc, (__bridge void*)self, &outputDataPacketSize, &outCacheBufferList, &packetDesc);

        if (status != noErr ) {
            retainBufferUnRetain(audioBuffer);
            if(_isRunning){
                GJLOG(GJ_LOGFORBID, "running状态编码错误");
                _isRunning = NO;
            }else{
                GJLOG(GJ_LOGWARNING, "编码结束");
            }
            break;
        }
        

        audioBuffer->size = outCacheBufferList.mBuffers[0].mDataByteSize+7;
//        adtsDataForPacketLength(outCacheBufferList.mBuffers[0].mDataByteSize, audioBuffer->data, _destFormat.mSampleRate, _destFormat.mChannelsPerFrame);
        packet->adtsOffset = 0;
        packet->adtsSize = 0;
        packet->aacOffset = 7;
        packet->aacSize = outCacheBufferList.mBuffers[0].mDataByteSize;
        packet->pts = _currentPts;
        _currentPts = -1;
        self.completeCallback(packet);
        retainBufferUnRetain(audioBuffer);
    }
}
#pragma -mark =======ADTS=======
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
        GJRetainBufferPool* pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, GTrue);
            GJRetainBufferPoolFree(pool);
        });
    }

    GJLOG(GJ_LOGINFO, "AACEncoderFromPCM");
    
}
#pragma mark - mutex

@end
