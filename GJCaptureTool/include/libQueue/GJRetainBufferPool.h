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
#include "GJPlatformHeader.h"


#ifdef __cplusplus
extern "C" {
#endif
    
struct GJRetainBufferPool;
    
typedef GJRetainBuffer* (R_MallocCallback)(struct GJRetainBufferPool* pool,GHandle userData);

typedef struct GJRetainBufferPool{
    GJQueue*    queue; //不用链表而用数组是避免一直动态创建和销毁结点数据。
    GUInt32        minSize;//最小大小。
    GInt32         generateSize;
//    GJRetainBuffer内存申请时的回调，为null时默认申请GJRetainBuffer，否则可以定制各种R_开头的结构体
    R_MallocCallback* mallocCallback;
    GHandle         callbackUserData;
}GJRetainBufferPool;
    
GBool GJRetainBufferPoolCreate(GJRetainBufferPool** pool,GUInt32 minSize,GBool atomic,R_MallocCallback callback QUEUE_DEFAULT(NULL),GHandle callbackUserData);

/**
 释放pool,存在没有回收的buffer时会阻塞

 @param pool pool
 */
GVoid GJRetainBufferPoolFree(GJRetainBufferPool** pool);

/**
 清除内容，当complete为yes时表示彻底清除，可能会产生阻塞等待
 
 @param p p description
 @param complete 是否彻底清除
 */
GBool GJRetainBufferPoolClean(GJRetainBufferPool* p,GBool complete);
/**
 获得retainbuffer,当GJRetainBuffer的引用为0时回收，初始值为1，该方法获得的callback等参数不能自定义

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
GJRetainBuffer* GJRetainBufferPoolGetSizeData(GJRetainBufferPool* p,GInt32 size);


#ifdef __cplusplus
}
#endif

#endif /* GJRetainBufferPool_h */
