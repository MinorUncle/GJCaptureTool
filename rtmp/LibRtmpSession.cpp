//
//  LibRtmpSession.cpp
//  AudioEditX
//
//  Created by Alex.Shi on 16/3/8.
//  Copyright © 2016年 com.Alex. All rights reserved.
//

#include "LibRtmpSession.hpp"

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdarg.h>
#include <memory.h>
#include "sps_decode.h"
#include "rtmp.h"
//#include "android/log.h"
#include <stdlib.h>
#include <string.h>

#define DATA_ITEMS_MAX_COUNT 100
#define RTMP_DATA_RESERVE_SIZE 400

#define RTMP_CONNECTION_TIMEOUT 1500
#define RTMP_RECEIVE_TIMEOUT    3

#define LOG_TAG "RTMP_SESSION"

#define LOGI(...) //__android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__);
#define LOGE(...) //__android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__);

#ifndef NULL
#define NULL 0
#endif

typedef struct _DataItem
{
    char* data;
    int size;
    int headlen;
}DataItem;

typedef struct _RTMPMetadata
{
    // video, must be h264 type
    unsigned int    nWidth;
    unsigned int    nHeight;
    unsigned int    nFrameRate;
    unsigned int    nSpsLen;
    unsigned char   *Sps;
    unsigned int    nPpsLen;
    unsigned char   *Pps;
} RTMPMetadata,*LPRTMPMetadata;

LibRtmpSession::LibRtmpSession(){
    
}

LibRtmpSession::LibRtmpSession(char* szRtmpUrl):_pRtmp(NULL)
,_iConnectFlag(0)
,_iMetaDataFlag(0)
,_pAdtsItems(NULL)
,_uiStartTimestamp(0)
,_uiAudioDTS(0)
,_uiVideoLastAudioDTS(0)
,_uiAudioDTSNoChangeCnt(0)
,_iASCSentFlag(0)
,_iAacType(0)
,_iSampleRate(0)
,_iChannels(0)
,_iWidth(0)
,_iHeight(0)
,_iFps(0)
{
    strcpy(_szRtmpUrl, szRtmpUrl);
    _pAdtsItems = (DataItem*)malloc(sizeof(DataItem)*DATA_ITEMS_MAX_COUNT);
    memset((void*)_pAdtsItems, 0, sizeof(DataItem)*DATA_ITEMS_MAX_COUNT);
    
    _pNaluItems = (DataItem*)malloc(sizeof(DataItem)*DATA_ITEMS_MAX_COUNT);
    memset((void*)_pNaluItems, 0, sizeof(DataItem)*DATA_ITEMS_MAX_COUNT);
    
    _pMetaData = (RTMPMetadata*)malloc(sizeof(RTMPMetadata));
    memset((void*)_pMetaData, 0, sizeof(RTMPMetadata));
}

LibRtmpSession::~LibRtmpSession(){
    if(_iConnectFlag != 0) {
        DisConnect();
        if (_pRtmp) {
            free(_pRtmp);
        }
        if (_pAdtsItems) {
            free(_pAdtsItems);
        }
        if (_pNaluItems) {
            free(_pNaluItems);
        }
        if (_pMetaData) {
            free(_pMetaData);
        }
    }
}

