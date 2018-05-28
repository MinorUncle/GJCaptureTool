//
//  GJRtmpSender.c
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJBufferPool.h"
#include "GJLog.h"
#include "GJQueue.h"
#include "GJRetainBuffer.h"
#include "GJStreamPush.h"
#include "log.h"
#include "rtmp.h"

#include "GJUtil.h"
#include "sps_decode.h"
#include <pthread.h>

#define BUFFER_CACHE_SIZE 300

struct _GJStreamPush {
    RTMP *          rtmp;
    GJQueue *       sendBufferQueue;
    char            pushUrl[MAX_URL_LENGTH];
    pthread_t       sendThread;
    pthread_mutex_t mutex;

    StreamPushMessageCallback messageCallback;
    void *                    rtmpPushParm;
    int                       stopRequest;
    int                       releaseRequest;

    GJTrafficStatus audioStatus;
    GJTrafficStatus videoStatus;

    GJAudioStreamFormat *audioFormat;
    GJVideoStreamFormat *videoFormat;
};

//typedef struct _GJStream_Packet {
//    RTMPPacket packet;
//    GJRetainBuffer*buffer;
//}GJStream_Packet;

GVoid GJStreamPush_Delloc(GJStreamPush *push);
GVoid GJStreamPush_Close(GJStreamPush *sender);

GVoid GJStreamPush_Release(GJStreamPush *sender);

GBool RTMP_AllocAndPackAACSequenceHeader(GJStreamPush *push, GInt32 aactype, GInt32 sampleRate, GInt32 channels, GUInt64 dts, RTMPPacket *sendPacket);
GBool RTMP_AllocAndPakcetAVCSequenceHeader(GJStreamPush *push, GUInt8 *sps, GInt32 spsSize, GUInt8 *pps, GInt32 ppsSize, GUInt64 dts, RTMPPacket *sendPacket);

static GInt32 interruptCB(GVoid *opaque) {
    GJStreamPush *push = (GJStreamPush *) opaque;
    return push->stopRequest;
}

