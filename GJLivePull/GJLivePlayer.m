//
//  GJLivePlayer.m
//  GJCaptureTool
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePlayer.h"
#import "GJAudioQueueDrivePlayer.h"
#import "GJImagePixelImageInput.h"
#import "GJImageView.h"
#import "GJQueue.h"
#import <pthread.h>
#import "GJLog.h"
#import "GJBufferPool.h"
#include "GJUtil.h"
//#define GJAUDIOQUEUEPLAY
#ifdef GJAUDIOQUEUEPLAY
#import "GJAudioQueuePlayer.h"
#endif


//#define UIIMAGE_SHOW



#define VIDEO_PTS_PRECISION   1000
#define AUDIO_PTS_PRECISION   100



#define VIDEO_MAX_CACHE_DUR 3000
#define AUDIO_MAX_CACHE_DUR 3000

#define VIDEO_MIN_CACHE_DUR 200
#define AUDIO_MIN_CACHE_DUR 200

#define VIDEO_MAX_CACHE_COUNT 100 //缓存空间，不能小于VIDEO_MAX_CACHE_DUR的帧数
#define AUDIO_MAX_CACHE_COUNT 200



typedef struct _GJImageBuffer{
    CVImageBufferRef image;
    GInt64           pts;
}GJImageBuffer;
typedef struct _GJAudioBuffer{
    GJRetainBuffer* audioData;
    GInt64           pts;
}GJAudioBuffer;



typedef enum _TimeSYNCType{
    kTimeSYNCAudio,
    kTimeSYNCVideo,
}TimeSYNCType;

typedef struct CacheControl{
    GUInt32                         lowAudioWaterFlag;
    GUInt32                         highAudioWaterFlag;
    GUInt32                         lowVideoWaterFlag;
    GUInt32                         highVideoWaterFlag;
}GJCacheControl;
typedef struct PlayControl{
    GJPlayStatus         status;
    pthread_mutex_t      oLock;
    pthread_t            playVideoThread;

    GJQueue*             imageQueue;
    GJQueue*             audioQueue;
}GJPlayControl;
typedef struct _GJNetShakeControl{
    GInt32 collectStartClock;
    GInt32 collectUnitStartClock;
    GInt32 collectUnitEndClock;
    GInt32 collectUnitCache;
    GInt32 maxCache;
    GInt32 minCache;
}GJNetShakeControl;
typedef struct _SyncInfo{
    GLong                 clock;
    GLong                 cPTS;

    GLong                 startTime;
    GLong                 startPts;
//    GLong                 trafficStatus.enter.pts;
//    GLong                 trafficStatus.leave.pts;

    GJTrafficStatus     trafficStatus;
}SyncInfo;
typedef struct SyncControl{
    SyncInfo videoInfo;
    SyncInfo audioInfo;
    GFloat32                speed;
    GLong                 speedTotalDuration;
    GLong                 bufferTotalDuration;
    GLong                 lastBufferDuration;
    GLong                 bufferTimes;
    GLong                 lastPauseFlag;
    TimeSYNCType          syncType;
#ifdef NETWORK_DELAY
    GLong                 networkDelay;
#endif
}GJSyncControl;
@interface GJLivePlayer()<GJAudioQueueDrivePlayerDelegate>{
    
    
    
#ifdef GJAUDIOQUEUEPLAY
    GJAudioQueuePlayer* _audioTestPlayer;
#endif
}
#ifndef UIIMAGE_SHOW
@property(strong,nonatomic)GJImagePixelImageInput*          imageInput;
#endif
@property(strong,nonatomic)GJAudioQueueDrivePlayer*         audioPlayer;
@property(strong,nonatomic)GJImageView*                     displayView;

@property(assign,nonatomic)GJSyncControl       syncControl;
@property(assign,nonatomic)GJPlayControl       playControl;
@property(assign,nonatomic)GJCacheControl      cacheControl;
@property(assign,nonatomic)GJNetShakeControl   shakeControl;
@end
@implementation GJLivePlayer



