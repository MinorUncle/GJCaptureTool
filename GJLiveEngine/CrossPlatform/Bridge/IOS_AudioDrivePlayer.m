//
//  IOS_AudioDrivePlayer.m
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//
#import "IOS_AudioDrivePlayer.h"
#import "GJAudioQueueDrivePlayer.h"
#import "GJAudioSessionCenter.h"
#import "GJLiveDefine+internal.h"
#import "GJLog.h"
#import <Foundation/Foundation.h>
@interface IOS_AudioDrivePlayer : NSObject

@end
@implementation IOS_AudioDrivePlayer

@end
inline static GBool audioPlaySetup(struct _GJAudioPlayContext *context, GJAudioFormat format, FillDataCallback dataCallback, GHandle userData) {
    GJAssert(context->obaque == GNULL, "上一个GJAudioQueueDrivePlayer 没有释放");
    if (format.mType != GJAudioType_PCM) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "视频格式不支持");
        return GFalse;
    }
    GJAudioQueueDrivePlayer *player = [[GJAudioQueueDrivePlayer alloc] initWithSampleRate:format.mSampleRate channel:format.mChannelsPerFrame formatID:kAudioFormatLinearPCM];
    NSError *error;
    if (![[GJAudioSessionCenter shareSession] requestPlay:YES key:[NSString stringWithFormat:@"%p", player] error:&error]) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "request play session fail:%s", error.localizedDescription.UTF8String);
    }

    if (![[GJAudioSessionCenter shareSession] activeSession:YES key:[NSString stringWithFormat:@"%p", player] error:&error]) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "activeSession session fail:%s", error.localizedDescription.UTF8String);
    }

    player.fillDataCallback = ^BOOL(void *data, int *size) {
        return dataCallback(userData, data, size);
    };
    context->obaque = (__bridge_retained GHandle) player;
    return context->obaque != nil;
}
inline static GVoid audioPlayUnSetup(struct _GJAudioPlayContext *context) {
    if (context->obaque) {
        GJAudioQueueDrivePlayer *player = (__bridge_transfer GJAudioQueueDrivePlayer *) (context->obaque);
        NSError *                error;
        if (![[GJAudioSessionCenter shareSession] requestPlay:NO key:[NSString stringWithFormat:@"%p", player] error:&error]) {
            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "request play session fail:%s", error.localizedDescription.UTF8String);
        }
        if (![[GJAudioSessionCenter shareSession] activeSession:NO key:[NSString stringWithFormat:@"%p", player] error:&error]) {
            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "activeSession session fail:%s", error.localizedDescription.UTF8String);
        }
        context->obaque = GNULL;
        player          = nil;
    }
}
inline static GVoid audioStop(struct _GJAudioPlayContext *context) {
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *) (context->obaque);
    [player stop:YES];
}
inline static GBool audioStart(struct _GJAudioPlayContext *context) {
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *) (context->obaque);
    return [player start];
}
inline static GVoid audioPause(struct _GJAudioPlayContext *context) {
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *) (context->obaque);
    [player pause];
}
inline static GBool audioResume(struct _GJAudioPlayContext *context) {
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *) (context->obaque);
    return [player resume];
}
inline static GBool audioSetSpeed(struct _GJAudioPlayContext *context, GFloat speed) {
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *) (context->obaque);
    player.speed                    = speed;
    return GTrue;
}
inline static GFloat audioGetSpeed(struct _GJAudioPlayContext *context) {
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *) (context->obaque);
    return player.speed;
}
inline static GJPlayStatus audioGetStatus(struct _GJAudioPlayContext *context) {
    GJAudioQueueDrivePlayer *player = (__bridge GJAudioQueueDrivePlayer *) (context->obaque);
    return player.status;
}
GVoid GJ_AudioPlayContextCreate(GJAudioPlayContext **audioPlayContext) {
    if (*audioPlayContext == NULL) {
        *audioPlayContext = (GJAudioPlayContext *) calloc(1, sizeof(GJAudioPlayContext));
    }
    GJAudioPlayContext *context = *audioPlayContext;
    context->audioPlaySetup     = audioPlaySetup;
    context->audioPlayUnSetup   = audioPlayUnSetup;
    context->audioStart         = audioStart;
    context->audioStop          = audioStop;
    context->audioPause         = audioPause;
    context->audioResume        = audioResume;
    context->audioSetSpeed      = audioSetSpeed;
    context->audioGetSpeed      = audioGetSpeed;
    context->audioGetStatus     = audioGetStatus;
    context->audioPlayCallback  = GNULL;
}
GVoid GJ_AudioPlayContextDealloc(GJAudioPlayContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "audioPlayUnSetup 没有调用，自动调用");
        (*context)->audioPlayUnSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
