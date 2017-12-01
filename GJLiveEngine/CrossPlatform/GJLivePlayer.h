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


//音频存在时，不会产生视频缓冲
//#define SHOULD_BUFFER_VIDEO_IN_AUDIO_CLOCK

typedef enum _GJPlayStatus {
    kPlayStatusStop,
    kPlayStatusRunning,
    kPlayStatusPause,
    kPlayStatusBuffering,
} GJPlayStatus;

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
    GJPlayMessage_BufferUpdate,
    GJPlayMessage_BufferEnd,
    GJPlayMessage_NetShakeUpdate,//const GTime;
#ifdef NETWORK_DELAY
    GJPlayMessage_TestNetShakeUpdate,//同一手机下真正测试的抖动
    GJPlayMessage_TestKeyDelayUpdate,//影响抖动的关键延迟
#endif
    GJPlayMessage_DewateringUpdate,//gbool
    GJPlayMessage_FristRender,
} GJPlayMessage;
typedef struct CacheInfo {
    GTime lowWaterFlag;
    GTime highWaterFlag;
    GTime speedTotalDuration;
    GTime bufferTotalDuration;
    GTime lastBufferDuration;
    GTime bufferTimes;
    GTime lastPauseFlag;
} GJCacheInfo;
typedef struct PlayControl {
    GJPlayStatus    status;
    pthread_mutex_t oLock;
    pthread_t       playVideoThread;
    GJQueue *       imageQueue;
    GJQueue *       audioQueue;
    GInt32          videoQueueWaitTime;
    //视频出队列等待时间(因为需要知道是否没有数据了，主动去缓存。也可以修改为还剩1帧时去缓存，就可以一直等待了)，音频不等待
} GJPlayControl;
typedef struct _GJNetShakeInfo {
    GTime collectStartClock;
    GTime collectStartPts;
    GTime maxDownShake;
    GTime preMaxDownShake;
    
#ifdef NETWORK_DELAY
    GInt32 networkDelay;
    GInt32 delayCount;
    GTime  collectStartDelay;
    GTime  maxTestDownShake;
    GTime  preMaxTestDownShake;

#endif
} GJNetShakeInfo;
typedef struct _SyncInfo {
    GTime           clock;
    GTime           cPTS;
    GTime           startTime;
    GTime           startPts;
    GLong           inDtsSeries;
    GJTrafficStatus trafficStatus;
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
GVoid GJLivePlay_SetAudioFormat(GJLivePlayer *player, GJAudioFormat audioFormat);
GVoid GJLivePlay_SetVideoFormat(GJLivePlayer *player, GJPixelType audioFormat);

GHandle GJLivePlay_GetVideoDisplayView(GJLivePlayer *player);

GJTrafficStatus GJLivePlay_GetVideoCacheInfo(GJLivePlayer *player);
GJTrafficStatus GJLivePlay_GetAudioCacheInfo(GJLivePlayer *player);
#ifdef NETWORK_DELAY
//采集到显示的延迟
GLong GJLivePlay_GetNetWorkDelay(GJLivePlayer *player);
#endif

//@protocol GJLivePlayerDeletate <NSObject>
//
//-(void)livePlayer:(GJLivePlayer*)livePlayer bufferUpdatePercent:(float)percent duration:(long)duration;
//
//@end
//
//
//
//@interface GJLivePlayer : NSObject
//@property(readonly,nonatomic)UIView* displayView;
//@property(weak,nonatomic)id<GJLivePlayerDeletate> delegate;
//
//
//@property(assign,nonatomic)AudioStreamBasicDescription audioFormat;
//
//-(void)start;
//-(void)stop;
//-(BOOL)addVideoDataWith:(CVImageBufferRef)imageData pts:(int64_t)pts;
//-(BOOL)addAudioDataWith:(GJRetainBuffer*)audioData pts:(int64_t)pts;
//-(GJTrafficStatus)getVideoCache;
//-(GJTrafficStatus)getAudioCache;
//#ifdef NETWORK_DELAY
//-(long)getNetWorkDelay;
//#endif
//
//@end
