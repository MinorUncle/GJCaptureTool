//
//  H264Decoder.m
//  FFMpegDemo
//
//  Created by tongguan on 16/6/15.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import "libavformat/avformat.h"
#import "libswscale/swscale.h"
#import <CoreVideo/CVPixelBuffer.h>

#import "GJQueue.h"
#include "GJBufferPool.h"
#import "H264Decoder.h"
#include "sps_decode.h"
struct _FFDecoder{
    GJPixelType             pixelFormat;
    GBool                   isRunning;
    AVCodec *               decoder;
    AVCodecContext *        decoderContext;
    GHandle                 videoDecodeQueue;
    VideoFrameOutCallback   callback;
    GHandle                 userData;
    GJQueue*                cacheQueue;
    pthread_t               runloopThread;
};
void pixelBufferReleasePlanarBytesCallback( void * CV_NULLABLE releaseRefCon, const void * CV_NULLABLE dataPtr, size_t dataSize, size_t numberOfPlanes, const void * CV_NULLABLE planeAddresses[] ){
    AVFrame* frame = releaseRefCon;
    av_frame_free(&frame);
    
}
static void* FFDecoder_DecodeRunloop(GHandle arg){
    FFDecoder* decoder = (FFDecoder*)arg;
    R_GJPacket* packetData;
    AVPacket* packet = av_packet_alloc();
    size_t width = decoder->decoderContext->width;
    size_t height = decoder->decoderContext->height;
    NSDictionary *attributes = @{(id) kCVPixelBufferOpenGLESCompatibilityKey : @YES};
    size_t pixelWidth[2] = {width,width/2};
    size_t pixelHeight[2] = {height,height/2};
    size_t planeBytesPerRow[2] = {width*height,width*height/2};
    while (decoder->isRunning && queuePop(decoder->cacheQueue, (GHandle*)&packetData, GINT32_MAX)) {
        AVFrame* frame  = av_frame_alloc();
        int errorCode = av_packet_from_data(packet, R_BufferStart(&packetData->retain)+packetData->dataOffset, packetData->dataSize);
        
        errorCode = avcodec_send_packet(decoder->decoderContext, packet);
        if (errorCode <0) {
            printf("avcodec_send_packet error:%d\n",errorCode);
        }
        errorCode = avcodec_receive_frame(decoder->decoderContext, frame);
        if (errorCode <0) {
            printf("avcodec_receive_frame error:%d\n",errorCode);
        }
        CVPixelBufferRef pixelbuffer;
//        CVReturn result = CVPixelBufferCreate(GNULL, width, height, (OSType)decoder->pixelFormat, (__bridge CFDictionaryRef)attributes, &pixelbuffer);
        CVReturn result = CVPixelBufferCreateWithPlanarBytes(GNULL, width, height, (OSType)decoder->pixelFormat, GNULL, 0, 2, (GVoid**)frame->data, pixelWidth, pixelHeight, planeBytesPerRow, pixelBufferReleasePlanarBytesCallback, frame, (__bridge CFDictionaryRef)attributes, &pixelbuffer);
        GJAssert(result == kCVReturnSuccess, "error");
        R_GJPixelFrame* pixelFrame = (R_GJPixelFrame*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJPixelFrame));
        pixelFrame->width = (GInt)width;
        pixelFrame->height = (GInt)height;
        pixelFrame->type = decoder->pixelFormat;
        pixelFrame->pts =  GTimeMake(frame->pts*decoder->decoderContext->time_base.num/decoder->decoderContext->time_base.den*1000, 1000);
        ((CVImageBufferRef *) R_BufferStart(&pixelFrame->retain))[0] = pixelbuffer;
        if (errorCode == 0 && decoder->callback) {
            decoder->callback(decoder->userData,pixelFrame);
        }
        av_packet_free_side_data(packet);
        av_init_packet(packet);
        packet->data = NULL;
        packet->size = 0;
        R_BufferUnRetain(&packetData->retain);
    }
    return GNULL;
}