static GHandle sendRunloop(GHandle parm) {

    pthread_setname_np("Loop.GJStreamPush");
    GJStreamPush *         push    = (GJStreamPush *) parm;
    kStreamPushMessageType errType = kStreamPushMessageType_connectError;
    GHandle                errParm = GNULL;

    GInt32 ret;
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "Stream_SetupURL success");
    RTMP_EnableWrite(push->rtmp);

    push->rtmp->Link.timeout = SEND_TIMEOUT;
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "开始连接服务器。。。");

    ret = RTMP_Connect(push->rtmp, GNULL);
    if (!ret) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "Stream_Connect error");
        errType = kStreamPushMessageType_connectError;
        goto ERROR;
    }

    RTMP_DeleteStream(push->rtmp);

    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "服务器连接成功，开始连接流");
    ret = RTMP_ConnectStream(push->rtmp, 3000);

    if (!ret) {

        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "Stream_ConnectStream error");
        errType = kStreamPushMessageType_connectError;
        goto ERROR;

    } else {

        if (push->messageCallback) {
            push->messageCallback(push->rtmpPushParm, kStreamPushMessageType_connectSuccess, GNULL);
        }
    }

    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "Stream_ConnectStream success");
    R_GJPacket *packet;

    RTMPPacket rtmpPacket;

    while (queuePop(push->sendBufferQueue, (GHandle *) &packet, INT32_MAX)) {

        if (push->stopRequest) {
            R_BufferUnRetain(&packet->retain);
            break;
        }

        if (packet->type == GJMediaType_Video) {

            if (packet->extendDataSize > 0) {
                GUInt8 *start = packet->extendDataOffset + R_BufferStart(&packet->retain);
                GUInt8 *sps = GNULL, *pps = GNULL;

                if ((start[4] & 0x1f) == 7) {
                    GInt32     spsSize = ntohl(*(GInt32*)start), ppsSize = ntohl(*(GInt32*)(start+4+spsSize));
                    sps = start + 4;
                    pps = sps + spsSize + 4;
                    
                    RTMPPacket avcPacket;
                    if (RTMP_AllocAndPakcetAVCSequenceHeader(push, sps, spsSize, pps, ppsSize, packet->dts, &avcPacket)) {

                        GInt32 iRet = RTMP_SendPacket(push->rtmp, &avcPacket, 0);
                        RTMPPacket_Free(&avcPacket);

                        if (iRet == GFalse) {
                            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "error send video FRAME");
                            R_BufferUnRetain(&packet->retain);
                            errType = kStreamPushMessageType_sendPacketError;
                            goto ERROR;
                        }


                        if (packet->dataSize <= 0) { //没有数据
                            push->videoStatus.leave.byte  = packet->dataSize;
                            push->videoStatus.leave.count = 1;
                            push->videoStatus.leave.ts    = (GLong) packet->dts;
                            continue;
                        }
                    } else {
                        R_BufferUnRetain(&packet->retain);
                        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "RTMP_AllocAndPakcetAVCSequenceHeader");
                        errType = kStreamPushMessageType_sendPacketError;
                        goto ERROR;
                    }
                } else {

                    GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "没有sps，pps，丢弃该帧");
                    push->videoStatus.leave.byte  = packet->dataSize;
                    push->videoStatus.leave.count = 1;
                    push->videoStatus.leave.ts    = (GLong) packet->dts;

                    R_BufferUnRetain(&packet->retain);
                    continue;
                }
            }else{
                if (push->videoStatus.enter.count == 0) {
                    GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "第一帧必须是关键帧");
                }
            }

            GInt32  ppPreSize = 5; //flv tag前置预留大小大小
            GUInt8  fristByte = 0x27;
            GUInt8 *nal_start = R_BufferStart(&packet->retain) + packet->dataOffset;
            if ((nal_start[4] & 0x1f) == 7) {
                fristByte = 0x17;
            }

            
            GInt32 preSize = ppPreSize + RTMP_MAX_HEADER_SIZE;
            if (nal_start - R_BufferStart(&packet->retain) + R_BufferFrontSize(&packet->retain) < preSize) {
//申请内存控制得当的话不会进入此条件、  先扩大，在查找。
#if MEMORY_CHECK
                GJAssert(0, "MEMORY_CHECK 状态下不能扩大内存");
#endif
                GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "预留位置过小,扩大");
                GInt32 nal_offset = (GInt32)(nal_start - R_BufferStart(&packet->retain));
                R_BufferMoveDataToPoint(&packet->retain, RTMP_MAX_HEADER_SIZE + ppPreSize, GTrue);

                if (packet->dataSize > 0) {
                    nal_start = nal_offset + R_BufferStart(&packet->retain);
                }
            }

            GUChar *body   = GNULL;
            GInt32  iIndex = 0;

            RTMPPacket_Reset(&rtmpPacket);
            //    使用pp做参考点，防止sei不发送的情况，导致pp移动，产生消耗
            rtmpPacket.m_body            = (GChar *) nal_start - ppPreSize;
            rtmpPacket.m_nBodySize       = (GUInt32)(R_BufferStart(&packet->retain) + packet->dataOffset + packet->dataSize - nal_start + ppPreSize);
            body                         = (GUChar *) rtmpPacket.m_body;
            rtmpPacket.m_packetType      = RTMP_PACKET_TYPE_VIDEO;
            rtmpPacket.m_nChannel        = 0x04;
            rtmpPacket.m_hasAbsTimestamp = 0;
            rtmpPacket.m_headerType      = RTMP_PACKET_SIZE_LARGE;
            rtmpPacket.m_nInfoField2     = push->rtmp->m_stream_id;
            rtmpPacket.m_nTimeStamp      = (uint32_t) packet->dts;
            if (packet->dataSize > 0) {
                body[iIndex++] = fristByte;
                body[iIndex++] = 0x01; // AVC NALU
                GInt32 ct      = (GInt32)(packet->pts - packet->dts);

                body[iIndex++] = ct & 0xff0000;
                body[iIndex++] = ct & 0xff00;
                body[iIndex++] = ct & 0xff;
            }

            GInt32 iRet = RTMP_SendPacket(push->rtmp, &rtmpPacket, 0);

            push->videoStatus.leave.ts = packet->dts;
            push->videoStatus.leave.count++;
            push->videoStatus.leave.byte += rtmpPacket.m_nBodySize;
            R_BufferUnRetain(&packet->retain);

            if (iRet == GFalse) {
                GJLOG(DEFAULT_LOG, GJ_LOGERROR, "error send video FRAME");
                errType = kStreamPushMessageType_sendPacketError;
                goto ERROR;
            }else{
                GJLOG(DEFAULT_LOG, GJ_LOGALL, "send video pts:%lld dts:%lld size:%d",packet->pts,packet->dts,packet->dataSize);
            }
        } else {
            //            printf("send packet pts:%lld size:%d  last data:%d\n",packet->pts,packet->dataSize,(packet->retain.data + packet->dataOffset + packet->dataSize -1)[0]);

            if (push->audioStatus.leave.count == 0) {
                RTMPPacket aacPacket;
                if (RTMP_AllocAndPackAACSequenceHeader(push, 2, push->audioFormat->format.mSampleRate, push->audioFormat->format.mChannelsPerFrame, packet->dts, &aacPacket)) {

                    GInt32 iRet = RTMP_SendPacket(push->rtmp, &aacPacket, 0);
                    RTMPPacket_Free(&aacPacket);

                    push->audioStatus.leave.byte  = aacPacket.m_nBodySize;
                    push->audioStatus.leave.count = 1;
                    push->audioStatus.leave.ts    = (GLong) packet->dts;
                    R_BufferUnRetain(&packet->retain);

                    if (iRet == GFalse) {
                        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "error send video FRAME");
                        errType = kStreamPushMessageType_sendPacketError;
                        goto ERROR;
                    }
                    continue;
                } else {

                    GJLOG(DEFAULT_LOG, GJ_LOGERROR, "RTMP_AllocAndPackAACSequenceHeader");
                    errType = kStreamPushMessageType_sendPacketError;
                    R_BufferUnRetain(&packet->retain);
                    goto ERROR;
                }
            }

            GUChar *body;
            GInt32  preSize = 2;

            RTMPPacket_Reset(&rtmpPacket);
            if (packet->dataOffset + R_BufferFrontSize(&packet->retain) < preSize + RTMP_MAX_HEADER_SIZE) { //申请内存控制得当的话不会进入此条件、
#if MEMORY_CHECK
                GJAssert(0, "MEMORY_CHECK 状态下不移动内存");
#endif
                GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "产生内存移动");
                R_BufferMoveDataToPoint(&packet->retain, RTMP_MAX_HEADER_SIZE + preSize, GTrue);
            }

            rtmpPacket.m_body      = (GChar *) (packet->dataOffset + R_BufferStart(&packet->retain) - preSize);
            rtmpPacket.m_nBodySize = packet->dataSize + preSize;

            body = (GUChar *) rtmpPacket.m_body;

            /*AF 01 + AAC RAW data*/
            body[0] = 0xAF;
            body[1] = 0x01;

            rtmpPacket.m_packetType      = RTMP_PACKET_TYPE_AUDIO;
            rtmpPacket.m_nChannel        = 0x04;
            rtmpPacket.m_nTimeStamp      = (int32_t) packet->dts;
            rtmpPacket.m_hasAbsTimestamp = 0;
            rtmpPacket.m_headerType      = RTMP_PACKET_SIZE_LARGE;
            rtmpPacket.m_nInfoField2     = push->rtmp->m_stream_id;

            GInt32 iRet = RTMP_SendPacket(push->rtmp, &rtmpPacket, 0);
            push->audioStatus.leave.byte += rtmpPacket.m_nBodySize;
            push->audioStatus.leave.count++;
            push->audioStatus.leave.ts = packet->dts;
            R_BufferUnRetain(&packet->retain);

            if (iRet == GFalse) {
                GJLOG(DEFAULT_LOG, GJ_LOGERROR, "error send packet FRAME");
                errType = kStreamPushMessageType_sendPacketError;
                goto ERROR;
            }else{
                GJLOG(DEFAULT_LOG, GJ_LOGALL, "send audio pts:%lld dts:%lld size:%d",packet->pts,packet->dts,packet->dataSize);
            }
        }
    }

    errType = kStreamPushMessageType_closeComplete;
