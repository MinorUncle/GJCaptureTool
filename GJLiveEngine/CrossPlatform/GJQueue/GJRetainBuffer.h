//
//  GJRetainBuffer.h
//  GJQueue
//
//  Created by mac on 17/2/22.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJRetainBuffer_h
#define GJRetainBuffer_h
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "GJLog.h"

#include "GJPlatformHeader.h"
#if MEMORY_CHECK
#include "GJListQueue.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif


typedef GBool (*RetainReleaseCallBack)(struct _GJRetainBuffer *data);

struct _GJRetainBuffer {
    GInt32  capacity;  //data之后的实际内存大小
    GInt32  size;      //data之后的实际使用内存大小，剩下之后的一定没有使用
    GInt32  frontSize; //data之前的内存,所以外部释放时一定要注意free((char*)data-frontSize);
    GInt32  retainCount;
    GUInt8 *data;
#if MEMORY_CHECK
    GBool   needCheck;
    GJListQueue *retainList;   //retain调用的函数名
    GJListQueue *unretainList; //unretain调用的函数名
#endif
    RetainReleaseCallBack retainReleaseCallBack;
    GVoid *               parm;
};
typedef struct _GJRetainBuffer GJRetainBuffer;

#if MEMORY_CHECK
GVoid R_BufferMemCheck(GJRetainBuffer *buffer);
#endif

#if 1
static inline GUInt8 *R_BufferOrigin(GJRetainBuffer *buffer) {
#if MEMORY_CHECK
    return buffer->data - buffer->frontSize;
#else
    return buffer->data - buffer->frontSize;
#endif
}

static inline GUInt8 *_R_BufferStart(GJRetainBuffer *buffer) {
    return buffer->data;
}
#define R_BufferStart(buffer) _R_BufferStart((GJRetainBuffer *) (buffer))

static inline GUInt8 *R_BufferCurrent(GJRetainBuffer *buffer) {
    return buffer->data + buffer->size;
}

static inline GUInt8 *R_BufferEnd(GJRetainBuffer *buffer) {
    return buffer->data + buffer->capacity;
}

static inline GVoid _R_BufferUseSize(GJRetainBuffer *buffer, GInt32 size) {
    buffer->size += size;
    GJAssert((buffer->size <= buffer->capacity), "MEM ERROR");
}
#define R_BufferUseSize(buffer, size) _R_BufferUseSize((GJRetainBuffer *) (buffer), size)
    
static inline GInt32 _R_BufferSize(GJRetainBuffer *buffer) {
    return buffer->size;
}
#define R_BufferSize(buffer) _R_BufferSize((GJRetainBuffer *) (buffer))

static inline GInt32 R_BufferFrontSize(GJRetainBuffer *buffer) {
    return buffer->frontSize;
}

static inline GInt32 R_BufferCapacity(GJRetainBuffer *buffer) {
    return buffer->capacity;
}

static inline GInt32 R_BufferRetainCount(GJRetainBuffer *buffer) {
    return buffer->retainCount;
}

static inline GHandle R_BufferUserData(GJRetainBuffer *buffer) {
    return buffer->parm;
}

static inline GVoid R_BufferSetCallback(GJRetainBuffer *buffer, RetainReleaseCallBack callback) {
    buffer->retainReleaseCallBack = callback;
}
//    将内存制成某个常量
static inline GVoid R_BufferWriteConst(GJRetainBuffer *buffer, GInt data, GInt32 size) {
    GJAssert(buffer->size + size <= buffer->capacity, "MEM ERROR");
    memset(buffer->data + buffer->size, data, size);
    buffer->size += size;
}

static inline GVoid _R_BufferWrite(GJRetainBuffer *buffer, GUInt8 *data, GInt32 size) {
    GJAssert(buffer->size + size <= buffer->capacity, "MEM ERROR");
    memcpy(buffer->data + buffer->size, data, size);
    buffer->size += size;
}

#define R_BufferWrite(buffer, data, size) _R_BufferWrite((GJRetainBuffer *) buffer, (GUInt8 *) data, size);
//    static inline GVoid  R_BufferRead(GJRetainBuffer* buffer,GUInt8* data,GInt32 size){
//        GJAssert(buffer->size >= size, "MEM ERROR");
//        memcpy(data, buffer->data+buffer->size-size, size);
//        buffer->size -= size;
//    }

static inline GVoid R_BufferClearFront(GJRetainBuffer *buffer) {
    if (buffer->frontSize > 0) {
        buffer->data      = buffer->data - buffer->frontSize;
        buffer->capacity  = buffer->capacity + buffer->frontSize;
        buffer->frontSize = 0;
    }
    buffer->size = 0;
}
static inline GVoid R_BufferClearSize(GJRetainBuffer *buffer) {
    buffer->size = 0;
}

/**
 起死回生，区别与_R_BufferRetain，明确知道retainCount==0，需要重新复活+1；

 @param x x description
 @return return value description
 */
#define R_BufferRelive(x) _R_BufferRelive(x, __func__)
static inline GVoid _R_BufferRelive(GJRetainBuffer *buffer, const GChar *tracker DEFAULT_PARAM(GNull)) {
    __sync_fetch_and_add(&buffer->retainCount, 1);
#if MEMORY_CHECK
    GJAssert(buffer->retainCount == 1, "");

    if (buffer->retainList == GNULL) {
        listCreate(&buffer->retainList, GTrue);
        listCreate(&buffer->unretainList, GTrue);
    }
    listPush(buffer->retainList, (GHandle) tracker);
#endif
}
/**
     引用计数加1
 
     @param buffer buffer description
     */
