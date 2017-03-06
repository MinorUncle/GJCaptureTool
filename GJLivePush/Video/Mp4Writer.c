//
//  Mp4Writer.c
//  GJCaptureTool
//
//  Created by mac on 17/1/5.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "Mp4Writer.h"
#include "mp4v2.h"
#include "sps_decode.h"
#include <pthread.h>
static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
void mp4WriterAddVideo(Mp4WriterContext* context, uint8_t* data,size_t size,double dts){
    pthread_mutex_lock(&context->writeLock);
    printf("1111111111111**********\n");

    if (data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1 && (data[4] & 0x1f) == 7) {
        uint8_t* sps,*pps,*idr,*sei;int spsSize,ppsSize,idrSize,seiSize;
        find_pp_sps_pps(NULL,data, (int)size, &idr, &sps, &spsSize, &pps, &ppsSize, &sei, &seiSize);
        if (spsSize==0) {
            printf("find SPS error");
            return;
        }

        if (context->videoTrackID == MP4_INVALID_TRACK_ID) {
            h264_decode_sps(sps, (unsigned int)spsSize, (int*)&context->width, (int*)&context->height, NULL);
            if (context->width <= 0 || context->height <= 0 ) {
                printf("decode SPS error");
                return;
            }

            context->videoTrackID = MP4AddH264VideoTrack(context->fileHandle, MP4_MSECS_TIME_SCALE,1.0/context->fps * MP4_MSECS_TIME_SCALE, context->width, context->height, sps[1], sps[2], sps[3], 3);
            MP4AddH264SequenceParameterSet(context->fileHandle, context->videoTrackID, sps, spsSize);
            MP4AddH264PictureParameterSet(context->fileHandle, context->videoTrackID, pps, ppsSize);
            MP4SetVideoProfileLevel(context->fileHandle, 0x7F);
        }

        if (idr) {
            idrSize =(int)( data+size - idr);
            data = idr-4;
            size = idrSize + 4;
        }else{
            return;
        }
    }
    
    int nSize = (int)size - 4;
    uint8_t *tmp = (uint8_t *)data;
    tmp[0] = (nSize & 0xff000000) >> 24;
    tmp[1] = (nSize & 0x00ff0000) >> 16;
    tmp[2] = (nSize & 0x0000ff00) >> 8;
    tmp[3] =  nSize & 0x000000ff;
    if(context->videoTrackID != MP4_INVALID_TRACK_ID){
        bool result = MP4WriteSample(context->fileHandle, context->videoTrackID, (const uint8_t*)data, (uint32_t)size,MP4_INVALID_DURATION,0,(data[4]&0x1f) == 5);
        printf("write result:%d type:%d\n",result,data[4]&0x1f);
        context->videoWriteCount++;
    }else{
        printf("No videoTrackID");
    }
    static long total = 0 ;
    total+=size;
    printf("total:%fMB,\n",total/1024.0/1024.0);
    printf("222222222222---------\n");

    pthread_mutex_unlock(&context->writeLock);

    return;
}
void mp4WriterAddAudio(Mp4WriterContext* context,uint8_t* data,size_t size){
    pthread_mutex_lock(&context->writeLock);
    printf("1111111111111**********\n");
    if (context->audioTrackID == MP4_INVALID_TRACK_ID) {
        int sampling_frequency_index,objType,channel_config;
        
        aac_parse_header(data, (int)size, &sampling_frequency_index,&objType, &channel_config);
        objType = 2;
        uint8_t dsi[2] = {0x14, 0x10};
        dsi[0] = (objType<<3) | (sampling_frequency_index>>1);
        dsi[1] = ((sampling_frequency_index&1)<<7) | (channel_config<<3);
        context->audioTrackID = MP4AddAudioTrack(context->fileHandle,mpeg4audio_sample_rates[sampling_frequency_index], 1024, MP4_MPEG4_AUDIO_TYPE);
        MP4SetAudioProfileLevel(context->fileHandle, 0x2);
        MP4SetTrackESConfiguration(context->fileHandle, context->audioTrackID, dsi, sizeof(dsi));
    }
    if (size>60) {
        MP4WriteSample(context->fileHandle, context->audioTrackID, data+7, (int)size-7, MP4_INVALID_DURATION, 0, 1);
    }
    printf("222222222222---------\n");
    pthread_mutex_unlock(&context->writeLock);
}
void mp4WriterClose(Mp4WriterContext** iContext){
    Mp4WriterContext* context = *iContext;
    MP4Close(context->fileHandle,0);
    free(context);
    *iContext = NULL;
}
void mp4WriterCreate(Mp4WriterContext** oContext,const char* fileName,uint8_t fps){
    Mp4WriterContext* context = (Mp4WriterContext*)malloc(sizeof(Mp4WriterContext));
    memset(context, 0, sizeof(Mp4WriterContext));
    context->videoTrackID = context->audioTrackID = MP4_INVALID_TRACK_ID;
    context->fileHandle = MP4Create(fileName,0);
    if (context->fileHandle == 0) {
        free(context);
        context = NULL;
        return;
    }
    context->fps = fps;
    
    *oContext = context;
}

void mp4ReadCreate(Mp4WriterContext** iContext,const char* fileName){
    Mp4WriterContext* context = (Mp4WriterContext*)malloc(sizeof(Mp4WriterContext));
    memset(context, 0, sizeof(Mp4WriterContext));
    context->videoTrackID = context->audioTrackID = MP4_INVALID_TRACK_ID;
    context->fileHandle = MP4Read(fileName);
    if (context->fileHandle == 0) {
        free(context);
        context = NULL;
        return;
    }
    for (int i = 1; i <= MP4GetNumberOfTracks(context->fileHandle,0,0); i++) {
        const char* type = MP4GetTrackType(context->fileHandle, i);
        if (!strcmp(type, MP4_VIDEO_TRACK_TYPE)) {
            context->videoTrackID = i;
            break;
        }
    }
    *iContext = context;
}

void lockInit(Mp4WriterContext* context){
    pthread_condattr_t cond_attr;
    pthread_condattr_init(&cond_attr);
    pthread_cond_init(&context->writeCond, &cond_attr);
    pthread_mutex_init(&context->writeLock, NULL);
}



