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
#import <pthread.h>
#import "GJLog.h"

#define VIDEO_PTS_PRECISION   0.4
#define AUDIO_PTS_PRECISION   0.1


typedef struct _GJImageBuffer{
    CVImageBufferRef image;
    CMTime           pts;
}GJImageBuffer;
typedef struct _GJAudioBuffer{
    GJRetainBuffer* audioData;
    CMTime           pts;
}GJAudioBuffer;

@interface GJPlayer()<GJAudioQueueDrivePlayerDelegate>{
    GJImageView*                _displayView;
    GJImageYUVDataInput*        _yuvInput;
    GJAudioQueueDrivePlayer*    _audioPlayer;
    
    float                       _playNeedterval;
    GJPlayStatus                _status;
    NSThread*                   _playThread;
    int                         _videoBufferStep;
    
    
}
@property(strong,nonatomic)GJImageYUVDataInput* YUVInput;
@property(assign,nonatomic)GJQueue*             imageQueue;
@property(assign,nonatomic)GJQueue*             audioQueue;
@property(assign,nonatomic)CMTime*              clockLine;
@property(assign,nonatomic)CMTime               aClock;
@property(assign,nonatomic)CMTime               vClock;

@end
@implementation GJPlayer
-(void) playRunLoop{
    pthread_setname_np("GJPlayRunLoop");
    
    GJImageBuffer* cImageBuf,*nImageBuf;
    if (queuePop(_imageQueue, (void**)&cImageBuf, INT_MAX) && (_status == kPlayStatusRunning || _status == kPlayStatusPause)) {
        OSType type = CVPixelBufferGetPixelFormatType(cImageBuf->image);
        if (type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            _YUVInput = [[GJImageYUVDataInput alloc]initPixelFormat:GJPixelFormatNV12];
            [_YUVInput addTarget:_displayView];
            _clockLine = &_vClock;
        }else{
            NSAssert(0, @"视频格式不支持");
            goto ERROR;
        }
    }else{
        goto ERROR;
    }
    GJAudioBuffer* audioBuffer;
    queueSetMixCacheSize(_audioQueue, 8);
    if (queuePeekTopOutValue(_audioQueue, (void**)&audioBuffer, INT_MAX) && (_status == kPlayStatusRunning || _status == kPlayStatusPause)) {
        queueSetMixCacheSize(_audioQueue, 0);
        
        uint8_t* adts = audioBuffer->audioData->data;
        uint8_t sampleRate = adts[2] << 2;
        sampleRate = sampleRate>>4;
        sampleRate = mpeg4audio_sample_rates[sampleRate];
        uint8_t channel = adts[2] & 0x1 <<2;
        channel += (adts[3] & 0xb0)>>6;
        _audioPlayer = [[GJAudioQueueDrivePlayer alloc]initWithSampleRate:sampleRate channel:channel formatID:kAudioFormatMPEG4AAC];
        _audioPlayer.delegate = self;
        _clockLine = &_aClock;
        [_audioPlayer start];
    }else{
        goto ERROR;
    }
    [_YUVInput updateDataWithImageBuffer:cImageBuf->image timestamp:cImageBuf->pts];
    _vClock = cImageBuf->pts;
    free(cImageBuf);
    cImageBuf = NULL;

    long cTime = 0;
    cTime = clock() * 1000 / CLOCKS_PER_SEC;
    while ((_status != kPlayStatusStop)) {
        if (queuePeekTopOutValue(_imageQueue, (void**)&nImageBuf,_status == kPlayStatusRunning?0:INT_MAX)) {
            if (_status == kPlayStatusPause) {
                queueWaitPop(_imageQueue, INT_MAX);
            }else if (_status == kPlayStatusBuffering){
                [self resume];
            }
        }else{
            if (_status == kPlayStatusStop) {
                break;
            }else{
                [self buffering];
                continue;
            }
        }
        
        long time = clock() * 1000 / CLOCKS_PER_SEC;
        float timeDiff = time - cTime;
        float delay = nImageBuf->pts.value*1000.0/nImageBuf->pts.timescale - _vClock.value*1000.0/_vClock.timescale - timeDiff;
        
        float clockDiff = _clockLine->value*1000.0/_clockLine->timescale - _vClock.value*1000.0/_vClock.timescale - timeDiff;
        delay -= clockDiff;
        
        if (delay > VIDEO_PTS_PRECISION*1000) {
            GJLOG(GJ_LOGWARNING, "视频需要等待时间过长");
            usleep(delay*1000);
            nImageBuf = NULL;
            continue;
        }
        if(queuePop(_imageQueue, (void**)&cImageBuf, 0)){
            if (delay < -VIDEO_PTS_PRECISION*1000){
                GJLOG(GJ_LOGWARNING, "视频落后严重，需要丢帧");
            }else{
                usleep(delay * 1000);
                [_YUVInput updateDataWithImageBuffer:cImageBuf->image timestamp:cImageBuf->pts];
                _vClock = cImageBuf->pts;
            }
            free(nImageBuf);
            cImageBuf = NULL;
            nImageBuf = NULL;
        };
    }
    
    
ERROR:
    _status = kPlayStatusStop;
    return;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        _status = kPlayStatusStop;
        _videoBufferStep = 10;
        _displayView = [[GJImageView alloc]init];
        queueCreate(&_imageQueue, 150, true, false);//150为暂停时视频最大缓冲
        queueCreate(&_audioQueue, 400, true, false);
    }
    return self;
}
-(UIView *)displayView{
    return _displayView;
}

