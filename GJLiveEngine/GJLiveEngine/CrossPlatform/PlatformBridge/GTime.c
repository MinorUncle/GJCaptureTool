//
//  GTime.c
//  GJLiveEngine
//
//  Created by melot on 2018/6/4.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#include "GTime.h"
#import <sys/time.h>

GTime GInvalidTime = {0};


GTime GJ_Gettime() {
    
#ifdef CA_TIME
    return GTimeMake(CACurrentMediaTime() * 1000, 1000);
#else
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return GTimeMake(tv.tv_sec * 1000 + tv.tv_usec / 1000, 1000);
#endif
}

GLong getCurrentTime(){
#ifdef CA_TIME
    return CACurrentMediaTime() * 1000;
#else
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000 + tv.tv_usec / 1000;
#endif
}

GVoid GJ_GetTimeStr(GChar *dest) {
    struct tm *local;
    
    struct timeval t;
    gettimeofday(&t, NULL);
    local = localtime(&t.tv_sec);
    sprintf(dest, "[%02d:%02d:%02d:%03d]", local->tm_hour, local->tm_min, local->tm_sec, t.tv_usec / 1000);
}
