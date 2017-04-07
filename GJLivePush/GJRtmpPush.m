//
//  GJRtmpSender.c
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRtmpPush.h"
#include "GJLog.h"
#import <Foundation/Foundation.h>
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
            free(packet);
        }else{
            GJAssert(iRet, "error send video FRAME\n");
            errType = GJRTMPPushMessageType_sendPacketError;
            retainBufferUnRetain(packet->retainBuffer);
            free(packet);
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
    
    queueCreate(&push->sendBufferQueue, BUFFER_CACHE_SIZE, true, false);
    push->messageCallback = callback;
    push->rtmpPushParm = rtmpPushParm;
    push->stopRequest = false;
    push->releaseRequest = false;
    pthread_mutex_init(&push->mutex, NULL);

    *sender = push;
}


void GJRtmpPush_SendH264Data(GJRtmpPush* sender,R_GJH264Packet* packet){
    if (sender->stopRequest) {
       
        return;
    }

//    static int time1 = 0;
//    NSData* data1 = [NSData dataWithBytes:buffer->data length:buffer->size];
//    NSLog(@"push%d:%@",time1++,data1);
    
    uint8_t *sps = packet->sps,*pps = packet->pps,*pp = packet->pp;
    int spsSize = packet->spsSize,ppsSize = packet->ppsSize,ppSize = packet->ppSize;
    
    GJRTMP_Packet* pushPacket = (GJRTMP_Packet*)malloc(sizeof(GJRTMP_Packet));
    memset(pushPacket, 0, sizeof(GJRTMP_Packet));
    GJRetainBuffer*retainBuffer = (GJRetainBuffer*)packet;
    pushPacket->retainBuffer = retainBuffer;
    RTMPPacket* sendPacket = &pushPacket->packet;

    unsigned char * body=NULL;
    int iIndex = 0;
    int preSize = 0;//前面额外需要的空间；
    int spsPreSize = 16,ppPreSize = 9;//flv tag前置预留大小大小
   

    if (packet->sps) {
        preSize += spsPreSize;
    }
    if (packet->pp) {
        preSize += ppPreSize;
        sendPacket->m_body = (char*)packet->pp - preSize-spsSize-ppsSize;
        sendPacket->m_nBodySize = preSize + packet->ppSize;
    }
#ifdef SEND_SEI
    if (packet->sei) {
        sendPacket->m_body = (char*)packet->sei - preSize-spsSize-ppsSize;
        sendPacket->m_nBodySize += packet->seiSize;
    }
#endif
    if (packet->pp-packet->retain.data < preSize+RTMP_MAX_HEADER_SIZE+spsSize+ppsSize) {//申请内存控制得当的话不会进入此条件、  先扩大，在查找。
        GJAssert(0, "预留位置过小");
    }

    body = (unsigned char *)sendPacket->m_body;
    sendPacket->m_packetType = RTMP_PACKET_TYPE_VIDEO;
    sendPacket->m_nChannel = 0x04;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType = RTMP_PACKET_SIZE_LARGE;
    sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
    sendPacket->m_nTimeStamp = (uint32_t)packet->pts;
  
    if (sps && pps) {
        GJLOG(GJ_LOGINFO, "spsSize:%d,ppsSize:%d",spsSize,ppsSize);
        GJAssert(ppsSize > 4 && spsSize>4, "pps errpr");
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

        if((packet->pp[4] & 0x1F) == 5)
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
        body[iIndex++] = ppSize    &0xff;
        // NALU data
//        memcpy(&body[iIndex],pp,ppSize);   //不需要移动
    }

      if(sender->stopRequest || !queuePush(sender->sendBufferQueue, pushPacket, 0)){
          free(pushPacket);
          sender->dropPacketCount++;
      }else{
          retainBufferRetain(retainBuffer);
          sender->inPts = pushPacket->packet.m_nTimeStamp;
      }
}

void GJRtmpPush_SendAACData(GJRtmpPush* sender,R_GJAACPacket* buffer){
    if (sender->stopRequest) {
        return;
    }
    unsigned char * body;
    int preSize = 2;
    GJRTMP_Packet* pushPacket = (GJRTMP_Packet*)malloc(sizeof(GJRTMP_Packet));
    GJRetainBuffer* retainBuffer = (GJRetainBuffer*)buffer;
    pushPacket->retainBuffer = retainBuffer;
    
    RTMPPacket* sendPacket = &pushPacket->packet;
    RTMPPacket_Reset(sendPacket);
    if (buffer->adts - buffer->retain.data < preSize+RTMP_MAX_HEADER_SIZE) {//申请内存控制得当的话不会进入此条件、
        GJAssert(0, "预留内存不够");
//        retainBufferSetFrontSize(buffer, preSize);
    }

    sendPacket->m_body = (char*)buffer->adts - preSize;
    sendPacket->m_nBodySize = buffer->adtsSize+buffer->aacSize+preSize;

    body = (unsigned char *)sendPacket->m_body;
    
    /*AF 01 + AAC RAW data*/
    body[0] = 0xAF;
    body[1] = 0x01;
    
    sendPacket->m_packetType = RTMP_PACKET_TYPE_AUDIO;
    sendPacket->m_nChannel = 0x04;
    sendPacket->m_nTimeStamp = (int32_t)buffer->pts;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType = RTMP_PACKET_SIZE_LARGE;
    sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
    if(!queuePush(sender->sendBufferQueue, pushPacket, 0)){
        free(pushPacket);
        sender->dropPacketCount++;
    }else{
        retainBufferRetain(retainBuffer);
        sender->inPts = pushPacket->packet.m_nTimeStamp;
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
    }
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


