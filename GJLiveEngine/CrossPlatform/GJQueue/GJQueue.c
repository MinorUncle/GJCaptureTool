//
//  GJQueue.c
//  GJQueue
//
//  Created by 未成年大叔 on 16/12/27.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#include "GJQueue.h"
#include "GJLog.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include <errno.h>
#include <sys/time.h>
#import <libkern/OSAtomic.h>


#define DEFAULT_MAX_COUNT 10

#define DEFAULT_TIME 100000000

struct _GJQueue{
    GJClass* debugClass;
    GUInt32 inPointer;  //尾
    GUInt32 outPointer; //头
    GUInt32 capacity;
    GUInt32 minCacheSize;
//    不用链表用数组的优点：
//    1：不用链表节点的额外结构体维护开支。
//    2: 能保证进和出队列在逻辑上和数据结构上的统一。链表的进和出都依赖上一个。//主要基于此才不用链表
//    缺点：
//    1：插入、排序、随机删除开销比较大。
//    2：链表没有最大限制，数组超过最大时再增大需要重新分配内存
    GHandle* queue;
    GBool pushEnable;
    GBool popEnable;
    pthread_cond_t inCond;
    pthread_cond_t outCond;
    pthread_mutex_t pushLock;
    pthread_mutex_t popLock;
    const GBool autoResize;//是否支持自动增长，当为YES时，push永远不会等待，只会重新申请内存,默认为GFalse
//    const GBool atomic;//是否多线程；,GFalse时不会等待。//mod一定多线程；
};



//////queue
GBool queueWaitPop(GJQueue* queue,GUInt32 ms);
GBool queueWaitPush(GJQueue* queue,GUInt32 ms);
GBool queueSignalPop(GJQueue* queue);
GBool queueSignalPush(GJQueue* queue);
static inline struct timespec getMsToTime(GUInt32 ms){
    struct timespec ts;
    struct timeval tv;
    
    
    //    gettimeofday(&tv, GNULL);
    //    GInt32 tu = ms%1000 * 1000 + tv.tv_usec;
    //    ts.tv_sec = tv.tv_sec + ms/1000 + tu / 1000000;
    //    ts.tv_nsec = tu % 1000000 * 1000;
    
    if (ms < 4) {
        ms = 0;
    }else{
        ms -= 4;
    }
    int sec, usec;
    gettimeofday(&tv, GNULL);
    sec = ms / 1000;
    ms = ms - (sec * 1000);
    assert(ms < 1000);
    usec = ms * 1000;
    assert(tv.tv_usec < 1000000);
    ts.tv_sec = tv.tv_sec + sec;
    ts.tv_nsec = (tv.tv_usec + usec) * 1000;
    assert(ts.tv_nsec < 2000000000);
    if(ts.tv_nsec > 999999999)
    {
        ts.tv_sec++;
        ts.tv_nsec -= 1000000000;
    }
    return ts;
}

inline GBool queueWaitPop(GJQueue* queue,GUInt32 ms)
{
    GInt32 ret = 0;
    if (ms < 1)return GFalse;
    
    struct timespec ts = getMsToTime(ms);
    ret = pthread_cond_timedwait(&queue->outCond, &queue->popLock, &ts);
    return ret==0;
}
inline GBool queueWaitPush(GJQueue* queue,GUInt32 ms)
{
    GInt32 ret = 0;
    if (ms < 1)return GFalse;
    
    struct timespec ts = getMsToTime(ms);
    
    ret = pthread_cond_timedwait(&queue->inCond, &queue->pushLock, &ts);
    
    return ret==0;
}
inline GBool queueSignalPop(GJQueue* queue)
{
//    GJLOG(GNULL, GJ_LOGINFO, "queueSignalPop:%p",queue);
    return !pthread_cond_signal(&queue->outCond);
}
inline GBool queueSignalPush(GJQueue* queue)
{
    return !pthread_cond_signal(&queue->inCond);
}
inline GBool queueBroadcastPop(GJQueue* queue)
{
    GJLOG(GNULL, GJ_LOGALL, "queueBroadcastPop:%p",queue);
    return !pthread_cond_broadcast(&queue->outCond);
}
inline GBool queueBroadcastPush(GJQueue* queue)
{
    GJLOG(GNULL, GJ_LOGALL, "queueBroadcastPush%p",queue);
    return !pthread_cond_broadcast(&queue->inCond);
}
inline GBool queueUnLockPop(GJQueue* q){
    return !pthread_mutex_unlock(&q->popLock);
}
inline GBool queueLockPop(GJQueue* q){
    return !pthread_mutex_lock(&q->popLock);
}

