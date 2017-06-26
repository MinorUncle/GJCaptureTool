//
//  AEAudioSender.m
//  TheAmazingAudioEngine
//
//  Created by lbzhao on 2017/5/8.
//  Copyright © 2017年 A Tasty Pixel. All rights reserved.
//

#import "AEAudioSender.h"
#import "AEMixerBuffer.h"

#define kProcessChunkSize 1024

@interface AEAudioSender(){
    AudioBufferList *_buffer;
}
@property (nonatomic, strong) AEMixerBuffer *mixer;

@end

@implementation AEAudioSender
- (id)initWithAudioController:(AEAudioController*)audioController {
    if ( !(self = [super init]) ) return nil;
    self.mixer = [[AEMixerBuffer alloc] initWithClientFormat:audioController.audioDescription];
    
    if ( audioController.inputEnabled && audioController.audioInputAvailable && audioController.inputAudioDescription.mChannelsPerFrame != audioController.audioDescription.mChannelsPerFrame ) {
        [_mixer setAudioDescription:*AEAudioControllerInputAudioDescription(audioController) forSource:AEAudioSourceInput];
    }
    _buffer = AEAudioBufferListCreate(audioController.audioDescription, 0);
    return self;
}

-(void)dealloc {
    free(_buffer);
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
        [THIS.delegate AEAudioSenderPushData:THIS->_buffer withTime:time];
    }
}

-(AEAudioReceiverCallback)receiverCallback {
    return audioCallback;
}
@end
