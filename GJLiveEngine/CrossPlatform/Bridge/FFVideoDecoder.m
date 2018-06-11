//
//  H264Decoder.m
//  FFMpegDemo
//
//  Created by tongguan on 16/6/15.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import "libavformat/avformat.h"
#import "libswscale/swscale.h"
#import "libavcodec/videotoolbox.h"
#import <CoreVideo/CVPixelBuffer.h>

#import "GJQueue.h"
#include "GJBufferPool.h"
#import "FFVideoDecoder.h"
#include "sps_decode.h"
struct _FFDecoder {
    GJPixelType           pixelFormat;
    GBool                 isRunning;
    AVCodec *             decoder;
    AVCodecContext *      decoderContext;
    GHandle               videoDecodeQueue;
    VideoFrameOutCallback callback;
    GHandle               userData;
    GJQueue *             cacheQueue;
    pthread_t             runloopThread;
    GJRetainBufferPool *  bufferPool;
    AVRational            timebase;
};
void pixelBufferReleasePlanarBytesCallback(void *CV_NULLABLE releaseRefCon, const void *CV_NULLABLE dataPtr, size_t dataSize, size_t numberOfPlanes, const void *CV_NULLABLE planeAddresses[]) {
    AVFrame *frame = releaseRefCon;
    av_frame_free(&frame);
}
static void *FFDecoder_DecodeRunloop(GHandle arg) {
    FFDecoder * decoder = (FFDecoder *) arg;
    R_GJPacket *packetData;
    AVPacket    packet;
    while (decoder->isRunning && queuePop(decoder->cacheQueue, (GHandle *) &packetData, GINT32_MAX)) {
        AVFrame * frame      = av_frame_alloc();
        AVPacket *sendPacket = GNULL;
        if ((packetData->flag & GJPacketFlag_AVPacketType) == GJPacketFlag_AVPacketType) {
            sendPacket = ((AVPacket *) (R_BufferStart(packetData) + packetData->extendDataOffset));
        } else {
            av_init_packet(&packet);
            packet.data = GNULL;
            packet.size = 0;

            av_packet_from_data(&packet, R_BufferStart(&packetData->retain) + packetData->dataOffset, packetData->dataSize);
            sendPacket = &packet;
        }
        int errorCode = avcodec_send_packet(decoder->decoderContext, sendPacket);
        GJAssert(errorCode >= 0, "avcodec_send_packet error:%s\n", av_err2str(errorCode));
        errorCode = avcodec_receive_frame(decoder->decoderContext, frame);
        if (errorCode < 0) {
            GJLOG(GNULL, GJ_LOGDEBUG, "avcodec_receive_frame error:%s\n", av_err2str(errorCode));
        } else {

            R_GJPixelFrame *pixelFrame                           = (R_GJPixelFrame *) GJRetainBufferPoolGetData(decoder->bufferPool);
            pixelFrame->height                                   = frame->width;
            pixelFrame->width                                    = frame->height;
            pixelFrame->pts                                      = GTimeMake(av_frame_get_best_effort_timestamp(frame) * 1.0 * decoder->timebase.num / decoder->timebase.den * 1000, 1000);
            pixelFrame->dts                                      = GTimeMake(frame->pkt_dts * 1.0 * decoder->timebase.num / decoder->timebase.den * 1000, 1000);
            pixelFrame->type                                     = decoder->pixelFormat;
            pixelFrame->flag                                     = kGJFrameFlag_P_AVFrame;
            ((AVFrame **) R_BufferStart(&pixelFrame->retain))[0] = frame;

            if (errorCode == 0 && decoder->callback) {
                decoder->callback(decoder->userData, pixelFrame);
            }
            R_BufferUnRetain(pixelFrame);
        }
        //sendPacket的内存都可以不用管，因为都是引用别人的内存。
        R_BufferUnRetain(&packetData->retain);
    }
    avcodec_close(decoder->decoderContext);
    avcodec_free_context(&decoder->decoderContext);
    decoder->runloopThread = GNULL;
    return GNULL;
}
GBool _setupDecoderContext(FFDecoder *decoder, enum AVCodecID codecID) {
    AVCodec *codec = avcodec_find_decoder(codecID);
    GJAssert(codec != nil, "格式不支持");
    decoder->decoder        = codec;
    decoder->decoderContext = avcodec_alloc_context3(codec);
    switch (decoder->pixelFormat) {
        case GJPixelType_YpCbCr8BiPlanar:
        case GJPixelType_YpCbCr8BiPlanar_Full:
            decoder->decoderContext->pix_fmt = AV_PIX_FMT_NV12;
            break;
        case GJPixelType_32BGRA:
            decoder->decoderContext->pix_fmt = AV_PIX_FMT_BGRA;
            break;
        default:
            GJAssert(0, "格式不支持");
            return GFalse;
            break;
    }

    return GTrue;
}
GBool FFDecoder_DecodePacket(FFDecoder *decoder, R_GJPacket *packet) {
    if (decoder->isRunning) {
        if (decoder->decoderContext == GNULL) {
            if ((packet->flag & GJPacketFlag_P_AVStreamType) == GJPacketFlag_P_AVStreamType) {
                GJAssert(decoder->decoderContext == GNULL, "待优化");
                AVStream *stream  = ((AVStream **) (R_BufferStart(packet) + packet->extendDataOffset))[0];
                decoder->timebase = stream->time_base;
                _setupDecoderContext(decoder, stream->codecpar->codec_id);
                GJAssert(avcodec_parameters_to_context(decoder->decoderContext, stream->codecpar) >= 0, "avcodec_parameters_to_context error");

                switch (decoder->pixelFormat) {
                    case GJPixelType_YpCbCr8BiPlanar:
                    case GJPixelType_YpCbCr8BiPlanar_Full:
                        decoder->decoderContext->pix_fmt = AV_PIX_FMT_NV12;
                        break;
                    case GJPixelType_32BGRA:
                        decoder->decoderContext->pix_fmt = AV_PIX_FMT_BGRA;
                        break;
                    default:
                        GJAssert(0, "格式不支持");
                        return GFalse;
                        break;
                }
                //直接起飞了
                if (avcodec_open2(decoder->decoderContext, decoder->decoder, GNULL) < 0) {
                    GJAssert(0, "格式不支持");
                    return GFalse;
                }

                GJAssert(decoder->runloopThread == GNULL, "已经飞过了，出问题了");
                pthread_create(&decoder->runloopThread, GNULL, FFDecoder_DecodeRunloop, decoder);
                return GTrue;
            } else if ((packet->flag & GJPacketFlag_DecoderType) == GJPacketFlag_DecoderType) {
                GJAssert(decoder->decoderContext == GNULL, "待优化");
                GJ_CODEC_TYPE  codecType;
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
                _setupDecoderContext(decoder, codecID);
                if (packet->dataSize <= 0) return GTrue;
            } else {
                GJAssert(0, "没有初始化信息包");
            }
        } else {
            if (!avcodec_is_open(decoder->decoderContext)) {
                //还没有打开加码器，一般是非ffmpeg拉流，还没有收到extendData。在这里必须收到
                GInt width, height, fps;
                if ((packet->flag & GJPacketFlag_KEY) == GJPacketFlag_KEY &&
                    packet->extendDataSize > 0 &&
                    h264_decode_sps(R_BufferStart(&packet->retain) + packet->extendDataOffset + 4, packet->extendDataSize - 4, &width, &height, &fps)) {
                    decoder->decoderContext->width  = width;
                    decoder->decoderContext->height = height;
                    decoder->timebase               = av_make_q(1, 1);
                    if (avcodec_open2(decoder->decoderContext, decoder->decoder, GNULL) < 0) {
                        GJAssert(0, "格式不支持");
                        return GFalse;
                    }
                    GJAssert(decoder->runloopThread == GNULL, "已经飞过了，出问题了");
                    //起飞了
                    pthread_create(&decoder->runloopThread, GNULL, FFDecoder_DecodeRunloop, decoder);
                    if (packet->dataSize <= 0) return GTrue;
                } else {
                    GJAssert(0, "编码器还没有办法打开，确实extendData");
                }
            }
        }

    } else {
        GJAssert(0, "解码器没有开始");
    }
    R_BufferRetain(packet);
    if (!decoder->isRunning || !queuePush(decoder->cacheQueue, packet, GINT32_MAX)) {
        R_BufferUnRetain(&packet->retain);
    };
    return GTrue;
}

