//
//  GJAudioAlignment.c
//  GJLiveEngine
//
//  Created by melot on 2017/9/4.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJAudioAlignment.h"
#include "TPCircularBuffer/TPCircularBuffer.h"
#include "GMemCheck.h"
#include "GJLog.h"
struct _GJAudioAlignmentContext {
    GInt32 sizePerFrame;
    GInt32 sizePerPacket;
    GInt32 samplerate;
    GDouble sizePerMs;//如果时间不是从0开始，则一定要双精度

    GInt32     alignmentSize;
    GTimeValue lastPts;
    GTimeValue startPts;

    TPCircularBuffer ringBuffer;
};

void audioAlignmentAlloc(GJAudioAlignmentContext **pContext, const GJAudioFormat *format) {
    if (pContext == nil) {
        return;
    }
    GJAudioAlignmentContext *context = (GJAudioAlignmentContext *) malloc(sizeof(GJAudioAlignmentContext));
    context->startPts                = -1;
    context->lastPts                 = GINT32_MAX;
    context->alignmentSize = 0;

    context->samplerate              = format->mSampleRate;
    context->sizePerFrame            = format->mBitsPerChannel * format->mChannelsPerFrame/8;
    context->sizePerPacket           = context->sizePerFrame * format->mFramePerPacket;
    context->sizePerMs               = context->sizePerFrame * format->mSampleRate / 1000.0;
    if (TPCircularBufferInit(&context->ringBuffer, context->sizePerPacket)) {
        TPCircularBufferSetAtomic(&context->ringBuffer, GFalse);
        *pContext = context;
    };
}

void audioAlignmentDelloc(GJAudioAlignmentContext **pContext) {
    if (pContext == GNULL || *pContext == GNULL) {
        return;
    }
    GJAudioAlignmentContext *context = *pContext;
    TPCircularBufferCleanup(&context->ringBuffer);
    free(context);
    *pContext = GNULL;
}

