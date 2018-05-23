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
/*
* |
*

*/

typedef struct GJRBufferDataTail{
    GJRetainBufferPool* pool;
}GJRBufferDataTail;

#if MENORY_CHECK
static inline GVoid GJRetainbufferPoolCheck(GJRetainBufferPool* pool ,GJRetainBuffer* buffer){
    
    R_BufferMemCheck(buffer);

    GLong* data = (GLong*)R_BufferEnd(buffer);
    GJAssert(data[-1] == (GLong)R_BufferUserData(buffer) && data[-1] == (GLong)pool, "该 buffer数据有误，不属于该bufferPool");
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
    
#if MENORY_CHECK
    if (!listCreate(&p->leaveList, 5)){
        free(p);
        GJAssert(0, "跟踪器启动失败");
    }
#endif
    
    return GTrue;
};

static GBool retainFreeCallBack(GJRetainBuffer * buffer){

#if MENORY_CHECK
//    GJRetainbufferPoolCheck()
#endif
    free(R_BufferOrigin(buffer));
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)buffer);
    return GTrue;
}

GBool GJRetainBufferPoolClean(GJRetainBufferPool* p,GBool complete){
    
    GJRetainBuffer* buffer = NULL;
    if (complete) {
        if (p->generateSize - queueGetLength(p->queue) > 0){
            GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "retainbuffer:%p,存在%d个buffer没有释放,会产生等待",p,p->generateSize - queueGetLength(p->queue));
        }
        while (p->generateSize > 0) {
            if(queuePop(p->queue, (GVoid**)&buffer, GINT32_MAX)){
                R_BufferSetCallback(buffer, retainFreeCallBack);
                R_BufferUnRetain(buffer);
            }else{
                GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "GJRetainBufferPoolClean error:%p",p);
            }
            p->generateSize --;
        }
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "GJRetainBufferPoolClean:%p 完成",p);
    }else{
        while (queuePop(p->queue,  (GVoid**)&buffer, 0)) {
            R_BufferSetCallback(buffer, retainFreeCallBack);
            R_BufferUnRetain(buffer);
        }
    }
    
#if MENORY_CHECK
    if (complete) {
        GJAssert(listLength(p->leaveList)==0, "跟踪器有误,还存在数据");
    }
#endif
    
    return GTrue;
};

GVoid GJRetainBufferPoolFree(GJRetainBufferPool* p){
    if (!p) {
        return ;
    }
    queueFree(&p->queue);
    
#if MENORY_CHECK
    listFree(&p->leaveList);
#endif
    
    free(p);
}

GBool GJRetainBufferPoolSetBuffer(GJRetainBufferPool* p,GJRetainBuffer* buffer){
    
    R_BufferClearFront(buffer);
    return queuePush(p->queue, buffer, 0);
}

static GBool retainReleaseCallBack(GJRetainBuffer * buffer){
    GJRetainBufferPool* pool = (GJRetainBufferPool*)R_BufferUserData(buffer);
    
#if MENORY_CHECK
    GJRetainbufferPoolCheck(pool,buffer);
    listDelete(pool->leaveList, buffer);
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
    if (!queuePop(p->queue, (GVoid**)&buffer, 0)) {
        
        GInt32 size = R_BufferStructSize();
        if(p->mallocCallback ){
            size = p->mallocCallback(p);
        }
        
#if MENORY_CHECK
        
        GUInt8* bufferM = _GJBufferPoolGetSizeData(defauleBufferPool(), size+sizeof(GJRBufferDataTail),file,func,line);
        GJRBufferDataTail* tail = (GJRBufferDataTail*)(bufferM + size);
        tail->pool = p;//bufferM结尾添加校验
        buffer =  (GJRetainBuffer*)bufferM;
#else
        
        GUInt8* bufferM = GJBufferPoolGetSizeData(defauleBufferPool(), size );
        buffer =  (GJRetainBuffer*)bufferM;
#endif

#if MENORY_CHECK
        
        R_BufferAlloc(&buffer, p->minSize+sizeof(GJRBufferDataTail), retainReleaseCallBack, p);
        tail = (GJRBufferDataTail*)R_BufferEnd(buffer) - 1;//data结尾添加校验
        tail->pool = p;
#else
        
        R_BufferAlloc(&buffer, p->minSize, retainReleaseCallBack, p);
#endif
        
        __sync_fetch_and_add(&p->generateSize,1);
    }
    R_BufferClearSize(buffer);

    GJAssert(R_BufferRetainCount(buffer) == 1, "retain 管理出错");
    
#if MENORY_CHECK
    GJAssert(listPush(p->leaveList, buffer), "跟踪器失败") ;
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
#if MENORY_CHECK
        GUInt8* bufferM = _GJBufferPoolGetSizeData(defauleBufferPool(), structSize+sizeof(GJRBufferDataTail),file, func, lineTracker);
        GJRBufferDataTail* tail = (GJRBufferDataTail*)(bufferM + structSize);
        tail->pool = p;//bufferM结尾添加校验
        buffer =  (GJRetainBuffer*)bufferM;
        
        R_BufferAlloc(&buffer, dataSize+sizeof(GJRBufferDataTail), retainReleaseCallBack, p);
        tail = (GJRBufferDataTail*)R_BufferEnd(buffer) - 1;//data结尾添加校验//不能加到前面，因为GJRetainBuffer有frontSize固定了前面的位置
        tail->pool = p;
#else
        buffer = (GJRetainBuffer*)GJBufferPoolGetSizeData(defauleBufferPool(), structSize );
        
        R_BufferAlloc(&buffer, dataSize, retainReleaseCallBack, p);
#endif
        
        __sync_fetch_and_add(&p->generateSize,1);
    }else{
        if (R_BufferCapacity(buffer) < dataSize + sizeof(GJRBufferDataTail)) {
            
            R_BufferReCapacity(buffer, dataSize+sizeof(GJRBufferDataTail));
#if MENORY_CHECK
            
            GJRBufferDataTail* tail = (GJRBufferDataTail*)R_BufferEnd(buffer);
            tail[-1].pool = p;
#endif
        }
    }
    memset(buffer+1, 0, structSize - sizeof(GJRetainBuffer));//GJRetainBuffer后面的数据清零
    R_BufferClearSize(buffer);
    GJAssert(R_BufferRetainCount(buffer) == 1, "retain 管理出错");
#if MENORY_CHECK
    GJAssert(listPush(p->leaveList, buffer), "跟踪器失败") ;
#endif
    return buffer;
}

