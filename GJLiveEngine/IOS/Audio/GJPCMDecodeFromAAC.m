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



@interface GJPCMDecodeFromAAC ()
{
    AudioConverterRef _decodeConvert;
    GJRetainBufferPool* _bufferPool;
    GJQueue* _resumeQueue;
    int _sourceMaxLenth;
    dispatch_queue_t _decodeQueue;

    
    
    R_GJPacket* _prePacket;
    AudioStreamPacketDescription tPacketDesc;
}

@property (nonatomic,assign) int64_t currentPts;
@property (nonatomic,assign) BOOL running;

@end

@implementation GJPCMDecodeFromAAC
- (instancetype)initWithDestDescription:(AudioStreamBasicDescription)destDescription SourceDescription:(AudioStreamBasicDescription)sourceDescription;
{
    self = [super init];
    if (self) {
        _sourceFormat = sourceDescription;
        _destFormat = destDescription;

        [self initQueue];
    }
    return self;
}


- (instancetype)init
{
    AudioStreamBasicDescription s = {0},d = [GJPCMDecodeFromAAC defaultDestFormatDescription];
    return [self initWithDestDescription:d SourceDescription:s];
}
-(void)initQueue{
    _decodeQueue = dispatch_queue_create("audioDecodeQueue", DISPATCH_QUEUE_SERIAL);
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
    GJLOG(GJ_LOGINFO, "AACDecode Start:%p",self);
    _running = YES;
    [self _createEncodeConverter];
}
-(void)stop{
    GJLOG(GJ_LOGINFO, "AACDecode stop:%p",self);
    _running = NO;
    queueEnablePop(_resumeQueue, GFalse);
    if(_decodeConvert){
        AudioConverterDispose(_decodeConvert);
        GJLOG(GJ_LOGINFO, "AudioConverterDispose");
        _decodeConvert = nil;
    }
    R_GJPacket* packet = NULL;
    while (queuePop(_resumeQueue, (GVoid**)&packet, 0)) {
        retainBufferUnRetain(&packet->retain);
    }
    if (_prePacket) {
        retainBufferUnRetain(&_prePacket->retain);
        _prePacket = NULL;
    }
}
//编码输入
static OSStatus decodeInputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData,AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    GJPCMDecodeFromAAC* decode =(__bridge GJPCMDecodeFromAAC*)inUserData;
    if (decode->_prePacket) {
        retainBufferUnRetain(&decode->_prePacket->retain);
        decode->_prePacket = NULL;
    }
    GJQueue* param =   decode->_resumeQueue;
    GJRetainBuffer* retainBuffer;
    R_GJPacket* packet;    
    if (decode.running && queuePop(param,(void**)&packet,INT_MAX)) {
        retainBuffer = &packet->retain;
        ioData->mBuffers[0].mData = packet->retain.data + packet->dataOffset;
        ioData->mBuffers[0].mNumberChannels = decode->_sourceFormat.mChannelsPerFrame;
        ioData->mBuffers[0].mDataByteSize = packet->dataSize;
        *ioNumberDataPackets = 1;
    }else{
        *ioNumberDataPackets = 0;
        GJLOG(GJ_LOGWARNING, "decodeInputDataProc 0 faile");
        return -1;
    }
    
    if (outDataPacketDescription) {
        decode->tPacketDesc.mStartOffset = decode->tPacketDesc.mVariableFramesInPacket=0;
        decode->tPacketDesc.mDataByteSize = packet->dataSize;
        outDataPacketDescription[0] = &(decode->tPacketDesc);
    }
    if (decode.currentPts <= 0) {
        decode.currentPts = packet->pts;
    }
    decode->_prePacket = packet;
    return noErr;
}

