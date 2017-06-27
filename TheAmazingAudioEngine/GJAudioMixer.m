//
//  GJAudioMixer.m
//  TheAmazingAudioEngine
//
//  Created by melot on 2017/6/27.
//  Copyright © 2017年 A Tasty Pixel. All rights reserved.
//

#import "GJAudioMixer.h"
#import "AEUtilities.h"
#define MAX_MIX_COUNT 4
@interface GJAudioMixer(){
    AUGraph                     _graph;
    AUNode                      _mixerNode;
    AudioUnit                   _mixerUnit;
    UInt32                        _mixCount;
    AudioStreamBasicDescription _clientFormat;
    AudioBufferList* _reanderBufferList;
    AudioBufferList* _inputSource[MAX_MIX_COUNT];
    int                 _intputCount;
    NSMutableDictionary* _receiveSource;
    int _currentCount;
    int _receiveBox[MAX_MIX_COUNT];
}
@property(nonatomic,weak)AEAudioController* audioController;
@end
@implementation GJAudioMixer
static void receiverCallback(__unsafe_unretained id    receiver,__unsafe_unretained AEAudioController *audioController,void *source,const AudioTimeStamp *time,UInt32 frames,AudioBufferList *audio){
    GJAudioMixer* mixer = receiver;
    NSNumber* index = mixer->_receiveSource[@((long)source)];
    NSUInteger bus = 0;
    if (index) {
        bus = index.unsignedIntegerValue;
        
    }else{
        for (bus = 0 ; bus < MAX_MIX_COUNT; bus++) {
            if (![mixer->_receiveSource.allValues containsObject:@(bus)]) {
                break;
            }
        }
        if (bus<MAX_MIX_COUNT) {
            [mixer->_receiveSource setObject:@(bus) forKey:@((long)source)];
        }else{
            NSLog(@"混合流数量超过最大");
            return;
        }
    }

    if (mixer->_intputCount == 1) {
        [mixer.delegate audioMixerProduceFrameWith:audio time:(int64_t)([[NSDate date]timeIntervalSince1970]*1000)];
        mixer->_currentCount = 0;
        mixer->_receiveBox[bus] = 0;
    }else{
        if (mixer->_receiveBox[bus] == 1) {//重复
            [mixer unitRenderWithCount:frames];
            
            for (int i = 0; i<audio->mNumberBuffers; i++) {
                memcpy(mixer->_inputSource[bus]->mBuffers[i].mData, audio->mBuffers[i].mData, audio->mBuffers[i].mDataByteSize);
                mixer->_inputSource[bus]->mBuffers[i].mDataByteSize = audio->mBuffers[i].mDataByteSize;
            }
            mixer->_receiveBox[bus] = 1;
            mixer->_currentCount = 1;
        }else {
            mixer->_currentCount++;
            for (int i = 0; i<audio->mNumberBuffers; i++) {
                memcpy(mixer->_inputSource[bus]->mBuffers[i].mData, audio->mBuffers[i].mData, audio->mBuffers[i].mDataByteSize);
                mixer->_inputSource[bus]->mBuffers[i].mDataByteSize = audio->mBuffers[i].mDataByteSize;
            }
            if (mixer->_currentCount == mixer->_intputCount) {
                [mixer unitRenderWithCount:frames];
            }else if(mixer->_currentCount > mixer->_intputCount){
                NSLog(@"err:%p  time:%f",source,time->mSampleTime);

            }
        }
    }
    
//    NSLog(@"source:%p  time:%f",source,time->mSampleTime);

}

static OSStatus sourceInputCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    GJAudioMixer* audioMix = (__bridge GJAudioMixer *)(inRefCon);
    for ( int i=0; i<ioData->mNumberBuffers; i++ ) {
        memcpy(ioData->mBuffers[i].mData,audioMix->_inputSource[inBusNumber]->mBuffers[i].mData,audioMix->_inputSource[inBusNumber]->mBuffers[i].mDataByteSize);
        ioData->mBuffers[i].mNumberChannels = audioMix->_inputSource[inBusNumber]->mBuffers[i].mNumberChannels;
        ioData->mBuffers[i].mDataByteSize = audioMix->_inputSource[inBusNumber]->mBuffers[i].mDataByteSize;
    }
