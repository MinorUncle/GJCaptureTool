//
//  GJLivePlayer.m
//  GJCaptureTool
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLivePlayer.h"
#include "GJBufferPool.h"
#include "GJLog.h"
#include "GJQueue.h"
#include "GJUtil.h"
#include "IOS_AudioDrivePlayer.h"
#include "IOS_PictureDisplay.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define GJLivePlay_LOG_SWITCH LOG_INFO

//#define UIIMAGE_SHOW

#define VIDEO_PTS_PRECISION 400
#define AUDIO_PTS_PRECISION 200

#define MAX_CACHE_DUR 5000 //抖动最大缓存控制
#define MIN_CACHE_DUR 100  //抖动最小缓存控制
#define MAX_CACHE_RATIO 3
#define HIGHT_PASS_FILTER 0.5 //高通滤波

#define UPDATE_SHAKE_TIME_MIN 2*MAX_CACHE_DUR //
#define UPDATE_SHAKE_TIME_MAX 10*MAX_CACHE_DUR //


#define VIDEO_MAX_CACHE_COUNT 100 //初始化缓存空间
#define AUDIO_MAX_CACHE_COUNT 200

GLong getClockLine(GJSyncControl *sync) {
    if (sync->syncType == kTimeSYNCAudio) {
        GTime time     = GJ_Gettime();
        GLong timeDiff = GTimeSubtractMSValue(time, sync->audioInfo.trafficStatus.leave.clock) * sync->speed;
        return GTimeMSValue(sync->audioInfo.trafficStatus.leave.ts) + timeDiff;
    } else {
        //不能采用上面的方法，应为time - sync->audioInfo.clock每次回产生误差， * sync->speed也会产生误差
        GTime time     = GJ_Gettime();
        GLong timeDiff = GTimeSubtractMSValue(time, sync->videoInfo.startTime);
        return timeDiff + GTimeMSValue(sync->videoInfo.startPts) - sync->bufferInfo.bufferTotalDuration + sync->bufferInfo.speedTotalDuration;
    }
    
//    SyncInfo* info;
//    if (sync->syncType == kTimeSYNCAudio) {
//        info = &sync->audioInfo;
//    } else {
//        info = &sync->videoInfo;
//    }
//
//    GTime time     = GJ_Gettime() / 1000;
//    GTime timeDiff = (time - info->clock) * sync->speed;
//    return sync->audioInfo.cPTS + timeDiff;
 
}

static void resetSyncToStartPts(GJSyncControl *sync, GTime startPts) {
    sync->videoInfo.startPts = sync->audioInfo.startPts = startPts;
    if (sync->syncType == kTimeSYNCAudio) {
        sync->videoInfo.startTime = sync->audioInfo.startTime = GJ_Gettime();
    }else{
        sync->videoInfo.startTime = GJ_Gettime();
        sync->audioInfo.startTime = G_TIME_INVALID;
    }
    sync->bufferInfo.speedTotalDuration = sync->bufferInfo.bufferTotalDuration = 0;
}

static GBool changeSyncType(GJSyncControl *sync, TimeSYNCType syncType) {
    if (syncType == kTimeSYNCVideo) {
        sync->syncType = kTimeSYNCVideo;
        resetSyncToStartPts(sync, sync->videoInfo.trafficStatus.leave.ts);
        sync->netShake.collectStartPts = sync->videoInfo.trafficStatus.enter.ts;
    } else {
        sync->syncType = kTimeSYNCAudio;
        resetSyncToStartPts(sync, sync->audioInfo.trafficStatus.leave.ts);
        sync->netShake.collectStartPts = sync->audioInfo.trafficStatus.enter.ts;
        

    }
    sync->netShake.collectStartClock = GJ_Gettime();
    return GTrue;
}

static void updateWater(GJSyncControl *syncControl, GLong shake){
    if (shake > MAX_CACHE_DUR) {
        shake = MAX_CACHE_DUR;
    } else if (shake < MIN_CACHE_DUR) {
        shake = MIN_CACHE_DUR;
    }
    GJAssert(shake < 10000, "异常");
    
    syncControl->bufferInfo.lowWaterFlag  = shake;
    
    syncControl->bufferInfo.highWaterFlag = syncControl->bufferInfo.lowWaterFlag * MAX_CACHE_RATIO;
    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "updateWater lowWaterFlag:%ld,highWaterFlag:%ld",syncControl->bufferInfo.lowWaterFlag,syncControl->bufferInfo.highWaterFlag);
}

static GBool GJLivePlay_StartDewatering(GJLivePlayer *player) {
    //    return;
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status == kPlayStatusRunning) {
        if (player->syncControl.speed <= 1.00001) {
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "startDewatering");
            if (player->callback) {
                GFloat32 speed = 1.2f;
                player->callback(player->userDate,GJPlayMessage_DewateringUpdate,&speed);
            }
            player->syncControl.speed = 1.2;
            player->audioPlayer->audioSetSpeed(player->audioPlayer, 1.2);
        }
        //减小最大抖动更新间隔
        GInt32 collectUpdateDur = player->syncControl.netShake.collectUpdateDur - UPDATE_SHAKE_TIME_MIN/2;
        collectUpdateDur = GMAX(collectUpdateDur, UPDATE_SHAKE_TIME_MIN);
        player->syncControl.netShake.collectUpdateDur = collectUpdateDur;
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "reduce collectUpdateDur to:%d",player->syncControl.netShake.collectUpdateDur);
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}

static GBool GJLivePlay_StopDewatering(GJLivePlayer *player) {
    //    return;
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->syncControl.speed > 1.0) {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "stopDewatering");
        if (player->callback) {
            GFloat32 speed = 1.0f;
            player->callback(player->userDate,GJPlayMessage_DewateringUpdate,&speed);
        }
        player->syncControl.speed = 1.0f;
        player->audioPlayer->audioSetSpeed(player->audioPlayer, 1.0f);
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}

static GBool GJLivePlay_StartBuffering(GJLivePlayer *player) {
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status == kPlayStatusRunning) {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "start buffing");
        player->playControl.status                   = kPlayStatusBuffering;
        player->playControl.videoQueueWaitTime       = GINT32_MAX;
        player->syncControl.bufferInfo.lastPauseFlag = GTimeMSValue(GJ_Gettime());
        player->audioPlayer->audioPause(player->audioPlayer);

        player->callback(player->userDate, GJPlayMessage_BufferStart, GNULL);
        queueSetMinCacheSize(player->playControl.imageQueue, VIDEO_MAX_CACHE_COUNT);
        queueSetMinCacheSize(player->playControl.audioQueue, AUDIO_MAX_CACHE_COUNT);
        //每次缓冲时增大最大抖动更新间隔
        GInt32 collectUpdateDur = player->syncControl.netShake.collectUpdateDur + UPDATE_SHAKE_TIME_MIN;
        collectUpdateDur = GMIN(collectUpdateDur, UPDATE_SHAKE_TIME_MAX);
        player->syncControl.netShake.collectUpdateDur = collectUpdateDur;
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "add collectUpdateDur to:%d",player->syncControl.netShake.collectUpdateDur);
    } else {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "buffer when status not in running");
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}