GLong getClockLine(GJSyncControl* sync){
    if (sync->syncType == kTimeSYNCAudio) {
        GLong time = GJ_Gettime() / 1000;
        GLong  timeDiff = time - sync->audioInfo.clock;
        return sync->audioInfo.cPTS+timeDiff;
    }else{
        GLong time = GJ_Gettime() / 1000;
        GLong timeDiff = time - sync->videoInfo.startTime;
        return timeDiff + sync->videoInfo.startPts - sync->bufferTotalDuration + sync->speedTotalDuration;
    }
}
static void resetSyncToStartPts(GJSyncControl* sync,GLong startPts){
    sync->videoInfo.startPts = sync->audioInfo.startPts = startPts;
    sync->videoInfo.startTime = sync->audioInfo.startTime = GJ_Gettime() / 1000.0;
    sync->speedTotalDuration = sync->bufferTotalDuration = 0;
}
static void changeSyncType(GJSyncControl* sync,TimeSYNCType syncType){
    if (syncType == kTimeSYNCVideo) {
        sync->syncType = kTimeSYNCVideo;
        resetSyncToStartPts(sync, sync->videoInfo.cPTS);
    }else{
        sync->syncType = kTimeSYNCAudio;
        resetSyncToStartPts(sync, sync->audioInfo.cPTS);
    }

}
static GHandle playVideoRunLoop(GHandle parm){
    pthread_setname_np("playVideoRunLoop");
    GJLivePlayer* player = (__bridge GJLivePlayer *)(parm);
    GJPlayControl* _playControl = &(player->_playControl);
    GJSyncControl* _syncControl = &(player->_syncControl);
    GJImageBuffer* cImageBuf;
  
    cImageBuf = GNULL;
    
    GJLOG(GJ_LOGDEBUG, "start play runloop");
    GJImageBuffer watiBuffer[2] = {0};
    queuePeekWaitValue(_playControl->imageQueue, 2, (GHandle*)&watiBuffer, GINT32_MAX);///等待至少两帧
    _syncControl->videoInfo.startTime = GJ_Gettime() / 1000;
    while ((_playControl->status != kPlayStatusStop)) {
        if (queuePop(_playControl->imageQueue, (GHandle*)&cImageBuf,_playControl->status == kPlayStatusBuffering?INT_MAX:0)) {
            if (_playControl->status == kPlayStatusStop){
               CVPixelBufferRelease(cImageBuf->image);
               GJBufferPoolSetData(defauleBufferPool(), (GHandle)cImageBuf);
               cImageBuf = GNULL;
               break;
            }
        }else{
            if (_playControl->status == kPlayStatusStop) {
                break;
            }else if (_playControl->status == kPlayStatusRunning){
                if(_syncControl->syncType == kTimeSYNCVideo){
                    GJLOG(GJ_LOGDEBUG, "video play queue empty when kTimeSYNCVideo,start buffer");
                    [player buffering];
                }else{
                    GJLOG(GJ_LOGWARNING, "video play queue empty when kTimeSYNCAudio,do not buffer");
                }
            }
            usleep(16*1000);
            continue;
        }
        
        GLong timeStandards = getClockLine(_syncControl);
        GLong delay = (GLong)cImageBuf->pts - timeStandards;

        if(delay > VIDEO_PTS_PRECISION) {
            if (_playControl->status == kPlayStatusStop) {
                goto DROP;
            }
            if(_syncControl->syncType == kTimeSYNCVideo){
                GJLOG(GJ_LOGWARNING, "视频等待视频时间过长 delay:%ld PTS:%ld clock:%ld,重置同步管理",delay,cImageBuf->pts,timeStandards);
                resetSyncToStartPts(_syncControl, (GLong)cImageBuf->pts);
                delay = 0;
            }else{
                GJLOG(GJ_LOGWARNING, "视频等待音频时间过长 delay:%ld PTS:%ld clock:%ld，等待下一帧做判断处理",delay,cImageBuf->pts,timeStandards);
                GJImageBuffer* nextBuffer = GNULL;
                if( queuePeekWaitValue(_playControl->imageQueue, 0, (GHandle*)&nextBuffer, VIDEO_PTS_PRECISION)){
                    if(nextBuffer->pts < cImageBuf->pts){
                        GJLOG(GJ_LOGWARNING, "视频PTS重新开始，直接丢帧");
                        goto DROP;
                    }else{
                        GLong oDelay = delay;
                        GJLOG(GJ_LOGWARNING, "视频PTS很可能错误，连续两帧需要长时间等待");
                        while (delay>20) {
                            if (_playControl->status == kPlayStatusStop) {
                                goto DROP;
                            }else{
                                GJLOG(GJ_LOGWARNING, "视频等待音频：%ld ms",oDelay - delay);
                                usleep((GUInt32)delay * 1000);
                                delay -= VIDEO_PTS_PRECISION;
                            }
                        }

                    }
                }else{
                    GJLOG(GJ_LOGWARNING, "视频等待音频时间过长,并且没有下一帧，直接丢帧");
                    goto DROP;
                };
//                if (queueGetLength(_playControl->audioQueue) == 0) {
//                    GJLOG(GJ_LOGWARNING, "视频等待音频时间过长,且音频为空，判断为音频断开，切换到视频同步",delay,cImageBuf->pts,timeStandards);
//                    _syncControl->syncType = kTimeSYNCVideo;
//                    delay = 0;
//                }
            }
        }
        if (delay < -VIDEO_PTS_PRECISION){
            if(_syncControl->syncType == kTimeSYNCVideo){
                GJLOG(GJ_LOGWARNING, "视频落后视频严重，delay：%ld, PTS:%ld clock:%ld，重置同步管理",delay,cImageBuf->pts,timeStandards);
                resetSyncToStartPts(_syncControl, (GLong)cImageBuf->pts);
                delay = 0;
            }else{
                GJLOG(GJ_LOGWARNING, "视频落后音频严重，delay：%ld, PTS:%ld clock:%ld，丢视频帧",delay,cImageBuf->pts,timeStandards);
                _syncControl->videoInfo.cPTS = (GLong)cImageBuf->pts;
                _syncControl->videoInfo.trafficStatus.leave.pts = (GLong)cImageBuf->pts;
                _syncControl->videoInfo.clock = GJ_Gettime() / 1000;
                goto DROP;
            }
        }
    DISPLAY:
        if (delay > 20) {
            GJLOGFREQ("play wait:%d, video pts:%ld",delay,_syncControl->videoInfo.cPTS);
            usleep((GUInt32)delay * 1000);
        }
        
        if (_syncControl->speed > 1.0) {
            _syncControl->speedTotalDuration += (_syncControl->speed - 1.0)*(GJ_Gettime() / 1000.0-_syncControl->videoInfo.clock);
        }
        
        _syncControl->videoInfo.clock = GJ_Gettime() / 1000;
        _syncControl->videoInfo.trafficStatus.leave.pts = (GLong)cImageBuf->pts;
        _syncControl->videoInfo.cPTS = (GLong)cImageBuf->pts;
        


#ifdef UIIMAGE_SHOW
        {
            CIImage* cimage = [CIImage imageWithCVPixelBuffer:cImageBuf->image];
            UIImage* image = [UIImage imageWithCIImage:cimage];
            // Update the display with the captured image for DEBUG purposes
            dispatch_async(dispatch_get_main_queue(), ^{
                ( (UIImageView*)player.displayView).image = image;
            });
        }
#else
        GJLOGFREQ("image show pts:%d",cImageBuf->pts);
        [player.imageInput updateDataWithImageBuffer:cImageBuf->image timestamp: CMTimeMake(cImageBuf->pts, 1000)];
        
#endif
    DROP:
        _syncControl->videoInfo.trafficStatus.leave.count++;
        CVPixelBufferRelease(cImageBuf->image);

        GJBufferPoolSetData(defauleBufferPool(), (GHandle)cImageBuf);
        cImageBuf = GNULL;
    }
ERROR:
    GJLOG(GJ_LOGINFO, "playRunLoop out");
    _playControl->status = kPlayStatusStop;
    _playControl->playVideoThread = nil;
    return GNULL;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        memset(&_audioFormat, 0, sizeof(_audioFormat));
 
        _syncControl.speed = 1.0;
        _playControl.status = kPlayStatusStop;
        
        _cacheControl.lowAudioWaterFlag = AUDIO_MIN_CACHE_DUR;
        _cacheControl.lowVideoWaterFlag = VIDEO_MIN_CACHE_DUR;
        _cacheControl.highAudioWaterFlag = AUDIO_MAX_CACHE_DUR;
        _cacheControl.highVideoWaterFlag = VIDEO_MAX_CACHE_DUR;
        _syncControl.syncType = kTimeSYNCVideo;

        pthread_mutex_init(&_playControl.oLock, GNULL);
        
#ifdef UIIMAGE_SHOW
        _displayView = (GJImageView*)[[UIImageView alloc]init];
#else
    _displayView = [[GJImageView alloc]init];
#endif
        queueCreate(&_playControl.imageQueue, VIDEO_MAX_CACHE_COUNT, GTrue, GTrue);//150为暂停时视频最大缓冲
        queueCreate(&_playControl.audioQueue, AUDIO_MAX_CACHE_COUNT, GTrue, GTrue);
    }
    return self;
}
-(UIView *)displayView{
    return _displayView;
}

