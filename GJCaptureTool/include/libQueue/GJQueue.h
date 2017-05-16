//
//  GJQueue.h
//  GJQueue
//
//  Created by 未成年大叔 on 16/12/27.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#ifndef GJQueue_h
#define GJQueue_h
#include <pthread.h>
#include <stdio.h>
#include "GJPlatformHeader.h"


/* exploit C++ ability of default values for function parameters */


#ifdef __cplusplus
extern "C" {
#endif
    
    
    
    
typedef struct _GJData{
    GVoid* data;
    GUInt32 size;
}GJData;

typedef struct _GJQueue{
    GUInt32 inPointer;  //尾
    GUInt32 outPointer; //头
    GUInt32 capacity;
    GUInt32 allocSize;
    GUInt32 minCacheSize;
    GVoid** queue;
    GBool pushEnable;
    GBool popEnable;
    pthread_cond_t inCond;
    pthread_cond_t outCond;
    pthread_mutex_t pushLock;
    pthread_mutex_t popLock;
    GBool autoResize;//是否支持自动增长，当为YES时，push永远不会等待，只会重新申请内存,默认为GFalse
    GBool atomic;//是否多线程；,GFalse时不会等待
}GJQueue;

//大于0为真，<= 0 为假

/**
 创建queue
 
 @param outQ outQ description
 @param capacity 初始申请的内存大小个数
 @param atomic 是否支持多线程
 @return return value description
 */
GBool queueCreate(GJQueue** outQ,GUInt32 capacity,GBool atomic QUEUE_DEFAULT(GTrue),GBool autoResize QUEUE_DEFAULT(GFalse));
GBool queueFree(GJQueue** inQ);

/**
 清空queue,不考虑minCache，同时释放所有pop和push，当outbuffer不为空时赋值给outbuffer.但是inoutCount小于剩余的大小则失败

 @param q q description
 @param outBuffer outBuffer description
 @param inoutCount inoutCount 返回实际pop的数据
 @return return value description
 */
GBool queueClean(GJQueue*q, GVoid** outBuffer QUEUE_DEFAULT(NULL),GInt32* inoutCount QUEUE_DEFAULT(0));
    
/**
 类似queueClean，但是会考虑minCache;

 @param q q description
 @param outBuffer 接受内存
 @param count 出栈个数
 @param ms 等待时间
 @return return value description
 */
GBool queuePopSerial(GJQueue*q, GVoid** outBuffer ,GInt32 count,GUInt32 ms QUEUE_DEFAULT(0));
GBool queuePop(GJQueue* q,GVoid** temBuffer,GUInt32 ms QUEUE_DEFAULT(0));
GBool queuePush(GJQueue* q,GVoid* temBuffer,GUInt32 ms QUEUE_DEFAULT(0));
GInt32 queueGetLength(GJQueue* q);

//enable为GFalse时，push和pop后无论什么情况不阻塞，直接返回失败.但是原来等待的继续等待。
GVoid queueEnablePop(GJQueue* q,GBool enable);
GVoid queueEnablePush(GJQueue* q,GBool enable);
    
//小于该大小不能出栈。可用于缓冲
GVoid queueSetMinCacheSize(GJQueue* q,GUInt32 cacheSize);
GUInt32 queueGetMinCacheSize(GJQueue* q);

    
/**
 根据index获得vause,当超过inPointer和outPointer范围则失败，用于遍历数组，不会产生压出队列作用

 @param q q description
 @param index 栈中第几个值，出栈位置为0，递增
 @param value value description
 @return return value description
 */
GBool queuePeekValue(GJQueue* q,const GInt32 index,GVoid** value);

GBool queuePeekWaitCopyValue(GJQueue* q,const GInt32 index,GHandle value,GInt32 vauleSize,GUInt32 ms QUEUE_DEFAULT(500));

/**
 与上一个函数类似，当是会等待

 @param q q description
 @param index index description
 @param value value description
 @param ms ms description
 @return return value description
 */
GBool queuePeekWaitValue(GJQueue* q,const GInt32 index,GVoid** value,GUInt32 ms QUEUE_DEFAULT(500));


GBool queueUnLockPop(GJQueue* q);
GBool queueLockPush(GJQueue* q);
GBool queueUnLockPush(GJQueue* q);
GBool queueLockPop(GJQueue* q);
GBool queueBroadcastPop(GJQueue* queue);
GBool queueBroadcastPush(GJQueue* queue);
GBool queueWaitPush(GJQueue* queue,GUInt32 ms);
GBool queueWaitPop(GJQueue* queue,GUInt32 ms);
#ifdef __cplusplus
}
#endif

#endif /* GJQueue_h */