int LibRtmpSession::Connect(int iFlag){
    int iRet = 0;
    _iConnectFlag = 0;
    
    //if (0 == pthread_mutex_trylock(&_mConnstatMutex)) {
    if (_pRtmp) {
        free(_pRtmp);
        _pRtmp = NULL;
    }
    if(!_pRtmp)
    {
        _pRtmp = RTMP_Alloc();
        if(_pRtmp)
        {
            RTMP_Init(_pRtmp);
        }else
        {
            free(_pRtmp);
            _pRtmp = NULL;
            iRet = -1;
            //pthread_mutex_unlock(&_mConnstatMutex);
            return iRet;
        }
    }
    
    //LOGI("RTMP_SetupURL:%s", _szRtmpUrl);
    if (RTMP_SetupURL(_pRtmp, (char*)_szRtmpUrl) == FALSE)
    {
        iRet = -2;
        free(_pRtmp);
        _pRtmp = NULL;
        //pthread_mutex_unlock(&_mConnstatMutex);
        return iRet;
    }
    //LOGI("RTMP_EnableWrite...");
    if(iFlag !=0)
    {
        RTMP_EnableWrite(_pRtmp);
    }
    
    _pRtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    
    //LOGI("RTMP_Connect...");
    if (RTMP_ConnectEx(_pRtmp, NULL, RTMP_CONNECTION_TIMEOUT) == FALSE)
    {
        RTMP_Close(_pRtmp);
        RTMP_Free(_pRtmp);
        _pRtmp = NULL;
        iRet = -3;
        LOGI("RTMP_Connect...error");
        return iRet;
    }
    //LOGI("RTMP_Connect...ok");
    
    //LOGI("RTMP_ConnectStream...");
    if (RTMP_ConnectStream(_pRtmp,10) == FALSE)
    {
        RTMP_Close(_pRtmp);
        RTMP_Free(_pRtmp);
        _pRtmp = NULL;
        iRet = -4;
        LOGI("RTMP_ConnectStream...error");
        return iRet;
    }
    //LOGI("RTMP_ConnectStream...ok");
    //_pRtmp->m_read.flags |= RTMP_READ_RESUME;
    //printf("connect: readflag=0x%08x, protocol=0x%08x\r\n", _pRtmp->m_read.flags, _pRtmp->Link.protocol);
    _iConnectFlag = 1;
    _iMetaDataFlag = 0;
    
    return iRet;
}

void LibRtmpSession::DisConnect(){
    if(_pRtmp)
    {
        LOGI("DisConnect: RTMP_Close...");
        RTMP_Close(_pRtmp);
        LOGI("DisConnect: RTMP_Close...END");
        LOGI("RTMP_Free: RTMP_Free...");
        RTMP_Free(_pRtmp);
        LOGI("RTMP_Free: RTMP_Free...END");
        
        _pRtmp = NULL;
        
        _iConnectFlag  = 0;
        _iMetaDataFlag = 0;
    }
}

int LibRtmpSession::IsConnected(){
    
    if(_pRtmp == NULL){
        return 0;
    }
    //pthread_mutex_lock(&_mConnstatMutex);
    int iRet = RTMP_IsConnected(_pRtmp);
    //pthread_mutex_unlock(&_mConnstatMutex);
    return iRet;
}

int LibRtmpSession::getSampleRateByType(int iType)
{
    int iSampleRate = 44100;
    switch (iType) {
        case 0:
            iSampleRate = 96000;
            break;
        case 1:
            iSampleRate = 88200;
            break;
        case 2:
            iSampleRate = 64000;
            break;
        case 3:
            iSampleRate = 48000;
            break;
        case 4:
            iSampleRate = 44100;
            break;
        case 5:
            iSampleRate = 32000;
            break;
        case 6:
            iSampleRate = 24000;
            break;
        case 7:
            iSampleRate = 22050;
            break;
        case 8:
            iSampleRate = 16000;
            break;
        case 9:
            iSampleRate = 12000;
            break;
        case 10:
            iSampleRate = 11025;
            break;
        case 11:
            iSampleRate = 8000;
            break;
        case 12:
            iSampleRate = 7350;
            break;
    }
    return iSampleRate;
}

int LibRtmpSession::getSampleRateType(int iSampleRate){
    int iRetType = 4;
    
    switch (iSampleRate) {
        case 96000:
            iRetType = 0;
            break;
        case 88200:
            iRetType = 1;
            break;
        case 64000:
            iRetType = 2;
            break;
        case 48000:
            iRetType = 3;
            break;
        case 44100:
            iRetType = 4;
            break;
        case 32000:
            iRetType = 5;
            break;
        case 24000:
            iRetType = 6;
            break;
        case 22050:
            iRetType = 7;
            break;
        case 16000:
            iRetType = 8;
            break;
        case 12000:
            iRetType = 9;
            break;
        case 11025:
            iRetType = 10;
            break;
        case 8000:
            iRetType = 11;
            break;
        case 7350:
            iRetType = 12;
            break;
    }
    return iRetType;
}

