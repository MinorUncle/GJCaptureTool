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
#import "GJUtil.h"
#import "libavformat/avformat.h"
#import "GJSignal.h"
#import "GJBufferPool.h"
#import "GJAudioAlignment.h"
#define AAC_FRAME_PER_PACKET 1024

@interface GJPCMDecodeFromAAC () {
    AudioConverterRef   _decodeConvert;
    GJRetainBufferPool *_bufferPool;
    GJQueue *           _resumeQueue;
    int                 _sourceMaxLenth;
    dispatch_queue_t    _decodeQueue;

    R_GJPacket *                 _prePacket;
    AudioStreamPacketDescription tPacketDesc;
    ASC                          _asc;
    GJSignal *                   _stopFinshSignal;

    GJAudioAlignmentContext*     _alignmentContext;
}

@property (nonatomic, assign) int64_t currentPts;
@property (nonatomic, assign) BOOL    running;

@end
static int startCount;
static int stopCount;

@implementation GJPCMDecodeFromAAC
- (BOOL)createCorverWithDescription:(AudioStreamBasicDescription)destDescription SourceDescription:(AudioStreamBasicDescription)sourceDescription {
    _sourceFormat       = sourceDescription;
    _destFormat         = destDescription;
    
    if (_alignmentContext) {
        audioAlignmentDelloc(&_alignmentContext);
    }
    GJAudioFormat format = {0};
    format.mBitsPerChannel = _destFormat.mBitsPerChannel;
    format.mChannelsPerFrame = _destFormat.mChannelsPerFrame;
    format.mSampleRate = _destFormat.mSampleRate;
    format.mFramePerPacket = _destFormat.mFramesPerPacket;
    format.mType = GJAudioType_PCM;
    audioAlignmentAlloc(&_alignmentContext, &format);
    
    __block BOOL result = NO;
    if (1) {
        result = [self _createEncodeConverter];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self _createEncodeConverter];
        });
    }
    return result;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self initQueue];
    }
    return self;
}
- (void)initQueue {
    _decodeQueue = dispatch_queue_create("audioDecodeQueue", DISPATCH_QUEUE_SERIAL);
    queueCreate(&_resumeQueue, 60, true, GFalse);
    //    queueSetDebugLeval(_resumeQueue, GJ_LOGALL);
    signalCreate(&_stopFinshSignal);
}
+ (AudioStreamBasicDescription)defaultSourceFormateDescription {
    AudioStreamBasicDescription format = {0};
    format.mChannelsPerFrame           = 1;
    format.mFramesPerPacket            = 1024;
    format.mSampleRate                 = 44100;
    format.mFormatID                   = kAudioFormatMPEG4AAC; //aac
    return format;
}
+ (AudioStreamBasicDescription)defaultDestFormatDescription {
    AudioStreamBasicDescription format = {0};
    format.mChannelsPerFrame           = 1;
    format.mSampleRate                 = 44100;
    format.mFormatID                   = kAudioFormatLinearPCM; //PCM
    format.mBitsPerChannel             = 16;
    format.mBytesPerPacket = format.mBytesPerFrame = format.mChannelsPerFrame * format.mBitsPerChannel;
    format.mFramesPerPacket                        = 1;
    format.mFormatFlags                            = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
    return format;
}

