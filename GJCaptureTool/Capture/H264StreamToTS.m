//
//  H264StreamToTS.m
//  Mp4ToTS
//
//  Created by tongguan on 16/7/14.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import "avformat.h"
#import "avcodec.h"
#import "opt.h"

#import "H264StreamToTS.h"

#define AUDIO_INDEX 1
#define VIDEO_INDEX 0

#define DEFAULT_TIME_PER_TS 10
@interface H264StreamToTS()
{
//    AVFormatContext* _icodec;
    AVFormatContext* _ocodec;
    AVStream * _ovideo_st;
    AVStream * _oaudio_st;
//    int video_stream_idx = -1;
//    int audio_stream_idx = -1;
//    AVCodec *audio_codec;
//    AVCodec *video_codec;
}
@end
@implementation H264StreamToTS
- (instancetype)initWithDestFilePath:(NSString*)filePath
{
    self = [super init];
    if (self) {
        _destFilePath = filePath;
        _preFileName = [filePath stringByDeletingPathExtension];
        NSArray* arry = [_preFileName componentsSeparatedByString:@"/"];
        _preFileName = arry.lastObject;
        
        
        _durationPerTs =  DEFAULT_TIME_PER_TS;
        av_register_all();
    }
    return self;
}

-(int)_init_mux
{
    int ret = 0;
    /* allocate the output media context */


    avformat_alloc_output_context2(&_ocodec, NULL,"mpegts", _destFilePath.UTF8String);

    if (!_ocodec)
    {
        return getchar();
    }
    AVOutputFormat* ofmt = NULL;
    ofmt = _ocodec->oformat;
    
    /* open the output file, if needed */
    if (!(ofmt->flags & AVFMT_NOFILE))
    {
        if (avio_open(&_ocodec->pb, _destFilePath.UTF8String, AVIO_FLAG_WRITE) < 0)
        {
            printf("Could not open '%s'\n", _destFilePath.UTF8String);
            return getchar();
        }
    }
    
    //这里添加的时候AUDIO_ID/VIDEO_ID有影响
    //添加音频信息到输出context
    _oaudio_st = [self add_out_stream:_ocodec type:AVMEDIA_TYPE_AUDIO];
    
    //添加视频信息到输出context
    _ovideo_st   = [self add_out_stream:_ocodec type:AVMEDIA_TYPE_VIDEO];
    
    av_dump_format(_ocodec, 0, _destFilePath.UTF8String, 1);
    
    ret = avformat_write_header(_ocodec, NULL);
    if (ret != 0)
    {
        printf("Call avformat_write_header function failed.\n");
        return 0;
    }
    return 1;
}
-(AVStream *)add_out_stream:(AVFormatContext*) output_format_context type:(enum AVMediaType)codec_type_t
{

    AVStream * output_stream = NULL;
    AVCodecContext* output_codec_context = NULL;
    
    output_stream = avformat_new_stream(output_format_context,NULL);
    if (!output_stream)
    {
        return NULL;
    }

    output_stream->id = output_format_context->nb_streams - 1;
    output_codec_context = output_stream->codec;
    output_stream->time_base  = (AVRational){1,1};
    output_stream->start_time = 0;
    output_stream->duration = -1;
    
    int ret = 0;
//    ret = avcodec_copy_context(output_stream->codec, in_stream->codec);
    if (ret < 0)
    {
        printf("Failed to copy context from input to output stream codec context\n");
        return NULL;
    }
    
    //这个很重要，要么纯复用解复用，不做编解码写头会失败,
    //另或者需要编解码如果不这样，生成的文件没有预览图，还有添加下面的header失败，置0之后会重新生成extradata
    output_codec_context->codec_tag = 0;
    
    //if(! strcmp( output_format_context-> oformat-> name,  "mp4" ) ||
    //!strcmp (output_format_context ->oformat ->name , "mov" ) ||
    //!strcmp (output_format_context ->oformat ->name , "3gp" ) ||
    //!strcmp (output_format_context ->oformat ->name , "flv"))
    if(AVFMT_GLOBALHEADER & output_format_context->oformat->flags)
    {
        output_codec_context->flags |= CODEC_FLAG_GLOBAL_HEADER;
    }
    return output_stream;
}
-(void)sendH264Stream:(uint8_t*)buffer lenth:(int)lengh pts:(int)pts dts:(int)dts{
    AVPacket packet;
    av_init_packet(&packet);
    av_packet_from_data(&packet, buffer, lengh);
    packet.pts = pts;
    packet.dts = dts;
    packet.stream_index = VIDEO_INDEX;
    [self slice_upPacket:&packet];
}
-(void)sendAACStream:(uint8_t*)buffer lenth:(int)lengh pts:(int)pts dts:(int)dts{
    AVPacket packet;
    av_init_packet(&packet);
    av_packet_from_data(&packet, buffer, lengh);
    packet.pts = pts;
    packet.dts = dts;
    packet.stream_index = AUDIO_INDEX;
}
static unsigned int first_segment = 1;     //第一个分片的标号
static unsigned int last_segment = 1;      //最后一个分片标号
static BOOL remove_file = 0;                //是否要移除文件（写在磁盘的分片已经达到最大）
static char remove_filename[256] = {0};    //要从磁盘上删除的文件名称
static char m_output_file_name[256];
static double prev_segment_time = 0;       //上一个分片时间
static int ret = 0;
static unsigned int actual_segment_durations[1024] = {0}; //各个分片文件实际的长度
static double segment_time ;


