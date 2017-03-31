//
//  GJRtmpSender.c
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRtmpPush.h"
#include "GJLog.h"

//extern "C"{
#include "sps_decode.h"
//}
#include <pthread.h>

#define RTMP_RECEIVE_TIMEOUT    3

#define BUFFER_CACHE_SIZE 40

typedef struct _GJRTMP_Packet {
    RTMPPacket packet;
    GJRetainBuffer* retainBuffer;
}GJRTMP_Packet;
void GJRtmpPush_Release(GJRtmpPush* push);
void GJRtmpPush_Delloc(GJRtmpPush* push);

static void* sendRunloop(void* parm){
    pthread_setname_np("rtmpPushLoop");
    GJRtmpPush* push = (GJRtmpPush*)parm;
    GJRTMPPushMessageType errType = GJRTMPPushMessageType_connectError;
    void* errParm = NULL;
    int ret = RTMP_SetupURL(push->rtmp, push->pushUrl);
    if (!ret && push->messageCallback) {
        errType = GJRTMPPushMessageType_urlPraseError;
        push->messageCallback(push, GJRTMPPushMessageType_urlPraseError,push->rtmpPushParm,NULL);
        goto ERROR;
    }
    RTMP_EnableWrite(push->rtmp);
    
    push->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    
    ret = RTMP_Connect(push->rtmp, NULL);
    if (!ret && push->messageCallback) {
        errType = GJRTMPPushMessageType_connectError;
        goto ERROR;
    }
    ret = RTMP_ConnectStream(push->rtmp, 0);
    if (!ret && push->messageCallback) {

        errType = GJRTMPPushMessageType_connectError;
        goto ERROR;
    }else{
        push->messageCallback(push, GJRTMPPushMessageType_connectSuccess,push->rtmpPushParm,NULL);
    }
    
    GJRTMP_Packet* packet;
    while (!push->stopRequest && queuePop(push->sendBufferQueue, (void**)&packet, INT32_MAX)) {
        push->outPts = packet->packet.m_nTimeStamp;
        int iRet = RTMP_SendPacket(push->rtmp,&packet->packet,0);
//        static int i = 0;
//        GJPrintf("sendcount:%d,pts:%d\n",i++,packet->packet.m_nTimeStamp);
        if (iRet) {
            push->sendByte += packet->retainBuffer->size;
            push->sendPacketCount ++;
            retainBufferUnRetain(packet->retainBuffer);
            GJBufferPoolSetData(push->memoryCachePool, packet);
        }else{
            GJAssert(iRet, "error send video FRAME\n");
            errType = GJRTMPPushMessageType_sendPacketError;
            retainBufferUnRetain(packet->retainBuffer);
            GJBufferPoolSetData(push->memoryCachePool, packet);
            goto ERROR;
        };

    }
    
  

    errType = GJRTMPPushMessageType_closeComplete;
ERROR:
    
    RTMP_Close(push->rtmp);
    push->messageCallback(push, errType,push->rtmpPushParm,errParm);

    bool shouldDelloc = false;
    pthread_mutex_lock(&push->mutex);
    push->sendThread = NULL;
    if (push->releaseRequest == true) {
        shouldDelloc = true;
    }
    pthread_mutex_unlock(&push->mutex);
    if (shouldDelloc) {
        GJRtmpPush_Delloc(push);
    }
    GJLOG(GJ_LOGINFO,"sendRunloop end");

    return NULL;
}

void GJRtmpPush_Create(GJRtmpPush** sender,PullMessageCallback callback,void* rtmpPushParm){
    GJRtmpPush* push = NULL;
    if (*sender == NULL) {
        push = (GJRtmpPush*)malloc(sizeof(GJRtmpPush));
    }else{
        push = *sender;
    }
    memset(push, 0, sizeof(GJRtmpPush));
    push->rtmp = RTMP_Alloc();
    RTMP_Init(push->rtmp);
    
    GJBufferPoolCreate(&push->memoryCachePool, true);
    queueCreate(&push->sendBufferQueue, BUFFER_CACHE_SIZE, true, false);
    push->messageCallback = callback;
    push->rtmpPushParm = rtmpPushParm;
    push->stopRequest = false;
    push->releaseRequest = false;
    pthread_mutex_init(&push->mutex, NULL);

    *sender = push;
}


