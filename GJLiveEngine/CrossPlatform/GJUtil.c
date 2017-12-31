//
//  GJUtil.c
//  GJCaptureTool
//
//  Created by melot on 2017/5/11.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include <stdio.h>
#import <sys/time.h>
#include "GJUtil.h"
#include "GJLiveDefine+internal.h"

#define CA_TIME
#ifdef CA_TIME
#include <QuartzCore/CABase.h>
#endif
GTime GJ_Gettime(){
#ifdef USE_CLOCK
    static clockd =  CLOCKS_PER_SEC /1000000 ;
    return clock() / clockd;
#endif
#ifdef CA_TIME
    return GTimeMake(CACurrentMediaTime()*1000, 1000);

#endif
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return GTimeMake(tv.tv_sec * 1000 + tv.tv_usec/1000, 1000);
}
