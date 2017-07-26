 //
//  ScreenRecorder.m
//  ScreenRecorderDemo
//
//  Created by mac on 16/11/17.
//  Copyright © 2016年 zhouguangjin. All rights reserved.
//

#import "GJScreenRecorder.h"
#import "GJQueue.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "GJLog.h"




@interface GJScreenRecorder()
{
    GJQueue* _imageCache;//缓冲
    GJQueue* _audioCache;//缓冲

    dispatch_queue_t _audioWriteQueue;
    dispatch_queue_t _videoWriteQueue;
    NSInteger* _totalCount;
    
    AVAssetWriter *_assetWriter;
    AVAssetWriterInput *_videoInput;
    AVAssetWriterInput *_audioInput;
    dispatch_queue_t _dispatchQueue;
    double _startTime;
    double _audioTime;
    AudioStreamBasicDescription _format;
    CMFormatDescriptionRef _formatDesc;
    
    uint8_t* _slientData;
}
@property(strong,nonatomic)CADisplayLink* fpsTimer;
@property(strong,nonatomic)NSRunLoop* captureRunLoop;

@end

@implementation GJScreenRecorder

- (instancetype)initWithDestUrl:(NSURL*)url;
{
    self = [super init];
    if (self) {
        _slientData = malloc(1024*16);
        memset(_slientData, 0, 1024*16);
        _audioWriteQueue = dispatch_queue_create("audioWriteQueue", DISPATCH_QUEUE_SERIAL);
        _videoWriteQueue = dispatch_queue_create("videoWriteQueue", DISPATCH_QUEUE_SERIAL);

        queueCreate(&_imageCache, 10, true, true);
        queueCreate(&_audioCache, 30, true, true);
        _captureQueue = dispatch_queue_create("GJScreenRecorderQueue", DISPATCH_QUEUE_SERIAL);

        _status = screenRecorderStopStatus;
        _destFileUrl = url;
        if([[NSFileManager defaultManager] fileExistsAtPath:self.destFileUrl.path])
        {
            //remove the old one
            [[NSFileManager defaultManager] removeItemAtPath:self.destFileUrl.path error:nil];
        }
        
        NSError *error = nil;
        
        unlink([self.destFileUrl path].UTF8String);
        _assetWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:self.destFileUrl.path]
                                                 fileType:AVFileTypeQuickTimeMovie
                                                    error:&error];
        if(error)GJLOG(GJ_LOGFORBID,"error = %@", [error localizedDescription].description);
    }
    return self;
}

#pragma mark interface

-(UIImage*)captureImageWithView:(UIView*)view{
    UIImage *image ;
    UIGraphicsBeginImageContext(view.bounds.size);
    [view drawViewHierarchyInRect:self.captureView.frame afterScreenUpdates:NO];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
-(BOOL)startWithView:(UIView*)targetView fps:(NSInteger)fps{
    if (_status != screenRecorderStopStatus || _videoInput != nil) {
        return NO;
    }
    
    _captureView=targetView;
    _captureFrame = [self _getRootFrameWithView:targetView];
    _status = screenRecorderRecorderingStatus;
    _fps = fps;
    queueEnablePop(_imageCache, true);
    queueEnablePop(_audioCache, true);

    //start
    BOOL result = [self _writeFile];
    if (result == NO) {
        return NO;
    }
    __weak GJScreenRecorder* wkSelf = self;
    if(fps>0){
        dispatch_async(_captureQueue, ^{
            wkSelf.fpsTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(_captureCurrentView)];
            wkSelf.fpsTimer.preferredFramesPerSecond = fps;
            wkSelf.captureRunLoop = [NSRunLoop currentRunLoop];
            [wkSelf.fpsTimer addToRunLoop:wkSelf.captureRunLoop forMode:NSDefaultRunLoopMode];
            [[NSRunLoop currentRunLoop]run];
        });

    }else{
        return NO;
    }
    return YES;
}



