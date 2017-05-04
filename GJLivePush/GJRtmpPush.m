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

#define BUFFER_CACHE_SIZE 300

typedef struct _GJRTMP_Packet {
    RTMPPacket packet;
    GJRetainBuffer* retainBuffer;
}GJRTMP_Packet;
void GJRtmpPush_Release(GJRtmpPush* push);
void GJRtmpPush_Delloc(GJRtmpPush* push);
void GJRtmpPush_Close(GJRtmpPush* push);
static void* sendRunloop(void* parm){
    pthread_setname_np("rtmpPushLoop");
    GJRtmpPush* push = (GJRtmpPush*)parm;
    GJRTMPPushMessageType errType = GJRTMPPushMessageType_connectError;
    void* errParm = NULL;
    int ret = RTMP_SetupURL(push->rtmp, push->pushUrl);
    if (!ret && push->messageCallback) {
        errType = GJRTMPPushMessageType_urlPraseError;
        goto ERROR;
    }
    GJLOG(GJ_LOGINFO, "RTMP_SetupURL success");
    RTMP_EnableWrite(push->rtmp);
    
    push->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    
    ret = RTMP_Connect(push->rtmp, NULL);
    if (!ret) {
        GJLOG(GJ_LOGERROR, "RTMP_Connect error");
        errType = GJRTMPPushMessageType_connectError;
        goto ERROR;
    }
    GJLOG(GJ_LOGINFO, "RTMP_Connect success");

    ret = RTMP_ConnectStream(push->rtmp, 0);
    if (!ret ) {
        GJLOG(GJ_LOGERROR, "RTMP_ConnectStream error");

        errType = GJRTMPPushMessageType_connectError;
        goto ERROR;
    }else{
        if(push->messageCallback){
            push->messageCallback(push, GJRTMPPushMessageType_connectSuccess,push->rtmpPushParm,NULL);
        }
    }
    GJLOG(GJ_LOGINFO, "RTMP_ConnectStream success");
    GJRTMP_Packet* packet;
    while (!push->stopRequest && queuePop(push->sendBufferQueue, (void**)&packet, INT32_MAX)) {
        

        int iRet = RTMP_SendPacket(push->rtmp,&packet->packet,0);
        
        if (iRet) {
            if (packet->packet.m_packetType == RTMP_PACKET_TYPE_VIDEO) {
                push->videoStatus.leave.byte+=packet->packet.m_nBodySize;
                push->videoStatus.leave.count++;
                push->videoStatus.leave.pts = packet->packet.m_nTimeStamp;
            }else{
                push->audioStatus.leave.byte+=packet->packet.m_nBodySize;
                push->audioStatus.leave.count++;
                push->audioStatus.leave.pts = packet->packet.m_nTimeStamp;
            }

            retainBufferUnRetain(packet->retainBuffer);
            GJBufferPoolSetData(defauleBufferPool(), (void*)packet);
        }else{
            GJLOG(GJ_LOGERROR, "error send video FRAME");
//            GJAssert(iRet, "error send video FRAME\n");
            errType = GJRTMPPushMessageType_sendPacketError;
            retainBufferUnRetain(packet->retainBuffer);
            GJBufferPoolSetData(defauleBufferPool(), (void*)packet);
            goto ERROR;
        };
    }
    
  

    errType = GJRTMPPushMessageType_closeComplete;
ERROR:
    
    if (push->messageCallback) {
        push->messageCallback(push, errType,push->rtmpPushParm,errParm);
    }
    RTMP_Close(push->rtmp);
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


bool GJRtmpPush_SendH264Data(GJRtmpPush* sender,R_GJH264Packet* packet){
    bool isKey = false;
    uint8_t *sps = packet->sps,*pps = packet->pps,*pp = packet->pp;
    int spsSize = packet->spsSize,ppsSize = packet->ppsSize,ppSize = packet->ppSize;
    
    GJRTMP_Packet* pushPacket = (GJRTMP_Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJRTMP_Packet));
    memset(pushPacket, 0, sizeof(GJRTMP_Packet));
    GJRetainBuffer*retainBuffer = (GJRetainBuffer*)packet;
    pushPacket->retainBuffer = retainBuffer;
    RTMPPacket* sendPacket = &pushPacket->packet;

    unsigned char * body=NULL;
    int iIndex = 0;
    int sps_ppsPreSize = 0,ppPreSize = 0,ppHasPreSize=9;//flv tag前置预留大小大小
   

    if (packet->sps) {
        sps_ppsPreSize = 16;
    }
    if (packet->pp) {
 
        ppPreSize = 9;
        
        if ((pp[4] & 0x1F) == 5) {
            isKey = true;
#ifdef SEND_SEI
            if (packet->sei) {
                pp = packet->sei;
                ppSize += packet->seiSize;
            }
#endif
            ppHasPreSize -= packet->pp - packet->pps - packet->ppsSize;
        }
    }else{
        GJAssert(0, "没有pp");
    }

    if (pp-packet->retain.data < ppPreSize+sps_ppsPreSize+RTMP_MAX_HEADER_SIZE+spsSize+ppsSize) {//申请内存控制得当的话不会进入此条件、  先扩大，在查找。
        retainBufferSetFrontSize(&packet->retain, RTMP_MAX_HEADER_SIZE+spsSize+ppsSize);
        GJLOG(GJ_LOGDEBUG, "预留位置过小,扩大");
    }
//    使用pp做参考点，防止sei不发送的情况，导致pp移动，产生消耗
    sendPacket->m_body = (char*)pp - ppPreSize - sps_ppsPreSize - spsSize - ppsSize;
    sendPacket->m_nBodySize = ppSize+spsSize+ppsSize+ppPreSize+sps_ppsPreSize;
    body = (unsigned char *)sendPacket->m_body;
    sendPacket->m_packetType = RTMP_PACKET_TYPE_VIDEO;
    sendPacket->m_nChannel = 0x04;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType = RTMP_PACKET_SIZE_LARGE;
    sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
    sendPacket->m_nTimeStamp = (uint32_t)packet->pts;
  
    if (sps && pps) {

        //先移动，防止被填充:[13]sps,[13+spsSize+3]pps
        if (ppHasPreSize<0) {//右移动
            pps = memmove(pp - ppPreSize - ppsSize, pps, ppsSize);
            sps = memmove(pp - ppPreSize - ppsSize - spsSize - 3, sps, spsSize);
        }else{
            sps = memmove(pp - ppPreSize - ppsSize - spsSize - 3, sps, spsSize);
            pps = memmove(pp - ppPreSize - ppsSize, pps, ppsSize);
        }


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
        
//        memmove(&body[iIndex],sps,spsSize);
        iIndex +=  spsSize;

        /*pps*/
        body[iIndex++]   = 0x01;
        body[iIndex++] = ((ppsSize) >> 8) & 0xff;
        body[iIndex++] = (ppsSize) & 0xff;
//        memmove(&body[iIndex], pps, ppsSize);
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
        body[iIndex++] = ppSize    &0xff;
        // NALU data
//        memcpy(&body[iIndex],pp,ppSize);   //不需要移动
    }

    retainBufferRetain(retainBuffer);
    if (queuePush(sender->sendBufferQueue, pushPacket, 0)) {
        sender->videoStatus.enter.pts = pushPacket->packet.m_nTimeStamp;
        sender->videoStatus.enter.count++;
        sender->videoStatus.enter.byte += pushPacket->packet.m_nBodySize;
        return true;
    }else{
        retainBufferUnRetain(retainBuffer);
        GJBufferPoolSetData(defauleBufferPool(), (void*)pushPacket);
        return false;
    }
}

