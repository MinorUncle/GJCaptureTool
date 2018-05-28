//
//  GJRetainBuffer.c
//  GJQueue
//
//  Created by mac on 17/2/22.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRetainBuffer.h"
#include "GJLog.h"


//struct _GJRetainBuffer{
//    GInt32 capacity; //data之后的实际内存大小
//    GInt32 size;      //data之后的实际使用内存大小，剩下之后的一定没有使用
//    GInt32 frontSize; //data之前的内存,所以外部释放时一定要注意free((char*)data-frontSize);
//    GInt32 retainCount;
//    GUInt8* data;
//#if MEMORY_CHECK
//    GBool needCheck;
//#endif
//    RetainReleaseCallBack retainReleaseCallBack;
//    GVoid *parm;
//};


#if MEMORY_CHECK
inline GVoid R_BufferMemCheck(GJRetainBuffer* buffer){
    if (buffer->needCheck) {
        GLong* data = (GLong*)(buffer->data-buffer->frontSize);
        GLong* tailData = (GLong*)(buffer->data+buffer->capacity);
        GLong size = buffer->capacity + buffer->frontSize;
        GJAssert(data[-1] == size &&
                 tailData[0] == data[-1] &&//此处的size检查实际上是malloc中的size数据
                 buffer->capacity < 60000 &&
                 buffer->size <= buffer->capacity, "数据存在错误");
    }
}
#endif

GVoid R_BufferAlloc(GJRetainBuffer**pBuffer, GInt32 size,GBool (*releaseCallBack)(GJRetainBuffer* data),GVoid* parm ){
    if (*pBuffer == NULL) {
        *pBuffer = (GJRetainBuffer*)malloc(sizeof(GJRetainBuffer));
        memset(*pBuffer, 0, sizeof(GJRetainBuffer));
    }
    GJRetainBuffer* buffer = *pBuffer;
    buffer->capacity = size;
    buffer->size = 0;
    buffer->data = malloc(size);

    //malloc已经有了检查，所以不需要重复添加检查数据。
#if MEMORY_CHECK
    buffer->needCheck = GTrue;
    buffer->retainList = buffer->unretainList = GNULL;
#endif
    buffer->frontSize = 0;
    buffer->retainReleaseCallBack = releaseCallBack;
    buffer->parm = parm;
    buffer->retainCount = 0;
    R_BufferRelive(buffer);
};

GVoid R_BufferPack(GJRetainBuffer**pBuffer, GVoid* sourceData, GInt32 size,GBool (*releaseCallBack)(GJRetainBuffer* data),GVoid* parm){
    if (*pBuffer == NULL) {
        *pBuffer = (GJRetainBuffer*)malloc(sizeof(GJRetainBuffer));
    }
    GJRetainBuffer* buffer = *pBuffer;
    buffer->capacity = size;
    buffer->size = 0;
#if MEMORY_CHECK
    GJAssert(0, "MEMORY_CHECK状态，请尽量避免该方法");
    buffer->needCheck = GFalse;
    buffer->retainList = buffer->unretainList = GNULL;
#endif
    buffer->data = sourceData;
    buffer->frontSize = 0;
    buffer->retainCount = 0;
    buffer->retainReleaseCallBack = releaseCallBack;
    buffer->parm = parm;
    R_BufferRelive(buffer);
}
GVoid R_BufferUnRetainUnTrack(GHandle buffer){
    R_BufferUnRetain(buffer);
}

GVoid _R_BufferUnRetain(GJRetainBuffer* buffer,const GChar* tracker){
#if MEMORY_CHECK
    R_BufferMemCheck(buffer);
    GJAssert(buffer->retainCount > 0, "retain 管理出错");
    
    listPush(buffer->unretainList, (GHandle)tracker);
#endif
    
    if (__sync_fetch_and_add(&buffer->retainCount,-1) <= 1) {//count是减一之前的值，，当连续unretain的时候，第一个unretain到达此的时候，第二个刚走完__sync_fetch_and_add，容易引起第一个先进入count的情况。所以修改为返回结果直接判断
#if MEMORY_CHECK
        GJAssert(listLength(buffer->unretainList) == listLength(buffer->retainList), "释放的个数与引用的个数不相等");
        listClean(buffer->retainList, GNULL, GNULL);
        listClean(buffer->unretainList, GNULL, GNULL);
        listFree(&buffer->retainList);
        listFree(&buffer->unretainList);
#endif

        if (buffer->retainReleaseCallBack) {
            if (!buffer->retainReleaseCallBack(buffer)) {
                free(buffer);
            }
        }else{
            GLong* data = (GLong*)(buffer->data - buffer->frontSize);
            free(data);
            free(buffer);
        }
    }
}

GVoid R_BufferFreeData(GJRetainBuffer* buffer){
    GLong* data = (GLong*)(buffer->data - buffer->frontSize);
#if MEMORY_CHECK
    R_BufferMemCheck(buffer);
#endif
    free(data);
}

GBool R_BufferMoveDataPoint(GJRetainBuffer* buffer,GInt32 offset,GBool keepMem){
    if (buffer->frontSize + offset < 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "可移动位置小于移动位置");
        return GFalse;
    }
    GUInt32 frontSize = buffer->frontSize + offset;
    return R_BufferMoveDataToPoint(buffer, frontSize, keepMem);
}

