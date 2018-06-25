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
#include "GTime.h"
#define DEFAULT_MAX_DROP_STEP 30
#define MAX_SEND_DELAY 60000 //in ms,重启
#define SEND_DELAY_TIME 1500 //宏观检测的延迟时间限额
#define SEND_DELAY_COUNT 25  //宏观检测的延迟帧数限额

#define SEND_TIMEOUT 3

#define SEND_SEI

#ifdef __GNUC__
# define likely(p)     __builtin_expect(!!(p), 1)
# define unlikely(p)   __builtin_expect(!!(p), 0)
# define unreachable() __builtin_unreachable()
#else
# define likely(p)     (!!(p))
# define unlikely(p)   (!!(p))
# define unreachable() ((void)0)
#endif
//#define TEST

#define GRationalMake(num, den) \
    (GRational) { (GInt32)(num), (GInt32)(den) }
#define GRationalValue(rational) (GFloat)(rational).num * 1.0 / (rational).den
#define GRationalEqual(rational1, rational2) ((rational1).num == (rational2).num && (rational1).den == (rational2).den)

typedef struct TrafficUnit {
    GLong ts_drift;  //ts - clock  in ms.

    GTime ts;         //ms,最新pts，排序后
    GTime clock;      //ms,最新的系统时间
    
    GTime firstTs;    //第一帧，pts
    GTime firstClock; //第一帧时间
                      //    GLong dts;//dts只能单调上升，否则重新开始计算
    GLong count;
    GLong byte;
    
} GJTrafficUnit;
typedef struct TrafficStatus {
    GJTrafficUnit leave;
    GJTrafficUnit enter;
} GJTrafficStatus;

typedef enum _GJPlayStatus {
    kPlayStatusInvalid,
    kPlayStatusStop,
    kPlayStatusRunning,
    kPlayStatusPause,
    kPlayStatusBuffering,
} GJPlayStatus;

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

typedef enum _CODEC_TYPE {
    GJ_CODEC_TYPE_AAC,
    GJ_CODEC_TYPE_H264,
    GJ_CODEC_TYPE_MPEG4,
    GJ_CODEC_TYPE_MPEG2VIDEO,
} GJ_CODEC_TYPE;

typedef struct PCMFrame {
    GJRetainBuffer retain;
    GTime          pts;
    GTime          dts;
    GInt32         channel;
} R_GJPCMFrame;

typedef enum _GJFrameFlag {
    kGJFrameFlag_P_CVPixelBuffer = 1 << 0, //CVPixelBufferRef
    kGJFrameFlag_P_AVFrame       = 1 << 1, //AVFrame*
} GJFrameFlag;

typedef struct PixelFrame {
    GJRetainBuffer retain;
    GJPixelType    type;
    GTime          pts;
    GTime          dts;
    GInt32         width;
    GInt32         height;
    GJFrameFlag    flag;
} R_GJPixelFrame;

typedef enum _GJMediaType {
    GJMediaType_Video,
    GJMediaType_Audio,
} GJMediaType;

//#define GJPacketFlag_KEY 1 << 0
typedef enum _GJPacketFlag {
    GJPacketFlag_KEY            = 1 << 0,
    GJPacketFlag_DecoderType    = 1 << 1,
    GJPacketFlag_P_AVStreamType = 1 << 2, //AVStream*
    GJPacketFlag_AVPacketType   = 1 << 3, //AVPacket
} GJPacketFlag;

typedef struct GJPacket {
    GJRetainBuffer retain;
    GJMediaType    type;
    GTime          pts;
    GTime          dts;
    GInt64         dataOffset;
    GInt32         dataSize;
    GInt64         extendDataOffset;
    //h264表示sps，pps等,aac表示aac头
    GInt32       extendDataSize;
    GJPacketFlag flag;
} R_GJPacket;

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

GInt32 R_GJPacketMalloc(GJRetainBufferPool *pool);

GInt32 R_GJPCMFrameMalloc(GJRetainBufferPool *pool);
GInt32 R_GJPixelFrameMalloc(GJRetainBufferPool *pool);

GInt32 R_GJStreamFrameMalloc(GJRetainBufferPool* pool);


GBool R_RetainBufferRelease(GJRetainBuffer* buffer);
#endif /* GJLiveDefine_internal_h */
