//
//  GJLivePlayer.m
//  GJCaptureTool
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePlayer.h"
#import "GJAudioQueueDrivePlayer.h"
#import "GJImageYUVDataInput.h"
#import "GJImageView.h"
#import "GJQueue.h"
#import <pthread.h>
#import "GJLog.h"
#import <sys/time.h>
#import "GJBufferPool.h"

//#define GJAUDIOQUEUEPLAY
#ifdef GJAUDIOQUEUEPLAY
#import "GJAudioQueuePlayer.h"
#endif



#define VIDEO_PTS_PRECISION   0.4
#define AUDIO_PTS_PRECISION   0.1

#define VIDEO_MAX_CACHE_COUNT 150
#define AUDIO_MAX_CACHE_COUNT 450

typedef struct _GJImageBuffer{
    CVImageBufferRef image;
    int64_t           pts;
}GJImageBuffer;
typedef struct _GJAudioBuffer{
    GJRetainBuffer* audioData;
    int64_t           pts;
}GJAudioBuffer;


typedef enum _TimeSYNCType{
    kTimeSYNCAudio,
    kTimeSYNCVideo,
    kTimeSYNCExternal,
}TimeSYNCType;

typedef struct CacheControl{
    int                         lowAudioWaterFlag;
    int                         highAudioWaterFlag;
    int                         lowVideoWaterFlag;
    int                         highVideoWaterFlag;
}GJCacheControl;
typedef struct PlayControl{
    GJPlayStatus         status;
    pthread_mutex_t      oLock;
    int                 audioOffset;
    pthread_t            playThread;

    GJQueue*             imageQueue;
    GJQueue*             audioQueue;
}GJPlayControl;
typedef struct SyncControl{
    long                 aClock;
    long                 vClock;
    long                 aCPTS;
    long                 vCPTS;

    float                speed;
    long                 bufferTotalDuration;
    long                 lastBufferDuration;
    long                 bufferTimes;

    long                 startTime;
    long                 startPts;
    long                 inVPts;
    long                 outVPts;
    long                 inAPts;
    long                 outAPts;
    long                 lastPauseFlag;
    TimeSYNCType          syncType;
    
#ifdef NETWORK_DELAY
    long                 networkDelay;
#endif
}GJSyncControl;
@interface GJLivePlayer()<GJAudioQueueDrivePlayerDelegate>{
    
    
    
#ifdef GJAUDIOQUEUEPLAY
    GJAudioQueuePlayer* _audioTestPlayer;
#endif
}
@property(strong,nonatomic)GJImageYUVDataInput*             YUVInput;
@property(strong,nonatomic)GJAudioQueueDrivePlayer*         audioPlayer;
@property(strong,nonatomic)GJImageView*                     displayView;

@property(assign,nonatomic)GJSyncControl       syncControl;
@property(assign,nonatomic)GJPlayControl       playControl;
@property(assign,nonatomic)GJCacheControl      cacheControl;




@end
@implementation GJLivePlayer

long long getTime(){
#ifdef USE_CLOCK
    static clockd =  CLOCKS_PER_SEC /1000000 ;
    return clock() / clockd;
#endif
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000000 + tv.tv_usec;
}