void GJRtmpPush_SendH264Data(GJRtmpPush* sender,GJRetainBuffer* buffer,uint32_t pts){
    if (sender->stopRequest) {
       
        return;
    }

    
    uint8_t *sps = NULL,*pps = NULL,*pp = NULL;
    int isKey = 0;
    int spsSize = 0,ppsSize = 0,ppSize = 0;
    
    GJRTMP_Packet* packet = (GJRTMP_Packet*)GJBufferPoolGetData(sender->memoryCachePool, sizeof(GJRTMP_Packet));
    packet->retainBuffer = buffer;
    
    RTMPPacket* sendPacket = &packet->packet;
    unsigned char * body=NULL;
    int iIndex = 0;
    int preSize = 0;//前面额外需要的空间；
    int spsPreSize = 16,ppPreSize = 9;//flv tag前置预留大小大小
    preSize = ppPreSize + spsPreSize;
    if (buffer->frontSize < preSize+RTMP_MAX_HEADER_SIZE) {//申请内存控制得当的话不会进入此条件、  先扩大，在查找。
        retainBufferSetFrontSize(buffer, preSize+RTMP_MAX_HEADER_SIZE);
    }
    find_pp_sps_pps(&isKey, (uint8_t*)buffer->data, buffer->size, &pp, &sps, &spsSize, &pps, &ppsSize, NULL, NULL);

    if (pp) {
        ppSize = (int)((uint8_t*)buffer->data + buffer->size - pp);//ppsSize最好通过计算获得，直接查找的话查找数据量比较大
    }
    RTMPPacket_Reset(sendPacket);

    sendPacket->m_body = (char*)buffer->data - preSize;
    body = (unsigned char *)sendPacket->m_body;
    sendPacket->m_packetType = RTMP_PACKET_TYPE_VIDEO;
    sendPacket->m_nChannel = 0x04;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType = RTMP_PACKET_SIZE_LARGE;
    sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
    sendPacket->m_nTimeStamp = pts;
    sendPacket->m_nBodySize = preSize + buffer->size;
  
    if (sps && pps) {
        body[iIndex++] = 0x17;
        body[iIndex++] = 0x00;
        
        body[iIndex++] = 0x00;
        body[iIndex++] = 0x00;
        body[iIndex++] = 0x00;
        
        body[iIndex++] = 0x01;
        body[iIndex++] = sps[1+4];
        body[iIndex++] = sps[2+4];
        body[iIndex++] = sps[3+4];
        body[iIndex++] = 0xff;
        
        /*sps*/
        body[iIndex++]   = 0xe1;
        body[iIndex++] = (spsSize >> 8) & 0xff;
        body[iIndex++] = spsSize & 0xff;
        
        memmove(&body[iIndex],sps,spsSize);
        iIndex +=  spsSize;

        /*pps*/
        body[iIndex++]   = 0x01;
        body[iIndex++] = ((ppsSize) >> 8) & 0xff;
        body[iIndex++] = (ppsSize) & 0xff;
        memmove(&body[iIndex], pps, ppsSize);
        iIndex +=  ppsSize;
    }
    
    if (pp) {

        if(isKey)
        {
            body[iIndex++] = 0x17;// 1:Iframe  7:AVC
        }
        else
        {
            body[iIndex++] = 0x27;// 2:Pframe  7:AVC
        }
        body[iIndex++] = 0x01;// AVC NALU
        body[iIndex++] = 0x00;
        body[iIndex++] = 0x00;
        body[iIndex++] = 0x00;
        // NALU size
        body[iIndex++] = ppSize>>24 &0xff;
        body[iIndex++] = ppSize>>16 &0xff;
        body[iIndex++] = ppSize>>8 &0xff;
        body[iIndex++] = ppSize&0xff;
        // NALU data
//        memcpy(&body[iIndex],pp,ppSize);   //不需要移动
    }
      if(sender->stopRequest || !queuePush(sender->sendBufferQueue, packet, 0)){
        GJBufferPoolSetData(sender->memoryCachePool, packet);
        sender->dropPacketCount++;
      }else{
          retainBufferRetain(buffer);
          sender->inPts = packet->packet.m_nTimeStamp;
      }
}