static GVoid GJLivePlay_StopBuffering(GJLivePlayer *player) {
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status == kPlayStatusBuffering) {
        player->playControl.status = kPlayStatusRunning;
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "GJLivePlay_StopBuffering:%p",player);
        queueSetMinCacheSize(player->playControl.imageQueue, 0);
        if (queueGetLength(player->playControl.imageQueue) > 0) {
            queueBroadcastPop(player->playControl.imageQueue);
        }
        queueSetMinCacheSize(player->playControl.audioQueue, 0);
        if (queueGetLength(player->playControl.audioQueue) > 0) {
            queueBroadcastPop(player->playControl.audioQueue);
        }
        if (player->syncControl.bufferInfo.lastPauseFlag != 0) {
            player->syncControl.bufferInfo.lastBufferDuration = GTimeMSValue(GJ_Gettime()) - player->syncControl.bufferInfo.lastPauseFlag;
            player->syncControl.bufferInfo.bufferTotalDuration += player->syncControl.bufferInfo.lastBufferDuration;
            player->syncControl.bufferInfo.bufferTimes++;
            player->syncControl.bufferInfo.lastPauseFlag = 0;
        } else {
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGFORBID, "暂停管理出现问题");
        }
        player->syncControl.videoInfo.trafficStatus.leave.clock = player->syncControl.audioInfo.trafficStatus.leave.clock = GJ_Gettime();
        if (player->syncControl.syncType == kTimeSYNCAudio) {
            player->audioPlayer->audioResume(player->audioPlayer);
        }
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "buffing times:%ld useDuring:%ld", player->syncControl.bufferInfo.bufferTimes, player->syncControl.bufferInfo.lastBufferDuration);
    } else {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "stopBuffering when status not buffering");
    }
    pthread_mutex_unlock(&player->playControl.oLock);
}

GVoid GJLivePlay_CheckNetShake(GJLivePlayer *player, GTime pts) {

    GJSyncControl *_syncControl = &player->syncControl;
    GTime           clock    = GJ_Gettime();
    SyncInfo *      syncInfo = &_syncControl->audioInfo;
    GJNetShakeInfo *netShake = &_syncControl->netShake;
    if (_syncControl->syncType == kTimeSYNCVideo) {
        syncInfo = &_syncControl->videoInfo;
    }
    //    GTime shake =  -(pts - netShake->collectStartPts - clock + netShake->collectStartClock);

    GLong shake = (GTimeSencondValue(clock) - GTimeSencondValue(netShake->collectStartClock) - (GTimeSencondValue(pts) - GTimeSencondValue(netShake->collectStartPts)))*1000; //统计少发的抖动
    GJAssert(shake < 100000,"");
    
#ifdef NETWORK_DELAY
    GLong delay = 0;
    GLong testShake = 0;
    if (NeedTestNetwork) {
        delay = (GLong)(clock.value & 0x7fffffff) - GTimeMSValue(pts);
        
        testShake = delay - netShake->collectStartDelay;
        
        if (testShake > netShake->maxTestDownShake) {
            netShake->maxTestDownShake = testShake;
        }
    }
#endif
    GJLOG(GNULL, GJ_LOGINFO, "new shake:%ld,max:%ld ,preMax:%ld",shake,netShake->maxDownShake,netShake->preMaxDownShake);
    if (shake > netShake->maxDownShake) {
        netShake->maxDownShake = shake;
#ifdef NETWORK_DELAY
        if (NeedTestNetwork && testShake > netShake->preMaxTestDownShake) {
            GJLOG(LOG_DEBUG, GJ_LOGDEBUG, "real MaxDownShake:%ld ,preMax:%ld current delay:%ld",netShake->maxTestDownShake,netShake->preMaxTestDownShake,delay);
            GLong parm = (GLong)delay;
            player->callback(player->userDate,GJPlayMessage_TestKeyDelayUpdate,&parm);
        }
#endif
        if (netShake->maxDownShake > netShake->preMaxDownShake) {
            updateWater(_syncControl, shake);
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "new shake to update waterFlage. max:%ld ,preMax:%ld", netShake->maxDownShake, netShake->preMaxDownShake);
            
            player->callback(player->userDate,GJPlayMessage_NetShakeUpdate,&shake);
#ifdef NETWORK_DELAY
            if (testShake != shake) {
                GJLOG(GNULL, GJ_LOGWARNING, "测量值(%ld)与真实值(%ld)不相等",testShake,shake);

            }
            if (NeedTestNetwork) {
                player->callback(player->userDate,GJPlayMessage_TestNetShakeUpdate,&testShake);
            }
#endif
        }
    }
    
    if(shake < 0){


        if(netShake->maxDownShake > netShake->preMaxDownShake){
            
            netShake->preMaxDownShake =  netShake->maxDownShake;
        }else if(GTimeMSValue(clock) - GTimeMSValue(netShake->collectStartClock) > (MIN_CACHE_DUR + MAX_CACHE_DUR)*0.5){
            //防止连续负数
            
            //防止高频的负数刷新更新时间，难以到达更新时间，以至于难以减小。
            netShake->maxDownShake = MIN_CACHE_DUR;
            netShake->preMaxDownShake =  netShake->preMaxDownShake*HIGHT_PASS_FILTER + netShake->maxDownShake*(1-HIGHT_PASS_FILTER);
            GJLOG(GNULL, GJ_LOGINFO, "negative shake to update water flage");
            updateWater(_syncControl,netShake->preMaxDownShake);
            player->callback(player->userDate,GJPlayMessage_NetShakeUpdate,&netShake->preMaxDownShake);
        }
        netShake->maxDownShake = MIN_CACHE_DUR;
        netShake->collectStartClock = clock;
        netShake->collectStartPts   = pts;
        GJLOG(GNULL, GJ_LOGINFO, "negative shake to update max:%ld ,preMax:%ld", netShake->maxDownShake, netShake->preMaxDownShake);
#ifdef NETWORK_DELAY
        if (NeedTestNetwork) {
            
            if (netShake->maxTestDownShake > netShake->preMaxTestDownShake) {
                netShake->preMaxTestDownShake =  netShake->maxTestDownShake;
                GJLOG(GNULL, GJ_LOGINFO, "real negative shake to update max:%ld ,preMax:%ld", netShake->maxTestDownShake, netShake->preMaxTestDownShake);
            }
            netShake->collectStartDelay = delay;
            netShake->maxTestDownShake = MIN_CACHE_DUR;
        }
#endif
    }else
    if (GTimeSubtractMSValue(clock, netShake->collectStartClock) >= netShake->collectUpdateDur) {
        
        if (netShake->preMaxDownShake > netShake->maxDownShake) {
            //0.5倍的缓冲
            netShake->maxDownShake = (netShake->maxDownShake + netShake->preMaxDownShake)*0.5;
            updateWater(_syncControl,netShake->maxDownShake);
            player->callback(player->userDate,GJPlayMessage_NetShakeUpdate,&netShake->maxDownShake);
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "time to update max:%ld ,preMax:%ld", netShake->maxDownShake, netShake->preMaxDownShake);
#ifdef NETWORK_DELAY
            if (testShake != shake) {
                GJLOG(GNULL, GJ_LOGWARNING, "测量值(%ld)与真实值(%ld)不相等",testShake,shake);
                
            }
            if (NeedTestNetwork) {
                player->callback(player->userDate,GJPlayMessage_TestNetShakeUpdate,&testShake);
            }
#endif
        }
        netShake->preMaxDownShake   = netShake->maxDownShake;
        netShake->maxDownShake      = 0;
        netShake->collectStartClock = clock;
        netShake->collectStartPts   = pts;

