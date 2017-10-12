//
//  GJStreamPull.c
//  GJCaptureTool
//
//  Created by 未成年大叔 on 17/3/4.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJBufferPool.h"
#include "GJFLVPack.h"
#import "GJLiveDefine+internal.h"
#include "GJLog.h"
#include "GJStreamPull.h"
#include "rtmp.h"
#include "sps_decode.h"
#include <string.h>

#define BUFFER_CACHE_SIZE 40
#define RTMP_RECEIVE_TIMEOUT 10

struct _GJStreamPull {
    RTMP *rtmp;
    char  pullUrl[MAX_URL_LENGTH];
#if MENORY_CHECK
    GJRetainBufferPool *memoryCachePool;
#endif
    pthread_t       pullThread;
    pthread_mutex_t mutex;

    GJTrafficUnit videoPullInfo;
    GJTrafficUnit audioPullInfo;

    StreamPullMessageCallback messageCallback;
    StreamPullDataCallback    dataCallback;

    GHandle messageCallbackParm;
    GHandle dataCallbackParm;

    int stopRequest;
    int releaseRequest;
};

GVoid GJStreamPull_Delloc(GJStreamPull *pull);

static GBool packetBufferRelease(GJRetainBuffer *buffer) {
    if (R_BufferUserData(buffer) == GNULL) {
        //sps pps
        R_BufferFreeData(buffer);
    }
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8 *) buffer);
    return GTrue;
}
static GInt32 interruptCB(GVoid *opaque) {
    GJStreamPull *pull = (GJStreamPull *) opaque;
    return pull->stopRequest;
}
static GHandle pullRunloop(GHandle parm) {
    pthread_setname_np("Loop.GJStreamPull");
    GJStreamPull *         pull    = (GJStreamPull *) parm;
    kStreamPullMessageType errType = kStreamPullMessageType_connectError;
    GHandle                errParm = NULL;
    GInt32                 ret;
    pull->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;

    ret = RTMP_Connect(pull->rtmp, NULL);
    if (!ret) {
        errType = kStreamPullMessageType_connectError;
        GJLOG(GJ_LOGERROR, "RTMP_Connect error");
        goto ERROR;
    }
    ret = RTMP_ConnectStream(pull->rtmp, 0);
    if (!ret) {
        errType = kStreamPullMessageType_connectError;
        GJLOG(GJ_LOGERROR, "RTMP_ConnectStream error");
        goto ERROR;
    } else {
        GJLOG(GJ_LOGDEBUG, "RTMP_Connect success");
        if (pull->messageCallback) {
            pull->messageCallback(pull, kStreamPullMessageType_connectSuccess, pull->messageCallbackParm, NULL);
        }
    }

    while (!pull->stopRequest) {
        RTMPPacket packet  = {0};
        GBool      rResult = GFalse;
        while ((rResult = RTMP_ReadPacket(pull->rtmp, &packet))) {
            GUInt8 *sps = NULL, *pps = NULL, *pp = NULL, *sei = NULL;
            GInt32  spsSize = 0, ppsSize = 0, ppSize = 0, seiSize = 0;
            if (!RTMPPacket_IsReady(&packet) || !packet.m_nBodySize) {
                continue;
            }

            RTMP_ClientPacket(pull->rtmp, &packet);

            if (packet.m_packetType == RTMP_PACKET_TYPE_AUDIO) {
                GJLOGFREQ("receive audio pts:%d", packet.m_nTimeStamp);
                pull->audioPullInfo.ts = packet.m_nTimeStamp;
                pull->audioPullInfo.count++;
                pull->audioPullInfo.byte += packet.m_nBodySize;
#if MENORY_CHECK
                R_GJPacket *aacPacket = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool, GMAX(7, packet.m_nBodySize));
                R_BufferWrite(&aacPacket->retain, (GUInt8 *) packet.m_body, packet.m_nBodySize);
                //                memcpy(aacPacket->retain.data, packet.m_body, packet.m_nBodySize);
                //                aacPacket->retain.size = packet.m_nBodySize;
                GJRetainBuffer *buffer = &aacPacket->retain;
                GUInt8 *        body   = (GUInt8 *) R_BufferStart(buffer);
                ;
                RTMPPacket_Free(&packet);
#else
                R_GJPacket *aacPacket = (R_GJPacket *) GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
                memset(aacPacket, 0, sizeof(R_GJPacket));
                GJRetainBuffer *buffer = &aacPacket->retain;
                GUInt8 *        body   = (GUInt8 *) packet.m_body;
                R_BufferPack(&buffer, body - RTMP_MAX_HEADER_SIZE, RTMP_MAX_HEADER_SIZE + packet.m_nBodySize, packetBufferRelease, NULL);
                buffer->size = RTMP_MAX_HEADER_SIZE + packet.m_nBodySize;
                R_BufferMoveDataToPoint(buffer, RTMP_MAX_HEADER_SIZE, GFalse);
                packet.m_body          = NULL;
#endif
                aacPacket->pts  = packet.m_nTimeStamp;
                aacPacket->type = GJMediaType_Audio;
                if (body[1] == GJ_flv_a_aac_package_type_aac_raw) {
                    aacPacket->dataOffset = 2;
                    aacPacket->dataSize   = (GInt32)(packet.m_nBodySize - 2);
                    aacPacket->flag       = 0;
                } else if (body[1] == GJ_flv_a_aac_package_type_aac_sequence_header) {
                    GUInt8  profile    = (body[2] & 0xF8) >> 3;
                    GUInt8  freqIdx    = ((body[2] & 0x07) << 1) | (body[3] >> 7);
                    GUInt8  chanCfg    = (body[3] >> 3) & 0x0f;
                    int     adtsLength = 7;
                    GUInt8 *adts       = R_BufferStart(&aacPacket->retain);
                    GInt32  fullLength = adtsLength + 0;
                    adts[0]            = (char) 0xFF;                                                     // 11111111  	= syncword
                    adts[1]            = (char) 0xF1;                                                     // 1111 0 00 1 = syncword+id(MPEG-4) + Layer + absent
                    adts[2]            = (char) (((profile - 1) << 6) + (freqIdx << 2) + (chanCfg >> 2)); // profile(2)+sampling(4)+privatebit(1)+channel_config(1)
                    adts[3]            = (char) (((chanCfg & 0x3) << 6) + (fullLength >> 11));
                    adts[4]            = (char) ((fullLength & 0x7FF) >> 3);
                    adts[5]            = (char) (((fullLength & 7) << 5) + 0x1F);
                    adts[6]            = (char) 0xFC;

                    aacPacket->dataOffset = 0;
                    aacPacket->dataSize   = adtsLength;
                    aacPacket->flag       = GJPacketFlag_KEY;

                } else {
                    GJLOG(GJ_LOGFORBID, "音频流格式错误");
                    R_BufferUnRetain(buffer);
                    break;
                }

                pthread_mutex_lock(&pull->mutex);
                if (!pull->releaseRequest) {
                    pull->dataCallback(pull, aacPacket, pull->dataCallbackParm);
                }
                pthread_mutex_unlock(&pull->mutex);
                R_BufferUnRetain(buffer);

            } else if (packet.m_packetType == RTMP_PACKET_TYPE_VIDEO) {
                GJLOGFREQ("receive video pts:%d", packet.m_nTimeStamp);
                //                GJLOG(GJ_LOGDEBUG,"receive video pts:%d",packet.m_nTimeStamp);

                GUInt8 *body  = (GUInt8 *) packet.m_body;
                GUInt8 *pbody = body;
                GInt32  isKey = 0;
                GInt32  index = 0;
                GInt32  ct    = 0;

                while (index < packet.m_nBodySize) {
                    if ((pbody[index] & 0x0F) == 0x07) {
                        index++;
                        if (pbody[index] == 0) { //sps pps
                            index += 10;
                            spsSize = pbody[index++] << 8;
                            spsSize += pbody[index++];
                            sps = pbody + index;
                            index += spsSize + 1;
                            ppsSize += pbody[index++] << 8;
                            ppsSize += pbody[index++];
                            pps = pbody + index;
                            index += ppsSize;
                            if (pbody + 4 > body + packet.m_nBodySize) {
                                GJLOG(GJ_LOGINFO, "only spspps\n");
                            }
                            R_GJPacket *h264Packet = (R_GJPacket *) GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
                            memset(h264Packet, 0, sizeof(R_GJPacket));
                            GJRetainBuffer *buffer = &h264Packet->retain;
                            R_BufferAlloc(&buffer, spsSize + ppsSize + 8, packetBufferRelease, GNULL);
                            h264Packet->dataOffset = 0;
                            h264Packet->dataSize   = 8 + spsSize + ppsSize;
                            GInt32  spsNsize       = htonl(spsSize);
                            GInt32  ppsNsize       = htonl(ppsSize);
                            GUInt8 *data           = R_BufferStart(buffer);
                            memcpy(data, &spsNsize, 4);
                            memcpy(data + 4, sps, spsSize);
                            memcpy(data + 4 + spsSize, &ppsNsize, 4);
                            memcpy(data + 8 + spsSize, pps, ppsSize);
                            h264Packet->type = GJMediaType_Video;
                            h264Packet->flag = GJPacketFlag_KEY;

                            pthread_mutex_lock(&pull->mutex);
                            if (!pull->releaseRequest) {
                                pull->dataCallback(pull, h264Packet, pull->dataCallbackParm);
                            }
                            pthread_mutex_unlock(&pull->mutex);
                            R_BufferUnRetain(buffer);

                        } else if (pbody[index] == 1) {
                            index++;
                            ct = pbody[index++] << 16;
                            ct |= pbody[index++] << 8;
                            ct |= pbody[index++];

                            while (index < packet.m_nBodySize) {
                                GInt8  type = pbody[index + 4] & 0x0F;
                                GInt32 size;
                                size = pbody[index] << 24;
                                size += pbody[index + 1] << 16;
                                size += pbody[index + 2] << 8;
                                size += pbody[index + 3];
                                if (type == 0x6) {
                                    seiSize = size + 4;
                                    sei     = body + index;
                                } else if (type == 0x5) {
                                    isKey  = GTrue;
                                    ppSize = size + 4;
                                    pp     = pbody + index;
                                } else if (type == 0x1) {
                                    isKey  = GFalse;
                                    ppSize = size + 4;
                                    pp     = pbody + index;
                                }
                                index += size + 4;
                            }

                        } else if (pbody[index] == 2) {
#if CLOSE_WHILE_STREAM_COMPLETE
                            GJLOG(GJ_LOGDEBUG, "直播结束\n");
                            RTMPPacket_Free(&packet);
                            errType = kStreamPullMessageType_closeComplete;
                            goto ERROR;
                            break;
#else
                            GJLOG(GJ_LOGDEBUG, "直播结束,继续等待开始\n");
                            RTMPPacket_Free(&packet);
                            break;

#endif
                        } else {
                            GJLOG(GJ_LOGFORBID, "h264格式有误\n");
                            RTMPPacket_Free(&packet);
                            goto ERROR;
                        }

                    } else {
                        GJLOG(GJ_LOGFORBID, "h264格式有误，type:%d\n", body[0]);
                        RTMPPacket_Free(&packet);
                        break;
                    }
                }

                if (!pp) {
                    RTMPPacket_Free(&packet);
                    continue;
                }
#if MENORY_CHECK
                R_GJPacket *h264Packet = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool, packet.m_nBodySize);
                R_BufferWrite(&h264Packet->retain, (GUInt8 *) packet.m_body, packet.m_nBodySize);
                //                memcpy(h264Packet->retain.data, packet.m_body, packet.m_nBodySize);
                GJRetainBuffer *buffer = &h264Packet->retain;
                //               buffer->size = packet.m_nBodySize;
                RTMPPacket_Free(&packet);
#else
                R_GJPacket *h264Packet = (R_GJPacket *) GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPacket));
                memset(h264Packet, 0, sizeof(R_GJPacket));
                GJRetainBuffer *buffer = &h264Packet->retain;
                R_BufferPack(&buffer, packet.m_body - RTMP_MAX_HEADER_SIZE, RTMP_MAX_HEADER_SIZE + packet.m_nBodySize, packetBufferRelease, NULL);
                buffer->size = packet.m_nBodySize;
                R_BufferMoveDataToPoint(buffer, RTMP_MAX_HEADER_SIZE, GFalse);
                packet.m_body = NULL;
