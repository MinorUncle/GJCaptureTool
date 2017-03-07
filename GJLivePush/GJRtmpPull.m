//
//  GJRtmpPull.c
//  GJCaptureTool
//
//  Created by 未成年大叔 on 17/3/4.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRtmpPull.h"
#include "GJDebug.h"
#include "sps_decode.h"
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
        void* outPoint;
        int outSize;
        if (packet->m_packetType == RTMP_PACKET_TYPE_AUDIO) {
            dataType = GJRTMPAudioData;
            outPoint = packet->m_body;
            outSize = packet->m_nBodySize;
        }else if (packet->m_packetType == RTMP_PACKET_TYPE_VIDEO){
            dataType = GJRTMPVideoData;
            uint8_t *sps = NULL,*pps = NULL,*pp = NULL;
            int isKey = 0;
            int spsSize = 0,ppsSize = 0,ppSize = 0;
            find_pp_sps_pps(&isKey, (uint8_t*)packet->m_body, packet->m_nBodySize, &pp, &sps, &spsSize, &pps, &ppsSize, NULL, NULL);
            
            if (pp && sps) {
                ppSize = (int)((uint8_t*)packet->m_body + packet->m_nBodySize - pp);//ppSize最好通过计算获得，直接查找的话查找数据量比较大
                pps = memmove(pp-ppsSize, pps, ppsSize);
                sps = memmove(pps-spsSize, sps, spsSize);
                outPoint = sps;
                outSize = spsSize+ppsSize+ppSize;
            }else if(pp){
                ppSize = (int)((uint8_t*)packet->m_body + packet->m_nBodySize - pp);//ppSize最好通过计算获得，直接查找的话查找数据量比较大
                outPoint = pp;
                outSize = ppSize;
            }else{
                NSData* data = [NSData dataWithBytes:packet->m_body length:packet->m_nBodySize];
                NSLog(@"data:%@",data);
                GJAssert(0, "数据有误\n");
            }
        }else{
            GJPrintf("not media Packet:%p type:%d \n",packet,packet->m_packetType);
            RTMPPacket_Free(packet);
            free(packet);
            continue;
        }

        GJRetainBuffer* retainBuffer;
        retainBufferPack(&retainBuffer, outPoint, outSize, retainBufferRelease, packet);
        static int count = 0;
        printf("pull count:%d  pts:%d\n",count++,packet->m_nTimeStamp);
        pull->dataCallback(pull,dataType,retainBuffer,pull->dataCallbackParm,packet->m_nTimeStamp);
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
        pull->messageCallback(pull,GJRTMPPullMessageType_urlPraseError,pull->messageCallbackParm,NULL);
        goto ERROR;
    }
    pull->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    
    ret = RTMP_Connect(pull->rtmp, NULL);
    if (!ret && pull->messageCallback) {
        RTMP_Close(pull->rtmp);
        errType = GJRTMPPullMessageType_connectError;
        goto ERROR;
    }
    ret = RTMP_ConnectStream(pull->rtmp, 0);
    if (!ret && pull->messageCallback) {
        RTMP_Close(pull->rtmp);
        
        errType = GJRTMPPullMessageType_connectError;
        goto ERROR;
    }else{
        pull->messageCallback(pull, GJRTMPPullMessageType_connectSuccess,pull->messageCallbackParm,NULL);
    }

    
    pthread_create(&pull->callbackThread, NULL, callbackLoop, pull);

    while(!pull->stopRequest){
        RTMPPacket* packet = (RTMPPacket*)malloc(sizeof(RTMPPacket));
        memset(packet, 0, sizeof(RTMPPacket));
        while (RTMP_ReadPacket(pull->rtmp, packet)) {
            
            if (!RTMPPacket_IsReady(packet) || !packet->m_nBodySize)
            {
 
                continue;
            }
            
            RTMP_ClientPacket(pull->rtmp, packet);
            bool ret = queuePush(pull->pullBufferQueue, packet, 1000000);
            GJAssert(ret, "queuePush 不可能失败的失败\n");
            packet = NULL;
            break;
        }
        if (packet) {
            RTMPPacket_Free(packet);
            free(packet);
//            GJAssert(0, "读取数据错误\n");
        }
    }
    pthread_join(pull->callbackThread, NULL);
    pull->callbackThread = NULL;
ERROR:
    pull->messageCallback(pull, errType,pull->messageCallbackParm,errParm);
    GJRtmpPull_Release(pull);
    if (pull->stopRequest) {
        free(pull);
    }else{
        pull->pullThread = NULL;
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
    pull->messageCallbackParm = rtmpPullParm;
    pull->stopRequest = false;
    *pullP = pull;
}
void GJRtmpPull_CloseAndRelease(GJRtmpPull* pull){
    if (pull->pullThread == NULL) {
        free(pull);
    }else{
        pull->stopRequest = true;
        queueEnablePop(pull->pullBufferQueue, false);//防止临界情况
        queueBroadcastPop(pull->pullBufferQueue);
    }
}

void GJRtmpPull_Release(GJRtmpPull* push){
    GJAssert(!(push->pullThread && !push->stopRequest),"请在stopconnect函数 或者GJRTMPMessageType_closeComplete回调 后调用\n");
    RTMP_Free(push->rtmp);
    GJRetainBuffer* buffer;
    while (queuePop(push->pullBufferQueue, (void**)&buffer, 0)) {
        retainBufferUnRetain(buffer);
    }
    queueRelease(&push->pullBufferQueue);
}

void GJRtmpPull_StartConnect(GJRtmpPull* pull,PullDataCallback dataCallback,void* callbackParm,const char* pullUrl){
    size_t length = strlen(pullUrl);
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(pull->pullUrl, pullUrl, length+1);
    pull->stopRequest = false;
    pull->dataCallback = dataCallback;
    pull->dataCallbackParm = callbackParm;
    pthread_create(&pull->pullThread, NULL, pullRunloop, pull);
}
