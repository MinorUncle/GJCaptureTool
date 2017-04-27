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

#ifndef bool
#   define bool unsigned int
#   define true 1
#   define false 0
#endif

#ifdef __cplusplus
extern "C" {
#endif
    
typedef struct _GJRetainBuffer{
    int capacity; //data之后的实际内存大小
    int size;      //data之后的实际使用内存大小，剩下之后的一定没有使用
    int frontSize; //data之前的内存,所以外部释放时一定要注意free((char*)data-frontSize);
    int retainCount;
    uint8_t* data;
    bool (*retainReleaseCallBack)(struct _GJRetainBuffer* data);
    void *parm;
}GJRetainBuffer;


/**
 为GJRetainBuffer申请data内存，需要时也创建一个GJRetainBuffer；

 @param retainBuffer 指针地址，当* retainBuffer为空时自动创建，
 @param size size description
 @param releaseCallBack releaseCallBack不为空时，在 retainCount为0时调用，并且在releaseCallBack中释放data内存。
        返回值表示releaseCallBack中是否已经释放GJRetainBuffer,当releaseCallBack为空时，GJRetainBuffer和data都在retainCount为0时自动释放。
        外部free请使用        free((char*)buffer->data - buffer->frontSize);

 */
void retainBufferAlloc(GJRetainBuffer** retainBuffer,int size,bool (*releaseCallBack)(GJRetainBuffer* data),void* parm );
void retainBufferPack(GJRetainBuffer** retainBuffer,void* data, int size,bool (*releaseCallBack)(GJRetainBuffer* data),void* parm);

void retainBufferRetain(GJRetainBuffer* buffer);
void retainBufferUnRetain(GJRetainBuffer* buffer);
void retainBufferFree(GJRetainBuffer* buffer);
    
/**
 设置前置内存大小，如果小于原来的，则会丢失原来的前置内存数据

 @param buffer buffer description
 @param frontSize 需要设置的大小。会尽量保持原来的数据，如果capacity大于size,则可能只产生移动
 */
void retainBufferSetFrontSize(GJRetainBuffer* buffer,int frontSize);

    
/**
 移动data指针，不做内存的修改，但是会涉及到front等的修改
 
 @param buffer buffer description
 @param offset 偏移的大小，不能移到内存外，否则false
 @return 是否成功
 */
bool retainBufferMoveDataPoint(GJRetainBuffer* buffer,int offset);
#ifdef __cplusplus
}
#endif

#endif /* GJRetainBuffer_h */
