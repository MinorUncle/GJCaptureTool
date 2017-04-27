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
#define DEFAULT_MAX_DROP_STEP 5
//默认i帧是p帧的I_P_RATE+1倍。越小丢帧时码率降低越大
#define I_P_RATE 4

@interface GJH264Encoder()
{
    int _dropStep;//隔多少帧丢一帧
    
}
@property(nonatomic,assign)VTCompressionSessionRef enCodeSession;
@property(nonatomic,assign)GJBufferPool* bufferPool;
@property(nonatomic,assign)int32_t currentBitRate;//当前码率
@property(nonatomic,assign)int currentDelayCount;//调整之后要过几帧才能反应，所以要延迟几帧再做检测调整；
@property(nonatomic,assign)int bufferRate;//当前调整时的缓存程度
@property(nonatomic,assign)BOOL shouldRestart;
@property(nonatomic,assign)BOOL stopRequest;//防止下一帧满时一直等待


@end

@implementation GJH264Encoder

-(instancetype)initWithFormat:(H264Format)format{
    self = [super init];
    if(self){
        _destFormat = format;
        if (format.baseFormat.bitRate>0) {
            _currentBitRate = format.baseFormat.bitRate;
            _allowMinBitRate = _currentBitRate;
            _dropStep = -1;
            _allowDropStep = 1;
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
    format.baseFormat.bitRate=100*1024*8;//bit/s
    format.gopSize=10;
    return format;
}
-(void)setDestFormat:(H264Format)destFormat{
    _destFormat = destFormat;
}

//编码
-(BOOL)encodeImageBuffer:(CVImageBufferRef)imageBuffer pts:(int64_t)pts fourceKey:(BOOL)fourceKey
{
    _frameCount++;
    if (_dropStep >= 0 && _frameCount%(_dropStep+1) == 0) {
        return NO;
    }
    
    
   
RETRY:
    {
        int32_t h = (int32_t)CVPixelBufferGetHeight(imageBuffer);
        int32_t w = (int32_t)CVPixelBufferGetWidth(imageBuffer);
        
        if (_enCodeSession == nil || h != _destFormat.baseFormat.height || w != _destFormat.baseFormat.width || _shouldRestart) {
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
                GJLOG(GJ_LOGERROR,"编码失败 kVTInvalidSessionErr,重新编码");
                VTCompressionSessionInvalidate(_enCodeSession);
                _enCodeSession = nil;
                goto RETRY;
            }else{
                GJLOG(GJ_LOGERROR,"编码失败：%d",status);
            }
            _shouldRestart = YES;
            return NO;
        }
    }
}

-(void)creatEnCodeSessionWithWidth:(int32_t)w height:(int32_t)h{
    if (_enCodeSession != nil) {
        _stopRequest = YES;
        VTCompressionSessionInvalidate(_enCodeSession);
    }
    _shouldRestart = NO;
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
    _stopRequest = NO;
    _destFormat.baseFormat.width = w;
    _destFormat.baseFormat.height = h;
    if (_bufferPool != NULL) {
        __block GJBufferPool* pool = _bufferPool;
        _bufferPool = NULL;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            GJBufferPoolClean(pool);
            GJBufferPoolDealloc(&pool);
        });
    }
    GJBufferPoolCreate(&_bufferPool,1, true);
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
        GJLOG(GJ_LOGERROR,"kVTCompressionPropertyKey_AllowFrameReordering set error");
    }
    //p帧
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AllowTemporalCompression, _destFormat.allowPframe?kCFBooleanTrue:kCFBooleanFalse);
    if (result != 0) {
        GJLOG(GJ_LOGERROR,"kVTCompressionPropertyKey_AllowTemporalCompression set error");
    }
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_ProfileLevel, getCFStrByLevel(_destFormat.level));
    if (result != 0) {
        GJLOG(GJ_LOGERROR,"kVTCompressionPropertyKey_ProfileLevel set error");
    }
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_H264EntropyMode, getCFStrByEntropyMode(_destFormat.model));
    if (result != 0) {
        GJLOG(GJ_LOGERROR,"kVTCompressionPropertyKey_H264EntropyMode set error");
    }
    
    [self setCurrentBitRate:_currentBitRate];
    

    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &(_destFormat.gopSize));
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval,frameIntervalRef);
    CFRelease(frameIntervalRef);
    if (result != 0) {
        GJLOG(GJ_LOGERROR,"kVTCompressionPropertyKey_MaxKeyFrameInterval set error");
    }

}

