//
//  PCMDecodeFromAAC.m
//  视频录制
//
//  Created by tongguan on 16/1/8.
//  Copyright © 2016年 未成年大叔. All rights reserved.
//


#import "PCMDecodeFromAAC.h"
#import "GJDebug.h"
#import "GJRetainBufferPool.h"
@interface PCMDecodeFromAAC ()
{
    AudioConverterRef _decodeConvert;
    GJRetainBufferPool* _bufferPool;
    GJQueue* _resumeQueue;
    AudioStreamPacketDescription _inPacketDescript;
    BOOL _isRunning;//状态，是否运行
    int _sourceMaxLenth;
    dispatch_queue_t _decodeQueue;
    UInt32 _outputDataPacketCount; //转码出去包的个数

    GJRetainBuffer* _preRetainBuffer;
}
@property(nonatomic,assign)AudioBufferList* outCacheBufferList;

@end

@implementation PCMDecodeFromAAC
- (instancetype)initWithDestDescription:(AudioStreamBasicDescription*)destDescription SourceDescription:(AudioStreamBasicDescription*)sourceDescription sourceMaxBufferLenth:(int)maxLenth;
{
    self = [super init];
    if (self) {
        
        if (sourceDescription != NULL) {
            _sourceFormatDescription = *sourceDescription;
            _sourceMaxLenth = maxLenth;
        }else{
            [self initDefaultSourceFormateDescription];
        }
        
        if (destDescription != NULL) {
            _destFormatDescription = *destDescription;
        }else{
            [self initDefaultDestFormatDescription];
        }
        
        [self initQueue];
    }
    return self;
}


- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initDefaultDestFormatDescription];
        [self initDefaultSourceFormateDescription];
        queueCreate(&_resumeQueue, 10,true,false);
        _sourceMaxLenth = _outputDataPacketCount * _destFormatDescription.mBytesPerPacket;
        [self initQueue];
    }
    return self;
}
-(void)initQueue{
    _outputDataPacketCount = 1024;
    _decodeQueue = dispatch_queue_create("audioDecodeQueue", DISPATCH_QUEUE_CONCURRENT);
}
-(void)initDefaultSourceFormateDescription{
    _sourceMaxLenth = 6000;
    
    memset(&_sourceFormatDescription, 0, sizeof(_sourceFormatDescription));
    _sourceFormatDescription.mChannelsPerFrame = 1;
    _sourceFormatDescription.mFramesPerPacket = 1024;
    _sourceFormatDescription.mSampleRate = 44100;
    _sourceFormatDescription.mFormatID = kAudioFormatMPEG4AAC;  //aac
}
-(void)initDefaultDestFormatDescription{
    memset(&_destFormatDescription, 0, sizeof(_destFormatDescription));
    _destFormatDescription.mChannelsPerFrame = 1;
    _destFormatDescription.mSampleRate = 44100;
    _destFormatDescription.mFormatID = kAudioFormatLinearPCM; //PCM
    _destFormatDescription.mBitsPerChannel = 16;
    _destFormatDescription.mBytesPerPacket = _destFormatDescription.mBytesPerFrame =_destFormatDescription.mChannelsPerFrame *  _destFormatDescription.mBitsPerChannel;
    _destFormatDescription.mFramesPerPacket = 1;
    _destFormatDescription.mFormatFlags = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
}

//编码输入
static OSStatus encodeInputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData,AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{ ///< style="font-family: Arial, Helvetica, sans-serif;">AudioConverterFillComplexBuffer 编码过程中，会要求这个函数来填充输入数据，也就是原始PCM数据</span>
   
    PCMDecodeFromAAC* decode =(__bridge PCMDecodeFromAAC*)inUserData;
    
    if (decode->_preRetainBuffer) {
        retainBufferUnRetain(decode->_preRetainBuffer);
        decode->_preRetainBuffer = NULL;
    }
    GJQueue* param =   decode->_resumeQueue;
    GJRetainBuffer* retainBuffer;
    AudioStreamPacketDescription* description = (AudioStreamPacketDescription*)&(decode->_inPacketDescript);

    
    if (queuePop(param,(void**)&retainBuffer,1000)) {
        ioData->mBuffers[0].mData = (uint8_t*)retainBuffer->data+7;
        ioData->mBuffers[0].mNumberChannels = decode->_sourceFormatDescription.mChannelsPerFrame;
        ioData->mBuffers[0].mDataByteSize = retainBuffer->size-7;
        *ioNumberDataPackets = 1;
        description->mDataByteSize = ioData->mBuffers[0].mDataByteSize ;
        description->mStartOffset = 0;
        description->mVariableFramesInPacket = 0;
        decode->_preRetainBuffer = retainBuffer;
    }else{
        *ioNumberDataPackets = 0;
        return -1;
    }
    
    if (outDataPacketDescription) {

        outDataPacketDescription[0] = description;
    }
    
    return noErr;
}