-(void)start{
    pthread_mutex_lock(&_playControl.oLock);
    GJLOG(GJ_LOGINFO, "GJLivePlayer start");
    _playControl.status = kPlayStatusRunning;
    _syncControl.videoInfo.startPts = _syncControl.audioInfo.startPts = LONG_MIN;
    memset(&_shakeControl, 0, sizeof(_shakeControl));
    queueEnablePush(_playControl.imageQueue, GTrue);
    queueEnablePush(_playControl.audioQueue, GTrue);

//    if (_playControl.playVideoThread == nil) {
//        _playControl.status = kPlayStatusRunning;
////        _playVideoThread = [[NSThread alloc]initWithTarget:self selector:@selector(playRunLoop) object:nil];
////        [_playVideoThread start];
//    }else{
//        GJLOG(GJ_LOGWARNING, "重复播放");
//    }
    pthread_mutex_unlock(&_playControl.oLock);
}
-(void)stop{
    [self stopBuffering];
    if(_playControl.status != kPlayStatusStop){
        GJLOG(GJ_LOGINFO, "gjliveplayer stop start");
        pthread_mutex_lock(&_playControl.oLock);
        _playControl.status = kPlayStatusStop;
        queueEnablePush(_playControl.audioQueue, GFalse);
        queueEnablePush(_playControl.imageQueue, GFalse);
        
        queueBroadcastPop(_playControl.imageQueue);
        queueBroadcastPop(_playControl.audioQueue);
        pthread_mutex_unlock(&_playControl.oLock);

        pthread_join(_playControl.playVideoThread, GNULL);

        pthread_mutex_lock(&_playControl.oLock);
        [_audioPlayer stop:true];
        _audioPlayer = nil;
        GInt32 vlength = queueGetLength(_playControl.imageQueue);
        GInt32 alength = queueGetLength(_playControl.audioQueue);
        
        if (vlength > 0) {
            GJImageBuffer** imageBuffer = (GJImageBuffer**)malloc(sizeof(GJImageBuffer*)*vlength);
            //不能用queuePop，因为已经enable false;
            if (queueClean(_playControl.imageQueue, (GHandle*)imageBuffer, &vlength)) {
                for (GInt32 i = 0; i < vlength; i++) {
                    CVPixelBufferRelease(imageBuffer[i]->image);
                    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)imageBuffer[i]);
                }
            }else{
                GJLOG(GJ_LOGFORBID, "videoClean Error");
            }
            free(imageBuffer);
//            while (queuePop(_playControl.imageQueue, (GVoid**)&imageBuffer, 0)) {
//                CVPixelBufferRelease(imageBuffer->image);
//                GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)imageBuffer);
//            }
        }
        GJLOG(GJ_LOGDEBUG, "video player queue clean over");
        if (alength > 0) {
            GJAudioBuffer** audioBuffer = (GJAudioBuffer**)malloc(sizeof(GJAudioBuffer*)*alength);
            if (queueClean(_playControl.audioQueue, (GHandle*)audioBuffer, &alength)) {
                for (GInt32 i = 0; i < alength; i++) {
                    retainBufferUnRetain(audioBuffer[i]->audioData);
                    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)audioBuffer[i]);
                }
            }else{
                GJLOG(GJ_LOGFORBID, "audioClean Error");
            }
            free(audioBuffer);
        }
        GJLOG(GJ_LOGDEBUG, "audio player queue clean over");
        pthread_mutex_unlock(&_playControl.oLock);
        
    }else{
        GJLOG(GJ_LOGWARNING, "重复停止");
    }
    
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
        _playControl.status = kPlayStatusBuffering;
        _syncControl.lastPauseFlag = GJ_Gettime() / 1000;
        [_audioPlayer pause];
        if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
            [self.delegate livePlayer:self bufferUpdatePercent:0.0 duration:0.0];
        }
        queueSetMinCacheSize(_playControl.imageQueue, VIDEO_MAX_CACHE_COUNT);
        queueSetMinCacheSize(_playControl.audioQueue, AUDIO_MAX_CACHE_COUNT);
    }else{
        GJLOG(GJ_LOGDEBUG, "buffer when status not in running");
    }
    pthread_mutex_unlock(&_playControl.oLock);
}
-(void)stopBuffering{
    pthread_mutex_lock(&_playControl.oLock);
    if (_playControl.status == kPlayStatusBuffering) {
        _playControl.status = kPlayStatusRunning;
        queueSetMinCacheSize(_playControl.imageQueue, 0);
        queueBroadcastPop(_playControl.imageQueue);
        queueSetMinCacheSize(_playControl.audioQueue, 0);
        queueBroadcastPop(_playControl.audioQueue);
        
        if (_syncControl.lastPauseFlag != 0) {
            _syncControl.lastBufferDuration = GJ_Gettime() / 1000 - _syncControl.lastPauseFlag;
            _syncControl.bufferTotalDuration += _syncControl.lastBufferDuration;
            _syncControl.bufferTimes++;
            _syncControl.lastPauseFlag = 0;
        }else{
            GJLOG(GJ_LOGFORBID, "暂停管理出现问题");
        }
        [_audioPlayer resume];
        GJLOG(GJ_LOGINFO, "buffing times:%d useDuring:%d",_syncControl.bufferTimes,_syncControl.lastBufferDuration);
    }else{
        GJLOG(GJ_LOGDEBUG, "stopBuffering when status not buffering");
    }
    pthread_mutex_unlock(&_playControl.oLock);
}
-(void)dewatering{
//    return;
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
//    return;
    pthread_mutex_lock(&_playControl.oLock);
    if (_syncControl.speed > 1.0) {
        GJLOG(GJ_LOGDEBUG, "stopDewatering");
        _syncControl.speed = 1.0;
        _audioPlayer.speed = _syncControl.speed;
    }
    pthread_mutex_unlock(&_playControl.oLock);
}
-(GJTrafficStatus)getAudioCache{
   
    return _syncControl.audioInfo.trafficStatus;
}
-(GJTrafficStatus)getVideoCache{
    return _syncControl.videoInfo.trafficStatus;
}
#ifdef NETWORK_DELAY
-(GLong)getNetWorkDelay{
    return _syncControl.networkDelay;
}
#endif

