//
//  GJPCMDecodeFromAAC.m
//  视频录制
//
//  Created by tongguan on 16/1/8.
//  Copyright © 2016年 未成年大叔. All rights reserved.
//


#import "GJPCMDecodeFromAAC.h"
#import "GJDebug.h"
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
            _sourceFormatDescription = *sourceDescription;
        }else{
            _sourceFormatDescription = [GJPCMDecodeFromAAC defaultSourceFormateDescription];
        }
        
        if (destDescription != NULL) {
            _destFormatDescription = *destDescription;
        }else{
            _destFormatDescription = [GJPCMDecodeFromAAC defaultDestFormatDescription];
        }
        [self initQueue];
    }
    return self;
}


- (instancetype)init
{
    AudioStreamBasicDescription dest = [GJPCMDecodeFromAAC defaultDestFormatDescription];
    AudioStreamBasicDescription sour = [GJPCMDecodeFromAAC defaultSourceFormateDescription];
    return [self initWithDestDescription:&dest SourceDescription:&sour];
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
        ioData->mBuffers[0].mNumberChannels = decode->_sourceFormatDescription.mChannelsPerFrame;
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
    } ;
}

#define AAC_FRAME_PER_PACKET 1024


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
    _destMaxOutSize *= AAC_FRAME_PER_PACKET;
    if (_bufferPool) {
        GJRetainBufferPoolCleanAndFree(&_bufferPool);
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
    AudioBufferList outCacheBufferList;
    UInt32 numPackets = AAC_FRAME_PER_PACKET;
    while (_isRunning) {
        memset(&packetDesc, 0, sizeof(packetDesc));
        memset(&outCacheBufferList, 0, sizeof(AudioBufferList));
        
        GJRetainBuffer* buffer = GJRetainBufferPoolGetData(_bufferPool);
        outCacheBufferList.mNumberBuffers = 1;
        outCacheBufferList.mBuffers[0].mNumberChannels = 1;
        outCacheBufferList.mBuffers[0].mData = buffer->data;
        outCacheBufferList.mBuffers[0].mDataByteSize = AAC_FRAME_PER_PACKET * _destFormatDescription.mBytesPerPacket;
        
        OSStatus status = AudioConverterFillComplexBuffer(_decodeConvert, encodeInputDataProc, (__bridge void*)self, &numPackets, &outCacheBufferList, &packetDesc);
        // assert(!status);
        if (status != noErr || status == -1) {
            
            retainBufferUnRetain(buffer);
            char* codeChar = (char*)&status;
            GJLOG(@"AudioConverterFillComplexBufferError：%c%c%c%c CODE:%d",codeChar[3],codeChar[2],codeChar[1],codeChar[0],status);
            break;
        }
        
        buffer->size = _destFormatDescription.mBytesPerPacket*numPackets;
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

    NSLog(@"GJPCMDecodeFromAAC dealloc");
}

#pragma mark - mutex

@end
