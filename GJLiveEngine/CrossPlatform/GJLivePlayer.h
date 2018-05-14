//
//  GJLivePlayer.h
//  GJCaptureTool
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJBridegContext.h"
#import "GJLiveDefine+internal.h"
#import "GJLiveDefine.h"
#import "GJRetainBuffer.h"
#import "GJSignal.h"


//音频存在时，不会产生视频缓冲
//#define SHOULD_BUFFER_VIDEO_IN_AUDIO_CLOCK


typedef enum _TimeSYNCType {
    kTimeSYNCAudio,
    kTimeSYNCVideo,
} TimeSYNCType;

typedef struct _GJBufferInfo {
    GFloat32 bufferRate;
    GInt32   bufferCachePts;
    GInt32   bufferDuring;
} GJBufferInfo;
typedef enum _GJPlayMessage {
    GJPlayMessage_BufferStart,
    GJPlayMessage_BufferUpdate,//UnitBufferInfo
    GJPlayMessage_BufferEnd,//GJCacheInfo
    GJPlayMessage_NetShakeRangeUpdate,//const GLone*,网络抖动收集的时间范围更新
    GJPlayMessage_NetShakeUpdate,//const GLone*，NetShakeRange时长内的网络抖动
#ifdef NETWORK_DELAY
    GJPlayMessage_TestNetShakeUpdate,//同一手机下真正测试的抖动
    GJPlayMessage_TestKeyDelayUpdate,//影响抖动的关键延迟
#endif
    GJPlayMessage_DewateringUpdate,//gbool
    GJPlayMessage_FristRender,
} GJPlayMessage;
typedef struct CacheInfo {
    GLong lowWaterFlag;
    GLong highWaterFlag;
    GLong speedTotalDuration;
    GLong bufferTotalDuration;
    GLong lastBufferDuration;
    GLong bufferTimes;
    GLong lastPauseFlag;
} GJCacheInfo;
typedef struct PlayControl {
    GJPlayStatus    status;
    pthread_mutex_t oLock;
    pthread_t       playVideoThread;
    GJQueue *       imageQueue;
    GJQueue *       audioQueue;
    
    R_GJPCMFrame*   freshAudioFrame;
    GInt32          videoQueueWaitTime;
    
    GJSignal*       stopSignal;//停止信号，可以不用sleep；
    //视频出队列等待时间(因为需要知道是否没有数据了，主动去缓存。也可以修改为还剩1帧时去缓存，就可以一直等待了)，音频不等待
} GJPlayControl;
typedef struct _GJNetShakeInfo {
    GInt32 collectUpdateDur;
    GTime collectStartClock;
    GTime collectStartPts;
    GLong maxDownShake;
    GLong preMaxDownShake;
    
    GBool hasBuffer;
    GBool hasDewater;
    //用于控制增加collectUpdateDur，每次同时hasDewater和hasBuffer时则增大collectUpdateDur
#ifdef NETWORK_DELAY
    GLong networkDelay;
    GLong delayCount;
    GLong  collectStartDelay;
    GLong  maxTestDownShake;
    GLong  preMaxTestDownShake;
#endif
} GJNetShakeInfo;
typedef struct _SyncInfo {
//    GTime           clock;
//    GTime           cPTS;
    GTime           startTime;
    GTime           startPts;
    GLong           inDtsSeries;
    GJTrafficStatus  trafficStatus;
} SyncInfo;
typedef struct SyncControl {
    SyncInfo       videoInfo;
    SyncInfo       audioInfo;
    GJCacheInfo    bufferInfo;
    TimeSYNCType   syncType;
    GJNetShakeInfo netShake;
    GFloat32       speed;


} GJSyncControl;
typedef GVoid (*GJLivePlayCallback)(GHandle userDate, GJPlayMessage message, GHandle param);

typedef struct _GJLivePlayContext {
    GJPipleNode pipleNode;
    GHandle            userDate;
    GJLivePlayCallback callback;
    GJSyncControl      syncControl;
    GJPlayControl      playControl;

    GJPictureDisplayContext *videoPlayer;
    GJAudioPlayContext *     audioPlayer;
    GJAudioFormat            audioFormat;
    R_GJPixelFrame *         sortQueue[5]; //用于排序,最大5个连续b帧
    GInt32                   sortIndex;
} GJLivePlayer;

GBool GJLivePlay_Create(GJLivePlayer **player, GJLivePlayCallback callback, GHandle userData);
GVoid GJLivePlay_Dealloc(GJLivePlayer **player);
GBool GJLivePlay_Start(GJLivePlayer *player);
GVoid GJLivePlay_Stop(GJLivePlayer *player);
GBool GJLivePlay_Pause(GJLivePlayer *player);
GVoid GJLivePlay_Resume(GJLivePlayer *player);
GBool GJLivePlay_AddVideoData(GJLivePlayer *player, R_GJPixelFrame *videoFrame);
GBool GJLivePlay_AddAudioData(GJLivePlayer *player, R_GJPCMFrame *audioFrame);
GVoid GJLivePlay_AddAudioSourceFormat(GJLivePlayer *player, GJAudioFormat audioFormat);
GVoid GJLivePlay_AddVideoSourceFormat(GJLivePlayer *player, GJPixelType audioFormat);
GHandle GJLivePlay_GetVideoDisplayView(GJLivePlayer *player);

GJTrafficStatus GJLivePlay_GetVideoCacheInfo(GJLivePlayer *player);
GJTrafficStatus GJLivePlay_GetAudioCacheInfo(GJLivePlayer *player);

inline static GBool GJLivePlay_NodeAddData(GJPipleNode* node,GJRetainBuffer* data, GJMediaType type){
    if (type == GJMediaType_Audio) {
       return GJLivePlay_AddAudioData((GJLivePlayer*)node, (R_GJPCMFrame*)data);
    }else{
       return  GJLivePlay_AddVideoData((GJLivePlayer*)node, (R_GJPixelFrame*)data);
    }
}

#ifdef NETWORK_DELAY
//采集到显示的延迟
GLong GJLivePlay_GetNetWorkDelay(GJLivePlayer *player);
#endif

