//
//  GJLivePlayer.h
//  GJCaptureTool
//
//  Created by mac on 17/3/7.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CMTime.h>
#import <CoreVideo/CVImageBuffer.h>
#import <AVFoundation/AVFoundation.h>
#import "GJRetainBuffer.h"
#import "GJLiveDefine.h"
#import "GJLiveDefine+internal.h"
#import "GJBridegContext.h"
@class UIView;
@class GJLivePlayer;
typedef enum _GJPlayStatus{
    kPlayStatusStop,
    kPlayStatusRunning,
    kPlayStatusPause,
    kPlayStatusBuffering,
}GJPlayStatus;

typedef enum _TimeSYNCType{
    kTimeSYNCAudio,
    kTimeSYNCVideo,
}TimeSYNCType;

typedef struct _GJBufferInfo{
    GFloat32   bufferRate;
    GInt32     bufferCachePts;
    GInt32     bufferDuring;
}GJBufferInfo;
typedef enum _GJPlayMessage{
    GJPlayMessage_BufferStart,
    GJPlayMessage_BufferUpdate,
    GJPlayMessage_BufferEnd,
}GJPlayMessage;
typedef struct CacheInfo{
    GUInt32                         lowWaterFlag;
    GUInt32                         highWaterFlag;
    GInt32                          speedTotalDuration;
    GInt32                          bufferTotalDuration;
    GInt32                          lastBufferDuration;
    GInt32                          bufferTimes;
    GInt32                          lastPauseFlag;
}GJCacheInfo;
typedef struct PlayControl{
    GJPlayStatus         status;
    pthread_mutex_t      oLock;
    pthread_t            playVideoThread;
    GJQueue*             imageQueue;
    GJQueue*             audioQueue;
}GJPlayControl;
typedef struct _GJNetShakeInfo{
    GInt32 collectStartClock;
    GInt32 collectUnitStartClock;
    GInt32 collectUnitEndClock;
    GInt32 collectUnitPtsCache;
    GInt32 maxShake;
    GInt32 minShake;
}GJNetShakeInfo;
typedef struct _SyncInfo{
    GInt32                 clock;
    GLong                  cPTS;
    GInt32                 startTime;
    GLong                  startPts;
    GJTrafficStatus        trafficStatus;
}SyncInfo;
typedef struct SyncControl{
    SyncInfo                videoInfo;
    SyncInfo                audioInfo;
    GJCacheInfo             bufferInfo;
    TimeSYNCType            syncType;
    GJNetShakeInfo          netShake;
    GFloat32                        speed;
    
#ifdef NETWORK_DELAY
    GLong                   networkDelay;
#endif
}GJSyncControl;
typedef GVoid (*GJLivePlayCallback)(GHandle userDate,GJPlayMessage message,GHandle param);

typedef struct _GJLivePlayContext{
    GHandle             userDate;
    GJLivePlayCallback  callback;
    GJSyncControl       syncControl;
    GJPlayControl       playControl;
    
    GJPictureDisplayContext videoPlayer;
    GJAudioPlayContext      audioPlayer;
    GJAudioFormat           audioFormat;
}GJLivePlayContext;

GBool  GJLivePlay_InjectVideoPlayer(GJLivePlayContext* player,const GJPictureDisplayContext* videoPlayer);
GBool  GJLivePlay_InjectAudioPlayer(GJLivePlayContext* player,const GJAudioPlayContext* audioPlayer,GJAudioFormat format);

GBool  GJLivePlay_Create(GJLivePlayContext* player,GJLivePlayCallback callback,GHandle userData);
GVoid  GJLivePlay_Release(GJLivePlayContext* player);
GBool  GJLivePlay_Start(GJLivePlayContext* player);
GVoid  GJLivePlay_Stop(GJLivePlayContext* player);
GBool  GJLivePlay_AddVideoData(GJLivePlayContext* player,R_GJFrame* videoFrame);
GBool  GJLivePlay_AddAudioData(GJLivePlayContext* player,R_GJFrame* audioFrame);
GJTrafficStatus  GJLivePlay_GetVideoCacheInfo(GJLivePlayContext* player);
GJTrafficStatus  GJLivePlay_GetAudioCacheInfo(GJLivePlayContext* player);
#ifdef NETWORK_DELAY
GLong GJLivePlay_GetNetWorkDelay(GJLivePlayContext* player);
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

