//
//  GJRtmpSender.c
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRtmpPush.h"
#include "GJLog.h"
#include "log.h"
#import <Foundation/Foundation.h>
//extern "C"{
#include "sps_decode.h"
//}
#include "GJUtil.h"
#include <pthread.h>

#define RTMP_RECEIVE_TIMEOUT    3

#define BUFFER_CACHE_SIZE 300

typedef struct _GJRTMP_Packet {
    RTMPPacket packet;
    GJRetainBuffer* retainBuffer;
}GJRTMP_Packet;
GVoid GJRtmpPush_Release(GJRtmpPush* push);
GVoid GJRtmpPush_Delloc(GJRtmpPush* push);
GVoid GJRtmpPush_Close(GJRtmpPush* push);
static GHandle sendRunloop(GHandle parm){
    pthread_setname_np("rtmpPushLoop");
    GJRtmpPush* push = (GJRtmpPush*)parm;
    GJRTMPPushMessageType errType = GJRTMPPushMessageType_connectError;
    GHandle errParm = GNULL;
    GInt32 ret = RTMP_SetupURL(push->rtmp, push->pushUrl);
    if (!ret && push->messageCallback) {
        errType = GJRTMPPushMessageType_urlPraseError;
        goto ERROR;
    }
    GJLOG(GJ_LOGINFO, "RTMP_SetupURL success");
    RTMP_EnableWrite(push->rtmp);
    
    push->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    GJLOG(GJ_LOGINFO, "开始连接服务器。。。");
    ret = RTMP_Connect(push->rtmp, GNULL);
    if (!ret) {
        GJLOG(GJ_LOGERROR, "RTMP_Connect error");
        errType = GJRTMPPushMessageType_connectError;
        goto ERROR;
    }
    GJLOG(GJ_LOGINFO, "服务器连接成功，开始连接流");

    ret = RTMP_ConnectStream(push->rtmp, 0);
    if (!ret ) {
        GJLOG(GJ_LOGERROR, "RTMP_ConnectStream error");
        errType = GJRTMPPushMessageType_connectError;
        goto ERROR;
    }else{
        if(push->messageCallback){
            push->messageCallback(push->rtmpPushParm, GJRTMPPushMessageType_connectSuccess,GNULL);
        }
    }
    GJLOG(GJ_LOGINFO, "RTMP_ConnectStream success");
    GJRTMP_Packet* packet;
#ifdef NETWORK_DELAY
    GUInt32 startPts = (GUInt32)(GJ_Gettime()/1000);
#endif
    while (!push->stopRequest && queuePop(push->sendBufferQueue, (GHandle*)&packet, INT32_MAX)) {
#ifdef NETWORK_DELAY
        packet->packet.m_nTimeStamp -= startPts;
#endif
        GInt32 iRet = RTMP_SendPacket(push->rtmp,&packet->packet,0);
        if (iRet) {
            if (packet->packet.m_packetType == RTMP_PACKET_TYPE_VIDEO) {
                GJLOGFREQ("send video pts:%d size:%d",packet->packet.m_nTimeStamp,packet->packet.m_nBodySize);
                push->videoStatus.leave.byte+=packet->packet.m_nBodySize;
                push->videoStatus.leave.count++;
                push->videoStatus.leave.pts = packet->packet.m_nTimeStamp;
            }else{
                GJLOGFREQ("send audio pts:%d size:%d",packet->packet.m_nTimeStamp,packet->packet.m_nBodySize);
                push->audioStatus.leave.byte+=packet->packet.m_nBodySize;
                push->audioStatus.leave.count++;
                push->audioStatus.leave.pts = packet->packet.m_nTimeStamp;
            }
            retainBufferUnRetain(packet->retainBuffer);
            GJBufferPoolSetData(defauleBufferPool(), (GHandle)packet);
        }else{
            GJLOG(GJ_LOGFORBID, "error send video FRAME");
            errType = GJRTMPPushMessageType_sendPacketError;
            retainBufferUnRetain(packet->retainBuffer);
            GJBufferPoolSetData(defauleBufferPool(), (GHandle)packet);
            goto ERROR;
        };
    }

    errType = GJRTMPPushMessageType_closeComplete;
ERROR:
    
    if (push->messageCallback) {
        push->messageCallback(push->rtmpPushParm, errType,errParm);
    }
    RTMP_Close(push->rtmp);
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&push->mutex);
    push->sendThread = GNULL;
    if (push->releaseRequest == GTrue) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&push->mutex);
    if (shouldDelloc) {
        GJRtmpPush_Delloc(push);
    }
    GJLOG(GJ_LOGINFO,"sendRunloop end");

    return GNULL;
}