GInt32 audioAlignmentUpdate(GJAudioAlignmentContext *context, GUInt8 *inData, GInt size, GTime *inoutPts,GUInt8* outData){

#ifdef DEBUG
    GJAssert(size == GALIGN(size, context->sizePerFrame), "size必须sizePerFrame字节对齐");
#endif
    
    GInt32 retValue = -1;
    GBool didOut = GFalse;
    if (context->startPts < 0 && size > 0) {
        if (!G_TIME_IS_INVALID(*inoutPts)) {
            context->startPts = GTimeMSValue(*inoutPts);
        }else{
            return -1;
        }
    }
    
    GInt32 tailSize = 0;
    GUInt8 *tail     = TPCircularBufferTail(&context->ringBuffer, &tailSize);
    
    GInt32 headSize = 0;
    GUInt8 *head     = TPCircularBufferHead(&context->ringBuffer, &headSize);
    
    if (tail == GNULL) {
        tail = head;
    }
    if (head == GNULL) {
        head = tail;
    }
    
    if(size > 0){
        if (G_TIME_IS_INVALID(*inoutPts)) {//pts无效则直接添加在后面
            GInt32 addSize = GMIN(headSize, size);
            memcpy(head, inData, addSize);
            TPCircularBufferProduce(&context->ringBuffer, addSize);
            tailSize += addSize;
            GJAssert(0, "无效pts");
        } else {
            GLong msPts = GTimeMSValue(*inoutPts);
            if (msPts < context->lastPts) {//重启pts
                context->startPts      = msPts;
                context->alignmentSize = 0;
                TPCircularBufferClear(&context->ringBuffer);
                head     = TPCircularBufferHead(&context->ringBuffer, &headSize);
                tail = head;//清除后tail等于head;
            }

            GLong totalPts   = (context->alignmentSize + tailSize) / context->sizePerMs + context->startPts;
            GLong delPts     = msPts - totalPts;
//            printf("audioalignment  input Pts:%ld totalPts:%ld delPts:%ld ,dPts:%lld inputSize:%d tailSize:%d,audioAlignment:%d\n",msPts, totalPts,delPts,msPts - context->lastPts,size,tailSize,context->alignmentSize);
            context->lastPts = msPts;

            if (delPts > 100) { //需要补充数据,则需要放入缓存区
                GInt32  appendSize = (GInt32)((delPts * context->sizePerMs));
                if (appendSize > headSize - size) { appendSize = headSize - size; }
                appendSize = GALIGN(appendSize, context->sizePerFrame);
                memset(head, 0, appendSize);
                head += appendSize;
                GJLOG(GNULL, GJ_LOGDEBUG, "audioalignment  dpts:%ld ,音频数据不足，补充空数据 fillEmptySize:%d\n",delPts, appendSize);
                
                memcpy(head, inData, size);
                
                GInt32 produceSize = appendSize + size;
                TPCircularBufferProduce(&context->ringBuffer, produceSize);
                tailSize += produceSize;
            }else if (delPts < -100){//需要丢弃数据,则需要放入缓存区
                GInt32 dropSize = -(GInt32)((delPts * context->sizePerMs));
                if (dropSize > tailSize + size) { dropSize = tailSize + size;}
                dropSize = GALIGN(dropSize, context->sizePerFrame);

                if (dropSize < tailSize) {
                    GJLOG(GNULL, GJ_LOGDEBUG, "audioalignment  dpts:%ld, 音频采集数据太快，丢数据 dropSize:%d\n",delPts,dropSize);
                    TPCircularBufferConsume(&context->ringBuffer, dropSize);
                    tail += dropSize;
                    tailSize -= dropSize;
                }else{
#ifdef DEBUG
                    GJAssert(tailSize == GALIGN(tailSize, context->sizePerFrame), "逻辑有误，tailSize一定是sizePerFrame字节对齐");
#endif
                   GJLOG(GNULL, GJ_LOGDEBUG, "audioalignment dpts:%ld 音频采集数据太快，丢数据 tailSize:%d,input size:%d\n",delPts,tailSize,dropSize-tailSize);
                    TPCircularBufferConsume(&context->ringBuffer, tailSize);
                    tail += tailSize;
                    GInt32 leftDropSize = dropSize - tailSize;
                    headSize += tailSize;
                    tailSize = 0;
#ifdef DEBUG
                    TPCircularBufferTail(&context->ringBuffer, &tailSize);
                    GJAssert(tailSize == 0, "逻辑有误");
#endif
                    GInt32 leftAddSize =  size - leftDropSize;
                    leftAddSize = GMIN(leftAddSize, headSize);//防止溢出。因为是环形的，所以正常情况下不会溢出，只会覆盖老数据
                    memcpy(head, inData + leftDropSize,leftAddSize);
                    TPCircularBufferProduce(&context->ringBuffer,leftAddSize);
                    tailSize += leftAddSize;
                }
            }else if(tailSize > 0 || size < context->sizePerPacket){//缓存区有数据，或者新加的数据不足够,则直接放入缓冲区
                memcpy(head, inData,size);
                TPCircularBufferProduce(&context->ringBuffer,size);
                tailSize += size;
//                GJLOG(GNULL, GJ_LOGDEBUG, "audioalignment add dataSize:%d tailSize:%d\n",size,tailSize);
            }else{//否则最优情况，可以不用复制到缓冲区，直接输出
                didOut = GTrue;
                GInt32 leftAddSize =  size;
                if(outData){
                    memcpy(outData, inData ,context->sizePerPacket);
                    leftAddSize -= context->sizePerPacket;
                    context->alignmentSize += context->sizePerPacket;
                    inoutPts->value = context->alignmentSize / context->sizePerMs + context->startPts;
                    inoutPts->scale = 1000;
                    retValue = 0;
//                    GJLOG(GNULL, GJ_LOGDEBUG,"audioalignment read dataSize:%d, leftsize:%d",context->sizePerPacket,leftAddSize);
                }
                leftAddSize = GALIGN(leftAddSize, context->sizePerFrame);
                if (leftAddSize > 0) {
                    memcpy(head,inData + (size - leftAddSize),leftAddSize);
                    TPCircularBufferProduce(&context->ringBuffer,leftAddSize);
//                    GJLOG(GNULL, GJ_LOGDEBUG, "audioalignment add1 dataSize:%d tailSize:%d\n",size,tailSize);
                    if (leftAddSize > context->sizePerPacket) {
                        retValue = 1;
                    }
                }
            }
        }
    }
    
    if (!didOut && tailSize >= context->sizePerPacket) {
        if (outData) {
            memcpy(outData, tail, context->sizePerPacket);
            TPCircularBufferConsume(&context->ringBuffer, context->sizePerPacket);
            context->alignmentSize += context->sizePerPacket;
            inoutPts->value = context->alignmentSize / context->sizePerMs + context->startPts;
            inoutPts->scale = 1000;
            tailSize -= context->sizePerPacket;
            retValue = 0;
//            GJLOG(GNULL, GJ_LOGDEBUG,"audioalignment read1 dataSize:%d, leftSize:%d",context->sizePerPacket,tailSize);
        }
        if (tailSize >= context->sizePerPacket) {
            retValue = 1;
        }
    }
      
    return retValue;
}
