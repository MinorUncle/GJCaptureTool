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

//因为正态分布概率与平均数(u)和方差(Q)关系。
//68.3%  u-Q<x<u+Q
//95.4%  u-2Q<x<u+2Q
//99.7%  u-3Q<x<u+3Q
//但是方差太大，一般在3s以上，所以不适合用以上方案，直接采用标准差

//标准差和极差表示抖动情况，可以用来自动控制抖动区间的控制，所以标准差越小，抖动更新区间越小，更新越快。
//因为卡顿是由最大抖动引起的，所以本机制采用极差来表示抖动情况。（通过实际数据采集，标准差和极差成比例关系）
//因为期望为0，所以极差约等于2*最大抖动值，所以最大抖动值可以控制抖动更新区间。

#define VIDEO_PTS_PRECISION 140 //视频最多延迟两帧精度播放
#define AUDIO_PTS_PRECISION 100 //改为100，2帧

#define MAX_CACHE_DUR 4000 //抖动最大缓存控制，所以最大可能缓存到4000*MAX_CACHE_RATIO都不会追赶，
#define MIN_CACHE_DUR 400  //抖动最小缓存控制
#define MAX_CACHE_RATIO 3

//#define MAX_HIGH_WATER_RATIO 4       //最大高水准比例
//#define MIN_HIGH_WATER_RATIO 2       //最小高水准比例
//当抖动越小时，HIGH_WATER的比例应该越大

//#define HIGHT_PASS_FILTER 0.5 //高通滤波
#define SMOOTH_FILTER 0.7 //平滑滤波

#define UPDATE_SHAKE_TIME_MIN (5 * MAX_CACHE_DUR) //
#define UPDATE_SHAKE_TIME_MAX (15 * MAX_CACHE_DUR)   //

/*  抖动估计时间（y）和和当前抖动大小(x)成线性关系, y = ax + b;
 *  其中已知两个对应关系采样点（MIN_CACHE_DUR,UPDATE_SHAKE_TIME_MIN）和(MAX_CACHE_DUR,UPDATE_SHAKE_TIME_MAX);
 *  所以a = (UPDATE_SHAKE_TIME_MAX-UPDATE_SHAKE_TIME_MIN)/(MAX_CACHE_DUR - MIN_CACHE_DUR)
 *     b = UPDATE_SHAKE_TIME_MAX - a*MAX_CACHE_DUR。
 */

#define VIDEO_MAX_CACHE_COUNT 200 //初始化缓存空间
#define AUDIO_MAX_CACHE_COUNT 600

#define CHASE_SPEED 1.1f

GLong getClockLine(GJSyncControl *sync) {
    if (sync->syncType == kTimeSYNCAudio) {
        GTime time     = GJ_Gettime();
        GLong timeDiff = (sync->speed-1)*GTimeSubtractMSValue(time, sync->audioInfo.trafficStatus.leave.clock);
        
        return GTimeMSValue(time)+sync->audioInfo.trafficStatus.leave.ts_drift + timeDiff;
    } else {
        if (sync->speed > 1.0) {
            sync->bufferInfo.speedTotalDuration += (sync->speed - 1.0) * GTimeSubtractMSValue(GJ_Gettime(), sync->videoInfo.trafficStatus.leave.clock);
        }
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
    } else {
        sync->videoInfo.startTime = GJ_Gettime();
        sync->audioInfo.startTime = G_TIME_INVALID;
    }
    sync->bufferInfo.speedTotalDuration = sync->bufferInfo.bufferTotalDuration = 0;
}

static GBool changeSyncType(GJSyncControl *sync, TimeSYNCType syncType) {
    GTime current = GJ_Gettime();
    if (syncType == kTimeSYNCVideo) {
        sync->syncType = kTimeSYNCVideo;
        resetSyncToStartPts(sync, sync->videoInfo.trafficStatus.leave.ts);
        sync->netShake.collectStartPts = sync->videoInfo.trafficStatus.enter.ts;
    } else {
        sync->syncType = kTimeSYNCAudio;
        resetSyncToStartPts(sync, sync->audioInfo.trafficStatus.leave.ts);
        sync->netShake.collectStartPts = sync->audioInfo.trafficStatus.enter.ts;
    }
    sync->netShake.collectStartClock = current;
    return GTrue;
}

static void updateWater(GJSyncControl *syncControl, GLong shake) {
    //    shake += syncControl->netShake.STDEV;
    if (shake > MAX_CACHE_DUR) {
        shake = MAX_CACHE_DUR;
    } else if (shake < MIN_CACHE_DUR) {
        shake = MIN_CACHE_DUR;
    }
    GJAssert(shake < 10000, "异常");
    syncControl->bufferInfo.lowWaterFlag = shake;
    syncControl->bufferInfo.highWaterFlag = syncControl->bufferInfo.lowWaterFlag * MAX_CACHE_RATIO;
    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "updateWater lowWaterFlag:%ld,highWaterFlag:%ld", syncControl->bufferInfo.lowWaterFlag, syncControl->bufferInfo.highWaterFlag);
}

#define PLAY_CACHE_LOG(syncControl)                                                                                                                                  \
    do {                                                                                                                                                             \
        __typeof__(syncControl) _syncControl = (syncControl);                                                                                                        \
        GLong vCache                         = GTimeSubtractMSValue(_syncControl->videoInfo.trafficStatus.enter.ts, _syncControl->videoInfo.trafficStatus.leave.ts); \
        GLong aCache                         = GTimeSubtractMSValue(_syncControl->audioInfo.trafficStatus.enter.ts, _syncControl->audioInfo.trafficStatus.leave.ts); \
        GLong vCacheCount                    = _syncControl->videoInfo.trafficStatus.enter.count - _syncControl->videoInfo.trafficStatus.leave.count;                \
        GLong aCacheCount                    = _syncControl->audioInfo.trafficStatus.enter.count - _syncControl->audioInfo.trafficStatus.leave.count;                \
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "sync type:%s vCache ts:%ld count:%ld aCache ts:%ld count:%ld lowWater:%ld,hightWater:%ld",                        \
              _syncControl->syncType == kTimeSYNCVideo ? "video" : "audio", vCache, vCacheCount, aCache, aCacheCount,                                                \
              _syncControl->bufferInfo.lowWaterFlag, _syncControl->bufferInfo.highWaterFlag);                                                                        \
    } while (0)