#ifdef NETWORK_DELAY
        if (NeedTestNetwork) {

            netShake->collectStartDelay = delay;
            netShake->maxTestDownShake = 0;
            netShake->preMaxTestDownShake   = netShake->maxTestDownShake;
        }
#endif
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "更新网络抖动收集");
    }
}

GVoid GJLivePlay_CheckWater(GJLivePlayer *player) {

    GJPlayControl *_playControl = &player->playControl;
    GJSyncControl *_syncControl = &player->syncControl;
    GLong          cache;
    if (_playControl->status == kPlayStatusBuffering) {
        UnitBufferInfo bufferInfo;
        if (_syncControl->syncType == kTimeSYNCAudio) {
            GLong vCache          = GTimeSubtractMSValue(_syncControl->videoInfo.trafficStatus.enter.ts , _syncControl->videoInfo.trafficStatus.leave.ts);
            GLong aCache          = GTimeSubtractMSValue(_syncControl->audioInfo.trafficStatus.enter.ts, _syncControl->audioInfo.trafficStatus.leave.ts);
            bufferInfo.cacheCount = _syncControl->audioInfo.trafficStatus.enter.count - _syncControl->audioInfo.trafficStatus.leave.count;
            cache                 = aCache;
            if (((aCache == 0 && vCache >= _syncControl->bufferInfo.lowWaterFlag) || //音频没有了，视频足够
                vCache >= _syncControl->bufferInfo.highWaterFlag - 300) &&    //音频缓冲了一部分后音频消失
             GTimeSubtractMSValue(GJ_Gettime(), _syncControl->audioInfo.trafficStatus.leave.clock) > 500) {//且已经缓冲了一部分时间
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "等待音频缓冲过程中(lowWater:%ld)，音频为空视频足够、或者视频(%ld ms)足够大于音频(%ld ms)。切换到视频同步",_syncControl->bufferInfo.lowWaterFlag,vCache,aCache);
                player->playControl.videoQueueWaitTime = 0;
                if(changeSyncType(_syncControl, kTimeSYNCVideo)){
                    GJLivePlay_StopBuffering(player);
                    player->audioPlayer->audioStop(player->audioPlayer);
                    
                    //清除老数据
                    GInt32 qLength = queueGetLength(_playControl->audioQueue);
                    if (qLength > 0) {
                        queueEnablePop(_playControl->audioQueue, GFalse);
                        R_GJPCMFrame **audioBuffer = (R_GJPCMFrame **) malloc(qLength * sizeof(R_GJPCMFrame *));
                        queueClean(_playControl->audioQueue, (GVoid **) audioBuffer, &qLength); //用clean，防止播放断同时也在读
                        for (GUInt32 i = 0; i < qLength; i++) {
                            _syncControl->audioInfo.trafficStatus.leave.count++;
                            _syncControl->audioInfo.trafficStatus.leave.byte += R_BufferSize(&audioBuffer[i]->retain);
                            R_BufferUnRetain(&audioBuffer[i]->retain);
                        }
                        free(audioBuffer);
                        queueEnablePop(_playControl->audioQueue, GTrue);
                    }
                };
                return;
            }
#ifdef SHOULD_BUFFER_VIDEO_IN_AUDIO_CLOCK
            //音频等待缓冲视频
            else if (((vCache == 0 && aCache >= _syncControl->bufferInfo.lowWaterFlag) ||
                     vCache >= _syncControl->bufferInfo.highWaterFlag - 300) &&
                     GJ_Gettime()/1000 - _syncControl->videoInfo.trafficStatus.leave.clock > 500)) {//且已经缓冲了一部分时间
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "等待视频缓冲过程中(lowWater:%lld)，视频为空音频足够、或者音频（%d ms）足够大于视频(%d ms)。停止视频等待",_syncControl->bufferInfo.lowWaterFlag,aCache,vCache);
                player->playControl.videoQueueWaitTime = GINT32_MAX;
                GJLivePlay_StopBuffering(player);
                return;
            }
#endif
        } else {
            cache                 = GTimeSubtractMSValue(_syncControl->videoInfo.trafficStatus.enter.ts, _syncControl->videoInfo.trafficStatus.leave.ts);
            bufferInfo.cacheCount = _syncControl->audioInfo.trafficStatus.enter.count - _syncControl->audioInfo.trafficStatus.leave.count;
        }
        GLong duration       = GTimeMSValue(GJ_Gettime()) - _syncControl->bufferInfo.lastPauseFlag;
        bufferInfo.bufferDur = duration;
        bufferInfo.cachePts  = cache;
        bufferInfo.percent   = cache * 1.0 / _syncControl->bufferInfo.lowWaterFlag;

        if (cache < _syncControl->bufferInfo.lowWaterFlag) {
            player->callback(player->userDate, GJPlayMessage_BufferUpdate, &bufferInfo);
        } else {
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "缓冲结束");
            player->callback(player->userDate, GJPlayMessage_BufferUpdate, &bufferInfo);
            player->callback(player->userDate, GJPlayMessage_BufferEnd, &bufferInfo);
            player->playControl.videoQueueWaitTime = 0;
            GJLivePlay_StopBuffering(player);
        }
    } else if (_playControl->status == kPlayStatusRunning) {
        if (_syncControl->syncType == kTimeSYNCAudio) {
            cache = GTimeSubtractMSValue(_syncControl->audioInfo.trafficStatus.enter.ts, _syncControl->audioInfo.trafficStatus.leave.ts);
        } else {
            cache = GTimeSubtractMSValue(_syncControl->videoInfo.trafficStatus.enter.ts , _syncControl->videoInfo.trafficStatus.leave.ts);
        }
        if (cache > _syncControl->bufferInfo.highWaterFlag) {
            if (_syncControl->speed <= 1.0) {
                GJLivePlay_StartDewatering(player);
            }
        } else if (cache < _syncControl->bufferInfo.lowWaterFlag * 1.5) {
            if (_syncControl->speed > 1.0) {
                GJLivePlay_StopDewatering(player);
            }
        }
    }
}

