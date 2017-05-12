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
#define I_P_RATE 4

#define DEFAULT_CHECK_DELAY 1000
#define DROP_BITRATE_RATE 0.1

@interface GJH264Encoder()
{
    GRational _dropStep;//每den帧丢num帧
    
}
@property(nonatomic,assign)VTCompressionSessionRef enCodeSession;
@property(nonatomic,assign)GJBufferPool* bufferPool;
@property(nonatomic,assign)GInt32 currentBitRate;//当前码率
@property(nonatomic,assign)GJTrafficStatus preBufferStatus;//上一次敏感检测状态

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
            _dropStep = GRationalMake(0, DEFAULT_MAX_DROP_STEP);
            _allowDropStep = GRationalMake(1, 2);
            _dynamicAlgorithm = GRationalMake(5, 10);
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
-(void)setAllowDropStep:(GRational)allowDropStep{
    if (allowDropStep.num > 1) {
        if (allowDropStep.den == allowDropStep.num) {
            _allowDropStep = allowDropStep;
        }else{
            GJLOG(GJ_LOGFORBID, "当num大于1时，den一定要等于num+1");
        }
    }else if(allowDropStep.num == 1){
        if (allowDropStep.den > DEFAULT_MAX_DROP_STEP) {
            GJLOG(GJ_LOGWARNING, "当num等于1时，den不能大于DEFAULT_MAX_DROP_STEP，自动修改");
            allowDropStep.den =DEFAULT_MAX_DROP_STEP;
            _allowDropStep = allowDropStep;
        }else if (allowDropStep.den <= 0){
            GJLOG(GJ_LOGFORBID, "den一定要等于1");
        }
    }else if(allowDropStep.num < 0){
        GJLOG(GJ_LOGFORBID, "num一定要大于1");
    }else{ //num == 0
        _allowDropStep = allowDropStep;
    }
}
//编码
-(BOOL)encodeImageBuffer:(CVImageBufferRef)imageBuffer pts:(int64_t)pts fourceKey:(BOOL)fourceKey
{
    if ((_frameCount++) % _dropStep.den < _dropStep.num) {
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
                GJLOG(GJ_LOGWARNING,"编码失败 kVTInvalidSessionErr,重新编码");
                VTCompressionSessionInvalidate(_enCodeSession);
                _enCodeSession = nil;
                goto RETRY;
            }else{
                GJLOG(GJ_LOGFORBID,"编码失败：%d",status);
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
    memset(&_preBufferStatus, 0, sizeof(_preBufferStatus));
    if (_bufferPool != NULL) {
        __block GJBufferPool* pool = _bufferPool;
        _bufferPool = NULL;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            GJBufferPoolClean(pool,true);
            GJBufferPoolFree(&pool);
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
        GJLOG(GJ_LOGFORBID,"kVTCompressionPropertyKey_AllowFrameReordering set error");
    }
    //p帧
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AllowTemporalCompression, _destFormat.allowPframe?kCFBooleanTrue:kCFBooleanFalse);
    if (result != 0) {
        GJLOG(GJ_LOGFORBID,"kVTCompressionPropertyKey_AllowTemporalCompression set error");
    }
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_ProfileLevel, getCFStrByLevel(_destFormat.level));
    if (result != 0) {
        GJLOG(GJ_LOGFORBID,"kVTCompressionPropertyKey_ProfileLevel set error");
    }
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_H264EntropyMode, getCFStrByEntropyMode(_destFormat.model));
    if (result != 0) {
        GJLOG(GJ_LOGFORBID,"kVTCompressionPropertyKey_H264EntropyMode set error");
    }
    
    [self setCurrentBitRate:_currentBitRate];
    

    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &(_destFormat.gopSize));
    result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval,frameIntervalRef);
    CFRelease(frameIntervalRef);
    if (result != 0) {
        GJLOG(GJ_LOGFORBID,"kVTCompressionPropertyKey_MaxKeyFrameInterval set error");
    }

}