-(void)stopRecord{
   GJLOG(GJ_LOGINFO, "stop uirecord\n");
    if (_status == screenRecorderStopStatus) {
        return ;
    }
    _status = screenRecorderStopStatus;

    [_fpsTimer removeFromRunLoop:_captureRunLoop forMode:NSDefaultRunLoopMode];
    
    if (_fpsTimer) {
        [_fpsTimer invalidate];
        _fpsTimer=nil;
    }
    _captureRunLoop = nil;

}
-(void)pause{
    _status = screenRecorderPauseStatus;
}
-(void)resume{
    _status = screenRecorderRecorderingStatus;
}
-(BOOL)setExternalAudioSourceWithFormat:(AudioStreamBasicDescription)streamFormat{
    if (streamFormat.mSampleRate > 0) {
        NSDictionary* audioOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                            [ NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                                            [ NSNumber numberWithInt: streamFormat.mChannelsPerFrame ], AVNumberOfChannelsKey,
                                            [ NSNumber numberWithFloat: streamFormat.mSampleRate  ], AVSampleRateKey,
                                             //[ NSNumber numberWithInt:AVAudioQualityLow], AVEncoderAudioQualityKey,
//                                             [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
                                             nil];
        
        _audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioOutputSettings];
        if (_audioInput == nil) {
            return NO;
        }
//        _audioInput.expectsMediaDataInRealTime = YES;
        if (![_assetWriter canAddInput:_audioInput]) {
            return NO;
        }
        [_assetWriter addInput:_audioInput];
        _format = streamFormat;
        OSStatus status = CMAudioFormatDescriptionCreate(NULL, &_format, 0, NULL, 0, NULL, NULL, &_formatDesc);
        return status == noErr;
    }else{
        return NO;
    }
}
-(void)finshWrite{
    [_assetWriter finishWritingWithCompletionHandler:^{
        NSError* error = _assetWriter.error;
        GJLOG(GJ_LOGINFO, "_assetWriter finishWriting");
        if (self.callback) {
            self.callback(self.destFileUrl, error);
            self.callback = nil;
        }else{
        
        }
        if (queueGetLength(_imageCache)) {
            int length = queueGetLength(_imageCache);
            void** imageArry = malloc(sizeof(void*)*length);;
            if (queueClean(_imageCache, imageArry, &length)) {
                for (int i = 0; i<length; i++) {
                    NSArray* arry = CFBridgingRelease(imageArry[i]);
                    arry = nil;
                }
            }
            free(imageArry);
        }
        
        if (queueGetLength(_audioCache)) {
            int length = queueGetLength(_audioCache);
            CMSampleBufferRef* audioArry = (CMSampleBufferRef*)malloc(sizeof(CMSampleBufferRef)*length);
            if (queueClean(_audioCache, (GHandle*)audioArry, &length)) {
                for (int i = 0; i<length; i++) {
                    CMSampleBufferRef sample = audioArry[i];
                    CFRelease(sample);
                }
            }
            free(audioArry);
        }
        
        _assetWriter = nil;
    }];

}


-(BOOL)createBlackSampleBufferWithSample:(CMSampleBufferRef*)sample data:(uint8_t*)data size:(int)blockSize frames:(int)frames pts:(double)blockPts{
    CMBlockBufferRef blockbuffer;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL, data, blockSize, NULL, NULL, 0, blockSize, 0, &blockbuffer);
    if (status != noErr) {
        NSLog(@"CMBlockBufferCreateWithMemoryBlock error");
        return NO;
    }
    
//    RecorderLOG(@"receive AudioPts fill:%f dt:%f",blockPts,blockDuring*1000);
    
    status = CMAudioSampleBufferCreateWithPacketDescriptions(kCFAllocatorDefault, blockbuffer, YES, NULL, NULL, _formatDesc, frames, CMTimeMake((int64_t)blockPts, 1000), NULL, sample);
    if (status != noErr) {
        CFRelease(blockbuffer);
        return NO;
    }
    return YES;
}

-(void)addCurrentAudioSource:(uint8_t*)data size:(int)size{
    if (_status != screenRecorderRecorderingStatus || _startTime <= 0) {
        return;
    }
    double pts = 0;

    double during = size/_format.mBytesPerFrame / _format.mSampleRate;
    double currentTime = CFAbsoluteTimeGetCurrent();
 
    @synchronized (self) {
        if (currentTime - _audioTime >2 * during) {
            int totalLength = (currentTime - _audioTime - during)*_format.mSampleRate*_format.mBytesPerFrame;
            while (totalLength >= size) {
                
                CMSampleBufferRef sample =  NULL;
                if([self createBlackSampleBufferWithSample:&sample data:_slientData size:size frames:size/_format.mBytesPerFrame pts:(_audioTime - _startTime)*1000]){
                    if(!queuePush(_audioCache, sample, 0)){
                        CFRelease(sample);
                    }
                    _audioTime += during;

                }else{
                    return;
                }
                
                totalLength -= size;
            }
        }if (_audioTime - currentTime > during*0.5) {
            GJLOG(GJ_LOGWARNING, "pts 太快 丢帧",pts);
            return;
        }
        pts = (_audioTime - _startTime)*1000;
        _audioTime += during;
        CMSampleBufferRef sample = NULL;
        if ([self createBlackSampleBufferWithSample:&sample data:data size:size frames:size/_format.mBytesPerFrame pts:pts]) {
            if(!queuePush(_audioCache, sample, 0)){
                CFRelease(sample);
            }
        }
    }

}

