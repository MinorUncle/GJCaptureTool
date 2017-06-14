//
//  GJFLVPack.h
//  GJCaptureTool
//
//  Created by melot on 2017/6/13.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJFLVPack_h
#define GJFLVPack_h

#include <stdio.h>


//flv tag type
typedef enum GJ_flv_tag_type {
    GJ_flv_tag_type_audio = 8,
    GJ_flv_tag_type_video = 9,
    GJ_flv_tag_type_script = 18,
} GJ_flv_tag_type;

//共6种(CodecID)，这里只用h264
typedef enum GJ_flv_v_codec_id{
    GJ_flv_v_codec_id_H263 = 2,
    GJ_flv_v_codec_id_H264 = 7,
} GJ_flv_v_codec_id;

//共13种(即sound format)，这里只用aac
typedef enum GJ_flv_a_codec_id{
    GJ_flv_a_codec_id_MP3 = 2,
    GJ_flv_a_codec_id_AAC = 10,
} GJ_flv_a_codec_id;

//sound size 8bit 16bit
typedef enum GJ_flv_a_sound_size{
    GJ_flv_a_sound_size_8_bit = 0,
    GJ_flv_a_sound_size_16_bit = 1,
} GJ_flv_a_sound_size;

//sound rate 5.5 11 22 44 kHz
typedef enum GJ_flv_a_sound_rate{
    GJ_flv_a_sound_rate_5_5kHZ = 0,
    GJ_flv_a_sound_rate_11kHZ = 1,
    GJ_flv_a_sound_rate_22kHZ = 2,
    GJ_flv_a_sound_rate_44kHZ = 3,
} GJ_flv_a_sound_rate;

//sound type mono/stereo
typedef enum GJ_flv_a_sound_type{
    GJ_flv_a_sound_type_mono = 0,
    GJ_flv_a_sound_type_stereo = 1,
} GJ_flv_a_sound_type;

//共5种
typedef enum GJ_flv_v_frame_type{
    GJ_flv_v_frame_type_key = 1,//关键帧
    GJ_flv_v_frame_type_inner = 2,//非关键帧
}GJ_flv_v_frame_type;

//h264 packet type
typedef enum GJ_flv_v_h264_packet_type{
    GJ_flv_v_h264_packet_type_seq_header = 0,
    GJ_flv_v_h264_packet_type_nalu = 1,
    GJ_flv_v_h264_packet_type_end_of_seq = 2,
}GJ_flv_v_h264_packet_type;

typedef enum GJ_flv_a_aac_packge_type{
    GJ_flv_a_aac_package_type_aac_sequence_header = 0,
    GJ_flv_a_aac_package_type_aac_raw = 1,
}GJ_flv_a_aac_packge_type;


#endif /* GJFLVPack_h */
