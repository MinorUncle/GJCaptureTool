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

//默认信号是非设置状态,wait不会等待
GBool signalCreate(GJSignal** signal);

//表示信号重置状态，wait会阻塞到下一次signal或者超时
GVoid signalReset(GJSignal* signal);
GBool signalWait(GJSignal* signal,GUInt32 ms);
//触发信号，同时信号为触发状态，wait不会阻塞
GVoid signalEmit(GJSignal* signal);
GVoid signalDestory(GJSignal** signal);
#endif /* GJSignal_h */