static GBool GJLivePlay_StartDewatering(GJLivePlayer *player) {
    //    return;

    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status == kPlayStatusRunning) {
        if (player->syncControl.speed <= 1.00001) {
            PLAY_CACHE_LOG(&player->syncControl);
            if (player->callback) {
                GFloat speed = CHASE_SPEED;
                player->callback(player->userDate, GJPlayMessage_DewateringUpdate, &speed);
            }
            player->syncControl.bufferInfo.dewaterTimes++;
            player->syncControl.speed = CHASE_SPEED;
            player->audioPlayer->audioSetSpeed(player->audioPlayer, CHASE_SPEED);
        }
        //增加最大抖动更新间隔
        //每次缓冲时增大最大抖动更新间隔
//        if (player->syncControl.bufferInfo.hasBuffer) {
//            player->syncControl.bufferInfo.hasBuffer      = GFalse;
//            GLong collectUpdateDur                        = player->syncControl.netShake.collectUpdateDur + UPDATE_SHAKE_TIME_MIN;
//            collectUpdateDur                              = GMIN(collectUpdateDur, UPDATE_SHAKE_TIME_MAX);
//            player->syncControl.netShake.collectUpdateDur = (GInt32) collectUpdateDur;
//            player->callback(player->userDate, GJPlayMessage_NetShakeRangeUpdate, &collectUpdateDur);
//            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "add collectUpdateDur to:%ld", player->syncControl.netShake.collectUpdateDur);
//        } else {
//            player->syncControl.bufferInfo.hasDewater = GTrue;
//        }
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}

static GBool GJLivePlay_StopDewatering(GJLivePlayer *player) {
    //    return;
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->syncControl.speed > 1.0) {
        GJSyncControl *syncControl = &player->syncControl;
        syncControl->bufferInfo.speedTotalDuration += (syncControl->speed - 1.0) * GTimeSubtractMSValue(GJ_Gettime(), syncControl->videoInfo.trafficStatus.leave.clock);

        PLAY_CACHE_LOG(&player->syncControl);
        if (player->callback) {
            GFloat speed = 1.0f;
            player->callback(player->userDate, GJPlayMessage_DewateringUpdate, &speed);
        }

        syncControl->speed = 1.0f;
        player->audioPlayer->audioSetSpeed(player->audioPlayer, 1.0f);
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}

static GBool GJLivePlay_StartBuffering(GJLivePlayer *player) {
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status == kPlayStatusRunning) {
        PLAY_CACHE_LOG(&player->syncControl);
#ifdef DEBUG
        GJSyncControl* _syncControl = &player->syncControl;
        GLong aCache                         = GTimeSubtractMSValue(_syncControl->audioInfo.trafficStatus.enter.ts, _syncControl->audioInfo.trafficStatus.leave.ts);
        GJAssert(aCache <= _syncControl->bufferInfo.lowWaterFlag, "为什么数据足够还要缓冲");
#endif
        player->playControl.status                   = kPlayStatusBuffering;
        player->playControl.videoQueueWaitTime       = GINT32_MAX;
        player->syncControl.bufferInfo.lastPauseFlag = GTimeMSValue(GJ_Gettime());
        player->audioPlayer->audioPause(player->audioPlayer);

        player->callback(player->userDate, GJPlayMessage_BufferStart, GNULL);
        queueSetMinCacheSize(player->playControl.imageQueue, VIDEO_MAX_CACHE_COUNT);
        queueSetMinCacheSize(player->playControl.audioQueue, AUDIO_MAX_CACHE_COUNT);
        //每次缓冲时增大最大抖动更新间隔 //fix:采用基于抖动的智能更新
//        if (player->syncControl.bufferInfo.hasDewater) {
//            player->syncControl.bufferInfo.hasDewater     = GFalse;
//            GLong collectUpdateDur                        = player->syncControl.netShake.collectUpdateDur + UPDATE_SHAKE_TIME_MIN;
//            collectUpdateDur                              = GMIN(collectUpdateDur, UPDATE_SHAKE_TIME_MAX);
//            player->syncControl.netShake.collectUpdateDur = (GInt32) collectUpdateDur;
//            player->callback(player->userDate, GJPlayMessage_NetShakeRangeUpdate, &collectUpdateDur);
//            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "add collectUpdateDur to:%ld", player->syncControl.netShake.collectUpdateDur);
//        } else {
//            player->syncControl.bufferInfo.hasBuffer = GTrue;
//        }

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
        PLAY_CACHE_LOG(&player->syncControl);
        queueSetMinCacheSize(player->playControl.imageQueue, 0);
        if (queueGetLength(player->playControl.imageQueue) > 0) {
            queueBroadcastPop(player->playControl.imageQueue);
        }
        queueSetMinCacheSize(player->playControl.audioQueue, 0);
        if (queueGetLength(player->playControl.audioQueue) > 0) {
            queueBroadcastPop(player->playControl.audioQueue);
        }
        GJCacheInfo *bufferInfo = &player->syncControl.bufferInfo;
        if (bufferInfo->lastPauseFlag != 0) {
            bufferInfo->lastBufferDuration = GTimeMSValue(GJ_Gettime()) - bufferInfo->lastPauseFlag;
            bufferInfo->bufferTotalDuration += bufferInfo->lastBufferDuration;
            bufferInfo->bufferTimes++;
            bufferInfo->lastPauseFlag = 0;
        } else {
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGFORBID, "暂停管理出现问题");
        }
        player->syncControl.videoInfo.trafficStatus.leave.clock = player->syncControl.audioInfo.trafficStatus.leave.clock = GJ_Gettime();
        if (player->syncControl.syncType == kTimeSYNCAudio) {
            player->audioPlayer->audioResume(player->audioPlayer);
        }
        player->callback(player->userDate, GJPlayMessage_BufferEnd, bufferInfo);
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "buffing times:%ld useDuring:%ld", bufferInfo->bufferTimes, bufferInfo->lastBufferDuration);
    } else {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "stopBuffering when status not buffering");
    }
    pthread_mutex_unlock(&player->playControl.oLock);
}