GBool FFDecoder_DecodePacket(FFDecoder* decoder,R_GJPacket *packet){
    
    if (decoder->isRunning && packet->flag & GJPacketFlag_DecoderType && decoder->decoder == GNULL) {
        GJ_CODEC_TYPE codecType;
        enum AVCodecID codecID = AV_CODEC_ID_NONE;
        memcpy(&codecType, R_BufferStart(&packet->retain), sizeof(GJ_CODEC_TYPE));
        switch (codecType) {
            case GJ_CODEC_TYPE_H264:
                codecID = AV_CODEC_ID_H264;
                break;
            case GJ_CODEC_TYPE_MPEG4:
                codecID = AV_CODEC_ID_MPEG4;
                break;
            default:
                GJAssert(0, "格式不支持");
                break;
        }
        decoder->decoder     = avcodec_find_decoder(codecID);
        decoder->decoderContext          = avcodec_alloc_context3(decoder->decoder);
        switch (decoder->pixelFormat) {
//            case GJPixelType_YpCbCr8Planar:
//            case GJPixelType_YpCbCr8Planar_Full:
//                decoder->decoderContext->pix_fmt = AV_PIX_FMT_YUV420P;
//                break;
            case GJPixelType_YpCbCr8BiPlanar:
            case GJPixelType_YpCbCr8BiPlanar_Full:
                decoder->decoderContext->pix_fmt = AV_PIX_FMT_NV12;
                break;
            default:
                GJAssert(0, "格式不支持");
                return GFalse;
                break;
        }
        if (packet->dataSize <= 0) {
            return GTrue;
        }
    }
    if (decoder->isRunning && packet->flag & GJPacketFlag_KEY && packet->extendDataSize > 0) {
        GInt width,height,fps;
        if(decoder->decoderContext && !avcodec_is_open(decoder->decoderContext) && h264_decode_sps(R_BufferStart(&packet->retain)+packet->extendDataOffset+4, packet->extendDataSize-4, &width, &height, &fps)){
            decoder->decoderContext->width = width;
            decoder->decoderContext->height = height;
            if(avcodec_open2(decoder->decoderContext, decoder->decoder, GNULL) < 0){
                GJAssert(0, "格式不支持");
                return GFalse;
            }
            pthread_create(&decoder->runloopThread, GNULL, FFDecoder_DecodeRunloop, decoder);
        };
    }
    R_BufferRetain(&packet->retain);
    if (!decoder->isRunning || !queuePush(decoder->cacheQueue, packet, GINT32_MAX)) {
        R_BufferUnRetain(&packet->retain);
    };
    return GTrue;
}

GBool FFDecoder_DecodeStart(FFDecoder* decoder){
    decoder->isRunning = GTrue;
    return GTrue;
}

GBool FFDecoder_DecodeStop(FFDecoder* decoder){
    decoder->isRunning = GFalse;
    queueEnablePop(decoder->cacheQueue, GFalse);
    queueBroadcastPop(decoder->cacheQueue);
    GInt32 length = 0;
    queueClean(decoder->cacheQueue, GNULL, &length);
    if (length > 0) {
        GHandle* buffer = malloc(sizeof(GHandle)*length);
        queueClean(decoder->cacheQueue, buffer, &length);
        for (int i = 0; i<length; i++) {
            R_BufferUnRetain((GJRetainBuffer*)(buffer[i]));
        }
        free(buffer);
    }
    return GTrue;
}

GBool FFDecoder_DecodeCreate(FFDecoder** decoderH,GJPixelType pixelFormat){
    FFDecoder *decoder = calloc(sizeof(FFDecoder),1);
    decoder->pixelFormat = pixelFormat;
    queueCreate(&decoder->cacheQueue, 10, GTrue, GTrue);
    *decoderH = decoder;
    return GTrue;
}

GVoid FFDecoder_DecodeDealloc(FFDecoder** decoderH){
    FFDecoder* decoder = *decoderH;
    queueFree(&decoder->cacheQueue);
    free(decoder);
    *decoderH = GNULL;
}

static void decodeCallback(GHandle userdata,R_GJPixelFrame* frame){
    struct _GJH264DecodeContext* context = userdata;
    NodeFlowDataFunc callFunc = pipleNodeFlowFunc(&context->pipleNode);
    if (context->callback) {
        context->callback(context->userData, frame);
    }
    callFunc(&context->pipleNode,&frame->retain,GJMediaType_Video);
}

inline static GBool decodeSetup(struct _GJH264DecodeContext *context, GJPixelType format, VideoFrameOutCallback callback, GHandle userData) {
    pipleNodeLock(&context->pipleNode);
    GJAssert(context->obaque == GNULL, "上一个视频解码器没有释放");
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder setup");
    FFDecoder* decoder = GNULL;
    FFDecoder_DecodeCreate(&decoder,format);
    decoder->callback = decodeCallback;
    decoder->userData = context;
    context->obaque = decoder;
    context->callback = callback;
    context->userData = userData;
    pipleNodeUnLock(&context->pipleNode);
    
    return GTrue;
}
inline static GVoid decodeUnSetup(struct _GJH264DecodeContext *context) {
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        FFDecoder* decoder  = (context->obaque);
        if (decoder->isRunning) {
            FFDecoder_DecodeStop(decoder);
        }
        context->obaque       = GNULL;
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder unsetup");
    }
    pipleNodeUnLock(&context->pipleNode);
}

