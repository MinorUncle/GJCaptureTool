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
#include <sys/sysctl.h>
#include <mach/mach_host.h>
#include <mach/mach.h>

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


GInt32 GJ_GetCPUCount(){
    GInt32 mib[2U] = { CTL_HW, HW_NCPU };
    GInt32 numCPUs;
    size_t sizeOfNumCPUs = sizeof(numCPUs);
    GInt32 status = sysctl(mib, 2U, &numCPUs, &sizeOfNumCPUs, NULL, 0U);
    if(status)return 1;
    return numCPUs;
}
GFloat32 GJ_GetCPUUsage(){
    kern_return_t kr;
        task_info_data_t tinfo;
        mach_msg_type_number_t task_info_count;
    
        task_info_count = TASK_INFO_MAX;
        kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)tinfo, &task_info_count);
        if (kr != KERN_SUCCESS) {
            return -1;
        }
    
        task_basic_info_t      basic_info;
        thread_array_t         thread_list;
        mach_msg_type_number_t thread_count;
    
        thread_info_data_t     thinfo;
        mach_msg_type_number_t thread_info_count;
    
        thread_basic_info_t basic_info_th;
        uint32_t stat_thread = 0; // Mach threads
    
        basic_info = (task_basic_info_t)tinfo;
    
        // get threads in the task
        kr = task_threads(mach_task_self(), &thread_list, &thread_count);
        if (kr != KERN_SUCCESS) {
            return -1;
        }
        if (thread_count > 0)
            stat_thread += thread_count;
    
        long tot_sec = 0;
        long tot_usec = 0;
        float tot_cpu = 0;
        GInt32 j;
    
        for (j = 0; j < thread_count; j++)
        {
            thread_info_count = THREAD_INFO_MAX;
            kr = thread_info(thread_list[j], THREAD_BASIC_INFO,
                             (thread_info_t)thinfo, &thread_info_count);
            if (kr != KERN_SUCCESS) {
                return -1;
            }
    
            basic_info_th = (thread_basic_info_t)thinfo;
    
            if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
                tot_sec = tot_sec + basic_info_th->user_time.seconds + basic_info_th->system_time.seconds;
                tot_usec = tot_usec + basic_info_th->system_time.microseconds + basic_info_th->system_time.microseconds;
                tot_cpu = tot_cpu + basic_info_th->cpu_usage / (float)TH_USAGE_SCALE * 100.0;
            }
    
        } // for each thread
    
        kr = vm_deallocate(mach_task_self(), (vm_offset_t)thread_list, thread_count * sizeof(thread_t));
        assert(kr == KERN_SUCCESS);
    
        return tot_cpu;
}

//GFloat32 GJ_GetCPUUsage(){
//natural_t numCPUsU = 0U;
//kern_return_t err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo);
//float useTotal = 0;
//if(err == KERN_SUCCESS) {
//    [CPUUsageLock lock];
//    for(unsigned i = 0U; i < numCPUs; ++i) {
//        float inUse, total;
//        if(prevCpuInfo) {
//            inUse = (
//                     (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER])
//                     + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM])
//                     + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE])
//                     );
//            total = inUse + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE]);
//        } else {
//            inUse = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
//            total = inUse + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];
//        }
//        useTotal += inUse / total;
//        NSLog(@"Core: %u Usage: %f",i,inUse / total);
//    }
//    //        NSLog(@"avg usage:%f memory:%f",useTotal / numCPUs,[self GetCurrentTaskUsedMemory]);
//    [CPUUsageLock unlock];
//
//    if(prevCpuInfo) {
//        size_t prevCpuInfoSize = sizeof(integer_t) * numPrevCpuInfo;
//        vm_deallocate(mach_task_self(), (vm_address_t)prevCpuInfo, prevCpuInfoSize);
//    }
//
//    prevCpuInfo = cpuInfo;
//    numPrevCpuInfo = numCpuInfo;
//
//    cpuInfo = NULL;
//    numCpuInfo = 0U;
//
//} else {
//    NSLog(@"Error!");
//    [updateTimer invalidate];
//}
//useTotal / numCPUs;
//}



#define SAMPLERATE_LEN 13

const GUInt32 adtsFrequency[SAMPLERATE_LEN] = {96000,88200,64000,48000,44100,32000,24000,22050,16000,12000,11025,8000,7350};