void LibRtmpSession::GetASCInfo(unsigned short usAscFlag)
{
    //ASC FLAG: xxxx xaaa aooo o111
    _iAacType = (usAscFlag & 0xf800) >> 11;
    _iSampleRate= (usAscFlag & 0x0780)>> 7;
    _iChannels = (usAscFlag & 0x78) >> 3;
}

void LibRtmpSession::GetSpsInfo(unsigned char* pSpsData, int iLength)
{
    int* Width = &_iWidth;
    int* Height = &_iHeight;
    int* Fps = &_iFps;
    h264_decode_sps(pSpsData, iLength, &Width, &Height, &Fps);
}

void LibRtmpSession::MakeAudioSpecificConfig(char* pConfig, int aactype, int sampleRate, int channels){
    unsigned short result = 0;
    
    //ASC FLAG: xxxx xaaa aooo o111
    result += aactype;
    result = result << 4;
    result += sampleRate;
    result = result << 4;
    result += channels;
    result = result <<3;
    int size = sizeof(result);
    
    if ((aactype == 5) || (aactype == 29)) {
        result |= 0x01;
    }
    memcpy(pConfig,&result,size);
    
    unsigned char low,high;
    low = pConfig[0];
    high = pConfig[1];
    pConfig[0] = high;
    pConfig[1] = low;
    
}

int LibRtmpSession::SendAudioSpecificConfig(unsigned short usASCFlag)
{
    int iSpeclen = 2;
    unsigned char szAudioSpecData[2];
    
    usASCFlag = (usASCFlag>>8) | (usASCFlag<<8);
    memcpy(szAudioSpecData, &usASCFlag, sizeof(usASCFlag));
    
    unsigned char* body;
    int len;
    len = iSpeclen+2;
    
    int rtmpLength = len;
    RTMPPacket rtmp_pack;
    RTMPPacket_Reset(&rtmp_pack);
    RTMPPacket_Alloc(&rtmp_pack,rtmpLength);
    
    body = (unsigned char *)rtmp_pack.m_body;
    body[0] = 0xAF;
    body[1] = 0x00;
    
    memcpy(&body[2],szAudioSpecData, sizeof(szAudioSpecData));
    
    rtmp_pack.m_packetType = RTMP_PACKET_TYPE_AUDIO;
    rtmp_pack.m_nBodySize = len;
    rtmp_pack.m_nChannel = 0x04;
    rtmp_pack.m_nTimeStamp = 0;
    rtmp_pack.m_hasAbsTimestamp = 0;
    rtmp_pack.m_headerType = RTMP_PACKET_SIZE_LARGE;
    
    if(_pRtmp)
        rtmp_pack.m_nInfoField2 = _pRtmp->m_stream_id;
    
    int iRet = RtmpPacketSend(&rtmp_pack);
    LOGI("SendAudioSpecificConfig: %02x %02x %02x %02x, return %d",  body[0],  body[1],  body[2],  body[3], iRet);
    _iASCSentFlag = 1;
    return iRet;
}