inline static  GBool  decodeStart(struct _GJH264DecodeContext* context){
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        FFDecoder* decoder  = (context->obaque);
        FFDecoder_DecodeStart(decoder);
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder decodeStart");

    }
    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
};

inline static  GVoid  decodeStop(struct _GJH264DecodeContext* context){
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        FFDecoder* decoder  = (context->obaque);
        if (decoder->isRunning) {
            FFDecoder_DecodeStop(decoder);
        }
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder decodeStart");
    }
    pipleNodeUnLock(&context->pipleNode);
};

inline static GBool decodePacket(struct _GJH264DecodeContext *context, R_GJPacket *packet) {
    pipleNodeLock(&context->pipleNode);
    FFDecoder* decoder  = (context->obaque);
    FFDecoder_DecodePacket(decoder, packet);
    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
}

inline static GBool decodePacketFunc(GJPipleNode* context, GJRetainBuffer* data,GJMediaType dataType){
    GBool result = GFalse;
    if (dataType == GJMediaType_Video) {
        result = decodePacket((GJH264DecodeContext*)context,(R_GJPacket*)data);
    }
    return  result;
    
}

GVoid GJ_FFDecodeContextCreate(GJH264DecodeContext **decodeContext) {
    if (*decodeContext == NULL) {
        *decodeContext = (GJH264DecodeContext *) malloc(sizeof(GJH264DecodeContext));
    }
    GJH264DecodeContext *context     = *decodeContext;
    memset(context, 0, sizeof(GJH264DecodeContext));
    pipleNodeInit(&context->pipleNode, decodePacketFunc);
    context->decodeSetup             = decodeSetup;
    context->decodeUnSetup           = decodeUnSetup;
    context->decodeStart             = decodeStart;
    context->decodeStop              = decodeStop;
    context->decodePacket            = GNULL;
}
GVoid GJ_FFDecodeContextDealloc(GJH264DecodeContext **context) {
    if ((*context)->obaque) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "decodeUnSetup 没有调用，自动调用");
        (*context)->decodeUnSetup(*context);
    }
    pipleNodeUnInit(&(*context)->pipleNode);
    free(*context);
    *context = GNULL;
}