long getClockLine(GJSyncControl* sync){
    if (sync->syncType == kTimeSYNCAudio) {
        long time = getTime() / 1000;
        long  timeDiff = time - sync->aClock;
        return sync->aCPTS+timeDiff;
    }else if(sync->syncType == kTimeSYNCVideo){
        long time = getTime() / 1000;
        long  timeDiff = time - sync->vClock;
        return sync->vCPTS + timeDiff;
    }else{
//        long time = getTime() / 1000;
//        if (sync->speed > 1.0) {
//            sync->bufferTotalDuration -= (sync->speed - 1.0)*(time-sync->showTime);
//        }
//        float timeDiff = time - sync->startTime;
        return 0;//timeDiff + sync->startPts-sync->bufferTotalDuration;
    }
}
static void* playRunLoop(void* parm){
    pthread_setname_np("GJPlayLoop");
    GJLivePlayer* player = (__bridge GJLivePlayer *)(parm);
    GJPlayControl* _playControl = &(player->_playControl);
    GJSyncControl* _syncControl = &(player->_syncControl);
    GJCacheControl* _cacheControl = &(player->_cacheControl);
    AudioStreamBasicDescription* _audioFormat = &(player->_audioFormat);
    
    GJImageBuffer* cImageBuf;
    if (_playControl->status != kPlayStatusStop &&
        queuePop(_playControl->imageQueue, (void**)&cImageBuf, INT_MAX) && (_playControl->status != kPlayStatusStop)) {
        OSType type = CVPixelBufferGetPixelFormatType(cImageBuf->image);
        if (type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            player.YUVInput = [[GJImageYUVDataInput alloc]initPixelFormat:GJPixelFormatNV12];
            [player.YUVInput addTarget:(GPUImageView*)player.displayView];
            _syncControl->startPts = cImageBuf->pts;
            _syncControl->syncType = kTimeSYNCVideo;
        }else{
            GJAssert(0,"视频格式不支持");
            goto ERROR;
        }
    }else{
        goto ERROR;
    }
    GJAudioBuffer* audioBuffer;
//    queueSetMinCacheSize(_playControl->audioQueue, 12);
//    if (_playControl->status != kPlayStatusStop &&
//        queuePeekWaitValue(_playControl->audioQueue, queueGetMinCacheSize(_playControl->audioQueue), (void**)&audioBuffer,INT_MAX)) {
//        if (_playControl->status != kPlayStatusStop) {
//            if (player.audioFormat.mFormatID <=0) {
//                queueSetMinCacheSize(_playControl->audioQueue, 0);
//                if (((uint64_t*)audioBuffer->audioData) && 0xFFF0 != 0xFFF0) {
//                    GJAssert(0, "音频格式不支持");
//                    goto ERROR;
//                }
//                uint8_t* adts = audioBuffer->audioData->data;
//                uint8_t sampleIndex = adts[2] << 2;
//                sampleIndex = sampleIndex>>4;
//                int sampleRate = mpeg4audio_sample_rates[sampleIndex];
//                uint8_t channel = adts[2] & 0x1 <<2;
//                channel += (adts[3] & 0xb0)>>6;
//                _audioFormat->mChannelsPerFrame = channel;
//                _audioFormat->mSampleRate = sampleRate;
//                _audioFormat->mFramesPerPacket = 1024;
//                _audioFormat->mFormatID = kAudioFormatMPEG4AAC;
//            }
//
//        }
//        
//        if (_audioFormat->mFormatID == kAudioFormatLinearPCM) {
//            _playControl->audioOffset = 0;
//        }else if (_audioFormat->mFormatID == kAudioFormatMPEG4AAC){
//            _playControl->audioOffset = 7;
//        }
//
//        player.audioPlayer = [[GJAudioQueueDrivePlayer alloc]initWithSampleRate:_audioFormat->mSampleRate channel:_audioFormat->mChannelsPerFrame formatID:_audioFormat->mFormatID];
//        player.audioPlayer.delegate = player;
//        [player.audioPlayer start];
//
//        _syncControl->startPts = audioBuffer->pts;
//        _syncControl->syncType = kTimeSYNCAudio;
//    }else{
//        goto ERROR;
//    }
  
    _syncControl->startTime = getTime() / 1000;
    _syncControl->vClock = _syncControl->startTime;
    _syncControl->outVPts = cImageBuf->pts;
    [player.YUVInput updateDataWithImageBuffer:cImageBuf->image timestamp: CMTimeMake(cImageBuf->pts, 1000)];
    CVPixelBufferRelease(cImageBuf->image);
    _syncControl->vCPTS = cImageBuf->pts;
    GJBufferPoolSetData(defauleBufferPool(), (void*)cImageBuf);

    cImageBuf = NULL;
    
    GJLOG(GJ_LOGDEBUG, "start play runloop");
    while ((_playControl->status != kPlayStatusStop)) {
        if (queuePop(_playControl->imageQueue, (void**)&cImageBuf,_playControl->status == kPlayStatusRunning?0:INT_MAX)) {
            
          
           if (_playControl->status == kPlayStatusBuffering){
                [player stopBuffering];
           }else if (_playControl->status == kPlayStatusStop){
               CVPixelBufferRelease(cImageBuf->image);
               GJBufferPoolSetData(defauleBufferPool(), (void*)cImageBuf);
               cImageBuf = NULL;
               break;
           }
            if (_syncControl->speed > 1.0 && queueGetLength(_playControl->imageQueue)<_cacheControl->lowVideoWaterFlag) {
                [player stopDewatering];
            }
        }else{
            if (_playControl->status == kPlayStatusStop) {
                break;
            }else if (_playControl->status == kPlayStatusRunning){
                GJLOG(GJ_LOGDEBUG, "video play queue empty");
                if(_syncControl->syncType != kTimeSYNCAudio){
                    [player buffering];
                }else{
                    usleep(16*1000);
                }
            }
            continue;
        }
        
        long timeStandards = getClockLine(_syncControl);
        long delay = cImageBuf->pts - timeStandards;


        while (delay > VIDEO_PTS_PRECISION*1000 ) {
            if (_playControl->status == kPlayStatusStop) {
                goto DROP;
            }
            if(_syncControl->syncType == kTimeSYNCVideo){
                delay = VIDEO_PTS_PRECISION*1000-16;
                break;//视频不会长时间等待视频
            }
            GJLOG(GJ_LOGWARNING, "视频等待时间长 delay:%ld PTS:%ld clock:%ld",delay,cImageBuf->pts,timeStandards);
            usleep(VIDEO_PTS_PRECISION*1000000);
            timeStandards = getClockLine(_syncControl);
            delay = cImageBuf->pts - timeStandards;
        }
        if (delay < -VIDEO_PTS_PRECISION*1000){
            GJLOG(GJ_LOGWARNING, "丢帧,视频落后严重，delay：%ld, PTS:%ld clock:%ld",delay,cImageBuf->pts,timeStandards);
            _syncControl->vCPTS = cImageBuf->pts;
            _syncControl->vClock = getTime() / 1000;
            goto DROP;
        }
    DISPLAY:
        if (delay > 10) {
            usleep((unsigned int)delay * 1000);
        }
        _syncControl->vClock = getTime() / 1000;
        _syncControl->outVPts = cImageBuf->pts;
        static int oTimes;
        NSLog(@"oTimes:%d,pts:%lld",oTimes++,cImageBuf->pts);
        [player.YUVInput updateDataWithImageBuffer:cImageBuf->image timestamp: CMTimeMake(cImageBuf->pts, 1000)];
        _syncControl->vCPTS = cImageBuf->pts;
        GJLOG(GJ_LOGALL,"video pts:%ld",_syncControl->vCPTS);
    DROP:
        CVPixelBufferRelease(cImageBuf->image);

        GJBufferPoolSetData(defauleBufferPool(), (void*)cImageBuf);
        cImageBuf = NULL;
    }
ERROR:
    GJLOG(GJ_LOGINFO, "playRunLoop out");
    _playControl->status = kPlayStatusStop;
    _playControl->playThread = nil;
    return NULL;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        memset(&_audioFormat, 0, sizeof(_audioFormat));
 
        _syncControl.speed = 1.0;
        _playControl.status = kPlayStatusStop;
        
        _cacheControl.lowAudioWaterFlag = 43;
        _cacheControl.lowVideoWaterFlag = 15;
        _cacheControl.highAudioWaterFlag = 172;
        _cacheControl.highVideoWaterFlag = 60;

        pthread_mutex_init(&_playControl.oLock, NULL);
        _displayView = [[GJImageView alloc]init];
        queueCreate(&_playControl.imageQueue, VIDEO_MAX_CACHE_COUNT, true, false);//150为暂停时视频最大缓冲
        queueCreate(&_playControl.audioQueue, AUDIO_MAX_CACHE_COUNT, true, false);
    }
    return self;
}
-(UIView *)displayView{
    return _displayView;
}

