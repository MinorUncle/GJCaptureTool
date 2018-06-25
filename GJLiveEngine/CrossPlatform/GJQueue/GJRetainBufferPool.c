//
//  GJRetainBufferPool.c
//  GJQueue
//
//  Created by mac on 17/2/22.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRetainBufferPool.h"
#include "GJBufferPool.h"
#include "GJLog.h"
#include <stdlib.h>
#include "GJUtil.h"


#if MEMORY_CHECK
typedef struct GJRBufferDataHead{
    GJRetainBufferPool* pool;
    GLong size;
}GJRBufferDataHead;

typedef struct GJRBufferDataTail{
    GJRetainBufferPool* pool;
}GJRBufferDataTail;

GVoid GJBufferPoolCheck(GJBufferPool* pool,GUInt8* data);

static inline GVoid GJRetainbufferPoolCheck(GJRetainBufferPool* pool ,GJRetainBuffer* buffer){

    GUInt8* data = (GUInt8*)buffer;
    GJBufferPoolCheck(defauleBufferPool(), data - sizeof(GJRBufferDataHead));//检查buffer本身结构体内存
//    R_BufferMemCheck(buffer);//检查buffer所带的data的内存、此处可以不用检查，因为每次unretain的时候都会检查
    GJRBufferDataHead* head = (GJRBufferDataHead*)(data - sizeof(GJRBufferDataHead));
    GJRBufferDataTail* tail = (GJRBufferDataTail*)(data + head->size);
    GJAssert(head->pool == (GJRetainBufferPool*)R_BufferUserData(buffer) &&
             head->pool == pool &&
             head->pool == tail->pool, "该 buffer数据有误，不属于该bufferPool");
}
#endif

GBool GJRetainBufferPoolCreate(GJRetainBufferPool** pool,GUInt32 minSize,GBool atomic,R_MallocCallback callback,P_RecycleNoticeCallback noticeCallback ,GHandle noticeUserData){
    
    GJRetainBufferPool* p;
    if (*pool == NULL) {
        p = (GJRetainBufferPool*)malloc(sizeof(GJRetainBufferPool));
    }else{
        p = *pool;
    }
    if (!queueCreate(&p->queue, 5,atomic,GTrue)){
        free(p);
        return GFalse;
    }
    p->minSize = minSize;
    p->mallocCallback = callback;
    p->noticeCallback = noticeCallback;
    p->noticeUserData = noticeUserData;
    p->generateSize = 0;
    *pool = p;
    
#if MEMORY_CHECK
    if (!listQueueCreate(&p->leaveList, 5)){
        free(p);
        GJAssert(0, "跟踪器启动失败");
    }
#endif
    
    return GTrue;
};

static GBool retainFreeCallBack(GJRetainBuffer * buffer){
    R_BufferFreeData(buffer);
#if MEMORY_CHECK
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)buffer-sizeof(GJRBufferDataHead));
#else
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)buffer);
#endif
    return GTrue;
}

GBool GJRetainBufferPoolClean(GJRetainBufferPool* p,GBool complete){
    
    GJRetainBuffer* buffer = NULL;
    if (complete) {
        if (p->generateSize - queueGetLength(p->queue) > 0){
            GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "retainbuffer:%p,存在%d个buffer没有释放,会产生等待",p,p->generateSize - queueGetLength(p->queue));
        }
#ifdef DEBUG
        GLong startMS = GJ_Gettime().value;
#endif
        while (p->generateSize > 0) {
            if(queuePop(p->queue, (GVoid**)&buffer, GINT32_MAX)){
                R_BufferSetCallback(buffer, retainFreeCallBack);
                R_BufferUnRetain(buffer);
            }else{
                GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "GJRetainBufferPoolClean error:%p",p);
            }
            p->generateSize --;
        }
#ifdef DEBUG
        GLong dl = GJ_Gettime().value - startMS;
        if(dl > 1000){
            GJLOG(GNULL, GJ_LOGWARNING, "等待时间太久:%ld ms，需要检查",dl);
        }
#endif
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "GJRetainBufferPoolClean:%p 完成",p);
    }else{
        while (queuePop(p->queue,  (GVoid**)&buffer, 0)) {
            R_BufferSetCallback(buffer, retainFreeCallBack);
            R_BufferUnRetain(buffer);
        }
    }
    
#if MEMORY_CHECK
    if (complete) {
        GJAssert(listQueueLength(p->leaveList)==0, "跟踪器有误,还存在数据");
    }
#endif
    
    return GTrue;
};

GVoid GJRetainBufferPoolFree(GJRetainBufferPool* p){
    if (!p) {
        return ;
    }
    queueFree(&p->queue);
    
#if MEMORY_CHECK
    listQueueFree(&p->leaveList);
#endif
    
    free(p);
}

GBool GJRetainBufferPoolSetBuffer(GJRetainBufferPool* p,GJRetainBuffer* buffer){
    
    R_BufferClearFront(buffer);
    return queuePush(p->queue, buffer, 0);
}

