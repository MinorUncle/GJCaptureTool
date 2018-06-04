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

@interface GJScreenRecorder () {
    dispatch_queue_t _audioWriteQueue;
    dispatch_queue_t _videoWriteQueue;
    NSInteger *      _totalCount;

    AVAssetWriter *                       _assetWriter;
    AVAssetWriterInput *                  _videoInput;
    AVAssetWriterInput *                  _audioInput;
    double                                _startTime;
    NSInteger                             _audioFrameCount;
    AudioStreamBasicDescription           _audioFormat;
    CMFormatDescriptionRef                _audioFormatDesc;
    uint8_t *                             _slientData;
    AVAssetWriterInputPixelBufferAdaptor *adaptor;
    int                                   _warningTimes;
}
@property (strong, nonatomic) CADisplayLink *fpsTimer;
@property (strong, nonatomic) NSRunLoop *    captureRunLoop;

@end

@implementation GJScreenRecorder

- (instancetype)initWithDestUrl:(NSURL *)url;
{
    self = [super init];
    if (self) {
        _audioWriteQueue = dispatch_queue_create("audioWriteQueue", DISPATCH_QUEUE_SERIAL);
        _videoWriteQueue = dispatch_queue_create("videoWriteQueue", DISPATCH_QUEUE_SERIAL);
        _slientData      = calloc(1, 2024 * 16);

        _status      = screenRecorderStopStatus;
        _destFileUrl = url;
        if ([[NSFileManager defaultManager] fileExistsAtPath:self.destFileUrl.path]) {
            //remove the old one
            [[NSFileManager defaultManager] removeItemAtPath:self.destFileUrl.path error:nil];
        }

        NSError *error = nil;

        unlink([self.destFileUrl path].UTF8String);
        _assetWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:self.destFileUrl.path]
                                                 fileType:AVFileTypeQuickTimeMovie
                                                    error:&error];
        if (error) GJLOG(GNULL, GJ_LOGERROR, "AVAssetWriter  create error:%s", error.localizedDescription.UTF8String);
    }
    return self;
}

#pragma mark interface

- (UIImage *)captureImageWithView:(UIView *)view {
    UIImage *image;
    UIGraphicsBeginImageContext(view.bounds.size);
    [view drawViewHierarchyInRect:self.captureView.frame afterScreenUpdates:NO];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (BOOL)addAudioSourceWithFormat:(AudioStreamBasicDescription)format {
    if (format.mSampleRate > 0) {
        NSDictionary *audioOutputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                                              [NSNumber numberWithInt:kAudioFormatMPEG4AAC], AVFormatIDKey,
                                                              [NSNumber numberWithInt:format.mChannelsPerFrame], AVNumberOfChannelsKey,
                                                              [NSNumber numberWithFloat:format.mSampleRate], AVSampleRateKey,
                                                              //                                             [ NSNumber numberWithBool:NO ], AVLinearPCMIsBigEndianKey,
                                                              //                                             [ NSNumber numberWithInt:streamFormat.mBitsPerChannel ], AVLinearPCMBitDepthKey,
                                                              //                                             [ NSNumber numberWithBool:NO ], AVLinearPCMIsFloatKey,
                                                              //                                             [ NSNumber numberWithBool:NO ], AVLinearPCMIsNonInterleaved,

                                                              [NSNumber numberWithInt:128000], AVEncoderBitRateKey,

                                                              //[ NSNumber numberWithInt:AVAudioQualityLow], AVEncoderAudioQualityKey,
                                                              //                                             [ NSNumber numberWithInt: 64000 ], AVEncoderBitRateKey,
                                                              nil];

        _audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioOutputSettings];
        if (_audioInput == nil) {
            return NO;
        }
        //                _audioInput.expectsMediaDataInRealTime = YES;
        if (![_assetWriter canAddInput:_audioInput]) {
            return NO;
        }
        [_assetWriter addInput:_audioInput];
        _audioFormat     = format;
        _audioFrameCount = 0;
        OSStatus status  = CMAudioFormatDescriptionCreate(NULL, &_audioFormat, 0, NULL, 0, NULL, NULL, &_audioFormatDesc);
        return status == noErr;
    } else {
        return NO;
    }
}
- (BOOL)addVideoSourceWithView:(UIView *)targetView fps:(NSInteger)fps {

    if (targetView.superview == nil) {
        GJLOG(GNULL, GJ_LOGFORBID, "录制的视图必须显示在屏幕上");
        return NO;
    }

    if (targetView.bounds.size.width < 2 || targetView.bounds.size.height < 2) {
        GJLOG(GNULL, GJ_LOGFORBID, "录制 视图大小不能小于2");
        return NO;
    }

    if (fps < 1) {
        GJLOG(GNULL, GJ_LOGFORBID, "录制 fps不能小于1");
        return NO;
    }

    _captureView                = targetView;
    _captureFrame               = targetView.bounds;
    _fps                        = fps;
    CGSize        size          = _captureFrame.size;
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:AVVideoCodecH264, AVVideoCodecKey,
                                                                             [NSNumber numberWithInt:size.width], AVVideoWidthKey,
                                                                             [NSNumber numberWithInt:size.height], AVVideoHeightKey, nil];
    _videoInput                            = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    _videoInput.expectsMediaDataInRealTime = YES;

    NSDictionary *sourcePixelBufferAttributesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                                                            [NSNumber numberWithInt:kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey,
                                                                            [NSNumber numberWithInt:size.width], kCVPixelBufferWidthKey,
                                                                            [NSNumber numberWithInt:size.height], kCVPixelBufferHeightKey,
                                                                            //                                                           [NSNumber numberWithBool:YES],
                                                                            //                                                           kCVPixelBufferCGBitmapContextCompatibilityKey,
                                                                            nil];

    adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoInput sourcePixelBufferAttributes:sourcePixelBufferAttributesDictionary];

    if (![_assetWriter canAddInput:_videoInput]) {
        //        GJLOG(GJ_LOGFORBID, "can not AddInput error,");
        return NO;
    }
    [_assetWriter addInput:_videoInput];
    return YES;
}

