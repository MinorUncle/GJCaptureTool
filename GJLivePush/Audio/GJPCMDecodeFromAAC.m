//
//  GJPCMDecodeFromAAC.m
//  视频录制
//
//  Created by tongguan on 16/1/8.
//  Copyright © 2016年 未成年大叔. All rights reserved.
//


#import "GJPCMDecodeFromAAC.h"
#import "GJLog.h"
#import "GJRetainBufferPool.h"

typedef struct _DecodeAudioFrame{
    GJRetainBuffer* audioBuffer;
    int pts;
    AudioStreamPacketDescription packetDesc;
}GJDecodeAudioFrame;

@interface GJPCMDecodeFromAAC ()
{
    AudioConverterRef _decodeConvert;
    GJRetainBufferPool* _bufferPool;
    GJQueue* _resumeQueue;
    BOOL _isRunning;//状态，是否运行
    int _sourceMaxLenth;
    dispatch_queue_t _decodeQueue;

    
    
    GJDecodeAudioFrame* _preFrame;
}

@property (nonatomic,assign) int currentPts;
@property (nonatomic,assign) BOOL running;

@end

@implementation GJPCMDecodeFromAAC
- (instancetype)initWithDestDescription:(AudioStreamBasicDescription*)destDescription SourceDescription:(AudioStreamBasicDescription*)sourceDescription;
{
    self = [super init];
    if (self) {
        
        if (sourceDescription != NULL) {
            _sourceFormat = *sourceDescription;
        }else{
            memset(&_sourceFormat, 0, sizeof(_sourceFormat));
        }
        
        if (destDescription != NULL) {
            _destFormat = *destDescription;
        }else{
            _destFormat = [GJPCMDecodeFromAAC defaultDestFormatDescription];
        }
        [self initQueue];
    }
    return self;
}


- (instancetype)init
{
   
    return [self initWithDestDescription:nil SourceDescription:nil];
}
-(void)initQueue{
    _decodeQueue = dispatch_queue_create("audioDecodeQueue", DISPATCH_QUEUE_CONCURRENT);
    queueCreate(&_resumeQueue, 20, true, true);
}
+(AudioStreamBasicDescription)defaultSourceFormateDescription{
    AudioStreamBasicDescription format = {0};
    format.mChannelsPerFrame = 1;
    format.mFramesPerPacket = 1024;
    format.mSampleRate = 44100;
    format.mFormatID = kAudioFormatMPEG4AAC;  //aac
    return format;
}
+(AudioStreamBasicDescription)defaultDestFormatDescription{
    AudioStreamBasicDescription format = {0};
    format.mChannelsPerFrame = 1;
    format.mSampleRate = 44100;
    format.mFormatID = kAudioFormatLinearPCM; //PCM
    format.mBitsPerChannel = 16;
    format.mBytesPerPacket = format.mBytesPerFrame =format.mChannelsPerFrame *  format.mBitsPerChannel;
    format.mFramesPerPacket = 1;
    format.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
    return format;
}


-(void)start{
    _running = YES;
    if (_decodeConvert == NULL) {
        [self _createEncodeConverter];
    }
}
-(void)stop{
    _running = NO;
    queueClean(_resumeQueue);
}
//编码输入
static OSStatus encodeInputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData,AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
   
    GJPCMDecodeFromAAC* decode =(__bridge GJPCMDecodeFromAAC*)inUserData;
    
    if (decode->_preFrame) {
        retainBufferUnRetain(decode->_preFrame->audioBuffer);
        free(decode->_preFrame);
        decode->_preFrame = NULL;
    }
    GJQueue* param =   decode->_resumeQueue;
    GJRetainBuffer* retainBuffer;
    GJDecodeAudioFrame* frame;
    AudioStreamPacketDescription* description = NULL;
    
    if (decode.running && queuePop(param,(void**)&frame,INT_MAX)) {
        retainBuffer = frame->audioBuffer;
        description = &(frame->packetDesc);
        ioData->mBuffers[0].mData = (uint8_t*)retainBuffer->data + description->mStartOffset;
        ioData->mBuffers[0].mNumberChannels = decode->_sourceFormat.mChannelsPerFrame;
        ioData->mBuffers[0].mDataByteSize = retainBuffer->size - (UInt32)description->mStartOffset;
        description->mDataByteSize -= description->mStartOffset;
        description->mStartOffset = 0;
        *ioNumberDataPackets = 1;
    }else{
        *ioNumberDataPackets = 0;
        return -1;
    }
    
    if (outDataPacketDescription) {
        outDataPacketDescription[0] = description;
    }
    if (decode.currentPts <= 0) {
        decode.currentPts = frame->pts;
    }
    decode->_preFrame = frame;
    return noErr;
}

-(void)decodeBuffer:(GJRetainBuffer*)audioBuffer packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins pts:(int)pts{
    
    retainBufferRetain(audioBuffer);
    GJDecodeAudioFrame *frame = (GJDecodeAudioFrame*)malloc(sizeof(GJDecodeAudioFrame));
    frame->audioBuffer = audioBuffer;
    frame->pts = pts;
    frame->packetDesc = *packetDescriptioins;
    if (!queuePush(_resumeQueue, frame,1000)) {
        retainBufferUnRetain(audioBuffer);
        free(frame);
        GJLOG(GJ_LOGWARNING,"aac decode to pcm queuePush faile");
    }
}

