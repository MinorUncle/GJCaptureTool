//
//  GJList.c
//  GJList
//
//  Created by 未成年大叔 on 2017/8/26.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJList.h"
#include <unistd.h>
#include <sys/time.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include "GJLog.h"

typedef struct _GJListNode {
    GUInt8* data;
    struct _GJListNode* next;
}GJListNode;

struct _GJList {
//    head 进,可以不需用node.pre；
    GJListNode* head;
    GJListNode* tail;
    GInt32 currentLength;
    
    GJListNode* recycleHead;
    GJListNode* recycleTail;
    GInt32 generateSize;

    GBool pushEnable;
    GBool popEnable;
    
    GInt32 minCacheSize;
    
    GInt32 upLimit;
    GInt32 waitCount;//当前等待个数，减少信号的发送
    pthread_cond_t cond;
    pthread_mutex_t lock;
    
};


static inline GBool listWait(GJList* list,GUInt32 ms)
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

static inline GBool listSignal(GJList* list)
{
    return !pthread_cond_signal(&list->cond);
}

static inline GBool listBroadcast(GJList* list)
{
    return !pthread_cond_broadcast(&list->cond);
}

static inline GBool listUnLock(GJList* list){
    return !pthread_mutex_unlock(&list->lock);
}

static inline GBool listLock(GJList* list){
    return !pthread_mutex_lock(&list->lock);
}

static inline GJListNode* listGetEmptyNode(GJList* list){
    GJListNode* node = GNULL;
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
        node = (GJListNode*)malloc(sizeof(GJListNode));
        list->generateSize ++;
    }
    return node;
};

static inline GVoid listRecycleNode(GJList* list,GJListNode* node){
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

GBool listCreate(GJList** outQ,GBool atomic){
    GJList* list = (GJList*)malloc(sizeof(GJList));
    if (!list) {
        return GFalse;
    }
    memset(list, 0, sizeof(GJList));
    
    pthread_condattr_t cond_attr;
    pthread_condattr_init(&cond_attr);
    pthread_cond_init(&list->cond, &cond_attr);
    pthread_mutex_init(&list->lock, NULL);
   
    list->pushEnable = GTrue;
    list->popEnable = GTrue;
    *outQ = list;
    return GTrue;
}

GBool listFree(GJList** inQ){
    GJList* list = *inQ;
    if (!list) {
        return GFalse;
    }
    GJAssert(listLength(list)==0, "listFree 错误，队列存在没有出列的实例");
    pthread_cond_destroy(&list->cond);
    pthread_mutex_destroy(&list->lock);
    
#if MEMORY_CHECK
    GJListNode* node = list->recycleHead;
    while (node) {
        GJListNode* next = node->next;
        free(node);
        node = next;
        list->generateSize--;
    }
    GJAssert(list->generateSize == 0, "管理有误");
#endif
    free(list);
    *inQ = NULL;
    return GTrue;
}

GVoid listEnablePop(GJList* list,GBool enable){
    listLock(list);
    if(!enable){
        list->popEnable = enable;
        listBroadcast(list);
    }else{
        list->popEnable = enable;
    }
    listUnLock(list);
}

GVoid listEnablePush(GJList* list,GBool enable){
    listLock(list);

    list->pushEnable = enable;

    listUnLock(list);

}

GBool listClean(GJList*list, GHandle* outBuffer,GInt32* outCount){
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
                GJListNode* node = list->head;
                outBuffer[i] = node->data;
                list->head = node->next;
                listRecycleNode(list, node);
                list->currentLength--;
            }
        }else{
            while (list->head) {
                GJListNode* node = list->head;
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

GBool listDelete(GJList* list,GHandle temBuffer){
    
    listLock(list);
    if (!list->popEnable) {
        listUnLock(list);
        return GFalse;
    }
    GJListNode* node = list->head;
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
        GJListNode* pre = node;
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

GBool listPop(GJList* list,GHandle* temBuffer,GUInt32 ms){
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
    
    GJListNode* node = list->head;
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
GBool listPush(GJList* list,GHandle temBuffer){
    
    listLock(list);
    if (!list->pushEnable) {
        listUnLock(list);
        return GFalse;
    }
    GJListNode* node = listGetEmptyNode(list);
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

GBool listSwop(GJList* list,GBool order, ListSwopFunc func){
    listLock(list);

    GBool swop = GFalse;
    if (list->head && list->head == list->tail) {
        if (!order) {
            GJListNode* prePre = GNULL;
            GJListNode* pre = list->head;
            GJListNode* node = list->head->next;
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

//GVoid   listSetLimit(GJList* list,GInt32 limit){
//    list->upLimit = limit;
//}

GInt32 listLength(GJList* list){
    return list->currentLength;
}

#if MEMORY_CHECK
GInt32 listGenerateSize(GJList* list){
    return list->generateSize;
}
#endif