GVoid GJLivePlay_CheckNetShake(GJLivePlayer *player, GTime pts) {

    GJSyncControl * _syncControl = &player->syncControl;
    GTime           clock        = GJ_Gettime();
    SyncInfo *      syncInfo     = &_syncControl->audioInfo;
    GJNetShakeInfo *netShake     = &_syncControl->netShake;
    if (_syncControl->syncType == kTimeSYNCVideo) {
        syncInfo = &_syncControl->videoInfo;
    }
    //    GTime shake =  -(pts - netShake->collectStartPts - clock + netShake->collectStartClock);
    GLong dClock = (GTimeSencondValue(clock) - GTimeSencondValue(netShake->collectStartClock)) * 1000;
    GLong dPTS   = (GTimeSencondValue(pts) - GTimeSencondValue(netShake->collectStartPts)) * 1000;
    GLong shake  = dClock - dPTS; //统计少发的抖动
    GLong dShake = shake;
//    if (shake < 0) { shake = -shake; }
#ifdef NETWORK_DELAY
    GLong delay     = 0;
    GLong testShake = 0;
    if (NeedTestNetwork) {
        delay = (GLong)(clock.value & 0x7fffffff) - GTimeMSValue(pts);

        testShake = delay - netShake->collectStartDelay;

        if (testShake > netShake->maxTestDownShake) {
            netShake->maxTestDownShake = testShake;
        }
    }
#endif
    //    GJLOG(GNULL, GJ_LOGINFO, "new shake:%ld,max:%ld ,preMax:%ld",shake,netShake->maxDownShake,netShake->preMaxDownShake);
    if (shake > netShake->maxDownShake) {
        netShake->maxDownShake = shake;
#ifdef NETWORK_DELAY
        if (NeedTestNetwork && testShake > netShake->preMaxTestDownShake) {
            GJLOG(LOG_DEBUG, GJ_LOGDEBUG, "real MaxDownShake:%ld ,preMax:%ld current delay:%ld", netShake->maxTestDownShake, netShake->preMaxTestDownShake, delay);
            GLong parm = (GLong) delay;
            player->callback(player->userDate, GJPlayMessage_TestKeyDelayUpdate, &parm);
        }
#endif
        if (netShake->maxDownShake > netShake->preMaxDownShake) {
            
            //增加是全额增加
            updateWater(_syncControl, shake);
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGALL, "new shake to update shake max then preMax. max:%ld ,preMax:%ld", netShake->maxDownShake, netShake->preMaxDownShake);
            player->callback(player->userDate, GJPlayMessage_NetShakeUpdate, &shake);
            
            //collectUpdateDur相应增加
            GLong currentMaxShake = GMIN(netShake->maxDownShake, MAX_CACHE_DUR);
            netShake->collectUpdateDur = netShake->paramA * currentMaxShake + netShake->paramB;
            player->callback(player->userDate, GJPlayMessage_NetShakeRangeUpdate, &netShake->collectUpdateDur);
#ifdef NETWORK_DELAY
            if (testShake != shake) {
                GJLOG(GNULL, GJ_LOGWARNING, "测量值(%ld)与真实值(%ld)不相等", testShake, shake);
            }
            if (NeedTestNetwork) {
                player->callback(player->userDate, GJPlayMessage_TestNetShakeUpdate, &testShake);
            }
#endif
        } else {
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGALL, "new shake to update shake max:%ld ,preMax:%ld", netShake->maxDownShake, netShake->preMaxDownShake);
        }
    }
//小于0有两种方案，一是按照一定比例下调，二是忽略
#if 0
    if(dShake < 0){
//如果是按照比例下调，则一定重新超时计时器，
        if(netShake->maxDownShake > netShake->preMaxDownShake){
//            如果有必要，更新preMaxDownShake
            netShake->preMaxDownShake =  netShake->maxDownShake;
        }else if(GTimeMSValue(clock) - GTimeMSValue(netShake->collectStartClock) > (MIN_CACHE_DUR + MAX_CACHE_DUR)*0.5){
//如果两次连续负数时间大约最大和最小的缓冲时间的平均值，则开始进入此区域（防止连续负数）。表示抖动变小，更新DownShake（此处逻辑有问题，抖动变小随时都有可能）
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
    }
#endif
    else if ((dShake < 0 && dClock >= netShake->collectUpdateDur) ||
             dClock >= 2 * netShake->collectUpdateDur) {
        //要shake小于0才开始更新抖动计时器，否则表示该包已经有延时了，后面的抖动计算就会偏小。
        //或者shake一直大于0，表示网络实在太差，也不需要高精度的抖动，则到达翻倍的超时时间也开始更新。

        if (netShake->preMaxDownShake >= netShake->maxDownShake) { //用>=而不是>，防止抖动比较小时，一直没有更新maxshake,导致要过两个周期才能进入此更新
            //降低时采用滤波器缓冲
            GLong downShake = netShake->preMaxDownShake * (1-SMOOTH_FILTER) + netShake->maxDownShake * SMOOTH_FILTER;
            updateWater(_syncControl, downShake);
            netShake->maxDownShake = downShake;
            player->callback(player->userDate, GJPlayMessage_NetShakeUpdate, &netShake->maxDownShake);
            
            //collectUpdateDur相应降低
            GLong currentMaxShake = GMIN(netShake->maxDownShake, MAX_CACHE_DUR);
            netShake->collectUpdateDur = netShake->paramA * currentMaxShake + netShake->paramB;
            player->callback(player->userDate, GJPlayMessage_NetShakeRangeUpdate, &netShake->collectUpdateDur);
#ifdef NETWORK_DELAY
            if (testShake != shake) {
                GJLOG(GNULL, GJ_LOGWARNING, "测量值(%ld)与真实值(%ld)不相等", testShake, shake);
            }
            if (NeedTestNetwork) {
                player->callback(player->userDate, GJPlayMessage_TestNetShakeUpdate, &testShake);
            }
#endif
        } //在每次的判断中已经增高了，增高是全额增高


        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "time to update shake max:%ld ,preMax:%ld,UpdateDur:%ld", netShake->maxDownShake, netShake->preMaxDownShake,netShake->collectUpdateDur);
        
        netShake->preMaxDownShake   = netShake->maxDownShake;
        netShake->maxDownShake      = MIN_CACHE_DUR;
        netShake->collectStartClock = clock;
        netShake->collectStartPts   = pts;

#ifdef NETWORK_DELAY
        if (NeedTestNetwork) {

            netShake->collectStartDelay   = delay;
            netShake->maxTestDownShake    = 0;
            netShake->preMaxTestDownShake = netShake->maxTestDownShake;
        }
#endif
        //        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGINFO, "更新网络抖动收集");
    }
}

