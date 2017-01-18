//
//  Mp4Writer.h
//  GJCaptureTool
//
//  Created by mac on 17/1/5.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef Mp4Writer_h
#define Mp4Writer_h

#include <stdio.h>
#include <stdlib.h>

typedef struct Mp4WriterContext {
    void* fileHandle;
    uint32_t videoTrackID;
    uint32_t audioTrackID;
    uint32_t videoWriteCount;
    uint32_t width;
    uint32_t height;
    uint8_t fps;
    pthread_cond_t writeCond;
    pthread_mutex_t writeLock;
}Mp4WriterContext;


void mp4WriterAddVideo(Mp4WriterContext* context, uint8_t* data,size_t size,double dts);
void mp4WriterAddAudio(Mp4WriterContext* context,uint8_t* data,size_t size);
void mp4WriterClose(Mp4WriterContext** oContext);
void mp4WriterCreate(Mp4WriterContext** oContext,const char* fileName,uint8_t fps);


void mp4ReadCreate(Mp4WriterContext** iContext,const char* fileName);
#endif /* Mp4Writer_h */
