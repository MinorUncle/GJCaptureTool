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
#import <sys/time.h>

#define VIDEO_PTS_PRECISION   0.4
#define AUDIO_PTS_PRECISION   0.1

#define VIDEO_MAX_CACHE_COUNT 300
#define AUDIO_MAX_CACHE_COUNT 750

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
    int                         _lowWaterFlag;
    int                         _highWaterFlag;
    NSLock*                     _oLock;

    
}
@property(strong,nonatomic)GJImageYUVDataInput* YUVInput;
@property(assign,nonatomic)GJQueue*             imageQueue;
@property(assign,nonatomic)GJQueue*             audioQueue;
@property(assign,nonatomic)long                 startPts;
@property(assign,nonatomic)long               aClock;
@property(assign,nonatomic)long               vClock;
@property(assign,nonatomic)long                startTime;
@property(assign,nonatomic)long                showTime;

@property(assign,nonatomic)long                 bufferTime;

@property(assign,nonatomic)long                 lastPauseFlag;
@property(assign,nonatomic)long                 speed;


@end
@implementation GJPlayer

long long getTime(){
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000000 + tv.tv_usec;
}

-(long) getClockLine{
    if (0) {
        return _aClock;
    }else{

        long time = getTime() / 1000;
        if (_speed > 1.0) {
            _bufferTime -= (_speed - 1.0)*(time-_showTime);
        }
        float timeDiff = time - _startTime;
        return timeDiff + _startPts-_bufferTime;
        _showTime = time;
    }
}
-(void) playRunLoop{
    pthread_setname_np("GJPlayRunLoop");
    
    GJImageBuffer* cImageBuf;
    if (queuePop(_imageQueue, (void**)&cImageBuf, INT_MAX) && (_status == kPlayStatusRunning || _status == kPlayStatusPause)) {
        OSType type = CVPixelBufferGetPixelFormatType(cImageBuf->image);
        if (type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            _YUVInput = [[GJImageYUVDataInput alloc]initPixelFormat:GJPixelFormatNV12];
            [_YUVInput addTarget:_displayView];
            _startPts = cImageBuf->pts.value*1000.0/cImageBuf->pts.timescale;
        }else{
            NSAssert(0, @"视频格式不支持");
            goto ERROR;
        }
    }else{
        goto ERROR;
    }
    GJAudioBuffer* audioBuffer;
    queueSetMixCacheSize(_audioQueue, 5);
    if (queuePeekWaitValue(_audioQueue, queueGetMixCacheSize(_audioQueue), (void**)&audioBuffer,INT_MAX)
        && (_status == kPlayStatusRunning || _status == kPlayStatusPause)) {
        queueSetMixCacheSize(_audioQueue, 0);
        
        uint8_t* adts = audioBuffer->audioData->data;
        uint8_t sampleRate = adts[2] << 2;
        sampleRate = sampleRate>>4;
        sampleRate = mpeg4audio_sample_rates[sampleRate];
        uint8_t channel = adts[2] & 0x1 <<2;
        channel += (adts[3] & 0xb0)>>6;
        _audioPlayer = [[GJAudioQueueDrivePlayer alloc]initWithSampleRate:sampleRate channel:channel formatID:kAudioFormatMPEG4AAC];
        _audioPlayer.delegate = self;
        _startPts = MIN(_startPts, audioBuffer->pts.value*1000.0/audioBuffer->pts.timescale);
        [_audioPlayer start];
    }else{
        goto ERROR;
    }
    _startTime = getTime() / 1000;
    _showTime = _startTime;
    [_YUVInput updateDataWithImageBuffer:cImageBuf->image timestamp:cImageBuf->pts];
    CVPixelBufferRelease(cImageBuf->image);
    _vClock = cImageBuf->pts.value * 1000.0 / cImageBuf->pts.timescale;
    free(cImageBuf);
    cImageBuf = NULL;


    while ((_status != kPlayStatusStop)) {
        if (queuePop(_imageQueue, (void**)&cImageBuf,_status == kPlayStatusRunning?0:INT_MAX)) {
           if (_status == kPlayStatusBuffering){
                [self stopBuffering];
           }else if (_status == kPlayStatusBuffering){
               CVPixelBufferRelease(cImageBuf->image);
               free(cImageBuf);
               cImageBuf = NULL;
               break;
           }
            if (_speed > 1.0 && queueGetLength(_imageQueue)<_lowWaterFlag) {
                [self stopDewatering];
            }
        }else{
            if (_status == kPlayStatusStop) {
                break;
            }else if (_status == kPlayStatusRunning){
                [self buffering];
            }
            continue;
        }
        
      
        long timeStandards = [self getClockLine];

        float delay = cImageBuf->pts.value*1000.0/cImageBuf->pts.timescale - timeStandards;
        printf("delay:%f ，\n",delay);
        while (delay > VIDEO_PTS_PRECISION*1000 && _status != kPlayStatusStop) {
            GJLOG(GJ_LOGWARNING, "视频需要等待时间过长");
            usleep(VIDEO_PTS_PRECISION*1000000);
            delay -= VIDEO_PTS_PRECISION*1000;
        }

        
        if (delay < -VIDEO_PTS_PRECISION*1000){
            GJLOG(GJ_LOGWARNING, "视频落后严重，需要丢帧");
        }else{
            usleep(delay * 1000);
            [_YUVInput updateDataWithImageBuffer:cImageBuf->image timestamp:cImageBuf->pts];
            CVPixelBufferRelease(cImageBuf->image);
            _vClock = cImageBuf->pts.value * 1000.0 / cImageBuf->pts.timescale;
        }
        free(cImageBuf);
        cImageBuf = NULL;
    
    }
    
    
ERROR:
    _status = kPlayStatusStop;
    _playThread = nil;
    return;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        _speed = 1.0;
        _oLock= [[NSLock alloc]init];
        _status = kPlayStatusStop;
        _lowWaterFlag = 10;
        _highWaterFlag = 40;
        _displayView = [[GJImageView alloc]init];
        queueCreate(&_imageQueue, VIDEO_MAX_CACHE_COUNT, true, false);//150为暂停时视频最大缓冲
        queueCreate(&_audioQueue, AUDIO_MAX_CACHE_COUNT, true, false);
    }
    return self;
}
-(UIView *)displayView{
    return _displayView;
}