int LibRtmpSession::SendAudioSpecificConfig(int aactype, int sampleRate, int channels)
{
    char* szAudioSpecData;
    int iSpeclen = 0;
    
    if ((aactype == 5) || (aactype == 29)) {
        iSpeclen = 4;
    }else{
        iSpeclen = 2;
    }
    szAudioSpecData = (char*)malloc(iSpeclen);
    memset(szAudioSpecData, 0, iSpeclen);
    MakeAudioSpecificConfig(szAudioSpecData, aactype, getSampleRateType(sampleRate), channels);
    
    unsigned char* body;
    int len;
    len = iSpeclen+2;
    
    int rtmpLength = len;
    RTMPPacket rtmp_pack;
    RTMPPacket_Reset(&rtmp_pack);
    RTMPPacket_Alloc(&rtmp_pack,rtmpLength);
    
    body = (unsigned char *)rtmp_pack.m_body;
    body[0] = 0xAF;
    body[1] = 0x00;
    
    memcpy(&body[2],szAudioSpecData,iSpeclen);
    free(szAudioSpecData);
    
    rtmp_pack.m_packetType = RTMP_PACKET_TYPE_AUDIO;
    rtmp_pack.m_nBodySize = len;
    rtmp_pack.m_nChannel = 0x04;
    rtmp_pack.m_nTimeStamp = 0;
    rtmp_pack.m_hasAbsTimestamp = 0;
    rtmp_pack.m_headerType = RTMP_PACKET_SIZE_LARGE;
    
    if(_pRtmp)
        rtmp_pack.m_nInfoField2 = _pRtmp->m_stream_id;
    
    int iRet = RtmpPacketSend(&rtmp_pack);
    LOGI("SendAudioSpecificConfig: %02x %02x %02x %02x, return %d",  body[0],  body[1],  body[2],  body[3], iRet);
    _iASCSentFlag = 1;
    return iRet;
}

int LibRtmpSession::RtmpPacketSend(RTMPPacket* packet)
{
    int iRet = 0;
    int iBodySize = packet->m_nBodySize;
    
    iRet = RTMP_SendPacket(_pRtmp,packet,0);
    
    return (iRet!=0)? iBodySize:0;
}

int LibRtmpSession::SendPacket(unsigned int nPacketType,unsigned char *data,unsigned int size,unsigned int nTimestamp)
{
    int rtmpLength = size;
    RTMPPacket rtmp_pack;
    RTMPPacket_Reset(&rtmp_pack);
    RTMPPacket_Alloc(&rtmp_pack,rtmpLength);
    
    rtmp_pack.m_nBodySize = size;
    memcpy(rtmp_pack.m_body,data,size);
    rtmp_pack.m_hasAbsTimestamp = 0;
    rtmp_pack.m_packetType = nPacketType;
    
    if(_pRtmp)
        rtmp_pack.m_nInfoField2 = _pRtmp->m_stream_id;
    
    rtmp_pack.m_nChannel = 0x04;
    
    rtmp_pack.m_headerType = RTMP_PACKET_SIZE_LARGE;
    if (RTMP_PACKET_TYPE_AUDIO == nPacketType && size !=4)
    {
        rtmp_pack.m_headerType = RTMP_PACKET_SIZE_MEDIUM;
    }
    rtmp_pack.m_nTimeStamp = nTimestamp;
    
    int nRet = RtmpPacketSend(&rtmp_pack);
    
    RTMPPacket_Free(&rtmp_pack);
    return nRet;
}