//    GVoid _R_BufferRetain(GJRetainBuffer* buffer, const GChar* tracker DEFAULT_PARAM(GNull));
#define R_BufferRetain(x) _R_BufferRetain((GJRetainBuffer *) (x), __func__)

static inline GVoid _R_BufferRetain(GJRetainBuffer *buffer, const GChar *tracker DEFAULT_PARAM(GNull)) {

    __sync_fetch_and_add(&buffer->retainCount, 1);
#if MEMORY_CHECK
    GJAssert(buffer->retainCount > 1, "0及以下的retaincount不能retain");
    if (buffer->retainList == GNULL) {
        listCreate(&buffer->retainList, GTrue);
        listCreate(&buffer->unretainList, GTrue);
    }
    listPush(buffer->retainList, (GHandle) tracker);
#endif
}
#else
GUInt8 *R_BufferOrigin(GJRetainBuffer *buffer);

GUInt8 *R_BufferStart(GJRetainBuffer *buffer);

GUInt8 *R_BufferCurrent(GJRetainBuffer *buffer);

GUInt8 *R_BufferEnd(GJRetainBuffer *buffer);

GVoid R_BufferSetSize(GJRetainBuffer *buffer, GInt32 size);

GInt32 R_BufferSize(GJRetainBuffer *buffer);

GInt32 R_BufferFrontSize(GJRetainBuffer *buffer);

GInt32 R_BufferCapacity(GJRetainBuffer *buffer);

GInt32 R_BufferRetainCount(GJRetainBuffer *buffer);

GHandle R_BufferUserData(GJRetainBuffer *buffer);

GVoid R_BufferSetCallback(GJRetainBuffer *buffer, RetainReleaseCallBack callback);

GVoid R_BufferWrite(GJRetainBuffer *buffer, GUInt8 *data, GInt32 size);

GVoid R_BufferWriteAppend(GJRetainBuffer *buffer, GUInt8 *data, GInt32 size);

GVoid R_BufferEraseOut(GJRetainBuffer *buffer, GUInt8 *data, GInt32 size);

GVoid R_BufferClearFront(GJRetainBuffer *buffer);

GVoid R_BufferRetain(GJRetainBuffer *buffer);

#endif

/**
 为GJRetainBuffer申请data内存，需要时也创建一个GJRetainBuffer；
 MEMORY_CHECK打开时负责内存校验
 data不能直接free，需要请用retainBufferFreeData；，包括releaseCallBack中

 @param R_Buffer 指针地址，当* R_Buffer为空时自动创建，
 @param size size description
 @param releaseCallBack releaseCallBack不为空时，在 retainCount为0时调用，并且在releaseCallBack中释放data内存。
                        返回值表示releaseCallBack中是否已经释放GJRetainBuffer,当releaseCallBack为空时，GJRetainBuffer和data都在retainCount为0时自动释放。
 */
GVoid R_BufferAlloc(GJRetainBuffer **R_Buffer, GInt32 size, GBool (*releaseCallBack)(GJRetainBuffer *data), GVoid *parm);

/**
 打包已经存在的内存块.注意该模块不参与内存校验

 @param R_Buffer R_Buffer description
 @param data data description
 @param size size description
 @param releaseCallBack releaseCallBack description
 */

GVoid R_BufferPack(GJRetainBuffer **R_Buffer, GVoid *data, GInt32 size, GBool (*releaseCallBack)(GJRetainBuffer *data), GVoid *parm);

/**
 不考虑releaseCallback,直接释放data内存，但是不释放buffer内存；

 @param buffer buffer description
 */
GVoid R_BufferFreeData(GJRetainBuffer *buffer);

/**
 需要扩大内存，一定要用此接口。只影响capacity，不保证内容不变。frontSize、size保持不变。
 
 @param retainbuffer retainbuffer description
 @param size 指capacity扩大到多少，不改变frontSize，所以总内存大小为frontSize+capacity。只扩大，缩小则没有影响；
 */
GVoid R_BufferReCapacity(GJRetainBuffer *retainbuffer, GInt32 size);

/**
 引用计数减1

 @param buffer buffer description
 */
GVoid _R_BufferUnRetain(GJRetainBuffer *buffer, const GChar *tracker DEFAULT_PARAM(GNull));
#define R_BufferUnRetain(x) _R_BufferUnRetain((GJRetainBuffer *) (x), __func__)

GVoid R_BufferUnRetainUnTrack(GHandle buffer);

/**
 移动data指针，不做内存的修改，但是会涉及到front等的修改
 
 @param buffer buffer description
 @param offset 偏移的大小，不能移到内存外，否则GFalse
 @param keepData 是否保持data到size之内的内存
 @return 是否成功
 */
GBool R_BufferMoveDataPoint(GJRetainBuffer* buffer,GInt32 offset,GBool keepData);

/**
 类似retainBufferMoveDataPoint，只是移到开始的位置，而不是偏移

 @param buffer buffer description
 @param frontSize 只能大于0
 @param keepData 是否保持data到size之内的内存，false不会产生realloc操作
 @return 是否成功
 */
GBool R_BufferMoveDataToPoint(GJRetainBuffer* buffer,GUInt32 frontSize,GBool keepData);
    
    
GInt32  R_BufferStructSize(void);

#ifdef __cplusplus
}
#endif

#endif /* GJRetainBuffer_h */