-(void)setCurrentBitRate:(int32_t)currentBitRate{
    if (currentBitRate>0 && _enCodeSession) {
        _currentBitRate = currentBitRate;
        CFNumberRef bitRate = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &(_currentBitRate));
        OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AverageBitRate, bitRate);
        CFRelease(bitRate);
        if (result != noErr) {
            GJLOG(GJ_LOGERROR, "kVTCompressionPropertyKey_AverageBitRate set error:%d",result);
        }else{
            GJLOG(GJ_LOGINFO, "set video bitrate:%0.2f kB/s",currentBitRate/1024.0/8.0);
        }
    }
}
static bool retainBufferRelease(GJRetainBuffer* buffer){
    GJBufferPool* pool = buffer->parm;
    GJBufferPoolSetData(pool, buffer->data-buffer->frontSize);
    GJBufferPoolSetData(defauleBufferPool(), (void*)buffer);
    return true;
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
    R_GJH264Packet* pushPacket = (R_GJH264Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJH264Packet));
    GJRetainBuffer* retainBuffer = &pushPacket->retain;
    memset(pushPacket, 0, sizeof(R_GJH264Packet));
#define PUSH_H264_PACKET_PRE_SIZE 45
    int needPreSize = PUSH_H264_PACKET_PRE_SIZE;
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sample);
    size_t length, totalLength;
    size_t bufferOffset = 0;
    uint8_t *inDataPointer;
    CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, (char**)&inDataPointer);

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
            GJLOG(GJ_LOGERROR,"CMVideoFormatDescriptionGetH264ParameterSetAt sps error:%d",statusCode);
            GJBufferPoolSetData(defauleBufferPool(), (void*)pushPacket);
            return;
        }
        
        size_t pparameterSetSize, pparameterSetCount;
        int ppHeadSize;
        const uint8_t *pparameterSet;
        statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, &ppHeadSize );
        if ((statusCode != noErr))
        {
            GJLOG(GJ_LOGERROR,"CMVideoFormatDescriptionGetH264ParameterSetAt pps error:%d",statusCode);
            GJBufferPoolSetData(defauleBufferPool(), (void*)pushPacket);
            return;
        }
        size_t spsppsSize = 4+4+sparameterSetSize+pparameterSetSize;
        int needSize = (int)(spsppsSize+totalLength+needPreSize);
        retainBufferPack(&retainBuffer, GJBufferPoolGetSizeData(encoder.bufferPool,needSize), needSize, retainBufferRelease, encoder.bufferPool);

        uint8_t* data = retainBuffer->data+needPreSize;
        memcpy(&data[0], "\x00\x00\x00\x01", 4);
//        memcpy(&data[0], &sparameterSetSize, 4);
        memcpy(&data[4], sparameterSet, sparameterSetSize);
        pushPacket->sps=data;
        pushPacket->spsSize=4+(int)sparameterSetSize;
        memcpy(&data[4+sparameterSetSize], "\x00\x00\x00\x01", 4);
//        memcpy(&data[4+sparameterSetSize], &pparameterSetSize, 4);
        memcpy(&data[8+sparameterSetSize], pparameterSet, pparameterSetSize);
        pushPacket->pps = data+4+sparameterSetSize;
        pushPacket->ppsSize = 4+(int)pparameterSetSize;
