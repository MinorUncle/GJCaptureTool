//
//  GJBufferPool.c
//  GJQueue
//
//  Created by 未成年大叔 on 16/11/7.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#include "GJBufferPool+cplus.h"
#include "GJPlatformHeader.h"

GJBuffer::GJBuffer(GInt8* bufferData,GInt32 bufferSize){
    static GInt32 i = 0;
    printf("GJBuffer count:%d\n",++i);
    data = bufferData;
    size = _capacity = bufferSize;
}
GJBuffer::GJBuffer(){
    data = NULL;
    size = _capacity = 0;
}
GInt32 GJBuffer::capacity(){
    return _capacity;
}

GJBufferPool::GJBufferPool(){
    _cacheQueue.autoResize = GTrue;
}
GJBufferPool::~GJBufferPool(){
    cleanBuffer();
}
GJBufferPool* GJBufferPool::defaultBufferPool()
{
    static GJBufferPool* _defaultPool = new GJBufferPool();
    return _defaultPool;
}

GJBuffer* GJBufferPool::getBuffer(GInt32 size){
    static GInt32 mc = 0;
    GJBuffer* buffer = NULL;
    if(_cacheQueue.queuePop(&buffer,0)) {
        if (buffer->_capacity < size) {
            free(buffer->data);
            buffer->data = (GInt8*)malloc(size);
            printf("malloc GJBuffer0 count:%d\n",++mc);
            
            buffer->size = buffer->_capacity = size;
        }else{
            buffer->size = size;
        }
    }
    if (!buffer) {
        buffer = new GJBuffer((GInt8*)malloc(size),size);
        printf("malloc GJBuffer count:%d\n",++mc);
    }
    return buffer;
}

GVoid GJBufferPool::setBuffer(GJBuffer* buffer){
    _cacheQueue.queuePush(buffer,0);
}
GVoid GJBufferPool::cleanBuffer(){
    GJBuffer* buffer;
    while (_cacheQueue.queuePop(&buffer)) {
        free(buffer->data);
        free(buffer);
    }
    _cacheQueue.clean();
}