-(void)start{
    pthread_mutex_lock(&_playControl.oLock);
    GJLOG(GJ_LOGINFO, "GJLivePlayer start");
    if (_playControl.playThread == nil) {
        _playControl.status = kPlayStatusRunning;
        pthread_create(&_playControl.playThread, NULL, playRunLoop, (__bridge void *)(self));
//        _playThread = [[NSThread alloc]initWithTarget:self selector:@selector(playRunLoop) object:nil];
//        [_playThread start];
    }else{
        GJLOG(GJ_LOGWARNING, "重复播放");
    }
    pthread_mutex_unlock(&_playControl.oLock);
}
-(void)stop{
    if (_playControl.status == kPlayStatusBuffering) {
        [self stopBuffering];
    }
    pthread_mutex_lock(&_playControl.oLock);
    if(_playControl.status != kPlayStatusStop){
        _playControl.status = kPlayStatusStop;
        [_audioPlayer stop:false];
        queueBroadcastPop(_playControl.imageQueue);
        queueBroadcastPop(_playControl.audioQueue);
        pthread_join(_playControl.playThread, NULL);
        queueClean(_playControl.imageQueue);
        queueClean(_playControl.audioQueue);
    }else{
        GJLOG(GJ_LOGWARNING, "重复停止");
    }
    pthread_mutex_unlock(&_playControl.oLock);
}
//-(void)pause{
//
//    _playControl.status = kPlayStatusPause;
//    _lastPauseFlag = getTime() / 1000;
//    
//    queueSetMixCacheSize(_playControl.imageQueue, VIDEO_MAX_CACHE_COUNT);
//    [_audioPlayer pause];
//    queueLockPop(_playControl.imageQueue);
//    queueWaitPop(_playControl.imageQueue, INT_MAX);
//    queueUnLockPop(_playControl.imageQueue);
//    [_oLock lock];
//
//}
//-(void)resume{
//    if (_playControl.status == kPlayStatusPause) {
//        _playControl.status = kPlayStatusRunning;
//         GJLOG(GJ_LOGINFO,"buffer total:%d\n",_bufferTime);
//        queueSetMixCacheSize(_playControl.imageQueue,0);
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
    pthread_mutex_lock(&_playControl.oLock);
    if(_playControl.status == kPlayStatusRunning){
        GJLOG(GJ_LOGDEBUG, "start buffing");
        _syncControl.lastPauseFlag = getTime() / 1000;
        [_audioPlayer pause];
        if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
            [self.delegate livePlayer:self bufferUpdatePercent:0.0 duration:0.0];
        }
        if (_syncControl.syncType == kTimeSYNCAudio) {
            queueSetMinCacheSize(_playControl.audioQueue, (uint)(_cacheControl.lowAudioWaterFlag));
            queueLockPop(_playControl.imageQueue);
        }else{
            queueSetMinCacheSize(_playControl.imageQueue, (uint)(_cacheControl.lowVideoWaterFlag));
            queueLockPop(_playControl.audioQueue);
        }
        _playControl.status = kPlayStatusBuffering;
    }else{
        GJLOG(GJ_LOGDEBUG, "buffer when status not in running");
    }
    pthread_mutex_unlock(&_playControl.oLock);
}
-(void)stopBuffering{
    pthread_mutex_lock(&_playControl.oLock);
    if (_playControl.status == kPlayStatusBuffering) {
        _playControl.status = kPlayStatusRunning;

        if (_syncControl.syncType == kTimeSYNCAudio) {
            queueSetMinCacheSize(_playControl.audioQueue, 0);
            queueUnLockPop(_playControl.imageQueue);
        }else{
            queueSetMinCacheSize(_playControl.imageQueue, 0);
            queueUnLockPop(_playControl.audioQueue);
        }
        if (_syncControl.lastPauseFlag != 0) {
            _syncControl.lastBufferDuration = getTime() / 1000 - _syncControl.lastPauseFlag;
            _syncControl.bufferTotalDuration += _syncControl.lastBufferDuration;
            _syncControl.bufferTimes++;
            _syncControl.lastPauseFlag = 0;
            GJLOG(GJ_LOGINFO, "buffing times:%d,totalduring:%ld",_syncControl.bufferTimes,_syncControl.bufferTotalDuration);
        }else{
            GJAssert(0, "暂停管理出现问题");
        }
        [_audioPlayer resume];
        GJLOG(GJ_LOGDEBUG,"buffer total:%d\n",_syncControl.lastBufferDuration);

    }else{
        GJLOG(GJ_LOGDEBUG, "stopBuffering when status not buffering");
    }
    pthread_mutex_unlock(&_playControl.oLock);
}
-(void)dewatering{
    return;
    pthread_mutex_lock(&_playControl.oLock);
    if (_playControl.status == kPlayStatusRunning) {
        if (_syncControl.speed<=1.0) {
            GJLOG(GJ_LOGDEBUG, "startDewatering");
            _syncControl.speed = 1.2;
            _audioPlayer.speed = _syncControl.speed;
        }
    }
    pthread_mutex_unlock(&_playControl.oLock);
}
-(void)stopDewatering{
    return;
    pthread_mutex_lock(&_playControl.oLock);
    if (_syncControl.speed > 1.0) {
        GJLOG(GJ_LOGDEBUG, "stopDewatering");
        _syncControl.speed = 1.0;
        _audioPlayer.speed = _syncControl.speed;
    }
    pthread_mutex_unlock(&_playControl.oLock);
}
-(GJCacheInfo)getAudioCache{
    GJCacheInfo value = {0};
    value.cacheCount = (int)queueGetLength(_playControl.audioQueue);
    value.cacheTime = (int)(_syncControl.inAPts - _syncControl.outAPts);
    return value;
}
-(GJCacheInfo)getVideoCache{
    GJCacheInfo value = {0};

    value.cacheCount = (int)queueGetLength(_playControl.imageQueue);
    value.cacheTime  = (int)(_syncControl.inVPts - _syncControl.outVPts);

    return value;
}
#ifdef NETWORK_DELAY
-(long)getNetWorkDelay{
    return _syncControl.networkDelay;
}
#endif
-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(int64_t)pts{    
    GJImageBuffer* imageBuffer  = (GJImageBuffer*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJImageBuffer));
    imageBuffer->image = imageData;
    imageBuffer->pts = pts;
    CVPixelBufferRetain(imageData);
    static int iTimes;
    NSLog(@"inTimes:%d,pts:%lld",iTimes++,pts);
    if (queuePush(_playControl.imageQueue, imageBuffer, 0)) {
        _syncControl.inVPts = imageBuffer->pts;
#ifdef NETWORK_DELAY
        int date = [[NSDate date]timeIntervalSince1970]*1000;
        _syncControl.networkDelay = date - _syncControl.inVPts;
#endif

        if (_syncControl.syncType != kTimeSYNCAudio && queueGetLength(_playControl.imageQueue)> _cacheControl.highVideoWaterFlag) {
            [self dewatering];
        }
        return YES;
    }else{
        GJLOG(GJ_LOGWARNING, "video player queue full,update oldest frame");
        GJImageBuffer* oldBuffer = NULL;
        if (queuePop(_playControl.imageQueue, (void**)&oldBuffer, 0)) {
            CVPixelBufferRelease(oldBuffer->image);
            GJBufferPoolSetData(defauleBufferPool(), (void*)oldBuffer);
            
            if(!queuePush(_playControl.imageQueue, imageBuffer, 0)){
                GJLOG(GJ_LOGERROR,"player video data push error");
                CVPixelBufferRelease(imageData);
                GJBufferPoolSetData(defauleBufferPool(), (void*)imageBuffer);
                return NO;
            }else{
                return YES;
            }
        }else{
            GJLOG(GJ_LOGERROR,"full player audio queue pop error");
            GJBufferPoolSetData(defauleBufferPool(), (void*)imageBuffer);
            return NO;
        }
    }
}

