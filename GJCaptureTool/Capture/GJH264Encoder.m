//
//  GJH264Encoder.m
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import "GJH264Encoder.h"
#import "GJRetainBufferPool.h"
@interface GJH264Encoder()
{
    long encoderFrameCount;
    BOOL _shouldRecreate;
    GJRetainBufferPool* _bufferPool;
}
@property(nonatomic,assign)VTCompressionSessionRef enCodeSession;
@property(nonatomic,assign)GJRetainBufferPool* bufferPool;


@end

@implementation GJH264Encoder

-(instancetype)initWithFps:(uint)fps{
    self = [super init];
    if (self) {

        [self setUpParm];
        _destFormat.baseFormat.fps=fps;
        _expectedFrameRate = _destFormat.baseFormat.fps;

    }
    return self;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setUpParm];
    }
    return self;
}
-(void)setUpParm{
    _shouldRecreate=YES;
    memset(&_destFormat, 0, sizeof(H264Format));
    _destFormat.model=EntropyMode_CABAC;
    _destFormat.level=profileLevelMain;
    _destFormat.allowBframe=false;
    _destFormat.allowPframe=true;
    _destFormat.baseFormat.bitRate=300*1024*8;//bit/s
    _destFormat.gopSize=10;
    
    _quality = 1.0;
}
-(void)setDestFormat:(H264Format)destFormat{
    _destFormat = destFormat;
}

//编码
-(void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer fourceKey:(BOOL)fourceKey
{
    
    
    CVImageBufferRef imgRef = CMSampleBufferGetImageBuffer(sampleBuffer);
    int32_t h = (int32_t)CVPixelBufferGetHeight(imgRef);
    int32_t w = (int32_t)CVPixelBufferGetWidth(imgRef);
    if (_shouldRecreate || h != _destFormat.baseFormat.height || w != _destFormat.baseFormat.width) {
        [self creatEnCodeSessionWithWidth:w height:h];
    }
    
    CMTime presentationTimeStamp = CMTimeMake(encoderFrameCount*1000.0/_destFormat.baseFormat.fps, 1000);
    CMTime during = kCMTimeInvalid;
    if (_destFormat.baseFormat.fps>0) {
        during = CMTimeMake(1, _destFormat.baseFormat.fps);
    }
    NSMutableDictionary * properties;
 
    if (fourceKey) {
        properties = [[NSMutableDictionary alloc]init];
        [properties setObject:@YES forKey:(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame];
    }
    
    OSStatus status = VTCompressionSessionEncodeFrame(
                                                      _enCodeSession,
                                                      imgRef,
                                                      presentationTimeStamp,
                                                      during, // may be kCMTimeInvalid
                                                       (__bridge CFDictionaryRef)properties,
                                                      NULL,
                                                      NULL );
    encoderFrameCount++;
    if (status != 0) {
        NSLog(@"encodeSampleBuffer error:%d",(int)status);
        return;
    }
    CFNumberRef outBit=0;
    VTSessionCopyProperty(_enCodeSession, kVTCompressionPropertyKey_AverageBitRate, NULL, &outBit);
    int32_t bit = 0;
    CFNumberGetValue(outBit,kCFNumberSInt32Type,&bit);
    NSLog(@"kCFNumberSInt32Type bit:%d",bit);

}

-(void)creatEnCodeSessionWithWidth:(int32_t)w height:(int32_t)h{
    if (_enCodeSession != nil) {
        VTCompressionSessionInvalidate(_enCodeSession);
    }
    OSStatus result = VTCompressionSessionCreate(
                                            NULL,
                                            w,
                                            h,
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
    _shouldRecreate=NO;
    _destFormat.baseFormat.width = w;
    _destFormat.baseFormat.height = h;
    if (_bufferPool != NULL) {
        GJRetainBufferPoolRelease(&_bufferPool);
    }
    GJRetainBufferPoolCreate(&_bufferPool, w*h*4);///选最大size
    [self _setCompressionSession];

    result = VTCompressionSessionPrepareToEncodeFrames(_enCodeSession);
 
}

-(void)_setCompressionSession{
    //    kVTCompressionPropertyKey_MaxFrameDelayCount
    //    kVTCompressionPropertyKey_MaxH264SliceBytes
    //    kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
    //    kVTCompressionPropertyKey_RealTime

    OSStatus result =0;
    //b帧
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AllowFrameReordering, _destFormat.allowBframe?kCFBooleanTrue:kCFBooleanFalse);
    if (result != 0) {
        NSLog(@"kVTCompressionPropertyKey_AllowFrameReordering set error");
    }
    //p帧
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AllowTemporalCompression, _destFormat.allowPframe?kCFBooleanTrue:kCFBooleanFalse);
    if (result != 0) {
        NSLog(@"kVTCompressionPropertyKey_AllowTemporalCompression set error");
    }
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_ProfileLevel, getCFStrByLevel(_destFormat.level));
    if (result != 0) {
        NSLog(@"kVTCompressionPropertyKey_ProfileLevel set error");
    }
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_H264EntropyMode, getCFStrByEntropyMode(_destFormat.model));
    if (result != 0) {
        NSLog(@"kVTCompressionPropertyKey_H264EntropyMode set error");
    }
    
    CFNumberRef bitRate = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &(_destFormat.baseFormat.bitRate));
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AverageBitRate, bitRate);
    CFRelease(bitRate);
    if (result != 0) {
        NSLog(@"kVTCompressionPropertyKey_AverageBitRate set error");
    }
    
