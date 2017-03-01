//
//  FFWriter.h
//  GJCaptureTool
//
//  Created by mac on 17/1/18.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef FFWriter_h
#define FFWriter_h

#include <stdio.h>
#include <stdlib.h>

#import "libavformat/avformat.h"
#import "libswscale/swscale.h"
#import "libavcodec/avcodec.h"

typedef struct FFWriterContext {
    
    AVFormatContext* outFormatContext;
    const char* fileName;
    AVStream* audioStream;
    AVStream* videoStream;
    uint32_t videoTrackID;
    uint32_t audioTrackID;
    uint32_t videoWriteCount;
    uint32_t width;
    uint32_t height;
    uint8_t fps;
    pthread_cond_t writeCond;
    pthread_mutex_t writeLock;
}FFWriterContext;


void mp4WriterAddVideo(FFWriterContext* context, uint8_t* data,size_t size,double dts);
void mp4WriterAddAudio(FFWriterContext* context,uint8_t* data,size_t size);
void mp4WriterClose(FFWriterContext** oContext);
void mp4WriterCreate(FFWriterContext** oContext,const char* fileName,uint8_t fps);


void mp4ReadCreate(FFWriterContext** iContext,const char* fileName);
#endif /* FFWriter_h */