GBool GJRtmpPush_Create(GJRtmpPush** sender,PushMessageCallback callback,GHandle rtmpPushParm){
    GJRtmpPush* push = GNULL;
    if (*sender == GNULL) {
        push = (GJRtmpPush*)malloc(sizeof(GJRtmpPush));
    }else{
        push = *sender;
    }
    memset(push, 0, sizeof(GJRtmpPush));
    push->rtmp = RTMP_Alloc();
    RTMP_Init(push->rtmp);
    
    queueCreate(&push->sendBufferQueue, BUFFER_CACHE_SIZE, GTrue, GTrue);
    push->messageCallback = callback;
    push->rtmpPushParm = rtmpPushParm;
    push->stopRequest = GFalse;
    push->releaseRequest = GFalse;
    pthread_mutex_init(&push->mutex, GNULL);
    *sender = push;
    return GTrue;
}
static GBool sequenceHeaderReleaseCallBack(GJRetainBuffer * buffer){
    free(buffer->data);
    free(buffer);
    return GTrue;
}
GBool GJRtmpPush_SendAVCSequenceHeader(GJRtmpPush* push,GUInt8* sps,GInt32 spsSize,GUInt8* pps,GInt32 ppsSize,GUInt64 dts){
    GJRTMP_Packet* pushPacket = (GJRTMP_Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJRTMP_Packet));
    RTMPPacket* sendPacket = &pushPacket->packet;
    RTMPPacket_Reset(sendPacket);
    pushPacket->retainBuffer = GNULL;
    GInt32 needSize = spsSize + ppsSize + RTMP_MAX_HEADER_SIZE + 16;
    GHandle data = (GHandle)malloc(needSize);
    pushPacket->packet.m_body = data + RTMP_MAX_HEADER_SIZE;
    pushPacket->packet.m_nBodySize = needSize - RTMP_MAX_HEADER_SIZE;
    sendPacket->m_packetType = RTMP_PACKET_TYPE_VIDEO;
    sendPacket->m_nChannel = 0x04;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType = RTMP_PACKET_SIZE_MEDIUM;
    sendPacket->m_nInfoField2 = push->rtmp->m_stream_id;
    sendPacket->m_nTimeStamp = (GUInt32)dts;
    
    retainBufferPack(&(pushPacket->retainBuffer), data, needSize, sequenceHeaderReleaseCallBack, GNULL);
    GUInt8* body = (GUInt8*)pushPacket->packet.m_body;
    GInt32 iIndex = 0;
    
    body[iIndex++] = 0x17;
    body[iIndex++] = 0x00;
    
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    
    ////AVCDecoderConfigurationRecord
    body[iIndex++] = 0x01;
    body[iIndex++] = sps[1];
    body[iIndex++] = sps[2];
    body[iIndex++] = sps[3];
    body[iIndex++] = 0xff;
    
    /*sps*/
    body[iIndex++]   = 0xe1;
    body[iIndex++] = spsSize>>8 & 0xff;
    body[iIndex++] = spsSize & 0xff;
    memcpy(&body[iIndex],sps,spsSize);
    iIndex +=  spsSize;
    
    /*pps*/
    body[iIndex++]   = 0x01;
    body[iIndex++] = ppsSize>>8 & 0xff;
    body[iIndex++] = ppsSize & 0xff;
    memcpy(&body[iIndex],pps,ppsSize);
    
    
    if (queuePush(push->sendBufferQueue, pushPacket, 0)) {
        push->videoStatus.enter.pts = pushPacket->packet.m_nTimeStamp;
        push->videoStatus.enter.count++;
        push->videoStatus.enter.byte += pushPacket->packet.m_nBodySize;
        return GTrue;
    }else{
        return GFalse;
    }
}
GBool GJRtmpPush_SendH264Data(GJRtmpPush* sender,R_GJH264Packet* packet){
    if (sender == GNULL) {
        return GFalse;
    }
    GBool isKey = GFalse;
    GUInt8 *pp = GNULL;
    GInt32 ppSize = 0;
    GInt32 ppPreSize = 0;//flv tag前置预留大小大小
    GUInt8 fristByte = 0x27;
    if (packet->ppSize > 0) {
        ppPreSize = 5;
        ppSize = packet->ppSize;
        pp = packet->ppOffset+packet->retain.data;
        if ((pp[0] & 0x1F) == 5 || (pp[0] & 0x1F) == 6) {
            isKey = GTrue;
            fristByte = 0x17;
            if (packet->seiSize != 0) {
                pp = packet->seiOffset + packet->retain.data;
                ppSize += packet->seiSize;
            }
        }
    }else{
        GJAssert(0, "没有pp");
        return GFalse;
    }
    
    GInt32 preSize = ppPreSize+RTMP_MAX_HEADER_SIZE;
    if (pp-packet->retain.data + packet->retain.frontSize < preSize) {//申请内存控制得当的话不会进入此条件、  先扩大，在查找。
        GJLOG(GJ_LOGDEBUG, "预留位置过小,扩大");
        retainBufferMoveDataToPoint(&packet->retain, RTMP_MAX_HEADER_SIZE+ppPreSize, GTrue);

        if (packet->ppSize > 0) {
            pp = packet->ppOffset+packet->retain.data;
        }
        if (packet->seiSize != 0) {
            pp = packet->seiOffset + packet->retain.data;
            ppSize += packet->seiSize;
        }
    }
    
    GJRTMP_Packet* pushPacket = (GJRTMP_Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJRTMP_Packet));
    memset(pushPacket, 0, sizeof(GJRTMP_Packet));
    GJRetainBuffer*retainBuffer = (GJRetainBuffer*)packet;
    pushPacket->retainBuffer = retainBuffer;
    RTMPPacket* sendPacket = &pushPacket->packet;

    GUChar * body=GNULL;
    GInt32 iIndex = 0;
   
   