GBool FFDecoder_DecodeStart(FFDecoder *decoder) {
    decoder->isRunning = GTrue;
    queueEnablePop(decoder->cacheQueue, GTrue);
    return GTrue;
}

GBool FFDecoder_DecodeStop(FFDecoder *decoder) {
    decoder->isRunning = GFalse;
    queueEnablePop(decoder->cacheQueue, GFalse);
    queueBroadcastPop(decoder->cacheQueue);
    queueFuncClean(decoder->cacheQueue, R_BufferUnRetainUnTrack);

    return GTrue;
}

inline static GVoid cvImagereleaseCallBack(GJRetainBuffer *buffer, GHandle userData) {
    AVFrame *frame = ((AVFrame **) R_BufferStart(buffer))[0];
    av_frame_free(&frame);
}
GBool FFDecoder_DecodeCreate(FFDecoder **decoderH, GJPixelType pixelFormat) {
    FFDecoder *decoder   = calloc(sizeof(FFDecoder), 1);
    decoder->pixelFormat = pixelFormat;
    GJRetainBufferPoolCreate(&decoder->bufferPool, sizeof(AVFrame *), GTrue, R_GJPixelFrameMalloc, cvImagereleaseCallBack, GNULL);
    queueCreate(&decoder->cacheQueue, 10, GTrue, GTrue);
    *decoderH = decoder;
    return GTrue;
}

