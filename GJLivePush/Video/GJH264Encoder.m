//
//  GJH264Encoder.m
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import "GJH264Encoder.h"
#import "GJRetainBufferPool.h"
#import "GJDebug.h"

#define DEFAULT_DELAY  5
#define DEFAULT_MAX_DROP_STEP 4
@interface GJH264Encoder()
{
    int _dropStep;//格多少帧丢一帧
    
}
@property(nonatomic,assign)VTCompressionSessionRef enCodeSession;
@property(nonatomic,assign)GJRetainBufferPool* bufferPool;
@property(nonatomic,assign)int32_t currentBitRate;//当前码率
@property(nonatomic,assign)int currentDelayCount;//调整之后要过几帧才能反应，所以要延迟几帧再做检测调整；


@end

@implementation GJH264Encoder

-(instancetype)initWithFormat:(H264Format)format{
    self = [super init];
    if(self){
        _destFormat = format;
        if (format.baseFormat.bitRate>0) {
            _currentBitRate = format.baseFormat.bitRate;
            _allowMinBitRate = _currentBitRate;
        }
    }
    return self;
}
- (instancetype)init
{
    return [self initWithFormat:[GJH264Encoder defaultFormat]];
}
+(H264Format)defaultFormat{
    H264Format format;
    memset(&format, 0, sizeof(H264Format));
    format.model=EntropyMode_CABAC;
    format.level=profileLevelMain;
    format.allowBframe=false;//false时解码dts一直为0
    format.allowPframe=true;
    format.baseFormat.bitRate=60*1024*8;//bit/s
    format.gopSize=10;
    return format;
}
-(void)setDestFormat:(H264Format)destFormat{
    _destFormat = destFormat;
}

//编码
-(BOOL)encodeImageBuffer:(CVImageBufferRef)imageBuffer pts:(CMTime)pts fourceKey:(BOOL)fourceKey
{
    _frameCount++;
    if (_dropStep > 0 && _frameCount%_dropStep == 0) {
        return NO;
    }
    
    
    int32_t h = (int32_t)CVPixelBufferGetHeight(imageBuffer);
    int32_t w = (int32_t)CVPixelBufferGetWidth(imageBuffer);
    if (_enCodeSession == nil || h != _destFormat.baseFormat.height || w != _destFormat.baseFormat.width) {
        [self creatEnCodeSessionWithWidth:w height:h];
    }
    
//    CMTime presentationTimeStamp = CMTimeMake(encoderFrameCount*1000.0/_destFormat.baseFormat.fps, 1000);
   
    NSMutableDictionary * properties = NULL;
    if (fourceKey) {
        properties = [[NSMutableDictionary alloc]init];
        [properties setObject:@YES forKey:(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame];
    }
    OSStatus status = VTCompressionSessionEncodeFrame(
                                                      _enCodeSession,
                                                      imageBuffer,
                                                      pts,  //pts能得到dts和pts
                                                      kCMTimeInvalid,// may be kCMTimeInvalid ,dts只能得到dts
                                                       (__bridge CFDictionaryRef)properties,
                                                      NULL,
                                                      NULL );
    
    if (status == 0) {
        _encodeframeCount++;
        return YES;
    }else{
        printf("编码失败：%d",status);
        return NO;
    }
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
    _destFormat.baseFormat.width = w;
    _destFormat.baseFormat.height = h;
    if (_bufferPool != NULL) {
        GJRetainBufferPoolRelease(&_bufferPool);
    }
    GJRetainBufferPoolCreate(&_bufferPool, w*h,true);///选最大size
    [self _setCompressionSession];

    VTCompressionSessionPrepareToEncodeFrames(_enCodeSession);
 
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
    
    CFNumberRef bitRate = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &(_currentBitRate));
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AverageBitRate, bitRate);
    CFRelease(bitRate);
    if (result != 0) {
        NSLog(@"kVTCompressionPropertyKey_AverageBitRate set error");
    }
    

    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &(_destFormat.gopSize));
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval,frameIntervalRef);
    CFRelease(frameIntervalRef);
    if (result != 0) {
        NSLog(@"kVTCompressionPropertyKey_MaxKeyFrameInterval set error");
    }

}

