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
    uint64_t           pts;
}GJImageBuffer;
typedef struct _GJAudioBuffer{
    GJRetainBuffer* audioData;
    uint64_t           pts;
}GJAudioBuffer;


typedef enum _TimeSYNCType{
    kTimeSYNCAudio,
    kTimeSYNCVideo,
    kTimeSYNCExternal,
}TimeSYNCType;

@interface GJPlayer()<GJAudioQueueDrivePlayerDelegate>{
    GJImageView*                _displayView;
    GJImageYUVDataInput*        _yuvInput;
    GJAudioQueueDrivePlayer*    _audioPlayer;
    
    float                       _playNeedterval;
    GJPlayStatus                _status;
    NSThread*                   _playThread;
    int                         _lowWaterFlag;
    int                         _highWaterFlag;
    NSRecursiveLock*            _oLock;

    
    int                         _audioOffset;
    
}
@property(strong,nonatomic)GJImageYUVDataInput* YUVInput;
@property(assign,nonatomic)GJQueue*             imageQueue;
@property(assign,nonatomic)GJQueue*             audioQueue;
@property(assign,nonatomic)long                 startPts;
@property(assign,nonatomic)long                 aClock;
@property(assign,nonatomic)long                 vClock;
@property(assign,nonatomic)long                 startTime;
@property(assign,nonatomic)long                 showTime;

@property(assign,nonatomic)long                 bufferTime;

@property(assign,nonatomic)long                 lastPauseFlag;
@property(assign,nonatomic)long                 speed;
@property(assign,nonatomic)TimeSYNCType         syncType;


@end
@implementation GJPlayer

long long getTime(){
#ifdef USE_CLOCK
    static clockd =  CLOCKS_PER_SEC /1000000 ;
    return clock() / clockd;
#endif
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000000 + tv.tv_usec;
}

-(long) getClockLine{
    if (_syncType == kTimeSYNCAudio) {
        return _aClock;
    }else if(_syncType == kTimeSYNCVideo){
        long time = getTime() / 1000;
        long  timeDiff = time - _showTime;
        return _vClock + timeDiff;
    }else{
        long time = getTime() / 1000;
        if (_speed > 1.0) {
            _bufferTime -= (_speed - 1.0)*(time-_showTime);
        }
        float timeDiff = time - _startTime;
        return timeDiff + _startPts-_bufferTime;
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
            _startPts = cImageBuf->pts;
            _syncType = kTimeSYNCVideo;
        }else{
            NSAssert(0, @"视频格式不支持");
            goto ERROR;
        }
    }else{
        goto ERROR;
    }
    GJAudioBuffer* audioBuffer;
    queueSetMixCacheSize(_audioQueue, 12);
    if (queuePeekWaitValue(_audioQueue, queueGetMixCacheSize(_audioQueue), (void**)&audioBuffer,INT_MAX)) {
        if (_status == kPlayStatusRunning || _status == kPlayStatusPause) {
            if (_audioFormat.mFormatID <=0) {
                queueSetMixCacheSize(_audioQueue, 0);
                if (((uint64_t*)audioBuffer->audioData) && 0xFFF0 != 0xFFF0) {
                    NSAssert(0, @"音频格式不支持");
                    goto ERROR;
                }
                uint8_t* adts = audioBuffer->audioData->data;
                uint8_t sampleIndex = adts[2] << 2;
                sampleIndex = sampleIndex>>4;
                int sampleRate = mpeg4audio_sample_rates[sampleIndex];
                uint8_t channel = adts[2] & 0x1 <<2;
                channel += (adts[3] & 0xb0)>>6;
                _audioFormat.mChannelsPerFrame = channel;
                _audioFormat.mSampleRate = sampleRate;
                _audioFormat.mFramesPerPacket = 1024;
                _audioFormat.mFormatID = kAudioFormatMPEG4AAC;
            }

        }
        
        if (_audioFormat.mFormatID == kAudioFormatLinearPCM) {
            _audioOffset = 0;
        }else if (_audioFormat.mFormatID == kAudioFormatMPEG4AAC){
            _audioOffset = 7;
        }
        _audioPlayer = [[GJAudioQueueDrivePlayer alloc]initWithSampleRate:_audioFormat.mSampleRate channel:_audioFormat.mChannelsPerFrame formatID:_audioFormat.mFormatID];
        _audioPlayer.delegate = self;
        [_audioPlayer start];
        _startPts = audioBuffer->pts;
        _syncType = kTimeSYNCAudio;
    }else{
        goto ERROR;
    }
  
    _startTime = getTime() / 1000;
    _showTime = _startTime;
    [_YUVInput updateDataWithImageBuffer:cImageBuf->image timestamp: CMTimeMake(cImageBuf->pts, 1000)];
    CVPixelBufferRelease(cImageBuf->image);
    _vClock = cImageBuf->pts;
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
                GJLOG(GJ_LOGDEBUG, "video play queue empty");
                usleep(10*1000);