#endif
                h264Packet->dts  = packet.m_nTimeStamp;
                h264Packet->pts  = h264Packet->dts + ct;
                h264Packet->type = GJMediaType_Video;
                if (sei) {
                    h264Packet->dataOffset = sei - (GUInt8 *) R_BufferStart(&h264Packet->retain);
                    if (pp) {
                        h264Packet->dataSize = seiSize + ppSize;
                    } else {
                        h264Packet->dataSize = seiSize;
                    }
                } else {
                    h264Packet->dataOffset = pp - (GUInt8 *) R_BufferStart(&h264Packet->retain);
                    h264Packet->dataSize   = ppSize;
                }

                pull->videoPullInfo.ts = packet.m_nTimeStamp;
                pull->videoPullInfo.count++;
                pull->videoPullInfo.byte += packet.m_nBodySize;
                GJAssert(h264Packet->dataOffset > 0 && h264Packet->dataOffset < R_BufferSize(&h264Packet->retain), "数据有误");

                pthread_mutex_lock(&pull->mutex);
                if (!pull->releaseRequest) {
                    pull->dataCallback(pull, h264Packet, pull->dataCallbackParm);
                }
                pthread_mutex_unlock(&pull->mutex);
                R_BufferUnRetain(buffer);

            } else {
                GJLOG(GJ_LOGWARNING, "not media Packet:%p type:%d", packet, packet.m_packetType);
                RTMPPacket_Free(&packet);
                break;
            }
            break;
        }
        //        if (packet.m_body) {
        //            RTMPPacket_Free(&packet);
        ////            GJAssert(0, "读取数据错误\n");
        //        }
        if (rResult == GFalse) {
            errType = kStreamPullMessageType_receivePacketError;
            GJLOG(GJ_LOGWARNING, "pull Read Packet Error");
            goto ERROR;
        }
    }
    
