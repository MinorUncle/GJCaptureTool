//
//  GJH264Decoder.m
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import "GJH264Decoder.h"
#import "GJLog.h"
#import "sps_decode.h"
@interface GJH264Decoder () {
    dispatch_queue_t _decodeQueue; //解码线程在子线程，主要为了避免decodeBuffer：阻塞，节省时间去接收数据
    NSData* _spsData;
    NSData* _ppsData;
    BOOL _isRunning;
    GJQueue* _inputQueue;
}
@property (nonatomic) VTDecompressionSessionRef decompressionSession;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) BOOL                        shouldRestart;

@end
@implementation     GJH264Decoder
inline static GVoid cvImagereleaseCallBack(GJRetainBuffer *buffer, GHandle userData) {
    CVImageBufferRef image = ((CVImageBufferRef *) R_BufferStart(buffer))[0];
    CVPixelBufferRelease(image);
}
- (instancetype)init {
    self = [super init];
    if (self) {
        //        _outPutImageFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        _outPutImageFormat = kCVPixelFormatType_32BGRA;
        GJRetainBufferPoolCreate(&_bufferPool, sizeof(CVPixelBufferRef), GTrue, R_GJPixelFrameMalloc, cvImagereleaseCallBack, GNULL);
        _isRunning= NO;
        _decodeQueue       = dispatch_queue_create("videoDecodeQueue", DISPATCH_QUEUE_SERIAL);
        queueCreate(&_inputQueue, 20, YES, YES);
    }
    return self;
}
- (void)dealloc {
    GJRetainBufferPool *temPool = _bufferPool;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        GJRetainBufferPoolClean(temPool, GTrue);
        GJRetainBufferPoolFree(temPool);
    });
}
- (void)createDecompSession {
    if (_decompressionSession != nil) {
        VTDecompressionSessionInvalidate(_decompressionSession);
    }
    _shouldRestart = NO;
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decodeOutputCallback;

    callBackRecord.decompressionOutputRefCon = (__bridge void *) self;

    NSDictionary *destinationImageBufferAttributes = @{(id) kCVPixelBufferOpenGLESCompatibilityKey : @YES,
                                                       (id) kCVPixelBufferPixelFormatTypeKey : @(_outPutImageFormat) };
    //使用UIImageView播放时可以设置这个
    //    NSDictionary *destinationImageBufferAttributes =[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO],(id)kCVPixelBufferOpenGLESCompatibilityKey,[NSNumber numberWithInt:kCVPixelFormatType_32BGRA],(id)kCVPixelBufferPixelFormatTypeKey,nil];

    OSStatus status = VTDecompressionSessionCreate(NULL,
                                                   _formatDesc,
                                                   NULL,
                                                   (__bridge CFDictionaryRef)(destinationImageBufferAttributes),
                                                   &callBackRecord,
                                                   &_decompressionSession);
    NSLog(@"Video Decompression Session Create: %@  code:%d  thread:%@", (status == noErr) ? @"successful!" : @"failed...", (int) status, [NSThread currentThread]);
}

void decodeOutputCallback(
    void *            decompressionOutputRefCon,
    void *            sourceFrameRefCon,
    OSStatus          status,
    VTDecodeInfoFlags infoFlags,
    CVImageBufferRef  imageBuffer,
    CMTime            presentationTimeStamp,
    CMTime            presentationDuration) {
    //    NSLog(@"decodeOutputCallback:%@",[NSThread currentThread]);

    if (status != 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "解码error1:%d", (int) status);
        return;
    }
    GTime pts = GTimeMake(presentationTimeStamp.value, presentationTimeStamp.timescale);
    GTime  dts = GTimeMake((GInt64)sourceFrameRefCon, 1000);
    GJLOGFREQ("decode packet output pts:%lld", pts.value);

    GJH264Decoder *decoder = (__bridge GJH264Decoder *) (decompressionOutputRefCon);

    R_GJPixelFrame *frame = (R_GJPixelFrame *) GJRetainBufferPoolGetData(decoder.bufferPool);
    frame->height         = (GInt32) CVPixelBufferGetHeight(imageBuffer);
    frame->width          = (GInt32) CVPixelBufferGetWidth(imageBuffer);
    frame->pts            = pts;
    frame->dts            = dts;
    frame->type           = CVPixelBufferGetPixelFormatType(imageBuffer);
    CVPixelBufferRetain(imageBuffer);
    ((CVImageBufferRef *) R_BufferStart(&frame->retain))[0] = imageBuffer;

    //    printf("after decode pts:%lld ,dts:%ld\n",pts,dts);
    decoder.completeCallback(frame);
    R_BufferUnRetain(&frame->retain);
}

