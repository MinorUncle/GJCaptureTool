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
#include "GJLiveDefine.h"
#define DEFAULT_MAX_DROP_STEP 8
#define MAX_SEND_DELAY 15000  //重启
#define SEND_DELAY_TIME 1500
#define SEND_DELAY_COUNT 25

//#define SEND_SEI
//#define TEST

typedef struct GRational{
    GInt32 num; ///< numerator
    GInt32 den; ///< denominator
} GRational;
#define GRationalMake(num,den) (GRational){(GInt32)(num),(GInt32)(den)}
#define GRationalValue(rational) (GFloat32)(rational).num*1.0/(rational).den
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
    GLong spsOffset;
    GInt32 spsSize;
    GLong ppsOffset;
    GInt32 ppsSize;
    GLong ppOffset;
    GInt32 ppSize;
    GLong seiOffset;
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
    GJMediaType_Video,
    GJMediaType_Audio,
}GJMediaType;

typedef struct GJFrame{
    GJRetainBuffer retain;
    GJMediaType mediaType;
    GLong pts;
}R_GJFrame;

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