GVoid GJLivePlay_CheckWater(GJLivePlayer *player) {

    GJPlayControl *_playControl = &player->playControl;
    GJSyncControl *_syncControl = &player->syncControl;
    GLong          cache;
    if (_playControl->status == kPlayStatusBuffering) {
        UnitBufferInfo bufferInfo;
        if (_syncControl->syncType == kTimeSYNCAudio) {

            GLong vCache      = GTimeSubtractMSValue(_syncControl->videoInfo.trafficStatus.enter.ts, _syncControl->videoInfo.trafficStatus.leave.ts);
            GLong aCache      = GTimeSubtractMSValue(_syncControl->audioInfo.trafficStatus.enter.ts, _syncControl->audioInfo.trafficStatus.leave.ts);
            GLong vCacheCount = _syncControl->videoInfo.trafficStatus.enter.count - _syncControl->videoInfo.trafficStatus.leave.count;

            bufferInfo.cacheCount = _syncControl->audioInfo.trafficStatus.enter.count - _syncControl->audioInfo.trafficStatus.leave.count;
            cache                 = aCache;
            //（(音频没有了&& 视频足够) || 音频缓冲了一部分后音频消失）&& （且已经缓冲了一部分时间|| 视频满了，再不播放就阻塞了）
            if (((aCache == 0 && vCache >= _syncControl->bufferInfo.lowWaterFlag) || vCache >= _syncControl->bufferInfo.highWaterFlag - 300) &&
                (GTimeSubtractMSValue(GJ_Gettime(), _syncControl->audioInfo.trafficStatus.leave.clock) > 500 || vCacheCount >= VIDEO_MAX_CACHE_COUNT * 0.8)) {
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "等待音频缓冲过程中(lowWater:%ld)，音频为空视频足够、或者视频(%ld ms)足够大于音频(%ld ms)。切换到视频同步", _syncControl->bufferInfo.lowWaterFlag, vCache, aCache);
                player->playControl.videoQueueWaitTime = 0;
                if (changeSyncType(_syncControl, kTimeSYNCVideo)) {
                    GJLivePlay_StopBuffering(player);
                    player->audioPlayer->audioStop(player->audioPlayer);

                    //清除老数据
                    GInt32 qLength = queueGetLength(_playControl->audioQueue);
                    if (qLength > 0) {
                        queueEnablePop(_playControl->audioQueue, GFalse);
                        queueFuncClean(_playControl->audioQueue, R_BufferUnRetainUnTrack);
                        queueEnablePop(_playControl->audioQueue, GTrue);
                    }
                };
                return;
            }
#ifdef SHOULD_BUFFER_VIDEO_IN_AUDIO_CLOCK
            //音频等待缓冲视频
            else if (((vCache == 0 && aCache >= _syncControl->bufferInfo.lowWaterFlag) ||
                      vCache >= _syncControl->bufferInfo.highWaterFlag - 300) &&
                     GJ_Gettime() / 1000 - _syncControl->videoInfo.trafficStatus.leave.clock > 500)) {//且已经缓冲了一部分时间
                    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "等待视频缓冲过程中(lowWater:%lld)，视频为空音频足够、或者音频（%d ms）足够大于视频(%d ms)。停止视频等待", _syncControl->bufferInfo.lowWaterFlag, aCache, vCache);
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
        GJLOG(GNULL, GJ_LOGINFO, "buffer percent:%f", bufferInfo.percent);

        if (cache < _syncControl->bufferInfo.lowWaterFlag) {
            player->callback(player->userDate, GJPlayMessage_BufferUpdate, &bufferInfo);
        } else {
            bufferInfo.percent = 1.0;
            player->callback(player->userDate, GJPlayMessage_BufferUpdate, &bufferInfo);
            player->playControl.videoQueueWaitTime = 0;
            GJLivePlay_StopBuffering(player);
        }
    } else if (_playControl->status == kPlayStatusRunning) {
        if (_syncControl->syncType == kTimeSYNCAudio) {
            cache = GTimeSubtractMSValue(_syncControl->audioInfo.trafficStatus.enter.ts, _syncControl->audioInfo.trafficStatus.leave.ts);
        } else {
            cache = GTimeSubtractMSValue(_syncControl->videoInfo.trafficStatus.enter.ts, _syncControl->videoInfo.trafficStatus.leave.ts);
        }
        if (cache > _syncControl->bufferInfo.highWaterFlag) {
            if (_syncControl->speed <= 1.0) {
                GJLOG(GNULL, GJ_LOGDEBUG, "StartDewatering with cache:%ld", cache);
                GJLivePlay_StartDewatering(player);
            }
        } else if (cache < (_syncControl->bufferInfo.lowWaterFlag +  _syncControl->bufferInfo.highWaterFlag)/2) {
            if (_syncControl->speed > 1.0) {
                GJLOG(GNULL, GJ_LOGDEBUG, "StopDewatering with cache:%ld", cache);
                GJLivePlay_StopDewatering(player);
            }
        }
    }
}

