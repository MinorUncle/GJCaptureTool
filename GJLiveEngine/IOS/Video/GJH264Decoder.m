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
#import "libavformat/avformat.h"
#import <UIKit/UIApplication.h>
#define VIDEO_DECODER_CACHE_COUNT 20
@interface GJH264Decoder () {
    dispatch_queue_t _decodeQueue; //解码线程在子线程，主要为了避免decodeBuffer：阻塞，节省时间去接收数据
    NSData* _spsData;
    NSData* _ppsData;
    GJQueue* _inputQueue;
    GJQueue* _gopQueue;
    GBool _isActive;
    GBool _needFlush;
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
        queueCreate(&_inputQueue, VIDEO_DECODER_CACHE_COUNT, YES, GFalse);
        queueCreate(&_gopQueue, 100, YES, GTrue);

        _isActive = [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(receiveNotification:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(receiveNotification:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}
-(void)receiveNotification:(NSNotification*)notic{
//    if ([notic.name isEqualToString:UIApplicationWillResignActiveNotification]) {
//        queueSetMinCacheSize(_inputQueue, VIDEO_DECODER_CACHE_COUNT+1);
//        _isActive = NO;
//    }else if([notic.name isEqualToString:UIApplicationDidBecomeActiveNotification]){
//        queueSetMinCacheSize(_inputQueue, 0);
//        _isActive = YES;
//    }
}
- (void)dealloc {
    queueFree(&_inputQueue);
    GJRetainBufferPool *temPool = _bufferPool;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        GJRetainBufferPoolClean(temPool, GTrue);
        GJRetainBufferPoolFree(temPool);
    });
    [[NSNotificationCenter defaultCenter]removeObserver:self];

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
    if ((GLong)sourceFrameRefCon < 0) {
        return;
    }
    GTime pts = GTimeMake(presentationTimeStamp.value, presentationTimeStamp.timescale);
    GTime  dts = GTimeMake((GInt64)sourceFrameRefCon, 1000);

    GJH264Decoder *decoder = (__bridge GJH264Decoder *) (decompressionOutputRefCon);

    R_GJPixelFrame *frame = (R_GJPixelFrame *) GJRetainBufferPoolGetData(decoder.bufferPool);
    frame->height         = (GInt32) CVPixelBufferGetHeight(imageBuffer);
    frame->width          = (GInt32) CVPixelBufferGetWidth(imageBuffer);
    frame->pts            = pts;
    frame->dts            = dts;
    frame->type           = CVPixelBufferGetPixelFormatType(imageBuffer);
    frame->flag           = kGJFrameFlag_P_CVPixelBuffer;
    CVPixelBufferRetain(imageBuffer);
    ((CVImageBufferRef *) R_BufferStart(&frame->retain))[0] = imageBuffer;

//    static GTime prePts,preDts;
//    GJLOG(GNULL,GJ_LOGINFO,"receive type:video pts:%lld dts:%lld dpts:%lld ddts:%lld", pts.value,dts.value, dts.value - preDts.value,dts.value - preDts.value);
//    preDts = dts;prePts = pts;
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
    queueEnablePop(_gopQueue, GTrue);

    GJLOG(GNULL, GJ_LOGDEBUG, "%p",self);

    dispatch_async(_decodeQueue, ^{
        R_GJPacket* packet;
        while (_isRunning) {
            if( queuePop(_inputQueue, (GHandle*)&packet, GINT32_MAX)){
                [self _decodePacket:packet];
                R_BufferUnRetain(packet);
            }
        }
        GJLOG(GNULL, GJ_LOGDEBUG, "video decode runloop end:%p",self);
    });
    return YES;
}
-(void)stopDecode{
    if (_isRunning) {
        _isRunning = NO;
        queueEnablePop(_inputQueue, GFalse);
        queueBroadcastPop(_inputQueue);
        queueEnablePop(_gopQueue, GFalse);
        queueBroadcastPop(_gopQueue);
        
        queueFuncClean(_inputQueue, R_BufferUnRetainUnTrack);
        queueFuncClean(_gopQueue, R_BufferUnRetainUnTrack);

        
        [self flush];
    }
}

-(void)flush{
    VTDecompressionSessionFinishDelayedFrames(_decompressionSession);
    _needFlush = GTrue;
}

- (void)decodePacket:(R_GJPacket *)packet {
    R_BufferRetain(&packet->retain);
    if (!_isRunning || !queuePush(_inputQueue, packet, GINT32_MAX)) {
        R_BufferUnRetain(&packet->retain);
    }
}

-(void)findInfoWithData:(GUInt8*)start dataSize:(int)dataSize sps:(GUInt8**)pSps spsSize:(int*)pSpsSize pps:(GUInt8**)pPps ppsSize:(int*)pPpsSize{
    int spsSize = 0,ppsSize = 0;
    GUInt8* sps = NULL,*pps = NULL;
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
    }else{
        GInt32 index = 0;
        while (index < dataSize) {
            if ((start[index+4] & 0x1f) == 7) {
                sps = start + index + 4;
                memcpy(&spsSize, start + index, 4);
                spsSize = ntohl(spsSize);
                index += spsSize+4;
            }else if ((start[index+4] & 0x1f) == 8){
                pps = start + index + 4;
                memcpy(&ppsSize, start + index, 4);
                ppsSize = ntohl(ppsSize);
                index += ppsSize+4;
                break;
            }else{
                GUInt32 nalSize = 0;
                memcpy(&nalSize, start + index, 4);
                nalSize = ntohl(nalSize);
                index += nalSize+4;
            }
        }
    }
    *pSps = sps;
    *pPps = pps;
    *pSpsSize = spsSize;
    *pPpsSize = ppsSize;
}

