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

/**
 获得当前时间

 @return scale in us
 */
GTime GJ_Gettime();

GInt32 GJ_GetCPUCount();
GFloat32 GJ_GetCPUUsage();

typedef struct _AVCC{
    
}AVCC;

typedef struct _GASC{
    GUInt8 frameLengthFlag;//1 b
    GUInt8 dependsOnCoreCorer;//1 b
    GUInt8 extensionFlag;//1 b
}GASC;

#define ADTS_SAMPLERATE_LEN 13
#define AST_SAMPLERATE_LEN 4

const GUInt32 astFrequency[AST_SAMPLERATE_LEN] = {5510,11025,22050,44100};
const GUInt32 adtsFrequency[ADTS_SAMPLERATE_LEN] = {96000,88200,64000,48000,44100,32000,24000,22050,16000,12000,11025,8000,7350};

typedef struct _AST{
    GUInt8 audioType;//5 b
    GUInt32 sampleRate;//4 b
    GUInt8 channelConfig;//4 b
    GASC asc;//3 b
}AST;

typedef struct _ADTS_VAR_H{
    GUInt16 aac_frame_length;//13 b
    GUInt16 adts_buffer_fullness;//11 b
    GUInt16 number_of_raw_data_blocks_in_frame;//2 b
}ADTS_VAR_H;
typedef struct _ADTS{
    GUInt8 ID;//1 b,MPEG Version: 0 for MPEG-4，1 for MPEG-2
    GUInt8 layer;//2 b,always: '00'
    GUInt8 protection_absent;//1 b,Warning, set to 1 if there is no CRC and 0 if there is CRC
    GUInt8 profile;//2 b,
    GUInt32 sampleRate;//4 b
    GUInt8 channelConfig;//3 b
    
    ADTS_VAR_H varHeader;
    
}ADTS;
//返回处理的长度，小于等于0表示内存不够或者不符合该结构
GInt32 writeADTS(GUInt8* buffer,GUInt8 size,const ADTS* adts);
GInt32 readADTS(const GUInt8* data,GUInt8 size,ADTS* adts);
GInt32 readASC(const GUInt8* data,GUInt8 size,AST* ast);
GInt32 writeASC(GUInt8* buffer,GUInt8 size,const AST* ast);
#endif /* GJUtil_h */
