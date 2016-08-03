//
//  H264Encoder.m
//  FFMpegDemo
//
//  Created by tongguan on 16/7/12.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

extern "C"{
#import "avcodec.h"
#import "imgutils.h"
}
#import "H264Encoder.h"
#import "GJQueue.h"
@interface H264Encoder()
{
    AVCodec* _videoEncoder;
    AVCodecContext* _videoEncoderContext;
    AVCodec* _audioEncoder;
    AVCodecContext* _audioEncoderContext;
    AVFrame* _frame;
//    AVFrame* _yuvFrame;
    AVPacket* _videoPacket;
    dispatch_queue_t _videoDecodeQueue;
    GJQueue<char*>* _queue;

}
@end
@implementation H264Encoder
@synthesize height = _height,width = _width;
- (instancetype)initWithWidth:(int)width height:(int)height
{
    self = [super init];
    if (self) {
        _height = height;
        _width = width;
        _max_b_frames = 4;
        _gop_size = 20;
        _bit_rate = 400000;
        [self _createEncoder];
    }
    return self;
}
-(void)_createEncoder{
    avcodec_register_all();
    _videoDecodeQueue = dispatch_queue_create("vidoeDecode", DISPATCH_QUEUE_CONCURRENT);
    
    _videoEncoder = avcodec_find_encoder(AV_CODEC_ID_H264);
    _videoEncoderContext = avcodec_alloc_context3(_videoEncoder);
    _videoEncoderContext->pix_fmt = AV_PIX_FMT_YUV420P;
    _videoEncoderContext->width = _width;
    _videoEncoderContext->height = _height;
    _videoEncoderContext->gop_size = _gop_size;
    _videoEncoderContext->time_base.num=1;
    _videoEncoderContext->time_base.den=25;
    _videoEncoderContext->bit_rate = _bit_rate;
    _videoEncoderContext->bit_rate_tolerance = 200;
    _videoEncoderContext->max_b_frames = _max_b_frames;

    int errorCode = avcodec_open2(_videoEncoderContext, _videoEncoder, nil);
    [self showErrWidhCode:errorCode preStr:@"avcodec_open2"];

    _videoPacket = av_packet_alloc();
    _frame =av_frame_alloc();
    _frame->width = _videoEncoderContext->width;
    _frame->height = _videoEncoderContext->height;
    _frame->format = AV_PIX_FMT_YUV420P;
    
    
    _queue = new GJQueue<char*>(2);
    _queue->shouldNonatomic = YES;
    _queue->shouldWait = YES;
    for (int i = 0; i<2; i++) {
        char* data = (char*)malloc(_videoEncoderContext->width* _videoEncoderContext->height*1.5);
        _queue->queuePush(data);
    }
}
static int framePts = 0;
-(void)encoderData:(CMSampleBufferRef)sampleBufferRef{
    CVImageBufferRef imgRef = CMSampleBufferGetImageBuffer(sampleBufferRef);
    
#ifdef DEBUG
    int w = (int)CVPixelBufferGetWidth(imgRef);
    int h = (int)CVPixelBufferGetHeight(imgRef);
    if (w != _width || h != _height) {
        exit(1);
    }
    
#endif
    
    
    CVPixelBufferLockBaseAddress(imgRef, 0);
    uint8_t* address = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(imgRef, 0);
    _frame->linesize[0] = (int)CVPixelBufferGetWidthOfPlane(imgRef, 0);
    _frame->linesize[1] = (int)CVPixelBufferGetWidthOfPlane(imgRef, 1);
    _frame->pts = framePts++;

    int errorCode = av_image_fill_arrays(_frame->data, _frame->linesize, address, _videoEncoderContext->pix_fmt, _width, _height, 1);

    
    [self showErrWidhCode:errorCode preStr:@"av_image_fill_arrays"];
    errorCode = avcodec_send_frame(_videoEncoderContext, _frame);
    [self showErrWidhCode:errorCode preStr:@"avcodec_send_frame"];
    CVPixelBufferUnlockBaseAddress(imgRef, 0);

    errorCode = avcodec_receive_packet(_videoEncoderContext, _videoPacket);
    [self showErrWidhCode:errorCode preStr:@"avcodec_receive_packet"];
    
    if (!errorCode) {
        [self.delegate H264Encoder:self h264:_videoPacket->data size:_videoPacket->size];
    }

}
-(void)showErrWidhCode:(int)errorCode preStr:(NSString*)preStr{
    char* c = (char*)&errorCode;
    if (errorCode <0 ) {
        NSString* err;
        if (errorCode == AVERROR(EAGAIN)) {
            err = @"EAGAIN";
        }else if(errorCode == AVERROR(EINVAL)){
            err = @"EINVAL";
        }else if (errorCode == AVERROR_EOF){
            err = @"AVERROR_EOF";
        }else if (errorCode == AVERROR(ENOMEM)){
            err = @"AVERROR(ENOMEM)";
        }
        if (preStr == nil) {
            preStr = @"";
        }
        NSLog(@"%@:%c%c%c%c error:%@，code:%d",preStr,c[3],c[2],c[1],c[0],err,errorCode);
    }else{
        NSLog(@"%@成功",preStr);
    }
}

@end
