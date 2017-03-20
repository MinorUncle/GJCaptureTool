//
//  GJRetainBufferPool.h
//  GJQueue
//
//  Created by mac on 17/2/22.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJRetainBufferPool_h
#define GJRetainBufferPool_h
#include "GJQueue.h"
#include "GJRetainBuffer.h"
#include <stdio.h>


#ifndef bool
#   define bool unsigned int
#   define true 1
#   define false 0
#endif

#ifdef __cplusplus
extern "C" {
#endif


typedef struct _GJRetainBufferPool{
    GJQueue* queue; //不用链表而用数组是避免一直动态创建和销毁结点数据。
    uint bufferSize;
    int    generateSize;
}GJRetainBufferPool;
bool GJRetainBufferPoolCreate(GJRetainBufferPool** pool,uint bufferSize,bool atomic);
bool GJRetainBufferPoolCleanAndFree(GJRetainBufferPool** pool);



/**
 获得retainbuffer,当GJRetainBuffer的引用为0时回收，初始值为1，

 @param p p description
 @return return value description
 */
GJRetainBuffer* GJRetainBufferPoolGetData(GJRetainBufferPool* p);

#ifdef __cplusplus
}
#endif

#endif /* GJRetainBufferPool_h */
