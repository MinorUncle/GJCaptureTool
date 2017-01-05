//
//  RtmpSendH264.m
//  GJCaptureTool
//
//  Created by tongguan on 16/7/29.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import "RtmpSendH264.h"
#import <CoreMedia/CMFormatDescription.h>

#import "avcodec.h"
#import "swscale.h"
#import "imgutils.h"
#import "avio.h"
#import "avformat.h"

@interface RtmpSendH264()
@property(nonatomic,assign,readonly)AVPacket* videoPacket;
@property(nonatomic,assign,readonly)AVPacket* audioPacket;


@property(nonatomic,assign)AVFormatContext* ofmt_ctx;
@property(nonatomic,copy)NSString* outUrl;
@property(nonatomic,assign)int sample_rate;







@end
@implementation RtmpSendH264
@synthesize videoPacket = _videoPacket,audioPacket = _audioPacket;

- (instancetype)initWithOutUrl:(NSString*)outUrl
{
    self = [super init];
    if (self) {
        _outUrl = outUrl;
        _hasBFrame = YES;
        av_register_all();
        avformat_network_init();
    }
    return self;
}
-(void)setSps:(NSData *)sps{
    _sps = sps;
    if(_sps && _pps){
        [self analyseSpsPps];
    }
}
-(void)setPps:(NSData *)pps{
    _pps = pps;
    if(_sps && _pps){
        [self analyseSpsPps];
    }
}
-(void)setHasBFrame:(BOOL)hasBFrame{
    if (_hasBFrame == hasBFrame) {
        return;
    }
    _hasBFrame = hasBFrame;

}
-(void)analyseSpsPps{
    _videoExtradata = [[NSMutableData alloc]initWithCapacity:_pps.length+_sps.length];
    [_videoExtradata appendData:_sps];
    [_videoExtradata appendData:_pps];
    uint8_t*  parameterSetPointers[2] = {(uint8_t*)_sps.bytes, (uint8_t*)_pps.bytes};
    size_t parameterSetSizes[2] = {_sps.length-4, _pps.length-4};
    CMVideoFormatDescriptionRef  desc;
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                 (const uint8_t *const*)parameterSetPointers,
                                                                 parameterSetSizes, 4,
                                                                 &desc);
    if(status != 0){
        NSLog(@"sps_pps解析失败：%d",status);
    }
    CMVideoDimensions fordesc = CMVideoFormatDescriptionGetDimensions(desc);
    _width = fordesc.width,_height = fordesc.height;
    
    
}

-(void)setAudioStreamFormat:(AudioStreamBasicDescription)audioStreamFormat{
    _audioStreamFormat = audioStreamFormat;
    _sample_rate = audioStreamFormat.mSampleRate;
}
-(AVFormatContext *)ofmt_ctx{
    if (_ofmt_ctx == nil) {
        if (!_width || !_height || !_sample_rate) {
            return nil;
        }
        int ret;
        avformat_alloc_output_context2(&_ofmt_ctx, NULL, "flv", _outUrl.UTF8String); //RTMP
        if (!_ofmt_ctx) {
            printf( "Could not create output context\n");
            ret = AVERROR_UNKNOWN;
            goto end;
        }
        
        //video stream
        AVStream *out_video_stream = avformat_new_stream(_ofmt_ctx, nil);
        AVCodecParameters* out_code_parm = out_video_stream->codecpar;
        out_code_parm->codec_type = AVMEDIA_TYPE_VIDEO;
        out_code_parm->codec_id = AV_CODEC_ID_H264;
        out_code_parm->bit_rate = _videoBitRate;
        out_code_parm->extradata = (uint8_t*)_videoExtradata.bytes;
        out_code_parm->extradata_size = (int)_videoExtradata.length;
        out_code_parm->format = AV_PIX_FMT_YUV420P;
        out_code_parm->width = _width;
        out_code_parm->height = _height;
        out_video_stream->time_base = av_make_q(1,1);
        
        //audio stream
        AVStream *out_audio_stream = avformat_new_stream(_ofmt_ctx, nil);
        out_code_parm = out_audio_stream->codecpar;
        out_code_parm->codec_type = AVMEDIA_TYPE_AUDIO;
        out_code_parm->codec_id = AV_CODEC_ID_AAC;
        out_code_parm->bit_rate = _audioBitRate;
        out_code_parm->format = AV_SAMPLE_FMT_FLT;
        out_code_parm->channels = 1;
        out_code_parm->sample_rate = _audioStreamFormat.mSampleRate;
        out_video_stream->time_base = av_make_q(1,1);
        
        av_dump_format(_ofmt_ctx, 0, _outUrl.UTF8String, 1);
    }
    
    return _ofmt_ctx;
end:
    return nil;
}
-(void)_start{
    if (!(self.ofmt_ctx->flags & AVFMT_NOFILE)) {
        int ret = avio_open(&(self.ofmt_ctx->pb), _outUrl.UTF8String, AVIO_FLAG_WRITE);
        if (ret < 0) {
            NSLog( @"Could not open output URL '%@'", _outUrl);
            assert(0);
        }
    }
    
    //写文件头（Write file header）
    if (avformat_write_header(self.ofmt_ctx, NULL) < 0) {
        printf( "Error occurred when avformat_write_header\n");
        assert(0);
    }

}
-(void)_end{
    int r = av_write_trailer(self.ofmt_ctx);
    if (r < 0) {
        NSLog(@"av_write_trailer faile");
    }
}

-(AVPacket *)videoPacket{
    if (_videoPacket == nil) {
        _videoPacket = av_packet_alloc();
        _videoPacket->stream_index = 0;
        _videoPacket->pts = _videoPacket->dts = 0;
    }
    
    return _videoPacket;
}
-(AVPacket *)audioPacket{
    if (_audioPacket == nil) {
        _audioPacket = av_packet_alloc();
        _audioPacket->stream_index = 1;
        _audioPacket->pts = _audioPacket->dts = 0;

    }
    return _audioPacket;
}

static BOOL eof;
-(void)sendH264Buffer:(uint8_t*)buffer lengh:(int)lenth pts:(int64_t)pts dts:(int64_t)dts eof:(BOOL)isEof{
    if (_ofmt_ctx == nil) {
        if (![self ofmt_ctx]) {
            return;
        }
        eof = NO;
        [self _start];
    }
    if (isEof) {
        if (eof) {
            [self _end];
        }else{
            eof = YES;
        }
    }
    
    av_packet_from_data(self.videoPacket, buffer, lenth);
    self.videoPacket->duration = pts - self.videoPacket->pts;
    self.videoPacket->pts = pts;
    self.videoPacket->dts = dts;
    
    if (av_interleaved_write_frame(_ofmt_ctx, _videoPacket) < 0) {
        printf( "Error muxing packet\n");
    }
}
-(void)sendAACBuffer:(uint8_t*)buffer lenth:(int)lenth pts:(int64_t)pts dts:(int64_t)dts eof:(BOOL)isEof{
    if (_ofmt_ctx == nil) {
        if(![self ofmt_ctx]){
            return;
        }
        eof = NO;
        [self _start];
    }
    
    if (isEof) {
        if (eof) {
            [self _end];
        }else{
            eof = YES;
        }
    }
    av_packet_from_data(self.videoPacket, buffer, lenth);
    self.audioPacket->duration = pts - self.audioPacket->pts;
    self.audioPacket->pts = pts;
    self.audioPacket->dts = dts;
    
    if (av_interleaved_write_frame(_ofmt_ctx, _audioPacket) < 0) {
        printf( "Error muxing packet\n");
    }
}
@end
