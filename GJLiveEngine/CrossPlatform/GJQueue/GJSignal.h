//
//  GJSignal.h
//  GJQueue
//
//  Created by melot on 2018/4/11.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#ifndef GJSignal_h
#define GJSignal_h

#include <stdio.h>
#include "GJPlatformHeader.h"
typedef struct _GJSignal GJSignal;

/**
 默认信号是非设置状态,wait不会等待

 @param signal signal description
 @return return value description
 */
GBool signalCreate(GJSignal **signal);

/**
 表示信号重置状态，wait会阻塞到下一次signal或者超时
 
 @param signal signal description
 */
GVoid signalReset(GJSignal *signal);

/**
 如果是Reset状态，则阻塞等待signalEmit触发，否则不等待

 @param signal signal description
 @param ms ms description
 @return false表示等待超时，否则表示不是Reset状态或者已经触发了signal，
 */
GBool signalWait(GJSignal *signal, GUInt32 ms);

/**
 触发信号，同时信号为触发状态，之后的wait不会阻塞，需要重新reset

 @param signal signal description
 */
GVoid signalEmit(GJSignal* signal);


/**
 销毁不支持多线程所以需要确保没有使用再销毁。

 @param signal signal description
 */
GVoid signalDestory(GJSignal** signal);
#endif /* GJSignal_h */