GBool GJAudioDrivePlayerCallback(GHandle player, void *data, GInt32 *outSize) {

    GJPlayControl *_playControl = &((GJLivePlayer *) player)->playControl;
    GJSyncControl *_syncControl = &((GJLivePlayer *) player)->syncControl;
 GJAudioFormat* format = &((GJLivePlayer *) player)->audioFormat;
    R_GJPCMFrame *audioBuffer;
    if (_playControl->status == kPlayStatusRunning && queuePop(_playControl->audioQueue, (GHandle *) &audioBuffer, format->mFramePerPacket*1000/format->mSampleRate)) {

        *outSize = R_BufferSize(&audioBuffer->retain);
        memcpy(data, R_BufferStart(&audioBuffer->retain), *outSize);

        GJAudioFormat* format = &((GJLivePlayer *) player)->audioFormat;
        GTime clock = GJ_Gettime();
        GTime ts = GTimeMake(GTimeMSValue(audioBuffer->pts) - format->mFramePerPacket*1000/format->mSampleRate,1000);
        _syncControl->audioInfo.trafficStatus.leave.count++;
        _syncControl->audioInfo.trafficStatus.leave.ts    = ts;
        _syncControl->audioInfo.trafficStatus.leave.clock = clock;

        _syncControl->audioInfo.trafficStatus.leave.ts_drift = GTimeSubtractMSValue(ts, clock);
#ifdef NETWORK_DELAY
        if (NeedTestNetwork) {
            if (_syncControl->syncType == kTimeSYNCAudio) {
                GLong packetDelay = ((GJ_Gettime().value) & 0x7fffffff) - GTimeMSValue(audioBuffer->pts);
                _syncControl->netShake.networkDelay += packetDelay;
                _syncControl->netShake.delayCount++;
            }
        }
#endif

//#ifdef DEBUG
//        static GInt64 preTime;
//        if (preTime == 0) {
//            preTime = GJ_Gettime().value;
//        }
//        GInt64 currentTime = GJ_Gettime().value;
//        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "消耗音频 PTS:%lld size:%d dTime:%lld ,ts_drift:%ld", audioBuffer->pts.value, R_BufferSize(&audioBuffer->retain), currentTime - preTime,_syncControl->audioInfo.trafficStatus.leave.ts_drift);
//        preTime = currentTime;
//#endif
        if (_playControl->freshAudioFrame != GNULL) {
            R_BufferUnRetain(_playControl->freshAudioFrame);
        }
        _playControl->freshAudioFrame = audioBuffer;
        return GTrue;
    } else {
        if (_playControl->status == kPlayStatusRunning) { //播放状态表示没有数据再播放了，才考虑填充
            GLong shake       = GMAX(_syncControl->netShake.maxDownShake, _syncControl->netShake.preMaxDownShake);
            GLong currentTime = GTimeMSValue(GJ_Gettime());
            GLong lastClock   = GTimeMSValue(_syncControl->audioInfo.trafficStatus.leave.clock);
            if (shake - (currentTime - lastClock) < AUDIO_PTS_PRECISION) { //去除抖动限制，因为可能抖动大于AUDIO_PTS_PRECISION，但是播放缓存也会消耗时间，
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "音频为空，但是估计缓冲时间不长，直接补充假数据，省去缓冲");
                *outSize = R_BufferSize(&_playControl->freshAudioFrame->retain);
                memcpy(data, R_BufferStart(_playControl->freshAudioFrame), *outSize);
                return GTrue;
            } else { //需要等待时间太久，不补充了，直接暂停播放吧。
                *outSize = 0;
                if (queueGetLength(_playControl->imageQueue) > VIDEO_MAX_CACHE_COUNT * 0.8) {
                    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "音频为空，视频几乎满了，为防止视频添加阻塞，主动切换到视频播放");
                    changeSyncType(_syncControl, kTimeSYNCVideo);

                } else {
                    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "audio player queue empty");
                    if (_syncControl->syncType == kTimeSYNCAudio) {
                        GJLivePlay_StartBuffering(player);
                    }
                }
                return GFalse;
            }
        } else { //否则表示已经开始缓存了，就算预计很快会有数据来也不会播放老数据
            *outSize = 0;
            return GFalse;
        }
    }
}

static GHandle GJLivePlay_VideoRunLoop(GHandle parm) {
    pthread_setname_np("Loop.GJVideoPlay");
    GJLivePlayer *  player       = parm;
    GJPlayControl * _playControl = &(player->playControl);
    GJSyncControl * _syncControl = &(player->syncControl);
    R_GJPixelFrame *cImageBuf;

    cImageBuf = GNULL;

    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "start play runloop");

    //    R_GJPixelFrame watiBuffer[2] = {0};

    if (_playControl->status == kPlayStatusStop) {
        goto END;
    }
    //    queuePeekWaitValue(_playControl->imageQueue, 2, (GHandle *) &watiBuffer, 100); ///等待至少两帧//不等了
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
            } else {
                usleep(10 * 1000);
            }
            continue;
        }

        GLong timeStandards = getClockLine(_syncControl);

        //速度的时空变化
        GLong delay = (GLong)((GTimeMSValue(cImageBuf->pts) - timeStandards) / _syncControl->speed);

        if (delay < -VIDEO_PTS_PRECISION) {

            GInt32 queueLenth = queueGetLength(_playControl->imageQueue);
            if (queueLenth > 0) {
                if (_syncControl->syncType == kTimeSYNCVideo) {
                    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频落后视频严重，delay：%ld, PTS:%lld clock:%ld，重置同步管理", delay, cImageBuf->pts.value, timeStandards);
                    resetSyncToStartPts(_syncControl, cImageBuf->pts);
                    delay = 0;
                } else {
                    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频落后音频严重，delay：%ld, PTS:%lld clock:%ld，丢视频帧", delay, cImageBuf->pts.value, timeStandards);
                    _syncControl->videoInfo.trafficStatus.leave.ts    = cImageBuf->pts;
                    _syncControl->videoInfo.trafficStatus.leave.clock = GJ_Gettime();
                    goto DROP;
                }
            } else {
                GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频落后严重，delay：%ld, PTS:%lld clock:%ld，并且没有下一帧，直接显示", delay, cImageBuf->pts.value, timeStandards);
            }
        }

    DISPLAY:
#ifdef DEBUG
//        GJLOG(GNULL, GJ_LOGDEBUG,"before render wait delay:%ld, video pts:%lld clock:%ld", delay, _syncControl->videoInfo.trafficStatus.leave.ts.value,timeStandards);
//        GLong beforeTime = GTimeMSValue(GJ_Gettime());
#endif
        if (delay > 4 && signalWait(_playControl->stopSignal, (GUInt32) delay)) {
            //bug 等待过程中速度变化无法感知，会有误差
            GJAssert(_playControl->status == kPlayStatusStop, "err signal emit");
            goto DROP;
        }



