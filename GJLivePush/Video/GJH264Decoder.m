//
//  GJH264Decoder.m
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import "GJH264Decoder.h"
#import "sps_decode.h"
#import "GJDebug.h"
@interface GJH264Decoder()
{
    dispatch_queue_t _decodeQueue;//解码线程在子线程，主要为了避免decodeBuffer：阻塞，节省时间去接收数据
}
@property(nonatomic)VTDecompressionSessionRef decompressionSession;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) BOOL shouldRestart;

@end
@implementation GJH264Decoder

- (instancetype)init
{
    self = [super init];
    if (self) {
        _decodeQueue = dispatch_queue_create("GJDecodeQueue", DISPATCH_QUEUE_SERIAL);
        _outPutImageFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    }
    return self;
}
-(void) createDecompSession
{
    if (_decompressionSession != nil) {
        VTDecompressionSessionInvalidate(_decompressionSession);
    }
    _shouldRestart = NO;
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decodeOutputCallback;
    
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
    
    NSDictionary *destinationImageBufferAttributes = @{(id)kCVPixelBufferOpenGLESCompatibilityKey:@YES,(id)kCVPixelBufferPixelFormatTypeKey:@(_outPutImageFormat)};
    //使用UIImageView播放时可以设置这个
    //    NSDictionary *destinationImageBufferAttributes =[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO],(id)kCVPixelBufferOpenGLESCompatibilityKey,[NSNumber numberWithInt:kCVPixelFormatType_32BGRA],(id)kCVPixelBufferPixelFormatTypeKey,nil];
    
    OSStatus status =  VTDecompressionSessionCreate(NULL,
                                                    _formatDesc,
                                                    NULL,
                                                    (__bridge CFDictionaryRef)(destinationImageBufferAttributes),
                                                    &callBackRecord,
                                                    &_decompressionSession);
    NSLog(@"Video Decompression Session Create: %@  code:%d  thread:%@", (status == noErr) ? @"successful!" : @"failed...",status,[NSThread currentThread]);
}


void decodeOutputCallback(
                          void * decompressionOutputRefCon,
                          void * sourceFrameRefCon,
                          OSStatus status,
                          VTDecodeInfoFlags infoFlags,
                          CVImageBufferRef imageBuffer,
                          CMTime presentationTimeStamp,
                          CMTime presentationDuration ){
//    NSLog(@"decodeOutputCallback:%@",[NSThread currentThread]);
    
    if (status != 0) {
        GJPrintf("解码error:%d",(int)status);
        return;
    }
//    GJPrintf("pts:%f   ,ptd:%f\n",presentationTimeStamp.value*1.0 / presentationTimeStamp.timescale,presentationDuration.value*1.0/presentationDuration.timescale);
    GJH264Decoder* decoder = (__bridge GJH264Decoder *)(decompressionOutputRefCon);
    if ([decoder.delegate respondsToSelector:@selector(GJH264Decoder:decodeCompleteImageData:pts:)]) {
        [decoder.delegate GJH264Decoder:decoder decodeCompleteImageData:imageBuffer pts:presentationTimeStamp.value*1000/presentationTimeStamp.timescale];
    }
    
}

-(uint8_t*)startCodeIndex:(uint8_t*)sour size:(long)size codeSize:(uint8_t*)codeSize{
    uint8_t* codeIndex = sour;
    while (codeIndex < sour +size -4) {
        if (codeIndex[0] == 0 && codeIndex[1] == 0 && codeIndex[2] == 0 && codeIndex[3] == 1) {
            *codeSize = 4;
            break;
        }else if (codeIndex[0] == 0 && codeIndex[1] == 0 && codeIndex[2] == 1){
            *codeSize = 3;
            break;
        }
        codeIndex++;
    }
    if (codeIndex == sour +size -4) {
        codeIndex = sour +size;
    }
    return codeIndex;
}