GBool GJAudioDrivePlayerCallback(GHandle player, void *data, GInt32 *outSize) {

    GJPlayControl *_playControl = &((GJLivePlayer *) player)->playControl;
    GJSyncControl *_syncControl = &((GJLivePlayer *) player)->syncControl;

    R_GJPCMFrame *audioBuffer;
    if (_playControl->status == kPlayStatusRunning && queuePop(_playControl->audioQueue, (GHandle *) &audioBuffer, 0)) {

        *outSize = R_BufferSize(&audioBuffer->retain);
        memcpy(data, R_BufferStart(&audioBuffer->retain), *outSize);
        
        _syncControl->audioInfo.trafficStatus.leave.count++;
        _syncControl->audioInfo.trafficStatus.leave.ts  = audioBuffer->pts;
        _syncControl->audioInfo.trafficStatus.leave.clock = GJ_Gettime();
        
#ifdef NETWORK_DELAY
        if (NeedTestNetwork) {
            if (_syncControl->syncType == kTimeSYNCAudio) {
                GLong packetDelay = ((GJ_Gettime().value ) & 0x7fffffff) - GTimeMSValue(audioBuffer->pts);
                _syncControl->netShake.networkDelay += packetDelay;
                _syncControl->netShake.delayCount ++;
            }
        }
#endif
        
#ifdef DEBUG
        static GInt64 preTime ;
        if (preTime == 0) {
            preTime = GJ_Gettime().value;
        }
        GInt64 currentTime = GJ_Gettime().value;
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGALL, "消耗音频 PTS:%lld size:%d dTime:%lld",audioBuffer->pts.value,R_BufferSize(&audioBuffer->retain),currentTime - preTime);
        preTime = currentTime;
#endif
        if(_playControl->freshAudioFrame != GNULL){
            R_BufferUnRetain(&_playControl->freshAudioFrame->retain);
        }
        _playControl->freshAudioFrame = audioBuffer;
        return GTrue;
    } else {
        GLong shake = GMAX(_syncControl->netShake.maxDownShake, _syncControl->netShake.preMaxDownShake);
        GLong currentTime = GTimeMSValue(GJ_Gettime());
        GLong lastClock = GTimeMSValue(_syncControl->audioInfo.trafficStatus.leave.clock);
        if(shake < AUDIO_PTS_PRECISION && shake-(currentTime - lastClock)< AUDIO_PTS_PRECISION){
            *outSize = R_BufferSize(&_playControl->freshAudioFrame->retain);
            memcpy(data, R_BufferStart(&_playControl->freshAudioFrame->retain), *outSize);
        }else{
            *outSize = 0;
            if (_playControl->status == kPlayStatusRunning) {
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "audio player queue empty");
                if (_syncControl->syncType == kTimeSYNCAudio) {
                    GJLivePlay_StartBuffering(player);
                }
            }
        }
        return GFalse;
    }
}

static GHandle GJLivePlay_VideoRunLoop(GHandle parm) {
    pthread_setname_np("playVideoRunLoop");
    GJLivePlayer *  player       = parm;
    GJPlayControl * _playControl = &(player->playControl);
    GJSyncControl * _syncControl = &(player->syncControl);
    R_GJPixelFrame *cImageBuf;

    cImageBuf = GNULL;

    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "start play runloop");

    R_GJPixelFrame watiBuffer[2] = {0};

    if (_playControl->status == kPlayStatusStop) {
        goto END;
    }
    queuePeekWaitValue(_playControl->imageQueue, 2, (GHandle *) &watiBuffer, 100); ///等待至少两帧
    _syncControl->videoInfo.startTime = GJ_Gettime();

    while ((_playControl->status != kPlayStatusStop)) {

        if (queuePop(_playControl->imageQueue, (GHandle *) &cImageBuf, player->playControl.videoQueueWaitTime)) {

            if (_playControl->status == kPlayStatusStop) {
                R_BufferUnRetain(&cImageBuf->retain);
                cImageBuf = GNULL;
                break;
            }

        } else {

            if (_playControl->status == kPlayStatusStop) {
                break;
            } else if (_playControl->status == kPlayStatusRunning) {

                if (_syncControl->syncType == kTimeSYNCVideo) {
                    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "video play queue empty when kTimeSYNCVideo,start buffer");
                    GJLivePlay_StartBuffering(player);
                } else {
#ifdef SHOULD_BUFFER_VIDEO_IN_AUDIO_CLOCK
                    if (_playControl->videoQueueWaitTime < 10) { //_playControl->videoQueueWaitTime <= 10 表示不等待，但是没有数据了，所以需要缓冲
                        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "video play queue empty when kTimeSYNCAudio,start buffer");
                        GJLivePlay_StartBuffering(player);
                    }
#else
                    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGALL, "video play queue empty when kTimeSYNCAudio,do not buffer");
                    usleep(10 * 1000);
#endif
                }
            }else{
                usleep(10 * 1000);
            }
            continue;
        }

        GLong timeStandards = getClockLine(_syncControl);
        
        //速度的时空变化
        GLong delay         = (GLong)((GTimeMSValue(cImageBuf->pts) - timeStandards)/_syncControl->speed);
        if (delay > VIDEO_PTS_PRECISION) {

            if (_playControl->status == kPlayStatusStop) {
                goto DROP;
            }
            printf("");
            if (_syncControl->syncType == kTimeSYNCVideo) {
                
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频等待视频时间过长 delay:%ld PTS:%lld clock:%ld,重置同步管理", delay, cImageBuf->pts.value, timeStandards);
                resetSyncToStartPts(_syncControl,cImageBuf->pts);
                delay = 0;
            } else {
                
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频等待音频时间过长 delay:%ld PTS:%lld clock:%ld，等待下一帧视频做判断处理", delay, cImageBuf->pts.value, timeStandards);
                R_GJPixelFrame nextBuffer = {0};
                //会一直等待，知道超时，或者stop or buffering广播，1ms用于执行时间
                if(queuePeekWaitCopyValue(_playControl->imageQueue, 0, (GHandle) &nextBuffer, sizeof(R_GJPixelFrame), (GUInt32)delay - 1)) {
                    if (_playControl->status == kPlayStatusStop) {
                        goto DROP;
                    }
                    if( getClockLine(_syncControl) > GTimeMSValue(nextBuffer.pts)-1){
                        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频长时间等待音频结束，超过下一帧显示时间，直接丢帧");
                        delay = 0;
                        goto DROP;
                    }else{
                        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频长时间等待音频结束,正常显示");
                    }
                    
                }else{
                    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频长时间等待音频结束,没有下一帧，直接显示");
                    delay = 0;
                }
            }
        } else if (delay < -VIDEO_PTS_PRECISION) {

            if (_syncControl->syncType == kTimeSYNCVideo) {
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频落后视频严重，delay：%ld, PTS:%lld clock:%ld，重置同步管理", delay, cImageBuf->pts.value, timeStandards);
                resetSyncToStartPts(_syncControl,cImageBuf->pts);
                delay = 0;
            } else {
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频落后音频严重，delay：%ld, PTS:%lld clock:%ld，丢视频帧", delay, cImageBuf->pts.value, timeStandards);
                _syncControl->videoInfo.trafficStatus.leave.ts                   = cImageBuf->pts;
                _syncControl->videoInfo.trafficStatus.leave.clock                  = GJ_Gettime();
                goto DROP;
            }
        }

    DISPLAY:
        if (delay > 1) {
            GJLOG(GNULL, GJ_LOGALL,"play wait:%ld, video pts:%lld", delay, _syncControl->videoInfo.trafficStatus.leave.ts.value);
            usleep((GUInt32) delay * 1000);
            if (_playControl->status == kPlayStatusStop) {
                //减少退出时的时间。
                goto DROP;
            }
        }

        if (_syncControl->speed > 1.0) {
            _syncControl->bufferInfo.speedTotalDuration += (_syncControl->speed - 1.0) * GTimeSubtractMSValue(GJ_Gettime(), _syncControl->videoInfo.trafficStatus.leave.clock);
        }

        _syncControl->videoInfo.trafficStatus.leave.clock                  = GJ_Gettime();
        _syncControl->videoInfo.trafficStatus.leave.ts = cImageBuf->pts;
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGALL, "消耗视频 PTS:%lld",cImageBuf->pts.value);