//        拷贝keyframe;
        memcpy(data+spsppsSize, inDataPointer, totalLength);
        inDataPointer = data + spsppsSize;
        
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
        int needSize = (int)(totalLength+needPreSize);
        retainBufferPack(&retainBuffer, GJBufferPoolGetSizeData(encoder.bufferPool,needSize), needSize, retainBufferRelease, encoder.bufferPool);
        uint8_t* rDate = retainBuffer->data+needPreSize;
        memcpy(rDate, inDataPointer, totalLength);
        inDataPointer = rDate;
    }
    int type;
    static const uint32_t AVCCHeaderLength = 4;
    while (bufferOffset < totalLength) {
        // Read the NAL unit length
        uint32_t NALUnitLength = 0;
        memcpy(&NALUnitLength, inDataPointer + bufferOffset, AVCCHeaderLength);
        NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
        type = inDataPointer[bufferOffset+AVCCHeaderLength] & 0x1F;
        if (type == 6) {//SEI
            
            pushPacket->sei = inDataPointer+bufferOffset;
            pushPacket->seiSize =(int)(NALUnitLength+4);
        }else if (type == 1 || type == 5){//pp
            pushPacket->pp = inDataPointer+bufferOffset;
            pushPacket->ppSize =(int)(NALUnitLength+4);
        }
        uint8_t* data = inDataPointer + bufferOffset;
        memcpy(&data[0], "\x00\x00\x00\x01", AVCCHeaderLength);
        bufferOffset += AVCCHeaderLength + NALUnitLength;
  
    }
    
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);

    GJAssert(bufferOffset == totalLength, "数据出错\n");
    pushPacket->pts = pts.value;

 
    
#if 0
    CMTime ptd = CMSampleBufferGetDuration(sample);
    CMTime opts = CMSampleBufferGetOutputPresentationTimeStamp(sample);
    CMTime odts = CMSampleBufferGetOutputDecodeTimeStamp(sample);
    CMTime optd = CMSampleBufferGetOutputDuration(sample);
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(sample);
    GJLOG(GJ_LOGINFO,"encode dts:%f pts:%f\n",dts.value*1.0 / dts.timescale,pts.value*1.0/pts.timescale);
#endif
//        static int i = 0;
//        NSLog(@"encodecount:%d,lenth:%d,pts:%lld \n",i++,pushPacket->ppsSize+pushPacket->spsSize+pushPacket->ppSize,pts.value);
//    NSLog(@"encode frame:%d",pushPacket->ppSize);
    while (!encoder.stopRequest){
        float bufferRate = [encoder.deleagte GJH264Encoder:encoder encodeCompletePacket:pushPacket];
        float difference = bufferRate - encoder.bufferRate;
        if(bufferRate > 0.999){
            [encoder reduceQualityWithStep:INT_MAX allowStop:YES];//停止进入
            encoder.currentDelayCount = encoder.destFormat.baseFormat.fps;
            usleep(10000);
            continue;
        }else if (encoder.currentDelayCount==0) {
            if (bufferRate > 0.3) {
                encoder.bufferRate = bufferRate;
                [encoder reduceQualityWithStep:1 allowStop:NO];
            }else if(bufferRate - 0.0 <0.1 && encoder.currentBitRate < encoder.destFormat.baseFormat.bitRate){
                encoder.bufferRate = bufferRate;
                [encoder appendQualityWithStep:1];
            }
            encoder.currentDelayCount = encoder.destFormat.baseFormat.fps;
        }else if(difference > 0.1){
            encoder.bufferRate = bufferRate;
            encoder.currentDelayCount = encoder.destFormat.baseFormat.fps;
            [encoder reduceQualityWithStep:difference*10 allowStop:NO];
        }else if(difference < -0.2){
            encoder.bufferRate = bufferRate;
            encoder.currentDelayCount = encoder.destFormat.baseFormat.fps;
            [encoder appendQualityWithStep:(-difference-0.1)*10];
        }else{
            encoder.currentDelayCount--;
        }
        break;
    }
    retainBufferUnRetain(retainBuffer);
}