- (BOOL)startRecode {
    if (_status != screenRecorderStopStatus) {
        return NO;
    }

    _warningTimes = 0;

    _status = screenRecorderRecorderingStatus;

    //start
    BOOL result = [self startWriteFile];
    if (result == NO) {
        return NO;
    }

    if (_videoInput) {
        self.fpsTimer               = [CADisplayLink displayLinkWithTarget:self selector:@selector(_captureCurrentView)];
        self.fpsTimer.frameInterval = 60 / _fps;
        [self.fpsTimer addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    }
    return YES;
}

- (void)stopRecord {
    _status = screenRecorderStopStatus;
}

- (void)pause {
    _status = screenRecorderPauseStatus;
}

- (void)resume {
    _status = screenRecorderRecorderingStatus;
}

NSData *createData;
- (BOOL)createBlackSampleBufferWithSample:(CMSampleBufferRef *)sample data:(uint8_t *)data size:(NSInteger)blockSize frames:(NSInteger)frames pts:(double)blockPts owner:(BOOL)owner {
    CMBlockBufferRef blockbuffer;
    uint8_t *        tempData;
    if (!owner) {
        tempData = malloc(blockSize);
        memcpy(tempData, data, blockSize);
    } else {
        tempData = data;
    }
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL, tempData, blockSize, NULL, NULL, 0, blockSize, 0, &blockbuffer);
    if (status != noErr) {
        NSLog(@"CMBlockBufferCreateWithMemoryBlock error");
        free(tempData);
        return NO;
    }

    status = CMAudioSampleBufferCreateWithPacketDescriptions(kCFAllocatorDefault, blockbuffer, YES, NULL, NULL, _audioFormatDesc, frames, CMTimeMake((int64_t) blockPts, 1000), NULL, sample);
    if (status != noErr) {
        CFRelease(blockbuffer);
        return NO;
    }

    return YES;
}
- (void)freeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMBlockBufferRef blockbuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    CFRelease(sampleBuffer);
    CFRelease(blockbuffer);
}