-(void)slice_upPacket:(AVPacket*)packet
{
    unsigned int current_segment_duration;
    segment_time = prev_segment_time;
    //这里是为了纠错，有文件pts为不可用值
    if (packet->pts < packet->dts)
    {
        packet->pts = packet->dts;
    }
    
    packet->pts = av_rescale_rnd(packet->pts, 1,_ovideo_st->time_base.num / _ovideo_st->time_base.den, AV_ROUND_NEAR_INF);
    packet->dts = av_rescale_rnd(packet->dts, 1,_ovideo_st->time_base.num / _ovideo_st->time_base.den, AV_ROUND_NEAR_INF);
    packet->duration = av_rescale_rnd(packet->duration,1, _ovideo_st->time_base.num / _ovideo_st->time_base.den, AV_ROUND_NEAR_INF);
    
    //视频
    if (packet->stream_index == VIDEO_INDEX )
    {
        printf("video\n");
    }
    else if (packet->stream_index == AUDIO_INDEX)
    {
        printf("audio\n");
    }
    
    current_segment_duration = (int)(segment_time - prev_segment_time + 0.5);
    actual_segment_durations[last_segment] = (current_segment_duration > 0 ? current_segment_duration: 1);
    
    if (segment_time - prev_segment_time >= _durationPerTs)
    {
        [self updateTSFile];
    }
    
    ret = av_interleaved_write_frame(_ocodec, packet);
    if (ret < 0)
    {
        printf("Warning: Could not write frame of stream\n");
    }
//        else if (ret > 0)
//        {
//            printf("End of stream requested\n");
//            av_free_packet(&packet);
//            break;
//        }
//        
//        av_free_packet(&packet);
    return;
}
-(BOOL)updateTSFile{
    ret = av_write_trailer(_ocodec);   // close ts file and free memory
    if (ret < 0)
    {
        printf("Warning: Could not av_write_trailer of stream\n");
        return NO;
    }
    avio_flush(_ocodec->pb);
    avio_close(_ocodec->pb);
    if (_numberOfMaxCountFiles >=0 && (int)(last_segment - first_segment) >= _numberOfMaxCountFiles)
    {
        remove_file = YES;
        first_segment++;
    }else{
        remove_file = 0;
    }
    //update TS
    [self write_index_file:first_segment last:last_segment end:0 durations:actual_segment_durations];
    
    if (remove_file)
    {
        sprintf(remove_filename,"%s_%u.ts",_preFileName.UTF8String,first_segment - 1);
        remove(remove_filename);
    }
    last_segment++;
    sprintf(m_output_file_name,"%s_%u.ts",_preFileName.UTF8String,last_segment);
    if (avio_open(&_ocodec->pb, m_output_file_name, AVIO_FLAG_WRITE) < 0)
    {
        printf("Could not open '%s'\n", _destFilePath.UTF8String);
        return NO;
    }
    
    // Write a new header at the start of each file
    if (avformat_write_header(_ocodec, NULL))
    {
        printf("Could not write mpegts header to first output file\n");
        return NO;
    }
    prev_segment_time = segment_time;
    return YES;
}
-(int) write_index_file:(const unsigned int )first_segment  last:(const unsigned int) last_segment end:(const int)end durations:( const unsigned int []) actual_segment_durations
{
    FILE *index_fp = NULL;
    char *write_buf = NULL;
    unsigned int i = 0;
    char m3u8_file_pathname[256] = {0};
    sprintf(m3u8_file_pathname,"%s",_destFilePath.UTF8String);
    
    index_fp = fopen(m3u8_file_pathname,"w");
    if (!index_fp)
    {
        printf("Could not open m3u8 index file (%s), no index file will be created\n",(char *)m3u8_file_pathname);
        return -1;
    }
    
    write_buf = (char *)malloc(sizeof(char) * 1024);
    if (!write_buf)
    {
        printf("Could not allocate write buffer for index file, index file will be invalid\n");
        fclose(index_fp);
        return -1;
    }
    
    
    if (1)
    {
        //#EXT-X-MEDIA-SEQUENCE：<Number> 播放列表文件中每个媒体文件的URI都有一个唯一的序列号。URI的序列号等于它之前那个RUI的序列号加一(没有填0)
        sprintf(write_buf,"#EXTM3U\n#EXT-X-TARGETDURATION:%d\n#EXT-X-MEDIA-SEQUENCE:%u\n",_durationPerTs,first_segment);
    }else{
        sprintf(write_buf,"#EXTM3U\n#EXT-X-TARGETDURATION:%d\n",_durationPerTs);
    }
    if (fwrite(write_buf, strlen(write_buf), 1, index_fp) != 1)
    {
        printf("Could not write to m3u8 index file, will not continue writing to index file\n");
        free(write_buf);
        fclose(index_fp);
        return -1;
    }
    
    for (i = first_segment; i < last_segment; i++)
    {
        sprintf(write_buf,"#EXTINF:%u,\n%s_%u.ts\n",actual_segment_durations[i-1],_preFileName.UTF8String,i);
        if (fwrite(write_buf, strlen(write_buf), 1, index_fp) != 1)
        {
            printf("Could not write to m3u8 index file, will not continue writing to index file\n");
            free(write_buf);
            fclose(index_fp);
            return -1;
        }
    }
    
    if (end)
    {
        sprintf(write_buf,"#EXT-X-ENDLIST\n");
        if (fwrite(write_buf, strlen(write_buf), 1, index_fp) != 1)
        {
            printf("Could not write last file and endlist tag to m3u8 index file\n");
            free(write_buf);
            fclose(index_fp);
            return -1;
        }
    }
    
    free(write_buf);
    fclose(index_fp);
    return 0;
}
-(void)stop{
    [self uinit_mux];
    [self write_index_file:first_segment last:last_segment end:1 durations:actual_segment_durations];
}
-(void)start{
    [self _init_mux];
    [self write_index_file:first_segment last:last_segment end:0 durations:actual_segment_durations];
}
-(int) uinit_mux
{
    char szError[256];
    int i = 0;
    int nRet = av_write_trailer(_ocodec);
    if (nRet < 0)
    {
        av_strerror(nRet, szError, 256);
        printf("%s",szError);
        printf("\n");
        printf("Call av_write_trailer function failed\n");
    }
    
    /* Free the streams. */
    for (i = 0; i < _ocodec->nb_streams; i++)
    {
        av_freep(&_ocodec->streams[i]->codec);
        av_freep(&_ocodec->streams[i]);
    }
    if (!(_ocodec->oformat->flags & AVFMT_NOFILE))
    {
        /* Close the output file. */
        avio_close(_ocodec->pb);
    }
    av_free(_ocodec);
    return 1;
}


@end