int LibRtmpSession::SendVideoSpsPps(unsigned char *pps,int pps_len,unsigned char * sps,int sps_len ,int pts,int dts)
{
    unsigned char * body=NULL;
    int iIndex = 0;
    
    int rtmpLength = 16+pps_len+sps_len;
    RTMPPacket rtmp_pack;
    RTMPPacket_Reset(&rtmp_pack);
    RTMPPacket_Alloc(&rtmp_pack,rtmpLength);
    
    body = (unsigned char *)rtmp_pack.m_body;
    
    body[iIndex++] = 0x17;
    body[iIndex++] = 0x00;
    
//    int val = pts-dts;
//    body[iIndex++] = (val >> 16) & 0xff;// Decoder delay
//    body[iIndex++] = (val >> 8) & 0xff;
//    body[iIndex++] = (val >> 0) & 0xff;
    
    body[iIndex++] = 0x00;// Decoder delay
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;

    
    body[iIndex++] = 0x01;
    body[iIndex++] = sps[1];
    body[iIndex++] = sps[2];
    body[iIndex++] = sps[3];
    body[iIndex++] = 0xff;
    
    /*sps*/
    body[iIndex++]   = 0xe1;
    body[iIndex++] = (sps_len >> 8) & 0xff;
    body[iIndex++] = sps_len & 0xff;
    memcpy(&body[iIndex],sps,sps_len);
    iIndex +=  sps_len;
    
    /*pps*/
    body[iIndex++]   = 0x01;
    body[iIndex++] = (pps_len >> 8) & 0xff;
    body[iIndex++] = (pps_len) & 0xff;
    memcpy(&body[iIndex], pps, pps_len);
    iIndex +=  pps_len;
    
    rtmp_pack.m_packetType = RTMP_PACKET_TYPE_VIDEO;
    rtmp_pack.m_nBodySize = iIndex;
    rtmp_pack.m_nChannel = 0x04;
    rtmp_pack.m_nTimeStamp = dts;
    rtmp_pack.m_hasAbsTimestamp = 0;
    rtmp_pack.m_headerType = RTMP_PACKET_SIZE_MEDIUM;
    
    if(_pRtmp)
        rtmp_pack.m_nInfoField2 = _pRtmp->m_stream_id;
    
    int iRet = RtmpPacketSend(&rtmp_pack);
    if(iRet > 0)
    {
        if(_pMetaData->Pps != pps)
        {
            _pMetaData->Pps = (unsigned char*)malloc(pps_len);
            memcpy(_pMetaData->Pps, pps, pps_len);
        }
        if(_pMetaData->Sps != sps)
        {
            _pMetaData->Sps = (unsigned char*)malloc(sps_len);
            memcpy(_pMetaData->Sps, sps, sps_len);
        }
        _iMetaDataFlag = 1;
    }
    RTMPPacket_Free(&rtmp_pack);
    return iRet;
}

int LibRtmpSession::SendH264Packet(unsigned char *data,unsigned int size,int bIsKeyFrame,unsigned int dts,int pts)
{
    if(data == NULL && size<11)
    {
        return FALSE;
    }
    
    unsigned char *body = (unsigned char*)malloc(size+9);
    memset(body,0,size+9);
    
    int i = 0;
    if(bIsKeyFrame)
    {
        body[i++] = 0x17;// 1:Iframe  7:AVC
        body[i++] = 0x01;// AVC NALU
        
//        body[i++] = (val >> 16) & 0xff;// Decoder delay
//        body[i++] = (val >> 8) & 0xff;
//        body[i++] = (val >> 0) & 0xff;
        body[i++] = 0x00;
        body[i++] = 0x00;
        body[i++] = 0x00;
        
        body[i++] = (size >> 24) & 0xFF;
        body[i++] = (size >> 16) & 0xFF;
        body[i++] = (size >> 8) & 0xFF;
        body[i++] = size & 0xFF;
        memcpy(&body[i],data,size);
    }
    else
    {
        body[i++] = 0x27;// 2:Pframe  7:AVC
        body[i++] = 0x01;// AVC NALU
        body[i++] = 0x00;
        body[i++] = 0x00;
        body[i++] = 0x00;
        
        body[i++] = (size >> 24) & 0xFF;
        body[i++] = (size >> 16) & 0xFF;
        body[i++] = (size >> 8) & 0xFF;
        body[i++] = size & 0xFF;
        memcpy(&body[i],data,size);
    }
    
    int bRet = SendPacket(RTMP_PACKET_TYPE_VIDEO,body,i+size,dts);
    
    free(body);
    
    return bRet;
}

int LibRtmpSession::SendAACData(unsigned char* buf, int size, unsigned int timeStamp)
{
    if(_pRtmp == NULL)
        return -1;
    
    if (size <= 0)
    {
        return -2;
    }
    
    unsigned char * body;
    
    int rtmpLength = size+2;
    RTMPPacket rtmp_pack;
    RTMPPacket_Reset(&rtmp_pack);
    RTMPPacket_Alloc(&rtmp_pack,rtmpLength);
    
    body = (unsigned char *)rtmp_pack.m_body;
    
    /*AF 01 + AAC RAW data*/
    body[0] = 0xAF;
    body[1] = 0x01;
    memcpy(&body[2],buf,size);
    
    rtmp_pack.m_packetType = RTMP_PACKET_TYPE_AUDIO;
    rtmp_pack.m_nBodySize = size+2;
    rtmp_pack.m_nChannel = 0x04;
    rtmp_pack.m_nTimeStamp = timeStamp;
    rtmp_pack.m_hasAbsTimestamp = 0;
    rtmp_pack.m_headerType = RTMP_PACKET_SIZE_LARGE;
    
    if(_pRtmp)
        rtmp_pack.m_nInfoField2 = _pRtmp->m_stream_id;
    
    return RtmpPacketSend(&rtmp_pack);
}

