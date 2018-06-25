//
//  GJListQueue.c
//  GJListQueue
//
//  Created by 未成年大叔 on 2017/8/26.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJListQueue.h"
#include <unistd.h>
#include <sys/time.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include "GJLog.h"

typedef struct _GJListQueueNode {
    GUInt8* data;
    struct _GJListQueueNode* next;
}GJListQueueNode;

struct _GJListQueue {
//    head 进,可以不需用node.pre；
    GJListQueueNode* head;
    GJListQueueNode* tail;
    GInt32 currentLength;
    
    GJListQueueNode* recycleHead;
    GJListQueueNode* recycleTail;
    GInt32 generateSize;

    GBool pushEnable;
    GBool popEnable;
    
    GInt32 minCacheSize;
    
    GInt32 upLimit;
    GInt32 waitCount;//当前等待个数，减少信号的发送
    pthread_cond_t cond;
    pthread_mutex_t lock;
    
};


static inline GBool listWait(GJListQueue* list,GUInt32 ms)
{
    GInt32 ret = 0;
    if (ms < 1)return GFalse;
    
    struct timespec ts;
    struct timeval tv;
    struct timezone tz;
    gettimeofday(&tv, &tz);
    GInt32 tu = ms%1000 * 1000 + tv.tv_usec;
    ts.tv_sec = tv.tv_sec + ms/1000 + tu / 1000000;
    ts.tv_nsec = tu % 1000000 * 1000;
    ret = pthread_cond_timedwait(&list->cond, &list->lock, &ts);
    
    return ret==0;
}

static inline GBool listSignal(GJListQueue* list)
{
    return !pthread_cond_signal(&list->cond);
}

static inline GBool listBroadcast(GJListQueue* list)
{
    return !pthread_cond_broadcast(&list->cond);
}

static inline GBool listUnLock(GJListQueue* list){
    return !pthread_mutex_unlock(&list->lock);
}

static inline GBool listLock(GJListQueue* list){
    return !pthread_mutex_lock(&list->lock);
}

static inline GJListQueueNode* listGetEmptyNode(GJListQueue* list){
    GJListQueueNode* node = GNULL;
    if (list->recycleHead != GNULL) {
        node = list->recycleHead;
        list->recycleHead = node->next;
        if(list->recycleHead == GNULL){
            
#if MEMORY_CHECK
            GJAssert(node == list->recycleTail, "管理有误");
#endif
            list->recycleTail = GNULL;
        }
    }else{
#if MEMORY_CHECK
        GJAssert(list->recycleTail == GNULL, "管理有误");
#endif
        node = (GJListQueueNode*)malloc(sizeof(GJListQueueNode));
        list->generateSize ++;
    }
    return node;
};

static inline GVoid listRecycleNode(GJListQueue* list,GJListQueueNode* node){
    if (list->recycleTail == GNULL) {
        
#if MEMORY_CHECK
        GJAssert(list->recycleHead == GNULL, "管理有误");
#endif
        list->recycleTail = list->recycleHead = node;
    }else{
        
#if MEMORY_CHECK
        GJAssert(list->recycleHead != GNULL, "管理有误");
#endif
        list->recycleTail->next = node;
        GJAssert(node != list->recycleHead, "");
        list->recycleTail = node;
    }
    node->next = GNULL;
}

GBool listQueueCreate(GJListQueue** outQ,GBool atomic){
    GJListQueue* list = (GJListQueue*)malloc(sizeof(GJListQueue));
    if (!list) {
        return GFalse;
    }
    memset(list, 0, sizeof(GJListQueue));
    
    pthread_condattr_t cond_attr;
    pthread_condattr_init(&cond_attr);
    pthread_cond_init(&list->cond, &cond_attr);
    pthread_mutex_init(&list->lock, NULL);
   
    list->pushEnable = GTrue;
    list->popEnable = GTrue;
    *outQ = list;
    return GTrue;
}

GBool listQueueFree(GJListQueue** inQ){
    GJListQueue* list = *inQ;
    if (!list) {
        return GFalse;
    }
    GJAssert(listQueueLength(list)==0, "listQueueFree 错误，队列存在没有出列的实例");
    pthread_cond_destroy(&list->cond);
    pthread_mutex_destroy(&list->lock);
    
    GJListQueueNode* node = list->recycleHead;
    while (node) {
        GJListQueueNode* next = node->next;
        free(node);
        node = next;
        list->generateSize--;
    }
    GJAssert(list->generateSize == 0, "管理有误");
    free(list);
    *inQ = NULL;
    return GTrue;
}

GVoid listQueueEnablePop(GJListQueue* list,GBool enable){
    listLock(list);
    if(!enable){
        list->popEnable = enable;
        listBroadcast(list);
    }else{
        list->popEnable = enable;
    }
    listUnLock(list);
}

GVoid listQueueEnablePush(GJListQueue* list,GBool enable){
    listLock(list);

    list->pushEnable = enable;

    listUnLock(list);

}

GBool listQueueClean(GJListQueue*list, GHandle* outBuffer,GInt32* outCount){
    GBool result = GTrue;
  
    listLock(list);
    listBroadcast(list);
    if (outBuffer == GNULL && outCount != GNULL) {
        *outCount = list->currentLength;
    }else if (outBuffer != NULL && *outCount < list->currentLength) {
        *outCount = 0;
        result = GFalse;
    }else{
        int i = 0;
        if(outBuffer != GNULL){
            while (list->head) {
                GJListQueueNode* node = list->head;
                outBuffer[i] = node->data;
                list->head = node->next;
                listRecycleNode(list, node);
                list->currentLength--;
            }
        }else{
            while (list->head) {
                GJListQueueNode* node = list->head;
                list->head = node->next;
                listRecycleNode(list, node);
                list->currentLength--;
            }
        }

        list->tail = GNULL;
#if MEMORY_CHECK
        GJAssert(list->currentLength == 0,"管理有误");
#endif
    }
    listUnLock(list);
    return result;
}

