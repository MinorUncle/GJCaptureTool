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


#define UPDATE_SHAKE_TIME 6000
#define MAX_CACHE_DUR 3000
#define MIN_CACHE_DUR 200

#define VIDEO_MAX_CACHE_COUNT 100 //初始化缓存空间
#define AUDIO_MAX_CACHE_COUNT 200

GLong getClockLine(GJSyncControl* sync){
    if (sync->syncType == kTimeSYNCAudio) {
        GLong time = GJ_Gettime() / 1000;
        GLong  timeDiff = time - sync->audioInfo.clock;
        return sync->audioInfo.cPTS+timeDiff;
    }else{
        GLong time = GJ_Gettime() / 1000;
        GLong timeDiff = time - sync->videoInfo.startTime;
        return timeDiff + sync->videoInfo.startPts - sync->bufferInfo.bufferTotalDuration + sync->bufferInfo.speedTotalDuration;
    }
}
static void resetSyncToStartPts(GJSyncControl* sync,GLong startPts){
    sync->videoInfo.startPts = sync->audioInfo.startPts = startPts;
    sync->videoInfo.startTime = sync->audioInfo.startTime = GJ_Gettime() / 1000.0;
    sync->bufferInfo.speedTotalDuration = sync->bufferInfo.bufferTotalDuration = 0;
}
static void changeSyncType(GJSyncControl* sync,TimeSYNCType syncType){
    if (syncType == kTimeSYNCVideo) {
        sync->syncType = kTimeSYNCVideo;
        resetSyncToStartPts(sync, sync->videoInfo.cPTS);
    }else{
        sync->syncType = kTimeSYNCAudio;
        resetSyncToStartPts(sync, sync->audioInfo.cPTS);
    }
    sync->netShake.collectStartClock = sync->netShake.collectUnitStartClock = sync->netShake.collectUnitEndClock = GJ_Gettime()/1000;
    sync->netShake.maxShake = MAX_CACHE_DUR;
    sync->netShake.minShake = MIN_CACHE_DUR;
    
}