bool GJRtmpPush_SendAACData(GJRtmpPush* sender,R_GJAACPacket* buffer){
    unsigned char * body;
    int preSize = 2;
    GJRTMP_Packet* pushPacket = (GJRTMP_Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJRTMP_Packet));

    GJRetainBuffer* retainBuffer = &buffer->retain;
    pushPacket->retainBuffer = retainBuffer;
    
    RTMPPacket* sendPacket = &pushPacket->packet;
    RTMPPacket_Reset(sendPacket);
    if (buffer->adtsOffset+buffer->retain.frontSize < preSize+RTMP_MAX_HEADER_SIZE) {//申请内存控制得当的话不会进入此条件、
        retainBufferSetFrontSize(&buffer->retain, preSize+RTMP_MAX_HEADER_SIZE);
    }

    sendPacket->m_body = (char*)(buffer->adtsOffset +buffer->retain.data - preSize);
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
    retainBufferRetain(retainBuffer);
    
    if (queuePush(sender->sendBufferQueue, pushPacket, 0)) {
        sender->audioStatus.enter.pts = pushPacket->packet.m_nTimeStamp;
        sender->audioStatus.enter.count++;
        sender->audioStatus.enter.byte += pushPacket->packet.m_nBodySize;
        return true;
    }else{
        retainBufferUnRetain(retainBuffer);
        GJBufferPoolSetData(defauleBufferPool(), (void*)pushPacket);
        return false;
    }
}