-(void)decodePacket:(R_GJPacket*)packet{
    retainBufferRetain(&packet->retain);
    if(!_running || !queuePush(_resumeQueue, packet,0)) {
        retainBufferUnRetain(&packet->retain);
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
        R_GJPacket* packet;
        if (queuePeekWaitValue(_resumeQueue, 0,(void**)&packet, INT_MAX) && packet->flag == GJPacketFlag_KEY && _running) {
            uint8_t* adts = packet->dataOffset+packet->retain.data;
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
            GJLOG(GJ_LOGFORBID,"aac decode queuePeekWaitValue faile");
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
        GJLOG(GJ_LOGFORBID, "AudioConverterNew error:%d",status);
        return NO;
    }
    _destMaxOutSize = 0;
    status = AudioConverterGetProperty(_decodeConvert, kAudioConverterPropertyMaximumOutputPacketSize, &size, &_destMaxOutSize);
    _destMaxOutSize *= AAC_FRAME_PER_PACKET;
    if (_bufferPool != NULL) {
        
        GJRetainBufferPool* pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, YES);
            GJRetainBufferPoolFree(pool);
        });
        _bufferPool = NULL;
    }
    GJRetainBufferPoolCreate(&_bufferPool, _destMaxOutSize,true,R_GJPCMFrameMalloc,GNULL);
    
    AudioConverterGetProperty(_decodeConvert, kAudioConverterCurrentInputStreamDescription, &size, &_sourceFormat);
    
    AudioConverterGetProperty(_decodeConvert, kAudioConverterCurrentOutputStreamDescription, &size, &_destFormat);
    
//    [self performSelectorInBackground:@selector(_converterStart) withObject:nil];
    dispatch_async(_decodeQueue, ^{
        [self _converterStart];
    });
    return YES;
}


-(void)_converterStart{
    GJLOG(GJ_LOGDEBUG, "_converterStart");

    AudioStreamPacketDescription packetDesc;
    AudioBufferList outCacheBufferList;
    while (_running) {
        memset(&packetDesc, 0, sizeof(packetDesc));
        memset(&outCacheBufferList, 0, sizeof(AudioBufferList));
        
        R_GJPCMFrame* frame = (R_GJPCMFrame*)GJRetainBufferPoolGetData(_bufferPool);
        outCacheBufferList.mNumberBuffers = 1;
        outCacheBufferList.mBuffers[0].mNumberChannels = 1;
        outCacheBufferList.mBuffers[0].mData = frame->retain.data;
        outCacheBufferList.mBuffers[0].mDataByteSize = AAC_FRAME_PER_PACKET * _destFormat.mBytesPerPacket;
        UInt32 numPackets = AAC_FRAME_PER_PACKET;

        OSStatus status = AudioConverterFillComplexBuffer(_decodeConvert, decodeInputDataProc, (__bridge void*)self, &numPackets, &outCacheBufferList, &packetDesc);
        if (status != noErr && status != -1) {
            retainBufferUnRetain(&frame->retain);
            queueEnablePop(_resumeQueue, GTrue);
            char* codeChar = (char*)&status;
            if (_running) {
                GJLOG(GJ_LOGFORBID, "AudioConverterFillComplexBufferError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
            }else{
                _running = GFalse;
                GJLOG(GJ_LOGDEBUG,"停止导致解码错误:%p",self);
            }
            break;
        }
        
        frame->retain.size = _destFormat.mBytesPerPacket*numPackets;
        frame->pts = _currentPts;
        frame->dts = _currentPts;
        _currentPts = -1;
        self.decodeCallback(frame);
        retainBufferUnRetain(&frame->retain);
    }
}

-(void)dealloc{
    AudioConverterDispose(_decodeConvert);
    if (_prePacket) {
        retainBufferUnRetain(&_prePacket->retain);
    }
    if (_bufferPool) {
        GJRetainBufferPool* pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, YES);
            GJRetainBufferPoolFree(pool);
        });
    }
    if (_resumeQueue) {
        queueFree(&(_resumeQueue));
    }
    GJLOG(GJ_LOGDEBUG, "gjpcmdecodeformaac delloc");
}

#pragma mark - mutex

@end