#ifdef NETWORK_DELAY
        if (NeedTestNetwork) {
            if (_syncControl->syncType == kTimeSYNCVideo) {
                GInt32 packetDelay = (GInt32)((GJ_Gettime().value) & 0x7fffffff) - (GInt32)GTimeMSValue(cImageBuf->pts);
                _syncControl->netShake.networkDelay += packetDelay;
                _syncControl->netShake.delayCount ++;
            }
        }
#endif

#ifdef UIIMAGE_SHOW
        {
            CIImage *cimage = [CIImage imageWithCVPixelBuffer:cImageBuf->image];
            UIImage *image  = [UIImage imageWithCIImage:cimage];
            // Update the display with the captured image for DEBUG purposes
            dispatch_async(dispatch_get_main_queue(), ^{
                ((UIImageView *) player.displayView).image = image;
            });
        }
#else

        GJLOGFREQ("video show pts:%lld", cImageBuf->pts.value);
        if (_syncControl->videoInfo.trafficStatus.leave.count == 0 && player->callback) {
            player->callback(player->userDate,GJPlayMessage_FristRender,GNULL);
        }
        player->videoPlayer->displayView(player->videoPlayer, &cImageBuf->retain);
#endif

    DROP:
        _syncControl->videoInfo.trafficStatus.leave.count++;
        R_BufferUnRetain(&cImageBuf->retain);
        cImageBuf = GNULL;
    }

END:
    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "playRunLoop out");
    _playControl->status          = kPlayStatusStop;
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

