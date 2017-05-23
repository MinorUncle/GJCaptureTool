//
//  GJLivePushContext.c
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLivePushContext.h"
#include "GJLog.h"
#include "GJUtil.h"

GVoid rtmpPushMessageCallback(GHandle userData, GJRTMPPushMessageType messageType,GHandle messageParm){
    GJLivePushContext* context = userData;
    switch (messageType) {
        case GJRTMPPushMessageType_connectSuccess:
        {
            GJLOG(GJ_LOGINFO, "推流连接成功");
            context->connentClock = GJ_Gettime()/1000;
            
//            [livePush.delegate livePush:livePush connentSuccessWithElapsed:[livePush.connentDate timeIntervalSinceDate:livePush.startPushDate]*1000];
//            [livePush pushRun];
        }
            break;
        case GJRTMPPushMessageType_closeComplete:{
            GJPushSessionInfo info = {0};
            NSDate* stopDate = [NSDate date];
            info.sessionDuring = [stopDate timeIntervalSinceDate:livePush.startPushDate]*1000;
            [livePush.delegate livePush:livePush closeConnent:&info resion:kConnentCloce_Active];
        }
            break;
        case GJRTMPPushMessageType_urlPraseError:
        case GJRTMPPushMessageType_connectError:
            GJLOG(GJ_LOGINFO, "推流连接失败");
            [livePush.delegate livePush:livePush errorType:kLivePushConnectError infoDesc:@"rtmp连接失败"];
            [livePush stopStreamPush];
            break;
        case GJRTMPPushMessageType_sendPacketError:
            [livePush.delegate livePush:livePush errorType:kLivePushWritePacketError infoDesc:@"发送失败"];
            [livePush stopStreamPush];
            break;
        default:
            break;
    }

}
GBool GJLivePush_Create(GJLivePushContext** pushContext,GJLivePushCallback callback,GHandle param){
    GBool result = GFalse;
    do{
        if (*pushContext == GNULL) {
            *pushContext = (GJLivePushContext*)calloc(1,sizeof(GJLivePushContext));
            if (*pushContext == GNULL) {
                result = GFalse;
                break;
            }
        }
        GJLivePushContext* context = *pushContext;
        context->callback = callback;
        context->userData = param;
        GJ_H264EncodeContextCreate(&context->videoEncoder);
        GJ_AACEncodeContextCreate(&context->audioEncoder);
        GJ_VideoProduceContextCreate(&context->videoProducer);
        GJ_AudioProduceContextCreate(&context->audioProducer);
        pthread_mutex_init(&context->lock, GNULL);
    }while (0);
    return result;

}
GBool GJLivePush_StartPush(GJLivePushContext* context,GChar* url){
    GBool result = GTrue;
    do{
        pthread_mutex_lock(&context->lock);
        if (context->videoPush != GNULL) {
            GJLOG(GJ_LOGERROR, "请先停止上一个流");
        }else{
            context->fristAudioEncodeClock = context->fristVideoEncodeClock = context->connentClock = G_TIME_INVALID;
            context->audioTraffic = context->videoTraffic = (GJTrafficStatus){0};
        
            if(!GJRtmpPush_Create(&context->videoPush, rtmpPushMessageCallback, (GHandle)context)){
                result = GFalse;
                break;
            };
            context->startPushClock = GJ_Gettime()/1000;
        }
        pthread_mutex_unlock(&context->lock);
    }while (0);
    return result;
    
}
GVoid GJLivePush_StopPush(GJLivePushContext* context){
    pthread_mutex_lock(&context->lock);
    if (context->videoPush) {
        GJRtmpPush_CloseAndDealloc(&context->videoPush);
        context->audioProducer->audioProduceStop(context->audioProducer);
        context->videoProducer->stopProduce(context->videoProducer);
        context->audioEncoder->encodeUnSetup(context->audioEncoder);
        context->videoEncoder->encodeUnSetup(context->videoEncoder);
    }else{
        GJLOG(GJ_LOGWARNING, "重复停止拉流");
    }
    pthread_mutex_unlock(&context->lock);
}
GBool GJLivePush_StartPreview(GJLivePushContext* context,GChar* url){
    return context->videoProducer->startPreview(context->videoProducer);
}
GVoid GJLivePush_StopPreview(GJLivePushContext* context){
    return context->videoProducer->stopPreview(context->videoProducer);
}
GVoid GJLivePush_Dealloc(GJLivePushContext** pushContext){
    GJLivePushContext* context = *pushContext;
    if (context == GNULL) {
        GJLOG(GJ_LOGERROR, "非法释放");
    }else{
        GJ_H264EncodeContextDealloc(&context->videoEncoder);
        GJ_AACEncodeContextDealloc(&context->audioEncoder);
        GJ_VideoProduceContextDealloc(&context->videoProducer);
        GJ_AudioProduceContextDealloc(&context->audioProducer);
        free(context);
        *pushContext = GNULL;
    }

}
GJTrafficStatus GJLivePush_GetVideoTrafficStatus(GJLivePushContext* context){
    return context->videoTraffic;
}
GJTrafficStatus GJLivePush_GetAudioTrafficStatus(GJLivePushContext* context){
    return context->audioTraffic;
}
GHandle GJLivePush_GetDisplayView(GJLivePushContext* context){
    return context->videoProducer->getRenderView(context->videoProducer);
}
