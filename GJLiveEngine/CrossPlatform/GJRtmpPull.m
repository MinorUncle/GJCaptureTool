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
#include "GJUtil.h"
#include "GJBridegContext.h"

#define BUFFER_CACHE_SIZE 40
#define RTMP_RECEIVE_TIMEOUT 10

struct _GJStreamPull {
    GJPipleNode pipleNode;
    RTMP *rtmp;
    char  pullUrl[MAX_URL_LENGTH];
#if MENORY_CHECK
    GJRetainBufferPool *memoryCachePool;
#endif
    pthread_t       pullThread;
    pthread_mutex_t mutex;

    GJTrafficUnit videoPullInfo;
    GJTrafficUnit audioPullInfo;

    MessageHandle messageCallback;
    StreamPullDataCallback    dataCallback;

    GHandle messageCallbackParm;
    GHandle dataCallbackParm;

    int stopRequest;
    int releaseRequest;
//#ifdef NETWORK_DELAY
//    GInt32 networkDelay;
//    GInt32 delayCount;
//#endif
};



GVoid GJStreamPull_Delloc(GJStreamPull *pull);

//static GBool packetBufferRelease(GJRetainBuffer *buffer) {
//    if (R_BufferUserData(buffer) == GNULL) {
//        //sps pps
//        R_BufferFreeData(buffer);
//    }
//    GJBufferPoolSetData(defauleBufferPool(), (GUInt8 *) buffer);
//    return GTrue;
//}
static GInt32 interruptCB(GVoid *opaque) {
    GJStreamPull *pull = (GJStreamPull *) opaque;
    return pull->stopRequest;
}
static GHandle pullRunloop(GHandle parm) {
    pthread_setname_np("Loop.GJStreamPull");
    GJStreamPull *         pull    = (GJStreamPull *) parm;
    kStreamPullMessageType errType = kStreamPullMessageType_connectError;
    GInt32                 ret;
    pull->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;

    ret = RTMP_Connect(pull->rtmp, NULL);
    if (!ret) {
        errType = kStreamPullMessageType_connectError;
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "RTMP_Connect error");
        goto ERROR;
    }
    ret = RTMP_ConnectStream(pull->rtmp, 0);
    if (!ret) {
        errType = kStreamPullMessageType_connectError;
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "RTMP_ConnectStream error");
        goto ERROR;
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "RTMP_Connect success");
        pthread_mutex_lock(&pull->mutex);
        if (pull->messageCallback) {
            defauleDeliveryMessage0(pull->messageCallback, pull, pull->messageCallbackParm, kStreamPullMessageType_connectSuccess);
//            pull->messageCallback(pull, kStreamPullMessageType_connectSuccess, pull->messageCallbackParm, NULL);
        }
        pthread_mutex_unlock(&pull->mutex);
    }

    while (!pull->stopRequest) {
        RTMPPacket packet  = {0};
        GBool      rResult = GFalse;
        while ((rResult = RTMP_ReadPacket(pull->rtmp, &packet))) {
            GUInt8 *sps = NULL, *pps = NULL;
            GInt32  spsSize = 0, ppsSize = 0, ppIndex = 0;
            if (!RTMPPacket_IsReady(&packet) || !packet.m_nBodySize) {
                continue;
            }

            RTMP_ClientPacket(pull->rtmp, &packet);

            if (packet.m_packetType == RTMP_PACKET_TYPE_AUDIO) {
                GJLOGFREQ("receive audio pts:%d", packet.m_nTimeStamp);
                pull->audioPullInfo.ts = GTimeMake(packet.m_nTimeStamp, 1000);
                pull->audioPullInfo.count++;
                pull->audioPullInfo.byte += packet.m_nBodySize;
                R_GJPacket *aacPacket = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool, GMAX(7, packet.m_nBodySize));
                //                memcpy(aacPacket->retain.data, packet.m_body, packet.m_nBodySize);
                //                aacPacket->retain.size = packet.m_nBodySize;
                GJRetainBuffer *buffer = &aacPacket->retain;
                GUInt8 *        body   = (GUInt8 *) packet.m_body;

                aacPacket->pts  = GTimeMake(packet.m_nTimeStamp, 1000);
                aacPacket->type = GJMediaType_Audio;
                if (body[1] == GJ_flv_a_aac_package_type_aac_raw) {
                    R_BufferWrite(&aacPacket->retain, (GUInt8 *) packet.m_body+2, packet.m_nBodySize-2);
                    aacPacket->dataSize = packet.m_nBodySize-2;
                    aacPacket->flag       = 0;
                } else if (body[1] == GJ_flv_a_aac_package_type_aac_sequence_header) {
                    ASC asc = {0};
                    GInt32 ascLen = 0;
                    if ((ascLen = readASC(body+2, 2, &asc)) > 0) {
                        aacPacket->flag = GJPacketFlag_KEY;
                        aacPacket->extendDataOffset = 0;
                        aacPacket->extendDataSize   = ascLen;
                        R_BufferWrite(buffer, body+2, ascLen);
                        aacPacket->dataOffset = aacPacket->dataSize = aacPacket->extendDataOffset = 0;
                        aacPacket->extendDataSize   = ascLen;
                        aacPacket->pts = GTimeMake(0, 1000);
                    }
                } else {
                    GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "音频流格式错误");
                    R_BufferUnRetain(buffer);
                    RTMPPacket_Free(&packet);
                    break;
                }
                RTMPPacket_Free(&packet);
                pthread_mutex_lock(&pull->mutex);
                if (!pull->releaseRequest) {
                    pull->dataCallback(pull, aacPacket, pull->dataCallbackParm);
                }
                pthread_mutex_unlock(&pull->mutex);

                pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&aacPacket->retain,GJMediaType_Audio);
                R_BufferUnRetain(buffer);

            } else if (packet.m_packetType == RTMP_PACKET_TYPE_VIDEO) {
                GJLOGFREQ("receive video pts:%d", packet.m_nTimeStamp);
                //                GJLOG(DEFAULT_LOG, GJ_LOGDEBUG,"receive video pts:%d",packet.m_nTimeStamp);

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
                                GJLOG(DEFAULT_LOG, GJ_LOGINFO, "only spspps\n");
                            }
                            R_GJPacket *h264Packet = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool,spsSize + ppsSize + 8);
                            GJRetainBuffer *buffer = &h264Packet->retain;
                            h264Packet->extendDataOffset = 0;
                            h264Packet->extendDataSize   = 8 + spsSize + ppsSize;
                            GInt32  spsNsize       = htonl(spsSize);
                            GInt32  ppsNsize       = htonl(ppsSize);
                            R_BufferWrite(buffer, (GUInt8*)&spsNsize, 4);
                            R_BufferWrite(buffer, sps, spsSize);
                            R_BufferWrite(buffer, (GUInt8*)&ppsNsize, 4);
                            R_BufferWrite(buffer, pps, ppsSize);
                            h264Packet->flag = GJPacketFlag_KEY;
                            h264Packet->type = GJMediaType_Video;
                            pthread_mutex_lock(&pull->mutex);
                            if (!pull->releaseRequest) {
                                pull->dataCallback(pull, h264Packet, pull->dataCallbackParm);
                            }
                            pthread_mutex_unlock(&pull->mutex);
                            pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&h264Packet->retain,GJMediaType_Video);

                            R_BufferUnRetain(buffer);
                        } else if (pbody[index] == 1) {
                            index++;
                            ct = pbody[index++] << 16;
                            ct |= pbody[index++] << 8;
                            ct |= pbody[index++];
                            ppIndex = index;
                            while (index < packet.m_nBodySize) {
                                GInt8  type = pbody[index + 4] & 0x0F;
                                GInt32 size;
                                size = pbody[index] << 24;
                                size += pbody[index + 1] << 16;
                                size += pbody[index + 2] << 8;
                                size += pbody[index + 3];
                                if (type == 0x5) {
                                    isKey  = GTrue;
                                } else if (type == 0x1) {
                                    isKey  = GFalse;
                                }
                                index += size + 4;
                            }

                        } else if (pbody[index] == 2) {
#if CLOSE_WHILE_STREAM_COMPLETE
                            GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "直播结束\n");
                            RTMPPacket_Free(&packet);
                            errType = kStreamPullMessageType_closeComplete;
                            goto ERROR;
                            break;