GBool GJLivePlay_Create(GJLivePlayer **liveplayer, GJLivePlayCallback callback, GHandle userData) {

    if (*liveplayer == GNULL) {
        *liveplayer = (GJLivePlayer *) calloc(1, sizeof(GJLivePlayer));
    }

    GJLivePlayer *player = *liveplayer;
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_Create:%p",player);
    pipleNodeInit(&player->pipleNode, GJLivePlay_NodeAddData);
    GJ_PictureDisplayContextCreate(&player->videoPlayer);
    player->videoPlayer->displaySetup(player->videoPlayer);
    GJ_AudioPlayContextCreate(&player->audioPlayer);
    player->callback           = callback;
    player->userDate           = userData;
    player->playControl.status = kPlayStatusStop;
    pthread_mutex_init(&player->playControl.oLock, GNULL);
    queueCreate(&player->playControl.imageQueue, VIDEO_MAX_CACHE_COUNT, GTrue, GTrue); //150为暂停时视频最大缓冲
    queueCreate(&player->playControl.audioQueue, AUDIO_MAX_CACHE_COUNT, GTrue, GTrue);
    return GTrue;
}
GVoid GJLivePlay_AddAudioSourceFormat(GJLivePlayer *player, GJAudioFormat audioFormat) {
    GJAssert(player->playControl.status != kPlayStatusStop, "开始播放后才能添加播放资源");
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_AddAudioSourceFormat:%p",player);
    if (memcmp(&audioFormat, &player->audioFormat, sizeof(audioFormat))!=0) {
        player->audioFormat = audioFormat;
        if (player->audioPlayer->obaque) {
            player->audioPlayer->audioPlayUnSetup(player->audioPlayer);
        }
        player->audioPlayer->audioPlaySetup(player->audioPlayer, player->audioFormat, GJAudioDrivePlayerCallback, player);
    }
}
GVoid GJLivePlay_AddVideoSourceFormat(GJLivePlayer *player, GJPixelType audioFormat) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_AddVideoSourceFormat:%p",player);
    player->videoPlayer->displaySetFormat(player->videoPlayer, audioFormat);
}
GBool GJLivePlay_Start(GJLivePlayer *player) {
    GBool result = GTrue;
    pthread_mutex_lock(&player->playControl.oLock);

    if (player->playControl.status != kPlayStatusRunning) {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "GJLivePlayer start");
        memset(&player->syncControl, 0, sizeof(player->syncControl));
        player->playControl.status             = kPlayStatusRunning;
        player->syncControl.videoInfo.startPts = G_TIME_INVALID;
        player->syncControl.audioInfo.startPts = G_TIME_INVALID;
        player->syncControl.audioInfo.startTime = G_TIME_INVALID;
        player->syncControl.videoInfo.inDtsSeries = -GINT32_MAX;
        player->syncControl.audioInfo.inDtsSeries = -GINT32_MAX;

        player->syncControl.speed                    = 1.0;
        player->syncControl.bufferInfo.lowWaterFlag  = MIN_CACHE_DUR;
        player->syncControl.bufferInfo.highWaterFlag = MAX_CACHE_DUR;

        player->syncControl.netShake.preMaxDownShake = MIN_CACHE_DUR;
        player->syncControl.netShake.maxDownShake    = MIN_CACHE_DUR;
        player->syncControl.netShake.collectUpdateDur = UPDATE_SHAKE_TIME_MIN;
        player->callback(player->userDate,GJPlayMessage_NetShakeUpdate,&player->syncControl.netShake.maxDownShake);
#ifdef NETWORK_DELAY
        player->syncControl.netShake.preMaxTestDownShake = MIN_CACHE_DUR;
        player->syncControl.netShake.maxTestDownShake    = MIN_CACHE_DUR;
        if(NeedTestNetwork){
            player->callback(player->userDate,GJPlayMessage_NetShakeUpdate,&player->syncControl.netShake.maxTestDownShake);
        }
#endif
        
        changeSyncType(&player->syncControl, kTimeSYNCVideo);
        queueEnablePush(player->playControl.imageQueue, GTrue);
        queueEnablePush(player->playControl.audioQueue, GTrue);
        queueEnablePop(player->playControl.audioQueue, GTrue);
        queueEnablePop(player->playControl.imageQueue, GTrue);

    } else {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "GJLivePlayer 重复 start");
    }

    pthread_mutex_unlock(&player->playControl.oLock);
    return result;
}
GVoid GJLivePlay_Stop(GJLivePlayer *player) {
    GJLivePlay_StopBuffering(player);

    if (player->playControl.status != kPlayStatusStop) {
        GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_Stop:%p",player);
        pthread_mutex_lock(&player->playControl.oLock);
        player->playControl.status = kPlayStatusStop;
        queueEnablePush(player->playControl.audioQueue, GFalse);
        queueEnablePush(player->playControl.imageQueue, GFalse);
        queueEnablePop(player->playControl.audioQueue, GFalse);
        queueEnablePop(player->playControl.imageQueue, GFalse);

        queueBroadcastPop(player->playControl.imageQueue);
        queueBroadcastPop(player->playControl.audioQueue);
        pthread_mutex_unlock(&player->playControl.oLock);

        pthread_join(player->playControl.playVideoThread, GNULL);

        pthread_mutex_lock(&player->playControl.oLock);
        player->audioPlayer->audioStop(player->audioPlayer);
        
        if (player->playControl.freshAudioFrame) {
            R_BufferUnRetain(&player->playControl.freshAudioFrame->retain);
            player->playControl.freshAudioFrame = GNULL;
        }
        
        GInt32 vlength = queueGetLength(player->playControl.imageQueue);
        GInt32 alength = queueGetLength(player->playControl.audioQueue);

        if (vlength > 0) {
            R_GJPixelFrame **imageBuffer = (R_GJPixelFrame **) malloc(sizeof(R_GJPixelFrame *) * vlength);
            //不能用queuePop，因为已经enable false;
            if (queueClean(player->playControl.imageQueue, (GHandle *) imageBuffer, &vlength)) {
                for (GInt32 i = 0; i < vlength; i++) {
                    R_BufferUnRetain(&imageBuffer[i]->retain);
                }
            } else {
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGFORBID, "videoClean Error");
            }
            free(imageBuffer);
        }

        for (int i = player->sortIndex - 1; i >= 0; i--) {
            R_GJPixelFrame *pixelFrame = player->sortQueue[i];
            R_BufferUnRetain(&pixelFrame->retain);
        }
        player->sortIndex = 0;

        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "video player queue clean over");

        if (alength > 0) {
            R_GJPCMFrame **audioBuffer = (R_GJPCMFrame **) malloc(sizeof(R_GJPCMFrame *) * alength);

            if (queueClean(player->playControl.audioQueue, (GHandle *) audioBuffer, &alength)) {
                for (GInt32 i = 0; i < alength; i++) {
                    R_BufferUnRetain(&audioBuffer[i]->retain);
                }
            } else {
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGFORBID, "audioClean Error");
            }

            free(audioBuffer);
        }

        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "audio player queue clean over");
        pthread_mutex_unlock(&player->playControl.oLock);

    } else {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "重复停止");
    }
}

GBool GJLivePlay_Pause(GJLivePlayer *player){
    GJAssert(player != GNULL, "GJLivePlay_Pause nil");
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_Pause:%p",player);
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status != kPlayStatusPause) {
        
        player->playControl.status = kPlayStatusPause;
        if (player->audioPlayer != GNULL) {
            player->playControl.videoQueueWaitTime       = GINT32_MAX;
            player->syncControl.bufferInfo.lastPauseFlag = GTimeMSValue(GJ_Gettime());
            player->audioPlayer->audioPause(player->audioPlayer);
            
            queueSetMinCacheSize(player->playControl.audioQueue, AUDIO_MAX_CACHE_COUNT);
        }
        player->callback(player->userDate, GJPlayMessage_BufferStart, GNULL);
        queueSetMinCacheSize(player->playControl.imageQueue, VIDEO_MAX_CACHE_COUNT);
    }else{
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "重复暂停");
    }

    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}
GVoid GJLivePlay_Resume(GJLivePlayer *player){
    GJAssert(player != GNULL, "GJLivePlay_Pause nil");
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_Resume:%p",player);
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status != kPlayStatusRunning) {
        player->playControl.status = kPlayStatusRunning;
        queueSetMinCacheSize(player->playControl.imageQueue, 0);
        if (queueGetLength(player->playControl.imageQueue) > 0) {
            queueBroadcastPop(player->playControl.imageQueue);
        }
        
        if (player->syncControl.bufferInfo.lastPauseFlag != 0) {
            player->syncControl.bufferInfo.lastBufferDuration = GTimeMSValue(GJ_Gettime()) - player->syncControl.bufferInfo.lastPauseFlag;
            player->syncControl.bufferInfo.bufferTotalDuration += player->syncControl.bufferInfo.lastBufferDuration;
            player->syncControl.bufferInfo.bufferTimes++;
            player->syncControl.bufferInfo.lastPauseFlag = 0;
        } else {
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGFORBID, "暂停管理出现问题,重复pause");
        }
        
        if (player->audioPlayer != GNULL) {
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "stop buffing");
            //先开启播放器，设置clock，否则视频先运行的话，会导致视频落后
            player->syncControl.videoInfo.trafficStatus.leave.clock = player->syncControl.audioInfo.trafficStatus.leave.clock = GJ_Gettime();
            player->audioPlayer->audioResume(player->audioPlayer);
            

            queueSetMinCacheSize(player->playControl.audioQueue, 0);
            if (queueGetLength(player->playControl.audioQueue) > 0) {
                queueBroadcastPop(player->playControl.audioQueue);
            }
        }
        
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "buffing times:%ld useDuring:%ld", player->syncControl.bufferInfo.bufferTimes, player->syncControl.bufferInfo.lastBufferDuration);
    }else{
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "播放状态下调用resume");
    }

    pthread_mutex_unlock(&player->playControl.oLock);
}