-(void)findInfoWithAVCC:(GUInt8*)avcc dataSize:(int)avccSize sps:(GUInt8**)pSps spsSize:(int*)pSpsSize pps:(GUInt8**)pPps ppsSize:(int*)pPpsSize{
    int spsSize = 0,ppsSize = 0;
    GUInt8* sps = NULL,*pps = NULL;
    if (avccSize > 9 && (avcc[8] & 0x1f) == 7) {
        sps     = avcc + 8;
        spsSize = avcc[6] << 8;
        spsSize |= avcc[7];
        if (avccSize > spsSize + 8 + 3 && (avcc[spsSize + 8 + 3] & 0x1f) == 8) {
            pps     = avcc + 8 + spsSize + 3;
            ppsSize = avcc[8 + spsSize + 1] << 8;
            ppsSize |= avcc[8 + spsSize + 2];
            
            GJAssert(avccSize == 8 + spsSize + 3 + ppsSize, "格式有问题");
            *pSps = sps;
            *pPps = pps;
            *pSpsSize = spsSize;
            *pPpsSize = ppsSize;
            
            GJLOG(DEFAULT_LOG,GJ_LOGDEBUG,"receive decode sps size:%d:", spsSize);
            GJ_LogHexString(GJ_LOGDEBUG, sps, (GUInt32) spsSize);
            GJLOG(DEFAULT_LOG,GJ_LOGDEBUG,"receive decode pps size:%d:", ppsSize);
            GJ_LogHexString(GJ_LOGDEBUG, pps, (GUInt32) ppsSize);
        }
    }
}
-(void)updateSpsPps:(GUInt8*)sps spsSize:(int)spsSize pps:(GUInt8*)pps ppsSize:(int)ppsSize{
    if(sps && pps && (_decompressionSession == nil || memcmp(sps, _spsData.bytes, spsSize) || memcmp(pps, _ppsData.bytes, ppsSize))){
        GJLOG(DEFAULT_LOG,GJ_LOGINFO,"decode sps size:%d:", spsSize);
        GJ_LogHexString(GJ_LOGINFO, sps, (GUInt32) spsSize);
        GJLOG(DEFAULT_LOG,GJ_LOGINFO,"decode pps size:%d:", ppsSize);
        GJ_LogHexString(GJ_LOGINFO, pps, (GUInt32) ppsSize);
        
        uint8_t *parameterSetPointers[2] = {sps, pps};
        size_t   parameterSetSizes[2]    = {spsSize, ppsSize};
        
        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                              (const uint8_t *const *) parameterSetPointers,
                                                                              parameterSetSizes, 4,
                                                                              &_formatDesc);
        if (status != 0) {
            GJAssert(0, "CMVideoFormatDescriptionCreateFromH264ParameterSets error:%d",status);
            return;
        }
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
}

