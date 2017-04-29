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
#include "GJRetainBufferPool.h"

//#define SEND_SEI
#define TEST
typedef struct TrafficUnit{
    GLong pts;//ms
    GLong count;
    GLong byte;
}GJTrafficUnit;
typedef struct TrafficStatus{
    GJTrafficUnit leave;
    GJTrafficUnit enter;
}GJTrafficStatus;
typedef struct H264Packet{
    GJRetainBuffer retain;
    GInt64 pts;
    GUInt8* sps;
    GInt32 spsSize;
    GUInt8* pps;
    GInt32 ppsSize;
    GUInt8* pp;
    GInt32 ppSize;
    GUInt8* sei;
    GInt32 seiSize;
}R_GJH264Packet;
typedef struct AACPacket{
    GJRetainBuffer retain;
    GInt64 pts;
    GLong adtsOffset;
    GInt32 adtsSize;
    GLong aacOffset;
    GInt32 aacSize;
}R_GJAACPacket;

typedef struct PCMPacket{
    GJRetainBuffer retain;
    GInt64 pts;
    GLong pcmOffset;
    GInt32 pcmSize;
}R_GJPCMPacket;

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

GJRetainBuffer* R_GJAACPacketMalloc(GJRetainBufferPool* pool,GHandle userdata);
GJRetainBuffer* R_GJPCMPacketMalloc(GJRetainBufferPool* pool,GHandle userdata);

GBool R_RetainBufferRelease(GJRetainBuffer* buffer);
#endif /* GJLiveDefine_internal_h */