#else
                            GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "直播结束,继续等待开始\n");
                            RTMPPacket_Free(&packet);
                            break;

#endif
                        } else {
                            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "h264格式有误\n");
                            RTMPPacket_Free(&packet);
                            goto ERROR;
                        }

                    } else {
                        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "h264格式有误，type:%d\n", body[0]);
                        RTMPPacket_Free(&packet);
                        goto ERROR;
                        break;
                    }
                }

                if (ppIndex>0) {
                    R_GJPacket *h264Packet = (R_GJPacket *) GJRetainBufferPoolGetSizeData(pull->memoryCachePool, packet.m_nBodySize);
                    R_BufferWrite(&h264Packet->retain, (GUInt8 *) packet.m_body+ppIndex, packet.m_nBodySize - ppIndex);
                    GJRetainBuffer *buffer = &h264Packet->retain;
                    
                    h264Packet->dts  = GTimeMake(packet.m_nTimeStamp, 1000);
                    h264Packet->pts  = GTimeMake(packet.m_nTimeStamp + ct, 1000);
                    h264Packet->type = GJMediaType_Video;
                    h264Packet->flag = isKey;
                    h264Packet->dataSize = R_BufferSize(&h264Packet->retain);
                    
                    pull->videoPullInfo.ts = GTimeMake(packet.m_nTimeStamp, 1000);
                    pull->videoPullInfo.count++;
                    pull->videoPullInfo.byte += packet.m_nBodySize;
                    GJAssert(h264Packet->dataOffset >= 0 && h264Packet->dataOffset < R_BufferSize(&h264Packet->retain), "数据有误");
                    
                    pthread_mutex_lock(&pull->mutex);
                    if (!pull->releaseRequest) {
                        pull->dataCallback(pull, h264Packet, pull->dataCallbackParm);
                    }
                    
                    pthread_mutex_unlock(&pull->mutex);
                    pipleNodeFlowFunc(&pull->pipleNode)(&pull->pipleNode,&h264Packet->retain,GJMediaType_Video);
                    
                    R_BufferUnRetain(buffer);
                }
               

            } else {
                GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "not media Packet:%p type:%d", &packet, packet.m_packetType);
            }
            RTMPPacket_Free(&packet);
        }
        //        if (packet.m_body) {
        //            RTMPPacket_Free(&packet);
        ////            GJAssert(0, "读取数据错误\n");
        //        }
        if (rResult == GFalse) {
            errType = kStreamPullMessageType_receivePacketError;
            GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "pull Read Packet Error");
            goto ERROR;
        }
    }
    
