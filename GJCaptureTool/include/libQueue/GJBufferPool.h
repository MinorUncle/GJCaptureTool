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
    uint     minSize;
}GJBufferPool;
bool GJBufferPoolCreate(GJBufferPool** pool,uint minSize,bool atomic);
//小数据最好多用默认的，大数据最好不要用默认的
GJBufferPool* defauleBufferPool();
void GJBufferPoolFree(GJBufferPool** pool);

/**
 清除内容，当complete为yes时表示彻底清除，可能会产生阻塞等待

 @param p p description
 @param complete 是否彻底清除
 */
void GJBufferPoolClean(GJBufferPool* p,bool complete);
uint8_t* GJBufferPoolGetData(GJBufferPool* p);
uint8_t* GJBufferPoolGetSizeData(GJBufferPool* p,int size);
bool GJBufferPoolSetData(GJBufferPool* p,uint8_t* data);

#ifdef __cplusplus
}
#endif

#endif /* GJBufferPool_h */