inline GBool queueLockPush(GJQueue* q){
    return !pthread_mutex_lock(&q->pushLock);
}
inline GBool queueUnLockPush(GJQueue* q){
    return !pthread_mutex_unlock(&q->pushLock);
}


#pragma mark DELEGATE

GVoid queueEnablePop(GJQueue* q,GBool enable){
    GJLOG(GNULL, GJ_LOGINFO, "queue:%p EnablePop:%d",q,enable);
    if(!enable){
        q->popEnable = enable;//之前也要enable一次，防止pop中assent击中
        queueBroadcastPop(q);//要broadcast，防止其他线程在waitpop，产生等待
        queueLockPop(q);//要lock，防止其他线程刚好读取上次的结果，然后又在之后的Broadcast后wait了。
        q->popEnable = enable;
        queueUnLockPop(q);
    }else{
        q->popEnable = enable;
    }
}

GVoid queueEnablePush(GJQueue* q,GBool enable){
    GJLOG(GNULL, GJ_LOGINFO, "queue:%p EnablePush:%d",q,enable);
    if(!enable){
        queueBroadcastPush(q);
        queueLockPush(q);
        q->pushEnable = enable;
        queueUnLockPush(q);
    }else{
        q->pushEnable = enable;
    }
}

GVoid queueSetMinCacheSize(GJQueue* q,GUInt32 cacheSize){
    GJLOG(GNULL, GJ_LOGDEBUG, "%d",cacheSize);
    q->minCacheSize = cacheSize;
}

GUInt32 queueGetMinCacheSize(GJQueue* q){
    return q->minCacheSize;
}

GFloat queueGetCacheRate(GJQueue* q){
    return (q->inPointer - q->outPointer)*1.0/q->capacity;
}

GInt32 queueGetLength(GJQueue* q){
    return (q->inPointer -  q->outPointer);
}

GBool queuePeekValue(GJQueue* q, GLong index,GVoid** value){
    if (index < 0 || index >= q->inPointer - q->outPointer) {
        return GFalse;
    }
    *value = q->queue[(q->outPointer+index) % q->capacity];
    assert(*value);
    return GTrue;
}

GBool queuePeekWaitValue(GJQueue* q,GLong index,GHandle* value,GUInt32 ms){
    
    queueLockPop(q);
    if (!q->popEnable) {
        queueUnLockPop(q);
        return GFalse;
    }
    
    if (q->inPointer - q->outPointer <= index) {
        int ret = GFalse;
        if (!(ret = queueWaitPop(q, ms)) || q->inPointer - q->outPointer <= index) {
            GJLOG(GNULL, GJ_LOGDEBUG, "%p",q);
            queueUnLockPop(q);
            return GFalse;
        }
    }
    *value = q->queue[(q->outPointer + index)%q->capacity];
    GJAssert(*value != GNULL, "error");
    queueUnLockPop(q);
    
    return GTrue;
}

GBool queuePeekWaitCopyValue(GJQueue* q,GHandle value,GInt32 vauleSize,GUInt32 ms DEFAULT_PARAM(500)){
    queueLockPop(q);
    if (!q->popEnable) {
        queueUnLockPop(q);
        return GFalse;
    }
    
    if (q->inPointer - q->outPointer <= q->minCacheSize) {
        int ret = GFalse;
        if (!(ret = queueWaitPop(q, ms)) || q->inPointer - q->outPointer <= q->minCacheSize) {
            if (ret == GTrue) {
                if (q->popEnable && q->minCacheSize == 0) {
                    //可能是由于broadcast产生,所以如果需要停止等待，broadcast之前禁止pop,也可能是minCacheSize增大（临界条件）引起
                    GJAssert(0, "error pop");
                }
            }
            queueUnLockPop(q);
            return GFalse;
        }
    }
    memcpy(value, q->queue[q->outPointer % q->capacity], vauleSize);
    queueUnLockPop(q);
    
    return GTrue;
}

/**
 出队列

 @param q q description
 @param temBuffer temBuffer description
 @param ms ms description 等待时间
 @return return value description
 */