- (uint8_t *)startCodeIndex:(uint8_t *)sour size:(long)size codeSize:(uint8_t *)codeSize {
    uint8_t *codeIndex = sour;
    while (codeIndex < sour + size - 4) {
        if (codeIndex[0] == 0 && codeIndex[1] == 0 && codeIndex[2] == 0 && codeIndex[3] == 1) {
            *codeSize = 4;
            break;
        } else if (codeIndex[0] == 0 && codeIndex[1] == 0 && codeIndex[2] == 1) {
            *codeSize = 3;
            break;
        }
        codeIndex++;
    }
    if (codeIndex == sour + size - 4) {
        codeIndex = sour + size;
    }
    return codeIndex;
}
-(BOOL)startDecode{
    if (_isRunning) {
        GJAssert(0, "重复开始");
        return NO;
    }
    _isRunning = YES;
    queueEnablePop(_inputQueue, GTrue);

    dispatch_async(_decodeQueue, ^{
        R_GJPacket* packet;
        while (_isRunning && queuePop(_inputQueue, (GHandle*)&packet, GINT32_MAX)) {
            [self _decodePacket:packet];
        }
    });
    return YES;
}
-(void)stopDecode{
    _isRunning = NO;
    queueEnablePop(_inputQueue, GFalse);
    queueBroadcastPop(_inputQueue);
    GInt32 length = 0;
    queueClean(_inputQueue, GNULL, &length);
    if (length > 0) {
        GHandle* buffer = malloc(sizeof(GHandle)*length);
        queueClean(_inputQueue, buffer, &length);
        for (int i = 0; i<length; i++) {
            R_BufferUnRetain((GJRetainBuffer*)(buffer[i]));
        }
        free(buffer);
    }
}
- (void)decodePacket:(R_GJPacket *)packet {
    R_BufferRetain(&packet->retain);
    if (!_isRunning || !queuePush(_inputQueue, packet, 0)) {
        R_BufferUnRetain(&packet->retain);
    }
}
- (void)_decodePacket:(R_GJPacket *)packet {
    OSStatus          status;
    long              blockLength  = 0;
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef  blockBuffer  = NULL;

//    static GInt32 index = 0;
//    index++;
//    GJLOG(DEFAULT_LOG,GJ_LOGDEBUG,"receive encode video index:%d size:%lld:",index-2, packet->dataSize-packet->dataOffset);
//    GJ_LogHexString(GJ_LOGDEBUG, R_BufferStart(&packet->retain)+packet->dataOffset, (GUInt32) 20);
    
    if (packet->flag == GJPacketFlag_KEY && packet->extendDataSize > 0) {
        
        int32_t  spsSize = 0, ppsSize = 0;
        uint8_t *sps = NULL, *pps = NULL, *start;
        start = R_BufferStart(&packet->retain) + packet->extendDataOffset;
        
        if ( (start[4] & 0x1f) == 7 ) {
            spsSize = ntohl(*(uint32_t*)start);
            sps = start + 4;
            if ((start[spsSize + 8] & 0x1f) == 8) {
                memcpy(&ppsSize, spsSize + sps, 4);
                ppsSize = ntohl(*(uint32_t*)(sps + spsSize));
                pps     = sps + spsSize + 4;
            }else{
                GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "包含sps而不包含pps");
            }
        }
        if(sps && pps 
           && (_decompressionSession == nil || memcmp(sps, _spsData.bytes, spsSize) || memcmp(pps, _ppsData.bytes, ppsSize))){
            GJLOG(DEFAULT_LOG,GJ_LOGINFO,"decode sps size:%d:", spsSize);
            GJ_LogHexString(GJ_LOGINFO, sps, (GUInt32) spsSize);
            GJLOG(DEFAULT_LOG,GJ_LOGINFO,"decode pps size:%d:", ppsSize);
            GJ_LogHexString(GJ_LOGINFO, pps, (GUInt32) ppsSize);
            
            uint8_t *parameterSetPointers[2] = {sps, pps};
            size_t   parameterSetSizes[2]    = {spsSize, ppsSize};
            
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                         (const uint8_t *const *) parameterSetPointers,
                                                                         parameterSetSizes, 4,
                                                                         &_formatDesc);
#if 0
            FourCharCode re = CMVideoFormatDescriptionGetCodecType(desc);
            
            char* code = (char*)&re;
            NSLog(@"code:%c %c %c %c \n",code[3],code[2],code[1],code[0]);
            CFArrayRef arr = CMVideoFormatDescriptionGetExtensionKeysCommonWithImageBuffers();
            signed long count = CFArrayGetCount(arr);
            for (int i = 0; i<count; i++) {
                CFPropertyListRef  list = CMFormatDescriptionGetExtension(desc, CFArrayGetValueAtIndex(arr, i));
                NSLog(@"key:%@,%@",CFArrayGetValueAtIndex(arr, i),list);
            }
#endif
            
            GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "reCreate decoder ,format:%p", _formatDesc);
            [self createDecompSession];
            if (_decompressionSession) {
                _spsData = [NSData dataWithBytes:sps length:spsSize];
                _ppsData = [NSData dataWithBytes:pps length:ppsSize];
            }else{
                GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "解码器创建失败");

            }
        }
    } else {
        if (_decompressionSession == NULL) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "解码器为空，且缺少关键帧，丢帧");
            goto ERROR;
        }
    }

    if (packet->dataSize > 0) {
#ifdef DEBUG
//        static GInt32 index = 0;
//        GJLOG(DEFAULT_LOG,GJ_LOGDEBUG,"decode video index:%d size:%d:",index++, packet->dataSize);
//        GJ_LogHexString(GJ_LOGDEBUG, R_BufferStart(&packet->retain)+packet->dataOffset+packet->dataSize-20, (GUInt32) 20);
#endif
        blockLength = (int) (packet->dataSize);
        void *data  = packet->dataOffset + R_BufferStart(&packet->retain);

        //        uint32_t dataLength32 = htonl (blockLength - 4);
        //        memcpy (data, &dataLength32, sizeof (uint32_t));
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,
                                                    blockLength,
                                                    kCFAllocatorNull, NULL,
                                                    0,
                                                    blockLength,
                                                    0, &blockBuffer);

        if (status == noErr) {
            const size_t       sampleSize = blockLength;
            CMSampleTimingInfo timingInfo;
            timingInfo.decodeTimeStamp       = kCMTimeInvalid;
            timingInfo.duration              = kCMTimeInvalid;
            timingInfo.presentationTimeStamp = CMTimeMake(packet->pts.value, packet->pts.scale);
            status                           = CMSampleBufferCreate(kCFAllocatorDefault,
                                          blockBuffer, true, NULL, NULL,
                                          _formatDesc, 1, 1, &timingInfo, 1,
                                          &sampleSize, &sampleBuffer);

            if (status != 0) {
                GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "CMSampleBufferCreate：%d", status);
                goto ERROR;
            }
        } else {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "CMBlockBufferCreateWithMemoryBlock error:%d", status);
            goto ERROR;
        }

    RETRY : {
        CFArrayRef             attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef dict        = (CFMutableDictionaryRef) CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);

        //                status = CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, pts);
        //
        //                assert(status == 0);
        VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
        VTDecodeInfoFlags  flagOut;
        GLong              dts    = packet->dts.value*1000/packet->dts.scale;
        OSStatus           status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags, (GVoid *) dts, &flagOut);
        if (status < 0) {
            if (kVTInvalidSessionErr == status) {
                VTDecompressionSessionInvalidate(_decompressionSession);
                _decompressionSession = nil;
                GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "解码错误  kVTInvalidSessionErr");
                [self createDecompSession];
                goto RETRY;
            } else {
                GJLOG(DEFAULT_LOG, GJ_LOGERROR, "解码错误0：%d  ,format:%p", status, _formatDesc);
            }
            //                    [self createDecompSession];
            //                    status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags,&sampleBuffer, &flagOut);
            //                    if (status < 0) {
            //                        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "解码错误：%d  丢帧",status);
            //                        _shouldRestart = YES;
            //                    }
        }

        CFRelease(sampleBuffer);
        CFRelease(blockBuffer);
    }
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "帧没有pp");
    }

