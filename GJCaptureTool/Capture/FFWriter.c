//
//  FFWriter.c
//  GJCaptureTool
//
//  Created by mac on 17/1/18.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "FFWriter.h"



void mp4WriterAddVideo(FFWriterContext* context, uint8_t* data,size_t size,double dts);
void mp4WriterAddAudio(FFWriterContext* context,uint8_t* data,size_t size);
void mp4WriterClose(FFWriterContext** oContext);
void mp4WriterCreate(FFWriterContext** oContext,const char* fileName,uint8_t fps){
    FFWriterContext* context = (FFWriterContext*)malloc(sizeof(FFWriterContext));
    memset(context, 0, sizeof(FFWriterContext));
    av_register_all();
    avcodec_register_all();
    context->fileName = fileName;
    avformat_alloc_output_context2(&context->outFormatContext, NULL, NULL, fileName);
    if (!context->outFormatContext)
    {
        printf( "Could not create output context\n");
        goto fail;
    }
    
    context->videoStream = avformat_new_stream(context->outFormatContext, 0);
    if (!context->videoStream)
    {
        printf( "Failed allocating output stream\n");
        goto fail;
    }
    
    //±‡¬Î≤Œ ˝
    AVCodecContext *c = context->videoStream->codec;
    AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_H264);
    avcodec_get_context_defaults3(c, codec);
    
    c->bit_rate = nBitRate;
    c->codec_id = AV_CODEC_ID_H264;
    c->codec_type = AVMEDIA_TYPE_VIDEO;
    c->time_base.num = 1;
    c->time_base.den = nFrameRate;
    //c->gop_size = nFrameRate;
    c->width = nWidth;
    c->height = nHeight;
    c->pix_fmt = AV_PIX_FMT_YUV420P;
    c->flags |= CODEC_FLAG_GLOBAL_HEADER;
    
    if (avcodec_open2(c, codec, 0) < 0)
    {
        printf("could not open codec\n");
        avformat_free_context(pInfo->pFmtCtx);
        delete pInfo;
        return 0;
    }
    
    //≥ı ºªØAVFrame
    c->coded_frame = av_frame_alloc();
    if (!c->coded_frame)
    {
        avformat_free_context(pInfo->pFmtCtx);
        delete pInfo;
        return 0;
    }
    int size = avpicture_get_size(AV_PIX_FMT_YUV420P, nWidth, nHeight);
    uint8_t *picture_buf = (uint8_t *)malloc(size);
    if (!picture_buf)
    {
        av_frame_free(&c->coded_frame);
        return 0;
    }
    avpicture_fill((AVPicture *)c->coded_frame, picture_buf, AV_PIX_FMT_YUV420P, nWidth, nHeight);
    
    pInfo->paudioStream = avformat_new_stream(pInfo->pFmtCtx, 0);
    if (!pInfo->paudioStream)
    {
        printf( "Failed allocating output stream\n");
        avformat_free_context(pInfo->pFmtCtx);
        delete pInfo;
        return 0;
    }
    
    c = pInfo->paudioStream->codec;
    codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    avcodec_get_context_defaults3(c, codec);
    
    c->codec = codec;
    c->codec_id = AV_CODEC_ID_AAC;
    c->codec_type = AVMEDIA_TYPE_AUDIO;
    c->bits_per_coded_sample = 2;
    c->bit_rate = 128000;
    c->sample_rate = 8000;
    c->channels = 1;
    c->sample_fmt = AV_SAMPLE_FMT_S16;
    c->time_base.num = 1;
    c->time_base.den = 10;
    
    int ret = avcodec_open2(c, codec, 0);
    if (ret < 0)
    {
        printf("could not open codec\n");
        avformat_free_context(pInfo->pFmtCtx);
        delete pInfo;
        return 0;
    }
    
    c->coded_frame = av_frame_alloc();
    if (!c->coded_frame)
    {
        avformat_free_context(pInfo->pFmtCtx);
        delete pInfo;
        return 0;
    }
    
    //¥Úø™Œƒº˛
    if (avio_open(&pInfo->pFmtCtx->pb, pFileName, AVIO_FLAG_WRITE) < 0)
    {
        printf( "Could not open output file '%s'", pFileName);
        av_frame_free(&pInfo->pStream->codec->coded_frame);
        avformat_free_context(pInfo->pFmtCtx);
        delete pInfo;
        return 0;
    }
    
    //–¥»ÎŒƒº˛Õ∑
    if (avformat_write_header(pInfo->pFmtCtx, NULL) < 0)
    {
        PlayMedia_CloseFile((long)pInfo);
        return 0;
    }
fail:
    
}

