//
//  GJRtmpSender.c
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJRtmpPush.h"
#import "sps_decode.h"
#define RTMP_RECEIVE_TIMEOUT    3

void GJRtmpPush_Create(GJRtmpPush** sender){
    GJRtmpPush* push = NULL;
    if (*sender == NULL) {
        push = (GJRtmpPush*)malloc(sizeof(GJRtmpPush));
    }else{
        push = *sender;
    }
    push->rtmp = RTMP_Alloc();
    RTMP_Init(push->rtmp);
    *sender = push;
}
void GJRtmpPush_Release(GJRtmpPush** sender){
    GJRtmpPush* push = *sender;
    RTMP_Free(push->rtmp);
}

void GJRtmpPush_SendH264Data(GJRtmpPush* sender,GJRetainBuffer* data,double dts);


void GJRtmpPush_SendAACData(GJRtmpPush* sender,GJRetainBuffer* data,double dts);


int  GJRtmpPush_StartConnect(GJRtmpPush* sender,char* sendUrl){
    int ret = RTMP_SetupURL(sender->rtmp, sendUrl);
    if (!ret) {
        return ret;
    }
    RTMP_EnableWrite(sender->rtmp);
    
    sender->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;

    ret = RTMP_Connect(sender->rtmp, NULL);
    if (!ret) {
        return ret;
    }
    ret = RTMP_ConnectStream(sender->rtmp, 0);
    if (!ret) {
        return ret;
    }
    return 0;
}
void GJRtmpPush_StopConnect(GJRtmpPush* sender){
    RTMP_Close(sender->rtmp);
}

