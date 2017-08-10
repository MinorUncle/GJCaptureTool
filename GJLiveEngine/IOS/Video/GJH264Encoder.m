//
//  GJH264Encoder.m
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import "GJH264Encoder.h"
#import "GJBufferPool.h"
#import "GJLiveDefine+internal.h"
#import "GJLog.h"
//#define DEFAULT_DELAY  10
//默认i帧是p帧的I_P_RATE+1倍。越小丢帧时码率降低越大

#define DEFAULT_CHECK_DELAY 1000
#define DROP_BITRATE_RATE 0.1

@interface GJH264Encoder()
{
    GInt64 _fristPts;
    GInt32 _dtsDelta;
    GBool _shouldRestart;
    BOOL requestFlush;
    
}
@property(nonatomic,assign)VTCompressionSessionRef enCodeSession;
@property(nonatomic,assign)GJBufferPool* bufferPool;
//@property(nonatomic,assign)GInt32 currentBitRate;//当前码率

@end

@implementation GJH264Encoder

-(instancetype)initWithSourceSize:(CGSize)size{
    self = [super init];
    if(self){
        _sourceSize = size;
        _bitrate = 600;;
//        _allowMinBitRate = _currentBitRate;
        _allowBFrame = YES;
        
        _profileLevel = profileLevelMain;
        _entropyMode = EntropyMode_CABAC;
        _fristPts = GINT64_MAX;
        _dtsDelta = 0;
        [self creatEnCodeSession];
        
    }
    return self;
}



//编码
-(BOOL)encodeImageBuffer:(CVImageBufferRef)imageBuffer pts:(int64_t)pts
{

//RETRY:
    {
    //    CMTime presentationTimeStamp = CMTimeMake(encoderFrameCount*1000.0/_destFormat.baseFormat.fps, 1000);
       
        NSMutableDictionary * properties = NULL;
        if (_enCodeSession == nil) {
            [self creatEnCodeSession];
            [self setAllParm];
        }
        if (requestFlush) {
            properties = [[NSMutableDictionary alloc]init];
            [properties setObject:@YES forKey:(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame];
            requestFlush = NO;
        }
//        printf("encode pts:%lld\n",pts);
        OSStatus status = VTCompressionSessionEncodeFrame(
                                                          _enCodeSession,
                                                          imageBuffer,
                                                          CMTimeMake(pts, 1000),  //pts能得到dts和pts
                                                          kCMTimeInvalid,// may be kCMTimeInvalid ,dts只能得到dts
                                                           (__bridge CFDictionaryRef)properties,
                                                          NULL,
                                                          NULL );
        
        
        if (status == 0) {
            _encodeframeCount++;
            return YES;
        }else{
            if (status == kVTInvalidSessionErr) {
                GJLOG(GJ_LOGWARNING,"编码失败 kVTInvalidSessionErr:%d,重新编码",status);
                VTCompressionSessionInvalidate(_enCodeSession);
                _enCodeSession = nil;
                [self creatEnCodeSession];
                [self setAllParm];
//                goto RETRY;//不重试，防止占用太多时间
            }else{
                GJLOG(GJ_LOGFORBID,"编码失败：%d",status);
            }
            _shouldRestart = YES;
            return NO;
        }
    }
}

-(void)creatEnCodeSession{
    if (_enCodeSession != nil) {
        VTCompressionSessionInvalidate(_enCodeSession);
    }
    _shouldRestart = NO;
    OSStatus result = VTCompressionSessionCreate(
                                            NULL,
                                            (int32_t)_sourceSize.width,
                                            (int32_t)_sourceSize.height,
                                            kCMVideoCodecType_H264,
                                            NULL,
                                            NULL,
                                            NULL,
                                            encodeOutputCallback,
                                            (__bridge void * _Nullable)(self),
                                            &_enCodeSession);
    if (!_enCodeSession) {
        NSLog(@"VTCompressionSessionCreate 失败------------------status:%d",(int)result);
        return;
    }
    _sps = _pps = nil;
    if (_bufferPool != NULL) {
        GJBufferPool* pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJBufferPoolClean(pool,true);
            GJBufferPoolFree(pool);
        });
        _bufferPool = NULL;
    }
    GJBufferPoolCreate(&_bufferPool,1, true);
    VTCompressionSessionPrepareToEncodeFrames(_enCodeSession);
 
}
-(void)setGop:(int)gop{
    _gop = gop;
    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &(_gop));
    OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval,frameIntervalRef);
    CFRelease(frameIntervalRef);
    if (result != 0) {
        GJLOG(GJ_LOGFORBID,"kVTCompressionPropertyKey_MaxKeyFrameInterval set error");
    }
}
-(void)setProfileLevel:(ProfileLevel)profileLevel{
    _profileLevel = profileLevel;
    OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_ProfileLevel, getCFStrByLevel(_profileLevel));
    if (result != 0) {
        GJLOG(GJ_LOGFORBID,"kVTCompressionPropertyKey_ProfileLevel set error");
    }
}
-(void)setEntropyMode:(EntropyMode)entropyMode{
    _entropyMode = entropyMode;
    OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_H264EntropyMode, getCFStrByEntropyMode(_entropyMode));
    if (result != 0) {
        GJLOG(GJ_LOGFORBID,"kVTCompressionPropertyKey_H264EntropyMode set error");
    }
}
-(void)setAllowBFrame:(BOOL)allowBFrame{
    _allowBFrame = allowBFrame;
    OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AllowFrameReordering, _allowBFrame?kCFBooleanTrue:kCFBooleanFalse);
    if (result != 0) {
        GJLOG(GJ_LOGFORBID,"kVTCompressionPropertyKey_AllowFrameReordering set error");
    }
}
-(void)setAllParm{
    //    kVTCompressionPropertyKey_MaxFrameDelayCount
    //    kVTCompressionPropertyKey_MaxH264SliceBytes
    //    kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
    //    kVTCompressionPropertyKey_RealTime

    self.allowBFrame = _allowBFrame;
    self.profileLevel = _profileLevel;
    self.entropyMode = _entropyMode;
    self.gop = _gop;
    self.bitrate = _bitrate;
}
-(void)setBitrate:(int)bitrate{
    if (bitrate>0 && _enCodeSession) {
        _bitrate = bitrate;
        CFNumberRef bitRate = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &(_bitrate));
        OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AverageBitRate, bitRate);
        CFRelease(bitRate);
        if (result != noErr) {
            GJLOG(GJ_LOGFORBID, "kVTCompressionPropertyKey_AverageBitRate set error:%d",result);
        }else{
            GJLOG(GJ_LOGINFO, "set video bitrate:%0.2f kB/s",bitrate/1024.0/8.0);
        }
    }
}