//    NSLog(@"inBusNumber:%d  time:%f",inBusNumber,inTimeStamp->mSampleTime);
    return noErr;
}
-(void)unitRenderWithCount:(UInt32)frames{
    _mixCount+=frames;
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp renderTimestamp = {0};
    renderTimestamp.mFlags = kAudioTimeStampSampleTimeValid;
    renderTimestamp.mSampleTime = (Float64)_mixCount;
    OSStatus result = AudioUnitRender(_mixerUnit, &flags, &renderTimestamp, 0, frames, _reanderBufferList);
    if (result != noErr) {
        NSLog(@"AudioUnitRender error:%d",result);
    }else{
        [self.delegate audioMixerProduceFrameWith:_reanderBufferList time:(int64_t)([[NSDate date]timeIntervalSince1970]*1000)];
    }
    
    if (_intputCount < _receiveSource.allKeys.count) {
        for (NSUInteger i = 0; i<MAX_MIX_COUNT; i++) {
            if (_receiveBox[i] == 0) {
                NSNumber* deleteKey;
                for (NSNumber* key in _receiveSource.allKeys) {
                    if (_receiveSource[key] == @(i)) {
                        deleteKey = key;
                        break;
                    }
                }
                if(deleteKey){
                    [_receiveSource removeObjectForKey:deleteKey];
                    break;
                }
                
            }
        }
    }
    memset(_receiveBox, 0, sizeof(_receiveBox));
    _currentCount = 0;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        _receiveSource = [NSMutableDictionary dictionaryWithCapacity:2];
    }
    return self;
}
-(void)setupWithAudioController:(AEAudioController *)audioController{
    self.audioController = audioController;
    if (_graph == NULL) {
        _clientFormat = audioController.audioDescription;
        [self createMixingGraph];
        if (_reanderBufferList != NULL) {
            AEAudioBufferListFree(_reanderBufferList);
            for (int i = 0; i<MAX_MIX_COUNT; i++) {
                AEAudioBufferListFree(_inputSource[i]);
            }
        }
        
        _reanderBufferList = AEAudioBufferListCreate(_clientFormat, 4096);
        for (int i = 0; i<MAX_MIX_COUNT; i++) {
            _inputSource[i] = AEAudioBufferListCreate(_clientFormat, 4096);
        }
    }
    [self refreshSourceCounts:_intputCount+1];
    _intputCount++;
}
-(void)teardown{
    [self refreshSourceCounts:_intputCount-1];
    _intputCount--;
}
-(AEAudioReceiverCallback)receiverCallback{
    return receiverCallback;
}

//-(BOOL)mixerAudioWithFrameCount:(UInt32)frameCount outBuffer:(AudioBufferList*)outBufferList{
//    AudioUnitRenderActionFlags flags = 0;
//    AudioTimeStamp renderTimestamp;
//    memset(&renderTimestamp, 0, sizeof(AudioTimeStamp));
//    renderTimestamp.mSampleTime = 0;
//    renderTimestamp.mFlags = kAudioTimeStampNothingValid;
//    OSStatus result = AudioUnitRender(_mixerUnit, &flags, &renderTimestamp, 0, frameCount, outBufferList);
//    return result;
//}
- (BOOL)createMixingGraph{
    // Create a new AUGraph
    OSStatus result = NewAUGraph(&_graph);
    if ( !AECheckOSStatus(result, "NewAUGraph") ) return false;
    
    // Multichannel mixer unit
    AudioComponentDescription mixer_desc = {
        .componentType = kAudioUnitType_Mixer,
        .componentSubType = kAudioUnitSubType_MultiChannelMixer,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0
    };
    
    // Add mixer node to graph
    result = AUGraphAddNode(_graph, &mixer_desc, &_mixerNode );
    if ( !AECheckOSStatus(result, "AUGraphAddNode mixer") ) return false;
    
    // Open the graph - AudioUnits are open but not initialized (no resource allocation occurs here)
    result = AUGraphOpen(_graph);
    if ( !AECheckOSStatus(result, "AUGraphOpen") ) return false;
    
    // Get reference to the audio unit
    result = AUGraphNodeInfo(_graph, _mixerNode, NULL, &_mixerUnit);
    if ( !AECheckOSStatus(result, "AUGraphNodeInfo") ) return false;
    
    // Set the audio unit to handle up to 4096 frames per slice to keep rendering during screen lock
    UInt32 maxFPS = 4096;
    AECheckOSStatus(AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, sizeof(maxFPS)),
                    "AudioUnitSetProperty(kAudioUnitProperty_MaximumFramesPerSlice)");
    
    // Try to set mixer's output stream format to our client format
    if(!AECheckOSStatus(AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &_clientFormat, sizeof(_clientFormat)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)")){
        return false;
    } ;
    
    return YES;
}