//快降慢升
-(void)appendQualityWithStep:(int)step{
    int leftStep = step;
    GJEncodeQuality quality = GJEncodeQualityGood;
    int32_t bitrate = _currentBitRate;
    GJLOG(GJ_LOGINFO, "appendQualityWithStep：%d",step);
    if (_dropStep >= 0) {
        _dropStep += _allowDropStep-1+leftStep;
        leftStep = 0;
        if (_dropStep > DEFAULT_MAX_DROP_STEP) {
            leftStep -= _dropStep - DEFAULT_MAX_DROP_STEP;
            _dropStep = -1;
            bitrate = _allowMinBitRate;
            quality = GJEncodeQualityGood;
        }else{
            bitrate = _allowMinBitRate*(1-1.0/(_dropStep+1))+bitrate/(_destFormat.baseFormat.fps - _destFormat.baseFormat.fps/_dropStep)*I_P_RATE;
            quality = GJEncodeQualitybad;
        }
        GJLOG(GJ_LOGINFO, "appendQuality by reduce to drop frame:%d",_dropStep);
    }
    if(leftStep > 0){
        if (bitrate < _destFormat.baseFormat.bitRate) {
            bitrate += (_destFormat.baseFormat.bitRate - _allowMinBitRate)*leftStep*0.2;
            bitrate = MIN(bitrate, _destFormat.baseFormat.bitRate);
            quality = GJEncodeQualityGood;
        }else{
            quality = GJEncodeQualityExcellent;
            GJLOG(GJ_LOGINFO, "appendQuality to full speed:%f",_currentBitRate/1024.0/8.0);
        }
    }
    if (_currentBitRate != bitrate) {
        self.currentBitRate = bitrate;
        if ([self.deleagte respondsToSelector:@selector(GJH264Encoder:qualityQarning:)]) {
            [self.deleagte GJH264Encoder:self qualityQarning:GJEncodeQualityExcellent];
        }
    }
 
}
-(void)reduceQualityWithStep:(int)step allowStop:(BOOL)allowStop{
    int leftStep = step;
    int currentBitRate = _currentBitRate;
    GJEncodeQuality quality = GJEncodeQualityGood;
    int32_t bitrate = _currentBitRate;
    
    GJLOG(GJ_LOGINFO, "reduceQualityWithStep：%d",step);

    if (_currentBitRate > _allowMinBitRate) {
        bitrate -= (_destFormat.baseFormat.bitRate - _allowMinBitRate)*leftStep*0.2;
        leftStep = 0;
        if (bitrate < _allowMinBitRate) {
            bitrate = _allowMinBitRate;
            leftStep = (currentBitRate - bitrate)/((_destFormat.baseFormat.bitRate - _allowMinBitRate)*0.2);
        }
        quality = GJEncodeQualityGood;
    }
    if (leftStep > 0){
        if (_dropStep != 0) {//最多到0，即缓冲已经满了，每帧都丢。
            if (_dropStep < 0) {//没有丢帧，则开始丢弃
                _dropStep = DEFAULT_MAX_DROP_STEP;
            }else{//否则加快丢帧
                _dropStep -= leftStep;
                if (_dropStep < _allowDropStep) {
                    if (allowStop) {
                        _dropStep = 0;
                    }else{
                        _dropStep = _allowDropStep;
                    }
                }
            }
            GJLOG(GJ_LOGINFO, "reduceQuality by reduce drop frame to setp:%d",_dropStep);
            //假设i帧是p帧的4倍；,越大，丢帧时码率减少越小
            bitrate = _allowMinBitRate*(1-1.0/(_dropStep+1))+bitrate/(_destFormat.baseFormat.fps - _destFormat.baseFormat.fps/_dropStep)*I_P_RATE;
            quality = GJEncodeQualitybad;
        }else{
            GJLOG(GJ_LOGINFO, "reduceQuality to minimum quality:%f",_currentBitRate/1024.0/8.0);
            if(!allowStop){
                _dropStep = _allowDropStep;
                bitrate = _allowMinBitRate*(1-1.0/(_dropStep+1))+bitrate/(_destFormat.baseFormat.fps - _destFormat.baseFormat.fps/_dropStep)*I_P_RATE;
            }
            quality = GJEncodeQualityTerrible;
        }
    }
    self.currentBitRate = bitrate;
    if ([self.deleagte respondsToSelector:@selector(GJH264Encoder:qualityQarning:)]) {
        [self.deleagte GJH264Encoder:self qualityQarning:quality];
    }
}
-(void)flush{
    _stopRequest = YES;
    if(_enCodeSession)VTCompressionSessionInvalidate(_enCodeSession);
    _enCodeSession = nil;
    _dropStep = -1;
    _currentBitRate = _destFormat.baseFormat.bitRate;

}


-(void)dealloc{
    _stopRequest = YES;
    if(_enCodeSession)VTCompressionSessionInvalidate(_enCodeSession);
    GJBufferPoolClean(_bufferPool);
    GJBufferPoolDealloc(&_bufferPool);
}
//-(void)restart{
//
//    [self creatEnCodeSession];
//}

@end
