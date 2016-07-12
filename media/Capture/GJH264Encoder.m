//
//  GJH264Encoder.m
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import "GJH264Encoder.h"
@interface GJH264Encoder()
{
    long encoderFrameCount;
    int32_t _currentWidth;
    int32_t _currentHeight;
    
}
@property(nonatomic)VTCompressionSessionRef enCodeSession;
@end

@implementation GJH264Encoder
int _keyInterval;////key内的p帧数量

GJH264Encoder* encoder ;
- (instancetype)init
{
    self = [super init];
    if (self) {
        encoder = self;
    }
    return self;
}



//编码
-(void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    BOOL fourceKey;
    CVImageBufferRef imgRef = CMSampleBufferGetImageBuffer(sampleBuffer);
    int32_t h = (int32_t)CVPixelBufferGetHeight(imgRef);
    int32_t w = (int32_t)CVPixelBufferGetWidth(imgRef);
    if (_enCodeSession == nil || h != _currentHeight || w != _currentWidth) {
        fourceKey = YES;
        [self creatEnCodeSessionWithWidth:w height:h];
    }
    CMTime presentationTimeStamp = CMTimeMake(encoderFrameCount, 10);
    NSMutableDictionary * properties = [[NSMutableDictionary alloc]init];
    [properties setObject:@1.0f forKey:(__bridge NSString *)kVTCompressionPropertyKey_Quality];
    [properties setObject:@(300*1000) forKey:(__bridge NSString *)kVTCompressionPropertyKey_AverageBitRate];
    if (fourceKey) {
        [properties setObject:@YES forKey:(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame];
    }
    OSStatus status = VTCompressionSessionEncodeFrame(
                                                      _enCodeSession,
                                                      imgRef,
                                                      presentationTimeStamp,
                                                      kCMTimeInvalid, // may be kCMTimeInvalid
                                                       (__bridge CFDictionaryRef)properties,
                                                      NULL,
                                                      NULL );
    encoderFrameCount++;
    if (status != 0) {
        NSLog(@"encodeSampleBuffer error:%d",(int)status);
        return;
    }
    
}

-(void)creatEnCodeSessionWithWidth:(int32_t)w height:(int32_t)h{
    if (_enCodeSession != nil) {
        VTCompressionSessionInvalidate(_enCodeSession);
    }
    OSStatus t = VTCompressionSessionCreate(
                                            NULL,
                                            w,
                                            h,
                                            kCMVideoCodecType_H264,
                                            NULL,
                                            NULL,
                                            NULL,
                                            encodeOutputCallback,
                                            NULL,
                                            &_enCodeSession);
    NSLog(@"VTCompressionSessionCreate status:%d",(int)t);
    _currentWidth = w;
    _currentHeight = h;
    VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    //b帧
    VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue);
    VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_5_2);
    VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC);
    
    SInt32 bitRate = 0.5;
    CFNumberRef ref = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
    VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AverageBitRate, ref);
    CFRelease(ref);
    
    float quality = 0.1;
    CFNumberRef  qualityRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberFloatType,&quality);
    VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_Quality,qualityRef);
    CFRelease(qualityRef);
    
    int frameInterval = 10;
    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
    VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval,frameIntervalRef);
    CFRelease(frameIntervalRef);
    
    VTCompressionSessionPrepareToEncodeFrames(_enCodeSession);
    //    UInt32 num = 5;
    //    ref = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type,&num);
    //    VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_ExpectedFrameRate,ref);
    
    
}

void encodeOutputCallback(void *  outputCallbackRefCon,void *  sourceFrameRefCon,OSStatus statu,VTEncodeInfoFlags infoFlags,
                          CMSampleBufferRef sample ){
    if (statu != 0) return;
    if (!CMSampleBufferDataIsReady(sample))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sample);
    size_t length, totalLength;
    uint8_t *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, (char**)&dataPointer);
    
    
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sample, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    if (keyframe)
    {
        NSLog(@"key interval%d",_keyInterval);
        _keyInterval = -1;
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
        size_t sparameterSetSize, sparameterSetCount;
        int spHeadSize;
        int ppHeadSize;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, &spHeadSize );
        if (statusCode == noErr)
        {
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, &ppHeadSize );
            if (statusCode == noErr)
            {
                uint8_t* data = malloc(4+4+sparameterSetSize+pparameterSetSize);
                memcpy(&data[0], "\x00\x00\x00\x01", 4);
                memcpy(&data[4], sparameterSet, sparameterSetSize);
                memcpy(&data[4+sparameterSetSize], "\x00\x00\x00\x01", 4);
                memcpy(&data[8+sparameterSetSize], pparameterSet, pparameterSetSize);
                
                if ([encoder.deleagte respondsToSelector:@selector(GJH264Encoder:encodeCompleteBuffer:withLenth:)]) {
                    [encoder.deleagte GJH264Encoder:encoder encodeCompleteBuffer:data withLenth:pparameterSetSize+sparameterSetSize+8];
                }
                free(data);
            }
        }
        
        //抛弃sps,pps
        uint32_t spsPpsLength = 0;
        memcpy(&spsPpsLength, dataPointer, 4);
        spsPpsLength = CFSwapInt32BigToHost(spsPpsLength);
        dataPointer += spsPpsLength + 4;
        totalLength -= spsPpsLength + 4;

    }
    

    
    if (statusCodeRet == noErr) {
        
        uint32_t bufferOffset = 0;
        static const uint32_t AVCCHeaderLength = 4;
        while (bufferOffset < totalLength) {
            
            _keyInterval++;
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            uint8_t* data = dataPointer + bufferOffset;
            memcpy(&data[0], "\x00\x00\x00\x01", AVCCHeaderLength);
            
            [encoder.deleagte GJH264Encoder:encoder encodeCompleteBuffer:data withLenth:NALUnitLength +AVCCHeaderLength];
            NSLog(@"h264编码成功,%d",NALUnitLength);
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
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
