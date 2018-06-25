//
//  GJListQueue.h
//  GJQueue
//
//  Created by 未成年大叔 on 2017/8/26.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJListQueue_h
#define GJListQueue_h

#include <stdio.h>
#include "GJPlatformHeader.h"
typedef struct _GJListQueue GJListQueue;

typedef GBool (*listQueueSwopFunc)(GHandle up, GHandle down, GBool* stop);

//创建一个GJListQueue*
GBool   listQueueCreate(GJListQueue** outQ,GBool atomic DEFAULT_PARAM(GTrue));
GBool   listQueueFree(GJListQueue** inQ);

/**
 入链,高位进，低位出

 @param list q description
 @param temBuffer temBuffer description
 //等待时间，只有链表满了才会等待，只有设置了limit才会满。(暂时没有需求，为了效率没有实现。)
 @return return value description
 */
GBool   listQueuePush(GJListQueue* list,GHandle temBuffer);

GBool   listQueuePop(GJListQueue* list,GHandle* temBuffer,GUInt32 ms DEFAULT_PARAM(0));
GBool   listQueueDelete(GJListQueue* list,GHandle temBuffer);

/**
 清除，并返回数据.
 outBuffer == GNULL && outCount == GNULL,表示丢弃数据，释放list。
 outBuffer == GNULL && outCount != GNULL,只返回list长度
 outBuffer != GNULL && outCount != GNULL,复制数据到outBuffer，返回长度到outCount

 @param list list description
 @param outBuffer 接收list中数据的内存，如果为NULL则直接丢弃
 @param outCount outCount description
 @return return value description
 */
GBool   listQueueClean(GJListQueue* list, GHandle* outBuffer,GInt32* outCount);
GVoid   listQueueEnablePush(GJListQueue* list,GBool enable);
GVoid   listQueueEnablePop(GJListQueue* list,GBool enable);
/**
一次冒泡交换。

 @param list list description
 @param order 是否从第一个开始顺序交换，否则从最后一个逆序交换
 @param func 每次交换的回调，不能为空
 @return 是否执行交换操作
 */
GBool listQueueSwop(GJListQueue* list, GBool order, listQueueSwopFunc func);

//最多能存储的上限
//GVoid   listSetLimit(GJListQueue* list,GInt32 limit);//(暂时没有需求，为了效率没有实现。)


GInt32  listQueueLength(GJListQueue* list);

#if MEMORY_CHECK
GInt32 listQueueGenerateSize(GJListQueue* list);
#endif

#endif /* GJListQueue_h */