static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(int64_t)pts{
#ifdef GJAUDIOQUEUEPLAY
    if (_audioTestPlayer == nil) {
        if (_audioFormat.mFormatID <=0) {
            queueSetMinCacheSize(_playControl.audioQueue, 0);
            if (((uint64_t*)audioData->data) && 0xFFF0 != 0xFFF0) {
                NSAssert(0, @"音频格式不支持");
            }
            uint8_t* adts = audioData->data;
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
        if (_audioFormat.mFormatID == kAudioFormatLinearPCM) {
            _audioOffset = 0;
        }else if (_audioFormat.mFormatID == kAudioFormatMPEG4AAC){
            _audioOffset = 7;
        }
        _audioTestPlayer = [[GJAudioQueuePlayer alloc]initWithSampleRate:_audioFormat.mSampleRate channel:_audioFormat.mChannelsPerFrame formatID:_audioFormat.mFormatID];
        [_audioTestPlayer start];
    }

    [_audioTestPlayer playData:audioData packetDescriptions:nil];
    return YES;
#endif
    GJAudioBuffer* audioBuffer = (GJAudioBuffer*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJAudioBuffer));
    audioBuffer->audioData = audioData;
    audioBuffer->pts = pts;
    retainBufferRetain(audioData);
    if(queuePush(_playControl.audioQueue, audioBuffer, 0)){
        _syncControl.inAPts = audioBuffer->pts;
#ifdef NETWORK_DELAY
        int date = [[NSDate date]timeIntervalSince1970]*1000;
        _syncControl.networkDelay = date - _syncControl.inAPts;
#endif
        if (_syncControl.syncType == kTimeSYNCAudio) {
            long length = queueGetLength(_playControl.audioQueue);
            if (_playControl.status == kPlayStatusBuffering){
                long duration = (long)(getTime()/1000) - _syncControl.lastPauseFlag;
                if (length < _cacheControl.lowAudioWaterFlag){
                    if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
                        [self.delegate livePlayer:self bufferUpdatePercent:length*1.0/_cacheControl.lowAudioWaterFlag duration:duration];
                    }
                }else{
                    if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
                        [self.delegate livePlayer:self bufferUpdatePercent:1.0 duration:duration];
                        [self stopBuffering];
                    }
                }
            }else if (_playControl.status == kPlayStatusRunning){
                if (length > _cacheControl.highVideoWaterFlag ) {
                    if (_syncControl.speed <= 1.0) {
                        [self dewatering];
                    }
                }else if (length < _cacheControl.lowAudioWaterFlag ){
                    if (_syncControl.speed >1.0) {
                        [self stopDewatering];
                    }
                }
            }
        }
        return YES;
    }else{
        GJLOG(GJ_LOGWARNING, "audio player queue full,update oldest frame");
        GJAudioBuffer* oldBuffer = NULL;
        if (queuePop(_playControl.audioQueue, (void**)&oldBuffer, 0)) {
            retainBufferUnRetain(oldBuffer->audioData);
            GJBufferPoolSetData(defauleBufferPool(), (void*)oldBuffer);
            if(!queuePush(_playControl.audioQueue, audioBuffer, 0)){
                GJLOG(GJ_LOGERROR,"player audio data push error");
                retainBufferUnRetain(audioData);
                GJBufferPoolSetData(defauleBufferPool(), (void*)audioBuffer);
                return NO;
            }else{
                return YES;
            }
        }else{
            GJLOG(GJ_LOGERROR,"full player audio queue pop error");
            GJBufferPoolSetData(defauleBufferPool(), (void*)audioBuffer);
            return NO;
        }
    }
}



-(BOOL)GJAudioQueueDrivePlayer:(GJAudioQueueDrivePlayer *)player outAudioData:(void *)data outSize:(int *)size{
    GJAudioBuffer* audioBuffer;
    if (_playControl.status == kPlayStatusRunning && _playControl.audioQueue && queuePop(_playControl.audioQueue, (void**)&audioBuffer, 0)) {
        *size = audioBuffer->audioData->size - _playControl.audioOffset;
        memcpy(data, audioBuffer->audioData->data + _playControl.audioOffset, *size);
        _syncControl.outAPts = audioBuffer->pts;
        _syncControl.aCPTS = audioBuffer->pts;
        _syncControl.aClock = getTime()/1000;
        GJLOG(GJ_LOGALL,"audio play pts:%d size:%d",_syncControl.aCPTS,*size);
        retainBufferUnRetain(audioBuffer->audioData);
        GJBufferPoolSetData(defauleBufferPool(), (void*)audioBuffer);
        return YES;
    }else{
        if (_playControl.status == kPlayStatusRunning) {
            GJLOG(GJ_LOGDEBUG, "audio player queue empty");
            if (_syncControl.syncType == kTimeSYNCAudio) {
                [self buffering];
            }
        }
        return NO;
    }
}
@end
