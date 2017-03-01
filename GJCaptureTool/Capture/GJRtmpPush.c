//
//  GJRtmpSender.c
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRtmpPush.h"
#include "GJDebug.h"
#include "sps_decode.h"
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
    push->audioPacket = (RTMPPacket*)malloc(sizeof(RTMPPacket));
    push->videoPacket = (RTMPPacket*)malloc(sizeof(RTMPPacket));
    
    
    *sender = push;
}
void GJRtmpPush_Release(GJRtmpPush** sender){
    GJRtmpPush* push = *sender;
    RTMP_Free(push->rtmp);
    free((void*)push->videoPacket);
    free((void*)push->audioPacket);

}

void GJRtmpPush_SendH264Data(GJRtmpPush* sender,GJRetainBuffer* buffer,double dts){
    uint8_t *sps = NULL,*pps = NULL,*pp = NULL;
    bool isKey = 0;
    int spsSize = 0,ppsSize = 0,ppSize = 0;
    find_pp_sps_pps(&isKey, buffer->data, buffer->size, &pp, &sps, &spsSize, &pps, &ppsSize, NULL, NULL);
    ppsSize = (int)((uint8_t*)buffer->data + buffer->size - pp);//ppsSize最好通过计算获得，直接查找的话查找数据量比较大
    
    RTMPPacket* sendPacket = (RTMPPacket*)sender->videoPacket;
    unsigned char * body=NULL;
    int iIndex = 0;
    int iRet = 0;
    int preSize = 0;//前面额外需要的空间；
    
    if (sps && pps) {
        int spsStartSize = 4,ppsStartSize = 4;//sps分隔符大小
        int spsOffset =  (int)(sps - (uint8_t*)buffer->data - spsStartSize);//sps起始偏移量，正常为0
        preSize = 16+RTMP_MAX_HEADER_SIZE - spsOffset;

        iIndex = 0;
        body = NULL;
        RTMPPacket_Reset(sendPacket);
        if (buffer->frontSize < preSize) {//申请内存控制得当的话不会进入此条件、
            retainBufferSetFrontSize(buffer, preSize);
        }
        sendPacket->m_body = (char*)sps-spsStartSize-16;
        sendPacket->m_nBytesRead = 0;
        
      
        body = (unsigned char *)sendPacket->m_body;
        
        body[iIndex++] = 0x17;
        body[iIndex++] = 0x00;
        
        body[iIndex++] = 0x00;
        body[iIndex++] = 0x00;
        body[iIndex++] = 0x00;
        
        body[iIndex++] = 0x01;
        body[iIndex++] = sps[1];
        body[iIndex++] = sps[2];
        body[iIndex++] = sps[3];
        body[iIndex++] = 0xff;
        
        /*sps*/
        body[iIndex++]   = 0xe1;
        body[iIndex++] = ((spsSize+spsStartSize) >> 8) & 0xff;
        body[iIndex++] = (spsSize+spsStartSize) & 0xff;
        memcpy(&body[iIndex],sps-spsStartSize,spsSize+spsStartSize);
        iIndex +=  spsSize+spsStartSize;
        
        /*pps*/
        body[iIndex++]   = 0x01;
        body[iIndex++] = ((ppsSize+ppsStartSize) >> 8) & 0xff;
        body[iIndex++] = (ppsSize+ppsStartSize) & 0xff;
        memcpy(&body[iIndex], pps-ppsStartSize, ppsSize+ppsStartSize);
        iIndex +=  ppsSize+ppsStartSize;
        
        sendPacket->m_packetType = RTMP_PACKET_TYPE_VIDEO;
        sendPacket->m_nBodySize = iIndex;
        sendPacket->m_nChannel = 0x04;
        sendPacket->m_nTimeStamp = 0;
        sendPacket->m_hasAbsTimestamp = 0;
        sendPacket->m_headerType = RTMP_PACKET_SIZE_MEDIUM;
        
        sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
        iRet = RTMP_SendPacket(sender->rtmp,sendPacket,0);
        if (!iRet) {
            GJPrintf("error sendspspps");
            return;
        }
    }
    
    if (pp) {
        body = NULL;
        int ppStartSize = 4;
        int ppOffset =  (int)(pp - (uint8_t*)buffer->data) - ppStartSize;//sps起始偏移量，正常为0
        preSize = 9+RTMP_MAX_HEADER_SIZE - ppOffset;//对于i帧前面存在sps，可能为负数
        int i = 0,size = ppsSize + ppStartSize;

        
        iIndex = 0;
        body = NULL;
        RTMPPacket_Reset(sendPacket);
        if (buffer->frontSize < preSize) {//申请内存控制得当的话不会进入此条件、
            retainBufferSetFrontSize(buffer, preSize);
        }
        
        sendPacket->m_body = (char*)pp - ppStartSize - 9;
        sendPacket->m_nBytesRead = 0;
        
        body = (unsigned char *)sendPacket->m_body;

        if(isKey)
        {
            body[i++] = 0x17;// 1:Iframe  7:AVC
        }
        else
        {
            body[i++] = 0x27;// 2:Pframe  7:AVC
        }
        body[i++] = 0x01;// AVC NALU
        body[i++] = 0x00;
        body[i++] = 0x00;
        body[i++] = 0x00;        
        // NALU size
        body[i++] = size>>24 &0xff;
        body[i++] = size>>16 &0xff;
        body[i++] = size>>8 &0xff;
        body[i++] = size&0xff;
        // NALU data
        memcpy(&body[i],pp-ppStartSize,ppSize+ppStartSize);
        sendPacket->m_nBodySize = ppSize + ppStartSize;
        sendPacket->m_hasAbsTimestamp = 0;
        sendPacket->m_packetType = RTMP_PACKET_TYPE_VIDEO;
        sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
        sendPacket->m_nChannel = 0x04;
        sendPacket->m_headerType = RTMP_PACKET_SIZE_LARGE;
        sendPacket->m_nTimeStamp = dts;
        iRet = RTMP_SendPacket(sender->rtmp,sendPacket,0);
        if (!iRet) {
            GJPrintf("error send KEY FRAME");
            return;
        }
    }
}

void GJRtmpPush_SendAACData(GJRtmpPush* sender,GJRetainBuffer* buffer,double dts){

    unsigned char * body;
    int preSize = 2+RTMP_MAX_HEADER_SIZE;
    RTMPPacket* sendPacket = (RTMPPacket*)sender->audioPacket;
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
    int iRet = RTMP_SendPacket(sender->rtmp,sendPacket,0);
    if (!iRet) {
        GJPrintf("error send audio FRAME");
        return;
    }
}


bool  GJRtmpPush_StartConnect(GJRtmpPush* sender,const char* sendUrl){
    int ret = RTMP_SetupURL(sender->rtmp, (char*)sendUrl);
    if (!ret) {
        return false;
    }
    RTMP_EnableWrite(sender->rtmp);
    
    sender->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;

    ret = RTMP_Connect(sender->rtmp, NULL);
    if (!ret) {
        return false;
    }
    ret = RTMP_ConnectStream(sender->rtmp, 0);
    if (!ret) {
        return false;
    }
    return true;
}
void GJRtmpPush_Close(GJRtmpPush* sender){
    RTMP_Close(sender->rtmp);
}