static GBool retainBufferRelease(GJRetainBuffer* buffer){
    GJBufferPool* pool = buffer->parm;
    GJBufferPoolSetData(pool, buffer->data-buffer->frontSize);
    GJBufferPoolSetData(defauleBufferPool(), (void*)buffer);
    return GTrue;
}

void encodeOutputCallback(void *  outputCallbackRefCon,void *  sourceFrameRefCon,OSStatus statu,VTEncodeInfoFlags infoFlags,
                          CMSampleBufferRef sample ){
    if (statu != 0) return;
    if (!CMSampleBufferDataIsReady(sample))
    {
        GJLOG(GJ_LOGWARNING,"didCompressH264 data is not ready ");
        return;
    }
    GJH264Encoder* encoder = (__bridge GJH264Encoder *)(outputCallbackRefCon);
    R_GJPacket* pushPacket = (R_GJPacket*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
    GJRetainBuffer* retainBuffer = &pushPacket->retain;
    memset(pushPacket, 0, sizeof(R_GJPacket));
#define PUSH_H264_PACKET_PRE_SIZE 45
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sample);
    size_t length, totalLength;
//    size_t bufferOffset = 0;
    uint8_t *inDataPointer;
    CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, (char**)&inDataPointer);

    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sample, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    if ( encoder.sps == nil)
    {
        if (!keyframe) {
            GJBufferPoolSetBackData((GUInt8*)pushPacket);
            return;
        }
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
        size_t sparameterSetSize, sparameterSetCount;
        int spHeadSize;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, &spHeadSize );
        if (statusCode != noErr)
        {
            GJLOG(GJ_LOGFORBID,"CMVideoFormatDescriptionGetH264ParameterSetAt sps error:%d",statusCode);
            GJBufferPoolSetData(defauleBufferPool(), (void*)pushPacket);
            return;
        }
        
        size_t pparameterSetSize, pparameterSetCount;
        int ppHeadSize;
        const uint8_t *pparameterSet;
        statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, &ppHeadSize );
        if ((statusCode != noErr))
        {
            GJLOG(GJ_LOGFORBID,"CMVideoFormatDescriptionGetH264ParameterSetAt pps error:%d",statusCode);
            GJBufferPoolSetData(defauleBufferPool(), (void*)pushPacket);
            return;
        }
        
        size_t spsppsSize = sparameterSetSize+pparameterSetSize;
        int needSize = (int)(spsppsSize+totalLength+PUSH_H264_PACKET_PRE_SIZE);
        retainBufferPack(&retainBuffer, GJBufferPoolGetSizeData(encoder.bufferPool,needSize), needSize, retainBufferRelease, encoder.bufferPool);
        
        if (retainBuffer->frontSize < PUSH_H264_PACKET_PRE_SIZE) {
            retainBufferMoveDataToPoint(retainBuffer, PUSH_H264_PACKET_PRE_SIZE, GFalse);
        }
        pushPacket->flag = GJPacketFlag_KEY;
        pushPacket->dataOffset = 0;
        pushPacket->dataSize = (GInt32)(totalLength + spsppsSize + 8);
        
        uint8_t* data = retainBuffer->data;
        memcpy(data, "\x00\x00\x00\x01", 4);
        memcpy(data+4, sparameterSet, sparameterSetSize);
        encoder.sps = [NSData dataWithBytes:data length:sparameterSetSize];

        memcpy(data+4+sparameterSetSize, "\x00\x00\x00\x01", 4);
        memcpy(data+ 8+ sparameterSetSize, pparameterSet, pparameterSetSize);
        encoder.pps = [NSData dataWithBytes:data + sparameterSetSize length:pparameterSetSize];

        memcpy(data+spsppsSize + 8, inDataPointer, totalLength);
        inDataPointer = data + spsppsSize +8;
        

    }else{
        int needSize = (int)(totalLength+PUSH_H264_PACKET_PRE_SIZE);
        retainBufferPack(&retainBuffer, GJBufferPoolGetSizeData(encoder.bufferPool,needSize), needSize, retainBufferRelease, encoder.bufferPool);
        if (retainBuffer->frontSize < PUSH_H264_PACKET_PRE_SIZE) {
            retainBufferMoveDataToPoint(retainBuffer, PUSH_H264_PACKET_PRE_SIZE, GFalse);
        }
        pushPacket->flag = 0;
        pushPacket->dataOffset = 0;
        pushPacket->dataSize = (GInt32)(totalLength);


//拷贝
        uint8_t* rDate = retainBuffer->data;
        memcpy(rDate, inDataPointer, totalLength);
        inDataPointer = rDate;
    }
    
    pushPacket->type = GJMediaType_Video;
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(sample);

    pushPacket->pts = pts.value;

    if (encoder->_allowBFrame) {
        if (encoder->_fristPts > pushPacket->pts) {
            encoder->_fristPts = pushPacket->pts;
            encoder->_dtsDelta = 0;
        }else if(encoder->_dtsDelta <= 0){
            encoder->_dtsDelta = (GInt32)(pushPacket->pts - encoder->_fristPts);
        }
        if (dts.value > 0) {
            pushPacket->dts = dts.value;
        }else{
            pushPacket->dts = pushPacket->pts;
        }
        pushPacket->dts -= encoder->_dtsDelta;
        if (pushPacket->dts > pushPacket->pts) {
            pushPacket->dts = pushPacket->pts;
        }

    }else{
        pushPacket->dts = pts.value;
    }
    //-----------
