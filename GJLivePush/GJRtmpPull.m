//
//  GJRtmpPull.c
//  GJCaptureTool
//
//  Created by 未成年大叔 on 17/3/4.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRtmpPull.h"
#include "GJLog.h"
#include "sps_decode.h"
#import "GJLiveDefine.h"
#include <string.h>
#import <Foundation/Foundation.h>
#define BUFFER_CACHE_SIZE 40
#define RTMP_RECEIVE_TIMEOUT    3


void GJRtmpPull_Delloc(GJRtmpPull* pull);

static bool retainBufferRelease(GJRetainBuffer* buffer){
    RTMPPacket* packet = buffer->parm;
    RTMPPacket_Free(packet);
    free(packet);
    free(buffer);
    return true;
}

static void* pullRunloop(void* parm){
    pthread_setname_np("rtmpPullLoop");
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

    
    while(!pull->stopRequest){
        RTMPPacket* packet = (RTMPPacket*)malloc(sizeof(RTMPPacket));
        memset(packet, 0, sizeof(RTMPPacket));
        while (RTMP_ReadPacket(pull->rtmp, packet)) {
            
            if (!RTMPPacket_IsReady(packet) || !packet->m_nBodySize)
            {
                continue;
            }
            
            RTMP_ClientPacket(pull->rtmp, packet);
            
//            static int time = 0;
//            
//            NSData* data = [NSData dataWithBytes:packet->m_body length:packet->m_nBodySize];
//
//            NSLog(@"pull%d,%@",time++,data);
            GJRTMPDataType dataType = 0;
            void* outPoint;
            int outSize;
            if (packet->m_packetType == RTMP_PACKET_TYPE_AUDIO) {
                dataType = GJRTMPAudioData;
                outPoint = packet->m_body+2;
                outSize = packet->m_nBodySize-2;
            }else if (packet->m_packetType == RTMP_PACKET_TYPE_VIDEO){
                dataType = GJRTMPVideoData;
                uint8_t *sps = NULL,*pps = NULL,*pp = NULL;
                uint8_t *body = (uint8_t*)packet->m_body;
                uint8_t *pbody = body;
                int isKey = 0;
                int spsSize = 0,ppsSize = 0,ppSize = 0;
                
                if ((*pbody & 0x0F) == 7) {
                    pbody = body+1;
                    if (*pbody == 0) {//sps pps
                        pbody= body+9;
                        pbody= body+11;
                        spsSize += pbody[0]<<8;
                        spsSize += pbody[1];
                        sps = body +13;
                        
                        pbody = sps+spsSize+1;
                        ppsSize += pbody[0]<<8;
                        ppsSize += pbody[1];
                        pps = pbody+2;
                        pbody = pps+ppsSize;
                        if (pbody+4<body+packet->m_nBodySize) {
                            pbody++;
                        }else{
                            GJLOG(GJ_LOGINFO,"only spspps\n");

                        }
                    }
                    if (*pbody == 1) {//naul
                        find_pp_sps_pps(&isKey, pbody+9,(int)(body+packet->m_nBodySize- pbody-9), &pp, NULL, NULL, NULL, NULL, NULL, NULL);
                    }
                    
                }else{
                    GJLOG(GJ_LOGERROR,"not h264 stream,type:%d\n",body[0] & 0x0F);
                    assert(0);
                }
                
//#define FIND_SPSPPS
#ifdef FIND_SPSPPS
                find_pp_sps_pps(&isKey, (uint8_t*)packet->m_body+9, packet->m_nBodySize-9, &pp, &sps, &spsSize, &pps, &ppsSize, NULL, NULL);
                
                if (pp && sps) {
                    spsSize -= 3;
                    ppsSize -= 9;
                    
                    if(spsSize != 13 || ppsSize != 8){
                        NSData* data = [NSData dataWithBytes:packet->m_body length:packet->m_nBodySize];
                        NSLog(@"sps data:%@",data);
                    }

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
                    
                    GJAssert(0, "数据有误\n");
                    RTMPPacket_Free(packet);
                    free(packet);
                    packet = NULL;
                    break;
                }
#endif
            }else{
                GJLOG(GJ_LOGWARNING,"not media Packet:%p type:%d \n",packet,packet->m_packetType);
                RTMPPacket_Free(packet);
                free(packet);
                packet = NULL;
                break;
            }
            GJH264Packet retainPacket = {0};
            GJRetainBuffer* retainBuffer = NULL;
            retainBufferPack(&retainBuffer, outPoint, outSize, retainBufferRelease, packet);
            pull->dataCallback(pull,dataType,retainBuffer,pull->dataCallbackParm,packet->m_nTimeStamp);
            retainBufferUnRetain(retainBuffer);
            packet = NULL;
            break;
        }
        if (packet) {
            RTMPPacket_Free(packet);
            free(packet);
//            GJAssert(0, "读取数据错误\n");
        }
    }
    errType = GJRTMPPullMessageType_closeComplete;
ERROR:
    pull->messageCallback(pull, errType,pull->messageCallbackParm,errParm);
    
    bool shouldDelloc = false;
    pthread_mutex_lock(&pull->mutex);
    pull->pullThread = NULL;
    if (pull->releaseRequest == true) {
        shouldDelloc = true;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJRtmpPull_Delloc(pull);
    }
    GJLOG(GJ_LOGDEBUG, "pullRunloop end");
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
    pthread_mutex_init(&pull->mutex, NULL);

    *pullP = pull;
}

void GJRtmpPull_Delloc(GJRtmpPull* pull){
    RTMPPacket* packet;
    while (queuePop(pull->pullBufferQueue, (void**)&packet, 0)) {
        RTMPPacket_Free(packet);
        free(packet);
    }
    queueCleanAndFree(&pull->pullBufferQueue);
    free(pull);
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_Delloc");
}
void GJRtmpPull_Close(GJRtmpPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_Close");

    pull->stopRequest = true;
    queueBroadcastPop(pull->pullBufferQueue);

}
void GJRtmpPull_Release(GJRtmpPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_Release");

    bool shouldDelloc = false;
    pthread_mutex_lock(&pull->mutex);
    pull->releaseRequest = true;
    if (pull->pullThread == NULL) {
        shouldDelloc = true;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJRtmpPull_Delloc(pull);
    }
}


void GJRtmpPull_StartConnect(GJRtmpPull* pull,PullDataCallback dataCallback,void* callbackParm,const char* pullUrl){
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_StartConnect");

    if (pull->pullThread != NULL) {
        GJRtmpPull_Close(pull);
        pthread_join(pull->pullThread, NULL);
    }
    size_t length = strlen(pullUrl);
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(pull->pullUrl, pullUrl, length+1);
    pull->stopRequest = false;
    pull->dataCallback = dataCallback;
    pull->dataCallbackParm = callbackParm;
    pthread_create(&pull->pullThread, NULL, pullRunloop, pull);
}
