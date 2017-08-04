//
//  GJLivePlayer.m
//  GJCaptureTool
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLivePlayer.h"
#include "GJQueue.h"
#include "GJLog.h"
#include "GJBufferPool.h"
#include "GJUtil.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "IOS_PictureDisplay.h"
#include "IOS_AudioDrivePlayer.h"



//#define UIIMAGE_SHOW


#define VIDEO_PTS_PRECISION   600
#define AUDIO_PTS_PRECISION   100


#define UPDATE_SHAKE_TIME 10000
#define MAX_CACHE_DUR 3000  //抖动最大缓存控制
#define MIN_CACHE_DUR 200   //抖动最小缓存控制
#define MAX_CACHE_RATIO 5

#define VIDEO_MAX_CACHE_COUNT 100 //初始化缓存空间
#define AUDIO_MAX_CACHE_COUNT 200

GTime getClockLine(GJSyncControl* sync){
    if (sync->syncType == kTimeSYNCAudio) {
        GTime time = GJ_Gettime() / 1000;
        GTime  timeDiff = time - sync->audioInfo.clock;
        return sync->audioInfo.cPTS+timeDiff;
    }else{
        GTime time = GJ_Gettime() / 1000;
        GTime timeDiff = time - sync->videoInfo.startTime;
        return timeDiff + sync->videoInfo.startPts - sync->bufferInfo.bufferTotalDuration + sync->bufferInfo.speedTotalDuration;
    }
}
static void resetSyncToStartPts(GJSyncControl* sync,GTime startPts){
    sync->videoInfo.startPts = sync->audioInfo.startPts = startPts;
    sync->videoInfo.startTime = sync->audioInfo.startTime = GJ_Gettime() / 1000.0;
    sync->bufferInfo.speedTotalDuration = sync->bufferInfo.bufferTotalDuration = 0;
}
static void changeSyncType(GJSyncControl* sync,TimeSYNCType syncType){
    if (syncType == kTimeSYNCVideo) {
        sync->syncType = kTimeSYNCVideo;
        resetSyncToStartPts(sync, sync->videoInfo.cPTS);
        sync->netShake.collectStartPts = sync->videoInfo.trafficStatus.enter.ts;
    }else{
        sync->syncType = kTimeSYNCAudio;
        resetSyncToStartPts(sync, sync->audioInfo.cPTS);
        sync->netShake.collectStartPts = sync->audioInfo.trafficStatus.enter.ts;

    }
    sync->netShake.collectStartClock = GJ_Gettime()/1000;

}