//@interface H264Decoder (){
//    AVFormatContext *  _formatContext;
//    AVCodec *          _videoDecoder;
//    AVCodecContext *   _videoDecoderContext;
//    struct SwsContext *_videoSwsContext;
//    AVCodec *          _audioDecoder;
//    AVCodecContext *   _audioDecoderContext;
//    AVFrame *          _frame;
//    AVPacket *         _videoPacket;
//    AVFrame *          _yuvFrame;
//    dispatch_queue_t   _videoDecodeQueue;
//}
//@end
//@implementation H264Decoder
//
//- (instancetype)initWithWidth:(int)width height:(int)height {
//    self = [super init];
//    if (self) {
//        avcodec_register_all();
//        _width  = width;
//        _height = height;
//    }
//
//    return self;
//}
//- (void)_createDecode {
//    _videoDecodeQueue = dispatch_queue_create("vidoeDecode", DISPATCH_QUEUE_SERIAL);
//    _formatContext    = avformat_alloc_context();
//    _videoDecoder     = avcodec_find_decoder(AV_CODEC_ID_H264);
//
//    _videoDecoderContext          = avcodec_alloc_context3(_videoDecoder);
//    _videoDecoderContext->width   = _width;
//    _videoDecoderContext->height  = _height;
//    _videoDecoderContext->pix_fmt = AV_PIX_FMT_YUV420P;
//    //    _videoDecoderContext->time_base
//
//    int errorCode = avcodec_open2(_videoDecoderContext, _videoDecoder, nil);
//    [self showErrWidhCode:errorCode preStr:@"avcodec_open2"];
//    _videoSwsContext = sws_getContext(_videoDecoderContext->width, _videoDecoderContext->height, _videoDecoderContext->pix_fmt, _videoDecoderContext->width, _videoDecoderContext->height, AV_PIX_FMT_YUV420P, SWS_BICUBIC, NULL, NULL, NULL);
//
//    _videoPacket      = av_packet_alloc();
//    _frame            = av_frame_alloc();
//    _yuvFrame         = av_frame_alloc();
//    _yuvFrame->width  = _width;
//    _yuvFrame->height = _height;
//    _yuvFrame->format = _videoDecoderContext->pix_fmt;
//    av_frame_get_buffer(_yuvFrame, 1);
//}
//
//- (void)decodeData:(uint8_t *)data lenth:(int)lenth {
//    if (_videoDecoderContext == nil) {
//        [self _createDecode];
//    }
//
//    int errorCode = av_packet_from_data(_videoPacket, data, lenth);
//    [self showErrWidhCode:errorCode preStr:@"av_packet_from_data"];
//
//    errorCode = avcodec_send_packet(_videoDecoderContext, _videoPacket);
//    [self showErrWidhCode:errorCode preStr:@"avcodec_send_packet"];
//
//    errorCode = avcodec_receive_frame(_videoDecoderContext, _frame);
//    if (errorCode < 0) {
//        [self showErrWidhCode:errorCode preStr:@"avcodec_receive_frame"];
//        return;
//    }
//    switch (_frame->pict_type) {
//        case AV_PICTURE_TYPE_I:
//            printf("i帧--------\n");
//            break;
//        case AV_PICTURE_TYPE_P:
//            printf("p帧--------\n");
//            break;
//        case AV_PICTURE_TYPE_B:
//            printf("b帧--------\n");
//            break;
//
//        default:
//            printf("其他帧--------\n");
//            break;
//    }
//
//    errorCode = sws_scale(_videoSwsContext, _frame->data, _frame->linesize, 0, _videoDecoderContext->height, _yuvFrame->data, _yuvFrame->linesize);
//    if (errorCode < 0) {
//        [self showErrWidhCode:errorCode preStr:@"sws_scale"];
//        return;
//    }
//    float width   = _yuvFrame->linesize[0];
//    float height  = _yuvFrame->height;
//    int   y_size  = width * height;
//    char *yuvdata = (char *) malloc(y_size * 1.5);
//
//    memcpy(yuvdata, _yuvFrame->data[0], y_size);
//    memcpy(yuvdata + y_size, _yuvFrame->data[1], y_size / 4.0);
//    memcpy(yuvdata + y_size + y_size / 4, _yuvFrame->data[2], y_size / 4.0);
//
//    if (errorCode > 0) {
//        [self.decoderDelegate H264Decoder:self GetYUV:yuvdata size:y_size * 1.5 width:width height:height];
//    }
//}
//
//- (void)decode {
//    if (_status == H264DecoderPlaying) {
//        [self _decodeData];
//        [self _parpareData];
//    }
//}
//- (BOOL)_parpareData {
//    int result = av_read_frame(_formatContext, _videoPacket);
//    if (result < 0) {
//        [self showErrWidhCode:result preStr:@"av_read_frame"];
//        if (result == AVERROR_EOF) {
//            [self stop];
//        }
//        return NO;
//    }
//    result = avcodec_send_packet(_videoDecoderContext, _videoPacket);
//    if (result < 0) {
//        [self showErrWidhCode:result preStr:@"avcodec_send_packet"];
//        return NO;
//    }
//    return YES;
//}
//- (void)_decodeData {
//    if (_status == H264DecoderStopped) {
//        return;
//    }
//    int result = avcodec_receive_frame(_videoDecoderContext, _frame);
//    if (result < 0) {
//        [self showErrWidhCode:result preStr:@"avcodec_receive_frame"];
//        return;
//    }
//    result = sws_scale(_videoSwsContext, _frame->data, _frame->linesize, 0, _videoDecoderContext->height, _yuvFrame->data, _yuvFrame->linesize);
//    if (result < 0) {
//        [self showErrWidhCode:result preStr:@"sws_scale"];
//        return;
//    }
//    float width  = _yuvFrame->linesize[0];
//    float height = _yuvFrame->height;
//    int   y_size = width * height;
//    char *data;
//
//    memcpy(data, _yuvFrame->data[0], y_size);
//    memcpy(data + y_size, _yuvFrame->data[1], y_size / 4.0);
//    memcpy(data + y_size + y_size / 4, _yuvFrame->data[2], y_size / 4.0);
//}
//
//- (void)showErrWidhCode:(int)errorCode preStr:(NSString *)preStr {
//    char *c = (char *) &errorCode;
//    if (errorCode < 0) {
//        NSString *err;
//        if (errorCode == AVERROR(EAGAIN)) {
//            err = @"EAGAIN";
//        } else if (errorCode == AVERROR(EINVAL)) {
//            err = @"EINVAL";
//        } else if (errorCode == AVERROR_EOF) {
//            err = @"AVERROR_EOF";
//        } else if (errorCode == AVERROR(ENOMEM)) {
//            err = @"AVERROR(ENOMEM)";
//        }
//        if (preStr == nil) {
//            preStr = @"";
//        }
//        NSLog(@"%@:%c%c%c%c error:%@", preStr, c[3], c[2], c[1], c[0], err);
//    } else {
//        NSLog(@"%@成功", preStr);
//    }
//}
//- (void)dealloc {
//}
//@end