-(void)setCurrentBitRate:(int32_t)currentBitRate{
    if (currentBitRate>0 && _enCodeSession) {
        _currentBitRate = currentBitRate;
        CFNumberRef bitRate = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &(_currentBitRate));
        OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AverageBitRate, bitRate);
        CFRelease(bitRate);
        GJAssert(result == 0, "kVTCompressionPropertyKey_AverageBitRate set error:%d",result);
    }
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
    
    GJAssert(bufferOffset == totalLength, "数据出错\n");
 
    retainBuffer->size = (int)bufferOffset;//size初始是最大值，一定要设置当前值
    assert(encoder.bufferPool->bufferSize >= retainBuffer->size);
    
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);

#if 0
    CMTime ptd = CMSampleBufferGetDuration(sample);
    CMTime opts = CMSampleBufferGetOutputPresentationTimeStamp(sample);
    CMTime odts = CMSampleBufferGetOutputDecodeTimeStamp(sample);
    CMTime optd = CMSampleBufferGetOutputDuration(sample);
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(sample);
    GJPrintf("encode dts:%f pts:%f\n",dts.value*1.0 / dts.timescale,pts.value*1.0/pts.timescale);
#endif
    float bufferRate = [encoder.deleagte GJH264Encoder:encoder encodeCompleteBuffer:retainBuffer keyFrame:keyframe pts:pts];
    retainBufferUnRetain(retainBuffer);

    if (encoder.currentDelayCount==0) {
        if (bufferRate > 0.3) {
            [encoder reduceQuality];
            encoder.currentDelayCount = DEFAULT_DELAY;
        }else if(bufferRate - 0.0 <0.001){
            [encoder appendQuality];
            encoder.currentDelayCount = DEFAULT_DELAY;
        }
    }else{
        encoder.currentDelayCount--;
    }
}
//快降慢升
-(void)appendQuality{
    if (_dropStep > 0) {
        if (++_dropStep > DEFAULT_MAX_DROP_STEP) {
            _dropStep = 0;
            [self.deleagte GJH264Encoder:self qualityQarning:GJEncodeQualitybad];
        }else{
            [self.deleagte GJH264Encoder:self qualityQarning:GJEncodeQualityGood];
        }
    }else{
        if (_currentBitRate < _destFormat.baseFormat.bitRate) {
            self.currentBitRate += (_destFormat.baseFormat.bitRate - _currentBitRate)*0.1;
            [self.deleagte GJH264Encoder:self qualityQarning:GJEncodeQualityGood];
        }else{
            [self.deleagte GJH264Encoder:self qualityQarning:GJEncodeQualityExcellent];
        }
    }
}
-(void)reduceQuality{
    if (_currentBitRate > _allowMinBitRate) {
        int32_t bitrate =_currentBitRate - (_currentBitRate - _allowMinBitRate)*0.4;
        if (bitrate < _allowMinBitRate) {
            bitrate = _allowMinBitRate;
        }
        self.currentBitRate = bitrate;
        [self.deleagte GJH264Encoder:self qualityQarning:GJEncodeQualityGood];
    }else{
        if (_dropStep > 2) {//最多到1，丢一半
            _dropStep--;
            [self.deleagte GJH264Encoder:self qualityQarning:GJEncodeQualitybad];
        }else{
            [self.deleagte GJH264Encoder:self qualityQarning:GJEncodeQualityTerrible];
        }
    }
}
-(void)flush{
    if(_enCodeSession)VTCompressionSessionInvalidate(_enCodeSession);
    _enCodeSession = nil;

}


-(void)dealloc{
    if(_enCodeSession)VTCompressionSessionInvalidate(_enCodeSession);    
}
//-(void)restart{
//
//    [self creatEnCodeSession];
//}

@end
