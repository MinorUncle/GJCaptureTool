//
//  GTime.h
//  GJLiveEngine
//
//  Created by melot on 2018/6/4.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#ifndef GTime_h
#define GTime_h

#include <stdio.h>
#include "GJPlatformHeader.h"


typedef GInt64              GTimeValue;
typedef GInt32              GTimeScale;


typedef struct _TIME{
    GTimeValue    value;
    GTimeScale    scale;
}GTime;

static inline GTime GTimeMake(GTimeValue value, GTimeScale scale)
{
    GTime time; time.value = value; time.scale = scale; return time;
}

static inline GTime GTimeSubtract(GTime minuend, GTime subtrahend)
{
    GTime time; time.value = minuend.value - subtrahend.value*minuend.scale/subtrahend.scale;time.scale = minuend.scale; return time;
}

static inline GFloat64 GTimeSubtractSecondValue(GTime minuend, GTime subtrahend)
{
    return minuend.value*1.0/subtrahend.scale - subtrahend.value*1.0/subtrahend.scale;
}

static inline GLong GTimeSubtractMSValue(GTime minuend, GTime subtrahend)
{
    return (GLong)(minuend.value*1000/minuend.scale - subtrahend.value*1000/subtrahend.scale);
}

static inline GTime GTimeAdd(GTime addend1, GTime addend2)
{
    GTime time; time.value = addend1.value + addend2.value*addend1.scale/addend2.scale;time.scale = addend1.scale; return time;
}

static inline GFloat64 GTimeSencondValue(GTime time)
{
    return (GFloat64)time.value/time.scale;
}

static inline GLong GTimeMSValue(GTime time)
{
    return (GLong)(time.value*1000/time.scale);
}
//typedef int64_t             GTime;
extern GTime GInvalidTime;
//static inline GTime GInvalidTime()
//{
//    GTime time; time.value = time.scale = 0; return time;
//}

#define G_TIME_INVALID GInvalidTime
#define G_TIME_IS_INVALID(T)      ((T).scale == 0)


#endif /* GTime_h */