#define AAC_FRAME_PER_PACKET 1024

static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
-(BOOL)_createEncodeConverter{
    if (_decodeConvert) {
        AudioConverterDispose(_decodeConvert);
    }
    
    if(_sourceFormat.mFormatID <= 0){
    // get audio format
        GJDecodeAudioFrame* frame;
        if (queuePeekWaitValue(_resumeQueue, 0,(void**)&frame, INT_MAX) && _running) {
            uint8_t* adts = frame->audioBuffer->data;
            uint8_t sampleIndex = adts[2] << 2;
            sampleIndex = sampleIndex>>4;
            int sampleRate = mpeg4audio_sample_rates[sampleIndex];
            uint8_t channel = adts[2] & 0x1 <<2;
            channel += (adts[3] & 0xb0)>>6;
            
            memset(&_sourceFormat, 0, sizeof(_sourceFormat));
            _sourceFormat.mFormatID = kAudioFormatMPEG4AAC;
            _sourceFormat.mChannelsPerFrame = channel;
            _sourceFormat.mSampleRate = sampleRate;
            _sourceFormat.mFramesPerPacket = 1024;
        }else{
            return false;
        }
    }
    
    if (_destFormat.mFormatID <= 0) {
        _destFormat.mSampleRate       = _sourceFormat.mSampleRate;               // 3
        _destFormat.mChannelsPerFrame = _sourceFormat.mChannelsPerFrame;                     // 4
        _destFormat.mFramesPerPacket  = 1;                     // 7
        _destFormat.mBitsPerChannel   = 16;                    // 5
        _destFormat.mBytesPerFrame   = _destFormat.mChannelsPerFrame * _destFormat.mBitsPerChannel/8;
        _destFormat.mFramesPerPacket = _destFormat.mBytesPerFrame * _destFormat.mFramesPerPacket ;
        _destFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
    }
    
    
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_destFormat);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_sourceFormat);
    

    OSStatus status = AudioConverterNew(&_sourceFormat, &_destFormat, &_decodeConvert);
    if (status != noErr) {
        GJLOG(GJ_LOGERROR, "AudioConverterNew error:%d",status);
    }
    _destMaxOutSize = 0;
    status = AudioConverterGetProperty(_decodeConvert, kAudioConverterPropertyMaximumOutputPacketSize, &size, &_destMaxOutSize);
    _destMaxOutSize *= AAC_FRAME_PER_PACKET;
    if (_bufferPool) {
        GJRetainBufferPoolCleanAndFree(&_bufferPool);
    }
    GJRetainBufferPoolCreate(&_bufferPool, _destMaxOutSize,true);
    
    AudioConverterGetProperty(_decodeConvert, kAudioConverterCurrentInputStreamDescription, &size, &_sourceFormat);
    
    AudioConverterGetProperty(_decodeConvert, kAudioConverterCurrentOutputStreamDescription, &size, &_destFormat);
    
//    [self performSelectorInBackground:@selector(_converterStart) withObject:nil];
    dispatch_async(_decodeQueue, ^{
        [self _converterStart];
    });
    return YES;
}


-(void)_converterStart{
    _isRunning = YES;
    AudioStreamPacketDescription packetDesc;
    AudioBufferList outCacheBufferList;
    UInt32 numPackets = AAC_FRAME_PER_PACKET;
    while (_isRunning) {
        memset(&packetDesc, 0, sizeof(packetDesc));
        memset(&outCacheBufferList, 0, sizeof(AudioBufferList));
        
        GJRetainBuffer* buffer = GJRetainBufferPoolGetData(_bufferPool);
        outCacheBufferList.mNumberBuffers = 1;
        outCacheBufferList.mBuffers[0].mNumberChannels = 1;
        outCacheBufferList.mBuffers[0].mData = buffer->data;
        outCacheBufferList.mBuffers[0].mDataByteSize = AAC_FRAME_PER_PACKET * _destFormat.mBytesPerPacket;
        
        OSStatus status = AudioConverterFillComplexBuffer(_decodeConvert, encodeInputDataProc, (__bridge void*)self, &numPackets, &outCacheBufferList, &packetDesc);
        // assert(!status);
        if (status != noErr || status == -1) {
            
            retainBufferUnRetain(buffer);
            char* codeChar = (char*)&status;
            GJLOG(GJ_LOGDEBUG, "AudioConverterFillComplexBufferError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
            break;
        }
        
        buffer->size = _destFormat.mBytesPerPacket*numPackets;
        int pts = _currentPts;
        _currentPts = -1;
        [self.delegate pcmDecode:self completeBuffer:buffer pts:pts];
        retainBufferUnRetain(buffer);
    }
}

-(void)dealloc{
    _isRunning = NO;
    AudioConverterDispose(_decodeConvert);
    if (_preFrame) {
        retainBufferUnRetain(_preFrame->audioBuffer);
        free(_preFrame);
    }
    GJLOG(GJ_LOGDEBUG, "gjpcmdecodeformaac delloc");
}

#pragma mark - mutex

@end