-(void)setCurrentBitRate:(int32_t)currentBitRate{
    if (currentBitRate>0 && _enCodeSession) {
        _currentBitRate = currentBitRate;
        CFNumberRef bitRate = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &(_currentBitRate));
        OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AverageBitRate, bitRate);
        CFRelease(bitRate);
        if (result != noErr) {
            GJLOG(GJ_LOGFORBID, "kVTCompressionPropertyKey_AverageBitRate set error:%d",result);
        }else{
            GJLOG(GJ_LOGINFO, "set video bitrate:%0.2f kB/s",currentBitRate/1024.0/8.0);
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
    R_GJH264Packet* pushPacket = (R_GJH264Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJH264Packet));
    GJRetainBuffer* retainBuffer = &pushPacket->retain;
    memset(pushPacket, 0, sizeof(R_GJH264Packet));
#define PUSH_H264_PACKET_PRE_SIZE 45
    
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
        size_t spsppsSize = 4+4+sparameterSetSize+pparameterSetSize;
        int needSize = (int)(spsppsSize+totalLength+PUSH_H264_PACKET_PRE_SIZE);
        retainBufferPack(&retainBuffer, GJBufferPoolGetSizeData(encoder.bufferPool,needSize), needSize, retainBufferRelease, encoder.bufferPool);
        if (retainBuffer->frontSize < PUSH_H264_PACKET_PRE_SIZE) {
            retainBufferMoveDataToPoint(retainBuffer, PUSH_H264_PACKET_PRE_SIZE,GFalse);
        }
        uint8_t* data = retainBuffer->data;
        memcpy(&data[0], "\x00\x00\x00\x01", 4);
//        memcpy(&data[0], &sparameterSetSize, 4);
        memcpy(&data[4], sparameterSet, sparameterSetSize);
        pushPacket->spsOffset=data - retainBuffer->data;
        pushPacket->spsSize=4+(int)sparameterSetSize;
        memcpy(&data[4+sparameterSetSize], "\x00\x00\x00\x01", 4);
//        memcpy(&data[4+sparameterSetSize], &pparameterSetSize, 4);
        memcpy(&data[8+sparameterSetSize], pparameterSet, pparameterSetSize);
        pushPacket->ppsOffset = data+4+sparameterSetSize - retainBuffer->data;
        pushPacket->ppsSize = 4+(int)pparameterSetSize;