-(void)checkBufferingAndWater{
//    GLong alength = queueGetLength(_playControl.audioQueue);
//    GLong vlength = queueGetLength(_playControl.imageQueue);

    if(_syncControl.syncType == kTimeSYNCAudio){
        if (_playControl.status == kPlayStatusBuffering){
            GLong vCache = _syncControl.videoInfo.trafficStatus.leave.pts - _syncControl.videoInfo.trafficStatus.leave.pts;
            GLong aCache = _syncControl.audioInfo.trafficStatus.enter.pts - _syncControl.audioInfo.trafficStatus.leave.pts;
            
            if ((aCache == 0 && vCache >= _cacheControl.lowVideoWaterFlag) || vCache >= _cacheControl.highVideoWaterFlag-300) {
                GJLOG(GJ_LOGWARNING, "音频缓冲过程中，音频为空视频足够、或者视频足够大于音频。切换到视频同步");
                [self stopBuffering];
                changeSyncType(&_syncControl, kTimeSYNCVideo);
                return;
            }
            GLong duration = (GLong)(GJ_Gettime()/1000) - _syncControl.lastPauseFlag;
            if (aCache < _cacheControl.lowAudioWaterFlag){
                if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
                    GJLOG(GJ_LOGINFO, "buffer percent:%f A cacheTime:%ld",aCache*1.0/_cacheControl.lowAudioWaterFlag,aCache);
                    [self.delegate livePlayer:self bufferUpdatePercent:aCache*1.0/_cacheControl.lowAudioWaterFlag duration:duration];
                }
            }else{
                if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
                    GJLOG(GJ_LOGINFO, "buffer percent:%f A cacheTime:%ld",1.0,aCache);
                    [self.delegate livePlayer:self bufferUpdatePercent:1.0 duration:duration];
                }
                [self stopBuffering];
            }
        }else if (_playControl.status == kPlayStatusRunning){
            GLong aCache = _syncControl.audioInfo.trafficStatus.enter.pts - _syncControl.audioInfo.trafficStatus.leave.pts;
            if (aCache > _cacheControl.highAudioWaterFlag ) {
                if (_syncControl.speed <= 1.0) {
                    [self dewatering];
                }
            }else if (aCache < _cacheControl.lowAudioWaterFlag ){
                if (_syncControl.speed >1.0) {
                    [self stopDewatering];
                }
            }
        }
    }else{
        GLong vCache = _syncControl.videoInfo.trafficStatus.enter.pts - _syncControl.videoInfo.trafficStatus.leave.pts;
        if (_playControl.status == kPlayStatusBuffering){
            GLong duration = (GLong)(GJ_Gettime()/1000) - _syncControl.lastPauseFlag;
            if (vCache < _cacheControl.lowVideoWaterFlag){
                if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
                    GJLOG(GJ_LOGINFO, "buffer percent:%f V cacheTime:%d",vCache*1.0/_cacheControl.lowVideoWaterFlag,vCache);
                    [self.delegate livePlayer:self bufferUpdatePercent:vCache*1.0/_cacheControl.lowVideoWaterFlag duration:duration];
                }
            }else{
                if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
                    GJLOG(GJ_LOGINFO, "buffer percent:%f V cacheTime:%d",1.0,vCache);
                    [self.delegate livePlayer:self bufferUpdatePercent:1.0 duration:duration];
                }
                [self stopBuffering];
            }
        }else if (_playControl.status == kPlayStatusRunning){
            if (vCache > _cacheControl.highVideoWaterFlag ) {
                if (_syncControl.speed <= 1.0) {
                    [self dewatering];
                }
            }else if (vCache < _cacheControl.lowVideoWaterFlag ){
                if (_syncControl.speed >1.0) {
                    [self stopDewatering];
                }
            }
        }
    }
}