END:
    errType = kStreamPullMessageType_closeComplete;
ERROR:
    RTMP_Close(pull->rtmp);

    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    if (pull->messageCallback) {
        defauleDeliveryMessage0(pull->messageCallback, pull, pull->messageCallbackParm, errType);
        //        pull->messageCallback(pull, errType, pull->messageCallbackParm, errParm);
    }
    pull->pullThread = NULL;
    if (pull->releaseRequest == GTrue) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJStreamPull_Delloc(pull);
    }
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "pullRunloop end");
    return NULL;
}
GBool GJStreamPull_Create(GJStreamPull **pullP, MessageHandle callback, GHandle rtmpPullParm) {
    GJStreamPull *pull = NULL;
    if (*pullP == NULL) {
        pull = (GJStreamPull *) malloc(sizeof(GJStreamPull));
    } else {
        pull = *pullP;
    }
    memset(pull, 0, sizeof(GJStreamPull));
    pipleNodeInit(&pull->pipleNode, GNULL);
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
        pipleNodeUnInit(&pull->pipleNode);
        free(pull);
        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPull_Delloc:%p", pull);
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "GJStreamPull_Delloc NULL PULL");
    }
}
GVoid GJStreamPull_Close(GJStreamPull *pull) {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPull_Close:%p", pull);
    pull->stopRequest = GTrue;
}
GVoid GJStreamPull_Release(GJStreamPull *pull) {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPull_Release:%p", pull);
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
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJStreamPull_StartConnect:%p", pull);

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
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "RTMP_SetupURL error");
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
//#ifdef NETWORK_DELAY
//GInt32 GJStreamPull_GetNetWorkDelay(GJStreamPull *pull){
//    GInt32 delay = 0;
//    if (pull->delayCount > 0) {
//        delay = pull->networkDelay/pull->delayCount;
//    }
//    pull->delayCount = 0;
//    pull->networkDelay = 0;
//    return delay;
//}
//#endif