GBool queuePop(GJQueue* q,GHandle* temBuffer,GUInt32 ms){
    queueLockPop(q);
    if (!q->popEnable) {
        queueUnLockPop(q);
        return GFalse;
    }
RETRY:
    if (q->inPointer - q->outPointer <= q->minCacheSize) {
        int ret = GFalse;
        GJLOG(q->debugClass, GJ_LOGALL, "queue:%p begin pop wait with incount:%d  outcount:%d  minCacheSize:%d",q,q->inPointer,q->outPointer,q->minCacheSize);
        if (!(ret = queueWaitPop(q, ms)) || q->inPointer - q->outPointer <= q->minCacheSize) {
            if (ret == GTrue && q->popEnable) {
                //可能是由于broadcast产生,所以如果需要停止等待，请broadcast之前禁止pop,
                //也可能是minCacheSize增大（临界条件）引起
                //也可能是push的inpoint增加了，两次连续pop在push的inpoint增加和push signal之间调用，（临界调节），只需要重试，因为时间非常短，所以无需修改等待的时间

                goto RETRY;
//                if (q->popEnable && q->minCacheSize == 0) {
//                }
            }
            queueUnLockPop(q);
            return GFalse;
        }
        GJLOG(q->debugClass, GJ_LOGALL, "queue:%p after pop wait with incount:%d  outcount:%d  minCacheSize:%d",q,q->inPointer,q->outPointer,q->minCacheSize);
    }
    GInt32 index = q->outPointer%q->capacity;
    //改为先读取，再自增，否则会出现自增后还没有读，写操作就已经覆盖了。
    *temBuffer = q->queue[index];
    OSMemoryBarrier();//使用内存栅栏，防止cpu乱序
    q->outPointer++;

    queueSignalPush(q);
    GJLOG(q->debugClass, GJ_LOGALL, "queue:%p signal pop with incount:%d  outcount:%d  minCacheSize:%d",q,q->inPointer,q->outPointer,q->minCacheSize);

    GJAssert(*temBuffer != GNULL, "error");
    queueUnLockPop(q);

    return GTrue;
}

/**
 如队列

 @param q q description
 @param temBuffer temBuffer description
 @param ms ms description
 @return return value description
 */
GBool queuePush(GJQueue* q,GHandle temBuffer,GUInt32 ms){
    queueLockPush(q);
    if (!q->pushEnable) {
        queueUnLockPush(q);
        return GFalse;
    }
    if (q->inPointer - q->outPointer == q->capacity) {//满了
        if (q->autoResize) {
            //resize
            GVoid** temBuffer = (GVoid**)malloc(sizeof(GVoid*)*(q->capacity * 2));
            assert(temBuffer);
            queueLockPop(q); ///锁住pop，因为满的所以一定不会死锁
            for (GUInt32 i = q->outPointer,j =0; j < q->capacity; i++,j++) {//采用q->allocSize，溢出也不会出错
                temBuffer[j] = q->queue[i%q->capacity];
            }
            free(q->queue);
            q->queue = temBuffer;
// 不能使用=q->allocSize，因为pop锁住之前可能改变了
            q->inPointer = q->inPointer - q->outPointer;
            q->outPointer = 0;
            q->capacity *= 2;

            queueUnLockPop(q);
        }else{
            if (!queueWaitPush(q, ms) || q->inPointer - q->outPointer == q->capacity) {
                queueUnLockPush(q);
                return GFalse;
            }

        }
    }
    q->queue[q->inPointer%q->capacity] = temBuffer;
//    __atomic_add_fetch();
//    __sync_add_and_fetch();
    OSMemoryBarrier();//使用内存栅栏，防止cpu乱序
    q->inPointer++;
    GJLOG(q->debugClass, GJ_LOGALL, "queue:%p after push wait with incount:%d  outcount:%d  minCacheSize:%d",q,q->inPointer,q->outPointer,q->minCacheSize);


    
//    if (q->inPointer - q->outPointer > q->minCacheSize) {//每次都发出信号，防止pop进入等待前一刻的临界条件此处发出了signal信号。
        queueSignalPop(q);
        GJLOG(q->debugClass, GJ_LOGALL, "queue:%p signal push with incount:%d  outcount:%d  minCacheSize:%d",q,q->inPointer,q->outPointer,q->minCacheSize);
//    }
    queueUnLockPush(q);
    assert(temBuffer);

    return GTrue;
}

