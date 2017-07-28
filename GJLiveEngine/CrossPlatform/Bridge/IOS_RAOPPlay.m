//
//  IOS_RAOPPlay.m
//  GJCaptureTool
//
//  Created by melot on 2017/7/28.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_RAOPPlay.h"
#import "GJBridegContext.h"
#include "audiooutput.h"
@implementation IOS_RAOPPlay

@end

typedef void (*audio_output_callback)(audio_output_p ao, void* buffer, size_t size, double host_time, void* ctx);


struct audio_output_t {
    struct decoder_output_format_t format;
    bool has_speed_control;
    void* blockChannel;
    audio_output_callback callback;
    void* callback_ctx;
    bool mute;
    float speed;
    float volume;
    
    void* globalUserData;
};

void audio_output_stop(struct audio_output_t* ao);

struct audio_output_t* audio_output_create(struct decoder_output_format_t decoder_output_format,void* globalUserData) {
    
    struct audio_output_t* ao = (struct audio_output_t*)malloc(sizeof(struct audio_output_t));
    bzero(ao, sizeof(struct audio_output_t));
    ao->format = decoder_output_format;
    ao->speed = 1.0;
    ao->volume = 1.0;
    ao->mute = false;
    ao->globalUserData = globalUserData;
//    AEBlockChannel* blockChannel = [AEBlockChannel channelWithBlock:^(const AudioTimeStamp *time, UInt32 frames, AudioBufferList *audio) {
//        ao->callback(ao, audio->mBuffers[0].mData, audio->mBuffers[0].mDataByteSize, hardware_host_time_to_seconds(time->mHostTime), ao->callback_ctx);
//    }];
//    
//    ao->blockChannel = (__bridge_retained void *)(blockChannel);

    
    return ao;
    
}

void audio_output_destroy(struct audio_output_t* ao) {
    
    audio_output_stop(ao);
//    AEBlockChannel* channel = CFBridgingRelease(ao->blockChannel);
//    channel = nil;

    
    free(ao);
    
}

void audio_output_set_callback(struct audio_output_t* ao, audio_output_callback callback, void* ctx) {
    
    ao->callback = callback;
    ao->callback_ctx = ctx;
    
}

void audio_output_session_start () {
//    [[GJAudioManager shareAudioManager].audioController addChannels:@[channel]];

}


void audio_output_stop(struct audio_output_t* ao) {
//    [[GJAudioManager shareAudioManager].audioController removeChannels:@[(__bridge AEBlockChannel*)ao->blockChannel]];

    
}

void audio_output_flush(struct audio_output_t* ao) {
    
    
}

double audio_output_get_playback_rate(audio_output_p ao) {
    

    
    return 1.0;
    
}

void audio_output_set_muted(struct audio_output_t* ao, bool muted) {
//    ao->mute = muted;
//    if (ao->blockChannel) {
//        AEBlockChannel* channel = (__bridge AEBlockChannel *)(ao->blockChannel);
//        channel.channelIsMuted = muted;
//    }
    
    
}