-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(GInt64)pts{
    GJLOGFREQ("收到音频 PTS:%lld",pts);
    if (pts < _syncControl.videoInfo.trafficStatus.enter.pts) {
        pthread_mutex_lock(&_playControl.oLock);
        GInt32 length = queueGetLength(_playControl.imageQueue);
        GJLOG(GJ_LOGWARNING, "视频pts不递增，抛弃之前的视频帧：%ld帧",length);
        GJImageBuffer** imageBuffer = (GJImageBuffer**)malloc(length*sizeof(GJImageBuffer*));
        queueBroadcastPop(_playControl.imageQueue);//other lock
        if(queueClean(_playControl.imageQueue, (GHandle*)imageBuffer, &length)){
            for (GUInt32 i = 0; i<length; i++) {
                CVPixelBufferRelease(imageBuffer[i]->image);
                GJBufferPoolSetData(defauleBufferPool(), (uint8_t*)imageBuffer[i]);
            }
        }
        if (imageBuffer) {
            free(imageBuffer);
        }
        _syncControl.videoInfo.trafficStatus.leave.pts = (GLong)pts;
        pthread_mutex_unlock(&_playControl.oLock);
    }
    
    if(_playControl.status == kPlayStatusStop){
        GJLOG(GJ_LOGWARNING, "播放器stop状态收到视频帧，直接丢帧");
        return NO;
    }
    if (_playControl.playVideoThread == GNULL) {
#ifndef UIIMAGE_SHOW
        if (_imageInput == nil) {
            OSType type = CVPixelBufferGetPixelFormatType(imageData);
            _imageInput = [[GJImagePixelImageInput alloc]initWithFormat:type];
            if (_imageInput == nil) {
                GJLOG(GJ_LOGFORBID, "GJImagePixelImageInput 创建失败！");
                return NO;
            }
            [_imageInput addTarget:(GPUImageView*)_displayView];
        }
#endif
            _syncControl.videoInfo.startPts = (GLong)pts;
            _syncControl.videoInfo.trafficStatus.leave.pts = (GLong)pts;///防止videoInfo.startPts不为从0开始时，videocache过大，
      
            pthread_mutex_lock(&_playControl.oLock);
            if (_playControl.status != kPlayStatusStop) {
                pthread_create(&_playControl.playVideoThread, GNULL, playVideoRunLoop, (__bridge void *)(self));
            }
            pthread_mutex_unlock(&_playControl.oLock);
    }
    
    GJImageBuffer* imageBuffer  = (GJImageBuffer*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJImageBuffer));
    imageBuffer->image = imageData;
    imageBuffer->pts = pts;
    CVPixelBufferRetain(imageData);
    BOOL result = YES;
