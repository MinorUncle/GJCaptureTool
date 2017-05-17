//
//  GJLivePullContext.c
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/5/17.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLivePullContext.h"
#include "GJUtil.h"
static GVoid livePlayCallback(GHandle userDate,GJPlayMessage message,GHandle param){
}
GVoid GJLivePull_Create(GJLivePullContext* context,GJLivePullCallback callback,GHandle param){
    if (context == GNULL) {
        context = (GJLivePullContext*)malloc(sizeof(GJLivePullContext));
        memset(context, 0, sizeof(GJLivePullContext));
    }
    GJLivePlay_Create(context->player, livePlayCallback, context);
    GJ_H264DecodeContextSetup(context->videoDecoder);
    GJ_AACDecodeContextSetup(context->audioDecoder);
    pthread_mutex_init(&context->lock, GNULL);

}
GVoid GJLivePull_StartPull(GJLivePullContext* context,char* url){
    pthread_mutex_lock(&context->lock);
    context->fristAudioClock = context->fristVideoClock = context->connentClock = context->fristVideoDecodeClock = nil;
    if (context->_videoPull != nil) {
        GJRtmpPull_CloseAndRelease(context->_videoPull);
    }
    GJRtmpPull_Create(&_videoPull, pullMessageCallback, (__bridge void *)(self));
    GJRtmpPull_StartConnect(_videoPull, pullDataCallback, (__bridge void *)(self),(const char*) url);
    [_player start];
    _startPullDate = [NSDate date];
    [_lock unlock];
    return YES;
}
GBool GJLivePull_StopPull(GJLivePullContext* context);
GVoid GJLivePull_StopDealloc(GJLivePullContext* context);