static GBool GJLivePlay_StartDewatering(GJLivePlayer* player){
    //    return;
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status == kPlayStatusRunning) {
        if (player->syncControl.speed<=1.0) {
            GJLOG(GJ_LOGDEBUG, "startDewatering");
            player->syncControl.speed = 1.2;
            player->audioPlayer.audioSetSpeed(&player->audioPlayer,1.2);
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
        player->audioPlayer.audioSetSpeed(&player->audioPlayer,1.0);
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return GTrue;
}
static GBool  GJLivePlay_StartBuffering(GJLivePlayer* player){
    pthread_mutex_lock(&player->playControl.oLock);
    if(player->playControl.status == kPlayStatusRunning){
        GJLOG(GJ_LOGDEBUG, "start buffing");
        player->playControl.status = kPlayStatusBuffering;
        player->syncControl.bufferInfo.lastPauseFlag = GJ_Gettime() / 1000;
        player->audioPlayer.audioPause(&player->audioPlayer);
        
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
        player->audioPlayer.audioResume(&player->audioPlayer);
        GJLOG(GJ_LOGINFO, "buffing times:%d useDuring:%d",player->syncControl.bufferInfo.bufferTimes,player->syncControl.bufferInfo.lastBufferDuration);
    }else{
        GJLOG(GJ_LOGDEBUG, "stopBuffering when status not buffering");
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    
}
GVoid GJLivePlay_CheckWater(GJLivePlayer* player){

    GJPlayControl* _playControl = &player->playControl;
    GJSyncControl* _syncControl = &player->syncControl;
    GLong cache;
    if (_playControl->status == kPlayStatusBuffering) {
        if(_syncControl->syncType == kTimeSYNCAudio){
            GLong vCache = _syncControl->videoInfo.trafficStatus.leave.pts - _syncControl->videoInfo.trafficStatus.leave.pts;
            GLong aCache = _syncControl->audioInfo.trafficStatus.enter.pts - _syncControl->audioInfo.trafficStatus.leave.pts;
            cache = aCache;
            if ((aCache == 0 && vCache >= _syncControl->bufferInfo.lowWaterFlag) || vCache >= _syncControl->bufferInfo.highWaterFlag-300) {
                GJLOG(GJ_LOGWARNING, "音频缓冲过程中，音频为空视频足够、或者视频足够大于音频。切换到视频同步");
                changeSyncType(_syncControl, kTimeSYNCVideo);
                GJLivePlay_StopBuffering(player);
                return;
            }
        }else{
            cache = _syncControl->videoInfo.trafficStatus.enter.pts - _syncControl->videoInfo.trafficStatus.leave.pts;
        }
//        GLong duration = (GLong)(GJ_Gettime()/1000) - _syncControl->bufferInfo.lastPauseFlag;
        if (cache < _syncControl->bufferInfo.lowWaterFlag){
            player->callback(player->userDate,GJPlayMessage_BufferUpdate,GNULL);
        }else{
            GJLOG(GJ_LOGDEBUG, "缓冲结束");
            player->callback(player->userDate,GJPlayMessage_BufferEnd,GNULL);
            GJLivePlay_StopBuffering(player);
        }
    }else if (_playControl->status == kPlayStatusRunning){
        if(_syncControl->syncType == kTimeSYNCAudio){
            cache = _syncControl->audioInfo.trafficStatus.enter.pts - _syncControl->audioInfo.trafficStatus.leave.pts;
        }else{
            cache = _syncControl->videoInfo.trafficStatus.leave.pts - _syncControl->videoInfo.trafficStatus.leave.pts;
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
GBool GJAudioDrivePlayerCallback(GJLivePlayer *player,void *data ,GInt32* outSize){
    GJPlayControl* _playControl = &player->playControl;
    GJSyncControl* _syncControl = &player->syncControl;
    R_GJPCMFrame* audioBuffer;
    if (_playControl->status == kPlayStatusRunning && queuePop(_playControl->audioQueue, (GHandle*)&audioBuffer, 0)) {
        *outSize = audioBuffer->retain.size;
        memcpy(data, audioBuffer->retain.data, *outSize);
        _syncControl->audioInfo.trafficStatus.leave.pts = (GLong)audioBuffer->pts;
        _syncControl->audioInfo.trafficStatus.leave.count++;
        _syncControl->audioInfo.cPTS = (GLong)audioBuffer->pts;
        _syncControl->audioInfo.clock = GJ_Gettime()/1000;
        GJLOGFREQ("audio show pts:%d",audioBuffer->pts);
        retainBufferUnRetain(&audioBuffer->retain);
        GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioBuffer);
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
    queuePeekWaitValue(_playControl->imageQueue, 2, (GHandle*)&watiBuffer, GINT32_MAX);///等待至少两帧
    _syncControl->videoInfo.startTime = GJ_Gettime() / 1000;
    while ((_playControl->status != kPlayStatusStop)) {
        if (queuePop(_playControl->imageQueue, (GHandle*)&cImageBuf,_playControl->status == kPlayStatusBuffering?GINT32_MAX:0)) {
            if (_playControl->status == kPlayStatusStop){
                retainBufferUnRetain(&cImageBuf->retain);
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
                    GJLivePlay_StartBuffering(player);
                }else{
                    GJLOG(GJ_LOGWARNING, "video play queue empty when kTimeSYNCAudio,do not buffer");
                }
            }
            usleep(30*1000);
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
                R_GJPixelFrame* nextBuffer = {0};
                GBool peekResult = GFalse;
                while ((peekResult = queuePeekWaitCopyValue(_playControl->imageQueue, 0, (GHandle)&nextBuffer, sizeof(R_GJPixelFrame), VIDEO_PTS_PRECISION))) {
                    if(nextBuffer->pts < cImageBuf->pts){
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
            _syncControl->bufferInfo.speedTotalDuration += (_syncControl->speed - 1.0)*(GJ_Gettime() / 1000.0-_syncControl->videoInfo.clock);
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
        GJLOGFREQ("video show pts:%d",cImageBuf->pts);
        player->videoPlayer.displayView(&player->videoPlayer,&cImageBuf->retain);
#endif
    DROP:
        _syncControl->videoInfo.trafficStatus.leave.count++;
        retainBufferUnRetain(&cImageBuf->retain);
        GJBufferPoolSetData(defauleBufferPool(), (GHandle)cImageBuf);
        cImageBuf = GNULL;
    }
ERROR:
    GJLOG(GJ_LOGINFO, "playRunLoop out");
    _playControl->status = kPlayStatusStop;
    _playControl->playVideoThread = nil;
    return GNULL;
}


GBool  GJLivePlay_InjectVideoPlayer(GJLivePlayer* player,const GJPictureDisplayContext* videoPlayer){
    player->videoPlayer = *videoPlayer;
    return GTrue;
}
GBool  GJLivePlay_InjectAudioPlayer(GJLivePlayer* player,const GJAudioPlayContext* audioPlayer,GJAudioFormat format){
    player->audioPlayer = *audioPlayer;
    player->audioFormat = format;
    return GTrue;
}

GBool  GJLivePlay_Create(GJLivePlayer* player,GJLivePlayCallback callback,GHandle userData){
    if (player == GNULL) {
        player = (GJLivePlayer*)malloc(sizeof(GJLivePlayer));
    }
    player->callback = callback;
    player->userDate = userData;
    player->playControl.status = kPlayStatusStop;
    pthread_mutex_init(&player->playControl.oLock, GNULL);
    queueCreate(&player->playControl.imageQueue, VIDEO_MAX_CACHE_COUNT, GTrue, GTrue);//150为暂停时视频最大缓冲
    queueCreate(&player->playControl.audioQueue, AUDIO_MAX_CACHE_COUNT, GTrue, GTrue);
    
    return GTrue;
}
GBool  GJLivePlay_Start(GJLivePlayer* player){
    GBool result = GTrue;
    pthread_mutex_lock(&player->playControl.oLock);
    if (player->playControl.status != kPlayStatusStop) {
        GJLOG(GJ_LOGINFO, "GJLivePlayer start");
        memset(&player->syncControl, 0, sizeof(player->syncControl));
        player->playControl.status = kPlayStatusRunning;
        player->syncControl.videoInfo.startPts = player->syncControl.audioInfo.startPts = G_TIME_INVALID;
        player->syncControl.speed = 1.0;
        player->syncControl.bufferInfo.lowWaterFlag = MIN_CACHE_DUR;
        player->syncControl.bufferInfo.highWaterFlag = MAX_CACHE_DUR;
        player->syncControl.syncType = kTimeSYNCVideo;
        queueEnablePush(player->playControl.imageQueue, GTrue);
        queueEnablePush(player->playControl.audioQueue, GTrue);
    }else{
        GJLOG(GJ_LOGWARNING, "GJLivePlayer 重复 start");
    }
    pthread_mutex_unlock(&player->playControl.oLock);
    return result;
}
GVoid  GJLivePlay_Stop(GJLivePlayer* player){
    GJLivePlay_StartBuffering(player);
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
        player->audioPlayer.audioStop(&player->audioPlayer);
        GInt32 vlength = queueGetLength(player->playControl.imageQueue);
        GInt32 alength = queueGetLength(player->playControl.audioQueue);
        
        if (vlength > 0) {
            R_GJPixelFrame** imageBuffer = (R_GJPixelFrame**)malloc(sizeof(R_GJPixelFrame*)*vlength);
            //不能用queuePop，因为已经enable false;
            if (queueClean(player->playControl.imageQueue, (GHandle*)imageBuffer, &vlength)) {
                for (GInt32 i = 0; i < vlength; i++) {
                    retainBufferUnRetain(&imageBuffer[i]->retain);
                    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)imageBuffer[i]);
                }
            }else{
                GJLOG(GJ_LOGFORBID, "videoClean Error");
            }
            free(imageBuffer);
        }
        GJLOG(GJ_LOGDEBUG, "video player queue clean over");
        if (alength > 0) {
            R_GJPCMFrame** audioBuffer = (R_GJPCMFrame**)malloc(sizeof(R_GJPCMFrame*)*alength);
            if (queueClean(player->playControl.audioQueue, (GHandle*)audioBuffer, &alength)) {
                for (GInt32 i = 0; i < alength; i++) {
                    retainBufferUnRetain(&audioBuffer[i]->retain);
                    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)audioBuffer[i]);
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
GBool  GJLivePlay_AddVideoData(GJLivePlayer* player,R_GJPixelFrame* videoFrame){

    GJLOGFREQ("收到音频 PTS:%lld",videoFrame);
    if (videoFrame->pts < player->syncControl.videoInfo.trafficStatus.enter.pts) {
        pthread_mutex_lock(&player->playControl.oLock);
        GInt32 length = queueGetLength(player->playControl.imageQueue);
        GJLOG(GJ_LOGWARNING, "视频pts不递增，抛弃之前的视频帧：%ld帧",length);
        R_GJPixelFrame** imageBuffer = (R_GJPixelFrame**)malloc(length*sizeof(R_GJPixelFrame*));
        queueBroadcastPop(player->playControl.imageQueue);//other lock
        if(queueClean(player->playControl.imageQueue, (GHandle*)imageBuffer, &length)){
            for (GUInt32 i = 0; i<length; i++) {
                retainBufferUnRetain(&imageBuffer[i]->retain);
                GJBufferPoolSetData(defauleBufferPool(), (uint8_t*)imageBuffer[i]);
            }
        }
        if (imageBuffer) {
            free(imageBuffer);
        }
        player->syncControl.videoInfo.trafficStatus.leave.pts = (GLong)videoFrame->pts;
        pthread_mutex_unlock(&player->playControl.oLock);
    }
    
    if(player->playControl.status == kPlayStatusStop){
        GJLOG(GJ_LOGWARNING, "播放器stop状态收到视频帧，直接丢帧");
        return GFalse;
    }
    if (player->playControl.playVideoThread == GNULL) {

        player->syncControl.videoInfo.startPts = (GLong)videoFrame->pts;
        player->syncControl.videoInfo.trafficStatus.leave.pts = (GLong)videoFrame->pts;///防止videoInfo.startPts不为从0开始时，videocache过大，
        
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
        player->syncControl.videoInfo.trafficStatus.enter.pts = (GLong)videoFrame->pts;
        player->syncControl.videoInfo.trafficStatus.enter.count++;
#ifdef NETWORK_DELAY
        GUInt32 date = [[NSDate date]timeIntervalSince1970]*1000;
        player->syncControl.networkDelay = date - player->syncControl.videoInfo.trafficStatus.enter.pts;
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
            GJBufferPoolSetData(defauleBufferPool(), (GHandle)oldBuffer);
            goto RETRY;
        }else{
            GJLOG(GJ_LOGFORBID,"full player audio queue pop error");
            retainBufferUnRetain(&videoFrame->retain);
            GJBufferPoolSetData(defauleBufferPool(), (uint8_t*)videoFrame);
            result = GFalse;
        }
    }
    return result;
}
GBool  GJLivePlay_AddAudioData(GJLivePlayer* player,R_GJPCMFrame* audioFrame){
    GJLOGFREQ("收到音频 PTS:%lld",audioFrame->pts);
    GJPlayControl* _playControl = &(player->playControl);
    GJSyncControl* _syncControl = &(player->syncControl);
    GBool result = GTrue;
    if (audioFrame->pts < _syncControl->audioInfo.trafficStatus.leave.pts) {
        pthread_mutex_lock(&_playControl->oLock);
        GJLOG(GJ_LOGWARNING, "音频pts不递增，抛弃之前的音频帧：%ld帧",queueGetLength(_playControl->audioQueue));
        
        queueBroadcastPop(_playControl->audioQueue);//other lock
        GInt32 qLength = queueGetLength(_playControl->audioQueue);
        if(qLength > 0){
            R_GJPCMFrame** audioBuffer = (R_GJPCMFrame**)malloc(qLength*sizeof(R_GJPCMFrame*));
            queueClean(_playControl->audioQueue, (GVoid**)audioBuffer, &qLength);//用clean，防止播放断同时也在读
            for (GUInt32 i = 0; i<qLength; i++) {
                _syncControl->audioInfo.trafficStatus.leave.count++;
                _syncControl->audioInfo.trafficStatus.leave.byte += audioBuffer[i]->retain.size;
                retainBufferUnRetain(&audioBuffer[i]->retain);
                GJBufferPoolSetData(defauleBufferPool(), (uint8_t*)audioBuffer[i]);
            }
            free(audioBuffer);
        }
        _syncControl->audioInfo.trafficStatus.leave.pts = (GLong)audioFrame->pts;//防止此时获得audioCache时误差太大，
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
        if (_playControl->status == kPlayStatusBuffering) {
            GJLivePlay_StopBuffering(player);
        }
        changeSyncType(_syncControl, kTimeSYNCAudio);
        _syncControl->audioInfo.trafficStatus.leave.pts = (GLong)audioFrame->pts;///防止audioInfo.startPts不为从0开始时，audiocache过大，
    }
    {
        //收集网络抖动
        GInt32 clock = GJ_Gettime()/1000;
        GInt32 unitClockDif = clock - _syncControl->netShake.collectUnitEndClock;
        GInt32 unitPtsDif = (GInt32)(audioFrame->pts - _syncControl->audioInfo.trafficStatus.enter.pts);
        GInt32 preShake = _syncControl->netShake.collectUnitPtsCache - _syncControl->netShake.collectUnitEndClock + _syncControl->netShake.collectUnitStartClock;
        GInt32 currentShake = unitPtsDif - unitClockDif;
        if ((currentShake >= -10.0 && preShake >= -10.0) || (currentShake <= 10.0 && preShake <= 10.0)) {
            _syncControl->netShake.collectUnitEndClock = clock;
            _syncControl->netShake.collectUnitPtsCache += unitPtsDif;
        }else{
            GInt32 totalShake = _syncControl->netShake.collectUnitPtsCache - clock + _syncControl->netShake.collectUnitStartClock;
            if (_syncControl->netShake.minShake > totalShake){
                _syncControl->netShake.minShake = totalShake;
                _syncControl->bufferInfo.lowWaterFlag = MIN(MAX(MIN_CACHE_DUR,-totalShake*2),MAX_CACHE_DUR);
                _syncControl->bufferInfo.highWaterFlag = _syncControl->bufferInfo.lowWaterFlag*3;
                
                GJLOG(GJ_LOGINFO, "preShake:%d,currentShake:%d,totalShake:%d,重置lowWaterFlag：%d，highWaterFlag：%d",preShake,currentShake,totalShake,_syncControl->bufferInfo.lowWaterFlag,_syncControl->bufferInfo.highWaterFlag);
                
                if (_syncControl->bufferInfo.lowWaterFlag > _syncControl->bufferInfo.highWaterFlag) {
                    GJLOG(GJ_LOGFORBID, "lowAudioWaterFlag 大于 highAudioWaterFlag怎么可能！！！");
                    _syncControl->bufferInfo.highWaterFlag = _syncControl->bufferInfo.lowWaterFlag;
                }
            }else{
                GJLOGFREQ("pull net shake:%d,but not affect",totalShake);
            }
            _syncControl->netShake.collectUnitStartClock = _syncControl->netShake.collectUnitEndClock;
            _syncControl->netShake.collectUnitEndClock = clock;
            _syncControl->netShake.collectUnitPtsCache = unitPtsDif;
            
            if (clock - _syncControl->netShake.collectStartClock >= UPDATE_SHAKE_TIME) {
                if (totalShake > 0) {
                    _syncControl->netShake.maxShake = totalShake;
                    _syncControl->netShake.minShake = MIN_CACHE_DUR;
                }else{
                    _syncControl->netShake.minShake = totalShake;
                    _syncControl->netShake.maxShake = MAX_CACHE_DUR;
                }
                _syncControl->netShake.collectStartClock = _syncControl->netShake.collectUnitStartClock;
                GJLOG(GJ_LOGINFO, "更新网络抖动收集 startClock:%d",_syncControl->netShake.collectStartClock);
            }
        }
    }
    if (player->audioPlayer.obaque == GNULL) {
        _syncControl->audioInfo.startPts = (GLong)audioFrame->pts;
        _syncControl->audioInfo.trafficStatus.leave.pts = (GLong)audioFrame->pts;///防止audioInfo.startPts不为从0开始时，audiocache过大，
        //防止视频先到，导致时差特别大
        _syncControl->audioInfo.cPTS = (GLong)audioFrame->pts;
        _syncControl->audioInfo.clock = GJ_Gettime()/1000;
        pthread_mutex_lock(&_playControl->oLock);//此时禁止开启和停止
        if (_playControl->status != kPlayStatusStop) {
            player->audioPlayer.audioPlayCreate(&player->audioPlayer,player->audioFormat);
            player->audioPlayer.audioStart(&player->audioPlayer);
            _syncControl->audioInfo.startTime = GJ_Gettime()/1000.0;
        }
        pthread_mutex_unlock(&_playControl->oLock);
    }
    retainBufferRetain(&audioFrame->retain);
RETRY:
    if(queuePush(_playControl->audioQueue, audioFrame, 0)){
        _syncControl->audioInfo.trafficStatus.enter.pts = (GLong)audioFrame->pts;
        _syncControl->audioInfo.trafficStatus.enter.count++;
        _syncControl->audioInfo.trafficStatus.enter.byte += audioFrame->retain.size;
        
#ifdef NETWORK_DELAY
        GUInt32 date = [[NSDate date]timeIntervalSince1970]*1000;
        _syncControl.networkDelay = date - _syncControl.audioInfo.trafficStatus.enter.pts;
#endif
        GJLivePlay_CheckWater(player);
        result =  GTrue;
    }else if(_playControl->status == kPlayStatusStop){
        GJLOG(GJ_LOGWARNING,"player audio data push while stop,drop");
        retainBufferUnRetain(&audioFrame->retain);
        GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioFrame);
        result = GFalse;
    }else{
        GJLOG(GJ_LOGWARNING, "audio player queue full,update oldest frame   ，正常情况不可能出现的case");
        R_GJPCMFrame* oldBuffer = GNULL;
        if (queuePop(_playControl->audioQueue, (GHandle*)&oldBuffer, 0)) {
            retainBufferUnRetain(&oldBuffer->retain);
            GJBufferPoolSetData(defauleBufferPool(), (GHandle)oldBuffer);
            goto RETRY;
        }else{
            GJLOG(GJ_LOGFORBID,"full player audio queue pop error");
            retainBufferUnRetain(&audioFrame->retain);
            GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioFrame);
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

GVoid  GJLivePlay_GetVideoDisplayView(GJLivePlayer* player){
    
}

GVoid  GJLivePlay_Release(GJLivePlayer* player){
    GJLOG(GJ_LOGDEBUG, "GJPlivePlayer dealloc");
    queueFree(&player->playControl.audioQueue);
    queueFree(&player->playControl.imageQueue);
}

//
//typedef struct _GJImageBuffer{
//    CVImageBufferRef image;
//    GInt64           pts;
//}GJImageBuffer;
//typedef struct _GJAudioBuffer{
//    GJRetainBuffer* audioData;
//    GInt64           pts;
//}GJAudioBuffer;
//@interface GJLivePlayer()<GJAudioQueueDrivePlayerDelegate>{
//    
//    
//    
//#ifdef GJAUDIOQUEUEPLAY
//    GJAudioQueuePlayer* _audioTestPlayer;
//#endif
//}
//#ifndef UIIMAGE_SHOW
//@property(strong,nonatomic)GJImagePixelImageInput*          imageInput;
//#endif
//@property(strong,nonatomic)GJAudioQueueDrivePlayer*         audioPlayer;
//@property(strong,nonatomic)GJImageView*                     displayView;
//
//@property(assign,nonatomic)GJSyncControl       syncControl;
//@property(assign,nonatomic)GJPlayControl       playControl;
////@property(assign,nonatomic)GJNetShakeControl   shakeControl;
//@end
//@implementation GJLivePlayer
//
//
//
//
//static GHandle playVideoRunLoop(GHandle parm){
//    pthread_setname_np("playVideoRunLoop");
//    GJLivePlayer* player = (__bridge GJLivePlayer *)(parm);
//    GJPlayControl* _playControl = &(player->_playControl);
//    GJSyncControl* _syncControl = &(player->_syncControl);
//    GJImageBuffer* cImageBuf;
//  
//    cImageBuf = GNULL;
//    
//    GJLOG(GJ_LOGDEBUG, "start play runloop");
//    GJImageBuffer watiBuffer[2] = {0};
//    queuePeekWaitValue(_playControl->imageQueue, 2, (GHandle*)&watiBuffer, GINT32_MAX);///等待至少两帧
//    _syncControl->videoInfo.startTime = GJ_Gettime() / 1000;
//    while ((_playControl->status != kPlayStatusStop)) {
//        if (queuePop(_playControl->imageQueue, (GHandle*)&cImageBuf,_playControl->status == kPlayStatusBuffering?INT_MAX:0)) {
//            if (_playControl->status == kPlayStatusStop){
//               CVPixelBufferRelease(cImageBuf->image);
//               GJBufferPoolSetData(defauleBufferPool(), (GHandle)cImageBuf);
//               cImageBuf = GNULL;
//               break;
//            }
//        }else{
//            if (_playControl->status == kPlayStatusStop) {
//                break;
//            }else if (_playControl->status == kPlayStatusRunning){
//                if(_syncControl->syncType == kTimeSYNCVideo){
//                    GJLOG(GJ_LOGDEBUG, "video play queue empty when kTimeSYNCVideo,start buffer");
//                    [player buffering];
//                }else{
//                    GJLOG(GJ_LOGWARNING, "video play queue empty when kTimeSYNCAudio,do not buffer");
//                }
//            }
//            usleep(30*1000);
//            continue;
//        }
//        
//        GLong timeStandards = getClockLine(_syncControl);
//        GLong delay = (GLong)cImageBuf->pts - timeStandards;
//
//        if(delay > VIDEO_PTS_PRECISION) {
//            if (_playControl->status == kPlayStatusStop) {
//                goto DROP;
//            }
//            if(_syncControl->syncType == kTimeSYNCVideo){
//                GJLOG(GJ_LOGWARNING, "视频等待视频时间过长 delay:%ld PTS:%ld clock:%ld,重置同步管理",delay,cImageBuf->pts,timeStandards);
//                resetSyncToStartPts(_syncControl, (GLong)cImageBuf->pts);
//                delay = 0;
//            }else{
//                GJLOG(GJ_LOGWARNING, "视频等待音频时间过长 delay:%ld PTS:%ld clock:%ld，等待下一帧做判断处理",delay,cImageBuf->pts,timeStandards);
//                GJImageBuffer nextBuffer = {0};
//                GBool peekResult = GFalse;
//                while ((peekResult = queuePeekWaitCopyValue(_playControl->imageQueue, 0, (GHandle)&nextBuffer, sizeof(GJImageBuffer), VIDEO_PTS_PRECISION))) {
//                    if(nextBuffer.pts < cImageBuf->pts){
//                        GJLOG(GJ_LOGWARNING, "视频PTS重新开始，直接显示");
//                        delay = 0;
//                        break;
//                    }else{
//                        timeStandards = getClockLine(_syncControl);
//                        delay = (GLong)cImageBuf->pts - timeStandards;
//                        if (delay > 30 * 1000) {
//                            usleep(30 * 1000);
//                        }else{
//                            GJLOG(GJ_LOGWARNING, "视频长时间等待音频结束");
//                            break;
//                        }
//                    }
//                }
//                if (!peekResult) {
//                    GJLOG(GJ_LOGWARNING, "视频等待音频时间过长,并且没有下一帧，直接显示");
//                    delay = 0;
//                    goto DROP;
//                }
//            }
//        }else if (delay < -VIDEO_PTS_PRECISION){
//            if(_syncControl->syncType == kTimeSYNCVideo){
//                GJLOG(GJ_LOGWARNING, "视频落后视频严重，delay：%ld, PTS:%ld clock:%ld，重置同步管理",delay,cImageBuf->pts,timeStandards);
//                resetSyncToStartPts(_syncControl, (GLong)cImageBuf->pts);
//                delay = 0;
//            }else{
//                GJLOG(GJ_LOGWARNING, "视频落后音频严重，delay：%ld, PTS:%ld clock:%ld，丢视频帧",delay,cImageBuf->pts,timeStandards);
//                _syncControl->videoInfo.cPTS = (GLong)cImageBuf->pts;
//                _syncControl->videoInfo.trafficStatus.leave.pts = (GLong)cImageBuf->pts;
//                _syncControl->videoInfo.clock = GJ_Gettime() / 1000;
//                goto DROP;
//            }
//        }
//    DISPLAY:
//        if (delay > 20) {
//            GJLOGFREQ("play wait:%d, video pts:%ld",delay,_syncControl->videoInfo.cPTS);
//            usleep((GUInt32)delay * 1000);
//        }
//        
//        if (_syncControl->speed > 1.0) {
//            _syncControl->bufferInfo.speedTotalDuration += (_syncControl->speed - 1.0)*(GJ_Gettime() / 1000.0-_syncControl->videoInfo.clock);
//        }
//        
//        _syncControl->videoInfo.clock = GJ_Gettime() / 1000;
//        _syncControl->videoInfo.trafficStatus.leave.pts = (GLong)cImageBuf->pts;
//        _syncControl->videoInfo.cPTS = (GLong)cImageBuf->pts;
//        
//
//
//#ifdef UIIMAGE_SHOW
//        {
//            CIImage* cimage = [CIImage imageWithCVPixelBuffer:cImageBuf->image];
//            UIImage* image = [UIImage imageWithCIImage:cimage];
//            // Update the display with the captured image for DEBUG purposes
//            dispatch_async(dispatch_get_main_queue(), ^{
//                ( (UIImageView*)player.displayView).image = image;
//            });
//        }
//#else
//        GJLOGFREQ("video show pts:%d",cImageBuf->pts);
//        [player.imageInput updateDataWithImageBuffer:cImageBuf->image timestamp: CMTimeMake(cImageBuf->pts, 1000)];
//        
//#endif
//    DROP:
//        _syncControl->videoInfo.trafficStatus.leave.count++;
//        CVPixelBufferRelease(cImageBuf->image);
//
//        GJBufferPoolSetData(defauleBufferPool(), (GHandle)cImageBuf);
//        cImageBuf = GNULL;
//    }
//ERROR:
//    GJLOG(GJ_LOGINFO, "playRunLoop out");
//    _playControl->status = kPlayStatusStop;
//    _playControl->playVideoThread = nil;
//    return GNULL;
//}
//- (instancetype)init
//{
//    self = [super init];
//    if (self) {
//        memset(&_audioFormat, 0, sizeof(_audioFormat));
// 
//        _playControl.status = kPlayStatusStop;
//        
//
//
//        pthread_mutex_init(&_playControl.oLock, GNULL);
//        
//#ifdef UIIMAGE_SHOW
//        _displayView = (GJImageView*)[[UIImageView alloc]init];
//#else
//    _displayView = [[GJImageView alloc]init];
//#endif
//        queueCreate(&_playControl.imageQueue, VIDEO_MAX_CACHE_COUNT, GTrue, GTrue);//150为暂停时视频最大缓冲
//        queueCreate(&_playControl.audioQueue, AUDIO_MAX_CACHE_COUNT, GTrue, GTrue);
//    }
//    return self;
//}
//-(UIView *)displayView{
//    return _displayView;
//}
//
//-(void)start{
//    pthread_mutex_lock(&_playControl.oLock);
//    GJLOG(GJ_LOGINFO, "GJLivePlayer start");
//    memset(&_syncControl, 0, sizeof(_syncControl));
//
//    _playControl.status = kPlayStatusRunning;
//    
//    _syncControl.videoInfo.startPts = _syncControl.audioInfo.startPts = LONG_MAX;
//    _syncControl.speed = 1.0;
//    _syncControl.bufferInfo.lowWaterFlag = MIN_CACHE_DUR;
//    _syncControl.bufferInfo.highWaterFlag = MAX_CACHE_DUR;
//    _syncControl.syncType = kTimeSYNCVideo;
//    
//    queueEnablePush(_playControl.imageQueue, GTrue);
//    queueEnablePush(_playControl.audioQueue, GTrue);
//    pthread_mutex_unlock(&_playControl.oLock);
//}
//-(void)stop{
//    [self stopBuffering];
//    if(_playControl.status != kPlayStatusStop){
//        GJLOG(GJ_LOGINFO, "gjliveplayer stop start");
//        pthread_mutex_lock(&_playControl.oLock);
//        _playControl.status = kPlayStatusStop;
//        queueEnablePush(_playControl.audioQueue, GFalse);
//        queueEnablePush(_playControl.imageQueue, GFalse);
//        
//        queueBroadcastPop(_playControl.imageQueue);
//        queueBroadcastPop(_playControl.audioQueue);
//        pthread_mutex_unlock(&_playControl.oLock);
//
//        pthread_join(_playControl.playVideoThread, GNULL);
//
//        pthread_mutex_lock(&_playControl.oLock);
//        [_audioPlayer stop:true];
//        _audioPlayer = nil;
//        GInt32 vlength = queueGetLength(_playControl.imageQueue);
//        GInt32 alength = queueGetLength(_playControl.audioQueue);
//        
//        if (vlength > 0) {
//            GJImageBuffer** imageBuffer = (GJImageBuffer**)malloc(sizeof(GJImageBuffer*)*vlength);
//            //不能用queuePop，因为已经enable false;
//            if (queueClean(_playControl.imageQueue, (GHandle*)imageBuffer, &vlength)) {
//                for (GInt32 i = 0; i < vlength; i++) {
//                    CVPixelBufferRelease(imageBuffer[i]->image);
//                    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)imageBuffer[i]);
//                }
//            }else{
//                GJLOG(GJ_LOGFORBID, "videoClean Error");
//            }
//            free(imageBuffer);
////            while (queuePop(_playControl.imageQueue, (GVoid**)&imageBuffer, 0)) {
////                CVPixelBufferRelease(imageBuffer->image);
////                GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)imageBuffer);
////            }
//        }
//        GJLOG(GJ_LOGDEBUG, "video player queue clean over");
//        if (alength > 0) {
//            GJAudioBuffer** audioBuffer = (GJAudioBuffer**)malloc(sizeof(GJAudioBuffer*)*alength);
//            if (queueClean(_playControl.audioQueue, (GHandle*)audioBuffer, &alength)) {
//                for (GInt32 i = 0; i < alength; i++) {
//                    retainBufferUnRetain(audioBuffer[i]->audioData);
//                    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)audioBuffer[i]);
//                }
//            }else{
//                GJLOG(GJ_LOGFORBID, "audioClean Error");
//            }
//            free(audioBuffer);
//        }
//        GJLOG(GJ_LOGDEBUG, "audio player queue clean over");
//        pthread_mutex_unlock(&_playControl.oLock);
//        
//    }else{
//        GJLOG(GJ_LOGWARNING, "重复停止");
//    }
//    
//}
////-(void)pause{
////
////    _playControl.status = kPlayStatusPause;
////    _lastPauseFlag = getTime() / 1000;
////    
////    queueSetMixCacheSize(_playControl.imageQueue, VIDEO_MAX_CACHE_COUNT);
////    [_audioPlayer pause];
////    queueLockPop(_playControl.imageQueue);
////    queueWaitPop(_playControl.imageQueue, INT_MAX);
////    queueUnLockPop(_playControl.imageQueue);
////    [_oLock lock];
////
////}
////-(void)resume{
////    if (_playControl.status == kPlayStatusPause) {
////        _playControl.status = kPlayStatusRunning;
////         GJLOG(GJ_LOGINFO,"buffer total:%d\n",_bufferTime);
////        queueSetMixCacheSize(_playControl.imageQueue,0);
////        if (_lastPauseFlag != 0) {
////            _bufferTime += getTime() / 1000 - _lastPauseFlag;
////            _lastPauseFlag = 0;
////        }else{
////            GJLOG(GJ_LOGWARNING, "暂停管理出现问题");
////        }
////        [_audioPlayer flush];
////        [_audioPlayer resume];
////    }else{
////        GJLOG(GJ_LOGDEBUG, "resume when status not pause");
////    }
////}
//-(void)buffering{
//    pthread_mutex_lock(&_playControl.oLock);
//    if(_playControl.status == kPlayStatusRunning){
//        GJLOG(GJ_LOGDEBUG, "start buffing");
//        _playControl.status = kPlayStatusBuffering;
//        _syncControl.bufferInfo.lastPauseFlag = GJ_Gettime() / 1000;
//        [_audioPlayer pause];
//        if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
//            [self.delegate livePlayer:self bufferUpdatePercent:0.0 duration:0.0];
//        }
//        queueSetMinCacheSize(_playControl.imageQueue, VIDEO_MAX_CACHE_COUNT);
//        queueSetMinCacheSize(_playControl.audioQueue, AUDIO_MAX_CACHE_COUNT);
//    }else{
//        GJLOG(GJ_LOGDEBUG, "buffer when status not in running");
//    }
//    pthread_mutex_unlock(&_playControl.oLock);
//}
//-(void)stopBuffering{
//    pthread_mutex_lock(&_playControl.oLock);
//    if (_playControl.status == kPlayStatusBuffering) {
//        _playControl.status = kPlayStatusRunning;
//        queueSetMinCacheSize(_playControl.imageQueue, 0);
//        queueBroadcastPop(_playControl.imageQueue);
//        queueSetMinCacheSize(_playControl.audioQueue, 0);
//        queueBroadcastPop(_playControl.audioQueue);
//        if (_syncControl.bufferInfo.lastPauseFlag != 0) {
//            _syncControl.bufferInfo.lastBufferDuration = GJ_Gettime() / 1000 - _syncControl.bufferInfo.lastPauseFlag;
//            _syncControl.bufferInfo.bufferTotalDuration += _syncControl.bufferInfo.lastBufferDuration;
//            _syncControl.bufferInfo.bufferTimes++;
//            _syncControl.bufferInfo.lastPauseFlag = 0;
//        }else{
//            GJLOG(GJ_LOGFORBID, "暂停管理出现问题");
//        }
//        _syncControl.videoInfo.clock = _syncControl.audioInfo.clock = GJ_Gettime()/1000;
//        [_audioPlayer resume];
//        GJLOG(GJ_LOGINFO, "buffing times:%d useDuring:%d",_syncControl.bufferInfo.bufferTimes,_syncControl.bufferInfo.lastBufferDuration);
//    }else{
//        GJLOG(GJ_LOGDEBUG, "stopBuffering when status not buffering");
//    }
//    pthread_mutex_unlock(&_playControl.oLock);
//}
//-(void)dewatering{
////    return;
//    pthread_mutex_lock(&_playControl.oLock);
//    if (_playControl.status == kPlayStatusRunning) {
//        if (_syncControl.speed<=1.0) {
//            GJLOG(GJ_LOGDEBUG, "startDewatering");
//            _syncControl.speed = 1.2;
//            _audioPlayer.speed = _syncControl.speed;
//        }
//    }
//    pthread_mutex_unlock(&_playControl.oLock);
//}
//-(void)stopDewatering{
////    return;
//    pthread_mutex_lock(&_playControl.oLock);
//    if (_syncControl.speed > 1.0) {
//        GJLOG(GJ_LOGDEBUG, "stopDewatering");
//        _syncControl.speed = 1.0;
//        _audioPlayer.speed = _syncControl.speed;
//    }
//    pthread_mutex_unlock(&_playControl.oLock);
//}
//-(GJTrafficStatus)getAudioCache{
//   
//    return _syncControl.audioInfo.trafficStatus;
//}
//-(GJTrafficStatus)getVideoCache{
//    return _syncControl.videoInfo.trafficStatus;
//}
//#ifdef NETWORK_DELAY
//-(GLong)getNetWorkDelay{
//    return _syncControl.networkDelay;
//}
//#endif
//
//-(void)checkBufferingAndWater{
////    GLong alength = queueGetLength(_playControl.audioQueue);
////    GLong vlength = queueGetLength(_playControl.imageQueue);
//    GLong cache;
//    if (_playControl.status == kPlayStatusBuffering) {
//        if(_syncControl.syncType == kTimeSYNCAudio){
//            GLong vCache = _syncControl.videoInfo.trafficStatus.leave.pts - _syncControl.videoInfo.trafficStatus.leave.pts;
//            GLong aCache = _syncControl.audioInfo.trafficStatus.enter.pts - _syncControl.audioInfo.trafficStatus.leave.pts;
//            cache = aCache;
//            if ((aCache == 0 && vCache >= _syncControl.bufferInfo.lowWaterFlag) || vCache >= _syncControl.bufferInfo.highWaterFlag-300) {
//                GJLOG(GJ_LOGWARNING, "音频缓冲过程中，音频为空视频足够、或者视频足够大于音频。切换到视频同步");
//                changeSyncType(&_syncControl, kTimeSYNCVideo);
//                [self stopBuffering];
//                return;
//            }
//        }else{
//            cache = _syncControl.videoInfo.trafficStatus.enter.pts - _syncControl.videoInfo.trafficStatus.leave.pts;
//        }
//        GLong duration = (GLong)(GJ_Gettime()/1000) - _syncControl.bufferInfo.lastPauseFlag;
//        if (cache < _syncControl.bufferInfo.lowWaterFlag){
//            if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
//                [self.delegate livePlayer:self bufferUpdatePercent:cache*1.0/_syncControl.bufferInfo.lowWaterFlag duration:duration];
//            }
//        }else{
//            if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
//                GJLOG(GJ_LOGDEBUG, "缓冲结束");
//                GJLOG(GJ_LOGINFO, "buffer percent:%f A cacheTime:%ld",1.0,cache);
//                [self.delegate livePlayer:self bufferUpdatePercent:1.0 duration:duration];
//            }
//            [self stopBuffering];
//        }
//    }else if (_playControl.status == kPlayStatusRunning){
//        if(_syncControl.syncType == kTimeSYNCAudio){
//            cache = _syncControl.audioInfo.trafficStatus.enter.pts - _syncControl.audioInfo.trafficStatus.leave.pts;
//        }else{
//            cache = _syncControl.videoInfo.trafficStatus.leave.pts - _syncControl.videoInfo.trafficStatus.leave.pts;
//        }
//        if (cache > _syncControl.bufferInfo.highWaterFlag ) {
//            if (_syncControl.speed <= 1.0) {
//                [self dewatering];
//            }
//        }else if (cache < _syncControl.bufferInfo.lowWaterFlag ){
//            if (_syncControl.speed >1.0) {
//                [self stopDewatering];
//            }
//        }
//    }
//
////    if(_syncControl.syncType == kTimeSYNCAudio){
////        if (_playControl.status == kPlayStatusBuffering){
////            GLong vCache = _syncControl.videoInfo.trafficStatus.leave.pts - _syncControl.videoInfo.trafficStatus.leave.pts;
////            GLong aCache = _syncControl.audioInfo.trafficStatus.enter.pts - _syncControl.audioInfo.trafficStatus.leave.pts;
////            
////            if ((aCache == 0 && vCache >= _syncControl.bufferInfo.lowWaterFlag) || vCache >= _syncControl.bufferInfo.highWaterFlag-300) {
////                GJLOG(GJ_LOGWARNING, "音频缓冲过程中，音频为空视频足够、或者视频足够大于音频。切换到视频同步");
////                [self stopBuffering];
////                changeSyncType(&_syncControl, kTimeSYNCVideo);
////                return;
////            }
////            GLong duration = (GLong)(GJ_Gettime()/1000) - _syncControl.bufferInfo.lastPauseFlag;
////            if (aCache < _syncControl.bufferInfo.lowWaterFlag){
////                if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
////                    GJLOG(GJ_LOGINFO, "buffer percent:%f A cacheTime:%ld",aCache*1.0/_syncControl.bufferInfo.lowWaterFlag,aCache);
////                    [self.delegate livePlayer:self bufferUpdatePercent:aCache*1.0/_syncControl.bufferInfo.lowWaterFlag duration:duration];
////                }
////            }else{
////                if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
////                    GJLOG(GJ_LOGINFO, "buffer percent:%f A cacheTime:%ld",1.0,aCache);
////                    [self.delegate livePlayer:self bufferUpdatePercent:1.0 duration:duration];
////                }
////                [self stopBuffering];
////            }
////        }else if (_playControl.status == kPlayStatusRunning){
////            GLong aCache = _syncControl.audioInfo.trafficStatus.enter.pts - _syncControl.audioInfo.trafficStatus.leave.pts;
////            if (aCache > _syncControl.bufferInfo.highWaterFlag ) {
////                if (_syncControl.speed <= 1.0) {
////                    [self dewatering];
////                }
////            }else if (aCache < _syncControl.bufferInfo.lowWaterFlag ){
////                if (_syncControl.speed >1.0) {
////                    [self stopDewatering];
////                }
////            }
////        }
////    }else{
////        GLong vCache = _syncControl.videoInfo.trafficStatus.enter.pts - _syncControl.videoInfo.trafficStatus.leave.pts;
////        if (_playControl.status == kPlayStatusBuffering){
////            GLong duration = (GLong)(GJ_Gettime()/1000) - _syncControl.bufferInfo.lastPauseFlag;
////            if (vCache < _syncControl.bufferInfo.lowWaterFlag){
////                if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
////                    GJLOG(GJ_LOGINFO, "buffer percent:%f V cacheTime:%d",vCache*1.0/_syncControl.bufferInfo.lowWaterFlag,vCache);
////                    [self.delegate livePlayer:self bufferUpdatePercent:vCache*1.0/_syncControl.bufferInfo.lowWaterFlag duration:duration];
////                }
////            }else{
////                if ([self.delegate respondsToSelector:@selector(livePlayer:bufferUpdatePercent:duration:)]) {
////                    GJLOG(GJ_LOGINFO, "buffer percent:%f V cacheTime:%d",1.0,vCache);
////                    [self.delegate livePlayer:self bufferUpdatePercent:1.0 duration:duration];
////                }
////                [self stopBuffering];
////            }
////        }else if (_playControl.status == kPlayStatusRunning){
////            if (vCache > _syncControl.bufferInfo.highWaterFlag ) {
////                if (_syncControl.speed <= 1.0) {
////                    [self dewatering];
////                }
////            }else if (vCache < _syncControl.bufferInfo.lowWaterFlag ){
////                if (_syncControl.speed >1.0) {
////                    [self stopDewatering];
////                }
////            }
////        }
////    }
//}
//
//-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(GInt64)pts{
//    GJLOGFREQ("收到音频 PTS:%lld",pts);
//    if (pts < _syncControl.videoInfo.trafficStatus.enter.pts) {
//        pthread_mutex_lock(&_playControl.oLock);
//        GInt32 length = queueGetLength(_playControl.imageQueue);
//        GJLOG(GJ_LOGWARNING, "视频pts不递增，抛弃之前的视频帧：%ld帧",length);
//        GJImageBuffer** imageBuffer = (GJImageBuffer**)malloc(length*sizeof(GJImageBuffer*));
//        queueBroadcastPop(_playControl.imageQueue);//other lock
//        if(queueClean(_playControl.imageQueue, (GHandle*)imageBuffer, &length)){
//            for (GUInt32 i = 0; i<length; i++) {
//                CVPixelBufferRelease(imageBuffer[i]->image);
//                GJBufferPoolSetData(defauleBufferPool(), (uint8_t*)imageBuffer[i]);
//            }
//        }
//        if (imageBuffer) {
//            free(imageBuffer);
//        }
//        _syncControl.videoInfo.trafficStatus.leave.pts = (GLong)pts;
//        pthread_mutex_unlock(&_playControl.oLock);
//    }
//    
//    if(_playControl.status == kPlayStatusStop){
//        GJLOG(GJ_LOGWARNING, "播放器stop状态收到视频帧，直接丢帧");
//        return NO;
//    }
//    if (_playControl.playVideoThread == GNULL) {
//#ifndef UIIMAGE_SHOW
//        if (_imageInput == nil) {
//            OSType type = CVPixelBufferGetPixelFormatType(imageData);
//            _imageInput = [[GJImagePixelImageInput alloc]initWithFormat:type];
//            if (_imageInput == nil) {
//                GJLOG(GJ_LOGFORBID, "GJImagePixelImageInput 创建失败！");
//                return NO;
//            }
//            [_imageInput addTarget:(GPUImageView*)_displayView];
//        }
//#endif
//            _syncControl.videoInfo.startPts = (GLong)pts;
//            _syncControl.videoInfo.trafficStatus.leave.pts = (GLong)pts;///防止videoInfo.startPts不为从0开始时，videocache过大，
//      
//            pthread_mutex_lock(&_playControl.oLock);
//            if (_playControl.status != kPlayStatusStop) {
//                pthread_create(&_playControl.playVideoThread, GNULL, playVideoRunLoop, (__bridge void *)(self));
//            }
//            pthread_mutex_unlock(&_playControl.oLock);
//    }
//    
//    GJImageBuffer* imageBuffer  = (GJImageBuffer*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJImageBuffer));
//    imageBuffer->image = imageData;
//    imageBuffer->pts = pts;
//    CVPixelBufferRetain(imageBuffer->image);
//    BOOL result = YES;
//RETRY:
//    if (queuePush(_playControl.imageQueue, imageBuffer, 0)) {
//        _syncControl.videoInfo.trafficStatus.enter.pts = (GLong)imageBuffer->pts;
//        _syncControl.videoInfo.trafficStatus.enter.count++;
//#ifdef NETWORK_DELAY
//        GUInt32 date = [[NSDate date]timeIntervalSince1970]*1000;
//        _syncControl.networkDelay = date - _syncControl.videoInfo.trafficStatus.enter.pts;
//#endif
//        [self checkBufferingAndWater];
//        result = YES;
//    }else if(_playControl.status == kPlayStatusStop){
//        GJLOG(GJ_LOGWARNING,"player video data push while stop,drop");
//        result = NO;
//    }else{
//        GJLOG(GJ_LOGWARNING, "video player queue full,update oldest frame");
//        GJImageBuffer* oldBuffer = GNULL;
//        if (queuePop(_playControl.imageQueue, (GHandle*)&oldBuffer, 0)) {
//            CVPixelBufferRelease(oldBuffer->image);
//            GJBufferPoolSetData(defauleBufferPool(), (GHandle)oldBuffer);
//            goto RETRY;
//        }else{
//            GJLOG(GJ_LOGFORBID,"full player audio queue pop error");
//            CVPixelBufferRelease(imageData);
//            GJBufferPoolSetData(defauleBufferPool(), (uint8_t*)imageBuffer);
//            result = NO;
//        }
//    }
//    return result;
//}
//#ifdef GJAUDIOQUEUEPLAY
//static const GUInt32 mpeg4audio_sample_rates[16] = {
//    96000, 88200, 64000, 48000, 44100, 32000,
//    24000, 22050, 16000, 12000, 11025, 8000, 7350
//};
//#endif
//
//
//-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(GInt64)pts{
//#ifdef GJAUDIOQUEUEPLAY
//    if (_audioTestPlayer == nil) {
//        if (_audioFormat.mFormatID <=0) {
//            queueSetMinCacheSize(_playControl.audioQueue, 0);
//            if (((uGInt64*)audioData->data) && 0xFFF0 != 0xFFF0) {
//                NSAssert(0, @"音频格式不支持");
//            }
//            uint8_t* adts = audioData->data;
//            uint8_t sampleIndex = adts[2] << 2;
//            sampleIndex = sampleIndex>>4;
//            GUInt32 sampleRate = mpeg4audio_sample_rates[sampleIndex];
//            uint8_t channel = adts[2] & 0x1 <<2;
//            channel += (adts[3] & 0xb0)>>6;
//            _audioFormat.mChannelsPerFrame = channel;
//            _audioFormat.mSampleRate = sampleRate;
//            _audioFormat.mFramesPerPacket = 1024;
//            _audioFormat.mFormatID = kAudioFormatMPEG4AAC;
//        }
//        _audioTestPlayer = [[GJAudioQueuePlayer alloc]initWithSampleRate:_audioFormat.mSampleRate channel:_audioFormat.mChannelsPerFrame formatID:_audioFormat.mFormatID];
//        [_audioTestPlayer start];
//    }
//    [_audioTestPlayer playData:audioData packetDescriptions:nil];
//    return YES;
//#endif
//    GJLOGFREQ("收到音频 PTS:%lld",pts);
//    BOOL result = YES;
//    if (pts < _syncControl.audioInfo.trafficStatus.leave.pts) {
//        pthread_mutex_lock(&_playControl.oLock);
//        GJLOG(GJ_LOGWARNING, "音频pts不递增，抛弃之前的音频帧：%ld帧",queueGetLength(_playControl.audioQueue));
//
//        queueBroadcastPop(_playControl.audioQueue);//other lock
//        GInt32 qLength = queueGetLength(_playControl.audioQueue);
//        if(qLength > 0){
//            GJAudioBuffer** audioBuffer = (GJAudioBuffer**)malloc(qLength*sizeof(GJAudioBuffer*));
//            queueClean(_playControl.audioQueue, (GVoid**)audioBuffer, &qLength);//用clean，防止播放断同时也在读
//            for (GUInt32 i = 0; i<qLength; i++) {
//                _syncControl.audioInfo.trafficStatus.leave.count++;
//                _syncControl.audioInfo.trafficStatus.leave.byte += audioBuffer[i]->audioData->size;
//                retainBufferUnRetain(audioBuffer[i]->audioData);
//                GJBufferPoolSetData(defauleBufferPool(), (uint8_t*)audioBuffer[i]);
//            }
//            free(audioBuffer);
//        }
//        _syncControl.audioInfo.trafficStatus.leave.pts = (GLong)pts;//防止此时获得audioCache时误差太大，
//        _syncControl.audioInfo.cPTS = (GLong)pts;//防止pts重新开始时，视频远落后音频
//        _syncControl.audioInfo.clock = GJ_Gettime()/1000;
//        pthread_mutex_unlock(&_playControl.oLock);
//
//    }
//    if (_playControl.status == kPlayStatusStop) {
//        GJLOG(GJ_LOGWARNING, "播放器stop状态收到视音频，直接丢帧");
//        result =  NO;
//        goto END;
//    }
//    if (_syncControl.syncType != kTimeSYNCAudio) {
//        GJLOG(GJ_LOGWARNING, "加入音频，切换到音频同步");
//        if (_playControl.status == kPlayStatusBuffering) {
//            [self stopBuffering];
//        }
//        changeSyncType(&_syncControl, kTimeSYNCAudio);
//        _syncControl.audioInfo.trafficStatus.leave.pts = (GLong)pts;///防止audioInfo.startPts不为从0开始时，audiocache过大，
//    }
//    {
//        //收集网络抖动
//        GInt32 clock = GJ_Gettime()/1000;
//        GInt32 unitClockDif = clock - _syncControl.netShake.collectUnitEndClock;
//        GInt32 unitPtsDif = (GInt32)(pts - _syncControl.audioInfo.trafficStatus.enter.pts);
//        GInt32 preShake = _syncControl.netShake.collectUnitPtsCache - _syncControl.netShake.collectUnitEndClock + _syncControl.netShake.collectUnitStartClock;
//        GInt32 currentShake = unitPtsDif - unitClockDif;
//        if ((currentShake >= -10.0 && preShake >= -10.0) || (currentShake <= 10.0 && preShake <= 10.0)) {
//            _syncControl.netShake.collectUnitEndClock = clock;
//            _syncControl.netShake.collectUnitPtsCache += unitPtsDif;
//        }else{
//            GInt32 totalShake = _syncControl.netShake.collectUnitPtsCache - clock + _syncControl.netShake.collectUnitStartClock;
//            if (_syncControl.netShake.minShake > totalShake){
//                _syncControl.netShake.minShake = totalShake;
//                _syncControl.bufferInfo.lowWaterFlag = MIN(MAX(MIN_CACHE_DUR,-totalShake*2),MAX_CACHE_DUR);
//                _syncControl.bufferInfo.highWaterFlag = _syncControl.bufferInfo.lowWaterFlag*3;
//                
//                GJLOG(GJ_LOGINFO, "preShake:%d,currentShake:%d,totalShake:%d,重置lowWaterFlag：%d，highWaterFlag：%d",preShake,currentShake,totalShake,_syncControl.bufferInfo.lowWaterFlag,_syncControl.bufferInfo.highWaterFlag);
//
//                if (_syncControl.bufferInfo.lowWaterFlag > _syncControl.bufferInfo.highWaterFlag) {
//                    GJLOG(GJ_LOGFORBID, "lowAudioWaterFlag 大于 highAudioWaterFlag怎么可能！！！");
//                    _syncControl.bufferInfo.highWaterFlag = _syncControl.bufferInfo.lowWaterFlag;
//                }
//            }else{
//                GJLOGFREQ("pull net shake:%d,but not affect",totalShake);
//            }
//            _syncControl.netShake.collectUnitStartClock = _syncControl.netShake.collectUnitEndClock;
//            _syncControl.netShake.collectUnitEndClock = clock;
//            _syncControl.netShake.collectUnitPtsCache = unitPtsDif;
//            
//            if (clock - _syncControl.netShake.collectStartClock >= UPDATE_SHAKE_TIME) {
//                if (totalShake > 0) {
//                    _syncControl.netShake.maxShake = totalShake;
//                    _syncControl.netShake.minShake = MIN_CACHE_DUR;
//                }else{
//                    _syncControl.netShake.minShake = totalShake;
//                    _syncControl.netShake.maxShake = MAX_CACHE_DUR;
//                }
//                _syncControl.netShake.collectStartClock = _syncControl.netShake.collectUnitStartClock;
//                GJLOG(GJ_LOGINFO, "更新网络抖动收集 startClock:%d",_syncControl.netShake.collectStartClock);
//
//            }
//        }
//    }
//    if (_audioPlayer == nil) {
//        _syncControl.audioInfo.startPts = (GLong)pts;
//        _syncControl.audioInfo.trafficStatus.leave.pts = (GLong)pts;///防止audioInfo.startPts不为从0开始时，audiocache过大，
//        //防止视频先到，导致时差特别大
//        _syncControl.audioInfo.cPTS = (GLong)pts;
//        _syncControl.audioInfo.clock = GJ_Gettime()/1000;
//        if (_audioFormat.mFormatID != kAudioFormatLinearPCM) {
//            GJLOG(GJ_LOGWARNING, "音频格式不支持");
//            result =  NO;
//            goto END;
//        }else{
//            pthread_mutex_lock(&_playControl.oLock);//此时禁止开启和停止
//            if (_playControl.status != kPlayStatusStop) {
//                _audioPlayer = [[GJAudioQueueDrivePlayer alloc]initWithSampleRate:_audioFormat.mSampleRate channel:_audioFormat.mChannelsPerFrame formatID:_audioFormat.mFormatID];
//                _audioPlayer.delegate = self;
//                [_audioPlayer start];
//                _syncControl.audioInfo.startTime = GJ_Gettime()/1000.0;
//            }
//            pthread_mutex_unlock(&_playControl.oLock);
//        }
//    }
//    
//
//    
//    GJAudioBuffer* audioBuffer = (GJAudioBuffer*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJAudioBuffer));
//    audioBuffer->audioData = audioData;
//    audioBuffer->pts = pts;
//    retainBufferRetain(audioData);
//RETRY:
//    if(queuePush(_playControl.audioQueue, audioBuffer, 0)){
//        _syncControl.audioInfo.trafficStatus.enter.pts = (GLong)audioBuffer->pts;
//        _syncControl.audioInfo.trafficStatus.enter.count++;
//        _syncControl.audioInfo.trafficStatus.enter.byte += audioBuffer->audioData->size;
//
//#ifdef NETWORK_DELAY
//        GUInt32 date = [[NSDate date]timeIntervalSince1970]*1000;
//        _syncControl.networkDelay = date - _syncControl.audioInfo.trafficStatus.enter.pts;
//#endif
//        [self checkBufferingAndWater];
//        result =  YES;
//    }else if(_playControl.status == kPlayStatusStop){
//        GJLOG(GJ_LOGWARNING,"player audio data push while stop,drop");
//        retainBufferUnRetain(audioData);
//        GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioBuffer);
//        result = NO;
//    }else{
//        GJLOG(GJ_LOGWARNING, "audio player queue full,update oldest frame   ，正常情况不可能出现的case");
//        GJAudioBuffer* oldBuffer = GNULL;
//        if (queuePop(_playControl.audioQueue, (GHandle*)&oldBuffer, 0)) {
//            retainBufferUnRetain(oldBuffer->audioData);
//            GJBufferPoolSetData(defauleBufferPool(), (GHandle)oldBuffer);
//            goto RETRY;
//        }else{
//            GJLOG(GJ_LOGFORBID,"full player audio queue pop error");
//            retainBufferUnRetain(audioData);
//            GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioBuffer);
//            result = NO;
//        }
//    }
//    
//END:
//    return result;
//}
//
//
//
//
//-(BOOL)GJAudioQueueDrivePlayer:(GJAudioQueueDrivePlayer *)player outAudioData:(void *)data outSize:(GInt32 *)size{
//    GJAudioBuffer* audioBuffer;
//    if (_playControl.status == kPlayStatusRunning && queuePop(_playControl.audioQueue, (GHandle*)&audioBuffer, 0)) {
//        *size = audioBuffer->audioData->size;
//        memcpy(data, audioBuffer->audioData->data, *size);
//        _syncControl.audioInfo.trafficStatus.leave.pts = (GLong)audioBuffer->pts;
//        _syncControl.audioInfo.trafficStatus.leave.count++;
//        _syncControl.audioInfo.cPTS = (GLong)audioBuffer->pts;
//        _syncControl.audioInfo.clock = GJ_Gettime()/1000;
////        GJLOG(GJ_LOGDEBUG,"audio play pts:%d size:%d",_syncControl.audioInfo.cPTS,*size);
//        GJLOGFREQ("audio show pts:%d",audioBuffer->pts);
//        retainBufferUnRetain(audioBuffer->audioData);
//        GJBufferPoolSetData(defauleBufferPool(), (GHandle)audioBuffer);
//        return YES;
//    }else{
//        if (_playControl.status == kPlayStatusRunning) {
//            GJLOG(GJ_LOGDEBUG, "audio player queue empty");
//            if (_syncControl.syncType == kTimeSYNCAudio) {
//                [self buffering];
//            }
//        }
//        return NO;
//    }
//}
//-(void)dealloc{
//    GJLOG(GJ_LOGDEBUG, "GJPlivePlayer dealloc");
//    queueFree(&_playControl.audioQueue);
//    queueFree(&_playControl.imageQueue);
//}
//@end
