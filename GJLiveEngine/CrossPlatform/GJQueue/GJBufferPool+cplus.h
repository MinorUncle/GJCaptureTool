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
#include "GJPlatformHeader.h"

class GJBufferPool;
typedef struct GJBuffer{
private:
    GInt32 _capacity;//readOnly,real data size
public:
    GInt8* data;
    GInt32 size;
    GJBuffer(GInt8* bufferData,GInt32 bufferSize);
    GJBuffer();
    GInt32 capacity();
    friend GJBufferPool;
} GJBuffer;


class GJBufferPool {
private:
    GJQueue<GJBuffer*> _cacheQueue; //用指针，效率更高
public:
    GJBufferPool();//自己新建空间
    static GJBufferPool* defaultBufferPool();//共享的空间   //注意内存紧张时释放内存
    GJBuffer* getBuffer(GInt32 size);
    GVoid setBuffer(GJBuffer* buffer);
    GVoid cleanBuffer();
    ~GJBufferPool();
};

#endif /* GJBufferPool_h */