//    if (CMTIME_IS_INVALID(dts)) {
//        pushPacket->dts = pts.value;
//    }else{
//        pushPacket->dts = dts.value;
//    }
    
//    printf("encode over pts:%lld dts:%lld data size:%zu\n",pts.value,pushPacket->dts,totalLength);
    
    
//    NSData* seid = [NSData dataWithBytes:pushPacket->ppOffset+pushPacket->retain.data length:30];
//    NSData* spsd = [NSData dataWithBytes:pushPacket->spsOffset+pushPacket->retain.data  length:pushPacket->spsSize];
//    NSData* ppsd = [NSData dataWithBytes:pushPacket->ppsOffset+pushPacket->retain.data  length:pushPacket->ppsSize];
//    
//    static int t = 0;
//    NSLog(@"push times:%d :%@,sps:%@，pps:%@",t++,seid,spsd,ppsd);
#if 0
    CMTime ptd = CMSampleBufferGetDuration(sample);
    CMTime opts = CMSampleBufferGetOutputPresentationTimeStamp(sample);
    CMTime odts = CMSampleBufferGetOutputDecodeTimeStamp(sample);
    CMTime optd = CMSampleBufferGetOutputDuration(sample);
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(sample);
    GJLOG(GJ_LOGINFO,"encode dts:%f pts:%f\n",dts.value*1.0 / dts.timescale,pts.value*1.0/pts.timescale);
#endif
    
    int bufferOffset = 0;
    
    
    static const uint32_t AVCCHeaderLength = 4;
    while (bufferOffset < totalLength) {
        // Read the NAL unit length
        uint32_t NALUnitLength = 0;
        memcpy(&NALUnitLength, inDataPointer + bufferOffset, AVCCHeaderLength);
        NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);

        uint8_t* data = inDataPointer + bufferOffset;
        memcpy(&data[0], "\x00\x00\x00\x01", AVCCHeaderLength);
        bufferOffset += AVCCHeaderLength + NALUnitLength;
    }
    
    encoder.completeCallback(pushPacket);
    retainBufferUnRetain(retainBuffer);
}


-(void)flush{
    requestFlush = YES;
    _sps = nil;
    _pps = nil;
}


-(void)dealloc{
    GJLOG(GJ_LOGDEBUG, "GJH264Encoder：%p",self);
    if(_enCodeSession)VTCompressionSessionInvalidate(_enCodeSession);
    if (_bufferPool) {
        GJBufferPool* pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJBufferPoolClean(pool,true);
            GJBufferPoolFree(pool);
        });
    }
    
}
//-(void)restart{
//
//    [self creatEnCodeSession];
//}

@end