#ifdef NETWORK_DELAY
        if (NeedTestNetwork) {
            if (_syncControl->syncType == kTimeSYNCVideo) {
                GInt32 packetDelay = (GInt32)((GJ_Gettime().value) & 0x7fffffff) - (GInt32) GTimeMSValue(cImageBuf->pts);
                _syncControl->netShake.networkDelay += packetDelay;
                _syncControl->netShake.delayCount++;
            }
        }
#endif

        player->videoPlayer->renderFrame(player->videoPlayer, cImageBuf);

#ifdef DEBUG  //delay display
//        static GLong prePTS;
//        static GLong preTime;
//        GLong currentPTS = GTimeMSValue(cImageBuf->pts);
//        GLong currentTime = GTimeMSValue(GJ_Gettime());
//
//        GLong currentTimeStandards = getClockLine(_syncControl);
//
//        GLong currentDelay = (GLong)((GTimeMSValue(cImageBuf->pts) - currentTimeStandards) / _syncControl->speed);
//
//        GJLOG(GNULL,GJ_LOGDEBUG,"render currentClock:%ld, currentPts:%ld currentTime:%ld dpts:%ld dtime:%ld beforeDelay:%ld cache:%d renderDelay:%ld ,rendDur:%ld\n",currentTimeStandards, currentPTS, currentTime,currentPTS - prePTS,currentTime - preTime,delay,queueGetLength(_playControl->imageQueue),currentDelay,currentTime-beforeTime);
//
//        prePTS =  currentPTS;
//        preTime =  currentTime;
#endif

    DROP:
        
        _syncControl->videoInfo.trafficStatus.leave.ts    = cImageBuf->pts;
        _syncControl->videoInfo.trafficStatus.leave.count++;

        GTime clock = GJ_Gettime();
        _syncControl->videoInfo.trafficStatus.leave.clock = clock;
        _syncControl->videoInfo.trafficStatus.leave.ts_drift = GTimeSubtractMSValue(cImageBuf->pts, clock);
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGALL, "消耗视频 PTS:%lld", cImageBuf->pts.value);
        R_BufferUnRetain(&cImageBuf->retain);
        cImageBuf = GNULL;
    }

END:
    GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "playRunLoop out");
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
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_Create:%p", player);
    pipleNodeInit(&player->pipleNode, GJLivePlay_NodeAddData);
    GJ_PictureDisplayContextCreate(&player->videoPlayer);
    player->videoPlayer->displaySetup(player->videoPlayer);
    GJ_AudioPlayContextCreate(&player->audioPlayer);
    player->callback           = callback;
    player->userDate           = userData;
    player->playControl.status = kPlayStatusStop;

    pthread_mutex_init(&player->playControl.oLock, GNULL);
    queueCreate(&player->playControl.imageQueue, VIDEO_MAX_CACHE_COUNT, GTrue, GTrue); //150为暂停时视频最大缓冲
    queueCreate(&player->playControl.audioQueue, AUDIO_MAX_CACHE_COUNT, GTrue, GFalse);
    signalCreate(&player->playControl.stopSignal);
    return GTrue;
}
GVoid GJLivePlay_AddAudioSourceFormat(GJLivePlayer *player, GJAudioFormat audioFormat) {
    GJAssert(player->playControl.status != kPlayStatusStop, "开始播放后才能添加播放资源");
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_AddAudioSourceFormat:%p", player);
    if (memcmp(&audioFormat, &player->audioFormat, sizeof(audioFormat)) != 0) {
        player->audioFormat = audioFormat;
        if (player->audioPlayer->obaque) {
            player->audioPlayer->audioPlayUnSetup(player->audioPlayer);
        }
        player->audioPlayer->audioPlaySetup(player->audioPlayer, player->audioFormat, GJAudioDrivePlayerCallback, player);
    }
}
GVoid GJLivePlay_AddVideoSourceFormat(GJLivePlayer *player, GJPixelType pixelFormat) {
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_AddVideoSourceFormat:%p", player);
    if (player->playControl.playVideoThread == GNULL) {
        
        pthread_mutex_lock(&player->playControl.oLock);
        
        if (player->playControl.status != kPlayStatusStop) {
            pthread_create(&player->playControl.playVideoThread, GNULL, GJLivePlay_VideoRunLoop, player);
        }
        
        pthread_mutex_unlock(&player->playControl.oLock);
    }
}
GBool GJLivePlay_Start(GJLivePlayer *player) {
    GBool                            result = GTrue;
    pthread_mutex_lock(&player->playControl.oLock);

    if (player->playControl.status != kPlayStatusRunning) {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGDEBUG, "GJLivePlayer start");
        memset(&player->syncControl, 0, sizeof(player->syncControl));
        player->playControl.status                = kPlayStatusRunning;
        player->syncControl.videoInfo.startPts    = G_TIME_INVALID;
        player->syncControl.audioInfo.startPts    = G_TIME_INVALID;
        player->syncControl.audioInfo.startTime   = G_TIME_INVALID;

        player->syncControl.speed                    = 1.0;
        player->syncControl.bufferInfo.lowWaterFlag  = MIN_CACHE_DUR;
        player->syncControl.bufferInfo.highWaterFlag = MIN_CACHE_DUR * 4;

        player->syncControl.netShake.preMaxDownShake  = MIN_CACHE_DUR;
        player->syncControl.netShake.maxDownShake     = MIN_CACHE_DUR;
        player->syncControl.netShake.collectUpdateDur = UPDATE_SHAKE_TIME_MIN;
        player->syncControl.netShake.paramA           = (UPDATE_SHAKE_TIME_MAX-UPDATE_SHAKE_TIME_MIN)/(MAX_CACHE_DUR - MIN_CACHE_DUR);
        player->syncControl.netShake.paramB           = UPDATE_SHAKE_TIME_MAX - player->syncControl.netShake.paramA*MAX_CACHE_DUR;
        player->callback(player->userDate, GJPlayMessage_NetShakeRangeUpdate, &player->syncControl.netShake.collectUpdateDur);
        player->callback(player->userDate, GJPlayMessage_NetShakeUpdate, &player->syncControl.netShake.maxDownShake);

#ifdef NETWORK_DELAY
        player->syncControl.netShake.preMaxTestDownShake = MIN_CACHE_DUR;
        player->syncControl.netShake.maxTestDownShake    = MIN_CACHE_DUR;
        if (NeedTestNetwork) {
            player->callback(player->userDate, GJPlayMessage_NetShakeUpdate, &player->syncControl.netShake.maxTestDownShake);
        }
#endif

        changeSyncType(&player->syncControl, kTimeSYNCVideo);
        queueEnablePush(player->playControl.imageQueue, GTrue);
        queueEnablePush(player->playControl.audioQueue, GTrue);
        queueEnablePop(player->playControl.audioQueue, GTrue);
        queueEnablePop(player->playControl.imageQueue, GTrue);
        signalReset(player->playControl.stopSignal);
    } else {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "GJLivePlayer 重复 start");
    }

    pthread_mutex_unlock(&player->playControl.oLock);
    return result;
}
GVoid GJLivePlay_Stop(GJLivePlayer *player) {
    GJLivePlay_StopBuffering(player);
    GJLivePlay_StopDewatering(player);

    if (player->playControl.status != kPlayStatusStop) {
        GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_Stop:%p", player);
        pthread_mutex_lock(&player->playControl.oLock);
        player->playControl.status = kPlayStatusStop;
        signalEmit(player->playControl.stopSignal);

        queueEnablePush(player->playControl.audioQueue, GFalse);
        queueEnablePush(player->playControl.imageQueue, GFalse);
        queueEnablePop(player->playControl.audioQueue, GFalse);
        queueEnablePop(player->playControl.imageQueue, GFalse);

        queueBroadcastPop(player->playControl.imageQueue);
        queueBroadcastPop(player->playControl.audioQueue);
        player->audioPlayer->audioStop(player->audioPlayer); //可能会等待一会，移到前面，防止过多的等待
        pthread_mutex_unlock(&player->playControl.oLock);

        pthread_join(player->playControl.playVideoThread, GNULL);

        pthread_mutex_lock(&player->playControl.oLock);

        if (player->playControl.freshAudioFrame) {
            R_BufferUnRetain(&player->playControl.freshAudioFrame->retain);
            player->playControl.freshAudioFrame = GNULL;
        }

        queueFuncClean(player->playControl.imageQueue, R_BufferUnRetainUnTrack);
        queueFuncClean(player->playControl.audioQueue, R_BufferUnRetainUnTrack);

        pthread_mutex_unlock(&player->playControl.oLock);

    } else {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "重复停止");
    }
}