int LibRtmpSession::SendAudioRawData(unsigned char* pBuff, int len, unsigned int ts){
    int rtmpLength = len;
    RTMPPacket* pRtmp_pack = (RTMPPacket*)malloc(sizeof(RTMPPacket) + RTMP_MAX_HEADER_SIZE+ rtmpLength+RTMP_DATA_RESERVE_SIZE);
    memset(pRtmp_pack, 0, sizeof(RTMPPacket) + RTMP_MAX_HEADER_SIZE+ rtmpLength+RTMP_DATA_RESERVE_SIZE);
    
    pRtmp_pack->m_body = ((char*)pRtmp_pack) + sizeof(RTMPPacket) + RTMP_MAX_HEADER_SIZE + RTMP_DATA_RESERVE_SIZE/2;
    
    /*AAC RAW data*/
    memcpy(pRtmp_pack->m_body,pBuff,rtmpLength);
    
    pRtmp_pack->m_packetType = RTMP_PACKET_TYPE_AUDIO;
    pRtmp_pack->m_nBodySize = rtmpLength;
    pRtmp_pack->m_nChannel = 0x04;
    pRtmp_pack->m_nTimeStamp = ts;
    pRtmp_pack->m_hasAbsTimestamp = 0;
    pRtmp_pack->m_headerType = RTMP_PACKET_SIZE_LARGE;
    
    if(_pRtmp)
        pRtmp_pack->m_nInfoField2 = _pRtmp->m_stream_id;
    
    int iRet = RtmpPacketSend(pRtmp_pack);
    
    free(pRtmp_pack);
    return iRet;
}

int LibRtmpSession::SendAudioData(unsigned char* pBuff, int len){
    int cnt = 0;
    int i;
    DataItem* pAdtsItems = (DataItem*)_pAdtsItems;
    //LOGI("SendAudioData: aac length=%d", len);
    
    for(i=0; i<len; i++)
    {
        unsigned char Data1 = pBuff[i];
        unsigned char Data2 = pBuff[i+1];
        if((Data1==0xFF) && (Data2==0xF1))
        {
            pAdtsItems[cnt].data = (char*)(pBuff+i);
            pAdtsItems[cnt].headlen = 7;
            i++;
            cnt++;
            if(cnt >= DATA_ITEMS_MAX_COUNT)
            {
                break;
            }
        }
    }
    
    for(i=0; i<cnt;i++)
    {
        if(i < cnt-1)
        {
            pAdtsItems[i].size = pAdtsItems[i+1].data - pAdtsItems[i].data;
            
        }
        else
        {
            pAdtsItems[i].size =(char*)(pBuff+len) - pAdtsItems[i].data;
        }
    }
    
    //LOGI("SendAudioData: cnt=%d", cnt);
    int iRet = 0;
    for(i=0; i<cnt; i++)
    {
        if(pAdtsItems[i].size > 0)
        {
            if (_uiStartTimestamp == 0) {
                _uiStartTimestamp = RTMP_GetTime();
            }else{
                _uiAudioDTS = RTMP_GetTime()-_uiStartTimestamp;
            }
            
            iRet = SendAACData((unsigned char*)(pAdtsItems[i].data+7),pAdtsItems[i].size-7, _uiAudioDTS);
            //LOGI("SendAudioData: SendAACData size=%u, DTS=%u return %d", pAdtsItems[i].size-7, _uiAudioDTS, iRet);
        }
    }
    return iRet;
}