- (void)start {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "AACDecode Start:%p", self);
    _running = YES;
    queueEnablePop(_resumeQueue, GTrue);
    queueEnablePush(_resumeQueue, GTrue);
    startCount++;
}
- (void)stop {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "AACDecode stop:%p", self);
    _running = NO;
    stopCount++;
    queueEnablePop(_resumeQueue, GFalse);
    queueEnablePush(_resumeQueue, GFalse);
    queueBroadcastPop(_resumeQueue);

    signalWait(_stopFinshSignal, INT_MAX);

    if (_decodeConvert) {
        AudioConverterDispose(_decodeConvert);
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "AudioConverterDispose");
        _decodeConvert = nil;
    }

    queueFuncClean(_resumeQueue, R_BufferUnRetainUnTrack);

    if (_prePacket) {
        R_BufferUnRetain(&_prePacket->retain);
        _prePacket = NULL;
    }
}
//编码输入
static OSStatus decodeInputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    GJPCMDecodeFromAAC *decode = (__bridge GJPCMDecodeFromAAC *) inUserData;
    if (decode->_prePacket) {
        R_BufferUnRetain(decode->_prePacket);
        decode->_prePacket = NULL;
    }
    GJQueue *   param  = decode->_resumeQueue;
    R_GJPacket *packet = GNULL;
    if (decode.running && queuePop(param, (void **) &packet, INT_MAX)) {
        if ((packet->flag & GJPacketFlag_AVPacketType) == GJPacketFlag_AVPacketType) {
            AVPacket *avpacket                = ((AVPacket *) R_BufferStart(packet) + packet->extendDataOffset);
            ioData->mBuffers[0].mData         = avpacket->data;
            ioData->mBuffers[0].mDataByteSize = avpacket->size;
        } else {
            ioData->mBuffers[0].mData         = R_BufferStart(packet) + packet->dataOffset;
            ioData->mBuffers[0].mDataByteSize = packet->dataSize;
        }
        ioData->mBuffers[0].mNumberChannels = decode->_sourceFormat.mChannelsPerFrame;
        *ioNumberDataPackets                = 1;
    } else {
        *ioNumberDataPackets = 0;
#ifdef DEBUG
        if (decode.running) {
            assert(0);
        }
#endif
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "decodeInputDataProc 0 faile");
        return -1;
    }

    if (outDataPacketDescription) {
        decode->tPacketDesc.mStartOffset = decode->tPacketDesc.mVariableFramesInPacket = 0;
        decode->tPacketDesc.mDataByteSize                                              = ioData->mBuffers[0].mDataByteSize;
        outDataPacketDescription[0]                                                    = &(decode->tPacketDesc);
    }
    if (decode.currentPts <= 0) {
        decode.currentPts = GTimeMSValue(packet->pts);
    }
    decode->_prePacket = packet;
    return noErr;
}

