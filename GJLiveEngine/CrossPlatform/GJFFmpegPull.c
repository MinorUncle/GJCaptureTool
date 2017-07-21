//
//  GJFFmpegPull.c
//  GJCaptureTool
//
//  Created by melot on 2017/7/11.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include <stdio.h>
#include "GJStreamPull.h"
#include "avformat.h"
#include "GJLog.h"
struct _GJStreamPull{
    AVFormatContext*                   formatContext;
    char                    pullUrl[MAX_URL_LENGTH];
    
    GJRetainBufferPool*      memoryCachePool;
    pthread_t               pullThread;
    pthread_mutex_t          mutex;
    
    GJTrafficUnit           videoPullInfo;
    GJTrafficUnit           audioPullInfo;
    
    StreamPullMessageCallback     messageCallback;
    StreamPullDataCallback        dataCallback;
    
    GHandle                   messageCallbackParm;
    GHandle                   dataCallbackParm;
    
    int                     stopRequest;
    int                     releaseRequest;
    
    
};
static GHandle pullRunloop(GHandle parm){
    GJStreamPull* pull = parm;
    GInt32 result = avformat_open_input(&pull->formatContext, pull->pullUrl, GNULL, GNULL);
    if (result < 0) {
        GJLOG(GJ_LOGERROR, "avformat_open_input error");
        return GFalse;
    }
    result = avformat_find_stream_info(pull->formatContext, GNULL);
    if (result < 0) {
        GJLOG(GJ_LOGERROR, "avformat_find_stream_info");
        return GFalse;
    }
    
    GInt32 vStream = av_find_best_stream(pull->formatContext, AVMEDIA_TYPE_VIDEO,
                        -1, -1, NULL, 0);
    if (vStream < 0) {
        GJLOG(GJ_LOGWARNING, "not found video stream");
    }
    GInt32 aStream = av_find_best_stream(pull->formatContext, AVMEDIA_TYPE_AUDIO,
                                         -1, -1, NULL, 0);
    if (aStream < 0) {
        GJLOG(GJ_LOGWARNING, "not found audio stream");
    }

    return GNULL;
}
//所有不阻塞
GBool GJStreamPull_Create(GJStreamPull** pullP,StreamPullMessageCallback callback,GHandle streamPullParm){
    GJStreamPull* pull = NULL;
    if (*pullP == NULL) {
        pull = (GJStreamPull*)malloc(sizeof(GJStreamPull));
    }else{
        pull = *pullP;
    }
    GInt32 ret = avformat_network_init();
    if (ret < 0) {
        return GFalse;
    }
    av_register_all();

    memset(pull, 0, sizeof(GJStreamPull));
    pull->formatContext = avformat_alloc_context();
    
    pull->messageCallback = callback;
    pull->messageCallbackParm = streamPullParm;
    pull->stopRequest = GFalse;
    pthread_mutex_init(&pull->mutex, NULL);
    *pullP = pull;
    return GTrue;
}
GVoid GJStreamPull_Delloc(GJStreamPull* pull){
    if (pull) {
        avformat_free_context(pull->formatContext);
        free(pull);
        GJLOG(GJ_LOGDEBUG, "GJStreamPull_Delloc:%p",pull);
    }else{
        GJLOG(GJ_LOGWARNING, "GJStreamPull_Delloc NULL PULL");
    }
}
GVoid GJStreamPull_Release(GJStreamPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJStreamPull_Release:%p",pull);
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->messageCallback = NULL;
    pull->releaseRequest = GTrue;
    if (pull->pullThread == NULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJStreamPull_Delloc(pull);
    }
}
GVoid GJStreamPull_Close(GJStreamPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJStreamPull_Close:%p",pull);
    pull->stopRequest = GTrue;
    
}

GVoid GJStreamPull_CloseAndRelease(GJStreamPull* pull){
    GJStreamPull_Close(pull);
    GJStreamPull_Release(pull);
}

GBool GJStreamPull_StartConnect(GJStreamPull* pull,StreamPullDataCallback dataCallback,GHandle callbackParm,const GChar* pullUrl){
    GJLOG(GJ_LOGDEBUG, "GJStreamPull_StartConnect:%p",pull);
    
    if (pull->pullThread != NULL) {
        GJStreamPull_Close(pull);
        pthread_join(pull->pullThread, NULL);
    }
    size_t length = strlen(pullUrl);
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(pull->pullUrl, pullUrl, length+1);
    pull->stopRequest = GFalse;
    pull->dataCallback = dataCallback;
    pull->dataCallbackParm = callbackParm;
    pthread_create(&pull->pullThread, NULL, pullRunloop, pull);
    
    return GTrue;
}
GJTrafficUnit GJStreamPull_GetVideoPullInfo(GJStreamPull* pull);
GJTrafficUnit GJStreamPull_GetAudioPullInfo(GJStreamPull* pull);
