//
//  H264Decoder.m
//  FFMpegDemo
//
//  Created by tongguan on 16/6/15.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//


#import "libavformat/avformat.h"
#import "libswscale/swscale.h"

#import "GJQueue.h"
#import "H264Decoder.h"
@interface H264Decoder()
{
    AVFormatContext *_formatContext;
    AVCodec* _videoDecoder;
    AVCodecContext* _videoDecoderContext;
    struct SwsContext* _videoSwsContext;
    AVCodec* _audioDecoder;
    AVCodecContext* _audioDecoderContext;
    AVFrame* _frame;
    AVPacket* _videoPacket;
    AVFrame* _yuvFrame;
    dispatch_queue_t _videoDecodeQueue;
}
@end
@implementation H264Decoder

- (instancetype)initWithWidth:(int)width height:(int)height
{
    self = [super init];
    if (self) {
        avcodec_register_all();
        _width = width;
        _height = height;
    }
    
    return self;
}
-(void)_createDecode{
    _videoDecodeQueue = dispatch_queue_create("vidoeDecode", DISPATCH_QUEUE_CONCURRENT);
    _formatContext = avformat_alloc_context();
    _videoDecoder =  avcodec_find_decoder(AV_CODEC_ID_H264);
    
    _videoDecoderContext = avcodec_alloc_context3(_videoDecoder);
    _videoDecoderContext->width = _width;
    _videoDecoderContext->height = _height;
    _videoDecoderContext->pix_fmt = AV_PIX_FMT_YUV420P;
//    _videoDecoderContext->time_base
    
    int errorCode = avcodec_open2(_videoDecoderContext, _videoDecoder, nil);
    [self showErrWidhCode:errorCode preStr:@"avcodec_open2"];
    _videoSwsContext = sws_getContext(_videoDecoderContext->width, _videoDecoderContext->height, _videoDecoderContext->pix_fmt, _videoDecoderContext->width, _videoDecoderContext->height, AV_PIX_FMT_YUV420P, SWS_BICUBIC, NULL, NULL, NULL);

    
    _videoPacket = av_packet_alloc();
    _frame =av_frame_alloc();
    _yuvFrame = av_frame_alloc();
    _yuvFrame->width = _width;
    _yuvFrame->height = _height;
    _yuvFrame->format = _videoDecoderContext->pix_fmt;
    av_frame_get_buffer(_yuvFrame, 1);
    
}


-(void)decodeData:(uint8_t*)data lenth:(int)lenth{
    if (_videoDecoderContext == nil) {
        [self _createDecode];
    }
    
    int errorCode = av_packet_from_data(_videoPacket, data, lenth);
    [self showErrWidhCode:errorCode preStr:@"av_packet_from_data"];

    
    errorCode = avcodec_send_packet(_videoDecoderContext, _videoPacket);
    [self showErrWidhCode:errorCode preStr:@"avcodec_send_packet"];
    

    errorCode = avcodec_receive_frame(_videoDecoderContext, _frame);
    if(errorCode< 0){
        [self showErrWidhCode:errorCode preStr:@"avcodec_receive_frame"];
        return;
    }
    switch (_frame->pict_type) {
        case AV_PICTURE_TYPE_I:
            printf("i帧--------\n");
            break;
        case AV_PICTURE_TYPE_P:
            printf("p帧--------\n");
            break;
        case AV_PICTURE_TYPE_B:
            printf("b帧--------\n");
            break;
            
        default:
            printf("其他帧--------\n");
            break;
    }
    
    errorCode = sws_scale(_videoSwsContext, _frame->data, _frame->linesize,0, _videoDecoderContext->height, _yuvFrame->data, _yuvFrame->linesize);
    if (errorCode<0) {
        [self showErrWidhCode:errorCode preStr:@"sws_scale"];
        return;
    }
    float width = _yuvFrame->linesize[0];
    float height = _yuvFrame->height;
    int y_size= width * height;
    char* yuvdata = (char*)malloc(y_size*1.5);

    memcpy(yuvdata, _yuvFrame->data[0], y_size);
    memcpy(yuvdata+y_size, _yuvFrame->data[1], y_size/4.0);
    memcpy(yuvdata+y_size+y_size/4, _yuvFrame->data[2], y_size/4.0);

    if (errorCode > 0) {
        [self.decoderDelegate H264Decoder:self GetYUV:yuvdata size:y_size*1.5 width:width height:height];
    }
    
}



-(void)decode{
    if (_status == H264DecoderPlaying) {
        [self _decodeData];
        [self _parpareData];
    }
}
-(BOOL)_parpareData{
    int result = av_read_frame(_formatContext, _videoPacket);
    if (result<0) {
        [self showErrWidhCode:result preStr:@"av_read_frame"];
        if (result == AVERROR_EOF) {
            [self stop];
        }
        return NO;
    }
    result = avcodec_send_packet(_videoDecoderContext, _videoPacket);
    if (result<0) {
        [self showErrWidhCode:result preStr:@"avcodec_send_packet"];
        return NO;
    }
    return YES;
}
-(void)_decodeData{
    if (_status == H264DecoderStopped) {
        return;
    }
    int result = avcodec_receive_frame(_videoDecoderContext, _frame);
    if(result< 0){
        [self showErrWidhCode:result preStr:@"avcodec_receive_frame"];
        return;
    }
    result = sws_scale(_videoSwsContext, _frame->data, _frame->linesize,0, _videoDecoderContext->height, _yuvFrame->data, _yuvFrame->linesize);
    if (result<0) {
        [self showErrWidhCode:result preStr:@"sws_scale"];
        return;
    }
    float width = _yuvFrame->linesize[0];
    float height = _yuvFrame->height;
    int y_size= width * height;
    char* data;

    memcpy(data, _yuvFrame->data[0], y_size);
    memcpy(data+y_size, _yuvFrame->data[1], y_size/4.0);
    memcpy(data+y_size+y_size/4, _yuvFrame->data[2], y_size/4.0);
   
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
        NSLog(@"%@:%c%c%c%c error:%@",preStr,c[3],c[2],c[1],c[0],err);
    }else{
        NSLog(@"%@成功",preStr);
    }
}
-(void)dealloc{


}
@end
