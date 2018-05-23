//
//  GJSignal.c
//  GJQueue
//
//  Created by melot on 2018/4/11.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#include "GJSignal.h"
#include "GJPlatformHeader.h"
#include <sys/time.h>
#include <assert.h>
#include <pthread.h>
#include "GMemCheck.h"

struct _GJSignal{
    pthread_cond_t cond;
    pthread_mutex_t lock;
    GBool reset;//signal 为true时表示需要阻塞wait，为false时不会wait。signal每次会置false;
};
GBool signalCreate(GJSignal** pSignal){
    assert(pSignal != GNULL && *pSignal == GNULL);
    GJSignal* signal = (GJSignal*)calloc(1,sizeof(GJSignal));
    pthread_condattr_t cond_attr;
    pthread_condattr_init(&cond_attr);
    pthread_cond_init(&signal->cond, &cond_attr);
    pthread_mutex_init(&signal->lock, NULL);
    signal->reset = GFalse;
    *pSignal = signal;
    return GTrue;
    
}

GBool signalWait(GJSignal* signal,GUInt32 ms){
    GInt32 ret = 0;
    pthread_mutex_lock(&signal->lock);
    if (signal->reset == GFalse) {
        pthread_mutex_unlock(&signal->lock);
        return GTrue;
    }
    struct timespec ts;
    struct timeval tv;
    
    //    gettimeofday(&tv, GNULL);
    //    GInt32 tu = ms%1000 * 1000 + tv.tv_usec;
    //    ts.tv_sec = tv.tv_sec + ms/1000 + tu / 1000000;
    //    ts.tv_nsec = tu % 1000000 * 1000;
    
    int sec, usec;
    gettimeofday(&tv, GNULL);
    sec = ms / 1000;
    ms = ms - (sec * 1000);
    assert(ms < 1000);
    usec = ms * 1000;
    assert(tv.tv_usec < 1000000);
    ts.tv_sec = tv.tv_sec + sec;
    ts.tv_nsec = (tv.tv_usec + usec) * 1000;
    assert(ts.tv_nsec < 2000000000);
    if(ts.tv_nsec > 999999999)
    {
        ts.tv_sec++;
        ts.tv_nsec -= 1000000000;
    }
    
    ret = pthread_cond_timedwait(&signal->cond, &signal->lock, &ts);
    pthread_mutex_unlock(&signal->lock);
    return ret==0;
}
GVoid signalEmit(GJSignal* signal){
    pthread_mutex_lock(&signal->lock);
    signal->reset = GFalse;
    pthread_cond_broadcast(&signal->cond);
    pthread_mutex_unlock(&signal->lock);
}
GVoid signalReset(GJSignal* signal){
    pthread_mutex_lock(&signal->lock);
    signal->reset = GTrue;
    pthread_mutex_unlock(&signal->lock);
}

GVoid signalDestory(GJSignal** pSignal){
    assert(pSignal != GNULL && *pSignal != GNULL);
    GJSignal* signal = *pSignal;
    pthread_cond_destroy(&signal->cond);
    pthread_mutex_destroy(&signal->lock);
    free((void*)signal);
    *pSignal = GNULL;
}

