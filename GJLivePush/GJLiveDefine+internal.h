//
//  GJLiveDefine+internal.h
//  GJCaptureTool
//
//  Created by melot on 2017/4/5.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJLiveDefine_internal_h
#define GJLiveDefine_internal_h
#include "GJRetainBuffer.h"
typedef struct H264Packet{
    GJRetainBuffer retain;
    uint8_t* memBlock;
    int needPreSize;
    int64_t pts;
    uint8_t* sps;
    int spsSize;
    uint8_t* pps;
    int ppsSize;
    uint8_t* pp;
    int ppSize;
    uint8_t* sei;
    int seiSize;
}R_GJH264Packet;
typedef struct AACPacket{
    GJRetainBuffer retain;
    uint8_t* memBlock;
    int needPreSize;
    int64_t pts;
    uint8_t* adts;
    int adtsSize;
    uint8_t* aac;
    int aacSize;
}R_GJAACPacket;

typedef enum _GJMediaType{
    GJVideoType,
    GJAudioType,
}GJMediaType;

typedef struct _GJStreamPacket{
    GJMediaType type;
    union{
        R_GJAACPacket* aacPacket;
        R_GJH264Packet* h264Packet;
    }packet;
}GJStreamPacket;

#endif /* GJLiveDefine_internal_h */