void GJRtmpPush_SendAACData(GJRtmpPush* sender,GJRetainBuffer* buffer,uint32_t dts){
    if (sender->stopRequest) {
        return;
    }
    unsigned char * body;
    int preSize = 2+RTMP_MAX_HEADER_SIZE;
    GJRTMP_Packet* packet = (GJRTMP_Packet*)GJBufferPoolGetData(sender->memoryCachePool, sizeof(GJRTMP_Packet));
    packet->retainBuffer = buffer;
    
    RTMPPacket* sendPacket = &packet->packet;
    RTMPPacket_Reset(sendPacket);
    if (buffer->frontSize < preSize) {//申请内存控制得当的话不会进入此条件、
        retainBufferSetFrontSize(buffer, preSize);
    }

    sendPacket->m_body = (char*)buffer->data - 2;
    body = (unsigned char *)sendPacket->m_body;
    
    /*AF 01 + AAC RAW data*/
    body[0] = 0xAF;
    body[1] = 0x01;
    memcpy(&body[2],buffer->data,buffer->size);
    
    sendPacket->m_packetType = RTMP_PACKET_TYPE_AUDIO;
    sendPacket->m_nBodySize = buffer->size+2;
    sendPacket->m_nChannel = 0x04;
    sendPacket->m_nTimeStamp = dts;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType = RTMP_PACKET_SIZE_LARGE;
    sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
    if(!queuePush(sender->sendBufferQueue, packet, 0)){
        GJBufferPoolSetData(sender->memoryCachePool, packet);
        sender->dropPacketCount++;
    }else{
        retainBufferRetain(buffer);
        sender->inPts = packet->packet.m_nTimeStamp;
    }
}

void  GJRtmpPush_StartConnect(GJRtmpPush* sender,const char* sendUrl){
    GJLOG(GJ_LOGINFO,"GJRtmpPush_StartConnect");

    size_t length = strlen(sendUrl);
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(sender->pushUrl, sendUrl, length+1);
    if (sender->sendThread) {
        GJRtmpPush_Close(sender);
        pthread_join(sender->sendThread, NULL);
    }
    sender->stopRequest = false;
    pthread_create(&sender->sendThread, NULL, sendRunloop, sender);
}
void GJRtmpPush_Delloc(GJRtmpPush* push){

    RTMP_Free(push->rtmp);
    GJRTMP_Packet* packet;
    while (queuePop(push->sendBufferQueue, (void**)&packet, 0)) {
        retainBufferUnRetain(packet->retainBuffer);
        GJBufferPoolSetData(push->memoryCachePool, packet);
    }
    GJBufferPoolCleanAndFree(&push->memoryCachePool);
    queueCleanAndFree(&push->sendBufferQueue);
    free(push);
    GJLOG(GJ_LOGDEBUG, "GJRtmpPush_Delloc");

}

void GJRtmpPush_Release(GJRtmpPush* push){
    GJLOG(GJ_LOGINFO,"GJRtmpPush_Release");
    
    bool shouldDelloc = false;
    pthread_mutex_lock(&push->mutex);
    push->releaseRequest = true;
    if (push->sendThread == NULL) {
        shouldDelloc = true;
    }
    pthread_mutex_unlock(&push->mutex);
    if (shouldDelloc) {
        GJRtmpPush_Delloc(push);
    }
}
void GJRtmpPush_Close(GJRtmpPush* sender){
    GJLOG(GJ_LOGINFO,"GJRtmpPush_Close");
    sender->stopRequest = true;
    queueBroadcastPop(sender->sendBufferQueue);
}


float GJRtmpPush_GetBufferRate(GJRtmpPush* sender){
    long length = queueGetLength(sender->sendBufferQueue);
    float size = sender->sendBufferQueue->allocSize * 1.0;
//    GJPrintf("BufferRate length:%ld ,size:%f   rate:%f\n",length,size,length/size);
    return length / size;
};
GJCacheInfo GJRtmpPush_GetBufferCacheInfo(GJRtmpPush* sender){
    GJCacheInfo value = {0};
    value.cacheCount = (int)queueGetLength(sender->sendBufferQueue);
    value.cacheTime = (int)(sender->inPts - sender->outPts);
    return value;
}


