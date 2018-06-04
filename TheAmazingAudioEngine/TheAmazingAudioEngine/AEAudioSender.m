//
//  AEAudioSender.m
//  TheAmazingAudioEngine
//
//  Created by lbzhao on 2017/5/8.
//  Copyright © 2017年 A Tasty Pixel. All rights reserved.
//

#import "AEAudioSender.h"
#import "AEMixerBuffer.h"

#define kProcessChunkSize 8192

@interface AEAudioSender(){
    AudioBufferList *_buffer;
    unsigned char   *_audioSenderData;
    int             _audioSenderDataOffset;
    UInt64          _old_frameTime;
    UInt64          _retainTime;
}
@property (nonatomic, strong) AEMixerBuffer *mixer;

@end

@implementation AEAudioSender

- (instancetype)init
{
    self = [super init];
    if (self) {
        _audioSenderData = (unsigned char*)malloc(4096 * 2 *sizeof(unsigned char));
        _audioSenderDataOffset = 0;
        _old_frameTime  = 0;
        _retainTime     = 0;

    }
    return self;
}
-(void)setupWithAudioController:(AEAudioController *)audioController{
    self.mixer = [[AEMixerBuffer alloc] initWithClientFormat:audioController.audioDescription];
    
    if ( audioController.inputEnabled && audioController.audioInputAvailable && audioController.inputAudioDescription.mChannelsPerFrame != audioController.audioDescription.mChannelsPerFrame ) {
        [_mixer setAudioDescription:*AEAudioControllerInputAudioDescription(audioController) forSource:AEAudioSourceInput];
    }
    _buffer = AEAudioBufferListCreate(audioController.audioDescription, 0);
}
-(void)dealloc {
    free(_buffer);
    free(_audioSenderData);
    _audioSenderDataOffset = 0;
}

static void audioCallback(__unsafe_unretained AEAudioSender *THIS,
                          __unsafe_unretained AEAudioController *audioController,
                          void                     *source,
                          const AudioTimeStamp     *time,
                          UInt32                    frames,
                          AudioBufferList          *audio) {
    
    AEMixerBufferEnqueue(THIS->_mixer, source, audio, frames, time);
    
    // Let the mixer buffer provide the audio buffer
    UInt32 bufferLength = kProcessChunkSize;
    for ( int i=0; i<THIS->_buffer->mNumberBuffers; i++ ) {
        THIS->_buffer->mBuffers[i].mData = NULL;
        THIS->_buffer->mBuffers[i].mDataByteSize = 0;
    }
    
    AEMixerBufferDequeue(THIS->_mixer, THIS->_buffer, &bufferLength, NULL);
    
    if ( bufferLength > 0 ) {
        [THIS->_delegate AEAudioSenderPushData:THIS->_buffer withTime:time];
    }
}

-(AEAudioReceiverCallback)receiverCallback {
    return audioCallback;
}
@end