static GBool retainReleaseCallBack(GJRetainBuffer * buffer){
    GJRetainBufferPool* pool = (GJRetainBufferPool*)R_BufferUserData(buffer);
    
#if MEMORY_CHECK
    GJRetainbufferPoolCheck(pool,buffer);
    listQueueDelete(pool->leaveList, buffer);
#endif
    
    if (pool->noticeCallback != GNULL) {
        pool->noticeCallback(buffer,pool->noticeUserData);
    }
    
//    重新复活时跟踪信息会更新
    R_BufferRelive(buffer);
    if (GJRetainBufferPoolSetBuffer(pool, buffer)) {
        return GTrue;
    }else{
        GJAssert(0,"不可能存在的问题出现啦\n");
        R_BufferSetCallback(buffer, retainFreeCallBack);
        R_BufferUnRetain(buffer);
        return GFalse;
    }
}

GJRetainBuffer* _GJRetainBufferPoolGetData(GJRetainBufferPool* p,const GChar* file,const GChar* func,GInt32 line){
    
    GJRetainBuffer* buffer = NULL;
    GInt32 structSize = R_BufferStructSize();
    if(p->mallocCallback ){
        structSize = p->mallocCallback(p);
    }
    
    if (!queuePop(p->queue, (GVoid**)&buffer, 0)) {
        
#if MEMORY_CHECK
        
        GUInt8* bufferM = _GJBufferPoolGetSizeData(defauleBufferPool(), structSize+sizeof(GJRBufferDataHead)+sizeof(GJRBufferDataTail),file,func,line);
        GJRBufferDataHead* head = (GJRBufferDataHead*)bufferM;
        head->pool = p;
        head->size = structSize;

        GJRBufferDataTail* tail = (GJRBufferDataTail*)(bufferM + sizeof(GJRBufferDataHead) + structSize);
        tail->pool = p;//bufferM结尾添加校验
        buffer =  (GJRetainBuffer*)(bufferM + sizeof(GJRBufferDataHead));

#else
        
        GUInt8* bufferM = GJBufferPoolGetSizeData(defauleBufferPool(), structSize );
        buffer =  (GJRetainBuffer*)bufferM;
#endif

        R_BufferAlloc(&buffer, p->minSize, retainReleaseCallBack, p);
        
        __sync_fetch_and_add(&p->generateSize,1);
    }
#if MEMORY_CHECK
    else{
        _GJBufferPoolUpdateTrackInfo(defauleBufferPool(),(GUInt8*)buffer - sizeof(GJRBufferDataHead),file,func,line);
    }
#endif
    R_BufferClearSize(buffer);

    GJAssert(R_BufferRetainCount(buffer) == 1, "retain 管理出错");
    
#if MEMORY_CHECK
    GJAssert(listQueuePush(p->leaveList, buffer), "跟踪器失败") ;
#endif
    return buffer;
}

GJRetainBuffer* _GJRetainBufferPoolGetSizeData(GJRetainBufferPool* p,GInt32 dataSize,const GChar* file,const GChar* func,GInt32 lineTracker){
    
    GJRetainBuffer* buffer = NULL;
    GJAssert(dataSize > p->minSize, "size 小于buffer大小");
    GInt32 structSize = R_BufferStructSize();
    if(p->mallocCallback ){
        structSize = p->mallocCallback(p);
    }
    if (!queuePop(p->queue, (GVoid**)&buffer, 0)) {
#if MEMORY_CHECK
        GUInt8* bufferM = _GJBufferPoolGetSizeData(defauleBufferPool(), structSize+sizeof(GJRBufferDataHead) + sizeof(GJRBufferDataTail),file, func, lineTracker);
        GJRBufferDataHead* head = (GJRBufferDataHead*)bufferM;
        head->pool = p;
        head->size = structSize;
        
        GJRBufferDataTail* tail = (GJRBufferDataTail*)(bufferM + sizeof(GJRBufferDataHead) + structSize);
        tail->pool = p;//bufferM结尾添加校验
        buffer =  (GJRetainBuffer*)(bufferM + sizeof(GJRBufferDataHead));
        
#else
        buffer = (GJRetainBuffer*)GJBufferPoolGetSizeData(defauleBufferPool(), structSize );
#endif
        R_BufferAlloc(&buffer, dataSize, retainReleaseCallBack, p);//最好此处内存别加检查，会影响capacity，每次unRetain 时，r_buffer会自己检查自己;

        __sync_fetch_and_add(&p->generateSize,1);
    }else{
        if (R_BufferCapacity(buffer) < dataSize) {
            
            R_BufferReCapacity(buffer, dataSize);
        }
#if MEMORY_CHECK
        _GJBufferPoolUpdateTrackInfo(defauleBufferPool(),(GUInt8*)buffer - sizeof(GJRBufferDataHead),file,func,lineTracker);
#endif
    }
    memset(buffer+1, 0, structSize - sizeof(GJRetainBuffer));//GJRetainBuffer后面的数据清零
    
    R_BufferClearSize(buffer);
    GJAssert(R_BufferRetainCount(buffer) == 1, "retain 管理出错");
#if MEMORY_CHECK
    GJAssert(listQueuePush(p->leaveList, buffer), "跟踪器失败") ;
#endif
    return buffer;
}