ERROR:
    return;
}

//解码
//- (void) render:(CMSampleBufferRef)sampleBuffer
//{
//    VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
//    VTDecodeInfoFlags flagOut;
//    OSStatus status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags,&sampleBuffer, &flagOut);
//    if (status < 0) {
//        GJPrintf("解码错误error:%d\n",status);
//        _shouldRestart = YES;
//    }
//}
NSString *const naluTypesStrings[] =
    {
        @"0: Unspecified (non-VCL)",
        @"1: Coded slice of a non-IDR picture (VCL)", // P frame
        @"2: Coded slice data partition A (VCL)",
        @"3: Coded slice data partition B (VCL)",
        @"4: Coded slice data partition C (VCL)",
        @"5: Coded slice of an IDR picture (VCL)", // I frame
        @"6: Supplemental enhancement information (SEI) (non-VCL)",
        @"7: Sequence parameter set (non-VCL)", // SPS parameter
        @"8: Picture parameter set (non-VCL)",  // PPS parameter
        @"9: Access unit delimiter (non-VCL)",
        @"10: End of sequence (non-VCL)",
        @"11: End of stream (non-VCL)",
        @"12: Filler data (non-VCL)",
        @"13: Sequence parameter set extension (non-VCL)",
        @"14: Prefix NAL unit (non-VCL)",
        @"15: Subset sequence parameter set (non-VCL)",
        @"16: Reserved (non-VCL)",
        @"17: Reserved (non-VCL)",
        @"18: Reserved (non-VCL)",
        @"19: Coded slice of an auxiliary coded picture without partitioning (non-VCL)",
        @"20: Coded slice extension (non-VCL)",
        @"21: Coded slice extension for depth view components (non-VCL)",
        @"22: Reserved (non-VCL)",
        @"23: Reserved (non-VCL)",
        @"24: STAP-A Single-time aggregation packet (non-VCL)",
        @"25: STAP-B Single-time aggregation packet (non-VCL)",
        @"26: MTAP16 Multi-time aggregation packet (non-VCL)",
        @"27: MTAP24 Multi-time aggregation packet (non-VCL)",
        @"28: FU-A Fragmentation unit (non-VCL)",
        @"29: FU-B Fragmentation unit (non-VCL)",
        @"30: Unspecified (non-VCL)",
        @"31: Unspecified (non-VCL)",
};

@end