int LibRtmpSession::SeparateNalus(unsigned char* pBuff, int len)
{
    int cnt = 0;
    int i = 0;
    
    for(i=0; i< len; i++)
    {
        if(pBuff[i] == 0)
        {
            //00 00 00 01
            if((pBuff[i+1]==0) && (pBuff[i+2] == 0) && (pBuff[i+3] == 1))
            {
                _pNaluItems[cnt].data = (char*)(pBuff+i+4);
                _pNaluItems[cnt].headlen = 4;
                i += 3;
                cnt++;
            }
            //00 00 01
            else if ((pBuff[i+1]==0) && (pBuff[i+2] == 1))
            {
                _pNaluItems[cnt].data = (char*)(pBuff+i+3);
                _pNaluItems[cnt].headlen = 3;
                i += 2;
                cnt++;
            }
            if(cnt >= DATA_ITEMS_MAX_COUNT)
            {
                break;
            }
        }
    }
    
    for(i=0; i<cnt;i++)
    {
        if(i < cnt-1)
        {
            _pNaluItems[i].size = _pNaluItems[i+1].data - _pNaluItems[i].data - _pNaluItems[i+1].headlen;
        }
        else
        {
            _pNaluItems[i].size =(char*)(pBuff+len) - _pNaluItems[i].data;
        }
    }
    return cnt;
}

int LibRtmpSession::SendVideoRawData(unsigned char* buf, int videodatalen, unsigned int ts){
    int rtmpLength = videodatalen;
    
    RTMPPacket* pRtmp_pack = (RTMPPacket*)malloc(sizeof(RTMPPacket) + RTMP_MAX_HEADER_SIZE+ rtmpLength+RTMP_DATA_RESERVE_SIZE);
    memset(pRtmp_pack, 0, sizeof(RTMPPacket) + RTMP_MAX_HEADER_SIZE+ rtmpLength+RTMP_DATA_RESERVE_SIZE);
    
    pRtmp_pack->m_nBodySize = videodatalen;
    pRtmp_pack->m_hasAbsTimestamp = 0;
    pRtmp_pack->m_packetType = RTMP_PACKET_TYPE_VIDEO;
    
    if(_pRtmp)
        pRtmp_pack->m_nInfoField2 = _pRtmp->m_stream_id;
    
    pRtmp_pack->m_nChannel = 0x04;
    
    pRtmp_pack->m_headerType = RTMP_PACKET_SIZE_LARGE;
    pRtmp_pack->m_nTimeStamp = ts;
    pRtmp_pack->m_body = ((char*)pRtmp_pack) + sizeof(RTMPPacket) + RTMP_MAX_HEADER_SIZE+RTMP_DATA_RESERVE_SIZE/2;
    memcpy(pRtmp_pack->m_body,buf,videodatalen);
    
    int iRet = RtmpPacketSend(pRtmp_pack);
    
    free(pRtmp_pack);
    
    return iRet;
}