- (void)decodePacket:(R_GJPacket *)packet {
    if (!_running) {
        return;
    }
    if ((packet->flag & GJPacketFlag_P_AVStreamType) == GJPacketFlag_P_AVStreamType) {
        AVStream *stream = ((AVStream **) (R_BufferStart(packet) + packet->extendDataOffset))[0];
        //        GJAssert(_decodeConvert == GNULL, "待优化");
        AudioStreamBasicDescription s = {0};
        s.mFramesPerPacket            = stream->codecpar->frame_size;
        s.mSampleRate                 = stream->codecpar->sample_rate;
        switch (stream->codecpar->codec_id) {
            case AV_CODEC_ID_AAC:
                s.mFormatID = kAudioFormatMPEG4AAC;
                break;

            default:
                GJAssert(0, "不支持");
                break;
        }
        s.mChannelsPerFrame = stream->codecpar->channels;

        if (_decodeConvert == nil ||
            _sourceFormat.mFramesPerPacket != s.mFramesPerPacket ||
            _sourceFormat.mSampleRate != s.mSampleRate ||
            _sourceFormat.mChannelsPerFrame != s.mChannelsPerFrame ||
            _sourceFormat.mFormatID != s.mFormatID) {
            AudioStreamBasicDescription d = s;
            d.mBitsPerChannel             = 16;
            d.mFormatID                   = kAudioFormatLinearPCM; //PCM
            d.mBytesPerPacket = d.mBytesPerFrame = d.mChannelsPerFrame * d.mBitsPerChannel / 8;
            d.mFramesPerPacket                   = AAC_FRAME_PER_PACKET;
            d.mFormatFlags                       = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
            [self createCorverWithDescription:d SourceDescription:s];
        }
        if (packet->dataSize <= 0) return;
    } else if ((packet->flag & GJPacketFlag_AVPacketType) != GJPacketFlag_AVPacketType) {
        uint8_t *astBuffer = packet->extendDataOffset + R_BufferStart(&packet->retain);
        ASC      asc       = {0};
        int      astLen    = 0;
        if (packet->extendDataSize > 0 && (astLen = readASC(astBuffer, packet->extendDataSize, &asc)) > 0) {
            if (_decodeConvert == nil || memcmp(&asc, &_asc, sizeof(asc)) != 0) {
                if (_decodeConvert) {
                    [self stop];
                }
                _asc                                       = asc;
                int                         sampleRate     = asc.sampleRate;
                uint8_t                     channel        = asc.channelConfig;
                int                         framePerPacket = asc.gas.frameLengthFlag ? 960 : 1024;
                AudioStreamBasicDescription s              = {0};
                s.mFramesPerPacket                         = framePerPacket;
                s.mSampleRate                              = sampleRate;
                s.mFormatID                                = kAudioFormatMPEG4AAC;
                s.mChannelsPerFrame                        = channel;

                AudioStreamBasicDescription d = s;
                d.mBitsPerChannel             = 16;
                d.mFormatID                   = kAudioFormatLinearPCM; //PCM
                d.mBytesPerPacket = d.mBytesPerFrame = d.mChannelsPerFrame * d.mBitsPerChannel / 8;
                d.mFramesPerPacket                   = 1;
                d.mFormatFlags                       = kLinearPCMFormatFlagIsPacked | kLinearPCMFormatFlagIsSignedInteger; // little-endian
                [self createCorverWithDescription:d SourceDescription:s];
            }
        }

        if (packet->dataSize <= 0) {
            return;
        }
    }

    R_BufferRetain(packet);
    if (!queuePush(_resumeQueue, packet, GINT32_MAX)) {
        R_BufferUnRetain(&packet->retain);
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "aac decode to pcm queuePush faile");
    }
}


- (BOOL)_createEncodeConverter {
    if (_decodeConvert) {
        AudioConverterDispose(_decodeConvert);
    }

    if (_sourceFormat.mFormatID <= 0) {

        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "_sourceFormat unknowe");
        return false;
    }
    if (_destFormat.mFormatID <= 0) {
        _destFormat.mSampleRate       = _sourceFormat.mSampleRate;       // 3
        _destFormat.mChannelsPerFrame = _sourceFormat.mChannelsPerFrame; // 4
        _destFormat.mFramesPerPacket  = 1;                               // 7
        _destFormat.mBitsPerChannel   = 16;                              // 5
        _destFormat.mBytesPerFrame    = _destFormat.mChannelsPerFrame * _destFormat.mBitsPerChannel / 8;
        _destFormat.mFramesPerPacket  = _destFormat.mBytesPerFrame * _destFormat.mFramesPerPacket;
        _destFormat.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    }

    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_destFormat);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_sourceFormat);
    OSStatus status = AudioConverterNew(&_sourceFormat, &_destFormat, &_decodeConvert);
    if (status != noErr) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioConverterNew error:%d", status);
        return NO;
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "_createEncodeConverter%p", _decodeConvert);
    }
    _destMaxOutSize = 0;
    status          = AudioConverterGetProperty(_decodeConvert, kAudioConverterPropertyMaximumOutputPacketSize, &size, &_destMaxOutSize);
    _destMaxOutSize *= AAC_FRAME_PER_PACKET;
    if (_bufferPool != NULL) {

        GJRetainBufferPool *pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, YES);
            GJRetainBufferPoolFree(pool);
        });
        _bufferPool = NULL;
    }
    GJRetainBufferPoolCreate(&_bufferPool, _destMaxOutSize, true, R_GJPCMFrameMalloc, GNULL, GNULL);

    AudioConverterGetProperty(_decodeConvert, kAudioConverterCurrentInputStreamDescription, &size, &_sourceFormat);

    AudioConverterGetProperty(_decodeConvert, kAudioConverterCurrentOutputStreamDescription, &size, &_destFormat);

    //    [self performSelectorInBackground:@selector(_converterStart) withObject:nil];
    dispatch_async(_decodeQueue, ^{
        [self _converterStart];
    });
    return YES;
}

