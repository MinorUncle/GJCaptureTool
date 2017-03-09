//
//  GJPlayer.m
//  GJCaptureTool
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJPlayer.h"
#import "GJAudioQueueDrivePlayer.h"
#import "GJImageYUVDataInput.h"
#import "GJImageView.h"
#import "GJQueue.h"


typedef struct _GJImageBuffer{
    CVImageBufferRef image;
    CMTime           pts;
}GJImageBuffer;
typedef struct _GJAudioBuffer{
    GJRetainBuffer* audioData;
    CMTime           pts;
}GJAudioBuffer;

@interface GJPlayer()<GJAudioQueueDrivePlayerDelegate>{
    GJImageView* _displayView;
    GJImageYUVDataInput* _yuvInput;
    GJAudioQueueDrivePlayer*  _audioPlayer;
    
    CMTime          _lastAudioPts;
    GJImageBuffer*  _lastImageBuffer;
    float           _playNeedterval;
    BOOL _isPlay;
}
@property(strong,nonatomic)GJImageYUVDataInput* YUVInput;
@property(assign,nonatomic)GJQueue* imageQueue;
@property(assign,nonatomic)GJQueue* audioQueue;
@end
@implementation GJPlayer
- (instancetype)init
{
    self = [super init];
    if (self) {
        _isPlay = NO;
        _displayView = [[GJImageView alloc]init];
        queueCreate(&_imageQueue, 30, true, false);
        queueCreate(&_audioQueue, 80, true, false);
    }
    return self;
}
-(UIView *)displayView{
    return _displayView;
}

-(void)start{
    _isPlay = YES;
}
-(void)stop{
    _isPlay = NO;
    [_audioPlayer stop:false];
}
-(void)addVideoDataWith:(CVImageBufferRef)imageData pts:(CMTime)pts{
    GJImageBuffer* imageBuffer  = (GJImageBuffer*)malloc(sizeof(GJImageBuffer));
    imageBuffer->image = imageData;
    imageBuffer->pts = pts;
    if (queuePush(_imageQueue, imageBuffer, 0)) {
        CVPixelBufferRetain(imageData);
    }else{
        free(imageBuffer);
    }
}
static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
-(void)addAudioDataWith:(GJRetainBuffer*)audioData pts:(CMTime)pts{
    if (_audioPlayer == nil) {
        uint8_t* adts = audioData->data;
        uint8_t sampleRate = adts[2] << 2;
        sampleRate = sampleRate>>4;
        sampleRate = mpeg4audio_sample_rates[sampleRate];
        uint8_t channel = adts[2] & 0x1 <<2;
        channel += (adts[3] & 0xb0)>>6;
        _audioPlayer = [[GJAudioQueueDrivePlayer alloc]initWithSampleRate:sampleRate channel:channel formatID:kAudioFormatMPEG4AAC];
        _audioPlayer.delegate = self;
        [_audioPlayer start];
    }
    
    GJAudioBuffer* audioBuffer = (GJAudioBuffer*)malloc(sizeof(GJAudioBuffer));
    audioBuffer->audioData = audioData;
    audioBuffer->pts = pts;
    if(queuePush(_audioQueue, audioBuffer, 0)){
        retainBufferRetain(audioData);
    }else{
        free(audioBuffer);
    }
}



-(BOOL)GJAudioQueueDrivePlayer:(GJAudioQueueDrivePlayer *)player outAudioData:(void **)data outSize:(int *)size{
    GJAudioBuffer* audioBuffer;
    if (queuePop(_audioQueue, (void**)&audioBuffer, 0)) {
        *data = audioBuffer->audioData->data+7;
        *size = audioBuffer->audioData->size-7;
        _lastAudioPts = audioBuffer->pts;
        retainBufferUnRetain(audioBuffer->audioData);
        free(audioBuffer);
    }
    if (_lastImageBuffer == nil) {
        GJImageBuffer* imageBuffer;
        if (queuePop(_imageQueue, (void**)&imageBuffer, 0)) {
            if (_YUVInput == nil) {
                OSType type = CVPixelBufferGetPixelFormatType(imageBuffer->image);
                if (type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
                    _YUVInput = [[GJImageYUVDataInput alloc]initPixelFormat:GJPixelFormatNV12];
                    [_YUVInput addTarget:_displayView];
                }else{
                    NSAssert(0, @"格式不支持");
                }
            }
            
            _playNeedterval = _audioPlayer.format.mFramesPerPacket*1000.0 / _audioPlayer.format.mSampleRate;
            float interval = imageBuffer->pts.value*1000.0/imageBuffer->pts.timescale - _lastAudioPts.value*1000.0/_lastAudioPts.timescale;
            if (interval < _playNeedterval && interval > -_playNeedterval) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    [_YUVInput updateDataWithImageBuffer:imageBuffer timestamp:imageBuffer->pts];
                    CVPixelBufferRelease(_lastImageBuffer->image);
                    free(_lastImageBuffer);
                    _lastImageBuffer == nil;
                });
            }else{
                _lastImageBuffer = imageBuffer;
            }
        }
        
    }else{
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            [_YUVInput updateDataWithImageBuffer:_lastImageBuffer->image timestamp:_lastImageBuffer->pts];
            CVPixelBufferRelease(_lastImageBuffer->image);
            free(_lastImageBuffer);
            _lastImageBuffer == nil;
        });
    }
    return YES;
}
@end