#pragma mark internal

-(void)_captureCurrentView{
    UIGraphicsBeginImageContextWithOptions(self.captureFrame.size, YES, 1.0);
    [self.captureView drawViewHierarchyInRect:self.captureFrame afterScreenUpdates:NO];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) {
        double pts = 0;
        @synchronized (self) {
            if (_startTime <= 0) {
                _audioTime = _startTime = CFAbsoluteTimeGetCurrent();
                
            }
            pts = (CFAbsoluteTimeGetCurrent() - _startTime)*1000;

        }
        static double preVPts;
        
        GJLOG(GJ_LOGINFO, "receive video Pts:%f,dt:%f",pts,pts-preVPts);
        preVPts = pts;

        NSArray* arry = @[image,@(pts)];
        if(queuePush(_imageCache, (GHandle)CFBridgingRetain(arry), INT_MAX)){
            _totalCount++;
        }else{
            CFBridgingRelease((__bridge CFTypeRef _Nullable)(arry));
        }
    }
}

-(CGRect)_getRootFrameWithView:(UIView*)view{
    CGRect rect = view.frame;
    UIView* superView = view.superview;
    while (superView) {
        rect.origin.x += superView.frame.origin.x;
        rect.origin.y += superView.frame.origin.y;
        superView = superView.superview;
    }
    return rect;
}


