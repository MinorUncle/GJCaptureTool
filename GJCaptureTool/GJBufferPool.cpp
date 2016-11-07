//
//  GJBufferPool.c
//  GJQueue
//
//  Created by 未成年大叔 on 16/11/7.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#include "GJBufferPool.h"
bool GJPoolBuffer::resizeCapture(long caputre,bool copy){
    if(caputre<0 || caputre < _length)return false;
    GJQueueLOG("resizefrome%ld to %ld\n",_caputureSize,caputre);
    uint8_t* temp = (uint8_t*)malloc(caputre);
    if(temp == NULL)return false;
    if (copy) {
        memcpy(temp, _data, _length);
    }
    free(_data);
    _data=temp;
    _caputureSize=caputre;
    return true;
}



void GJBufferPool::_init(){
    _queue.autoResize=true;
    _queue.shouldWait=false;
    _queue.shouldNonatomic=true;
    _numElem=0;
}
#define DEFAULT_POOL_BUFFER_SIZE 10
GJBufferPool::GJBufferPool(long suitableBufferSize, int size){
    _init();
    if (size <= 0) {return;}
    if (suitableBufferSize<=0) {   suitableBufferSize=10;    }
    for (int i =0; i<size; i++) {
        GJPoolBuffer* buffer = new GJPoolBuffer(suitableBufferSize);
        _queue.queuePush(buffer);
    }
    
};
GJPoolBuffer* GJBufferPool::get(long size){
    GJPoolBuffer* buffer=NULL;
    if (_queue.queuePop(&buffer)) {
        if (buffer->caputreSize()<size) {
            free(buffer->data());
            buffer->_data=(uint8_t*)malloc(size);
            buffer->_caputureSize=size;
        }
        buffer->setLength(size);
    }else{
        buffer = new GJPoolBuffer(size);
    }
    return buffer;
};
void GJBufferPool::put(GJPoolBuffer* buffer){
    _queue.queuePush(buffer);
};
GJBufferPool::~GJBufferPool(){
    GJPoolBuffer* buffer;
    while (_queue.queuePop(&buffer)) {
        free(buffer);
    }
}