- (void)addCurrentAudioSource:(uint8_t *)data size:(NSInteger)size {
    if (_startTime <= 0 || _audioInput == nil) {
        return;
    }
    uint8_t *blockData = malloc(size);
    memcpy(blockData, data, size);
    dispatch_async(_audioWriteQueue, ^{
        if (_status == screenRecorderStopStatus && _audioInput) {
            [_audioInput markAsFinished];
            _audioInput = nil;
            GJLOG(GNULL, GJ_LOGDEBUG, "_audioInput markAsFinished");
            @synchronized(self) {
                if (_audioInput == nil && _videoInput == nil) {
                    [self finshWrite];
                }
            }
            return;
        }
        double    pts               = 0;
        double    currentTime       = CFAbsoluteTimeGetCurrent();
        NSInteger currentTimeFrames = (currentTime - _startTime) * _audioFormat.mSampleRate;
        NSInteger sizeFrame         = size / _audioFormat.mBytesPerFrame;
        @synchronized(self) {
            while (currentTimeFrames - _audioFrameCount > 2 * sizeFrame) {
                CMSampleBufferRef sample = NULL;
                pts                      = _audioFrameCount * 1000 / _audioFormat.mSampleRate;
                if ([self createBlackSampleBufferWithSample:&sample data:_slientData size:size frames:sizeFrame pts:pts owner:NO]) {
                    _audioFrameCount += sizeFrame;
                    [self writeAudioWithSampleBuffer:sample pts:pts];
                    [self freeSampleBuffer:sample];
                    GJLOG(GNULL, GJ_LOGINFO, "appendSampleBuffer empty data，currentTimeFrames:%ld audioframe:%d", (long) currentTimeFrames, _audioFrameCount);
                } else {
                    NSAssert(0, @"createBlackSampleBufferWithSample ERROR");
                    return;
                }
            }
        }
        if (_audioFrameCount - currentTimeFrames > sizeFrame * 0.5) {
            GJLOG(GNULL, GJ_LOGINFO, "接收的音频数据太快，丢帧");
            return;
        }
        pts                      = _audioFrameCount * 1000 / _audioFormat.mSampleRate;
        CMSampleBufferRef sample = NULL;
        if ([self createBlackSampleBufferWithSample:&sample data:blockData size:size frames:sizeFrame pts:pts owner:YES]) {
            _audioFrameCount += sizeFrame;
            [self writeAudioWithSampleBuffer:sample pts:pts];
            [self freeSampleBuffer:sample];
        } else {
            NSAssert(0, @"createBlackSampleBufferWithSample ERROR");
        }
    });
}

#pragma mark internal
- (void)_captureCurrentView {
    @autoreleasepool {
        if (self.status == screenRecorderStopStatus) {
            [_fpsTimer invalidate];
            _fpsTimer = nil;
            [_videoInput markAsFinished];
            if (_assetWriter.error) {
                GJLOG(GNULL, GJ_LOGERROR, "_videoInput Finished,error:%s", _assetWriter.error.localizedDescription.UTF8String);
            } else {
                GJLOG(GNULL, GJ_LOGDEBUG, "_videoInput Finished");
            }
            _videoInput = nil;
            @synchronized(self) {
                if (_audioInput == nil && _videoInput == nil) {
                    [self finshWrite];
                }
            }

            if (_audioInput) {
                //防止音频回调没有时无法结束
                [self addCurrentAudioSource:_slientData size:1024 * _audioFormat.mBytesPerFrame];
            }
            return;
        }
        CVPixelBufferRef pixelBuffer = NULL;
        CVReturn         result      = CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pixelBuffer);
        if (result != kCVReturnSuccess) {
            GJLOG(GNULL, GJ_LOGERROR, "CVPixelBufferPoolCreatePixelBuffer error:%d", result);
            [self videoFourceFinsh];
            return;
        }
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *          pxdata        = CVPixelBufferGetBaseAddress(pixelBuffer);
        CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();

        CGContextRef context = CGBitmapContextCreate(pxdata, _captureFrame.size.width, _captureFrame.size.height, 8, bytesPerRow, rgbColorSpace, kCGImageAlphaPremultipliedFirst);
        UIGraphicsPushContext(context);
        //注意第n个变换参数会应用0 ~ n-1个数据的变换
        CGAffineTransform affine = CGAffineTransformTranslate(CGAffineTransformMakeScale(1, -1), 0, -1 * _captureFrame.size.height);
        CGContextConcatCTM(context, affine);
        //        采用afterScreenUpdates：NO,采用YES，防止动画变慢
        result = [self.captureView drawViewHierarchyInRect:self.captureView.frame afterScreenUpdates:NO];
        UIGraphicsPopContext();
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        CGColorSpaceRelease(rgbColorSpace);
        CGContextRelease(context);

        if (result) {
            int64_t pts = 0;
            if (_startTime <= 0) {
                _startTime = CFAbsoluteTimeGetCurrent();
                pts        = 0;
            } else {
                pts = (int64_t)((CFAbsoluteTimeGetCurrent() - _startTime) * 1000);
            }
            dispatch_async(_videoWriteQueue, ^{
                [self writeVideoWithPixelBuffer:pixelBuffer pts:pts];
                CVPixelBufferRelease(pixelBuffer);
                if (_status != screenRecorderStopStatus && _audioInput) {
                    @synchronized(self) {
                        double    currentTime       = CFAbsoluteTimeGetCurrent();
                        NSInteger currentTimeFrames = (currentTime - _startTime) * _audioFormat.mSampleRate;
                        NSInteger sizeFrame         = 1024;
                        NSInteger size              = sizeFrame * _audioFormat.mBytesPerFrame;
                        if (currentTimeFrames - _audioFrameCount > 4 * sizeFrame) {
                            [self addCurrentAudioSource:_slientData size:size];
                            GJLOG(GNULL, GJ_LOGINFO, "appendSampleBuffer2 empty data，currentTimeFrames:%ld audioframe:%ld", (long) currentTimeFrames, (long) _audioFrameCount);
                        }
                    }
                }
            });
        } else {
            CVPixelBufferRelease(pixelBuffer);
        }
    }
}
- (void)writeVideoWithPixelBuffer:(CVPixelBufferRef)pixelBuffer pts:(int64_t)pts {

    if ([_videoInput isReadyForMoreMediaData]) {

        if (![adaptor appendPixelBuffer:pixelBuffer withPresentationTime:CMTimeMake(pts, 1000)]) {

            GJLOG(GNULL, GJ_LOGINFO, "appendPixelBuffer pts:%lld error:%s", pts, _assetWriter.error.localizedDescription.UTF8String);
            [self videoFourceFinsh];
        } else {
            GJLOG(GNULL, GJ_LOGINFO, "appendPixelBuffer pts:%lld", pts);
        }
    }
}