-(void)start{
    [_oLock lock];
    if (_playThread == nil) {
        _status = kPlayStatusRunning;
        _playThread = [[NSThread alloc]initWithTarget:self selector:@selector(playRunLoop) object:nil];
        [_playThread start];
    }else{
        GJLOG(GJ_LOGWARNING, "重复播放");
    }
    [_oLock unlock];
}
-(void)stop{
    [_oLock lock];
    if(_status != kPlayStatusStop){
    _status = kPlayStatusStop;
    [_audioPlayer stop:false];
    }else{
        GJLOG(GJ_LOGWARNING, "重复停止");
    }
    [_oLock unlock];
}
//-(void)pause{
//
//    _status = kPlayStatusPause;
//    _lastPauseFlag = getTime() / 1000;
//    
//    queueSetMixCacheSize(_imageQueue, VIDEO_MAX_CACHE_COUNT);
//    [_audioPlayer pause];
//    queueLockPop(_imageQueue);
//    queueWaitPop(_imageQueue, INT_MAX);
//    queueUnLockPop(_imageQueue);
//    [_oLock lock];
//
//}
//-(void)resume{
//    if (_status == kPlayStatusPause) {
//        _status = kPlayStatusRunning;
//         GJLOG(GJ_LOGINFO,"buffer total:%d\n",_bufferTime);
//        queueSetMixCacheSize(_imageQueue,0);
//        if (_lastPauseFlag != 0) {
//            _bufferTime += getTime() / 1000 - _lastPauseFlag;
//            _lastPauseFlag = 0;
//        }else{
//            GJLOG(GJ_LOGWARNING, "暂停管理出现问题");
//        }
//        [_audioPlayer flush];
//        [_audioPlayer resume];
//    }else{
//        GJLOG(GJ_LOGDEBUG, "resume when status not pause");
//    }
//}
-(void)buffering{
    [_oLock lock];
    if(_status != kPlayStatusBuffering){
        _status = kPlayStatusBuffering;
        queueSetMixCacheSize(_imageQueue, queueGetLength(_imageQueue)+_lowWaterFlag);
        _lastPauseFlag = getTime() / 1000;
        [_audioPlayer pause];
    }else{
        GJLOG(GJ_LOGDEBUG, "buffer when status in buffing");
    }
    [_oLock unlock];
}
-(void)stopBuffering{
    [_oLock lock];
    if (_status == kPlayStatusBuffering) {
        _status = kPlayStatusRunning;
        GJLOG(GJ_LOGINFO,"buffer total:%d\n",_bufferTime);
        queueSetMixCacheSize(_imageQueue,0);
        if (_lastPauseFlag != 0) {
            _bufferTime += getTime() / 1000 - _lastPauseFlag;
            _lastPauseFlag = 0;
        }else{
            GJLOG(GJ_LOGWARNING, "暂停管理出现问题");
        }
        [_audioPlayer flush];
        [_audioPlayer resume];
    }else{
        GJLOG(GJ_LOGDEBUG, "stopBuffering when status not buffering");
    }
    [_oLock unlock];
}
-(void)dewatering{
    [_oLock lock];
    if (_status == kPlayStatusRunning) {
        _speed = 1.2;
        _audioPlayer.speed = _speed;
    }
    [_oLock unlock];
}
-(void)stopDewatering{
    [_oLock lock];
    _speed = 1.0;
    _audioPlayer.speed = _speed;
    [_oLock unlock];
}
-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(CMTime)pts{
    GJImageBuffer* imageBuffer  = (GJImageBuffer*)malloc(sizeof(GJImageBuffer));
    imageBuffer->image = imageData;
    imageBuffer->pts = pts;
    if (queuePush(_imageQueue, imageBuffer, 0)) {
        CVPixelBufferRetain(imageData);
        if (queueGetLength(_imageQueue)> _highWaterFlag) {
            [self dewatering];
        }
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
        _aClock = audioBuffer->pts.value * 1000.0 / audioBuffer->pts.timescale;
        free(audioBuffer);
        return YES;
    }else{
        [self buffering];
        return NO;
    }
}
@end