GVoid FFDecoder_DecodeDealloc(FFDecoder **decoderH) {
    FFDecoder *decoder = *decoderH;
    queueFree(&decoder->cacheQueue);

    GJRetainBufferPool *temPool = decoder->bufferPool;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        GJRetainBufferPoolClean(temPool, GTrue);
        GJRetainBufferPoolFree(temPool);
    });

    free(decoder);
    *decoderH = GNULL;
}

static void decodeCallback(GHandle userdata, R_GJPixelFrame *frame) {
    struct _FFVideoDecodeContext *context  = userdata;
    NodeFlowDataFunc              callFunc = pipleNodeFlowFunc(&context->pipleNode);
    if (context->callback) {
        context->callback(context->userData, frame);
    }
    callFunc(&context->pipleNode, &frame->retain, GJMediaType_Video);
}

inline static GBool decodeSetup(struct _FFVideoDecodeContext *context, GJPixelType format, VideoFrameOutCallback callback, GHandle userData) {
    pipleNodeLock(&context->pipleNode);
    GJAssert(context->obaque == GNULL, "上一个视频解码器没有释放");
    GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder setup");
    FFDecoder *decoder = GNULL;
    FFDecoder_DecodeCreate(&decoder, format);
    decoder->callback = decodeCallback;
    decoder->userData = context;
    context->obaque   = decoder;
    context->callback = callback;
    context->userData = userData;
    pipleNodeUnLock(&context->pipleNode);

    return GTrue;
}
inline static GVoid decodeUnSetup(struct _FFVideoDecodeContext *context) {
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        FFDecoder *decoder = (context->obaque);
        if (decoder->isRunning) {
            FFDecoder_DecodeStop(decoder);
        }
        context->obaque = GNULL;
        GJLOG(DEFAULT_LOG, GJ_LOGINFO, "GJH264Decoder unsetup");
    }
    pipleNodeUnLock(&context->pipleNode);
}

inline static GBool decodeStart(struct _FFVideoDecodeContext *context) {
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        FFDecoder *decoder = (context->obaque);
        FFDecoder_DecodeStart(decoder);
        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "%p",context);
    }
    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
};

inline static GVoid decodeStop(struct _FFVideoDecodeContext *context) {
    pipleNodeLock(&context->pipleNode);
    if (context->obaque) {
        FFDecoder *decoder = (context->obaque);
        if (decoder->isRunning) {
            FFDecoder_DecodeStop(decoder);
        }
        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "%p",context);
    }
    pipleNodeUnLock(&context->pipleNode);
};

inline static GBool decodePacket(struct _FFVideoDecodeContext *context, R_GJPacket *packet) {
    pipleNodeLock(&context->pipleNode);
    FFDecoder *decoder = (context->obaque);
    FFDecoder_DecodePacket(decoder, packet);
    pipleNodeUnLock(&context->pipleNode);
    return GTrue;
}

inline static GBool decodePacketFunc(GJPipleNode *context, GJRetainBuffer *data, GJMediaType dataType) {
    GBool result = GFalse;
    if (dataType == GJMediaType_Video) {
        result = decodePacket((FFVideoDecodeContext *) context, (R_GJPacket *) data);
    }
    return result;
}

GVoid GJ_FFDecodeContextCreate(FFVideoDecodeContext **decodeContext) {
    if (*decodeContext == NULL) {
        *decodeContext = (FFVideoDecodeContext *) malloc(sizeof(FFVideoDecodeContext));
    }
    FFVideoDecodeContext *context = *decodeContext;
    memset(context, 0, sizeof(FFVideoDecodeContext));
    pipleNodeInit(&context->pipleNode, decodePacketFunc);
    context->decodeSetup   = decodeSetup;
    context->decodeUnSetup = decodeUnSetup;
    context->decodeStart   = decodeStart;
    context->decodeStop    = decodeStop;
    context->decodePacket  = GNULL;
}
GVoid GJ_FFDecodeContextDealloc(FFVideoDecodeContext **context) {
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

