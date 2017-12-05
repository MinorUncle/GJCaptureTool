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
#define DEFAULT_MAX_DROP_STEP 30
#define MAX_SEND_DELAY 60000  //in ms,重启
#define SEND_DELAY_TIME 1500 //宏观检测的延迟时间限额
#define SEND_DELAY_COUNT 25 //宏观检测的延迟帧数限额

#define SEND_TIMEOUT 3


#define SEND_SEI
//#define TEST


#define GRationalMake(num,den)  (GRational){(GInt32)(num),(GInt32)(den)}
#define GRationalValue(rational) (GFloat32)(rational).num*1.0/(rational).den

//typedef struct GStickerParm{
//    GCRect frame;
//    GFloat32 rotation;
//    GHandle image;
//} GStickerParm;
typedef struct TrafficUnit{
    GLong ts;//ms,最新pts，排序后
    GTime clock;//ms,最新的系统时间
//    GLong dts;//dts只能单调上升，否则重新开始计算
    GLong count;
    GLong byte;
}GJTrafficUnit;
typedef struct TrafficStatus{
    GJTrafficUnit leave;
    GJTrafficUnit enter;
}GJTrafficStatus;

//typedef struct H264Packet{
//    GJRetainBuffer retain;
//    GInt64 pts;
//    GLong spsOffset;//裸数据
//    GInt32 spsSize;
//    GLong ppsOffset;//裸数据
//    GInt32 ppsSize;
//    GLong ppOffset;//四位大端字节表示长度
//    GInt32 ppSize;
//    GLong seiOffset;
//    GInt32 seiSize;
//}R_GJH264Packet;
//typedef struct AACPacket{
//    GJRetainBuffer retain;
//    GInt64 pts;
//    GLong adtsOffset;
//    GInt32 adtsSize;
//    GLong aacOffset;
//    GInt32 aacSize;
//}R_GJAACPacket;

typedef struct PCMFrame{
    GJRetainBuffer retain;
    GInt64 pts;
    GInt64 dts;
    GInt32 channel;
}R_GJPCMFrame;

typedef struct PixelFrame{
    GJRetainBuffer retain;
    GJPixelType type;
    GInt64 pts;
    GInt64 dts;
    GInt32 width;
    GInt32 height;
}R_GJPixelFrame;

typedef enum _GJMediaType{
    GJMediaType_Video,
    GJMediaType_Audio,
}GJMediaType;
typedef enum _GJPacketFlag{
    GJPacketFlag_KEY = 1 << 0,
}GJPacketFlag;
typedef struct GJPacket{
    GJRetainBuffer retain;
    GJMediaType type;
    GInt64 pts;
    GInt64 dts;
    GInt64 dataOffset;
    GInt32 dataSize;
    GInt64 extendDataOffset;
    //h264表示sps，pps等,aac表示aac头
    GInt32 extendDataSize;
    GJPacketFlag  flag;
}R_GJPacket;

//typedef struct GJStreamFrame{
//    union{
//        R_GJPCMFrame* pcmFrame;
//        R_GJPixelFrame* pixelFrame;
//    }frame;
//    GJMediaType mediaType;
//}R_GJStreamFrame;

//typedef struct _GJStreamPacket{
//    union{
//        R_GJAACPacket* aacPacket;
//        R_GJH264Packet* h264Packet;
//    }packet;
//    GJMediaType type;
//}R_GJStreamPacket;

//GJRetainBuffer* R_GJAACPacketMalloc(GJRetainBufferPool* pool,GHandle userdata);
//GJRetainBuffer* R_GJH264PacketMalloc(GJRetainBufferPool* pool,GHandle userdata);

GInt32 R_GJPacketMalloc(GJRetainBufferPool* pool);

GInt32 R_GJPCMFrameMalloc(GJRetainBufferPool* pool);
GInt32 R_GJPixelFrameMalloc(GJRetainBufferPool* pool);

GInt32 R_GJStreamFrameMalloc(GJRetainBufferPool* pool);


GBool R_RetainBufferRelease(GJRetainBuffer* buffer);
#endif /* GJLiveDefine_internal_h */