//    CFNumberRef  qualityRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberFloatType,&_quality);
//    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_Quality,qualityRef);
//    CFRelease(qualityRef);
//    if (result != 0) {
//        NSLog(@"kVTCompressionPropertyKey_Quality set error");
//    }
    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &(_destFormat.gopSize));
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval,frameIntervalRef);
    CFRelease(frameIntervalRef);
    if (result != 0) {
        NSLog(@"kVTCompressionPropertyKey_MaxKeyFrameInterval set error");
    }

    
    CFNumberRef frameRate = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &_expectedFrameRate);
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_ExpectedFrameRate,frameRate);
    CFRelease(frameRate);
    if (result != 0) {
        NSLog(@"kVTCompressionPropertyKey_ExpectedFrameRate set error");
    }
    
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_CleanAperture,frameRate);

}



void encodeOutputCallback(void *  outputCallbackRefCon,void *  sourceFrameRefCon,OSStatus statu,VTEncodeInfoFlags infoFlags,
                          CMSampleBufferRef sample ){
    if (statu != 0) return;
    if (!CMSampleBufferDataIsReady(sample))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    GJH264Encoder* encoder = (__bridge GJH264Encoder *)(outputCallbackRefCon);
    GJRetainBuffer* retainBuffer = GJRetainBufferPoolGetData(encoder.bufferPool);

    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sample);
    size_t length, totalLength;
    size_t bufferOffset = 0;
    uint8_t *dataPointer;
    CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, (char**)&dataPointer);

    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sample, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
        size_t sparameterSetSize, sparameterSetCount;
        int spHeadSize;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, &spHeadSize );
        if (statusCode != noErr)
        {
            NSLog(@"CMVideoFormatDescriptionGetH264ParameterSetAt sps error:%d",statusCode);
            return;
        }
        size_t pparameterSetSize, pparameterSetCount;
        int ppHeadSize;
        const uint8_t *pparameterSet;
        statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, &ppHeadSize );
        if ((statusCode != noErr))
        {
            NSLog(@"CMVideoFormatDescriptionGetH264ParameterSetAt pps error:%d",statusCode);
            return;
        }
        size_t spsppsSize = 4+4+sparameterSetSize+pparameterSetSize;
       
        uint8_t* data = retainBuffer->data;
        memcpy(&data[0], "\x00\x00\x00\x01", 4);
//        memcpy(&data[0], &sparameterSetSize, 4);
        memcpy(&data[4], sparameterSet, sparameterSetSize);
        memcpy(&data[4+sparameterSetSize], "\x00\x00\x00\x01", 4);
//        memcpy(&data[4+sparameterSetSize], &pparameterSetSize, 4);
        memcpy(&data[8+sparameterSetSize], pparameterSet, pparameterSetSize);
        
//        拷贝keyframe;
        memcpy(data+spsppsSize, dataPointer, totalLength);
        dataPointer = data;
        totalLength += spsppsSize;
        bufferOffset = spsppsSize;
        
        //sei
//        NSData* dt = [NSData dataWithBytes:dataPointer length:MIN(totalLength, 100)];
//        NSLog(@"t:%@",dt);
//        uint32_t seiLength = 0;
//        memcpy(&seiLength, dataPointer, 4);
//        seiLength = CFSwapInt32BigToHost(seiLength);
//        
//        dataPointer += seiLength + 4;
//        totalLength -= seiLength + 4;

    }else{
        memcpy(retainBuffer->data, dataPointer, totalLength);
        dataPointer = retainBuffer->data;
    }
    

    

    static const uint32_t AVCCHeaderLength = 4;
    while (bufferOffset < totalLength) {
        // Read the NAL unit length
        uint32_t NALUnitLength = 0;
        memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
        
        NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
        uint8_t* data = dataPointer + bufferOffset;
        memcpy(&data[0], "\x00\x00\x00\x01", AVCCHeaderLength);
        bufferOffset += AVCCHeaderLength + NALUnitLength;
    }
    
    if (bufferOffset > totalLength) {
        assert(0);
    }
    CMTime dt = CMSampleBufferGetDecodeTimeStamp(sample);
    retainBuffer->size = (int)bufferOffset;//size初始是最大值，一定要设置当前值
    [encoder.deleagte GJH264Encoder:encoder encodeCompleteBuffer:retainBuffer keyFrame:keyframe dts:dt.value*1.0/dt.timescale];
    retainBufferUnRetain(retainBuffer);
}

-(void)stop{
    _enCodeSession = nil;
}
-(void)dealloc{
    VTCompressionSessionInvalidate(_enCodeSession);

    
}
//-(void)restart{
//
//    [self creatEnCodeSession];
//}

@end