GVoid R_BufferReCapacity(GJRetainBuffer* buffer,GInt32 size){
    if (buffer->capacity < size) {//保持frontSize大小，但是不保证内存不变
        
#if MEMORY_CHECK
        R_BufferMemCheck(buffer);
#endif
        buffer->data = (GUInt8*)realloc(R_BufferOrigin(buffer), size + buffer->frontSize) + buffer->frontSize;
        buffer->capacity = size;
    }
}

GBool R_BufferMoveDataToPoint(GJRetainBuffer* buffer,GUInt32 frontSize,GBool keepMem){

    if (!keepMem) {
        if(buffer->frontSize + buffer->capacity < frontSize){
            GJLOG(DEFAULT_LOG, GJ_LOGERROR, "配置的forntSize 超出范围");
            return GFalse;
        }
        buffer->size = buffer->size -(frontSize - buffer->frontSize) ;
        if (buffer->size<0) {
            buffer->size = 0;
        }
        buffer->data = buffer->data-buffer->frontSize+frontSize;
        buffer->capacity = buffer->capacity + buffer->frontSize - frontSize;
        buffer->frontSize = frontSize;
#if MEMORY_CHECK
        R_BufferMemCheck(buffer);
#endif
        return GTrue;
    }else{
#if MEMORY_CHECK
        GJAssert(0, "MEMORY_CHECK 状态下不能尝试内存重新申请，");
#endif
        GInt32 canOffset = buffer->capacity - buffer->size +buffer->frontSize;
        if (canOffset >= frontSize) {//可以移动则直接移动
            GJLOG(DEFAULT_LOG, GJ_LOGINFO,"move frome:%p,to:%p,size:%d currentForntSize:%d  needForntSize:%d \n ",buffer->data+buffer->frontSize,buffer->data - buffer->frontSize + frontSize,buffer->size,buffer->frontSize,frontSize);
            memmove(buffer->data - 2*buffer->frontSize + frontSize, buffer->data-buffer->frontSize, buffer->size+buffer->frontSize);
            buffer->data = buffer->data -  buffer->frontSize + frontSize;
            buffer->capacity -= frontSize -  buffer->frontSize;
            buffer->frontSize = frontSize;
        }else{//否则直接扩大内存
            GJLOG(DEFAULT_LOG, GJ_LOGINFO,"move reduce realloc\n");
            
            GInt32 needSize = buffer->capacity+buffer->frontSize+frontSize-canOffset;
            GUInt8* temData = (GUInt8*)realloc(buffer->data-buffer->frontSize, needSize);
            //        frontMem也复制过去。size之后，capacity之前的未使用内存被使用完
            memmove(temData+frontSize-buffer->frontSize, temData, buffer->size+buffer->frontSize);
            buffer->data = temData+frontSize;
            buffer->frontSize = frontSize;
            buffer->capacity = buffer->size;
        }
        return GTrue;
    }
}

GInt32  R_BufferStructSize(){
    return sizeof(GJRetainBuffer);
}

#if 0

GUInt8* R_BufferOrigin(GJRetainBuffer* buffer){
#if MEMORY_CHECK
    return buffer->data-buffer->frontSize-sizeof(GLong);
#else
    return buffer->data-buffer->frontSize;
#endif
}

GUInt8* R_BufferStart(GJRetainBuffer* buffer){
    return buffer->data;
}

GUInt8* R_BufferCurrent(GJRetainBuffer* buffer){
    return buffer->data+buffer->size;
}

GUInt8* R_BufferEnd(GJRetainBuffer* buffer){
    return buffer->data+buffer->capacity;
}

GVoid R_BufferSetSize(GJRetainBuffer* buffer,GInt32 size){
    buffer->size = size;
}

GInt32 R_BufferSize(GJRetainBuffer* buffer){
    return buffer->size;
}

GInt32 R_BufferFrontSize(GJRetainBuffer* buffer){
    return buffer->frontSize;
}

GInt32 R_BufferCapacity(GJRetainBuffer* buffer){
    return buffer->capacity;
}

GInt32  R_BufferRetainCount(GJRetainBuffer* buffer){
    return buffer->retainCount;
}

GHandle  R_BufferUserData(GJRetainBuffer* buffer){
    return buffer->parm;
}

GVoid R_BufferSetCallback(GJRetainBuffer* buffer,RetainReleaseCallBack callback){
    buffer->retainReleaseCallBack = callback;
}

GVoid  R_BufferWrite(GJRetainBuffer* buffer,GUInt8* data,GInt32 size){
    memcpy(buffer->data, data, size);
    buffer->size = size;
}

GVoid  R_BufferWriteAppend(GJRetainBuffer* buffer,GUInt8* data,GInt32 size){
    memcpy(buffer->data+buffer->size, data, size);
    buffer->size += size;
    
}

GVoid  R_BufferEraseOut(GJRetainBuffer* buffer,GUInt8* data,GInt32 size){
    memcpy(data, buffer->data+buffer->size-size, size);
    buffer->size -= size;
}

GVoid R_BufferClearFront(GJRetainBuffer* buffer){
    if (buffer->frontSize>0) {
        buffer->data = buffer->data-buffer->frontSize;
        buffer->capacity = buffer->capacity + buffer->frontSize;
        buffer->frontSize = 0;
    }
    buffer->size = 0;
}

GVoid R_BufferRetain(GJRetainBuffer* buffer){
    __sync_fetch_and_add(&buffer->retainCount,1);
}

#endif