GBool GJLivePlay_Pause(GJLivePlayer *player) {
    GJAssert(player != GNULL, "GJLivePlay_Pause nil");
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_Pause:%p", player);
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status != kPlayStatusPause) {

        player->playControl.status = kPlayStatusPause;
        if (player->audioPlayer != GNULL) {
            player->playControl.videoQueueWaitTime       = GINT32_MAX;
            player->syncControl.bufferInfo.lastPauseFlag = GTimeMSValue(GJ_Gettime());
            player->audioPlayer->audioPause(player->audioPlayer);

            queueSetMinCacheSize(player->playControl.audioQueue, AUDIO_MAX_CACHE_COUNT + 1);
        }
        queueSetMinCacheSize(player->playControl.imageQueue, VIDEO_MAX_CACHE_COUNT + 1);
    } else {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "重复暂停");
    }

    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}
GVoid GJLivePlay_Resume(GJLivePlayer *player) {
    GJAssert(player != GNULL, "GJLivePlay_Pause nil");
    GJLOG(GNULL, GJ_LOGDEBUG, "GJLivePlay_Resume:%p", player);
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
            GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGFORBID, "暂停管理出现问题,重复resume");
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
    } else {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "播放状态下调用resume");
    }

    pthread_mutex_unlock(&player->playControl.oLock);
}

GBool GJLivePlay_AddVideoData(GJLivePlayer *player, R_GJPixelFrame *videoFrame) {
    GJLOG(GNULL, GJ_LOGALL, "收到视频 PTS:%lld DTS:%lld\n",videoFrame->pts.value,videoFrame->dts.value);
    
    if (videoFrame->pts.value < player->syncControl.videoInfo.trafficStatus.enter.ts.value) {
        
        pthread_mutex_lock(&player->playControl.oLock);
        GInt32 length = queueGetLength(player->playControl.imageQueue);
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频pts不递增，抛弃之前的视频帧：%d帧", length);
        if (length > 0) {
            queueEnablePop(player->playControl.imageQueue, GFalse);
            queueFuncClean(player->playControl.imageQueue, R_BufferUnRetainUnTrack);
            
            queueEnablePop(player->playControl.imageQueue, GTrue);
        }
        player->syncControl.videoInfo.startPts               = videoFrame->pts;
        player->syncControl.videoInfo.trafficStatus.leave.ts = videoFrame->pts;
        pthread_mutex_unlock(&player->playControl.oLock);
    }
    
    if (player->playControl.status == kPlayStatusStop) {
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "播放器stop状态收到视频帧，直接丢帧");
        return GFalse;
    }

    if (unlikely(player->syncControl.videoInfo.trafficStatus.enter.count == 0)) {
        player->syncControl.videoInfo.startPts               = videoFrame->pts;
        player->syncControl.videoInfo.trafficStatus.leave.ts = videoFrame->pts; ///防止videoInfo.startPts不为从0开始时，videocache过大，
        if (player->callback) {
            player->callback(player->userDate, GJPlayMessage_FirstRender, videoFrame);
        }
        player->videoPlayer->renderFrame(player->videoPlayer, videoFrame);
    }

    static GInt64 prePts;
    if (videoFrame->pts.value < prePts) {
        printf("pts:%lld,prepts:%lld\n",videoFrame->pts.value,prePts);
    }
    prePts = videoFrame->pts.value;
    R_BufferRetain(videoFrame);
    GBool result = GTrue;
    if (player->syncControl.syncType != kTimeSYNCAudio) {
        GJLivePlay_CheckNetShake(player, videoFrame->pts);
    }