- (void)writeAudioWithSampleBuffer:(CMSampleBufferRef)sampleBuffer pts:(int64_t)pts {
    if ([_audioInput isReadyForMoreMediaData]) {
        BOOL result = [_audioInput appendSampleBuffer:sampleBuffer];
        if (!result) {
            GJLOG(GNULL, GJ_LOGINFO, "appendSampleBuffer error:%s", _assetWriter.error.localizedDescription.UTF8String);
            [self audioFourceFinsh];
        }
    } else {
        _warningTimes++;
        if (_warningTimes < 10) {
            GJLOG(GNULL, GJ_LOGWARNING, "NOT isReadyForMoreMediaData,编码速率不够（%d），丢帧", _warningTimes);
        } else {
            GJLOG(GNULL, GJ_LOGERROR, "NOT isReadyForMoreMediaData,编码速率不够 失败");
        }
    }
}

- (NSURL *)destFileUrl {
    if (_destFileUrl == nil) {
        NSDateFormatter *format = [[NSDateFormatter alloc] init];
        [format setDateFormat:@"yyyy_MM_dd_HH_mm_ss"];
        NSString *path = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
        path           = [path stringByAppendingPathComponent:@"RecoderFile"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *file = [format stringFromDate:[NSDate date]];
        path           = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", file]];
        _destFileUrl   = [NSURL fileURLWithPath:path];
    }
    return _destFileUrl;
}

- (BOOL)startWriteFile {
    NSURL *fileUrl = [_destFileUrl URLByDeletingPathExtension];
    fileUrl        = [fileUrl URLByAppendingPathExtension:@"pcm"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileUrl.path]) {
        [[NSFileManager defaultManager] createFileAtPath:fileUrl.path contents:nil attributes:nil];
    }

    BOOL result = [_assetWriter startWriting];
    if (result == NO) {
        //        GJLOG(GJ_LOGFORBID, "startWriting error,%@",_assetWriter.error);
        return NO;
    }
    _startTime = -1;
    [_assetWriter startSessionAtSourceTime:kCMTimeZero];

    return YES;
}

- (void)audioFourceFinsh {

    [self stopRecord];
    //    [_audioInput markAsFinished];
}

- (void)videoFourceFinsh {

    [self stopRecord];
    [_videoInput markAsFinished];
}
- (void)finshWrite {
    [_assetWriter finishWritingWithCompletionHandler:^{

        NSError *error = _assetWriter.error;
        if (self.callback) {
            self.callback(self.destFileUrl, error);
        }
        if (error) {
            GJLOG(GNULL, GJ_LOGERROR, "finishWriting:%s", error.localizedDescription.UTF8String);

        } else {
            GJLOG(GNULL, GJ_LOGDEBUG, "finishWriting");
        }
        _assetWriter = nil;
    }];
}


#pragma mark delegate

-(void)dealloc{
    free(_slientData);
    if (_audioFormatDesc) {
        CFRelease(_audioFormatDesc);
    }
//    GJLOG(GJ_LOGDEBUG, "screenrecorder delloc:%@",self);
}
@end
