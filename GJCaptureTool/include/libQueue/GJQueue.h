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


/* exploit C++ ability of default values for function parameters */
#ifndef QUEUE_DEFAULT
#if defined( __cplusplus )
#   define QUEUE_DEFAULT(x) =x
#else
#   define QUEUE_DEFAULT(x)

#endif
#endif

#ifndef bool
#   define bool unsigned int
#   define true 1
#   define false 0
#endif

#ifdef __cplusplus
extern "C" {
#endif
    
    
    
    
    typedef struct _GJData{
        void* data;
        unsigned int size;
    }GJData;
    
    typedef struct _GJQueue{
        unsigned long inPointer;  //尾
        unsigned long outPointer; //头
        unsigned int capacity;
        unsigned int allocSize;
        unsigned int minCacheSize;
        void** queue;
        bool pushEnable;
        bool popEnable;
        pthread_cond_t inCond;
        pthread_cond_t outCond;
        pthread_mutex_t pushLock;
        pthread_mutex_t popLock;
        bool autoResize;//是否支持自动增长，当为YES时，push永远不会等待，只会重新申请内存,默认为false
        bool atomic;//是否多线程；,false时不会等待
    }GJQueue;
    
    //大于0为真，<= 0 为假
    
    /**
     创建queue
     
     @param outQ outQ description
     @param capacity 初始申请的内存大小个数
     @param atomic 是否支持多线程
     @return return value description
     */
    bool queueCreate(GJQueue** outQ,unsigned int capacity,bool atomic QUEUE_DEFAULT(true),bool autoResize QUEUE_DEFAULT(false));
    bool queueCleanAndFree(GJQueue** inQ);
    bool queueClean(GJQueue*q, void** outBuffer,long* outCount);
    bool queuePop(GJQueue* q,void** temBuffer,unsigned int ms QUEUE_DEFAULT(500));
    bool queuePush(GJQueue* q,void* temBuffer,unsigned int ms QUEUE_DEFAULT(500));
    long queueGetLength(GJQueue* q);
    
    //enable为false时，push和pop后无论什么情况不阻塞，直接返回失败.但是原来等待的继续等待。
    void queueEnablePop(GJQueue* q,bool enable);
    void queueEnablePush(GJQueue* q,bool enable);
    
    //小于该大小不能出栈。可用于缓冲
    void queueSetMinCacheSize(GJQueue* q,unsigned int cacheSize);
    unsigned int queueGetMinCacheSize(GJQueue* q);
    
    
    /**
     根据index获得vause,当超过inPointer和outPointer范围则失败，用于遍历数组，不会产生压出队列作用
     
     @param q q description
     @param index 栈中第几个值，出栈位置为0，递增
     @param value value description
     @return return value description
     */
    bool queuePeekValue(GJQueue* q,const long index,void** value);
    
    
    /**
     与上一个函数类似，当是会等待
     
     @param q q description
     @param index index description
     @param value value description
     @param ms ms description
     @return return value description
     */
    bool queuePeekWaitValue(GJQueue* q,const long index,void** value,unsigned int ms QUEUE_DEFAULT(500));
    
    
    bool queueUnLockPop(GJQueue* q);
    bool queueLockPush(GJQueue* q);
    bool queueUnLockPush(GJQueue* q);
    bool queueLockPop(GJQueue* q);
    bool queueBroadcastPop(GJQueue* queue);
    bool queueBroadcastPush(GJQueue* queue);
    bool queueWaitPush(GJQueue* queue,unsigned int ms);
    bool queueWaitPop(GJQueue* queue,unsigned int ms);
#ifdef __cplusplus
}
#endif

#endif /* GJQueue_h */
