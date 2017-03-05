//
//  GJRtmpPull.c
//  GJCaptureTool
//
//  Created by 未成年大叔 on 17/3/4.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRtmpPull.h"
#include "GJDebug.h"
#include <string.h>
#define BUFFER_CACHE_SIZE 40
#define RTMP_RECEIVE_TIMEOUT    3


void GJRtmpPull_Release(GJRtmpPull* pull);

static bool retainBufferRelease(GJRetainBuffer* buffer){
    RTMPPacket* packet = buffer->parm;
    RTMPPacket_Free(packet);
    free(packet);
    return true;
}
static void* callbackLoop(void* parm){
    GJRtmpPull* pull = (GJRtmpPull*)parm;
    RTMPPacket* packet;
    while (queuePop(pull->pullBufferQueue, (void**)&packet, 10000000) && !pull->stopRequest) {
        GJRTMPDataType dataType = 0;
        if (packet->m_packetType == RTMP_PACKET_TYPE_AUDIO) {
            dataType = RTMP_PACKET_TYPE_AUDIO;
        }else if (packet->m_packetType == RTMP_PACKET_TYPE_VIDEO){
            dataType = RTMP_PACKET_TYPE_VIDEO;
        }else{
            GJPrintf("not media Packet:%d",packet->m_packetType);
            RTMPPacket_Free(packet);
            free(packet);
            continue;
        }

        GJRetainBuffer* retainBuffer;
        retainBufferPack(&retainBuffer, packet->m_body, packet->m_nBodySize, retainBufferRelease, packet);
        pull->dataCallback(dataType,retainBuffer,packet->m_nTimeStamp);
    }
    queueEnablePop(pull->pullBufferQueue, true);
    return NULL;
}
static void* pullRunloop(void* parm){
    GJRtmpPull* pull = (GJRtmpPull*)parm;
    GJRTMPPullMessageType errType = GJRTMPPullMessageType_connectError;
    void* errParm = NULL;
    int ret = RTMP_SetupURL(pull->rtmp, pull->pullUrl);
    if (!ret && pull->messageCallback) {
        errType = GJRTMPPullMessageType_urlPraseError;
        pull->messageCallback(GJRTMPPullMessageType_urlPraseError,pull->rtmpPullParm,NULL);
        goto ERROR;
    }
    
    pull->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    pthread_create(&pull->callbackThread, NULL, callbackLoop, pull);

    while(!pull->stopRequest){
        RTMPPacket* packet = (RTMPPacket*)malloc(sizeof(RTMPPacket));
        memset(packet, 0, sizeof(RTMPPacket));
        if (RTMP_ReadPacket(pull->rtmp, packet)) {
            if(!queuePush(pull->pullBufferQueue, packet, 1000000)){
                RTMPPacket_Free(packet);
                free(packet);
            };
        }else{
            free(packet);
        }
    }
    pthread_join(pull->callbackThread, NULL);
ERROR:
    pull->pullThread = NULL;
    pull->messageCallback(errType,pull->rtmpPullParm,errParm);
    if (pull->stopRequest) {
        GJRtmpPull_Release(pull);
    }
    return NULL;
}
void GJRtmpPull_Create(GJRtmpPull** pullP,PullMessageCallback callback,void* rtmpPullParm){
    GJRtmpPull* pull = NULL;
    if (*pullP == NULL) {
        pull = (GJRtmpPull*)malloc(sizeof(GJRtmpPull));
    }else{
        pull = *pullP;
    }
    memset(pull, 0, sizeof(GJRtmpPull));
    pull->rtmp = RTMP_Alloc();
    RTMP_Init(pull->rtmp);
    
//    GJBufferPoolCreate(&pull->memoryCachePool, true);
    queueCreate(&pull->pullBufferQueue, BUFFER_CACHE_SIZE, true, false);
    pull->messageCallback = callback;
    pull->rtmpPullParm = rtmpPullParm;
    pull->stopRequest = false;
    *pullP = pull;
}
void GJRtmpPull_CloseAndRelease(GJRtmpPull* pull){
    pull->stopRequest = true;
    queueEnablePop(pull->pullBufferQueue, false);//防止临界情况
    queueBroadcastPop(pull->pullBufferQueue);

}

void GJRtmpPush_Release(GJRtmpPull* push){
    GJAssert(!(push->pullThread && !push->stopRequest),"请在stopconnect函数 或者GJRTMPMessageType_closeComplete回调 后调用\n");
    RTMP_Free(push->rtmp);
    GJRetainBuffer* buffer;
    while (queuePop(push->pullBufferQueue, (void**)&buffer, 0)) {
        retainBufferUnRetain(buffer);
    }
    queueRelease(&push->pullBufferQueue);
    free(push);
}

void GJRtmpPull_StartConnect(GJRtmpPull* pull,PullDataCallback dataCallback,const char* pullUrl){
    size_t length = strlen(pullUrl);
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(pull->pullUrl, pullUrl, length+1);
    pull->stopRequest = false;
    pull->dataCallback = dataCallback;
    pthread_create(&pull->pullThread, NULL, pullRunloop, pull);

}
