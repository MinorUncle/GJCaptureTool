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
    
typedef GInt32 (R_MallocCallback)(struct GJRetainBufferPool* pool);
typedef GVoid  (P_RecycleNoticeCallback)(GJRetainBuffer* buffer,GHandle userData);
    
typedef struct GJRetainBufferPool{
    //不用链表而用数组是避免一直动态创建和销毁结点数据。
    GJQueue*    queue;
    
    //最小大小。
    GUInt32        minSize;
    GInt32         generateSize;
    
    //GJRetainBuffer内存申请时的回调，为null时默认申请GJRetainBuffer，否则可以定制各种R_开头的结构体
    R_MallocCallback* mallocCallback;
    
    //    每次回收内存时的通知，用于处理伪释放内存前的处理
    P_RecycleNoticeCallback* noticeCallback;
    GHandle noticeUserData;
#if MENORY_CHECK
    
    //跟踪离开bufferpool的数据
    GJList*     leaveList;
#endif
}GJRetainBufferPool;
    
    
/**
 pool创建

 @param pool null则自动申请内存
 @param minSize 最小的获得的内存
 @param atomic 是否多线程
 @param callback retainbuffer结构体申请时的回调，用于定制各种R_结构体
 P_RecycleNoticeCallback retainbuffer回收时的通知
 @return return value description
 */
GBool GJRetainBufferPoolCreate(GJRetainBufferPool** pool,GUInt32 minSize,GBool atomic,R_MallocCallback callback DEFAULT_PARAM(NULL),P_RecycleNoticeCallback noticeCallback DEFAULT_PARAM(NULL),GHandle noticeUserData DEFAULT_PARAM(NULL));

/**
 释放pool,存在没有回收的buffer时会阻塞

 @param pool pool
 */
GVoid GJRetainBufferPoolFree(GJRetainBufferPool* pool);

/**
 清除内容，当complete为yes时表示彻底清除，可能会产生阻塞等待
 
 @param p        p description
 @param complete 是否彻底清除
 */
GBool GJRetainBufferPoolClean(GJRetainBufferPool* p,GBool complete);
    
/**
 获得retainbuffer,当GJRetainBuffer的引用为0时回收，初始值为1，该方法获得的callback等参数不能自定义

 @param p       p description
 @return return value description
 */
#define GJRetainBufferPoolGetData(x) _GJRetainBufferPoolGetData(x,__FILE__, __func__,__LINE__)
GJRetainBuffer* _GJRetainBufferPoolGetData(GJRetainBufferPool* p,const GChar* file,const GChar* func DEFAULT_PARAM(GNull), GInt32 line);

/**
 获得retainbuffer,当GJRetainBuffer的引用为0时回收，初始值为1，size必须大于minSize;


 @param p       p description
 @param size    size description
 @return return value description
 */
#define GJRetainBufferPoolGetSizeData(x,y) _GJRetainBufferPoolGetSizeData(x,y,__FILE__,__func__,__LINE__)
GJRetainBuffer* _GJRetainBufferPoolGetSizeData(GJRetainBufferPool* p,GInt32 size,const GChar* file,const GChar* func DEFAULT_PARAM(GNull),GInt32 line);

#ifdef __cplusplus
}
#endif

#endif /* GJRetainBufferPool_h */