/**
 解码

 @param packet packet description
 @return 返回yes，表示此包可以释放了，false表示解码还需要在此使用，不能释放
 */
- (OSStatus)_decodePacket:(R_GJPacket *)packet {
    long              packetSize  = 0;
    GUInt8*            packetData  = 0;
    AVPacket* pkt = NULL;



    int32_t  spsSize = 0, ppsSize = 0;
    uint8_t *sps = NULL, *pps = NULL;
    GBool isKeyPacket = GFalse;
    if ((packet->flag & GJPacketFlag_AVPacketType) == GJPacketFlag_AVPacketType){
        pkt = ((AVPacket*)(R_BufferStart(packet) + packet->extendDataOffset));
        GInt32 extendDataSize = 0;
        GUInt8* extendData = av_packet_get_side_data(pkt, AV_PKT_DATA_NEW_EXTRADATA, &extendDataSize);
        [self findInfoWithAVCC:extendData dataSize:extendDataSize sps:&sps spsSize:&spsSize pps:&pps ppsSize:&ppsSize];
        if (sps && pps) {
            [self updateSpsPps:sps spsSize:spsSize pps:pps ppsSize:ppsSize];
        }
        packetSize = (int) pkt->size;
        packetData = pkt->data;
        isKeyPacket = (pkt->flags & AV_PKT_FLAG_KEY) == AV_PKT_FLAG_KEY;

    }else if ((packet->flag & GJPacketFlag_P_AVStreamType) == GJPacketFlag_P_AVStreamType) {
        AVStream* stream = ((AVStream**)(R_BufferStart(packet)+packet->extendDataOffset))[0];
        AVCodecParameters *codecpar = stream->codecpar;
        [self findInfoWithAVCC:codecpar->extradata dataSize:codecpar->extradata_size sps:&sps spsSize:&spsSize pps:&pps ppsSize:&ppsSize];
        GJAssert(sps != GNULL && pps != NULL, "没有sps，pps");
        [self updateSpsPps:sps spsSize:spsSize pps:pps ppsSize:ppsSize];
    }
    
    
    if (_decompressionSession == nil) {
        if (!isKeyPacket) {
            GJLOG(GNULL, GJ_LOGWARNING, "解码器没有初始化，且收到的非i帧，丢帧");
            return noErr;
        }else if(_spsData != nil && _ppsData != nil){
            [self createDecompSession];
        }else{
            GJLOG(GNULL, GJ_LOGFORBID, "解码器没有初始化，且收到的i帧，但是没有sps,pps信息，丢帧");
            return noErr;
        }
    }
    
    if (_needFlush) {
        if (!isKeyPacket) {
            GJLOG(GNULL, GJ_LOGWARNING, "解码器刷新了，收到非i帧，丢帧");
            return GTrue;
        }else{
            _needFlush = GFalse;
        }
    }
    if (packetSize > 0) {
        
        if (isKeyPacket) {//刷新gop
            queueFuncClean(_gopQueue, R_BufferUnRetainUnTrack);
        }
        R_BufferRetain(packet);
        if (!queuePush(_gopQueue, packet, 0)) {
            R_BufferUnRetain(packet);
        }
        
        CMSampleBufferRef sampleBuffer = NULL;
        OSStatus status = kVTVideoDecoderMalfunctionErr;
        sampleBuffer = [self createSampleBufferWithData:packetData size:packetSize pts:GTimeMSValue(packet->pts)];
        if (sampleBuffer) {
            status = [self decodeSampleBuffer:sampleBuffer dts:GTimeMSValue(packet->dts) flag:0];
            CFRelease(sampleBuffer);
        }
        
        if (status < 0) {
            if (kVTInvalidSessionErr == status) {
                VTDecompressionSessionWaitForAsynchronousFrames(_decompressionSession);
                VTDecompressionSessionInvalidate(_decompressionSession);
                CFRelease(_decompressionSession);
                _decompressionSession = nil;
                GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "无效解码器，重启解码器，恢复数据");
                [self createDecompSession];
                
                OSStatus oldStatus = noErr;
                if (!isKeyPacket) {//非i帧则需要恢复
                    R_GJPacket* oldPacket = GNULL;
                    GInt32 oldPacketSize = 0;
                    GUInt8* oldPacketData = GNULL;
                    GLong index = 0;
                    oldStatus = kVTVideoDecoderMalfunctionErr;
                    while(queuePeekValue(_gopQueue,index++, (GHandle*)&oldPacket)){
                        AVPacket* oldPkt = ((AVPacket*)(R_BufferStart(oldPacket) + oldPacket->extendDataOffset));
                        oldPacketSize = (int) oldPkt->size;
                        oldPacketData = oldPkt->data;
                                                    
                        if (oldPacketSize>0) {
                            CMSampleBufferRef oldSampleBuffer = NULL;
                            oldSampleBuffer = [self createSampleBufferWithData:oldPacketData size:oldPacketSize pts:GTimeMSValue(oldPacket->pts)];
                            if (oldSampleBuffer) {
                                oldStatus = [self decodeSampleBuffer:oldSampleBuffer dts:-1 flag:kVTDecodeFrame_DoNotOutputFrame];
                                CFRelease(oldSampleBuffer);
                            }
                            if (oldStatus != noErr) {
                                GJLOG(DEFAULT_LOG, GJ_LOGERROR, "恢复gop，gop数据有误， 无法刷新解码器,清除gop,error status：%d", oldStatus);
                                queueFuncClean(_gopQueue, R_BufferUnRetainUnTrack);
                                [self flush];
                                break;
                            }
                        }
                    }
                }
   
            } else  if (status == kVTVideoDecoderMalfunctionErr) {
                if (isKeyPacket) {
                    GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "i帧解码错误，数据格式有问题,会造成丢帧至下一个i帧，status:%d:%p", status, _formatDesc);

                }else{
                    GJLOG(DEFAULT_LOG, GJ_LOGERROR, "非i帧解码错误，需要强制刷新：%d  ,会造成丢帧至下一个i帧，format:%p", status, _formatDesc);
                }
                [self flush];
            }else {
                GJLOG(DEFAULT_LOG, GJ_LOGERROR, "解码错误0：%d  ,format:%p", status, _formatDesc);
            }
        }
    }
    
    return noErr;
