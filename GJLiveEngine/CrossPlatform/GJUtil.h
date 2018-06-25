//
//  GJUtil.h
//  GJCaptureTool
//
//  Created by melot on 2017/5/11.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJUtil_h
#define GJUtil_h
#include "GJPlatformHeader.h"
#include "GJList.h"
#include "GTime.h"
/**
 获得当前时间

 @return scale in us
 */
GTime GJ_Gettime();
GLong getCurrentTime();
GInt32 GJ_GetCPUCount();
GFloat GJ_GetCPUUsage();

//快排
void quickSort(int* a,int len);

typedef struct _AVCC{
    
}AVCC;

typedef struct _GASC{
    GUInt8 frameLengthFlag;//1 b,0表示帧长为1024，1表示帧长为960
    GUInt8 dependsOnCoreCorer;//1 b
    GUInt8 extensionFlag;//1 b
}GASC;

typedef enum GJAudioObjectType {
    kGJ_AOT_NULL,
    // Support?                Name
    kGJ_AOT_AAC_MAIN,              ///< Y                       Main
    kGJ_AOT_AAC_LC,                ///< Y                       Low Complexity
    kGJ_AOT_AAC_SSR,               ///< N (code in SoC repo)    Scalable Sample Rate
    kGJ_AOT_AAC_LTP,               ///< Y                       Long Term Prediction
    kGJ_AOT_SBR,                   ///< Y                       Spectral Band Replication
}GJAudioObjectType;
typedef struct _ASC{
    GJAudioObjectType audioType;//5 b
    GUInt32 sampleRate;//4 b
    GUInt8 channelConfig;//4 b
    GASC gas;//3 b
}ASC;

typedef struct _ADTS_VAR_H{
    GUInt16 aac_frame_length;//13 b
    GUInt16 adts_buffer_fullness;//11 b
    GUInt16 number_of_raw_data_blocks_in_frame;//2 b
}ADTS_VAR_H;
typedef struct _ADTS{
    GUInt8 ID;//1 b,MPEG Version: 0 for MPEG-4，1 for MPEG-2
    GUInt8 layer;//2 b,always: '00'
    GUInt8 protection_absent;//1 b,Warning, set to 1 if there is no CRC and 0 if there is CRC
    GJAudioObjectType profile;//2 b,
    GUInt32 sampleRate;//4 b
    GUInt8 channelConfig;//3 b
    
    ADTS_VAR_H varHeader;
    
}ADTS;
//返回处理的长度，小于等于0表示内存不够或者不符合该结构
GInt32 writeADTS(GUInt8* buffer,GUInt8 size,const ADTS* adts);
GInt32 readADTS(const GUInt8* data,GUInt8 size,ADTS* adts);
GInt32 readASC(const GUInt8* data,GUInt8 size,ASC* asc);
GInt32 writeASC(GUInt8* buffer,GUInt8 size,const ASC* asc);

GVoid GJ_GetTimeStr(GChar* dest);//最少15字节个空间
#endif /* GJUtil_h */