END:
    errType = kStreamPullMessageType_closeComplete;
ERROR:
    RTMP_Close(pull->rtmp);
    if (pull->messageCallback) {
        pull->messageCallback(pull, errType, pull->messageCallbackParm, errParm);
    }
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->pullThread = NULL;
    if (pull->releaseRequest == GTrue) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJStreamPull_Delloc(pull);
    }
    GJLOG(GJ_LOGDEBUG, "pullRunloop end");
    return NULL;
}
GBool GJStreamPull_Create(GJStreamPull **pullP, StreamPullMessageCallback callback, GHandle rtmpPullParm) {
    GJStreamPull *pull = NULL;
    if (*pullP == NULL) {
        pull = (GJStreamPull *) malloc(sizeof(GJStreamPull));
    } else {
        pull = *pullP;
    }
    memset(pull, 0, sizeof(GJStreamPull));
    pull->rtmp = RTMP_Alloc();
    RTMP_Init(pull->rtmp);
    RTMP_SetInterruptCB(pull->rtmp, interruptCB, pull);
    RTMP_SetTimeout(pull->rtmp, 8000);
    pull->messageCallback     = callback;
    pull->messageCallbackParm = rtmpPullParm;
    pull->stopRequest         = GFalse;

#if MENORY_CHECK
    GJRetainBufferPoolCreate(&pull->memoryCachePool, 1, GTrue, R_GJPacketMalloc, GNULL, GNULL);
#endif
    pthread_mutex_init(&pull->mutex, NULL);
    *pullP = pull;
    return GTrue;
}