static GBool GJLivePlay_StartDewatering(GJLivePlayer* player){
    //    return;
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status == kPlayStatusRunning) {
        if (player->syncControl.speed<=1.0) {
            GJLOG(GJ_LOGDEBUG, "startDewatering");
            player->syncControl.speed = 1.2;
            player->audioPlayer->audioSetSpeed(player->audioPlayer,1.2);
        }
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}
static GBool GJLivePlay_StopDewatering(GJLivePlayer* player){
    //    return;
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->syncControl.speed > 1.0) {
        GJLOG(GJ_LOGDEBUG, "stopDewatering");
        player->syncControl.speed = 1.0;
        player->audioPlayer->audioSetSpeed(player->audioPlayer,1.0);
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}
static GBool  GJLivePlay_StartBuffering(GJLivePlayer* player){
    pthread_mutex_lock(&player->playControl.oLock);
    if(player->playControl.status == kPlayStatusRunning){
        GJLOG(GJ_LOGDEBUG, "start buffing");
        player->playControl.status = kPlayStatusBuffering;
        player->playControl.videoQueueWaitTime = GINT32_MAX;
        player->syncControl.bufferInfo.lastPauseFlag = GJ_Gettime() / 1000;
        player->audioPlayer->audioPause(player->audioPlayer);
        
        player->callback(player->userDate,GJPlayMessage_BufferStart,GNULL);
        queueSetMinCacheSize(player->playControl.imageQueue, VIDEO_MAX_CACHE_COUNT);
        queueSetMinCacheSize(player->playControl.audioQueue, AUDIO_MAX_CACHE_COUNT);
    }else{
        GJLOG(GJ_LOGDEBUG, "buffer when status not in running");
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}
static GVoid  GJLivePlay_StopBuffering(GJLivePlayer* player){
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status == kPlayStatusBuffering) {
        player->playControl.status = kPlayStatusRunning;
        queueSetMinCacheSize(player->playControl.imageQueue, 0);
        queueBroadcastPop(player->playControl.imageQueue);
        queueSetMinCacheSize(player->playControl.audioQueue, 0);
        queueBroadcastPop(player->playControl.audioQueue);
        if (player->syncControl.bufferInfo.lastPauseFlag != 0) {
            player->syncControl.bufferInfo.lastBufferDuration = GJ_Gettime() / 1000 - player->syncControl.bufferInfo.lastPauseFlag;
            player->syncControl.bufferInfo.bufferTotalDuration += player->syncControl.bufferInfo.lastBufferDuration;
            player->syncControl.bufferInfo.bufferTimes++;
            player->syncControl.bufferInfo.lastPauseFlag = 0;
        }else{
            GJLOG(GJ_LOGFORBID, "暂停管理出现问题");
        }
        player->syncControl.videoInfo.clock = player->syncControl.audioInfo.clock = GJ_Gettime()/1000;
        player->audioPlayer->audioResume(player->audioPlayer);
        GJLOG(GJ_LOGINFO, "buffing times:%d useDuring:%d",player->syncControl.bufferInfo.bufferTimes,player->syncControl.bufferInfo.lastBufferDuration);
    }else{
        GJLOG(GJ_LOGDEBUG, "stopBuffering when status not buffering");
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    
}
GVoid GJLivePlay_CheckNetShake(GJSyncControl* _syncControl,GTime pts){
   
    GTime clock = GJ_Gettime()/1000;
    SyncInfo* syncInfo = &_syncControl->audioInfo;
    GJNetShakeInfo* netShake = &_syncControl->netShake;
    if (_syncControl->syncType == kTimeSYNCVideo) {
        syncInfo = &_syncControl->videoInfo;
    }
//    GTime shake =  -(pts - netShake->collectStartPts - clock + netShake->collectStartClock);
    
    GTime shake =  (clock - netShake->collectStartClock) - (pts - netShake->collectStartPts);//统计少发的抖动

//    GJLOG(GJ_LOGINFO, "setLowshake:%lld,max:%lld ,preMax:%lld",shake,netShake->maxDownShake,netShake->preMaxDownShake);
    if (shake > netShake->maxDownShake) {
        netShake->maxDownShake = shake;
//        GJLOG(GJ_LOGINFO, "setLowMaxDownShake:%lld",netShake->maxDownShake);
        if (shake > netShake->preMaxDownShake) {
            if ( shake > MAX_CACHE_DUR) {
                shake = MAX_CACHE_DUR;
            }else if (shake < MIN_CACHE_DUR){
                shake = MIN_CACHE_DUR;
            }
            _syncControl->bufferInfo.lowWaterFlag = shake;
            _syncControl->bufferInfo.highWaterFlag = _syncControl->bufferInfo.lowWaterFlag*MAX_CACHE_RATIO;
            GJLOG(GJ_LOGINFO, "setLowWater:%lld,hightWater:%d，max:%lld ,preMax:%lld",_syncControl->bufferInfo.lowWaterFlag,_syncControl->bufferInfo.highWaterFlag,netShake->maxDownShake,netShake->preMaxDownShake);
        }
    }
    if (clock - netShake->collectStartClock >= UPDATE_SHAKE_TIME) {
        netShake->preMaxDownShake = netShake->maxDownShake;
        netShake->maxDownShake = 0;
        netShake->collectStartClock = clock;
        netShake->collectStartPts = pts;
        GJLOG(GJ_LOGINFO, "更新网络抖动收集");
    }
}
//GVoid GJLivePlay_CheckNetShake(GJSyncControl* _syncControl,GTime pts){
////   typedef struct _GJNetShakeInfo{
////    GTime collectStartClock;
////    GTime preCollectClock;
////    GTime preCollectPts;
////    GTime preUpShake;
////    GTime preDownShake;
////    GTime upShake;
////    GTime downShake;
////    }GJNetShakeInfo;
//    GTime clock = GJ_Gettime()/1000;
//    SyncInfo* syncInfo = &_syncControl->audioInfo;
//    GJNetShakeInfo* netShake = &_syncControl->netShake;
//    if (_syncControl->syncType == kTimeSYNCVideo) {
//        syncInfo = &_syncControl->videoInfo;
//    }
//    
//    GTime unitClockDif = clock - netShake->preCollectClock;
//    GTime unitPtsDif = (pts - syncInfo->trafficStatus.enter.ts);
//    GTime currentShake = unitPtsDif - unitClockDif;
//    if(currentShake < 0) {
//        netShake->downShake += currentShake;
//        GTime totalShake = netShake->preUpShake + netShake->preDownShake + netShake->upShake+netShake->downShake;
//        if (-totalShake > _syncControl->bufferInfo.lowWaterFlag) {
//            _syncControl->bufferInfo.lowWaterFlag = GMAX(-totalShake,MIN_CACHE_DUR);
//            _syncControl->bufferInfo.highWaterFlag = GMAX(netShake->preDownShake+netShake->downShake, MAX_CACHE_DUR);
//        }
//    }else{
//        netShake->upShake += currentShake;
//        GTime totalShake = netShake->preUpShake + netShake->preDownShake + netShake->upShake+netShake->downShake;
//        _syncControl->bufferInfo.lowWaterFlag = GMAX(-totalShake,MIN_CACHE_DUR);
//    }
//    GJLOG(GJ_LOGINFO, "setLowWater:%d,hightWater:%d",_syncControl->bufferInfo.lowWaterFlag,_syncControl->bufferInfo.highWaterFlag);
//    netShake->preCollectClock = clock;
//    netShake->preCollectPts = pts;
//    if (clock - netShake->collectStartClock >= UPDATE_SHAKE_TIME) {
//        netShake->preDownShake = netShake->downShake;
//        netShake->preUpShake = netShake->upShake;
//        netShake->downShake = 0;
//        netShake->upShake = 0;
//        netShake->collectStartClock = clock;
//        GJLOG(GJ_LOGINFO, "更新网络抖动收集");
//    }
//}
//GVoid GJLivePlay_CheckNetShake(GJSyncControl* _syncControl,GTime pts){
////    typedef struct _GJNetShakeInfo{
////        GTime collectStartClock;
////        GTime collectUnitStartClock;
////        GTime collectUnitEndClock;
////        GTime collectUnitPtsCache;
////        GTime preUnitMaxShake;
////        GTime preUnitMinShake;
////        
////        GTime maxShake;
////        GTime minShake;
////    }GJNetShakeInfo;
//    //收集网络抖动
//    GTime clock = GJ_Gettime()/1000;
//    SyncInfo* syncInfo = &_syncControl->audioInfo;
//    if (_syncControl->syncType == kTimeSYNCVideo) {
//        syncInfo = &_syncControl->videoInfo;
//    }
//    GTime unitClockDif = clock - _syncControl->netShake.collectUnitEndClock;
//    GTime unitPtsDif = (pts - syncInfo->trafficStatus.enter.ts);
//    GTime preShake = _syncControl->netShake.collectUnitPtsCache - _syncControl->netShake.collectUnitEndClock + _syncControl->netShake.collectUnitStartClock;
//    GTime currentShake = unitPtsDif - unitClockDif;
//    if ((currentShake >= -10.0 && preShake >= -10.0) || (currentShake <= 10.0 && preShake <= 10.0)) {
//        _syncControl->netShake.collectUnitEndClock = clock;
//        _syncControl->netShake.collectUnitPtsCache += unitPtsDif;
//    }else{
//        GTime unitShake = -preShake;
//        if (_syncControl->netShake.maxDownShake > unitShake){
//            _syncControl->netShake.maxDownShake = unitShake;
//            unitShake = GMAX(unitShake, _syncControl->netShake.preUnitMaxDownShake);
//            _syncControl->bufferInfo.lowWaterFlag = GMAX(MIN_CACHE_DUR,unitShake);
//             
//            GJLOG(GJ_LOGINFO, "preShake:%d,currentShake:%d,totalShake:%d,重置lowWaterFlag：%d，highWaterFlag：%d",preShake,currentShake,totalShake,_syncControl->bufferInfo.lowWaterFlag,_syncControl->bufferInfo.highWaterFlag);
//            
//            if (_syncControl->bufferInfo.lowWaterFlag > _syncControl->bufferInfo.highWaterFlag) {
//                GJLOG(GJ_LOGFORBID, "lowAudioWaterFlag 大于 highAudioWaterFlag怎么可能！！！");
//                _syncControl->bufferInfo.highWaterFlag = _syncControl->bufferInfo.lowWaterFlag;
//            }
//        }else{
//            GJLOGFREQ("pull net shake:%d,but not affect",totalShake);
//        }
//        _syncControl->netShake.collectUnitStartClock = _syncControl->netShake.collectUnitEndClock;
//        _syncControl->netShake.collectUnitEndClock = clock;
//        _syncControl->netShake.collectUnitPtsCache = unitPtsDif;
//        
//        if (clock - _syncControl->netShake.collectStartClock >= UPDATE_SHAKE_TIME) {
//            _syncControl->netShake.preUnitMaxShake = _syncControl->netShake.maxShake;
//            _syncControl->netShake.preUnitMinShake = _syncControl->netShake.minShake;
//            _syncControl->netShake.minShake = -MIN_CACHE_DUR;
//            _syncControl->netShake.maxShake = MAX_CACHE_DUR;
//            _syncControl->netShake.collectStartClock = _syncControl->netShake.collectUnitStartClock;
//            GJLOG(GJ_LOGINFO, "更新网络抖动收集 startClock:%d",_syncControl->netShake.collectStartClock);
//        }
//    }
//}
GVoid GJLivePlay_CheckWater(GJLivePlayer* player){

    GJPlayControl* _playControl = &player->playControl;
    GJSyncControl* _syncControl = &player->syncControl;
    GLong cache;
    if (_playControl->status == kPlayStatusBuffering) {
        UnitBufferInfo bufferInfo;
        if(_syncControl->syncType == kTimeSYNCAudio){
            GLong vCache = _syncControl->videoInfo.trafficStatus.enter.ts - _syncControl->videoInfo.trafficStatus.leave.ts;
            GLong aCache = _syncControl->audioInfo.trafficStatus.enter.ts - _syncControl->audioInfo.trafficStatus.leave.ts;
            bufferInfo.cacheCount = _syncControl->audioInfo.trafficStatus.enter.count - _syncControl->audioInfo.trafficStatus.leave.count;
            cache = aCache;
            if ((aCache == 0 && vCache >= _syncControl->bufferInfo.lowWaterFlag) || //音频没有了，视频足够
                vCache >= _syncControl->bufferInfo.highWaterFlag-300) {//音频缓冲了一部分后音频消失
                GJLOG(GJ_LOGWARNING, "等待音频缓冲过程中，音频为空视频足够、或者视频足够大于音频。切换到视频同步");
                player->playControl.videoQueueWaitTime = 0;
                GJLivePlay_StopBuffering(player);
                changeSyncType(_syncControl, kTimeSYNCVideo);
                return;
            }
#ifdef SHOULD_BUFFER_VIDEO_IN_AUDIO_CLOCK
            //音频等待缓冲视频
            else if((vCache == 0 && aCache >= _syncControl->bufferInfo.lowWaterFlag) || vCache >= _syncControl->bufferInfo.highWaterFlag-300){
                GJLOG(GJ_LOGWARNING, "等待视频缓冲过程中，视频为空音频足够、或者音频足够大于音频。停止视频等待");
                player->playControl.videoQueueWaitTime = GINT32_MAX;
                GJLivePlay_StopBuffering(player);
                return;
            }
#endif
        }else{
            cache = _syncControl->videoInfo.trafficStatus.enter.ts - _syncControl->videoInfo.trafficStatus.leave.ts;
            bufferInfo.cacheCount = _syncControl->audioInfo.trafficStatus.enter.count - _syncControl->audioInfo.trafficStatus.leave.count;
        }
        GLong duration = (GLong)(GJ_Gettime()/1000 - _syncControl->bufferInfo.lastPauseFlag);
        bufferInfo.bufferDur = duration;
        bufferInfo.cachePts = cache;
        bufferInfo.percent = cache*1.0/_syncControl->bufferInfo.lowWaterFlag;
        
        if (cache < _syncControl->bufferInfo.lowWaterFlag){
            player->callback(player->userDate,GJPlayMessage_BufferUpdate,&bufferInfo);
        }else{
            GJLOG(GJ_LOGDEBUG, "缓冲结束");
            player->callback(player->userDate,GJPlayMessage_BufferUpdate,&bufferInfo);
            player->callback(player->userDate,GJPlayMessage_BufferEnd,&bufferInfo);
            player->playControl.videoQueueWaitTime = 0;
            GJLivePlay_StopBuffering(player);
        }
    }else if (_playControl->status == kPlayStatusRunning){
        if(_syncControl->syncType == kTimeSYNCAudio){
            cache = _syncControl->audioInfo.trafficStatus.enter.ts - _syncControl->audioInfo.trafficStatus.leave.ts;
        }else{
            cache = _syncControl->videoInfo.trafficStatus.enter.ts - _syncControl->videoInfo.trafficStatus.leave.ts;
        }
        if (cache > _syncControl->bufferInfo.highWaterFlag ) {
            if (_syncControl->speed <= 1.0) {
                GJLivePlay_StartDewatering(player);
            }
        }else if (cache < _syncControl->bufferInfo.lowWaterFlag ){
            if (_syncControl->speed >1.0) {
                GJLivePlay_StopDewatering(player);
            }
        }
    }
}
GBool GJAudioDrivePlayerCallback(GHandle player,void *data ,GInt32* outSize){
    
    GJPlayControl* _playControl = &((GJLivePlayer*)player)->playControl;
    GJSyncControl* _syncControl = &((GJLivePlayer*)player)->syncControl;
    
    R_GJPCMFrame* audioBuffer;
    if (_playControl->status == kPlayStatusRunning && queuePop(_playControl->audioQueue, (GHandle*)&audioBuffer, 0)) {
        
        *outSize = audioBuffer->retain.size;
        memcpy(data, audioBuffer->retain.data, *outSize);
        _syncControl->audioInfo.trafficStatus.leave.ts = (GLong)audioBuffer->pts;
        _syncControl->audioInfo.trafficStatus.leave.count++;
        _syncControl->audioInfo.cPTS = (GLong)audioBuffer->pts;
        _syncControl->audioInfo.clock = GJ_Gettime()/1000;
        GJLOGFREQ("audio show pts:%d",audioBuffer->pts);
        retainBufferUnRetain(&audioBuffer->retain);
        return GTrue;
    }else{
        if (_playControl->status == kPlayStatusRunning) {
            GJLOG(GJ_LOGDEBUG, "audio player queue empty");
            if (_syncControl->syncType == kTimeSYNCAudio) {
                GJLivePlay_StartBuffering(player);
            }
        }
        return GFalse;
    }
}
static GHandle GJLivePlay_VideoRunLoop(GHandle parm){
    pthread_setname_np("playVideoRunLoop");
    GJLivePlayer* player = parm;
    GJPlayControl* _playControl = &(player->playControl);
    GJSyncControl* _syncControl = &(player->syncControl);
    R_GJPixelFrame* cImageBuf;
    
    cImageBuf = GNULL;
    
    GJLOG(GJ_LOGDEBUG, "start play runloop");

    R_GJPixelFrame watiBuffer[2] = {0};
    
    if (_playControl->status == kPlayStatusStop) {
        goto END;
    }
    queuePeekWaitValue(_playControl->imageQueue, 2, (GHandle*)&watiBuffer, 100);///等待至少两帧
    _syncControl->videoInfo.startTime = GJ_Gettime() / 1000;
    
    while ((_playControl->status != kPlayStatusStop)) {
        
        if (queuePop(_playControl->imageQueue, (GHandle*)&cImageBuf,player->playControl.videoQueueWaitTime)) {
            
            if (_playControl->status == kPlayStatusStop){
                retainBufferUnRetain(&cImageBuf->retain);
                cImageBuf = GNULL;
                break;
            }
            
        }else{
            
            if (_playControl->status == kPlayStatusStop) {
                break;
            }else if (_playControl->status == kPlayStatusRunning){
                
                if(_syncControl->syncType == kTimeSYNCVideo){
                    GJLOG(GJ_LOGDEBUG, "video play queue empty when kTimeSYNCVideo,start buffer");
                    GJLivePlay_StartBuffering(player);
                }else{
#ifdef SHOULD_BUFFER_VIDEO_IN_AUDIO_CLOCK
                    if (_playControl->videoQueueWaitTime < 10) {//_playControl->videoQueueWaitTime <= 10 表示不等待，但是没有数据了，所以需要缓冲
                        GJLOG(GJ_LOGDEBUG, "video play queue empty when kTimeSYNCAudio,start buffer");
                        GJLivePlay_StartBuffering(player);
                    }
#else
                    GJLOG(GJ_LOGALL, "video play queue empty when kTimeSYNCAudio,do not buffer");
                    usleep(10*1000);
#endif
                }
            }
            continue;
        }
        
        GTime timeStandards = getClockLine(_syncControl);
        GTime delay = (GLong)cImageBuf->pts - timeStandards;
        
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
                R_GJPixelFrame nextBuffer = {0};
                GBool peekResult = GFalse;
                while ((peekResult = queuePeekWaitCopyValue(_playControl->imageQueue, 0, (GHandle)&nextBuffer, sizeof(R_GJPixelFrame), VIDEO_PTS_PRECISION))) {
                    if (_playControl->status == kPlayStatusStop) {
                        goto DROP;
                    }
                    if(nextBuffer.pts < cImageBuf->pts){
                        GJLOG(GJ_LOGWARNING, "视频PTS重新开始，直接显示");
                        delay = 0;
                        break;
                    }else{
                        timeStandards = getClockLine(_syncControl);
                        delay = (GLong)cImageBuf->pts - timeStandards;
                        
                        if (delay > 30 * 1000) {
                            usleep(30 * 1000);
                        }else{
                            GJLOG(GJ_LOGWARNING, "视频长时间等待音频结束");
                            break;
                        }
                    }
                }
                
                if (!peekResult) {
                    GJLOG(GJ_LOGWARNING, "视频等待音频时间过长,并且没有下一帧，直接显示");
                    delay = 0;
                    goto DROP;
                }
            }
        }else if (delay < -VIDEO_PTS_PRECISION){
            
            if(_syncControl->syncType == kTimeSYNCVideo){
                GJLOG(GJ_LOGWARNING, "视频落后视频严重，delay：%ld, PTS:%ld clock:%ld，重置同步管理",delay,cImageBuf->pts,timeStandards);
                resetSyncToStartPts(_syncControl, (GLong)cImageBuf->pts);
                delay = 0;
            }else{
                GJLOG(GJ_LOGWARNING, "视频落后音频严重，delay：%ld, PTS:%ld clock:%ld，丢视频帧",delay,cImageBuf->pts,timeStandards);
                _syncControl->videoInfo.cPTS = (GLong)cImageBuf->pts;
                _syncControl->videoInfo.trafficStatus.leave.ts = (GLong)cImageBuf->pts;
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
            _syncControl->bufferInfo.speedTotalDuration += (_syncControl->speed - 1.0)*(GJ_Gettime() / 1000.0-_syncControl->videoInfo.clock);
        }
        
        _syncControl->videoInfo.clock = GJ_Gettime() / 1000;
        _syncControl->videoInfo.trafficStatus.leave.ts = (GLong)cImageBuf->pts;
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
        
        GJLOGFREQ("video show pts:%d",cImageBuf->pts);
        player->videoPlayer->displayView(player->videoPlayer,&cImageBuf->retain);
#endif
        
    DROP:
        _syncControl->videoInfo.trafficStatus.leave.count++;
        retainBufferUnRetain(&cImageBuf->retain);
        cImageBuf = GNULL;
    }
    
END:
    GJLOG(GJ_LOGINFO, "playRunLoop out");
    _playControl->status = kPlayStatusStop;
    _playControl->playVideoThread = nil;
    return GNULL;
}


