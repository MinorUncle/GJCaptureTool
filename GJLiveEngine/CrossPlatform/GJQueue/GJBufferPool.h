//
//  GJBufferPool.h
//  GJQueue
//
//  Created by 未成年大叔 on 16/12/28.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#ifndef GJBufferPool_h
#define GJBufferPool_h
#include "GJQueue.h"
#include <stdio.h>
#include "GJPlatformHeader.h"

/* exploit C++ ability of default values for function parameters */


#ifdef __cplusplus
extern "C" {
#endif
    
    typedef struct _GJBufferPool GJBufferPool;

    GBool GJBufferPoolCreate(GJBufferPool** pool,GUInt32 minSize,GBool atomic);
    
    //小数据最好多用默认的，大数据最好不要用默认的
    GJBufferPool* defauleBufferPool(void);
    
    GVoid GJBufferPoolFree(GJBufferPool* pool);

    /**
     清除内容，当complete为yes时表示彻底清除，可能会产生阻塞等待,所以不要在主线程执行，除非你明确知道后果

     @param p           p description
     @param complete    是否彻底清除
     */
    GVoid GJBufferPoolClean(GJBufferPool* p,GBool complete);
    
    /**
     获取minSize大小的数据

     @param p           p description
     @return return     value description
     */
    GUInt8* GJBufferPoolGetData(GJBufferPool* p,const GChar* func DEFAULT_PARAM(GNull), GInt32 lineTracker);
    
    
    /**
     获取size大小的数据，size一定要大于minsize

     @param p           p description
     @param size        size description
     @return return     value description
     */
#define GJBufferPoolGetSizeData(x,y) _GJBufferPoolGetSizeData(x,y,__FILE__,__func__, __LINE__)
    GUInt8* _GJBufferPoolGetSizeData(GJBufferPool* p,GInt32 size,const GChar* file  DEFAULT_PARAM(GNull),const GChar* func  DEFAULT_PARAM(GNull), GInt32 lineTrac DEFAULT_PARAM(0));
    
    GBool GJBufferPoolSetData(GJBufferPool* p,GUInt8* data);
#ifdef __cplusplus
}
#endif

#endif /* GJBufferPool_h */
