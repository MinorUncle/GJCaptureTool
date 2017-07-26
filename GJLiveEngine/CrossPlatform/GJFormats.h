//
//  Formats.h
//  GJCaptureTool
//
//  Created by 未成年大叔 on 16/10/16.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#ifndef Formats_h
#define Formats_h
#include "GJPlatformHeader.h"
typedef enum GJType{
    VideoType,
    AudooType,
}GJType;
typedef enum ProfileLevel{
    profileLevelBase,
    profileLevelMain,
    profileLevelHigh,
}ProfileLevel;
typedef enum EntropyMode{
    EntropyMode_CABAC,
    EntropyMode_CAVLC,
}EntropyMode;

#define VIDEO_TIMESCALE 1000


//typedef struct GJVideoFormat{
//    
//    uint32_t width,height;
//    uint8_t fps;
//    uint32_t bitRate;
//}GJVideoFormat;
//
//typedef struct H264Format{
//    GJVideoFormat baseFormat;
//    uint32_t gopSize;
//    EntropyMode model;
//    ProfileLevel level;
//    int allowBframe;
//    int allowPframe;
//}H264Format;





//typedef struct GJPacket{
//    uint32_t timestamp;
//    uint32_t pts;
//    uint32_t dts;
//    uint8_t* data;
//    uint32_t dataSize;
//}GJPacket;






#endif /* Formats_h */