void  GJRtmpPush_StartConnect(GJRtmpPush* sender,const char* sendUrl){
//    char* p = "GJRtmpPush_StartConnect__test";
//    GJ_Log(GJ_LOGINFO,p,p);
    GJLOG(GJ_LOGINFO,"GJRtmpPush_StartConnect:%p",sender);

    size_t length = strlen(sendUrl);
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(sender->pushUrl, sendUrl, length+1);
    if (sender->sendThread) {
        GJLOG(GJ_LOGWARNING,"上一个push没有释放，开始释放并等待");
        GJRtmpPush_Close(sender);
        pthread_join(sender->sendThread, NULL);
        GJLOG(GJ_LOGWARNING,"等待push释放结束");
    }
    sender->stopRequest = false;
    pthread_create(&sender->sendThread, NULL, sendRunloop, sender);
}
void GJRtmpPush_Delloc(GJRtmpPush* push){

    RTMP_Free(push->rtmp);
    GJRTMP_Packet* packet;
    while (queuePop(push->sendBufferQueue, (void**)&packet, 0)) {
        retainBufferUnRetain(packet->retainBuffer);
        GJBufferPoolSetData(defauleBufferPool(), (void*)packet);
    }
    queueFree(&push->sendBufferQueue);
    free(push);
    GJLOG(GJ_LOGDEBUG, "GJRtmpPush_Delloc:%p",push);

}
void GJRtmpPush_CloseAndRelease(GJRtmpPush* push){
    
    GJRtmpPush_Close(push);
    GJRtmpPush_Release(push);
}
void GJRtmpPush_Release(GJRtmpPush* push){
    GJLOG(GJ_LOGINFO,"GJRtmpPush_Release::%p",push);
    
    bool shouldDelloc = false;
    push->messageCallback = NULL;
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
    if (sender->stopRequest) {
        GJLOG(GJ_LOGINFO,"GJRtmpPush_Close：%p  重复关闭",sender);

    }else{
        GJLOG(GJ_LOGINFO,"GJRtmpPush_Close:%p",sender);
        sender->stopRequest = true;
        queueBroadcastPop(sender->sendBufferQueue);

    }
}


float GJRtmpPush_GetBufferRate(GJRtmpPush* sender){
    long length = queueGetLength(sender->sendBufferQueue);
    float size = sender->sendBufferQueue->allocSize * 1.0;
//    GJPrintf("BufferRate length:%ld ,size:%f   rate:%f\n",length,size,length/size);
    return length / size;
};
GJTrafficStatus GJRtmpPush_GetVideoBufferCacheInfo(GJRtmpPush* push){
    return push->videoStatus;
}
GJTrafficStatus GJRtmpPush_GetAudioBufferCacheInfo(GJRtmpPush* push){
    return push->audioStatus;
}