GInt32 writeADTS(GUInt8* buffer,GUInt8 size,const ADTS* adts){
    if (size < 7 || adts == GNULL) {
        return GFalse;
    }
    GInt8 frequencyIndex = -1;
    for (GUInt8 i = 0; i< SAMPLERATE_LEN; i++) {
        if (adtsFrequency[i] == adts->sampleRate) {
            frequencyIndex = i;
            break;
        }
    }
    if (frequencyIndex < 0) {
        return GFalse;
    }
    GUInt8 profile = adts->profile - 1;
    GUInt16 fullLength = adts->varHeader.aac_frame_length + 7;
    buffer[0]                = (char) 0xFF;                                                 // 11111111      = syncword
    buffer[1]                = (char) 0xF1;                                                 // 1111 0 00 1 = syncword+id(MPEG-4) + Layer + absent
    buffer[2]                = (char) (((profile) << 6) + (frequencyIndex << 2) + (adts->channelConfig >> 2)); // profile(2)+sampling(4)+privatebit(1)+channel_config(1)
    buffer[3]                = (char) (((adts->channelConfig & 3) << 6) + (fullLength >> 11));
    buffer[4]                = (char) ((fullLength & 0x7FF) >> 3);
    buffer[5]                = (char) (((fullLength & 7) << 5) + 0x1F);
    buffer[6]                = (char) 0xFC;
    return 7;
}

GInt32 readADTS(const GUInt8* data,GUInt8 size,ADTS* adts){
    if (size < 7 || adts == GNULL) {
        return GFalse;
    }
    if(data[0] != 0xff || (data[1] & 0xf0) != 0xf0 || (data[1] & 0x0f) > 1)return GFalse;
    GUInt8  sampleIndex          = data[2] << 2;
    sampleIndex                   = sampleIndex >> 4;
    if (sampleIndex > SAMPLERATE_LEN) {
        return GFalse;
    }
    adts->protection_absent = data[1] & 0x1;
    
    adts->profile = (data[2] >> 6) + 1;
    adts->sampleRate = adtsFrequency[sampleIndex];
    adts->channelConfig            = (data[2] & 0x1) << 2;
    adts->channelConfig += (data[3] & 0xc0) >> 6;
    GUInt32  length;
    memcpy(&length, data + 3, 4);
    length = ntohl(length);
    length &= 0x03ffe000;
    adts->varHeader.aac_frame_length = length >> 13;
    return adts->protection_absent ? 7:9;
}

GInt32 readASC(const GUInt8* data,GUInt8 size,ASC* asc){
    if (size < 2 || asc == GNULL) {
        return GFalse;
    }
    asc->audioType = (data[0] & 0xF8) >> 3;
    GUInt16 frequencyIndex = ((data[0] & 0x07) << 1) | (data[1] >> 7);
    if (frequencyIndex > SAMPLERATE_LEN) {
        return GFalse;
    }
    asc->sampleRate = adtsFrequency[frequencyIndex];
    asc->channelConfig = (data[1] >> 3) & 0x0f;
    asc->gas.frameLengthFlag = (data[1] & 0x04) >> 2;
    return 2;
}

GInt32 writeASC(GUInt8* buffer,GUInt8 size,const ASC* asc){
    if (size < 2 || asc == GNULL) {
        return GFalse;
    }
    GInt8 frequencyIndex = -1;
    for (GUInt8 i = 0; i< SAMPLERATE_LEN; i++) {
        if (adtsFrequency[i] == asc->sampleRate) {
            frequencyIndex = i;
            break;
        }
    }
    if (frequencyIndex < 0) {
        return GFalse;
    }
    buffer[0]   = (asc->audioType << 3) | ((frequencyIndex & 0xe) >> 1);
    buffer[1]   = ((frequencyIndex & 0x1) << 7) | (asc->channelConfig << 3);
    return 2;
}


void quickSort(int* a,int len){
    if (len <= 1) {
        return;
    }
    int l = 0;
    int r = len-1;
    int x = a[l];
    while (l < r) {
        for (; l<r; r--) {//找到右边大于x的位置，并与交换到左边位置
            if (a[r] < x) {
                a[l++] = a[r];
                break;
            }
        }
        
        for ( ; l<r; l++) {//找到左边边大于x的位置，并与交换到右边位置
            if (a[l] > x) {
                a[r--] = a[l];
                break;
            }
        }
    }
    a[l] = x;
    
    quickSort(a, l);
    quickSort(a+l+1, len-(l+1));
}
