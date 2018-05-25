//
//  GJBufferPool.c
//  GJQueue
//
//  Created by 未成年大叔 on 16/12/28.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#include "GJBufferPool.h"
#include <stdlib.h>
#include "GJLog.h"
#include "GJList.h"
#include "GJUtil.h"



/**
 多线程支持，可以是不同size；尽量使用相同size（仅仅多个判断），
 */
struct _GJBufferPool{
    GJList*     queue; //不用链表而用数组是避免一直动态创建和销毁结点数据。
    GInt32      generateSize;
    GUInt32     minSize;
    
#if MENORY_CHECK
    
    //跟踪离开bufferpool的数据
    GJList*     leaveList;
#endif
};


typedef struct GJBufferDataTail{
    GInt32 size;
}GJBufferDataTail;

#if MENORY_CHECK
GJBufferDataHead* GJBufferPoolGetDataHead(GUInt8* data){
    return (GJBufferDataHead*)(data - sizeof(GJBufferDataHead));
}
static inline GJBufferDataTail* GJBufferPoolGetDataTail(GUInt8* data){
    return (GJBufferDataTail*)(data + GJBufferPoolGetDataHead(data)->size);
}

GVoid GJBufferPoolCheck(GJBufferPool* pool,GUInt8* data){
//    GChar* tracker = (GChar*)(((GLong*)data) - 3);
    GJBufferDataHead* head = GJBufferPoolGetDataHead(data);
    GJAssert(pool == head->pool, "数据有误，data不属于该pool");
    GJBufferDataTail* tail = GJBufferPoolGetDataTail(data);
    GJAssert(head->size == tail->size, "内存溢出");
};
#endif

GBool GJBufferPoolCreate(GJBufferPool** pool,GUInt32 minSize,GBool atomic){
    GJBufferPool* p;
    if (*pool == NULL) {
        
        p = (GJBufferPool*)malloc(sizeof(GJBufferPool));
    }else{
        p = *pool;
    }
    if (!listCreate(&p->queue,GTrue)){
        free(p);
        return GFalse;
    }
    
#if MENORY_CHECK
    if (!listCreate(&p->leaveList, 5)){
        free(p);
        GJAssert(0, "跟踪器启动失败");
    }
#endif

    p->generateSize = 0;
    p->minSize = minSize;
    *pool = p;
    return GTrue;
};

GJBufferPool* defauleBufferPool(){
    static GJBufferPool* _defaultPool = NULL;
    if (_defaultPool == NULL) {
        GJBufferPoolCreate(&_defaultPool,1, GTrue);
    }
    return _defaultPool;
}
struct GJRetainBuffer;
GVoid GJBufferPoolClean(GJBufferPool* p,GBool complete){

    if(complete){
#ifdef DEBUG
//        GLong startMS = GJ_Gettime().value;
#endif
        if (p->generateSize > listLength(p->queue)) {
            GJLOG(DEFAULT_LOG, GJ_LOGWARNING, ":%p,还有%d个buffer没有释放,需要等待\n",p,p->generateSize - listLength(p->queue));
        }
        while (p->generateSize > 0) {
            GUInt8* data;
            
// 离开的内存块申请位置打印命令 p ((GJBufferDataHead*)(p->leaveList->head->data))[-1].file
// 未回收的所有retain列表       p ((GJRetainBuffer*)(p->leaveList->head->data+16))->retainList->head->data//16为R_RetainBuffer的前缀检查数据GJRBufferDataHead的大小
// 未回收的所有unretain列表       p ((GJRetainBuffer*)(p->leaveList->head->data+16))->unretainList->head->data//16为R_RetainBuffer的前缀检查数据GJRBufferDataHead的大小

            if (listPop(p->queue, (GHandle*)&data, GINT32_MAX)) {
                
#if MENORY_CHECK

                GJBufferPoolCheck(p,(GUInt8*)data);
                data -= sizeof(GJBufferDataHead);
#else
                data -= sizeof(GLong);
#endif
                free(data);
            }else{
                GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "GJBufferPoolClean error:%p",p);
            }
            p->generateSize --;
        }
#ifdef DEBUG
//        GJAssert(GJ_Gettime().value - startMS < 1000, "等待时间太久，需要检查")   ;
#endif
        GJLOG(DEFAULT_LOG, GJ_LOGINFO,"GJBufferPoolClean：%p 完成",p);
    }else{
        GUInt8* data;
        while (listPop(p->queue, (GHandle*)&data, 0)) {
            
#if MENORY_CHECK

            GJBufferPoolCheck(p,(GUInt8*)data);
            data -= sizeof(GJBufferDataHead);
#endif
            free(data);
            p->generateSize --;
        }
    }
    
#if MENORY_CHECK
    if (complete) {
        GJAssert(listLength(p->leaveList)==0, "跟踪器有误,还存在数据");
    }
#endif
    return ;
};

GVoid GJBufferPoolFree(GJBufferPool* pool){
    if (!pool) {
        return ;
    }
    listFree(&pool->queue);
#if MENORY_CHECK
    listFree(&pool->leaveList);
#endif
    
    free(pool);
};

#if MENORY_CHECK