//        拷贝keyframe;
        memcpy(data+spsppsSize, inDataPointer, totalLength);
        inDataPointer = data + spsppsSize;
    }else{
        int needSize = (int)(totalLength+PUSH_H264_PACKET_PRE_SIZE);
        retainBufferPack(&retainBuffer, GJBufferPoolGetSizeData(encoder.bufferPool,needSize), needSize, retainBufferRelease, encoder.bufferPool);
        if (retainBuffer->frontSize < PUSH_H264_PACKET_PRE_SIZE) {
            retainBufferMoveDataToPoint(retainBuffer, PUSH_H264_PACKET_PRE_SIZE,GFalse);
        }
        uint8_t* rDate = retainBuffer->data;
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
            
            pushPacket->seiOffset = inDataPointer+bufferOffset - retainBuffer->data;
            pushPacket->seiSize =(int)(NALUnitLength+4);
        }else if (type == 1 || type == 5){//pp
            pushPacket->ppOffset = inDataPointer+bufferOffset - retainBuffer->data;
            pushPacket->ppSize =(int)(NALUnitLength+4);
        }
        uint8_t* data = inDataPointer + bufferOffset;
        memcpy(&data[0], "\x00\x00\x00\x01", AVCCHeaderLength);
        bufferOffset += AVCCHeaderLength + NALUnitLength;
  
    }
    
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
//    GJAssert(pushPacket->retain.capacity >= pushPacket->seiSize+pushPacket->spsSize+pushPacket->ppSize+pushPacket->ppsSize, "数据出错\n");
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
    GJTrafficStatus bufferStatus = [encoder.deleagte GJH264Encoder:encoder encodeCompletePacket:pushPacket];
  
    if (bufferStatus.enter.count % encoder.dynamicAlgorithm.den == 0) {//DEFAULT_CHECK_DELAY ms一次常规不敏感检测，但是最准确
        GLong cacheInCount = bufferStatus.enter.count - bufferStatus.leave.count;
  
        if(cacheInCount == 1 && encoder.currentBitRate < encoder.destFormat.baseFormat.bitRate){
            GJLOG(GJ_LOGINFO, "宏观检测出提高视频质量");
            [encoder appendQualityWithStep:1];
        }else{
            GLong diffInCount = bufferStatus.leave.count - encoder.preBufferStatus.leave.count;
            if(diffInCount <= encoder.dynamicAlgorithm.num){//降低质量敏感检测,丢帧时有误差
                GJLOG(GJ_LOGINFO, "敏感检测出降低视频质量");
                [encoder reduceQualityWithStep:encoder.dynamicAlgorithm.num - diffInCount+1];
            }else if(diffInCount > encoder.dynamicAlgorithm.den + encoder.dynamicAlgorithm.num){//提高质量敏感检测,丢帧时有误差
                GJLOG(GJ_LOGINFO, "敏感检测出提高音频质量");
                [encoder appendQualityWithStep:diffInCount - encoder.dynamicAlgorithm.den - encoder.dynamicAlgorithm.num];
            }else{
                GLong cacheInPts = bufferStatus.enter.pts - bufferStatus.leave.pts;
                if (diffInCount < encoder.dynamicAlgorithm.den && cacheInPts > SEND_DELAY_TIME && cacheInCount > SEND_DELAY_COUNT) {
                    GJLOG(GJ_LOGWARNING, "宏观检测出降低视频质量 (很少可能会出现)");
                    [encoder reduceQualityWithStep:encoder.dynamicAlgorithm.den - diffInCount];
                }
            }
        }
        encoder.preBufferStatus = bufferStatus;
    }
    retainBufferUnRetain(retainBuffer);
}