-(void)start{
    _status = kPlayStatusRunning;
    _playThread = [[NSThread alloc]initWithTarget:self selector:@selector(playRunLoop) object:nil];
    [_playThread start];
}
-(void)stop{
    _status = kPlayStatusStop;
    [_audioPlayer stop:false];
}
-(void)pause{
    _status = kPlayStatusPause;
    queueSetMixCacheSize(_imageQueue, 1000);
    [_audioPlayer pause];
}
-(void)resume{
    _status = kPlayStatusRunning;
    queueSetMixCacheSize(_imageQueue,0);
    [_audioPlayer resume];
}
-(void)buffering{
    _status = kPlayStatusBuffering;
    queueSetMixCacheSize(_imageQueue, queueGetLength(_imageQueue)+_videoBufferStep);
    [_audioPlayer pause];
}
-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(CMTime)pts{
    GJImageBuffer* imageBuffer  = (GJImageBuffer*)malloc(sizeof(GJImageBuffer));
    imageBuffer->image = imageData;
    imageBuffer->pts = pts;
    if (queuePush(_imageQueue, imageBuffer, 0)) {
        CVPixelBufferRetain(imageData);
        return YES;
    }else{
        free(imageBuffer);
        return NO;
    }
}

static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(CMTime)pts{
    GJAudioBuffer* audioBuffer = (GJAudioBuffer*)malloc(sizeof(GJAudioBuffer));
    audioBuffer->audioData = audioData;
    audioBuffer->pts = pts;
    if(queuePush(_audioQueue, audioBuffer, 0)){
        retainBufferRetain(audioData);
        return YES;

    }else{
        free(audioBuffer);
        return NO;
    }
}



-(BOOL)GJAudioQueueDrivePlayer:(GJAudioQueueDrivePlayer *)player outAudioData:(void **)data outSize:(int *)size{
    GJAudioBuffer* audioBuffer;
    if (queuePop(_audioQueue, (void**)&audioBuffer, 0)) {
        *data = audioBuffer->audioData->data+7;
        *size = audioBuffer->audioData->size-7;
        retainBufferUnRetain(audioBuffer->audioData);
        _aClock = audioBuffer->pts;
        free(audioBuffer);
        return YES;
    }else{
        [self buffering];
        return NO;
    }
}
@end