GVoid _GJBufferPoolUpdateTrackInfo(GJBufferPool* pool,GUInt8* data,const GChar* file  DEFAULT_PARAM(GNull),const GChar* func  DEFAULT_PARAM(GNull), GInt32 lineTracker DEFAULT_PARAM(0)){
    GJBufferDataHead* head = GJBufferPoolGetDataHead(data);
    GJAssert(pool == head->pool, "数据有误，data不属于该pool");
    GJBufferDataTail* tail = GJBufferPoolGetDataTail(data);
    GJAssert(head->size == tail->size, "内存溢出");
    head->file = file;
    head->func = func;
    head->line = lineTracker;
#ifdef GATHER_TIME
    GJ_GetTimeStr(head->time);
#endif
}
#endif

GUInt8* _GJBufferPoolGetSizeData(GJBufferPool* p,GInt32 size,const GChar* file, const GChar* func, GInt32 lineTracker){
    GUInt8* data;
    
    GJAssert(size >= p->minSize, "GJBufferPoolGetSizeData size less then minsize");
    if (listPop(p->queue, (GVoid**)&data, 0)) {
        
        if ( *data < size) {
            
#if MENORY_CHECK
            data = (GUInt8*)realloc(data-sizeof(GJBufferDataHead), size + sizeof(GJBufferDataHead) + sizeof(GJBufferDataTail));
            GJBufferDataHead* head = (GJBufferDataHead*)data;
            head->file = file;
            head->func = func;
            head->line = lineTracker;
            head->pool = p;
            head->size = size;
#ifdef GATHER_TIME
            GJ_GetTimeStr(head->time);
#endif
            GJBufferDataTail* tail = (GJBufferDataTail*)(data + sizeof(GJBufferDataHead) + size);
            tail->size = size;

            data += sizeof(GJBufferDataHead);
#else
            data = (GUInt8*)realloc(data-sizeof(GLong), size + sizeof(GLong));
            *(GLong*)data = (GLong)size;
            data += sizeof(GLong);
#endif
        }
#if MENORY_CHECK

        else{
            GJBufferDataHead* head = (GJBufferDataHead*)(data - sizeof(GJBufferDataHead));
            head->file = file;
            head->func = func;
            head->line = lineTracker;
            head->pool = p;
            head->size = size;
        }
#endif
    }else{
        
#if MENORY_CHECK
        
        data = (GUInt8*)malloc(size + sizeof(GJBufferDataHead) + sizeof(GJBufferDataTail));
        GJBufferDataHead* head = (GJBufferDataHead*)data;
        head->file = file;
        head->func = func;
        head->line = lineTracker;
        head->pool = p;
        head->size = size;
#ifdef GATHER_TIME
        GJ_GetTimeStr(head->time);
#endif
        GJBufferDataTail* tail = (GJBufferDataTail*)(data + sizeof(GJBufferDataHead) + size);
        tail->size = size;
        
        data += sizeof(GJBufferDataHead);
#else
        
        data = (GUInt8*)malloc(size + sizeof(GLong));
        *(GLong*)data = (GLong)size;
        data += sizeof(GLong);
#endif
        __sync_fetch_and_add(&p->generateSize,1);
    }

#if MENORY_CHECK
    GJAssert(listPush(p->leaveList, data), "跟踪器失败") ;
#endif
    return (GUInt8*)data;
}

GUInt8* GJBufferPoolGetData(GJBufferPool* p,const GChar* func, GInt32 lineTracker){
    GUInt8* data;
    
    if (!listPop(p->queue, (GVoid**)&data, 0)) {
#if MENORY_CHECK
        data = (GUInt8*)malloc(p->minSize + sizeof(GJBufferDataHead) + sizeof(GJBufferDataTail));
        GJBufferDataHead* pre = (GJBufferDataHead*)data;
        pre->func = func;
        pre->line = lineTracker;
        pre->pool = p;
        pre->size = p->minSize;
#ifdef GATHER_TIME
        GJ_GetTimeStr(pre->time);
#endif
        GJBufferDataTail* tail = (GJBufferDataTail*)(data + sizeof(GJBufferDataHead) + p->minSize);
        tail->size = p->minSize;
        
        data += sizeof(GJBufferDataHead);
#else
        data = (GUInt8*)malloc(p->minSize + sizeof(GLong));
        *(GLong*)data = (GLong)p->minSize;
        data += sizeof(GLong);
#endif
        __sync_fetch_and_add(&p->generateSize,1);
    }

#if MENORY_CHECK
    GJAssert(listPush(p->leaveList, data), "跟踪器失败") ;
#endif
    return (GUInt8*)data;
}

//GBool GJBufferPoolSetBackData(GUInt8* data){
//    GJBufferPool* p = (GJBufferPool*)*((GLong*)data - 1);
//    return queuePush(p->queue, (GLong*)data - 2, 0);
//}
GBool GJBufferPoolSetData(GJBufferPool* p,GUInt8* data){
    
#if MENORY_CHECK
    GJBufferPoolCheck(p,data);
    listDelete(p->leaveList, data);
#endif
    
    return listPush(p->queue,data);
}