-(void)decodeBuffer:(GJRetainBuffer*)audioBuffer packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins{
    
    retainBufferRetain(audioBuffer);
    queuePush(_resumeQueue, audioBuffer,1000);
    if (_decodeConvert == NULL) {
        [self _createEncodeConverter];
    }
}

-(AudioBufferList *)outCacheBufferList{
    if (_outCacheBufferList == nil) {
        _outCacheBufferList = (AudioBufferList*)malloc(sizeof(AudioBufferList));
        
        _outCacheBufferList->mNumberBuffers = 1;
        _outCacheBufferList->mBuffers[0].mNumberChannels = 1;
        _outCacheBufferList->mBuffers[0].mData = (void*)malloc(_outputDataPacketCount * _destFormatDescription.mBytesPerPacket);
        _outCacheBufferList->mBuffers[0].mDataByteSize = _outputDataPacketCount * _destFormatDescription.mBytesPerPacket;
    }
    return _outCacheBufferList;
}


-(BOOL)_createEncodeConverter{
    if (_decodeConvert) {
        AudioConverterDispose(_decodeConvert);
    }
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_destFormatDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_sourceFormatDescription);
    

    OSStatus status = AudioConverterNew(&_sourceFormatDescription, &_destFormatDescription, &_decodeConvert);
    assert(!status);
    GJLOG(@"AudioConverterNewSpecific success");

    _destMaxOutSize = 0;
    status = AudioConverterGetProperty(_decodeConvert, kAudioConverterPropertyMaximumOutputPacketSize, &size, &_destMaxOutSize);
    assert(!status);
    _destMaxOutSize *= _outputDataPacketCount;
    if (_bufferPool) {
        GJRetainBufferPoolRelease(&_bufferPool);
    }
    GJRetainBufferPoolCreate(&_bufferPool, _destMaxOutSize,true);
    
    AudioConverterGetProperty(_decodeConvert, kAudioConverterCurrentInputStreamDescription, &size, &_sourceFormatDescription);
    
    AudioConverterGetProperty(_decodeConvert, kAudioConverterCurrentOutputStreamDescription, &size, &_destFormatDescription);
    
//    [self performSelectorInBackground:@selector(_converterStart) withObject:nil];
    dispatch_async(_decodeQueue, ^{
        [self _converterStart];
    });
    return YES;
}


-(void)_converterStart{
    _isRunning = YES;
    AudioStreamPacketDescription packetDesc;
    while (_isRunning) {
        memset(&packetDesc, 0, sizeof(packetDesc));

        self.outCacheBufferList->mBuffers[0].mDataByteSize = _outputDataPacketCount * _destFormatDescription.mBytesPerPacket;
        OSStatus status = AudioConverterFillComplexBuffer(_decodeConvert, encodeInputDataProc, (__bridge void*)self, &_outputDataPacketCount, self.outCacheBufferList, &packetDesc);
        // assert(!status);
        if (status != noErr || status == -1) {
            char* codeChar = (char*)&status;
            GJLOG(@"AudioConverterFillComplexBufferError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
            break;
        }
        
        if ([self.delegate respondsToSelector:@selector(pcmDecode:completeBuffer:packetDesc:)]) {
             GJRetainBuffer* buffer = GJRetainBufferPoolGetData(_bufferPool);
            buffer->size = _destFormatDescription.mBytesPerPacket*_outputDataPacketCount;
            memcpy(buffer->data, _outCacheBufferList->mBuffers[0].mData, _outCacheBufferList->mBuffers[0].mDataByteSize);
            AudioStreamPacketDescription desc = {0,0,buffer->size};
            [self.delegate pcmDecode:self completeBuffer:buffer packetDesc:&desc];
        }
    }
}

-(void)dealloc{
    _isRunning = NO;
    AudioConverterDispose(_decodeConvert);
    if (_outCacheBufferList) {
        if (_outCacheBufferList->mBuffers[0].mData) {
            free(_outCacheBufferList->mBuffers[0].mData);
        }
        free(_outCacheBufferList);
    }
    if (_preRetainBuffer) {
        retainBufferUnRetain(_preRetainBuffer);
        _preRetainBuffer = NULL;
    }
    NSLog(@"PCMDecodeFromAAC dealloc");
}

#pragma mark - mutex

@end
