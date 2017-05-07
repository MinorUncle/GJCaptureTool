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
#include "GJPlatformHeader.h"


#ifdef __cplusplus
extern "C" {
#endif
    
    typedef struct _GJRetainBuffer{
        GInt32 capacity; //data之后的实际内存大小
        GInt32 size;      //data之后的实际使用内存大小，剩下之后的一定没有使用
        GInt32 frontSize; //data之前的内存,所以外部释放时一定要注意free((char*)data-frontSize);
        GInt32 retainCount;
        GUInt8* data;
        GBool (*retainReleaseCallBack)(struct _GJRetainBuffer* data);
        GVoid *parm;
    }GJRetainBuffer;
    
    
    /**
     为GJRetainBuffer申请data内存，需要时也创建一个GJRetainBuffer；
     
     @param retainBuffer 指针地址，当* retainBuffer为空时自动创建，
     @param size size description
     @param releaseCallBack releaseCallBack不为空时，在 retainCount为0时调用，并且在releaseCallBack中释放data内存。
     返回值表示releaseCallBack中是否已经释放GJRetainBuffer,当releaseCallBack为空时，GJRetainBuffer和data都在retainCount为0时自动释放。
     外部free请使用        free((char*)buffer->data - buffer->frontSize);
     
     */
    GVoid retainBufferAlloc(GJRetainBuffer** retainBuffer,GInt32 size,GBool (*releaseCallBack)(GJRetainBuffer* data),GVoid* parm );
    GVoid retainBufferPack(GJRetainBuffer** retainBuffer,GVoid* data, GInt32 size,GBool (*releaseCallBack)(GJRetainBuffer* data),GVoid* parm);
    
    GVoid retainBufferRetain(GJRetainBuffer* buffer);
    GVoid retainBufferUnRetain(GJRetainBuffer* buffer);
    GVoid retainBufferFree(GJRetainBuffer* buffer);
    
    
    /**
     移动data指针，不做内存的修改，但是会涉及到front等的修改
     
     @param buffer buffer description
     @param offset 偏移的大小，不能移到内存外，否则GFalse
     @param keepMem 是否保持data到size之内的内存
     @return 是否成功
     */
    GBool retainBufferMoveDataPoint(GJRetainBuffer* buffer,GInt32 offset,GBool keepMem);
    
    /**
     类似retainBufferMoveDataPoint，只是移到开始的位置，而不是偏移
     
     @param buffer buffer description
     @param frontSize 只能大于0
     @param keepMem 是否保持data到size之内的内存
     @return 是否成功
     */
    GBool retainBufferMoveDataToPoint(GJRetainBuffer* buffer,GUInt32 frontSize,GBool keepMem);
#ifdef __cplusplus
}
#endif

#endif /* GJRetainBuffer_h */