int LibRtmpSession::GetASCSentFlag(){
    /*
     _iSendASCCount++;
     if(_iSendASCCount > 300){
     _iSendASCCount = 0;
     _iASCSentFlag = 0;
     }
     */
    return _iASCSentFlag;
}
int LibRtmpSession::SendVideoData(unsigned char* buf, int videodatalen){
    int itemscnt = SeparateNalus(buf,videodatalen);
    int iRet = 0;
    
    //LOGI("SendVideoData..Sps=0x%08x, Pps=0x%08x", _pMetaData->Sps, _pMetaData->Pps);
    
    if((!_pMetaData->Sps) || (!_pMetaData->Pps))
    {
        if(itemscnt > 0)
        {
            int i=0;
            for(i=0; i<itemscnt;i++)
            {
                //LOGI("SendVideoData: i=%d, Nalu.data[4]=0x%02x, sps=0x%08x",  i, _pNaluItems[i].data[4], _pMetaData->Sps);
                bool bSpsFlag = ((_pNaluItems[i].data[0]&0x1f) == 7);
                
                if(bSpsFlag && (!_pMetaData->Sps))
                {
                    _pMetaData->nSpsLen = _pNaluItems[i].size;
                    _pMetaData->Sps = (unsigned char*)malloc(_pMetaData->nSpsLen);
                    memcpy(_pMetaData->Sps, _pNaluItems[i].data, _pMetaData->nSpsLen);
                    int* Width = &_iWidth;
                    int* Height = &_iHeight;
                    int* Fps = &_iFps;
                    h264_decode_sps(_pMetaData->Sps,_pMetaData->nSpsLen, &Width, &Height, &Fps);
                    
                    _pMetaData->nWidth = _iWidth;
                    _pMetaData->nHeight = _iHeight;
                    
                    if(_iFps)
                        _pMetaData->nFrameRate = _iFps;
                    else
                        _pMetaData->nFrameRate = 20;
                }
                bool bPpsFlag = ((_pNaluItems[i].data[0]&0x1f) == 8);
                
                if(bPpsFlag && (!_pMetaData->Pps))
                {
                    _pMetaData->nPpsLen = _pNaluItems[i].size;
                    _pMetaData->Pps = (unsigned char*)malloc(_pMetaData->nPpsLen);
                    memcpy(_pMetaData->Pps, _pNaluItems[i].data, _pNaluItems[i].size);
                }
            }
        }
        if((_pMetaData->Sps) && (_pMetaData->Pps))
        {
//            SendVideoSpsPps(_pMetaData->Pps,_pMetaData->nPpsLen,_pMetaData->Sps,_pMetaData->nSpsLen);
        }
    }
    //LOGI("SendVideoData..._iMetaDataFlag=%d, itemscnt=%d", _iMetaDataFlag, itemscnt);
    if(!_iMetaDataFlag)
    {
        return -1;
    }
    
    if(itemscnt > 0)
    {
        int i=0;
        int isKey = 0;
        
        int iSendSize = 0;
        int iValidNaluCount = 0;
        unsigned char* pSendBuffer = (unsigned char*)malloc(videodatalen);
        memset(pSendBuffer, 0, videodatalen);
        
        for(i=0; i<itemscnt; i++)
        {
            if(_pNaluItems[i].size == 0)
            {
                continue;
            }
            
            unsigned char ucType = _pNaluItems[i].data[0];
            //LOGI("NALU type=0x%02x", ucType);
            if((ucType&0x1f) == 8)//pps
            {
                continue;
            }
            if((ucType&0x1f) == 7)//sps
            {
                continue;
            }
            if(isKey == 0){
                isKey  = ((ucType&0x1f) == 0x05) ? 1 : 0;
            }
            int iNaluSize = _pNaluItems[i].size;
            memcpy(pSendBuffer+iSendSize,_pNaluItems[i].data,iNaluSize);
            iSendSize += iNaluSize;
            iValidNaluCount++;
        }
        
        unsigned int uiVideoTimestamp = 0;
        if (_uiStartTimestamp == 0) {
            _uiStartTimestamp = RTMP_GetTime();
        }else{
            uiVideoTimestamp = RTMP_GetTime()-_uiStartTimestamp;
        }
//        iRet =SendH264Packet(pSendBuffer, iSendSize, isKey, uiVideoTimestamp);
        if(isKey != 0)
        {
            LOGI("SCREEN_CONTENT_REAL_TIME(%d) I Frame return %d, 0x%02x, timestamp=%u, audio_ts=%d", iSendSize, iRet, pSendBuffer[0], uiVideoTimestamp, _uiAudioDTS);
        }
        
        free(pSendBuffer);
    }
    
    return iRet;
}

int LibRtmpSession::ReadData(unsigned char* buffer, int iSize)
{
    int iRet = 0;
    if(_pRtmp == NULL)
    {
        return -1;
    }
    
    iRet = RTMP_Read(_pRtmp, (char*)buffer, iSize);
    return iRet;
}

int LibRtmpSession::GetReadStatus()
{
    int iStatus = _pRtmp->m_read.status;
    
    return iStatus;
}

int LibRtmpSession::GetAACType()
{
    return _iAacType;
}

int LibRtmpSession::GetSampleRate()
{
    return _iSampleRate;
};
int LibRtmpSession::GetChannels()
{
    return _iChannels;
};
