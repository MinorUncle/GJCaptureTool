//
//  GJBufferPool.h
//  GJQueue
//
//  Created by 未成年大叔 on 16/11/7.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#ifndef GJBufferPool_cplus_h
#define GJBufferPool_cplus_h

#import "GJQueue+cplus.h"

class GJBufferPool;
typedef struct GJBuffer{
private:
    int _capacity;//readOnly,real data size
public:
    void* data;
    int size;
    GJBuffer(int8_t* bufferData,int bufferSize);
    GJBuffer();
    int capacity();
    friend GJBufferPool;
} GJBuffer;


class GJBufferPool {
private:
    GJQueue<GJBuffer*> _cacheQueue; //用指针，效率更高
public:
    GJBufferPool();//自己新建空间
    static GJBufferPool* defaultBufferPool();//共享的空间   //注意内存紧张时释放内存
    GJBuffer* getBuffer(int size);
    void setBuffer(GJBuffer* buffer);
    void cleanBuffer();
    ~GJBufferPool();
};

#endif /* GJBufferPool_h */