-(NSURL *)destFileUrl{
    if (_destFileUrl == nil) {
        NSDateFormatter* format = [[NSDateFormatter alloc]init];
        [format setDateFormat:@"yyyy_MM_dd_HH_mm_ss"];
        NSString* path = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
        path = [path stringByAppendingPathComponent:@"RecoderFile"];
        if (![[NSFileManager defaultManager]fileExistsAtPath:path]) {
            [[NSFileManager defaultManager]createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString* file = [format stringFromDate:[NSDate date]];
        path = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4",file]];
        _destFileUrl = [NSURL fileURLWithPath:path];
    }
    return _destFileUrl;
}


-(BOOL)_writeFile{
    
    CGSize size = _captureFrame.size;
    if (size.width < 1 || size.height < 1) {
        return NO;
    }
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:AVVideoCodecH264, AVVideoCodecKey,
                                   [NSNumber numberWithInt:size.width], AVVideoWidthKey,
                                   [NSNumber numberWithInt:size.height], AVVideoHeightKey, nil];
    _videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    NSDictionary *sourcePixelBufferAttributesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                                           [NSNumber numberWithInt:       kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey,
                                                           [NSNumber numberWithInt:size.width], kCVPixelBufferWidthKey,
                                                           [NSNumber numberWithInt:size.height], kCVPixelBufferHeightKey,
                                                           [NSNumber numberWithBool:YES],
                                                           kCVPixelBufferCGBitmapContextCompatibilityKey,
                                                           nil];
    
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
                                                     assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoInput sourcePixelBufferAttributes:sourcePixelBufferAttributesDictionary];
     _videoInput.expectsMediaDataInRealTime = YES;

    if (![_assetWriter canAddInput:_videoInput]){
        GJLOG(GJ_LOGFORBID, "can not AddInput error,");
        return NO;
    }
    [_assetWriter addInput:_videoInput];
    BOOL result = [_assetWriter startWriting];
    if (result == NO) {
        GJLOG(GJ_LOGFORBID, "startWriting error,%@",_assetWriter.error);

        return NO;
    }
    _startTime = -1;
    [_assetWriter startSessionAtSourceTime:kCMTimeZero];
    
    [_videoInput requestMediaDataWhenReadyOnQueue:_videoWriteQueue usingBlock:^{
        while([_videoInput isReadyForMoreMediaData]){
            @autoreleasepool {

                if(_status != screenRecorderStopStatus)
                {
                        NSArray* imageArry ;
                        void* popValue = NULL;
                        if (queuePop(_imageCache, &popValue, 20)) {
                            imageArry = CFBridgingRelease(popValue);
                            UIImage* image = imageArry[0];
              
                            double time = ((NSNumber*)imageArry[1]).doubleValue;
                            CVPixelBufferRef buffer = [self pixelBufferFromCGImage:[image CGImage] size:size bufferPool:adaptor.pixelBufferPool];
                            CMTime currentSampleTime = CMTimeMake((int64_t)time, 1000);
                            if (buffer == NULL) {
                                GJLOG(GJ_LOGFORBID, "get buffer Pool ERROR:%@ ",_assetWriter.error);
                                [self videoFourceFinsh];
                                
                            }else{
                                if(![adaptor appendPixelBuffer:buffer withPresentationTime:currentSampleTime]){
                                    GJLOG(GJ_LOGFORBID, "appendPixelBuffer pts:%f error:%@",time,_assetWriter.error);
                                    [self videoFourceFinsh];

                                }else{
                                    GJLOG(GJ_LOGINFO, "appendPixelBuffer pts:%f",time);
                                }
                                CVPixelBufferRelease(buffer);
                            }                       
                        }else{
                            GJLOG(GJ_LOGINFO, "video pop time out ");

                        }
                }else{
                    
                    NSArray* imageArry ;
                    void* popValue = NULL;
                    if (queuePop(_imageCache, &popValue, 0)) {
                        
                        imageArry = CFBridgingRelease(popValue);
                        UIImage* image = imageArry[0];
                        double time = ((NSNumber*)imageArry[1]).doubleValue;
                        CVPixelBufferRef buffer = [self pixelBufferFromCGImage:[image CGImage] size:size bufferPool:adaptor.pixelBufferPool];
                        CMTime currentSampleTime = CMTimeMake((int64_t)time, 1000);
                        
                        if (buffer == NULL) {
                            GJLOG(GJ_LOGFORBID, "get buffer Pool ERROR:%@",_assetWriter.error);
                            [self videoFourceFinsh];

                        }else{
                            if(![adaptor appendPixelBuffer:buffer withPresentationTime:currentSampleTime]){
                                GJLOG(GJ_LOGERROR, "appendPixelBuffer stoped pts:%f error:%@ ",time,_assetWriter.error);
                                [self videoFourceFinsh];
                            }else{
                                GJLOG(GJ_LOGINFO, "appendPixelBuffer stoped pts:%f",time);
                            }
                            CVPixelBufferRelease(buffer);
                        }
                    }else{
                        [_videoInput markAsFinished];
                        _videoInput = nil;
                        GJLOG(GJ_LOGINFO, "video stop");
                        @synchronized (self) {
                            if (_videoInput == nil && _audioInput == nil) {
                                [self finshWrite];
                            }
                        }
                        break;
                    }

                }
            }

        }
    }];
    
    
    [_audioInput requestMediaDataWhenReadyOnQueue:_audioWriteQueue usingBlock:^{
        while([_audioInput isReadyForMoreMediaData]){
            @autoreleasepool {
                static int64_t prePts = 0;
                if(_status != screenRecorderStopStatus)
                {
                        CMSampleBufferRef audioBuffer ;
                        if (queuePop(_audioCache, (GHandle*)&audioBuffer, 20)) {
                           BOOL result =  [_audioInput appendSampleBuffer:audioBuffer];
                            if (!result) {
                                GJLOG(GJ_LOGERROR, "appendSampleBuffer error:%@",_assetWriter.error);
                                [self audioFourceFinsh];
                        
                                
                            }else{
                                int64_t samplePts = CMSampleBufferGetOutputPresentationTimeStamp(audioBuffer).value;
                                GJLOG(GJ_LOGINFO, "appendSampleBuffer pts:%lld dt:%d",samplePts,samplePts - prePts);
                                prePts = samplePts;
                            }
                            
                            CMBlockBufferRef blockbuffer = CMSampleBufferGetDataBuffer(audioBuffer);
                            CFRelease(audioBuffer);
                            free(blockbuffer);

                        }else{
                            double current = CFAbsoluteTimeGetCurrent();
                            GJLOG(GJ_LOGINFO, "audio pop timeout:%f\n",current);
                            @synchronized (self) {
                                if (current - _audioTime > 4096/_format.mSampleRate && _audioTime > 100) {
                                    int blockSize = 1024 * _format.mBytesPerFrame;
                                    double blockDuring = 1024 / _format.mSampleRate ;
                                    double blockPts =  (_audioTime - _startTime)*1000;
                                    
                                    CMSampleBufferRef sample = NULL;
                                    if (![self createBlackSampleBufferWithSample:&sample data:_slientData size:blockSize frames:blockSize/_format.mBytesPerFrame pts:blockPts]) {
                                        return;
                                    }
                                    _audioTime += blockDuring;
                                    BOOL result =  [_audioInput appendSampleBuffer:sample];
                                    if (!result) {
                                        GJLOG(GJ_LOGFORBID, "appendSampleBuffer error:%@",_assetWriter.error);
                                        [self audioFourceFinsh];
                                    }
#ifdef DEBUG
                                    else{
                                        int64_t samplePts = CMSampleBufferGetOutputPresentationTimeStamp(sample).value;
                                        GJLOG(GJ_LOGINFO, "appendSampleBuffer empty data pts:%lld dt:%d",samplePts,samplePts - prePts);
                                        prePts = samplePts;
                                    }
#endif
                                    
                                    CMBlockBufferRef blockbuffer = CMSampleBufferGetDataBuffer(sample);
                                    CFRelease(sample);
                                    free(blockbuffer);

                                }
                            }
                        }
                }else{
                    
                    CMSampleBufferRef sample ;
                    if (queuePop(_audioCache, (GHandle*)&sample, 20)) {
                        
                        BOOL result =  [_audioInput appendSampleBuffer:sample];
                        if (!result) {
                            GJLOG(GJ_LOGFORBID, "appendSampleBuffer error:%@",_assetWriter.error);
                            [self audioFourceFinsh];
                        }
#ifdef DEBUG
                        else{
                            int64_t samplePts = CMSampleBufferGetOutputPresentationTimeStamp(sample).value;
                            GJLOG(GJ_LOGINFO, "appendSampleBuffer pts:%lld dt:%d",samplePts,samplePts - prePts);
                            prePts = samplePts;
                        }
#endif
                        CMBlockBufferRef blockbuffer = CMSampleBufferGetDataBuffer(sample);
                        CFRelease(sample);
                        free(blockbuffer);
                    }else{
                        [_audioInput markAsFinished];
                        _audioInput = nil;
                        GJLOG(GJ_LOGINFO, "audio stop");
                        @synchronized (self) {
                            if (_audioInput == nil && _videoInput == nil) {
                                [self finshWrite];
                            }
                        }

                        break;
                    }
                    
                }
                
            }

        }
    }];
    return YES;
}