-(void)decodeBuffer:(GJRetainBuffer *)buffer pts:(uint64_t)pts
{
//    NSLog(@"decodeFrame:%@",[NSThread currentThread]);
    
    OSStatus status;
    uint8_t *data = NULL;
    uint8_t *pps = NULL;
    uint8_t *sps = NULL;
    uint8_t *frame = buffer->data;
    long frameSize = buffer->size;
    int _spsSize = 0;
    int _ppsSize = 0;
    long blockLength = 0;
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;

    uint8_t fristCodeSize = 0;//兼容三个0和四个0
    uint8_t secondCodeSize = 0;
    uint8_t* fristPoint = [self startCodeIndex:frame size:frameSize codeSize:&fristCodeSize];
    uint8_t* secondPoint = [self startCodeIndex:fristPoint + fristCodeSize size:frame + frameSize - fristPoint - fristCodeSize codeSize:&secondCodeSize];

    while (fristPoint < frame + frameSize) {
        int nalu_type = (fristPoint[fristCodeSize] & 0x1F);
        switch (nalu_type) {
            case 7:
                _spsSize = (int)(secondPoint - fristPoint) - fristCodeSize;
                sps = fristPoint+fristCodeSize;
                int w,h,fps;
                w = h = fps = 0;
                h264_decode_sps(sps, _spsSize, &w, &h, &fps);
                break;
            case 8:{
                _ppsSize = (int)(secondPoint - fristPoint) - fristCodeSize;
                pps = fristPoint+fristCodeSize;
                if (pps && sps) {
                    uint8_t*  parameterSetPointers[2] = {sps, pps};
                    size_t parameterSetSizes[2] = {_spsSize, _ppsSize};
                    
                    CMVideoFormatDescriptionRef  desc;
                    status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                                 (const uint8_t *const*)parameterSetPointers,
                                                                                 parameterSetSizes, 4,
                                                                                 &desc);
                    
                    BOOL shouldReCreate = NO;
                    
                
                    
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
                    CMVideoDimensions currentDimens = CMVideoFormatDescriptionGetDimensions(desc);
                    if (_formatDesc == NULL) {
                        _formatDesc = desc;
                    }else{
                        CMVideoDimensions preDimens = CMVideoFormatDescriptionGetDimensions(_formatDesc);
                        if (currentDimens.width != preDimens.width || currentDimens.height != preDimens.height) {
                            CFRelease(_formatDesc);
                            _formatDesc = desc;
                            shouldReCreate = YES;
                        }else{
                            CFRelease(desc);
                        }
                    }
                    
//                    if (!CMFormatDescriptionEqual(_formatDesc, desc)) {
//                        shouldReCreate = false;
//                        if (_formatDesc) {
//                            CFRelease(_formatDesc);
//                        }
//                        _formatDesc = desc;
//                    }else{
//                        CFRelease(desc);
//                    }
                    if(status == noErr)
                    {
                        if (_decompressionSession == NULL || shouldReCreate || _shouldRestart) {
                            [self createDecompSession];

                        }
                    }
                }
            }
                break;
            case 5:
            case 1:
            {
//                int offset = _spsSize + _ppsSize;
                blockLength = (int)(secondPoint - fristPoint);
                data = fristPoint;
                uint32_t dataLength32 = htonl (blockLength - fristCodeSize);
                memcpy (data, &dataLength32, sizeof (uint32_t));
                status = CMBlockBufferCreateWithMemoryBlock(NULL, data,
                                                            blockLength,
                                                            kCFAllocatorNull, NULL,
                                                            0,
                                                            blockLength,
                                                            0, &blockBuffer);
                
                
                if(status == noErr)
                {
                    const size_t sampleSize = blockLength;
                    CMSampleTimingInfo timingInfo ;
                    timingInfo.decodeTimeStamp = kCMTimeInvalid;
                    timingInfo.duration = kCMTimeInvalid;
                    timingInfo.presentationTimeStamp = CMTimeMake(pts, 1000);
                    status = CMSampleBufferCreate(kCFAllocatorDefault,
                                                  blockBuffer, true, NULL, NULL,
                                                  _formatDesc, 1, 1, &timingInfo, 1,
                                                  &sampleSize, &sampleBuffer);
                    
                    
                    if (status != 0) {
                        GJPrintf("\t\t SampleBufferCreate: \t %d\n", status);
                        goto ERROR;
                    }
                }else{
                    goto ERROR;
                }


                CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
                CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
                CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
                
//                status = CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, pts);
//                
//                assert(status == 0);
                [self render:sampleBuffer];
                CFRelease(sampleBuffer);
                CFRelease(blockBuffer);
            }
                
            default:
                break;
        }
        fristPoint = secondPoint;
        fristCodeSize = secondCodeSize;
        secondPoint = [self startCodeIndex:fristPoint + fristCodeSize size:frame + frameSize - fristPoint - fristCodeSize codeSize:&secondCodeSize];
    }
    
ERROR:
    return;

}

//解码
- (void) render:(CMSampleBufferRef)sampleBuffer
{
    VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags flagOut;
    OSStatus status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags,&sampleBuffer, &flagOut);
    if (status < 0) {
        GJPrintf("解码错误error:%d\n",status);
        _shouldRestart = YES;
    }
}
NSString * const naluTypesStrings[] =
{
    @"0: Unspecified (non-VCL)",
    @"1: Coded slice of a non-IDR picture (VCL)",    // P frame
    @"2: Coded slice data partition A (VCL)",
    @"3: Coded slice data partition B (VCL)",
    @"4: Coded slice data partition C (VCL)",
    @"5: Coded slice of an IDR picture (VCL)",      // I frame
    @"6: Supplemental enhancement information (SEI) (non-VCL)",
    @"7: Sequence parameter set (non-VCL)",         // SPS parameter
    @"8: Picture parameter set (non-VCL)",          // PPS parameter
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