//GBool  GJLivePlay_InjectVideoPlayer(GJLivePlayer* player,const GJPictureDisplayContext* videoPlayer){
//    player->videoPlayer = *videoPlayer;
//    return GTrue;
//}
//GBool  GJLivePlay_InjectAudioPlayer(GJLivePlayer* player,const GJAudioPlayContext* audioPlayer,GJAudioFormat format){
//    player->audioPlayer = *audioPlayer;
//    player->audioFormat = format;
//    return GTrue;
//}

GBool  GJLivePlay_Create(GJLivePlayer** liveplayer,GJLivePlayCallback callback,GHandle userData){
    
    if (*liveplayer == GNULL) {
        *liveplayer = (GJLivePlayer*)calloc(1,sizeof(GJLivePlayer));
    }
    
    GJLivePlayer* player = *liveplayer;
    GJ_PictureDisplayContextCreate(&player->videoPlayer);
    player->videoPlayer->displaySetup(player->videoPlayer);
    GJ_AudioPlayContextCreate(&player->audioPlayer);
    player->callback = callback;
    player->userDate = userData;
    player->playControl.status = kPlayStatusStop;
    pthread_mutex_init(&player->playControl.oLock, GNULL);
    queueCreate(&player->playControl.imageQueue, VIDEO_MAX_CACHE_COUNT, GTrue, GTrue);//150为暂停时视频最大缓冲
    queueCreate(&player->playControl.audioQueue, AUDIO_MAX_CACHE_COUNT, GTrue, GTrue);
    
    return GTrue;
}
GVoid  GJLivePlay_SetAudioFormat(GJLivePlayer* player,GJAudioFormat audioFormat){
    
    player->audioFormat = audioFormat;
    
}
GVoid  GJLivePlay_SetVideoFormat(GJLivePlayer* player,GJPixelType audioFormat){
    
    player->videoPlayer->displaySetFormat(player->videoPlayer,audioFormat);
    
}
GBool  GJLivePlay_Start(GJLivePlayer* player){
    GBool result = GTrue;
    pthread_mutex_lock(&player->playControl.oLock);
    
    if (player->playControl.status != kPlayStatusRunning) {
        GJLOG(GJ_LOGINFO, "GJLivePlayer start");
        memset(&player->syncControl, 0, sizeof(player->syncControl));
        player->playControl.status = kPlayStatusRunning;
        player->syncControl.videoInfo.startPts = player->syncControl.audioInfo.startPts = G_TIME_INVALID;
        player->syncControl.videoInfo.inDtsSeries = -GINT32_MAX;
        player->syncControl.audioInfo.inDtsSeries = -GINT32_MAX;

        player->syncControl.speed = 1.0;
        player->syncControl.bufferInfo.lowWaterFlag = MIN_CACHE_DUR;
        player->syncControl.bufferInfo.highWaterFlag = MAX_CACHE_DUR;
        
        player->syncControl.netShake.preMaxDownShake = MIN_CACHE_DUR;
        player->syncControl.netShake.maxDownShake = MIN_CACHE_DUR;

        changeSyncType(&player->syncControl, kTimeSYNCVideo);
        queueEnablePush(player->playControl.imageQueue, GTrue);
        queueEnablePush(player->playControl.audioQueue, GTrue);
    }else{
        GJLOG(GJ_LOGWARNING, "GJLivePlayer 重复 start");
    }
    
    pthread_mutex_unlock(&player->playControl.oLock);
    return result;
}
GVoid  GJLivePlay_Stop(GJLivePlayer* player){
    GJLivePlay_StopBuffering(player);
    
    if(player->playControl.status != kPlayStatusStop){
        GJLOG(GJ_LOGINFO, "gjliveplayer stop start");
        pthread_mutex_lock(&player->playControl.oLock);
        player->playControl.status = kPlayStatusStop;
        queueEnablePush(player->playControl.audioQueue, GFalse);
        queueEnablePush(player->playControl.imageQueue, GFalse);
        
        queueBroadcastPop(player->playControl.imageQueue);
        queueBroadcastPop(player->playControl.audioQueue);
        pthread_mutex_unlock(&player->playControl.oLock);
        
        pthread_join(player->playControl.playVideoThread, GNULL);
        
        pthread_mutex_lock(&player->playControl.oLock);
        player->audioPlayer->audioStop(player->audioPlayer);
        player->audioPlayer->audioPlayUnSetup(player->audioPlayer);
        GInt32 vlength = queueGetLength(player->playControl.imageQueue);
        GInt32 alength = queueGetLength(player->playControl.audioQueue);
        
        if (vlength > 0) {
            R_GJPixelFrame** imageBuffer = (R_GJPixelFrame**)malloc(sizeof(R_GJPixelFrame*)*vlength);
            //不能用queuePop，因为已经enable false;
            if (queueClean(player->playControl.imageQueue, (GHandle*)imageBuffer, &vlength)) {
                for (GInt32 i = 0; i < vlength; i++) {
                    retainBufferUnRetain(&imageBuffer[i]->retain);
                }
            }else{
                GJLOG(GJ_LOGFORBID, "videoClean Error");
            }
            free(imageBuffer);
        }

        for (int i =  player->sortIndex-1 ; i >= 0; i--) {
            R_GJPixelFrame* pixelFrame = player->sortQueue[i];
            retainBufferUnRetain(&pixelFrame->retain);
        }
        player->sortIndex = 0;
        
        GJLOG(GJ_LOGDEBUG, "video player queue clean over");
        
        if (alength > 0) {
            R_GJPCMFrame** audioBuffer = (R_GJPCMFrame**)malloc(sizeof(R_GJPCMFrame*)*alength);
            
            if (queueClean(player->playControl.audioQueue, (GHandle*)audioBuffer, &alength)) {
                for (GInt32 i = 0; i < alength; i++) {
                    retainBufferUnRetain(&audioBuffer[i]->retain);
                }
            }else{
                GJLOG(GJ_LOGFORBID, "audioClean Error");
            }
            
            free(audioBuffer);
        }
        
        
        GJLOG(GJ_LOGDEBUG, "audio player queue clean over");
        pthread_mutex_unlock(&player->playControl.oLock);
        
    }else{
        GJLOG(GJ_LOGWARNING, "重复停止");
    }
}
inline static GBool  _internal_AddVideoData(GJLivePlayer* player,R_GJPixelFrame* videoFrame){
    GJLivePlay_CheckNetShake(&player->syncControl, videoFrame->pts);
//    printf("add play video pts:%lld\n",videoFrame->pts);
    if (player->playControl.playVideoThread == GNULL) {
        
        player->syncControl.videoInfo.startPts = (GLong)videoFrame->pts;
        player->syncControl.videoInfo.trafficStatus.leave.ts = (GLong)videoFrame->pts;///防止videoInfo.startPts不为从0开始时，videocache过大，
        
        pthread_mutex_lock(&player->playControl.oLock);
        
        if (player->playControl.status != kPlayStatusStop) {
            pthread_create(&player->playControl.playVideoThread, GNULL, GJLivePlay_VideoRunLoop,player);
        }
        
        pthread_mutex_unlock(&player->playControl.oLock);
    }
    
    retainBufferRetain(&videoFrame->retain);
    GBool result = GTrue;
    
RETRY:
    if (queuePush(player->playControl.imageQueue, videoFrame, 0)) {
        player->syncControl.videoInfo.trafficStatus.enter.ts = (GLong)videoFrame->pts;
        player->syncControl.videoInfo.trafficStatus.enter.count++;
#ifdef NETWORK_DELAY
        GUInt32 date = [[NSDate date]timeIntervalSince1970]*1000;
        player->syncControl.networkDelay = date - player->syncControl.videoInfo.trafficStatus.enter.ts;
#endif
        GJLivePlay_CheckWater(player);
        result = GTrue;
        
    }else if(player->playControl.status == kPlayStatusStop){
        
        GJLOG(GJ_LOGWARNING,"player video data push while stop,drop");
        result = GFalse;
        
    }else{
        
        GJLOG(GJ_LOGWARNING, "video player queue full,update oldest frame");
        R_GJPixelFrame* oldBuffer = GNULL;
        
        if (queuePop(player->playControl.imageQueue, (GHandle*)&oldBuffer, 0)) {
            
            retainBufferUnRetain(&oldBuffer->retain);
            goto RETRY;
            
        }else{
            
            GJLOG(GJ_LOGFORBID,"full player audio queue pop error");
            retainBufferUnRetain(&videoFrame->retain);
            result = GFalse;
            
        }
        
    }
    return result;
}
GBool  GJLivePlay_AddVideoData(GJLivePlayer* player,R_GJPixelFrame* videoFrame){

//    printf("收到视频 PTS:%lld\n",videoFrame->pts);

//    printf("PTS:%lld\n",videoFrame->pts);
    if (videoFrame->dts < player->syncControl.videoInfo.inDtsSeries) {
        
        pthread_mutex_lock(&player->playControl.oLock);
        GInt32 length = queueGetLength(player->playControl.imageQueue);
        GJLOG(GJ_LOGWARNING, "视频dts不递增，抛弃之前的视频帧：%ld帧",length);
        R_GJPixelFrame** imageBuffer = (R_GJPixelFrame**)malloc(length*sizeof(R_GJPixelFrame*));
        queueBroadcastPop(player->playControl.imageQueue);//other lock
        
        if(queueClean(player->playControl.imageQueue, (GHandle*)imageBuffer, &length)){
            for (GUInt32 i = 0; i<length; i++) {
                retainBufferUnRetain(&imageBuffer[i]->retain);
            }
        }
        
        if (imageBuffer) {
            free(imageBuffer);
        }

        for (int i =  player->sortIndex-1 ; i >= 0; i--) {
            R_GJPixelFrame* pixelFrame = player->sortQueue[i];
            retainBufferUnRetain(&pixelFrame->retain);
        }
        player->sortIndex = 0;
        
        player->syncControl.videoInfo.trafficStatus.leave.ts = (GLong)videoFrame->pts;
        player->syncControl.videoInfo.inDtsSeries = -GINT32_MAX;
        pthread_mutex_unlock(&player->playControl.oLock);
    }
    
    if(player->playControl.status == kPlayStatusStop){
        GJLOG(GJ_LOGWARNING, "播放器stop状态收到视频帧，直接丢帧");
        return GFalse;
    }
    player->syncControl.videoInfo.inDtsSeries = (GLong)videoFrame->dts;

    if (player->sortIndex <= 0 || player->sortQueue[player->sortIndex-1]->pts > videoFrame->pts) {
        player->sortQueue[player->sortIndex++] = videoFrame;
        retainBufferRetain(&videoFrame->retain);
        return GTrue;
    }
    for (int i =  player->sortIndex-1 ; i >= 0; i--) {
        R_GJPixelFrame* pixelFrame = player->sortQueue[i];
        GBool ret = _internal_AddVideoData(player, pixelFrame);
        retainBufferUnRetain(&pixelFrame->retain);
        if (!ret) {
            return GFalse;
        }
    }
    
    player->sortIndex = 1;
    player->sortQueue[0] = videoFrame;
    retainBufferRetain(&videoFrame->retain);
    return GTrue;
}
GBool  GJLivePlay_AddAudioData(GJLivePlayer* player,R_GJPCMFrame* audioFrame){
    
    GJLOGFREQ("收到音频 PTS:%lld",audioFrame->pts);
    GJPlayControl* _playControl = &(player->playControl);
    GJSyncControl* _syncControl = &(player->syncControl);
    GBool result = GTrue;
    GJAssert(audioFrame->retain.size, "size 不能为0");

    if (audioFrame->dts < _syncControl->audioInfo.inDtsSeries) {
        
        pthread_mutex_lock(&_playControl->oLock);
        GJLOG(GJ_LOGWARNING, "音频dts不递增，抛弃之前的音频帧：%ld帧",queueGetLength(_playControl->audioQueue));
        
        queueBroadcastPop(_playControl->audioQueue);//other lock
        GInt32 qLength = queueGetLength(_playControl->audioQueue);
        
        if(qLength > 0){
            R_GJPCMFrame** audioBuffer = (R_GJPCMFrame**)malloc(qLength*sizeof(R_GJPCMFrame*));
            queueClean(_playControl->audioQueue, (GVoid**)audioBuffer, &qLength);//用clean，防止播放断同时也在读
            for (GUInt32 i = 0; i<qLength; i++) {
                _syncControl->audioInfo.trafficStatus.leave.count++;
                _syncControl->audioInfo.trafficStatus.leave.byte += audioBuffer[i]->retain.size;
                retainBufferUnRetain(&audioBuffer[i]->retain);
            }
            free(audioBuffer);
        }
        
        _syncControl->audioInfo.inDtsSeries = -GINT32_MAX;
        _syncControl->audioInfo.trafficStatus.leave.ts = (GLong)audioFrame->pts;//防止此时获得audioCache时误差太大，
        _syncControl->audioInfo.cPTS = (GLong)audioFrame->pts;//防止pts重新开始时，视频远落后音频
        _syncControl->audioInfo.clock = GJ_Gettime()/1000;
        pthread_mutex_unlock(&_playControl->oLock);
    }
    
    if (_playControl->status == kPlayStatusStop) {
        GJLOG(GJ_LOGWARNING, "播放器stop状态收到视音频，直接丢帧");
        result =  GFalse;
        goto END;
    }
    
    if (_syncControl->syncType != kTimeSYNCAudio) {
        GJLOG(GJ_LOGWARNING, "加入音频，切换到音频同步");
        
///<fix -2017. 7.26  //not stop buffer ,contion buffer to low water;
//        if (_playControl->status == kPlayStatusBuffering) {
//            GJLivePlay_StopBuffering(player);
//        }
        changeSyncType(_syncControl, kTimeSYNCAudio);
        _syncControl->audioInfo.trafficStatus.leave.ts = (GLong)audioFrame->pts;///防止audioInfo.startPts不为从0开始时，audiocache过大，
    }
    
    GJLivePlay_CheckNetShake(&player->syncControl, audioFrame->pts);
    
    if (player->audioPlayer->obaque == GNULL) {
        _syncControl->audioInfo.startPts = (GLong)audioFrame->pts;
        _syncControl->audioInfo.trafficStatus.leave.ts = (GLong)audioFrame->pts;///防止audioInfo.startPts不为从0开始时，audiocache过大，
        //防止视频先到，导致时差特别大
        _syncControl->audioInfo.cPTS = (GLong)audioFrame->pts;
        _syncControl->audioInfo.clock = GJ_Gettime()/1000;
        pthread_mutex_lock(&_playControl->oLock);//此时禁止开启和停止
        
        if (_playControl->status != kPlayStatusStop) {
            player->audioPlayer->audioPlaySetup(player->audioPlayer,player->audioFormat,GJAudioDrivePlayerCallback,player);
            player->audioPlayer->audioStart(player->audioPlayer);
            _syncControl->audioInfo.startTime = GJ_Gettime()/1000.0;
        }
        
        pthread_mutex_unlock(&_playControl->oLock);
    }
    
    retainBufferRetain(&audioFrame->retain);
    
RETRY:
    if(queuePush(_playControl->audioQueue, audioFrame, 0)){
        _syncControl->audioInfo.inDtsSeries = (GLong)audioFrame->dts;
        _syncControl->audioInfo.trafficStatus.enter.ts = (GLong)audioFrame->pts;
        _syncControl->audioInfo.trafficStatus.enter.count++;
        _syncControl->audioInfo.trafficStatus.enter.byte += audioFrame->retain.size;
        
#ifdef NETWORK_DELAY
        GUInt32 date = [[NSDate date]timeIntervalSince1970]*1000;
        _syncControl.networkDelay = date - _syncControl.audioInfo.trafficStatus.enter.ts;
#endif
        GJLivePlay_CheckWater(player);
        result =  GTrue;
        
    }else if(_playControl->status == kPlayStatusStop){
        
        GJLOG(GJ_LOGWARNING,"player audio data push while stop,drop");
        retainBufferUnRetain(&audioFrame->retain);
        result = GFalse;
        
    }else{
        
        GJLOG(GJ_LOGWARNING, "audio player queue full,update oldest frame   ，正常情况不可能出现的case");
        R_GJPCMFrame* oldBuffer = GNULL;
        if (queuePop(_playControl->audioQueue, (GHandle*)&oldBuffer, 0)) {
            retainBufferUnRetain(&oldBuffer->retain);
            goto RETRY;
        }else{
            GJLOG(GJ_LOGFORBID,"full player audio queue pop error");
            retainBufferUnRetain(&audioFrame->retain);
            result = GFalse;
        }
    }
    
END:
    return result;
}
GJTrafficStatus  GJLivePlay_GetVideoCacheInfo(GJLivePlayer* player){
    return player->syncControl.videoInfo.trafficStatus;
}
GJTrafficStatus  GJLivePlay_GetAudioCacheInfo(GJLivePlayer* player){
    return player->syncControl.audioInfo.trafficStatus;
}

GHandle  GJLivePlay_GetVideoDisplayView(GJLivePlayer* player){
    return player->videoPlayer->getDispayView(player->videoPlayer);
}

GVoid  GJLivePlay_Dealloc(GJLivePlayer** livePlayer){
    GJLOG(GJ_LOGDEBUG, "GJPlivePlayer dealloc");
    GJLivePlayer* player = *livePlayer;
    player->videoPlayer->displayUnSetup(player->videoPlayer);
    GJ_PictureDisplayContextDealloc(&player->videoPlayer);
    GJ_AudioPlayContextDealloc(&player->audioPlayer);
    queueFree(&player->playControl.audioQueue);
    queueFree(&player->playControl.imageQueue);
    free(player);
    *livePlayer = GNULL;
}