//                [self buffering];
            }
            continue;
        }
        
        long timeStandards = [self getClockLine];
        long delay = cImageBuf->pts - timeStandards;


        while (delay > VIDEO_PTS_PRECISION*1000 ) {
            if (_status == kPlayStatusStop) {
                goto DROP;
            }
            if(_syncType == kTimeSYNCVideo){
                delay = VIDEO_PTS_PRECISION*1000-16;
                break;//视频不会长时间等待视频
            }
            GJLOG(GJ_LOGWARNING, "视频等待时间长 delay:%ld PTS:%ld clock:%ld",delay,cImageBuf->pts,timeStandards);
            usleep(VIDEO_PTS_PRECISION*1000000);
            timeStandards = [self getClockLine];
            delay = cImageBuf->pts - timeStandards;
        }
        if (delay < -VIDEO_PTS_PRECISION*1000){
            GJLOG(GJ_LOGWARNING, "丢帧,视频落后严重，delay：%ld, PTS:%ld clock:%ld",delay,cImageBuf->pts,timeStandards);
            goto DROP;
        }
    DISPLAY:
        if (delay > 10) {
            usleep(delay * 1000);
        }
        _showTime = getTime() / 1000;
        [_YUVInput updateDataWithImageBuffer:cImageBuf->image timestamp: CMTimeMake(cImageBuf->pts, 1000)];
        CVPixelBufferRelease(cImageBuf->image);
        _vClock = cImageBuf->pts;
        NSLog(@"video pts:%ld",_vClock);
    DROP:
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
        memset(&_audioFormat, 0, sizeof(_audioFormat));
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
        if (_status == kPlayStatusBuffering) {
            [self stopBuffering];
        }
        _status = kPlayStatusStop;
        [_audioPlayer stop:false];
        queueClean(_imageQueue);
        queueClean(_audioQueue);
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
    if(_status == kPlayStatusRunning){
        _status = kPlayStatusBuffering;
        GJLOG(GJ_LOGDEBUG, "start buffing");

        queueSetMixCacheSize(_imageQueue, queueGetLength(_imageQueue)+_lowWaterFlag);
        _lastPauseFlag = getTime() / 1000;
        [_audioPlayer pause];
    }else{
        GJLOG(GJ_LOGDEBUG, "buffer when status not in running");
    }
    [_oLock unlock];
}
-(void)stopBuffering{
    [_oLock lock];
    if (_status == kPlayStatusBuffering) {
        _status = kPlayStatusRunning;
        GJLOG(GJ_LOGDEBUG,"buffer total:%d\n",_bufferTime);
        queueSetMixCacheSize(_imageQueue,0);
        if (_lastPauseFlag != 0) {
            _bufferTime += getTime() / 1000 - _lastPauseFlag;
            _lastPauseFlag = 0;
        }else{
            GJLOG(GJ_LOGWARNING, "暂停管理出现问题");
        }
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

-(CacheInfo)cache{
    GJImageBuffer* packet;
    long newPts = 0;
    CacheInfo value = {0};
    queueLockPop(_imageQueue);
    value.cacheCount = queueGetLength(_imageQueue);
    if(queuePeekValue(_imageQueue,value.cacheCount -1, (void**)&packet)){
        newPts = packet->pts;
        if (queuePeekValue(_imageQueue, 0, (void**)&packet)) {
            value.cacheTime = newPts - packet->pts;
        }else{
            value.cacheTime = 0;
        }
    }else{
        value.cacheTime = 0;
    }
    queueUnLockPop(_imageQueue);

    return value;
}
-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(uint64_t)pts{
    GJImageBuffer* imageBuffer  = (GJImageBuffer*)malloc(sizeof(GJImageBuffer));
    imageBuffer->image = imageData;
    imageBuffer->pts = pts;
    if (_imageQueue && queuePush(_imageQueue, imageBuffer, 0)) {
        CVPixelBufferRetain(imageData);
        if (queueGetLength(_imageQueue)> _highWaterFlag) {
            [self dewatering];
        }
        return YES;
    }else{
        GJLOG(GJ_LOGWARNING, "video player queue full,update oldest frame");
        GJImageBuffer* oldBuffer = NULL;
        if (queuePop(_imageQueue, (void**)&oldBuffer, 0)) {
            CVPixelBufferRelease(oldBuffer->image);
            free(oldBuffer);
            
            if(queuePush(_imageQueue, imageBuffer, 0)){
                CVPixelBufferRetain(imageBuffer->image);
                return YES;
            }else{
                GJLOG(GJ_LOGERROR,"player video data push error");
                free(imageBuffer);
                return NO;
            }
        }else{
            GJLOG(GJ_LOGERROR,"full player audio queue pop error");
            free( imageBuffer);
            return NO;
        }
    }
}

static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(uint64_t)pts{

    
    GJAudioBuffer* audioBuffer = (GJAudioBuffer*)malloc(sizeof(GJAudioBuffer));
    audioBuffer->audioData = audioData;
    audioBuffer->pts = pts;
    if(queuePush(_audioQueue, audioBuffer, 0)){
        retainBufferRetain(audioData);
        return YES;
    }else{
        GJLOG(GJ_LOGWARNING, "audio player queue full,update oldest frame");
        GJAudioBuffer* oldBuffer = NULL;
        if (queuePop(_audioQueue, (void**)&oldBuffer, 0)) {
            retainBufferUnRetain(oldBuffer->audioData);
            free(oldBuffer);
            if(queuePush(_audioQueue, audioBuffer, 0)){
                retainBufferRetain(audioData);
                return YES;
            }else{
                GJLOG(GJ_LOGERROR,"player audio data push error");
                free(audioBuffer);
                return NO;
            }
        }else{
            GJLOG(GJ_LOGERROR,"full player audio queue pop error");
            free(audioBuffer);
            return NO;
        }
    }
}



-(BOOL)GJAudioQueueDrivePlayer:(GJAudioQueueDrivePlayer *)player outAudioData:(void *)data outSize:(int *)size{
    GJAudioBuffer* audioBuffer;
    if (_audioQueue && queuePop(_audioQueue, (void**)&audioBuffer, 0)) {
        *size = audioBuffer->audioData->size - _audioOffset;
        memcpy(data, audioBuffer->audioData->data + _audioOffset, *size);

        retainBufferUnRetain(audioBuffer->audioData);
        _aClock = audioBuffer->pts;
        NSLog(@"audio pts:%d",_aClock);
        free(audioBuffer);
        return YES;
    }else{
        GJLOG(GJ_LOGDEBUG, "audio player queue empty");
        [self buffering];
        return NO;
    }
}
@end