RETRY:
    if (queuePush(player->playControl.imageQueue, videoFrame, GINT32_MAX)) {
        player->syncControl.videoInfo.trafficStatus.enter.ts    = videoFrame->pts;
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
//GBool GJLivePlay_AddVideoData(GJLivePlayer *player, R_GJPixelFrame *videoFrame) {
//
//        GJLOG(GNULL, GJ_LOGDEBUG, "收到视频 PTS:%lld DTS:%lld\n",videoFrame->pts.value,videoFrame->dts.value);
//
//    if (videoFrame->dts.value < player->syncControl.videoInfo.inDtsSeries) {
//
//        pthread_mutex_lock(&player->playControl.oLock);
//        GInt32 length = queueGetLength(player->playControl.imageQueue);
//        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "视频dts不递增，抛弃之前的视频帧：%d帧", length);
//        if (length > 0) {
//            queueEnablePop(player->playControl.imageQueue, GFalse);
//            queueFuncClean(player->playControl.imageQueue, R_BufferUnRetainUnTrack);
//
//            queueEnablePop(player->playControl.imageQueue, GTrue);
//        }
//
//        for (int i = player->sortIndex - 1; i >= 0; i--) {
//            R_GJPixelFrame *pixelFrame = player->sortQueue[i];
//            R_BufferUnRetain(&pixelFrame->retain);
//        }
//        player->sortIndex                                    = 0;
//        player->syncControl.videoInfo.trafficStatus.leave.ts = videoFrame->pts;
//        player->syncControl.videoInfo.inDtsSeries            = -GINT32_MAX;
//        pthread_mutex_unlock(&player->playControl.oLock);
//    }
//
//    if (player->playControl.status == kPlayStatusStop) {
//        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "播放器stop状态收到视频帧，直接丢帧");
//        return GFalse;
//    }
//    player->syncControl.videoInfo.inDtsSeries = videoFrame->dts.value;
//
//    if (unlikely(player->syncControl.videoInfo.trafficStatus.enter.count == 0 && player->sortIndex <= 0)) { //第一次直接进入，加快第一帧显示
//        if (player->callback) {
//            player->callback(player->userDate, GJPlayMessage_FirstRender, videoFrame);
//        }
//        player->videoPlayer->renderFrame(player->videoPlayer, videoFrame);
//    }
//    //没有数据或者有 比较早的b帧，直接放入排序队列末尾
//    if (player->sortIndex <= 0 || player->sortQueue[player->sortIndex - 1]->pts.value > videoFrame->pts.value) {
//        player->sortQueue[player->sortIndex++] = videoFrame;
//        R_BufferRetain(videoFrame);
//        return GTrue;
//    }
//    //比前面最小的要大，说明b帧完成，可以倒序全部放入
//    for (int i = player->sortIndex - 1; i >= 0; i--) {
//        R_GJPixelFrame *pixelFrame = player->sortQueue[i];
//        GBool           ret        = _internal_AddVideoData(player, pixelFrame);
//        //取消排序队列的引用
//        R_BufferUnRetain(&pixelFrame->retain);
//        if (!ret) {
//            return GFalse;
//        }
//    }
//    //刚接受的一个是最大的，继续放入排序队列，用于判断下一帧释放b帧
//    player->sortIndex    = 1;
//    player->sortQueue[0] = videoFrame;
//    R_BufferRetain(videoFrame);
//    return GTrue;
//}
GBool GJLivePlay_AddAudioData(GJLivePlayer *player, R_GJPCMFrame *audioFrame) {

    GJLOG(GNULL, GJ_LOGALL, "收到音频 PTS:%lld DTS:%lld size:%d", audioFrame->pts.value, audioFrame->dts.value,R_BufferSize(audioFrame));
    GJPlayControl *_playControl = &(player->playControl);
    GJSyncControl *_syncControl = &(player->syncControl);
    GBool          result       = GTrue;
    GJAssert(R_BufferSize(&audioFrame->retain), "size 不能为0");

    if (audioFrame->dts.value < _syncControl->audioInfo.trafficStatus.enter.ts.value) {
        //加锁，防止此状态停止
        pthread_mutex_lock(&_playControl->oLock);
        GJLOG(GJLivePlay_LOG_SWITCH, GJ_LOGWARNING, "音频dts不递增，抛弃之前的音频帧：%d帧", queueGetLength(_playControl->audioQueue));

        GInt32 qLength = queueGetLength(_playControl->audioQueue);

        if (qLength > 0) {
            queueEnablePop(_playControl->audioQueue, GFalse);
            queueFuncClean(_playControl->audioQueue, R_BufferUnRetainUnTrack);
            queueEnablePop(_playControl->audioQueue, GTrue);
        }
        GTime current = GJ_Gettime();
        _syncControl->audioInfo.trafficStatus.leave.ts    = audioFrame->pts; //防止此时获得audioCache时误差太大，防止pts重新开始时，视频远落后音频
        _syncControl->audioInfo.trafficStatus.leave.clock = current;
        _syncControl->audioInfo.trafficStatus.leave.ts_drift = GTimeSubtractMSValue(audioFrame->pts, current)-30;//预测30ms后播放此帧，只是用作没有播放前的视频同步，播放音频后会自动更新
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
        GTime current = GJ_Gettime();
        _syncControl->audioInfo.trafficStatus.enter.ts    = audioFrame->pts; ///防止audioInfo.startPts==0 导致startshakepts=0;
        _syncControl->audioInfo.trafficStatus.leave.ts    = audioFrame->pts; ///防止audioInfo.startPts不为从0开始时，audiocache过大，
        _syncControl->audioInfo.trafficStatus.leave.clock = current;
        _syncControl->audioInfo.trafficStatus.leave.ts_drift = GTimeSubtractMSValue(audioFrame->pts, current)-30;//预测30ms后播放此帧，只是用作没有播放前的视频同步，播放音频后会自动更新

        if (changeSyncType(_syncControl, kTimeSYNCAudio)) {
            //加锁，防止正好关闭播放
            pthread_mutex_lock(&_playControl->oLock);
            if (player->playControl.status != kPlayStatusStop) {
                player->audioPlayer->audioStart(player->audioPlayer);
                player->syncControl.audioInfo.startTime = GJ_Gettime();
            } else {
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
    R_BufferRetain(audioFrame);
    
RETRY:
    if (queuePush(_playControl->audioQueue, audioFrame, GINT32_MAX)) {
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
    signalDestory(&player->playControl.stopSignal);

    free(player);
    *livePlayer = GNULL;
}


