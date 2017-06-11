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
    GRational _dropStep;//每den帧丢num帧
    
}
@property(nonatomic,assign)VTCompressionSessionRef enCodeSession;
@property(nonatomic,assign)GJBufferPool* bufferPool;
//@property(nonatomic,assign)GInt32 currentBitRate;//当前码率
@property(nonatomic,assign)GJTrafficStatus preBufferStatus;//上一次敏感检测状态

@property(nonatomic,assign)BOOL shouldRestart;
@property(nonatomic,assign)BOOL stopRequest;//防止下一帧满时一直等待


@end

@implementation GJH264Encoder

-(instancetype)initWithSourceSize:(CGSize)size{
    self = [super init];
    if(self){
        _sourceSize = size;
        _bitrate = 600;;
//        _allowMinBitRate = _currentBitRate;
        _dropStep = GRationalMake(0, DEFAULT_MAX_DROP_STEP);
        _allowDropStep = GRationalMake(1, 5);
        _dynamicAlgorithm = GRationalMake(5, 10);
        _allowBFrame = NO;
        
        _profileLevel = profileLevelMain;
        _entropyMode = EntropyMode_CABAC;
        
        [self creatEnCodeSession];
        
    }
    return self;
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
                [self creatEnCodeSession];
                [self setAllParm];
                goto RETRY;
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
        _stopRequest = YES;
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
    _stopRequest = NO;
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
        size_t spsppsSize = sparameterSetSize+pparameterSetSize;
        int needSize = (int)(spsppsSize+totalLength+PUSH_H264_PACKET_PRE_SIZE);
        retainBufferPack(&retainBuffer, GJBufferPoolGetSizeData(encoder.bufferPool,needSize), needSize, retainBufferRelease, encoder.bufferPool);
        if (retainBuffer->frontSize < PUSH_H264_PACKET_PRE_SIZE) {
            retainBufferMoveDataToPoint(retainBuffer, PUSH_H264_PACKET_PRE_SIZE,GFalse);
        }
        uint8_t* data = retainBuffer->data;
        memcpy(&data[0], sparameterSet, sparameterSetSize);
        pushPacket->spsOffset=data - retainBuffer->data;
        pushPacket->spsSize=(int)sparameterSetSize;
        
        memcpy(&data[sparameterSetSize], pparameterSet, pparameterSetSize);
        pushPacket->ppsOffset = sparameterSetSize;
        pushPacket->ppsSize = (int)pparameterSetSize;
//        拷贝keyframe;
        memcpy(data+spsppsSize, inDataPointer, totalLength);
        inDataPointer = data + spsppsSize;
    }else{
        int needSize = (int)(totalLength+PUSH_H264_PACKET_PRE_SIZE);
        retainBufferPack(&retainBuffer, GJBufferPoolGetSizeData(encoder.bufferPool,needSize), needSize, retainBufferRelease, encoder.bufferPool);
        if (retainBuffer->frontSize < PUSH_H264_PACKET_PRE_SIZE) {
            retainBufferMoveDataToPoint(retainBuffer, PUSH_H264_PACKET_PRE_SIZE,GFalse);
        }
//拷贝
        uint8_t* rDate = retainBuffer->data;
        memcpy(rDate, inDataPointer, totalLength);
        inDataPointer = rDate;
    }
    
    pushPacket->ppOffset = inDataPointer - retainBuffer->data;
    pushPacket->ppSize = (GInt32)totalLength;
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    pushPacket->pts = pts.value;
    
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
    
    encoder.completeCallback(pushPacket);
    retainBufferUnRetain(retainBuffer);
    
//    int type;
//    static const uint32_t AVCCHeaderLength = 4;
//    while (bufferOffset < totalLength) {
//        // Read the NAL unit length
//        uint32_t NALUnitLength = 0;
//        memcpy(&NALUnitLength, inDataPointer + bufferOffset, AVCCHeaderLength);
//        NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
//        type = inDataPointer[bufferOffset+AVCCHeaderLength] & 0x1F;
//        if (type == 6) {//SEI
//            
//            pushPacket->seiOffset = inDataPointer+bufferOffset - retainBuffer->data;
//            pushPacket->seiSize =(int)(NALUnitLength+4);
//        }else if (type == 1 || type == 5){//pp
//            pushPacket->ppOffset = inDataPointer+bufferOffset - retainBuffer->data;
//            pushPacket->ppSize =(int)(NALUnitLength+4);
//        }
//        uint8_t* data = inDataPointer + bufferOffset;
//        memcpy(&data[0], "\x00\x00\x00\x01", AVCCHeaderLength);
//        bufferOffset += AVCCHeaderLength + NALUnitLength;
//  
//    }
    
 
}

