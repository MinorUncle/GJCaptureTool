//
//  GJBufferPool.h
//  GJQueue
//
//  Created by 未成年大叔 on 16/11/7.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#ifndef GJBufferPool_h
#define GJBufferPool_h

#include "GJQueue.h"
#include <string>

struct GJBufferPool;

typedef struct GJBuffer{
public:
    uint8_t* data(){return _data;};
    long length(){return _length;}
    GJBuffer(long length){if(length<0){_length=0;_data=NULL;return;}; _data=(uint8_t*)malloc(length);_length=length;}
    GJBuffer(){_data=NULL;_length=0;}
protected:
    uint8_t* _data;
    long _length;
    ~GJBuffer(){if(_data)free(_data);}
}GJBuffer;

struct GJPoolBuffer:GJBuffer{
public:
    GJPoolBuffer(long length):GJBuffer(length){_caputureSize=_length;}
    long caputreSize(){return _caputureSize;}
    bool setLength(long length){if(length<=_caputureSize){_length=length;return true;}else return false;}
    bool resizeCapture(long caputre,bool copy);
private:
    long _caputureSize;//申请空间的大小
    friend GJBufferPool;
};

typedef struct GJPoolBuffer GJPoolBuffer;

typedef struct GJBufferPool{
public:
    GJBufferPool(long suitableBufferSize, int size);
    GJBufferPool(){_init();};
    GJPoolBuffer* get(long size);
    void put(GJPoolBuffer* buffer);
    int availableNum(){return _queue.currentLenth();}
    ~GJBufferPool();
private:
    void _init();
    GJQueue<GJPoolBuffer*> _queue;
    int _numElem;
    
}GJBufferPool;



#endif /* GJBufferPool_h */