//快降慢升
-(void)appendQualityWithStep:(GLong)step{
    GLong leftStep = step;
    GJEncodeQuality quality = GJEncodeQualityGood;
    int32_t bitrate = _currentBitRate;
    GJLOG(GJ_LOGINFO, "appendQualityWithStep：%d",step);
    if (leftStep > 0 && GRationalValue(_dropStep) > 0.5) {
//        _dropStep += _allowDropStep-1+leftStep;
        GJAssert(_dropStep.den - _dropStep.num == 1, "管理错误1");

        _dropStep.num -= leftStep;
        _dropStep.den -= leftStep;
        leftStep = 0;
        if (_dropStep.num < 1) {
            leftStep = 1 - _dropStep.num;
            _dropStep = GRationalMake(1,2);
        }else{
            bitrate = _allowMinBitRate*(1-GRationalValue(_dropStep));
            bitrate += _allowMinBitRate/_destFormat.baseFormat.fps*I_P_RATE;
            quality = GJEncodeQualityTerrible;
            GJLOG(GJ_LOGINFO, "appendQuality by reduce to drop frame:num %d,den %d",_dropStep.num,_dropStep.den);
        }
    }
    if (leftStep > 0 && _dropStep.num != 0) {
        //        _dropStep += _allowDropStep-1+leftStep;
        GJAssert(_dropStep.num == 1, "管理错误2");
        _dropStep.num = 1;
        _dropStep.den += leftStep;
        leftStep = 0;
        if (_dropStep.den > DEFAULT_MAX_DROP_STEP) {
            leftStep = DEFAULT_MAX_DROP_STEP - _dropStep.den;
            _dropStep = GRationalMake(0,DEFAULT_MAX_DROP_STEP);
            bitrate = _allowMinBitRate;
        }else{
            bitrate = _allowMinBitRate*(1-GRationalValue(_dropStep));
            bitrate += bitrate/_destFormat.baseFormat.fps*(1-GRationalValue(_dropStep))*I_P_RATE;
            quality = GJEncodeQualitybad;
            GJLOG(GJ_LOGINFO, "appendQuality by reduce to drop frame:num %d,den %d",_dropStep.num,_dropStep.den);
        }
    }
    if(leftStep > 0){
        if (bitrate < _destFormat.baseFormat.bitRate) {
            bitrate += (_destFormat.baseFormat.bitRate - _allowMinBitRate)*leftStep*DROP_BITRATE_RATE;
            bitrate = MIN(bitrate, _destFormat.baseFormat.bitRate);
            quality = GJEncodeQualityGood;
        }else{
            quality = GJEncodeQualityExcellent;
            bitrate = _destFormat.baseFormat.bitRate;
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
-(void)reduceQualityWithStep:(GLong)step{
    GLong leftStep = step;
    int currentBitRate = _currentBitRate;
    GJEncodeQuality quality = GJEncodeQualityGood;
    int32_t bitrate = _currentBitRate;
    
    GJLOG(GJ_LOGINFO, "reduceQualityWithStep：%d",step);

    if (_currentBitRate > _allowMinBitRate) {
        bitrate -= (_destFormat.baseFormat.bitRate - _allowMinBitRate)*leftStep*DROP_BITRATE_RATE;
        leftStep = 0;
        if (bitrate < _allowMinBitRate) {
            leftStep = (currentBitRate - bitrate)/((_destFormat.baseFormat.bitRate - _allowMinBitRate)*DROP_BITRATE_RATE);
            bitrate = _allowMinBitRate;
        }
        quality = GJEncodeQualityGood;
    }
    if (leftStep > 0 && GRationalValue(_dropStep) <= 0.50001 && GRationalValue(_dropStep) < GRationalValue(_allowDropStep)){
        if(_dropStep.num == 0)_dropStep = GRationalMake(1, DEFAULT_MAX_DROP_STEP);
        _dropStep.num = 1;
        _dropStep.den -= leftStep;
        leftStep = 0;
        
        GRational tempR = GRationalMake(1, 2);
        if (GRationalValue(_allowDropStep) < 0.5) {
            tempR = _allowDropStep;
        }
        if (_dropStep.den < tempR.den) {
            leftStep = tempR.den - _dropStep.den;
            _dropStep.den = tempR.den;
        }else{
        
            bitrate = _allowMinBitRate*(1-GRationalValue(_dropStep));
            bitrate += bitrate/_destFormat.baseFormat.fps*(1-GRationalValue(_dropStep))*I_P_RATE;
            quality = GJEncodeQualitybad;
            GJLOG(GJ_LOGINFO, "reduceQuality1 by reduce to drop frame:num %d,den %d",_dropStep.num,_dropStep.den);

        }
    }
    if (leftStep > 0 && GRationalValue(_dropStep) < GRationalValue(_allowDropStep)){
        _dropStep.num += leftStep;
        _dropStep.den += leftStep;
        if(_dropStep.den > _allowDropStep.den){
            _dropStep.num -= _dropStep.den - _allowDropStep.den;
            _dropStep.den = _allowDropStep.den;
        }
        bitrate = _allowMinBitRate*(1-GRationalValue(_dropStep));
        bitrate += bitrate/_destFormat.baseFormat.fps*(1-GRationalValue(_dropStep))*I_P_RATE;
        quality = GJEncodeQualityTerrible;
        GJLOG(GJ_LOGINFO, "reduceQuality2 by reduce to drop frame:num %d,den %d",_dropStep.num,_dropStep.den);
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
    _dropStep = GRationalMake(0, 1);
    _currentBitRate = _destFormat.baseFormat.bitRate;

}


-(void)dealloc{
    _stopRequest = YES;
    if(_enCodeSession)VTCompressionSessionInvalidate(_enCodeSession);
    if (_bufferPool) {
        GJBufferPoolClean(_bufferPool,true);
        GJBufferPoolFree(&_bufferPool);
    }
}
//-(void)restart{
//
//    [self creatEnCodeSession];
//}

@end