ERROR:

    if (push->messageCallback) {
        push->messageCallback(push->rtmpPushParm, errType, errParm);
    }
    RTMP_Close(push->rtmp);
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&push->mutex);
    push->sendThread = GNULL;
    if (push->releaseRequest == GTrue) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&push->mutex);
    if (shouldDelloc) {
        GJStreamPush_Delloc(push);
    }
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "sendRunloop end");

    return GNULL;
}

GBool GJStreamPush_Create(GJStreamPush **sender, StreamPushMessageCallback callback, GHandle streamPushParm, const GJAudioStreamFormat *audioFormat, const GJVideoStreamFormat *videoFormat) {
    GJStreamPush *push = GNULL;
    if (*sender == GNULL) {
        push = (GJStreamPush *) malloc(sizeof(GJStreamPush));
    } else {
        push = *sender;
    }
    memset(push, 0, sizeof(GJStreamPush));
    push->rtmp = RTMP_Alloc();
    RTMP_Init(push->rtmp);
    RTMP_SetInterruptCB(push->rtmp, interruptCB, push);
    RTMP_SetTimeout(push->rtmp, 8000);
    queueCreate(&push->sendBufferQueue, BUFFER_CACHE_SIZE, GTrue, GTrue);
    push->messageCallback = callback;
    push->rtmpPushParm    = streamPushParm;
    push->stopRequest     = GFalse;
    push->releaseRequest  = GFalse;
    if (audioFormat) {
        push->audioFormat  = (GJAudioStreamFormat *) malloc(sizeof(GJAudioStreamFormat));
        *push->audioFormat = *audioFormat;
    }
    if (videoFormat) {
        push->videoFormat  = (GJVideoStreamFormat *) malloc(sizeof(GJVideoStreamFormat));
        *push->videoFormat = *videoFormat;
    }
    pthread_mutex_init(&push->mutex, GNULL);
    *sender = push;
    return GTrue;
}
//static GBool sequenceHeaderReleaseCallBack(GJRetainBuffer * buffer){
//    free(buffer->data);
//    free(buffer);
//    return GTrue;
//}
GBool RTMP_AllocAndPakcetAVCSequenceHeader(GJStreamPush *push, GUInt8 *sps, GInt32 spsSize, GUInt8 *pps, GInt32 ppsSize, GUInt64 dts, RTMPPacket *sendPacket) {
    if (push == GNULL) return GFalse;
    RTMPPacket_Reset(sendPacket);

    GInt32 needSize = spsSize + ppsSize + 16;
    if (!RTMPPacket_Alloc(sendPacket, needSize)) {
        return GFalse;
    }

    sendPacket->m_nBodySize       = needSize;
    sendPacket->m_packetType      = RTMP_PACKET_TYPE_VIDEO;
    sendPacket->m_nChannel        = 0x04;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType      = RTMP_PACKET_SIZE_MEDIUM;
    sendPacket->m_nInfoField2     = push->rtmp->m_stream_id;
    sendPacket->m_nTimeStamp      = (GUInt32) dts;

    GUInt8 *body   = (GUInt8 *) sendPacket->m_body;
    GInt32  iIndex = 0;

    body[iIndex++] = 0x17;
    body[iIndex++] = 0x00;

    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;

    ////AVCDecoderConfigurationRecord
    body[iIndex++] = 0x01;
    body[iIndex++] = sps[1];
    body[iIndex++] = sps[2];
    body[iIndex++] = sps[3];
    body[iIndex++] = 0xff;

    /*sps*/
    body[iIndex++] = 0xe1;
    body[iIndex++] = spsSize >> 8 & 0xff;
    body[iIndex++] = spsSize & 0xff;
    memcpy(&body[iIndex], sps, spsSize);
    iIndex += spsSize;

    /*pps*/
    body[iIndex++] = 0x01;
    body[iIndex++] = ppsSize >> 8 & 0xff;
    body[iIndex++] = ppsSize & 0xff;
    memcpy(&body[iIndex], pps, ppsSize);

    return GTrue;
}
//GBool GJStreamPush_SendH264Data(GJStreamPush* sender,R_GJPacket* packet){
//    if (sender == GNULL) {
//        return GFalse;
//    }
//    GBool isKey = GFalse;
//    GUInt8 *pp = GNULL;
//    GInt32 ppSize = 0;
//    GInt32 ppPreSize = 0;//flv tag前置预留大小大小
//    GUInt8 fristByte = 0x27;
//    if (packet->flag == GJPacketFlag_KEY) {
//        ppPreSize = 5;
//        ppSize = packet->dataSize;
//        pp = packet->dataOffset+packet->retain.data;
//        if ((pp[0] & 0x1F) == 5 || (pp[0] & 0x1F) == 6) {
//            isKey = GTrue;
//            fristByte = 0x17;
//        }
//    }else{
//        GJAssert(0, "没有pp");
//        return GFalse;
//    }
//
//    GInt32 preSize = ppPreSize+RTMP_MAX_HEADER_SIZE;
//    if (pp-packet->retain.data + packet->retain.frontSize < preSize) {//申请内存控制得当的话不会进入此条件、  先扩大，在查找。
//        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "预留位置过小,扩大");
//       R_BufferMoveDataToPoint(&packet->retain, RTMP_MAX_HEADER_SIZE+ppPreSize, GTrue);
//
//        if (packet->dataSize > 0) {
//            pp = packet->dataOffset+packet->retain.data;
//        }
//    }
//
//    GJStream_Packet* pushPacket = (GJStream_Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJStream_Packet));
//    memset(pushPacket, 0, sizeof(GJStream_Packet));
//    GJRetainBuffer*buffer = (GJRetainBuffer*)packet;
//    pushPacket->buffer =buffer;
//    RTMPPacket* sendPacket = &pushPacket->packet;
//
//    GUChar * body=GNULL;
//    GInt32 iIndex = 0;
//
//
////    使用pp做参考点，防止sei不发送的情况，导致pp移动，产生消耗
//    sendPacket->m_body = (GChar*)pp - ppPreSize;
//    sendPacket->m_nBodySize = ppSize+ppPreSize;
//    body = (GUChar *)sendPacket->m_body;
//    sendPacket->m_packetType = RTMP_PACKET_TYPE_VIDEO;
//    sendPacket->m_nChannel = 0x04;
//    sendPacket->m_hasAbsTimestamp = 0;
//    sendPacket->m_headerType = RTMP_PACKET_SIZE_LARGE;
//    sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
//    sendPacket->m_nTimeStamp = (uint32_t)packet->pts;
//    if (packet->dataSize > 0) {
//        body[iIndex++] = fristByte;
//        body[iIndex++] = 0x01;// AVC NALU
//
//        body[iIndex++] = 0x00;
//        body[iIndex++] = 0x00;
//        body[iIndex++] = 0x00;
//    }
//
//   R_BufferRetain(buffer);
//    if (queuePush(sender->sendBufferQueue, pushPacket, 0)) {
//        sender->videoStatus.enter.ts = pushPacket->packet.m_nTimeStamp;
//        sender->videoStatus.enter.count++;
//        sender->videoStatus.enter.byte += pushPacket->packet.m_nBodySize;
//        return GTrue;
//    }else{
//        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "不可能出现的错误");
//       R_BufferUnRetain(buffer);
//        GJBufferPoolSetData(defauleBufferPool(), (GHandle)pushPacket);
//        return GFalse;
//    }
//}
GBool RTMP_AllocAndPackAACSequenceHeader(GJStreamPush *push, GInt32 aactype, GInt32 sampleRate, GInt32 channels, GUInt64 dts, RTMPPacket *sendPacket) {
    if (push == GNULL) {
        return GFalse;
    }
    GUInt8 srIndex = 0;
    if (sampleRate == 44100) {
        srIndex = 4;
    } else if (sampleRate == 22050) {
        srIndex = 7;
    } else if (sampleRate == 11025) {
        srIndex = 10;
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "sampleRate error");
        return GFalse;
    }

    GUInt8 config1  = (aactype << 3) | ((srIndex & 0xe) >> 1);
    GUInt8 config2  = ((srIndex & 0x1) << 7) | (channels << 3);
    GInt32 needSize = 2 + 2;
    RTMPPacket_Reset(sendPacket);
    if (!RTMPPacket_Alloc(sendPacket, needSize)) {
        return GFalse;
    };
    sendPacket->m_nBodySize       = needSize;
    sendPacket->m_packetType      = RTMP_PACKET_TYPE_AUDIO;
    sendPacket->m_nChannel        = 0x04;
    sendPacket->m_hasAbsTimestamp = 0;
    sendPacket->m_headerType      = RTMP_PACKET_SIZE_MEDIUM;
    sendPacket->m_nInfoField2     = push->rtmp->m_stream_id;
    sendPacket->m_nTimeStamp      = (GUInt32) dts;

    GUInt8 *body = (GUInt8 *) sendPacket->m_body;
    body[0]      = 0xAF;
    body[1]      = 0x00;
    body[2]      = config1;
    body[3]      = config2;
    return GTrue;
}
//GBool GJStreamPush_SendAACData(GJStreamPush* sender,R_GJPacket* buffer){
//    if (sender == GNULL) {
//        return GFalse;
//    }
//    GUChar * body;
//    GInt32 preSize = 2;
//    GJStream_Packet* pushPacket = (GJStream_Packet*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(GJStream_Packet));
//
//    GJRetainBuffer*buffer = &buffer->retain;
//    pushPacket->buffer =buffer;
//
//    RTMPPacket* sendPacket = &pushPacket->packet;
//    RTMPPacket_Reset(sendPacket);
//    if (buffer->dataOffset+buffer->retain.frontSize < preSize+RTMP_MAX_HEADER_SIZE) {//申请内存控制得当的话不会进入此条件、
//        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "产生内存移动");
//       R_BufferMoveDataToPoint(&buffer->retain, RTMP_MAX_HEADER_SIZE+preSize, GTrue);
//    }
//
//    sendPacket->m_body = (GChar*)(buffer->dataOffset +buffer->retain.data - preSize);
//    sendPacket->m_nBodySize = buffer->dataSize+preSize;
//
//    body = (GUChar *)sendPacket->m_body;
//
//    /*AF 01 + AAC RAW data*/
//    body[0] = 0xAF;
//    body[1] = 0x01;
//
//    sendPacket->m_packetType = RTMP_PACKET_TYPE_AUDIO;
//    sendPacket->m_nChannel = 0x04;
//    sendPacket->m_nTimeStamp = (int32_t)buffer->pts;
//    sendPacket->m_hasAbsTimestamp = 0;
//    sendPacket->m_headerType = RTMP_PACKET_SIZE_LARGE;
//    sendPacket->m_nInfoField2 = sender->rtmp->m_stream_id;
//   R_BufferRetain(buffer);
//
//    if (queuePush(sender->sendBufferQueue, pushPacket, 0)) {
//        sender->audioStatus.enter.ts = pushPacket->packet.m_nTimeStamp;
//        sender->audioStatus.enter.count++;
//        sender->audioStatus.enter.byte += pushPacket->packet.m_nBodySize;
//        return GTrue;
//    }else{
//        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "不可能出现的错误");
//       R_BufferUnRetain(buffer);
//        GJBufferPoolSetData(defauleBufferPool(), (GHandle)pushPacket);
//        return GFalse;
//    }
//}
GBool GJStreamPush_SendVideoData(GJStreamPush *push, R_GJPacket *packet) {

    if (push == GNULL) return GFalse;

    R_BufferRetain(&packet->retain);
    if (queuePush(push->sendBufferQueue, packet, 0)) {
        
        push->videoStatus.enter.ts = (GLong) packet->dts;
        push->videoStatus.enter.count++;
        push->videoStatus.enter.byte += packet->dataSize;

    } else {
        R_BufferUnRetain(&packet->retain);
    }

    return GTrue;
}
GBool GJStreamPush_SendAudioData(GJStreamPush *push, R_GJPacket *packet) {

    if (push == GNULL) return GFalse;

    R_BufferRetain(&packet->retain);
    if (queuePush(push->sendBufferQueue, packet, 0)) {

        push->audioStatus.enter.ts = (GLong) packet->dts;
        push->audioStatus.enter.count++;
        push->audioStatus.enter.byte += packet->dataSize;
    } else {
        R_BufferUnRetain(&packet->retain);
    }
    return GTrue;
}
GBool GJStreamPush_StartConnect(GJStreamPush *sender, const GChar *sendUrl) {

    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJStreamPush_StartConnect:%p", sender);

    size_t length = strlen(sendUrl);
    memset(&sender->videoStatus, 0, sizeof(GJTrafficStatus));
    memset(&sender->audioStatus, 0, sizeof(GJTrafficStatus));
    GJAssert(length <= MAX_URL_LENGTH - 1, "sendURL 长度不能大于：%d", MAX_URL_LENGTH - 1);
    memcpy(sender->pushUrl, sendUrl, length + 1);
    if (sender->sendThread) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "上一个push没有释放，开始释放并等待");
        GJStreamPush_Close(sender);
        pthread_join(sender->sendThread, GNULL);
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "等待push释放结束");
    }
    sender->stopRequest = GFalse;

    if (!RTMP_SetupURL(sender->rtmp, sender->pushUrl)) {
        return GFalse;
    }
    queueEnablePush(sender->sendBufferQueue, GTrue);
    queueEnablePop(sender->sendBufferQueue, GTrue);
    GInt32 ret = pthread_create(&sender->sendThread, GNULL, sendRunloop, sender);
    if (ret != 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "pthread_create error:%d",ret);
    }
    return ret == 0;
}
GVoid GJStreamPush_Delloc(GJStreamPush *push) {

    RTMP_Free(push->rtmp);
    GInt32 length = queueGetLength(push->sendBufferQueue);
    if (length > 0) {
        R_GJPacket **packet = (R_GJPacket **) malloc(sizeof(R_GJPacket *) * length);
        //queuepop已经关闭
        if (queueClean(push->sendBufferQueue, (GHandle *) packet, &length)) {
            for (GInt32 i = 0; i < length; i++) {
                R_BufferUnRetain(&packet[i]->retain);
            }
        }
        free(packet);
    }
    queueFree(&push->sendBufferQueue);

    if (push->videoFormat) free(push->videoFormat);
    if (push->audioFormat) free(push->audioFormat);

    free(push);
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPush_Delloc:%p", push);
}
GVoid GJStreamPush_CloseAndDealloc(GJStreamPush **push) {

    GJStreamPush_Close(*push);
    GJStreamPush_Release(*push);
    *push = GNULL;
}
GVoid GJStreamPush_Release(GJStreamPush *push) {
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJStreamPush_Release::%p", push);

    GBool shouldDelloc    = GFalse;
    push->messageCallback = GNULL;
    pthread_mutex_lock(&push->mutex);
    push->releaseRequest = GTrue;
    if (push->sendThread == GNULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&push->mutex);
    if (shouldDelloc) {
        GJStreamPush_Delloc(push);
    }
}
GVoid GJStreamPush_Close(GJStreamPush *sender) {
    if (sender->stopRequest) {
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJStreamPush_Close：%p  重复关闭", sender);
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJStreamPush_Close:%p", sender);
        sender->stopRequest = GTrue;
        queueEnablePush(sender->sendBufferQueue, GFalse);
        queueEnablePop(sender->sendBufferQueue, GFalse);
        queueBroadcastPop(sender->sendBufferQueue);
        queueBroadcastPush(sender->sendBufferQueue);
    }
}

GFloat32 GJStreamPush_GetBufferRate(GJStreamPush *sender) {
    return queueGetCacheRate(sender->sendBufferQueue);
    //    GLong length = queueGetLength(sender->sendBufferQueue);
    //    GFloat32 size = sender->sendBufferQueue->allocSize * 1.0;
    ////    GJPrintf("BufferRate length:%ld ,size:%f   rate:%f\n",length,size,length/size);
    //    return length / size;
};
GJTrafficStatus GJStreamPush_GetVideoBufferCacheInfo(GJStreamPush *push) {
    if (push == GNULL) {
        return (GJTrafficStatus){0};
    } else {
        return push->videoStatus;
    }
}
GJTrafficStatus GJStreamPush_GetAudioBufferCacheInfo(GJStreamPush *push) {
    if (push == GNULL) {
        return (GJTrafficStatus){0};
    } else {
        return push->audioStatus;
    }
}
