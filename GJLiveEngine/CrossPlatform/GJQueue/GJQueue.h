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
 
typedef struct _GJQueue GJQueue;


//大于0为真，<= 0 为假

/**
 创建queue,注意，在临界情况下可能存在最多一个点的差距
 
 @param outQ outQ description
 @param capacity 初始申请的内存大小个数
 @param atomic 是否支持多线程.(多线程指同一端多线程只是pop和push线程不同则不需要atomic，如果是多个线程push或者pop则需要atomic)
 @return return value description
 */
GBool queueCreate(GJQueue** outQ,GUInt32 capacity,GBool atomic DEFAULT_PARAM(GTrue),GBool autoResize DEFAULT_PARAM(GFalse));
GBool queueFree(GJQueue** inQ);

    
/**
 用于释放数据内存的回调，data表示入队列的数据

 */
typedef void (*QueueCleanFunc)(GHandle data);
    
/**
 清除还没有出队列的数据

 @param q q description
 @param func func description
 */
GVoid queueFuncClean(GJQueue* q,QueueCleanFunc func);
/**
 清空queue,不考虑minCache，同时释放所有pop和push，当outbuffer不为空时赋值给outbuffer.但是inoutCount小于剩余的大小则失败
clean前一定要enable push和pop to false
 @param q q description
 @param outBuffer outBuffer description
 @param inoutCount inoutCount 返回实际pop的数据
 @return return value description
 */
GBool queueClean(GJQueue*q, GVoid** outBuffer DEFAULT_PARAM(NULL),GInt32* inoutCount DEFAULT_PARAM(0));
    
/**
 类似queueClean，但是会考虑minCache;

 @param q q description
 @param outBuffer 接受内存
 @param count 出栈个数
 @param ms 等待时间
 @return return value description
 */
GBool queuePopSerial(GJQueue*q, GVoid** outBuffer ,GInt32 count,GUInt32 ms DEFAULT_PARAM(0));
GBool queuePop(GJQueue* q,GHandle* temBuffer,GUInt32 ms DEFAULT_PARAM(0));
GBool queuePush(GJQueue* q,GHandle temBuffer,GUInt32 ms DEFAULT_PARAM(0));
GInt32 queueGetLength(GJQueue* q);

//enable为GFalse时，push和pop后无论什么情况不阻塞，直接返回失败.并广播取消正在进行的阻塞。
GVoid queueEnablePop(GJQueue* q,GBool enable);
GVoid queueEnablePush(GJQueue* q,GBool enable);
    
//小于该大小不能出栈。可用于缓冲
GVoid queueSetMinCacheSize(GJQueue* q,GUInt32 cacheSize);
GUInt32 queueGetMinCacheSize(GJQueue* q);

//    当前缓存数量/总共申请的空间
GFloat32 queueGetCacheRate(GJQueue* q);

/**
 根据index获得vause,当超过inPointer和outPointer范围则失败，用于遍历数组，不会产生压出队列作用

 @param q q description
 @param index 栈中第几个值，出栈位置为0，递增
 @param value value description
 @return return value description
 */
GBool queuePeekValue(GJQueue* q, GLong index,GVoid** value);

    
/**
 与上一个函数类似，但是会等待，peek一个指针,而且等待的位置结果是out+index的位置，但是每次有数据进入时都会返回，所以如果返回false时，如果有需要，则还要继续peek;
 也与queueWait机制完全一样，除了不会真正pop，只是获取值

 @param q q description
 @param value value description
 @param ms ms description
 @return return value description
 */
GBool queuePeekWaitValue(GJQueue* q,GLong index,GHandle* value,GUInt32 ms DEFAULT_PARAM(500));

/**
 与上一个函数类似，但是peek的是复制内存，多线程请用此函数，防止peek之后马上被其他线程释放了。
 
 @param q q description
 @param value value description
 @param ms ms description
 @return return value description
 */
GBool queuePeekWaitCopyValue(GJQueue* q,GHandle value,GInt32 vauleSize,GUInt32 ms DEFAULT_PARAM(500));
GBool queueUnLockPop(GJQueue* q);
GBool queueLockPush(GJQueue* q);
GBool queueUnLockPush(GJQueue* q);
GBool queueLockPop(GJQueue* q);
GBool queueBroadcastPop(GJQueue* queue);
GBool queueBroadcastPush(GJQueue* queue);
GBool queueWaitPush(GJQueue* queue,GUInt32 ms);
GBool queueWaitPop(GJQueue* queue,GUInt32 ms);
    
GVoid queueSetDebugLeval(GJQueue*queue,GInt32 leval);
#ifdef __cplusplus
}
#endif

#endif /* GJQueue_h */