GVoid queueFuncClean(GJQueue* q,QueueCleanFunc func){
    queueBroadcastPop(q);//确保可以锁住下一个,避免循环锁
    queueLockPop(q);
    queueBroadcastPush(q);//确保可以锁住下一个,避免循环锁
    queueLockPush(q);
    
    for (GInt32 i = 0; q->outPointer+i <q->inPointer; i++) {
        func(q->queue[(q->outPointer+i) % q->capacity]);
    }
    q->inPointer=q->outPointer=0;
    queueBroadcastPush(q);

    queueUnLockPush(q);
    queueUnLockPop(q);
}
GBool queueClean(GJQueue*q, GVoid** outBuffer,GInt32* outCount){
    GBool result = GTrue;
    queueBroadcastPop(q);//确保可以锁住下一个,避免循环锁
    queueLockPop(q);
    queueBroadcastPush(q);//确保可以锁住下一个,避免循环锁
    queueLockPush(q);
    
    if (outBuffer != NULL && *outCount < q->inPointer - q->outPointer) {
        *outCount = 0;
        result = GFalse;
    }else{
        if (outBuffer != NULL) {
            for (GInt32 i = 0; q->outPointer+i <q->inPointer; i++) {
                outBuffer[i] = q->queue[(q->outPointer+i) % q->capacity];
            }
            *outCount = q->inPointer - q->outPointer;
            q->inPointer=q->outPointer=0;
            queueBroadcastPush(q);
        }else{
            if (outCount) {
                *outCount = q->inPointer - q->outPointer;
            }
        }
    }
    queueUnLockPush(q);
    queueUnLockPop(q);
    return result;
}

//GBool queuePopSerial(GJQueue*q, GVoid** outBuffer ,GInt32 count,GUInt32 ms){
//    queueLockPop(q);
//    if (!q->popEnable) {
//        queueUnLockPop(q);
//        return GFalse;
//    }
//    
//    if (q->inPointer - q->outPointer <= q->minCacheSize + count) {
//        if (!queueWaitPop(q, ms) || q->inPointer - q->outPointer <= q->minCacheSize + count) {
//            //            GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "pop fail Wait in ----------\n");
//            queueUnLockPop(q);
//            return GFalse;
//        }
//    }
//    
//    for (GInt32 i = 0; i < count; i++,q->outPointer++) {
//        outBuffer[i] = q->queue[q->outPointer % q->allocSize];
//    }
//    //#if DEBUG
//    //    memset(&q->queue[index], 0, sizeof(GVoid*));
//    //#endif
//    queueSignalPush(q);
//    //    GJQueuePrintf("after signal out.  incount:%ld  outcount:%ld----------\n",q->inPointer,q->outPointer);
//    queueUnLockPop(q);
//    return GTrue;
//}

GBool queueCreate(GJQueue** outQ,GUInt32 capacity,GBool atomic,GBool autoResize){
    GJQueue* q = (GJQueue*)malloc(sizeof(GJQueue));
    if (!q) {
        return GFalse;
    }
    memset(q, 0, sizeof(GJQueue));
    q->debugClass = GNULL;
    
    pthread_condattr_t cond_attr;
    pthread_condattr_init(&cond_attr);
    pthread_cond_init(&q->inCond, &cond_attr);
    pthread_cond_init(&q->outCond, &cond_attr);
    pthread_mutex_init(&q->popLock, NULL);
    pthread_mutex_init(&q->pushLock, NULL);
    if (capacity<=0) {capacity = DEFAULT_MAX_COUNT;}
    q->capacity = capacity;
    *(GBool*)&q->autoResize = autoResize;
    q->minCacheSize = 0;
    q->pushEnable = GTrue;
    q->popEnable = GTrue;
    q->queue = (GVoid**)malloc(sizeof(GVoid*) * q->capacity);
    GJAssert(!(atomic == GFalse && autoResize == GTrue), "非多线程状态不支持自动增长");
    if (!q->queue) {
        free(q);
        return GFalse;
    }
    *outQ = q;
    return GTrue;
}

GBool queueFree(GJQueue** inQ){
    GJQueue* q = *inQ;
    if (!q) {
        return GFalse;
    }
    GJAssert(queueGetLength(q)==0, "queueFree 错误，队列存在没有出列的实例");
    free(q->queue);
    pthread_cond_destroy(&q->inCond);
    pthread_cond_destroy(&q->outCond);
    pthread_mutex_destroy(&q->popLock);
    pthread_mutex_destroy(&q->pushLock);
    free(q);
    *inQ = NULL;
    return GTrue;
}
extern const GJClass*  debugClass[];
GVoid queueSetDebugLeval(GJQueue*queue,GInt32 leval){
    queue->debugClass = (GJClass*)debugClass[leval];
}