inline static GBool _internal_AddVideoData(GJLivePlayer *player, R_GJPixelFrame *videoFrame) {
    //    printf("add play video pts:%lld\n",videoFrame->pts);
    if (player->playControl.playVideoThread == GNULL) {

        player->syncControl.videoInfo.startPts               = videoFrame->pts;
        player->syncControl.videoInfo.trafficStatus.leave.ts = videoFrame->pts; ///防止videoInfo.startPts不为从0开始时，videocache过大，

        pthread_mutex_lock(&player->playControl.oLock);

        if (player->playControl.status != kPlayStatusStop) {
            pthread_create(&player->playControl.playVideoThread, GNULL, GJLivePlay_VideoRunLoop, player);
        }

        pthread_mutex_unlock(&player->playControl.oLock);
    }

    R_BufferRetain(&videoFrame->retain);
    GBool result = GTrue;
    if (player->syncControl.syncType != kTimeSYNCAudio) {
        GJLivePlay_CheckNetShake(player, videoFrame->pts);
    }

RETRY:
    if (queuePush(player->playControl.imageQueue, videoFrame, 0)) {
        player->syncControl.videoInfo.trafficStatus.enter.ts = videoFrame->pts;
        player->syncControl.videoInfo.trafficStatus.enter.clock = GJ_Gettime();
        player->syncControl.videoInfo.trafficStatus.enter.count++;

        GJLivePlay_CheckWater(player);
        result = GTrue;

    } else if (player->playControl.status == kPlayStatusStop) {
        R_BufferUnRetain(&videoFrame->retain);
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "player video data push while stop,drop");
        result = GFalse;

    } else {

        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGFORBID, "video player queue full,update oldest frame");
        R_GJPixelFrame *oldBuffer = GNULL;

        if (queuePop(player->playControl.imageQueue, (GHandle *) &oldBuffer, 0)) {

            R_BufferUnRetain(&oldBuffer->retain);
            goto RETRY;

        } else {

            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGFORBID, "full player audio queue pop error");
            R_BufferUnRetain(&videoFrame->retain);
            result = GFalse;
        }
    }
    return result;
}
GBool GJLivePlay_AddVideoData(GJLivePlayer *player, R_GJPixelFrame *videoFrame) {

    GJLOG(GNULL, GJ_LOGALL, "收到视频 PTS:%lld DTS:%lld\n",videoFrame->pts.value,videoFrame->dts.value);

    if (videoFrame->dts.value < player->syncControl.videoInfo.inDtsSeries) {

        pthread_mutex_lock(&player->playControl.oLock);
        GInt32 length = queueGetLength(player->playControl.imageQueue);
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频dts不递增，抛弃之前的视频帧：%d帧", length);
        if(length > 0){
            queueEnablePop(player->playControl.imageQueue, GFalse);
            R_GJPixelFrame **imageBuffer = (R_GJPixelFrame **) malloc(length * sizeof(R_GJPixelFrame *));
            if (queueClean(player->playControl.imageQueue, (GHandle *) imageBuffer, &length)) {
                for (GUInt32 i = 0; i < length; i++) {
                    R_BufferUnRetain(&imageBuffer[i]->retain);
                }
            }
            if (imageBuffer) {
                free(imageBuffer);
            }
            queueEnablePop(player->playControl.imageQueue, GTrue);
        }
       
        for (int i = player->sortIndex - 1; i >= 0; i--) {
            R_GJPixelFrame *pixelFrame = player->sortQueue[i];
            R_BufferUnRetain(&pixelFrame->retain);
        }
        player->sortIndex = 0;
        player->syncControl.videoInfo.trafficStatus.leave.ts = videoFrame->pts;
        player->syncControl.videoInfo.inDtsSeries            = -GINT32_MAX;
        pthread_mutex_unlock(&player->playControl.oLock);
    }

    if (player->playControl.status == kPlayStatusStop) {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "播放器stop状态收到视频帧，直接丢帧");
        return GFalse;
    }
    player->syncControl.videoInfo.inDtsSeries = videoFrame->dts.value;

    
    //没有数据或者有 比较早的b帧，直接放入排序队列末尾
    if (player->sortIndex <= 0 || player->sortQueue[player->sortIndex - 1]->pts.value > videoFrame->pts.value) {
        player->sortQueue[player->sortIndex++] = videoFrame;
        R_BufferRetain(&videoFrame->retain);
        return GTrue;
    }
    //比前面最小的要大，说明b帧完成，可以倒序全部放入
    for (int i = player->sortIndex - 1; i >= 0; i--) {
        R_GJPixelFrame *pixelFrame = player->sortQueue[i];
        GBool           ret        = _internal_AddVideoData(player, pixelFrame);
        //取消排序队列的引用
        R_BufferUnRetain(&pixelFrame->retain);
        if (!ret) {
            return GFalse;
        }
    }