GBool listQueueDelete(GJListQueue* list,GHandle temBuffer){
    
    listLock(list);
    if (!list->popEnable) {
        listUnLock(list);
        return GFalse;
    }
    GJListQueueNode* node = list->head;
    if (node->data == temBuffer) {
        list->head = node->next;
        if (list->head == GNULL) {
#if MEMORY_CHECK
            GJAssert(node == list->tail, "管理有误");
#endif
            list->tail = GNULL;
        }
        listRecycleNode(list, node);
        list->currentLength --;
    }else{
        GJListQueueNode* pre = node;
        node = node->next;
        while (node) {
            if (node->data == temBuffer) {
                pre->next = node->next;
                if (list->tail == node) {
                    list->tail = pre;
                }
                listRecycleNode(list, node);
                list->currentLength --;
                break;
            }
            pre = node;
            node = node->next;
        }
    }
    
#if MEMORY_CHECK
    GJAssert(node != GNULL, "追踪器有误， node 不存在");
#endif

    listUnLock(list);
    return GTrue;
}

GBool listQueuePop(GJListQueue* list,GHandle* temBuffer,GUInt32 ms){
    listLock(list);
    if (!list->popEnable) {
        listUnLock(list);
        return GFalse;
    }
    
    if (list->currentLength <= list->minCacheSize) {
///<----------1  一定需要，避免收到signal之后被其他lock的线程抢先进入lock，然后list->currentLength > list->minCacheSize还是为false，导致没有超时，但是返回失败
///<----------1也存在问题，会导致listBroadcast无效,所以如果需要退出，请在broadcast之前将popEnable设置为false，
        GBool didWait = GFalse;
        struct timeval tv0,tv1;
        gettimeofday(&tv0, NULL);
        GInt32 leftMs = ms;
        list->waitCount++;
        GBool ret = GFalse;
        while ((ret = listWait(list, leftMs))) {
            if (list->currentLength > list->minCacheSize ) {
                didWait = GTrue;
                break;
            }else if(!list->popEnable){
                break;
            }
            gettimeofday(&tv1, NULL);
            leftMs -= (GInt32)(tv1.tv_sec * 1000 + tv1.tv_usec/1000)-(GInt32)(tv0.tv_sec * 1000 + tv0.tv_usec/1000);
        }
        list->waitCount--;
//----------->>>>
        if (!didWait) {
#ifdef DEBUG
            if (ret && list->popEnable) {
                GJAssert(0, "这种情况不应该会false");
            }
#endif
            listUnLock(list);
            return GFalse;
        }
    }
    
    GJListQueueNode* node = list->head;
    list->head = node->next;
    if (list->head == GNULL) {
#if MEMORY_CHECK
        GJAssert(node == list->tail, "管理有误");
#endif
        list->tail = GNULL;
    }
    *temBuffer = node->data;
    
    list->currentLength --;
    listRecycleNode(list, node);
    
    listUnLock(list);
    return GTrue;
}

/**
 如队列
 
 @param list list description
 @param temBuffer temBuffer description
 @return return value description
 */
GBool listQueuePush(GJListQueue* list,GHandle temBuffer){
    
    listLock(list);
    if (!list->pushEnable) {
        listUnLock(list);
        return GFalse;
    }
    GJListQueueNode* node = listGetEmptyNode(list);
    if (list->tail == GNULL) {
        list->tail = list->head = node;
    }else{
        list->tail->next = node;
        list->tail = node;
    }
    
    node->next = GNULL;
    node->data = temBuffer;
    list->currentLength ++;

    if (list->waitCount > 0) {
        listSignal(list);
    }
    GJAssert(list->head != GNULL, "");
    listUnLock(list);
    return GTrue;
}

GBool listQueueSwop(GJListQueue* list,GBool order, listQueueSwopFunc func){
    listLock(list);

    GBool swop = GFalse;
    if (list->head && list->head == list->tail) {
        if (!order) {
            GJListQueueNode* prePre = GNULL;
            GJListQueueNode* pre = list->head;
            GJListQueueNode* node = list->head->next;
            GBool stop = GFalse;
            while (stop) {
                if (func(pre,node,&stop)) {
                    if (pre == list->head) {
                        list->head = node;
                    }else{
                        prePre->next = node;
                    }
                    if (node == list->tail) {
                        list->tail = pre;
                    }
                    pre->next = node->next;
                    node->next = pre;
                }
                prePre = pre;
                pre = node;
                node = node->next;
                if (node == GNULL) {
                    stop = GTrue;
                }
            }

        }else{
            GJAssert(0, "暂时不支持");
        }
    }

    listUnLock(list);

    return swop;
}

//GVoid   listSetLimit(GJListQueue* list,GInt32 limit){
//    list->upLimit = limit;
//}

GInt32 listQueueLength(GJListQueue* list){
    return list->currentLength;
}

#if MEMORY_CHECK
GInt32 listQueueGenerateSize(GJListQueue* list){
    return list->generateSize;
}
#endif