GVoid GJStreamPull_Delloc(GJStreamPull *pull) {
    if (pull) {
#if MENORY_CHECK
        GJRetainBufferPoolClean(pull->memoryCachePool, GTrue);
        GJRetainBufferPoolFree(pull->memoryCachePool);
#endif
        RTMP_Free(pull->rtmp);
        free(pull);
        GJLOG(GJ_LOGDEBUG, "GJStreamPull_Delloc:%p", pull);
    } else {
        GJLOG(GJ_LOGWARNING, "GJStreamPull_Delloc NULL PULL");
    }
}
GVoid GJStreamPull_Close(GJStreamPull *pull) {
    GJLOG(GJ_LOGDEBUG, "GJStreamPull_Close:%p", pull);
    pull->stopRequest = GTrue;
}
GVoid GJStreamPull_Release(GJStreamPull *pull) {
    GJLOG(GJ_LOGDEBUG, "GJStreamPull_Release:%p", pull);
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->messageCallback = NULL;
    pull->releaseRequest  = GTrue;
    if (pull->pullThread == NULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJStreamPull_Delloc(pull);
    }
}
GVoid GJStreamPull_CloseAndRelease(GJStreamPull *pull) {
    GJStreamPull_Close(pull);
    GJStreamPull_Release(pull);
}

GBool GJStreamPull_StartConnect(GJStreamPull *pull, StreamPullDataCallback dataCallback, GHandle callbackParm, const GChar *pullUrl) {
    GJLOG(GJ_LOGDEBUG, "GJStreamPull_StartConnect:%p", pull);

    if (pull->pullThread != NULL) {
        GJStreamPull_Close(pull);
        pthread_join(pull->pullThread, NULL);
    }
    size_t length = strlen(pullUrl);
    GJAssert(length <= MAX_URL_LENGTH - 1, "sendURL 长度不能大于：%d", MAX_URL_LENGTH - 1);
    memcpy(pull->pullUrl, pullUrl, length + 1);
    pull->stopRequest      = GFalse;
    pull->dataCallback     = dataCallback;
    pull->dataCallbackParm = callbackParm;
    if (!RTMP_SetupURL(pull->rtmp, pull->pullUrl)) {
        GJLOG(GJ_LOGERROR, "RTMP_SetupURL error");
        return GFalse;
    }
    return pthread_create(&pull->pullThread, NULL, pullRunloop, pull) == 0;
}
GJTrafficUnit GJStreamPull_GetVideoPullInfo(GJStreamPull *pull) {
    return pull->videoPullInfo;
}
GJTrafficUnit GJStreamPull_GetAudioPullInfo(GJStreamPull *pull) {
    return pull->audioPullInfo;
}
