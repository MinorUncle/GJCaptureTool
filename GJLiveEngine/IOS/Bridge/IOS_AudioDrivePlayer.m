//
//  IOS_AudioDrivePlayer.m
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "GJAudioQueueDrivePlayer.h"
#import "IOS_AudioDrivePlayer.h"
#import "GJLiveDefine+internal.h"
#import "GJLog.h"
#import "GJAudioSessionCenter.h"
@interface IOS_AudioDrivePlayer : NSObject

@end
@implementation IOS_AudioDrivePlayer

@end
inline static GBool audioPlaySetup (struct _GJAudioPlayContext* context,GJAudioFormat format,FillDataCallback dataCallback,GHandle userData){
    if (format.mType != GJAudioType_PCM) {
        GJLOG(GJ_LOGFORBID, "视频格式不支持");
        return GFalse;
    }
    GJAudioQueueDrivePlayer* player = [[GJAudioQueueDrivePlayer alloc]initWithSampleRate:format.mSampleRate channel:format.mChannelsPerFrame formatID:kAudioFormatLinearPCM];
    NSError* error;
    if(![[GJAudioSessionCenter shareSession]requestPlay:YES key:player error:&error]){
        GJLOG(GJ_LOGERROR, "request play session fail:%@",error);
    }

    player.fillDataCallback = ^BOOL(void *data, int *size) {
        return dataCallback(userData,data,size);
    };
    context->obaque = (__bridge_retained GHandle)player;
    return context->obaque != nil;
}
inline static GVoid audioPlayUnSetup (struct _GJAudioPlayContext* context){
    if (context->obaque) {
        GJAudioQueueDrivePlayer* player = (__bridge_transfer GJAudioQueueDrivePlayer *)(context->obaque);
        NSError* error;
        if(![[GJAudioSessionCenter shareSession]requestPlay:NO key:player error:&error]){
            GJLOG(GJ_LOGERROR, "request play session fail:%@",error);
        }
        player = nil;
        context->obaque = GNULL;
    }
}
inline static GVoid audioStop(struct _GJAudioPlayContext* context){
    GJAudioQueueDrivePlayer* player = (__bridge GJAudioQueueDrivePlayer *)(context->obaque);
    [player stop:YES];
}
inline static GBool audioStart(struct _GJAudioPlayContext* context){
    GJAudioQueueDrivePlayer* player = (__bridge GJAudioQueueDrivePlayer *)(context->obaque);
    return [player start];
}
inline static GVoid audioPause(struct _GJAudioPlayContext* context){
    GJAudioQueueDrivePlayer* player = (__bridge GJAudioQueueDrivePlayer *)(context->obaque);
    [player pause];
}
inline static GBool audioResume(struct _GJAudioPlayContext* context){
    GJAudioQueueDrivePlayer* player = (__bridge GJAudioQueueDrivePlayer *)(context->obaque);
    return [player resume];
}
inline static GBool audioSetSpeed(struct _GJAudioPlayContext* context,GFloat32 speed){
    GJAudioQueueDrivePlayer* player = (__bridge GJAudioQueueDrivePlayer *)(context->obaque);
    player.speed = speed;
    return GTrue;
}
inline static GFloat32 audioGetSpeed(struct _GJAudioPlayContext* context){
    GJAudioQueueDrivePlayer* player = (__bridge GJAudioQueueDrivePlayer *)(context->obaque);
    return player.speed;
}
GVoid GJ_AudioPlayContextCreate(GJAudioPlayContext** audioPlayContext){
    if (*audioPlayContext == NULL) {
        *audioPlayContext = (GJAudioPlayContext*)malloc(sizeof(GJAudioPlayContext));
    }
    GJAudioPlayContext* context = *audioPlayContext;
    context->audioPlaySetup = audioPlaySetup;
    context->audioPlayUnSetup = audioPlayUnSetup;
    context->audioStart = audioStart;
    context->audioStop = audioStop;
    context->audioPause = audioPause;
    context->audioResume = audioResume;
    context->audioSetSpeed = audioSetSpeed;
    context->audioGetSpeed = audioGetSpeed;
    context->audioPlayCallback = GNULL;
}
GVoid GJ_AudioPlayContextDealloc(GJAudioPlayContext** context){
    if ((*context)->obaque) {
        GJLOG(GJ_LOGWARNING, "audioPlayUnSetup 没有调用，自动调用");
        (*context)->audioPlayUnSetup(*context);
        
    }
    free(*context);
    *context = GNULL;
}