//    使用pp做参考点，防止sei不发送的情况，导致pp移动，产生消耗
    sendPacket->m_body = (GChar*)pp - ppPreSize;
    sendPacket->m_nBodySize = ppSize+ppPreSize;
    body = (GUChar *)sendPacket->m_body;
    sendPacket->m_packetType = RTMP_PACKET_TYPE_VIDEO;
    sendPacket->m_nChannel = 0x04;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType = RTMP_PACKET_SIZE_LARGE;
    sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
    sendPacket->m_nTimeStamp = (uint32_t)packet->pts;
    if (packet->ppSize > 0) {
        body[iIndex++] = fristByte;
        body[iIndex++] = 0x01;// AVC NALU
        
        body[iIndex++] = 0x00;
        body[iIndex++] = 0x00;
        body[iIndex++] = 0x00;
    }

    retainBufferRetain(retainBuffer);
    if (queuePush(sender->sendBufferQueue, pushPacket, 0)) {
        sender->videoStatus.enter.pts = pushPacket->packet.m_nTimeStamp;
        sender->videoStatus.enter.count++;
        sender->videoStatus.enter.byte += pushPacket->packet.m_nBodySize;
        return GTrue;
    }else{
        GJLOG(GJ_LOGFORBID, "不可能出现的错误");
        retainBufferUnRetain(retainBuffer);
        GJBufferPoolSetData(defauleBufferPool(), (GHandle)pushPacket);
        return GFalse;
    }
}
GBool GJRtmpPush_SendAACSequenceHeader(GJRtmpPush* push,GInt32 aactype, GInt32 sampleRate, GInt32 channels,GUInt64 dts){
    if (push == GNULL) {
        return GFalse;
    }
    GUInt8 srIndex = 0;
    if (sampleRate == 44100) {
        srIndex = 4;
    }else if (sampleRate == 22050){
        srIndex = 7;
    }else if (sampleRate == 11025){
        srIndex = 10;
    }else{
        GJLOG(GJ_LOGFORBID, "sampleRate error");
        return GFalse;
    }
    
    GUInt8 config1 = (aactype << 3) | ((srIndex & 0xe) >> 1);
    GUInt8 config2 = ((srIndex & 0x1) << 7) | (channels << 3);
    
    GJRTMP_Packet* pushPacket = (GJRTMP_Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJRTMP_Packet));
    RTMPPacket* sendPacket = &pushPacket->packet;
    RTMPPacket_Reset(sendPacket);
    pushPacket->retainBuffer = GNULL;
    GInt32 needSize = 2 + 2 + RTMP_MAX_HEADER_SIZE;
    GHandle data = (GHandle)malloc(needSize);
    pushPacket->packet.m_body = data + RTMP_MAX_HEADER_SIZE;
    pushPacket->packet.m_nBodySize = needSize - RTMP_MAX_HEADER_SIZE;
    sendPacket->m_packetType = RTMP_PACKET_TYPE_AUDIO;
    sendPacket->m_nChannel = 0x04;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType = RTMP_PACKET_SIZE_MEDIUM;
    sendPacket->m_nInfoField2 = push->rtmp->m_stream_id;
    sendPacket->m_nTimeStamp = (GUInt32)dts;

    retainBufferPack(&(pushPacket->retainBuffer), data, needSize, sequenceHeaderReleaseCallBack, GNULL);
    GUInt8* body = (GUInt8*)pushPacket->packet.m_body;
    body[0] = 0xAF;
    body[1] = 0x00;
    
    body[2] = config1;
    body[3] = config2;
    if (queuePush(push->sendBufferQueue, pushPacket, 0)) {
        push->audioStatus.enter.pts = pushPacket->packet.m_nTimeStamp;
        push->audioStatus.enter.count++;
        push->audioStatus.enter.byte += pushPacket->packet.m_nBodySize;
        return GTrue;
    }else{
        return GFalse;
    }
}
GBool GJRtmpPush_SendAACData(GJRtmpPush* sender,R_GJAACPacket* buffer){
    if (sender == GNULL) {
        return GFalse;
    }
    GUChar * body;
    GInt32 preSize = 2;
    GJRTMP_Packet* pushPacket = (GJRTMP_Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJRTMP_Packet));

    GJRetainBuffer* retainBuffer = &buffer->retain;
    pushPacket->retainBuffer = retainBuffer;
    
    RTMPPacket* sendPacket = &pushPacket->packet;
    RTMPPacket_Reset(sendPacket);
    if (buffer->adtsOffset+buffer->retain.frontSize < preSize+RTMP_MAX_HEADER_SIZE) {//申请内存控制得当的话不会进入此条件、
        GJLOG(GJ_LOGWARNING, "产生内存移动");
        retainBufferMoveDataToPoint(&buffer->retain, RTMP_MAX_HEADER_SIZE+preSize, GTrue);
    }

    sendPacket->m_body = (GChar*)(buffer->aacOffset +buffer->retain.data - preSize);
    sendPacket->m_nBodySize = buffer->aacSize+preSize;

    body = (GUChar *)sendPacket->m_body;
    
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
        return GTrue;
    }else{
        GJLOG(GJ_LOGFORBID, "不可能出现的错误");
        retainBufferUnRetain(retainBuffer);
        GJBufferPoolSetData(defauleBufferPool(), (GHandle)pushPacket);
        return GFalse;
    }
}

