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
GLong GJ_Gettime(){
#ifdef USE_CLOCK
    static clockd =  CLOCKS_PER_SEC /1000000 ;
    return clock() / clockd;
#endif
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long)tv.tv_sec * 1000000 + tv.tv_usec;
}