ERROR:
    return GFalse;
}
-(CMSampleBufferRef)createSampleBufferWithData:(GUInt8*)packetData size:(GLong)packetSize pts:(GInt64)pts{
    
    //#if MENORY_CHECK  格式检查，针对不规则流
    ////<-----conversion
    //    if (((GUInt16*)packetData)[0] == 0 && packetData[2] == 0 && packetData[3] == 1) {
    
    //        GUInt8* preNal = GNULL;
    //        for (int i = 3; i<packetSize-4; i++) {
    //            if (packetData[i] == 0) {
    //                if (packetData[i+1] == 0) {
    //                    if (packetData[i+2] == 0) {
    //                        if (packetData[i+3] == 1) {
    //                            if (preNal != GNULL) {
    //                                GInt32 nalSize = (GInt32)(packetData + i - preNal);
    //                                nalSize = htonl(nalSize);
    //                                memcpy(preNal-4, &nalSize, 4);
    //                            }
    //                            preNal = packetData + i+4;
    //                            i+=3;//跳过4-1个
    //                        }else if(packetData[i+3] != 0){//3-1
    //                            i+=2;
    //                        }//否则//1-1
    //                    }else if(packetData[i+2] == 1){//匹配成功0x000001，3-1,
    //                        AVPacket* pkt = ((AVPacket*)(R_BufferStart(packet) + packet->extendDataOffset));
    //
    //                        av_grow_packet(pkt,1);
    //
    //                        memmove(packetData+i+1, packetData+i, packetSize-i);
    //                        if (preNal != GNULL) {
    //                            GInt32 nalSize = (GInt32)(packetData + i - preNal);
    //                            nalSize = htonl(nalSize);
    //                            memcpy(preNal-4, &nalSize, 4);
    //                        }
    //                        preNal = packetData + i +4;
    //                        i+=3;
    //                    }else{
    //                        i+=2;
    //                    }
    //                }else{
    //                    i++;
    //                }
    //            }
    //        }
    //        if (preNal) {
    //            GInt32 nalSize = (GInt32)(packetData + packetSize - preNal);
    //            nalSize = htonl(nalSize);
    //            memcpy(preNal-4, &nalSize, 4);
    //        }
    //    }
    ///->>>
    
    //格式检查，针对不规则流
#ifdef DEBUG
    int32_t unitSize = 0;
    uint8_t* current;
    long totalSize = 0;
    current = packetData;
    while (totalSize < packetSize) {
        memcpy(&unitSize, current, 4);
        unitSize = ntohl(unitSize);
        totalSize += unitSize+4;
        current += unitSize+4;
    }
    assert(totalSize == packetSize);

//    if (totalSize != packetSize) {
//        NSLog(@"size error");
//    }
#endif
    
    
    OSStatus status;
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef  blockBuffer  = NULL;
    
    //        uint32_t dataLength32 = htonl (blockLength - 4);
    //        memcpy (data, &dataLength32, sizeof (uint32_t));
    status = CMBlockBufferCreateWithMemoryBlock(NULL, packetData,
                                                packetSize,
                                                kCFAllocatorNull, NULL,
                                                0,
                                                packetSize,
                                                0, &blockBuffer);
    
    if (status == noErr) {
        const size_t       sampleSize = packetSize;
        CMSampleTimingInfo timingInfo;
        timingInfo.decodeTimeStamp       = kCMTimeInvalid;
        timingInfo.duration              = kCMTimeInvalid;
        timingInfo.presentationTimeStamp = CMTimeMake(pts, 1000);
        status                           = CMSampleBufferCreate(kCFAllocatorDefault,
                                                                blockBuffer, true, NULL, NULL,
                                                                _formatDesc, 1, 1, &timingInfo, 1,
                                                                &sampleSize, &sampleBuffer);
        
        if (status != 0) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "CMSampleBufferCreate：%d", status);
        }
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "CMBlockBufferCreateWithMemoryBlock error:%d", status);
    }
    CFRelease(blockBuffer);

    return sampleBuffer;
}

-(OSStatus)decodeSampleBuffer:(CMSampleBufferRef)sampleBuffer dts:(GLong)dts flag:(VTDecodeFrameFlags)flag{
    
    CFArrayRef             attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFMutableDictionaryRef dict        = (CFMutableDictionaryRef) CFArrayGetValueAtIndex(attachments, 0);
    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    
    //                status = CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, pts);
    //
    //                assert(status == 0);
    VTDecodeFrameFlags flags = 0;
    VTDecodeInfoFlags  flagOut;
    OSStatus           status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags, (GVoid *) dts, &flagOut);
    return status;
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