GBool  GJRtmpPush_StartConnect(GJRtmpPush* sender,const GChar* sendUrl){
//    GChar* p = "GJRtmpPush_StartConnect__test";
//    GJ_Log(GJ_LOGINFO,p,p);
    GJLOG(GJ_LOGINFO,"GJRtmpPush_StartConnect:%p",sender);

    size_t length = strlen(sendUrl);
    memset(&sender->videoStatus, 0, sizeof(GJTrafficStatus));
    memset(&sender->audioStatus, 0, sizeof(GJTrafficStatus));
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(sender->pushUrl, sendUrl, length+1);
    if (sender->sendThread) {
        GJLOG(GJ_LOGWARNING,"上一个push没有释放，开始释放并等待");
        GJRtmpPush_Close(sender);
        pthread_join(sender->sendThread, GNULL);
        GJLOG(GJ_LOGWARNING,"等待push释放结束");
    }
    sender->stopRequest = GFalse;
    pthread_create(&sender->sendThread, GNULL, sendRunloop, sender);
    return GTrue;
}
GVoid GJRtmpPush_Delloc(GJRtmpPush* push){

    RTMP_Free(push->rtmp);
    GInt32 length = queueGetLength(push->sendBufferQueue);
    if (length>0) {
        GJRTMP_Packet** packet = (GJRTMP_Packet**)malloc(sizeof(GJRTMP_Packet*)*length);
        //queuepop已经关闭
        if (queueClean(push->sendBufferQueue, (GHandle*)packet, &length)) {
            for (GInt32 i = 0; i<length; i++) {
                retainBufferUnRetain(packet[i]->retainBuffer);
                GJBufferPoolSetData(defauleBufferPool(), (GHandle)packet[i]);
            }
            
        }
        free(packet);
    }
    queueFree(&push->sendBufferQueue);
    free(push);
    GJLOG(GJ_LOGDEBUG, "GJRtmpPush_Delloc:%p",push);

}
GVoid GJRtmpPush_CloseAndDealloc(GJRtmpPush** push){
    
    GJRtmpPush_Close(*push);
    GJRtmpPush_Release(*push);
    *push = GNULL;
}
GVoid GJRtmpPush_Release(GJRtmpPush* push){
    GJLOG(GJ_LOGINFO,"GJRtmpPush_Release::%p",push);
    
    GBool shouldDelloc = GFalse;
    push->messageCallback = GNULL;
    pthread_mutex_lock(&push->mutex);
    push->releaseRequest = GTrue;
    if (push->sendThread == GNULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&push->mutex);
    if (shouldDelloc) {
        GJRtmpPush_Delloc(push);
    }
}
GVoid GJRtmpPush_Close(GJRtmpPush* sender){
    if (sender->stopRequest) {
        GJLOG(GJ_LOGINFO,"GJRtmpPush_Close：%p  重复关闭",sender);
    }else{
        GJLOG(GJ_LOGINFO,"GJRtmpPush_Close:%p",sender);
        sender->stopRequest = GTrue;
        queueEnablePush(sender->sendBufferQueue, GFalse);
        queueBroadcastPop(sender->sendBufferQueue);

    }
}


GFloat32 GJRtmpPush_GetBufferRate(GJRtmpPush* sender){
    GLong length = queueGetLength(sender->sendBufferQueue);
    GFloat32 size = sender->sendBufferQueue->allocSize * 1.0;
//    GJPrintf("BufferRate length:%ld ,size:%f   rate:%f\n",length,size,length/size);
    return length / size;
};
GJTrafficStatus GJRtmpPush_GetVideoBufferCacheInfo(GJRtmpPush* push){
    if (push == GNULL) {
        return (GJTrafficStatus){0};
    }else{
        return push->videoStatus;
    }
}
GJTrafficStatus GJRtmpPush_GetAudioBufferCacheInfo(GJRtmpPush* push){
    if (push == GNULL) {
        return (GJTrafficStatus){0};
    }else{
        return push->audioStatus;
    }
}


