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
@interface IOS_AudioDrivePlayer : NSObject

@end
@implementation IOS_AudioDrivePlayer

@end
inline static GBool audioPlayCreate (struct _GJAudioPlayContext* context,GJAudioFormat format){
    if (format.mType != GJAudioType_PCM) {
        GJLOG(GJ_LOGFORBID, "视频格式不支持");
        return GFalse;
    }
    context->obaque = (__bridge_retained GHandle)([[GJAudioQueueDrivePlayer alloc]initWithSampleRate:format.mSampleRate channel:format.mChannelsPerFrame formatID:kAudioFormatLinearPCM]);
    return context->obaque != nil;
}
inline static GVoid audioPlayDealloc (struct _GJAudioPlayContext* context){
    GJAudioQueueDrivePlayer* player = (__bridge_transfer GJAudioQueueDrivePlayer *)(context->obaque);
    player = nil;
    free(context);
    
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
GVoid GJ_AudioPlayContextSetup(GJAudioPlayContext* context){
    if (context == NULL) {
        context = (GJAudioPlayContext*)malloc(sizeof(GJAudioPlayContext));
    }
    context->audioPlayCreate = audioPlayCreate;
    context->audioPlayDealloc = audioPlayDealloc;
    context->audioStart = audioStart;
    context->audioStop = audioStop;
    context->audioPause = audioPause;
    context->audioResume = audioResume;
    context->audioSetSpeed = audioSetSpeed;
    context->audioGetSpeed = audioGetSpeed;
    context->audioPlayCallback = GNULL;
}