//
////快降慢升
//-(void)appendQualityWithStep:(GLong)step{
//    GLong leftStep = step;
//    GJEncodeQuality quality = GJEncodeQualityGood;
//    int32_t bitrate = _currentBitRate;
//    GJLOG(GJ_LOGINFO, "appendQualityWithStep：%d",step);
//    if (leftStep > 0 && GRationalValue(_dropStep) > 0.5) {
////        _dropStep += _allowDropStep-1+leftStep;
//        GJAssert(_dropStep.den - _dropStep.num == 1, "管理错误1");
//
//        _dropStep.num -= leftStep;
//        _dropStep.den -= leftStep;
//        leftStep = 0;
//        if (_dropStep.num < 1) {
//            leftStep = 1 - _dropStep.num;
//            _dropStep = GRationalMake(1,2);
//        }else{
//            bitrate = _allowMinBitRate*(1-GRationalValue(_dropStep));
//            bitrate += _allowMinBitRate/_destFormat.baseFormat.fps*I_P_RATE;
//            quality = GJEncodeQualityTerrible;
//            GJLOG(GJ_LOGINFO, "appendQuality by reduce to drop frame:num %d,den %d",_dropStep.num,_dropStep.den);
//        }
//    }
//    if (leftStep > 0 && _dropStep.num != 0) {
//        //        _dropStep += _allowDropStep-1+leftStep;
//        GJAssert(_dropStep.num == 1, "管理错误2");
//        _dropStep.num = 1;
//        _dropStep.den += leftStep;
//        leftStep = 0;
//        if (_dropStep.den > DEFAULT_MAX_DROP_STEP) {
//            leftStep = DEFAULT_MAX_DROP_STEP - _dropStep.den;
//            _dropStep = GRationalMake(0,DEFAULT_MAX_DROP_STEP);
//            bitrate = _allowMinBitRate;
//        }else{
//            bitrate = _allowMinBitRate*(1-GRationalValue(_dropStep));
//            bitrate += bitrate/_destFormat.baseFormat.fps*(1-GRationalValue(_dropStep))*I_P_RATE;
//            quality = GJEncodeQualitybad;
//            GJLOG(GJ_LOGINFO, "appendQuality by reduce to drop frame:num %d,den %d",_dropStep.num,_dropStep.den);
//        }
//    }
//    if(leftStep > 0){
//        if (bitrate < _destFormat.baseFormat.bitRate) {
//            bitrate += (_destFormat.baseFormat.bitRate - _allowMinBitRate)*leftStep*DROP_BITRATE_RATE;
//            bitrate = MIN(bitrate, _destFormat.baseFormat.bitRate);
//            quality = GJEncodeQualityGood;
//        }else{
//            quality = GJEncodeQualityExcellent;
//            bitrate = _destFormat.baseFormat.bitRate;
//            GJLOG(GJ_LOGINFO, "appendQuality to full speed:%f",_currentBitRate/1024.0/8.0);
//        }
//    }
//    if (_currentBitRate != bitrate) {
//        self.currentBitRate = bitrate;
//        if ([self.deleagte respondsToSelector:@selector(GJH264Encoder:qualityQarning:)]) {
//            [self.deleagte GJH264Encoder:self qualityQarning:GJEncodeQualityExcellent];
//        }
//    }
// 
//}
//-(void)reduceQualityWithStep:(GLong)step{
//    GLong leftStep = step;
//    int currentBitRate = _currentBitRate;
//    GJEncodeQuality quality = GJEncodeQualityGood;
//    int32_t bitrate = _currentBitRate;
//    
//    GJLOG(GJ_LOGINFO, "reduceQualityWithStep：%d",step);
//
//    if (_currentBitRate > _allowMinBitRate) {
//        bitrate -= (_destFormat.baseFormat.bitRate - _allowMinBitRate)*leftStep*DROP_BITRATE_RATE;
//        leftStep = 0;
//        if (bitrate < _allowMinBitRate) {
//            leftStep = (currentBitRate - bitrate)/((_destFormat.baseFormat.bitRate - _allowMinBitRate)*DROP_BITRATE_RATE);
//            bitrate = _allowMinBitRate;
//        }
//        quality = GJEncodeQualityGood;
//    }
//    if (leftStep > 0 && GRationalValue(_dropStep) <= 0.50001 && GRationalValue(_dropStep) < GRationalValue(_allowDropStep)){
//        if(_dropStep.num == 0)_dropStep = GRationalMake(1, DEFAULT_MAX_DROP_STEP);
//        _dropStep.num = 1;
//        _dropStep.den -= leftStep;
//        leftStep = 0;
//        
//        GRational tempR = GRationalMake(1, 2);
//        if (GRationalValue(_allowDropStep) < 0.5) {
//            tempR = _allowDropStep;
//        }
//        if (_dropStep.den < tempR.den) {
//            leftStep = tempR.den - _dropStep.den;
//            _dropStep.den = tempR.den;
//        }else{
//        
//            bitrate = _allowMinBitRate*(1-GRationalValue(_dropStep));
//            bitrate += bitrate/_destFormat.baseFormat.fps*(1-GRationalValue(_dropStep))*I_P_RATE;
//            quality = GJEncodeQualitybad;
//            GJLOG(GJ_LOGINFO, "reduceQuality1 by reduce to drop frame:num %d,den %d",_dropStep.num,_dropStep.den);
//
//        }
//    }
//    if (leftStep > 0 && GRationalValue(_dropStep) < GRationalValue(_allowDropStep)){
//        _dropStep.num += leftStep;
//        _dropStep.den += leftStep;
//        if(_dropStep.den > _allowDropStep.den){
//            _dropStep.num -= _dropStep.den - _allowDropStep.den;
//            _dropStep.den = _allowDropStep.den;
//        }
//        bitrate = _allowMinBitRate*(1-GRationalValue(_dropStep));
//        bitrate += bitrate/_destFormat.baseFormat.fps*(1-GRationalValue(_dropStep))*I_P_RATE;
//        quality = GJEncodeQualityTerrible;
//        GJLOG(GJ_LOGINFO, "reduceQuality2 by reduce to drop frame:num %d,den %d",_dropStep.num,_dropStep.den);
//    }
//    self.currentBitRate = bitrate;
//    if ([self.deleagte respondsToSelector:@selector(GJH264Encoder:qualityQarning:)]) {
//        [self.deleagte GJH264Encoder:self qualityQarning:quality];
//    }
//}
-(void)flush{
    _stopRequest = YES;
    if(_enCodeSession)VTCompressionSessionInvalidate(_enCodeSession);
    _enCodeSession = nil;
    _dropStep = GRationalMake(0, 1);
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
