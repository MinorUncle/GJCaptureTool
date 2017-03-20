//
//  GJBufferPool.h
//  GJQueue
//
//  Created by 未成年大叔 on 16/12/28.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#ifndef GJBufferPool_h
#define GJBufferPool_h
#include "GJQueue.h"
#include <stdio.h>

/* exploit C++ ability of default values for function parameters */

#ifndef bool
#   define bool unsigned int
#   define true 1
#   define false 0
#endif
#ifdef __cplusplus
extern "C" {
#endif

/**
    多线程支持，可以是不同size；尽量使用相同size（仅仅多个判断），
 */
typedef struct _GJBufferPool{
    GJQueue* queue; //不用链表而用数组是避免一直动态创建和销毁结点数据。
    int    generateSize;
}GJBufferPool;
bool GJBufferPoolCreate(GJBufferPool** pool,bool atomic);
GJBufferPool* defauleBufferPool();
bool GJBufferPoolCleanAndFree(GJBufferPool** pool);

void* GJBufferPoolGetData(GJBufferPool* p,int size);
bool GJBufferPoolSetData(GJBufferPool* p,void* data);

#ifdef __cplusplus
}
#endif

#endif /* GJBufferPool_h */
