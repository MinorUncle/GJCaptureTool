//
//  LibRtmpSession.hpp
//  AudioEditX
//
//  Created by Alex.Shi on 16/3/8.
//  Copyright © 2016年 com.Alex. All rights reserved.
//

#ifndef RtmpSession_hpp
#define RtmpSession_hpp

#include <stdio.h>
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif
    
#define RTMP_TYPE_PLAY 0
#define RTMP_TYPE_PUSH 1
    
    typedef struct RTMP RTMP;
    typedef struct RTMPPacket RTMPPacket;
    typedef struct _RTMPMetadata RTMPMetadata;
    typedef struct _DataItem DataItem;
    
    class LibRtmpSession{
    public:
        LibRtmpSession(char* szRtmpUrl);
        ~LibRtmpSession();
        
        int Connect(int iFlag);
        void DisConnect();
        int IsConnected();
        
        int SendAudioRawData(unsigned char* pBuff, int len, unsigned int ts);
        
        int SendVideoRawData(unsigned char* buf, int videodatalen, unsigned int ts);
        int GetConnectedFlag(){return  _iConnectFlag;};
        void SetConnectedFlag(int iConnectFlag){_iConnectFlag=iConnectFlag;};
        
        int GetASCSentFlag();
        void GetASCInfo(unsigned short usAscFlag);
        int SendAudioSpecificConfig(int aactype, int sampleRate, int channels);
        void MakeAudioSpecificConfig(char* pData, int aactype, int sampleRate, int channels);
        
        int SendAudioSpecificConfig(unsigned short usASCFlag);
        int SendAudioData(unsigned char* buf, int size);
        int SendAACData(unsigned char* buf, int size, unsigned int timeStamp);
        
        int SendVideoSpsPps(unsigned char *pps,int pps_len,unsigned char * sps,int sps_len, int pts,int dts);
        int SendVideoData(unsigned char* buf, int size);
        int SendH264Packet(unsigned char *data,unsigned int size,int bIsKeyFrame,unsigned int nTimeStamp,int pts);
        
        int ReadData(unsigned char* buf, int iSize);
        int GetReadStatus();
        
        void GetSpsInfo(unsigned char* pSpsData, int iLength);
        int GetAACType();
        int GetSampleRate();
        int GetChannels();
        int getSampleRateByType(int iType);
        
    private:
        LibRtmpSession();
        
        int RtmpPacketSend(RTMPPacket* packet);
        int SendPacket(unsigned int nPacketType,unsigned char *data,unsigned int size,unsigned int nTimestamp);
        int getSampleRateType(int iSampleRate);
        
        int SeparateNalus(unsigned char* pBuff, int len);
    private:
        int _iAacType;
        int _iSampleRate;
        int _iChannels;
        
        int _iWidth;
        int _iHeight;
        int _iFps;
        
        char _szRtmpUrl[256];
        RTMP* _pRtmp;
        DataItem* _pAdtsItems;
        DataItem* _pNaluItems;
        int _iConnectFlag;
        int _iMetaDataFlag;
        int _iASCSentFlag;
        unsigned int _uiStartTimestamp;
        unsigned int _uiAudioDTS;
        unsigned int _uiVideoLastAudioDTS;
        unsigned int _uiAudioDTSNoChangeCnt;
        
        RTMPMetadata* _pMetaData;
        //pthread_mutex_t _mConnstatMutex;
    };
#ifdef __cplusplus
}
#endif
#endif /* RtmpSession_hpp */