RETRY:
    if (queuePush(_playControl.imageQueue, imageBuffer, 0)) {
        _syncControl.videoInfo.trafficStatus.enter.pts = (GLong)imageBuffer->pts;
        _syncControl.videoInfo.trafficStatus.enter.count++;
#ifdef NETWORK_DELAY
        GUInt32 date = [[NSDate date]timeIntervalSince1970]*1000;
        _syncControl.networkDelay = date - _syncControl.videoInfo.trafficStatus.enter.pts;
#endif
        [self checkBufferingAndWater];
        result = YES;
    }else if(_playControl.status == kPlayStatusStop){
        GJLOG(GJ_LOGWARNING,"player video data push while stop,drop");
        result = NO;
    }else{
        GJLOG(GJ_LOGWARNING, "video player queue full,update oldest frame");
        GJImageBuffer* oldBuffer = GNULL;
        if (queuePop(_playControl.imageQueue, (GHandle*)&oldBuffer, 0)) {
            CVPixelBufferRelease(oldBuffer->image);
            GJBufferPoolSetData(defauleBufferPool(), (GHandle)oldBuffer);
            goto RETRY;
        }else{
            GJLOG(GJ_LOGFORBID,"full player audio queue pop error");
            CVPixelBufferRelease(imageData);
            GJBufferPoolSetData(defauleBufferPool(), (uint8_t*)imageBuffer);
            result = NO;
        }
    }
    return result;
}
#ifdef GJAUDIOQUEUEPLAY
static const GUInt32 mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
#endif
-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(GInt64)pts{
#ifdef GJAUDIOQUEUEPLAY
    if (_audioTestPlayer == nil) {
        if (_audioFormat.mFormatID <=0) {
            queueSetMinCacheSize(_playControl.audioQueue, 0);
            if (((uGInt64*)audioData->data) && 0xFFF0 != 0xFFF0) {
                NSAssert(0, @"音频格式不支持");
            }
            uint8_t* adts = audioData->data;
            uint8_t sampleIndex = adts[2] << 2;
            sampleIndex = sampleIndex>>4;
            GUInt32 sampleRate = mpeg4audio_sample_rates[sampleIndex];
            uint8_t channel = adts[2] & 0x1 <<2;
            channel += (adts[3] & 0xb0)>>6;
            _audioFormat.mChannelsPerFrame = channel;
            _audioFormat.mSampleRate = sampleRate;
            _audioFormat.mFramesPerPacket = 1024;
            _audioFormat.mFormatID = kAudioFormatMPEG4AAC;
        }

        _audioTestPlayer = [[GJAudioQueuePlayer alloc]initWithSampleRate:_audioFormat.mSampleRate channel:_audioFormat.mChannelsPerFrame formatID:_audioFormat.mFormatID];
        [_audioTestPlayer start];
    }

    [_audioTestPlayer playData:audioData packetDescriptions:nil];
    return YES;
#endif
    GJLOGFREQ("收到音频 PTS:%lld",pts);
    BOOL result = YES;
    if (pts < _syncControl.audioInfo.trafficStatus.leave.pts) {
        pthread_mutex_lock(&_playControl.oLock);
        GJLOG(GJ_LOGWARNING, "音频pts不递增，抛弃之前的音频帧：%ld帧",queueGetLength(_playControl.audioQueue));

        queueBroadcastPop(_playControl.audioQueue);//other lock
        GInt32 qLength = queueGetLength(_playControl.audioQueue);
        if(qLength > 0){
            GJAudioBuffer** audioBuffer = (GJAudioBuffer**)malloc(qLength*sizeof(GJAudioBuffer*));
            
            queueClean(_playControl.audioQueue, (GVoid**)audioBuffer, &qLength);//用clean，防止播放断同时也在读
            for (GUInt32 i = 0; i<qLength; i++) {
                _syncControl.audioInfo.trafficStatus.leave.count++;
                _syncControl.audioInfo.trafficStatus.leave.byte += audioBuffer[i]->audioData->size;
                retainBufferUnRetain(audioBuffer[i]->audioData);
                GJBufferPoolSetData(defauleBufferPool(), (uint8_t*)audioBuffer[i]);
            }
            free(audioBuffer);
        }
        _syncControl.audioInfo.trafficStatus.leave.pts = (GLong)pts;//防止此时获得audioCache时误差太大，
        pthread_mutex_unlock(&_playControl.oLock);

    }
    
    
    if (_playControl.status == kPlayStatusStop) {
        GJLOG(GJ_LOGWARNING, "播放器stop状态收到视音频，直接丢帧");
        result =  NO;
        goto END;
    }
    if (_syncControl.syncType != kTimeSYNCAudio) {
        GJLOG(GJ_LOGWARNING, "加入音频，切换到音频同步");
        changeSyncType(&_syncControl, kTimeSYNCAudio);
        _syncControl.audioInfo.trafficStatus.leave.pts = (GLong)pts;///防止audioInfo.startPts不为从0开始时，audiocache过大，
    }
    {
        //收集网络抖动
        GLong clock = GJ_Gettime()/1000;
        
    }
    if (_audioPlayer == nil) {
        _syncControl.audioInfo.startPts = (GLong)pts;
        _syncControl.audioInfo.trafficStatus.leave.pts = (GLong)pts;///防止audioInfo.startPts不为从0开始时，audiocache过大，
        //防止视频先到，导致时差特别大
        _syncControl.audioInfo.cPTS = (GLong)pts;
        _syncControl.audioInfo.clock = GJ_Gettime()/1000;
        if (_audioFormat.mFormatID != kAudioFormatLinearPCM) {
            GJLOG(GJ_LOGWARNING, "音频格式不支持");
            result =  NO;
            goto END;
        }else{
            pthread_mutex_lock(&_playControl.oLock);//此时禁止开启和停止
            if (_playControl.status != kPlayStatusStop) {
                _audioPlayer = [[GJAudioQueueDrivePlayer alloc]initWithSampleRate:_audioFormat.mSampleRate channel:_audioFormat.mChannelsPerFrame formatID:_audioFormat.mFormatID];
                _audioPlayer.delegate = self;
                [_audioPlayer start];
                _syncControl.audioInfo.startTime = GJ_Gettime()/1000.0;
            }
            pthread_mutex_unlock(&_playControl.oLock);
        }
    }
    

    
    GJAudioBuffer* audioBuffer = (GJAudioBuffer*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJAudioBuffer));
    audioBuffer->audioData = audioData;
    audioBuffer->pts = pts;
    retainBufferRetain(audioData);