-(void)audioFourceFinsh{
    [self stopRecord];

    int length = queueGetLength(_audioCache);
    CMSampleBufferRef* audioArry = (CMSampleBufferRef*)malloc(sizeof(CMSampleBufferRef)*length);
    if (queueClean(_audioCache, (GHandle*)audioArry, &length)) {
        for (int i = 0; i<length; i++) {
            CMSampleBufferRef sample = audioArry[i];
            CFRelease(sample);
        }
    }
    free(audioArry);
    
    [_audioInput markAsFinished];
}
-(void)videoFourceFinsh{
    [self stopRecord];

    if (queueGetLength(_imageCache)) {
        int length = queueGetLength(_imageCache);
        void** imageArry = malloc(sizeof(void*)*length);;
        if (queueClean(_imageCache, imageArry, &length)) {
            for (int i = 0; i<length; i++) {
                NSArray* arry = CFBridgingRelease(imageArry[i]);
                arry = nil;
            }
        }
        free(imageArry);
    }
    
    [_videoInput markAsFinished];

}

-(CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image size:(CGSize)size bufferPool:(CVPixelBufferPoolRef)pool
{

    CVPixelBufferRef pixelBuffer = NULL ;
    CVReturn result = CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &pixelBuffer);
    if (result != kCVReturnSuccess) {
        return NULL;
    }
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pixelBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(pxdata, size.width, size.height, 8, bytesPerRow, rgbColorSpace, kCGImageAlphaPremultipliedFirst);

    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
       return pixelBuffer;
}


#pragma mark delegate

-(void)dealloc{

    GJLOG(GJ_LOGDEBUG, "screenrecorder delloc:%@",self);
    free(_slientData);
}
@end
