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
    GJQueue*    queue; //不用链表而用数组是避免一直动态创建和销毁结点数据。
    uint        minSize;//最小大小。
    int         generateSize;
}GJRetainBufferPool;
bool GJRetainBufferPoolCreate(GJRetainBufferPool** pool,uint minSize,bool atomic);

/**
 释放pool,存在没有回收的buffer时会阻塞

 @param pool pool
 @return return value description
 */
bool GJRetainBufferPoolCleanAndFree(GJRetainBufferPool** pool);



/**
 获得retainbuffer,当GJRetainBuffer的引用为0时回收，初始值为1，

 @param p p description
 @return return value description
 */
GJRetainBuffer* GJRetainBufferPoolGetData(GJRetainBufferPool* p);

    
/**
 获得retainbuffer,当GJRetainBuffer的引用为0时回收，初始值为1，size必须大于minSize;


 @param p p description
 @param size size description
 @return return value description
 */
GJRetainBuffer* GJRetainBufferPoolGetSizeData(GJRetainBufferPool* p,int size);


#ifdef __cplusplus
}
#endif

#endif /* GJRetainBufferPool_h */