- (void)_converterStart {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "_converterStart");

    AudioStreamPacketDescription packetDesc;
    AudioBufferList              outCacheBufferList;
    signalReset(_stopFinshSignal);
    while (_running) {
        memset(&packetDesc, 0, sizeof(packetDesc));
        memset(&outCacheBufferList, 0, sizeof(AudioBufferList));

        R_GJPCMFrame *frame                            = (R_GJPCMFrame *) GJRetainBufferPoolGetData(_bufferPool);
        outCacheBufferList.mNumberBuffers              = 1;
        outCacheBufferList.mBuffers[0].mNumberChannels = 1;
        outCacheBufferList.mBuffers[0].mData           = R_BufferStart(&frame->retain);
        outCacheBufferList.mBuffers[0].mDataByteSize   = AAC_FRAME_PER_PACKET * _destFormat.mBytesPerPacket;
        UInt32   numPackets                            = AAC_FRAME_PER_PACKET;
        OSStatus status                                = AudioConverterFillComplexBuffer(_decodeConvert, decodeInputDataProc, (__bridge void *) self, &numPackets, &outCacheBufferList, &packetDesc);
        if (status != noErr && numPackets == 0) {
            R_BufferUnRetain(&frame->retain);
            queueEnablePop(_resumeQueue, GTrue);
            char *codeChar = (char *) &status;
            if (_running && status != -1) {
                GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "AudioConverterFillComplexBufferError：%c%c%c%c CODE:%d", codeChar[3], codeChar[2], codeChar[1], codeChar[0], status);
            } else {
                _running = GFalse;
                GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "停止解码:%p", self);
            }
            break;
        }

        R_BufferUseSize(&frame->retain, outCacheBufferList.mBuffers[0].mDataByteSize);
        frame->dts = frame->pts = GTimeMake(_currentPts, 1000);
        
        GTime pts = frame->dts;
        GUInt8* data = R_BufferStart(frame);
        GInt32 dataSize = R_BufferSize(frame);
        GInt32 ret = 0;
        while ((ret = audioAlignmentUpdate(_alignmentContext, data, dataSize, &pts, R_BufferStart(frame))) > 0) {
            //有校正后的填充数据
            frame->dts = frame->pts = pts;
            self.decodeCallback(frame);
            R_BufferUnRetain(&frame->retain);

            frame = (R_GJPCMFrame *) GJRetainBufferPoolGetData(_bufferPool);
            pts = GInvalidTime;
            R_BufferUseSize(&frame->retain, _destMaxOutSize);
            data = GNULL;
            dataSize = 0;
        }
        self.decodeCallback(frame);
        _currentPts = -1;
        R_BufferUnRetain(&frame->retain);
    }
    GJLOG(GNULL, GJ_LOGDEBUG, "signalEmit：%p", _stopFinshSignal);
    signalEmit(_stopFinshSignal);
}

- (void)dealloc {
    AudioConverterDispose(_decodeConvert);
    if (_prePacket) {
        R_BufferUnRetain(&_prePacket->retain);
    }
    if (_bufferPool) {
        GJRetainBufferPool *pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, YES);
            GJRetainBufferPoolFree(pool);
        });
    }
    if (_resumeQueue) {
        queueFree(&(_resumeQueue));
    }
    if (_alignmentContext) {
        audioAlignmentDelloc(&_alignmentContext);
    }
    signalDestory(&_stopFinshSignal);
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "gjpcmdecodeformaac delloc:%p", self);
}

#pragma mark - mutex

@end