//刚接受的一个是最大的，继续放入排序队列，用于判断下一帧释放b帧
    player->sortIndex    = 1;
    player->sortQueue[0] = videoFrame;
    R_BufferRetain(&videoFrame->retain);
    return GTrue;
}
GBool GJLivePlay_AddAudioData(GJLivePlayer *player, R_GJPCMFrame *audioFrame) {

    GJLOG(GNULL, GJ_LOGALL, "收到音频 PTS:%lld DTS:%lld\n",audioFrame->pts.value,audioFrame->dts.value);
    GJPlayControl *_playControl = &(player->playControl);
    GJSyncControl *_syncControl = &(player->syncControl);
    GBool          result       = GTrue;
    GJAssert(R_BufferSize(&audioFrame->retain), "size 不能为0");

    if (audioFrame->dts.value < _syncControl->audioInfo.inDtsSeries) {
//加锁，防止此状态停止
        pthread_mutex_lock(&_playControl->oLock);
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "音频dts不递增，抛弃之前的音频帧：%d帧", queueGetLength(_playControl->audioQueue));

        GInt32 qLength = queueGetLength(_playControl->audioQueue);

        if (qLength > 0) {
            queueEnablePop(_playControl->audioQueue, GFalse);
            R_GJPCMFrame **audioBuffer = (R_GJPCMFrame **) malloc(qLength * sizeof(R_GJPCMFrame *));
            queueClean(_playControl->audioQueue, (GVoid **) audioBuffer, &qLength); //用clean，防止播放断同时也在读
            for (GUInt32 i = 0; i < qLength; i++) {
                _syncControl->audioInfo.trafficStatus.leave.count++;
                _syncControl->audioInfo.trafficStatus.leave.byte += R_BufferSize(&audioBuffer[i]->retain);
                R_BufferUnRetain(&audioBuffer[i]->retain);
            }
            free(audioBuffer);
            queueEnablePop(_playControl->audioQueue, GTrue);
        }

        _syncControl->audioInfo.inDtsSeries            = -GINT32_MAX;
        _syncControl->audioInfo.trafficStatus.leave.ts = audioFrame->pts; //防止此时获得audioCache时误差太大，防止pts重新开始时，视频远落后音频
        _syncControl->audioInfo.trafficStatus.leave.clock = GJ_Gettime();
        pthread_mutex_unlock(&_playControl->oLock);
    }

    if (_playControl->status == kPlayStatusStop) {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "播放器stop状态收到视音频，直接丢帧");
        result = GFalse;
        goto END;
    }

    if (_syncControl->syncType != kTimeSYNCAudio) {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "加入音频，切换到音频同步");
        
        ///<fix -2017. 7.26  //not stop buffer ,contion buffer to low water;
        //        if (_playControl->status == kPlayStatusBuffering) {
        //            GJLivePlay_StopBuffering(player);
        //        }
        _syncControl->audioInfo.trafficStatus.enter.ts = audioFrame->pts; ///防止audioInfo.startPts==0 导致startshakepts=0;
        _syncControl->audioInfo.trafficStatus.leave.ts = audioFrame->pts; ///防止audioInfo.startPts不为从0开始时，audiocache过大，
        _syncControl->audioInfo.trafficStatus.leave.clock = GJ_Gettime();
        if (changeSyncType(_syncControl, kTimeSYNCAudio)) {
            //加锁，防止正好关闭播放
            pthread_mutex_lock(&_playControl->oLock);
            if(player->playControl.status != kPlayStatusStop){
                player->audioPlayer->audioStart(player->audioPlayer);
                player->syncControl.audioInfo.startTime = GJ_Gettime();
            }else{
                GJAssert(GFalse, "需要优化，此状态下禁止播放");
            }
            pthread_mutex_unlock(&_playControl->oLock);

        };
    }
    
    GJLivePlay_CheckNetShake(player, audioFrame->pts);
    
//    if (player->audioPlayer->audioGetStatus(player->audioPlayer) <= kPlayStatusStop) {
//        _syncControl->audioInfo.startPts               = audioFrame->pts;
//        _syncControl->audioInfo.trafficStatus.leave.ts = audioFrame->pts; ///防止audioInfo.startPts不为从0开始时，audiocache过大，
//        //防止视频先到，导致时差特别大
//        _syncControl->audioInfo.trafficStatus.leave.ts  = audioFrame->pts;
//        _syncControl->audioInfo.trafficStatus.leave.clock = GJ_Gettime();
//
//    }
    R_BufferRetain(&audioFrame->retain);
    
RETRY:
    if (queuePush(_playControl->audioQueue, audioFrame, 0)) {
        _syncControl->audioInfo.inDtsSeries            = audioFrame->dts.value;
        _syncControl->audioInfo.trafficStatus.enter.ts = audioFrame->pts;
        _syncControl->audioInfo.trafficStatus.enter.clock = GJ_Gettime();
        _syncControl->audioInfo.trafficStatus.enter.count++;
        _syncControl->audioInfo.trafficStatus.enter.byte += R_BufferSize(&audioFrame->retain);

        GJLivePlay_CheckWater(player);
        result = GTrue;

    } else if (_playControl->status == kPlayStatusStop) {

        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "player audio data push while stop,drop");
        R_BufferUnRetain(&audioFrame->retain);
        result = GFalse;

    } else {

        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "audio player queue full,update oldest frame   ，正常情况不可能出现的case");
        R_GJPCMFrame *oldBuffer = GNULL;
        if (queuePop(_playControl->audioQueue, (GHandle *) &oldBuffer, 0)) {
            R_BufferUnRetain(&oldBuffer->retain);
            goto RETRY;
        } else {
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGFORBID, "full player audio queue pop error");
            R_BufferUnRetain(&audioFrame->retain);
            result = GFalse;
        }
    }

END:
    return result;
}
GJTrafficStatus GJLivePlay_GetVideoCacheInfo(GJLivePlayer *player) {
    return player->syncControl.videoInfo.trafficStatus;
}
GJTrafficStatus GJLivePlay_GetAudioCacheInfo(GJLivePlayer *player) {
    return player->syncControl.audioInfo.trafficStatus;
}

#ifdef NETWORK_DELAY
GLong GJLivePlay_GetNetWorkDelay(GJLivePlayer *player){
    GLong delay = 0;
    if (player->syncControl.netShake.delayCount > 0) {
        delay = player->syncControl.netShake.networkDelay / player->syncControl.netShake.delayCount;
    }
    player->syncControl.netShake.delayCount = 0;
    player->syncControl.netShake.networkDelay = 0;
    return delay;
}
#endif

GHandle GJLivePlay_GetVideoDisplayView(GJLivePlayer *player) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_GetVideoDisplayView:%p",player);
    return player->videoPlayer->getDispayView(player->videoPlayer);
}

GVoid GJLivePlay_Dealloc(GJLivePlayer **livePlayer) {
    GJLivePlayer *player = *livePlayer;
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_Dealloc:%p",player);
    if (player->audioPlayer->obaque) {
        player->audioPlayer->audioPlayUnSetup(player->audioPlayer);
    }
    pipleNodeUnInit(&player->pipleNode);
    player->videoPlayer->displayUnSetup(player->videoPlayer);
    GJ_PictureDisplayContextDealloc(&player->videoPlayer);
    GJ_AudioPlayContextDealloc(&player->audioPlayer);
    queueFree(&player->playControl.audioQueue);
    queueFree(&player->playControl.imageQueue);
    free(player);
    *livePlayer = GNULL;
}


