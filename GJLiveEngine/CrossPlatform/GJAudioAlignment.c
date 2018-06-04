//
//  GJAudioAlignment.c
//  GJLiveEngine
//
//  Created by melot on 2018/6/4.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#include "GJAudioAlignment.h"
#include "TPCircularBuffer/TPCircularBuffer.h"
#include "GMemCheck.h"
struct _GJAudioAlignmentContext {
    GInt32 sizePerFrame;
    GInt32 sizePerPacket;
    GInt32 sizePerMs;
    GInt32 samplerate;

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
    context->sizePerMs               = context->sizePerFrame * format->mSampleRate / 1000;
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
}

GInt32 audioAlignmentUpdate(GJAudioAlignmentContext *context, GVoid *data, GInt size, GTime *pts) {

    GInt32 retSize = 0;
    if (context->startPts < 0) {
        if (!G_TIME_IS_INVALID(*pts)) {
            context->startPts = GTimeMSValue(*pts);
            context->lastPts  = context->startPts;
            context->alignmentSize += size;
        }
    } else {

        GInt32 tailSize = 0;
        GVoid *tail     = TPCircularBufferTail(&context->ringBuffer, &tailSize);
        if (G_TIME_IS_INVALID(*pts)) {

            GJAssert(tailSize >= size, "大小有问题");
            GInt32 ringSize = GMIN(size, tailSize);
            memcpy(data, tail, ringSize);
            TPCircularBufferConsume(&context->ringBuffer, ringSize);
            size    = ringSize;
            retSize = tailSize - size;
        } else {
            GLong msPts = GTimeMSValue(*pts);
            if (msPts < context->lastPts) {
                context->startPts      = msPts;
                context->alignmentSize = 0;
                TPCircularBufferClear(&context->ringBuffer);
            }

            context->lastPts = msPts;
            GLong totalPts   = (context->alignmentSize + tailSize) / context->sizePerMs + context->startPts;
            GLong delPts     = msPts - totalPts;

            if (delPts > 100 || tailSize > 0 ) { //有缓存，或者需要补充数据，都需要保存新的数据
                printf("audioalignment delpts:%ld tailSize:%d inputsize；%d\n",delPts,tailSize,size);
                GInt32  availableBytes = 0;
                GUInt8 *head           = TPCircularBufferHead(&context->ringBuffer, &availableBytes);
                GInt32 appendSize = 0;
                if (delPts > 0) { //补充空数据
                    appendSize = (GInt32)((delPts * context->sizePerMs));
                    if (appendSize > availableBytes - size) { appendSize = availableBytes - size; }
                    appendSize = appendSize & ~context->sizePerFrame;
                    memset(head, 0, appendSize);
                    head += appendSize;
                    printf("audioalignment fillEmptySize:%d\n",appendSize);
                }
                memcpy(head, data, size);
                TPCircularBufferProduce(&context->ringBuffer, size + appendSize);
                tailSize += size + appendSize;
                if (tail == GNULL) {//如果不为null则可以直接用否则重新获取
                    tail     = TPCircularBufferTail(&context->ringBuffer, &tailSize);
                }
                memcpy(data, tail, size);
                TPCircularBufferConsume(&context->ringBuffer, size);
                retSize = tailSize - size;
            }else if (delPts < 0){
                
            }
        }

        pts->value = context->alignmentSize / context->sizePerMs + context->startPts;
        pts->scale = 1000;
        context->alignmentSize += size;
    }
    return retSize;
}