RETRY:
    if(queuePush(_playControl.audioQueue, audioBuffer, 0)){
        _syncControl.audioInfo.trafficStatus.enter.pts = (GLong)audioBuffer->pts;
        _syncControl.audioInfo.trafficStatus.enter.count++;
        _syncControl.audioInfo.trafficStatus.enter.byte += audioBuffer->audioData->size;

#ifdef NETWORK_DELAY
        GUInt32 date = [[NSDate date]timeIntervalSince1970]*1000;
        _syncControl.networkDelay = date - _syncControl.audioInfo.trafficStatus.enter.pts;
#endif
        [self checkBufferingAndWater];
        result =  YES;
    }else if(_playControl.status == kPlayStatusStop){
        GJLOG(GJ_LOGWARNING,"player audio data push while stop,drop");
        retainBufferUnRetain(audioData);
        GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioBuffer);
        result = NO;
    }else{
        GJLOG(GJ_LOGWARNING, "audio player queue full,update oldest frame   ，正常情况不可能出现的case");
        GJAudioBuffer* oldBuffer = GNULL;
        if (queuePop(_playControl.audioQueue, (GHandle*)&oldBuffer, 0)) {
            retainBufferUnRetain(oldBuffer->audioData);
            GJBufferPoolSetData(defauleBufferPool(), (GHandle)oldBuffer);
            goto RETRY;
        }else{
            GJLOG(GJ_LOGFORBID,"full player audio queue pop error");
            retainBufferUnRetain(audioData);
            GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioBuffer);
            result = NO;
        }
    }
    
