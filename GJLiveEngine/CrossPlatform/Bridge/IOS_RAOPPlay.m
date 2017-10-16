//
//  IOS_RAOPPlay.m
//  GJCaptureTool
//
//  Created by melot on 2017/7/28.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_RAOPPlay.h"
#import "GJAudioManager.h"
#import "GJBridegContext.h"
#import "GJLivePushContext.h"
#import "GJLog.h"
#include "audiooutput.h"
extern double hardware_host_time_to_seconds(double host_time);

@implementation IOS_RAOPPlay

@end

typedef void (*audio_output_callback)(audio_output_p ao, void *buffer, size_t size, double host_time, void *ctx);

struct audio_output_t {
    struct decoder_output_format_t format;
    bool                           has_speed_control;
    void *                         blockChannel;
    void *                         audioManager;
    AudioConverterRef              _convert;
    AudioBufferList                convertOutBuffer;
    AudioBufferList *              convertInBuffer;

    audio_output_callback callback;
    void *                callback_ctx;
    bool                  mute;
    float                 speed;
    float                 volume;

    void *globalUserData;
};

void audio_output_stop(struct audio_output_t *ao);
static OSStatus decodeInputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {

    struct audio_output_t *ao = (struct audio_output_t *) inUserData;
    *ioData                   = *(ao->convertInBuffer);
    *ioNumberDataPackets      = ioData->mBuffers[0].mDataByteSize / ao->format.frame_size;

    return noErr;
}
struct audio_output_t *audio_output_create(struct decoder_output_format_t decoder_output_format, void *globalUserData) {

    struct audio_output_t *ao = (struct audio_output_t *) malloc(sizeof(struct audio_output_t));
    bzero(ao, sizeof(struct audio_output_t));
    ao->format         = decoder_output_format;
    ao->speed          = 1.0;
    ao->volume         = 1.0;
    ao->mute           = false;
    ao->globalUserData = globalUserData;

    GJLivePushContext *context = ao->globalUserData;
    GJAudioManager *   manager = (__bridge GJAudioManager *) (context->audioProducer->obaque);
    ao->audioManager           = (__bridge_retained void *) manager;

    AudioStreamBasicDescription destFormat = manager.audioController.audioDescription;

    if (destFormat.mBitsPerChannel != decoder_output_format.bit_depth ||
        destFormat.mSampleRate != decoder_output_format.sample_rate ||
        destFormat.mChannelsPerFrame != decoder_output_format.channels) {

        AudioStreamBasicDescription sourFormat = {0};
        sourFormat.mBitsPerChannel             = decoder_output_format.bit_depth;
        sourFormat.mSampleRate                 = decoder_output_format.sample_rate;
        sourFormat.mBytesPerFrame              = decoder_output_format.frame_size;
        sourFormat.mFramesPerPacket            = decoder_output_format.frames_per_packet;
        sourFormat.mFormatID                   = kAudioFormatLinearPCM;
        sourFormat.mFormatFlags                = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;

        UInt32 size = sizeof(AudioStreamBasicDescription);
        AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &destFormat);
        AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &sourFormat);
        OSStatus status = AudioConverterNew(&sourFormat, &destFormat, &ao->_convert);

        if (status != noErr) {

            ao->convertOutBuffer.mNumberBuffers = 0;
            ao->_convert                        = NULL;

        } else {

            ao->convertOutBuffer.mNumberBuffers              = 1;
            ao->convertOutBuffer.mBuffers[0].mData           = malloc(8192);
            ao->convertOutBuffer.mBuffers[0].mDataByteSize   = 8192;
            ao->convertOutBuffer.mBuffers[0].mNumberChannels = destFormat.mChannelsPerFrame;
        }
    }

    AEBlockChannel *blockChannel = [AEBlockChannel channelWithBlock:^(const AudioTimeStamp *time, UInt32 frames, AudioBufferList *audio) {

        if (ao->_convert) {
            ao->convertInBuffer = audio;
            AudioConverterFillComplexBuffer(ao->_convert, decodeInputDataProc, ao, &frames, &ao->convertOutBuffer, nil);
        }
        ao->callback(ao, audio->mBuffers[0].mData, audio->mBuffers[0].mDataByteSize, hardware_host_time_to_seconds(time->mHostTime), ao->callback_ctx);

    }];

    ao->blockChannel = (__bridge_retained void *) (blockChannel);

    return ao;
}

void audio_output_destroy(struct audio_output_t *ao) {

    GJAudioManager *manager = (__bridge_transfer GJAudioManager *) (ao->audioManager);

    [manager.audioController performSynchronousMessageExchangeWithBlock:^{
        audio_output_stop(ao);

        if (ao->_convert) {
            AudioConverterDispose(ao->_convert);
        }
        for (int i = 0; i < ao->convertOutBuffer.mNumberBuffers; i++) {
            if (ao->convertOutBuffer.mBuffers[i].mData) {
                free(ao->convertOutBuffer.mBuffers[0].mData);
            }
        }

        free(ao);
        GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "audio_output_destroy");
    }];
}
void audio_output_set_volume(struct audio_output_t *ao, double volume) {

    ao->volume = volume;
    if (ao->blockChannel) {
        AEBlockChannel *channel = (__bridge AEBlockChannel *) (ao->blockChannel);
        channel.volume          = volume;
    }
}

void audio_output_set_callback(struct audio_output_t *ao, audio_output_callback callback, void *ctx) {

    ao->callback     = callback;
    ao->callback_ctx = ctx;
}

void audio_output_start(struct audio_output_t *ao) {

    AEBlockChannel *channel = (__bridge AEBlockChannel *) ao->blockChannel;

    GJAudioManager *manager = (__bridge GJAudioManager *) (ao->audioManager);

    [manager.audioController addChannels:@[ channel ]];
}

void audio_output_stop(struct audio_output_t *ao) {

    GJAudioManager *manager = (__bridge GJAudioManager *) (ao->audioManager);

    [manager.audioController removeChannels:@[ (__bridge AEBlockChannel *) ao->blockChannel ]];
}

void audio_output_flush(struct audio_output_t *ao) {
}

double audio_output_get_playback_rate(audio_output_p ao) {

    return 1.0;
}
void audio_output_set_playback_rate(audio_output_p ao, double playback_rate) {
}
void audio_output_set_muted(struct audio_output_t *ao, bool muted) {

    ao->mute = muted;
    if (ao->blockChannel) {
        AEBlockChannel *channel = (__bridge AEBlockChannel *) (ao->blockChannel);
        channel.channelIsMuted  = muted;
    }
}