-(BOOL)refreshSourceCounts:(int)counts{
    // Set bus count
    UInt32 busCount = counts;
    if ( !AECheckOSStatus(AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &busCount, sizeof(busCount)),
                          "AudioUnitSetProperty(kAudioUnitProperty_ElementCount)") ) return NO;
    
    // The default volume for the MultiChannelMixer is 0 on OSX and 1 on iOS. ¯\_(ツ)_/¯
    AudioUnitParameterValue defaultOutputVolume = 1.0;
    if ( !AECheckOSStatus(AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, defaultOutputVolume, 0),
                          "AudioUnitSetParameter(kMultiChannelMixerParam_Volume)") ) return NO;

    // Configure each bus
    for ( int busNumber=0; busNumber<busCount; busNumber++ ) {
        // Set input stream format
        if(!AECheckOSStatus(AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, busNumber,  &_clientFormat, sizeof(AudioStreamBasicDescription)),
                   "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)")){
            return NO;
        };
        
        // Set volume
        AudioUnitParameterValue value = 1;
        if(!AECheckOSStatus(AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, busNumber, value, 0),
                    "AudioUnitSetParameter(kMultiChannelMixerParam_Volume)")){
            return NO;
        }
        
        // Set pan
        value = 0;
        if(!AECheckOSStatus(AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Pan, kAudioUnitScope_Input, busNumber, value, 0),
                    "AudioUnitSetParameter(kMultiChannelMixerParam_Pan)")){
            return NO;
        }
        
        // Set the render callback
        AURenderCallbackStruct rcbs;
        rcbs.inputProc = &sourceInputCallback;
        rcbs.inputProcRefCon = (__bridge void *)self;
        OSStatus result = AUGraphSetNodeInputCallback(_graph, _mixerNode, busNumber, &rcbs);
        if ( result != kAUGraphErr_InvalidConnection /* Ignore this error */ )
            AECheckOSStatus(result, "AUGraphSetNodeInputCallback");
    }
    Boolean isInited = false;
    AUGraphIsInitialized(_graph, &isInited);
    if ( !isInited ) {
        if(!AECheckOSStatus(AUGraphInitialize(_graph), "AUGraphInitialize")){
            return NO;
        }else{
            return YES;
        }
    } else {
        BOOL result = NO;
        for ( int retries=3; retries > 0; retries-- ) {
            if (AECheckOSStatus(AUGraphUpdate(_graph, NULL), "AUGraphUpdate") ) {
                result = YES;
                break;
            }
            [NSThread sleepForTimeInterval:0.01];
        }
        return result;
    }

}
-(void)dealloc{
    if (_reanderBufferList != NULL) {
        AEAudioBufferListFree(_reanderBufferList);
        for (int i = 0; i<MAX_MIX_COUNT; i++) {
            AEAudioBufferListFree(_inputSource[i]);
        }
    }
}
@end