END:
//    {
//    GJAudioBuffer* audioBuffer ;
//    if (queuePop(_playControl.audioQueue, (GHandle*)&audioBuffer, 0)) {
//        retainBufferUnRetain(audioData);
//        GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioBuffer);
//    }
//    }
    return result;
}



-(BOOL)GJAudioQueueDrivePlayer:(GJAudioQueueDrivePlayer *)player outAudioData:(void *)data outSize:(GInt32 *)size{
    GJAudioBuffer* audioBuffer;
    if (_playControl.status == kPlayStatusRunning && queuePop(_playControl.audioQueue, (GHandle*)&audioBuffer, 0)) {
        *size = audioBuffer->audioData->size;
        memcpy(data, audioBuffer->audioData->data, *size);
        _syncControl.audioInfo.trafficStatus.leave.pts = (GLong)audioBuffer->pts;
        _syncControl.audioInfo.trafficStatus.leave.count++;
        _syncControl.audioInfo.cPTS = (GLong)audioBuffer->pts;
        _syncControl.audioInfo.clock = GJ_Gettime()/1000;
//        GJLOG(GJ_LOGDEBUG,"audio play pts:%d size:%d",_syncControl.audioInfo.cPTS,*size);
        retainBufferUnRetain(audioBuffer->audioData);
        GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioBuffer);
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
-(void)dealloc{
    GJLOG(GJ_LOGDEBUG, "GJPlivePlayer dealloc");
    queueFree(&_playControl.audioQueue);
    queueFree(&_playControl.imageQueue);
}
@end
