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
#ifdef ENABLE_IGNORE
    #define IGNORE_BUS -1
#endif

#define MAX_FRAME_COUNT 4096

@interface GJAudioMixer(){
    AUGraph                         _graph;
    AUNode                          _mixerNode;
    AudioUnit                       _mixerUnit;
    UInt32                          _mixCount;
    AudioStreamBasicDescription     _clientFormat;
    AudioBufferList*                _reanderBufferList;
    AudioBufferList*                _inputSourcBufferCache[MAX_MIX_COUNT];
    UInt32                          _bytePerFrame;
    
    int                             _listenIntputCount;//add的source个数
    UInt32                          _elementCount;
    
#ifdef ENABLE_IGNORE
    NSMutableArray*                 _ignoreSource;
#endif
    
    NSMutableDictionary*            _receiveSource;//收到的source
    NSMutableArray*                 _unitReceiveBox;
    
    BOOL                            _needUpdateSource;//提高效率
}
@property(nonatomic,weak)AEAudioController* audioController;
@end
@implementation GJAudioMixer

#ifdef ENABLE_IGNORE

-(void)addIgnoreSource:(void*)source{
    if (![_ignoreSource containsObject:@((long)source)]) {
        [_ignoreSource addObject:@((long)source)];
        _needUpdateSource = YES;
    }
}
-(void)removeIgnoreSource:(void*)source{
    if ([_ignoreSource containsObject:@((long)source)]) {
        [_ignoreSource removeObject:@((long)source)];
        _needUpdateSource = YES;
    }
}
#endif

static void receiverCallback(__unsafe_unretained id    receiver,__unsafe_unretained AEAudioController *audioController,void *source,const AudioTimeStamp *time,UInt32 frames,AudioBufferList *audio){
//    NSLog(@"source:%p  ,sampid:%f,hostTime:%lld",source,time->mSampleTime,time->mHostTime);
    GJAudioMixer* mixer = receiver;
    NSNumber* sourceN = @((long)source);
#ifdef ENABLE_IGNORE
    if ([mixer->_ignoreSource containsObject:sourceN]) {
        NSNumber* sourcBusN = mixer->_receiveSource[sourceN];
        if (!sourcBusN) {
            [mixer->_receiveSource setObject:@(IGNORE_BUS) forKey:sourceN];
            NSLog(@"添加新的 IGNORE_Source：%p",source);
        }else if(sourcBusN.unsignedIntegerValue != IGNORE_BUS){//已经存在
            UInt32 v = ((NSNumber*)(mixer->_receiveSource[sourceN])).unsignedIntegerValue;
            for (NSNumber* key in mixer->_receiveSource.allKeys) {
                UInt32 cv = ((NSNumber*)(mixer->_receiveSource[key])).unsignedIntegerValue;
                if (cv > v) {
                    mixer->_receiveSource[key] = @(cv);
                }
            }
            mixer->_receiveSource[sourceN] = @(IGNORE_BUS);
            NSLog(@"已存在的转换到IGNORE_Source：%p",source);
        }
        [mixer->_unitReceiveBox addObject:@((long)source)];

        if (mixer->_unitReceiveBox.count == mixer->_listenIntputCount) {
            [mixer unitRenderWithCount:frames time:(int64_t)([[NSDate date]timeIntervalSince1970]*1000)];
        }
        
        return;
    }
#endif
    
    NSNumber* busN = mixer->_receiveSource[@((long)source)];
    NSUInteger bus = 0;
#ifdef ENABLE_IGNORE
    if (busN) {
        if(busN.unsignedIntegerValue == IGNORE_BUS){
            UInt32 maxBus = 0;
            for (NSNumber* key in mixer->_receiveSource.allKeys) {
                if (mixer->_receiveSource[key] != @(IGNORE_BUS) ) {
                    maxBus++;
                }
            }
            bus = maxBus;
            busN = @(bus);
            [mixer->_receiveSource setObject:busN forKey:@((long)source)];
            NSLog(@"IGNORE_BUS转换到Source：%p",source);
            [mixer refreshSourceFource:NO];
        }else{
            bus = busN.unsignedIntegerValue;
        }
    }else{
        if (mixer->_receiveSource.count < MAX_MIX_COUNT) {
            UInt32 maxBus = 0;
            for (NSNumber* key in mixer->_receiveSource.allKeys) {
                if (mixer->_receiveSource[key] != @(IGNORE_BUS) ) {
                    maxBus++;
                }
            }
            bus = maxBus;
            busN = @(bus);
            [mixer->_receiveSource setObject:busN forKey:@((long)source)];
            NSLog(@"添加新的Source：%p",source);
            [mixer refreshSourceFource:NO];
        }else{
            NSLog(@"混合流数量超过最大");
            return;
        }
    }
#else
    if (busN) {
         bus = busN.unsignedIntegerValue;
    }else{
        if (mixer->_receiveSource.count < MAX_MIX_COUNT) {
            UInt32 maxBus = mixer->_receiveSource.allKeys.count;
            bus = maxBus;
            busN = @(bus);
            [mixer->_receiveSource setObject:busN forKey:@((long)source)];
            NSLog(@"添加新的Source：%p",source);
            [mixer refreshSource];
        }else{
            NSLog(@"混合流数量超过最大");
            return;
        }
    }
#endif

    
    
    if (mixer->_elementCount == 1) {
        if (mixer->_unitReceiveBox.count > 0) {
            for (NSNumber* key in mixer->_unitReceiveBox) {
#ifdef ENABLE_IGNORE
                if (mixer->_receiveSource[key] != @(IGNORE_BUS)) {
#endif
                    NSNumber* v = mixer->_receiveSource[key];
                    float dt = frames * 1000 /  mixer->_audioController.audioDescription.mSampleRate;
                    [mixer.delegate audioMixerProduceFrameWith:mixer->_inputSourcBufferCache[v.unsignedIntegerValue] time:(int64_t)([[NSDate date]timeIntervalSince1970]*1000 - dt)];
                    NSLog(@"只有一个source 但是之前已经收到了一个相同的source:%p",(void*)key.longValue);
#ifdef ENABLE_IGNORE
                }
#endif
            }
        }
        [mixer.delegate audioMixerProduceFrameWith:audio time:(int64_t)([[NSDate date]timeIntervalSince1970]*1000)];
        [mixer->_unitReceiveBox removeAllObjects];
    }else{
        if ([mixer->_unitReceiveBox containsObject:sourceN]) {//重复
            NSLog(@"重复，出现错乱，重置状态！(teardown不及时导致，没有收到的数据置空)");
            for (NSNumber* key in mixer->_receiveSource.allKeys) {
                if (![mixer->_unitReceiveBox containsObject:key]
#ifdef ENABLE_IGNORE
                    && ![mixer->_ignoreSource containsObject:key]
#endif
                    ) {
                    NSNumber* v = mixer->_receiveSource[key];
                    UInt32 ncbus = v.unsignedIntegerValue;
                    NSLog(@"clean source:%p",(void*)(v.longValue));
                    for (int i = 0; i<mixer->_inputSourcBufferCache[ncbus]->mNumberBuffers; i++) {
                        memset(mixer->_inputSourcBufferCache[ncbus]->mBuffers[i].mData, 0, mixer->_inputSourcBufferCache[ncbus]->mBuffers[i].mDataByteSize);
                    }
                }
            }
            float dt = frames * 1000 /  mixer->_audioController.audioDescription.mSampleRate;
            [mixer unitRenderWithCount:frames time:(int64_t)([[NSDate date]timeIntervalSince1970]*1000 - dt)];
            [mixer->_unitReceiveBox removeAllObjects];
            [mixer->_receiveSource removeAllObjects];
            bus = 0;
            busN = @(bus);
            [mixer->_receiveSource setObject:busN forKey:@((long)source)];
            [mixer->_unitReceiveBox addObject:sourceN];
            for (int i = 0; i<audio->mNumberBuffers; i++) {
                memcpy(mixer->_inputSourcBufferCache[bus]->mBuffers[i].mData, audio->mBuffers[i].mData, audio->mBuffers[i].mDataByteSize);
                mixer->_inputSourcBufferCache[bus]->mBuffers[i].mDataByteSize = audio->mBuffers[i].mDataByteSize;
            }
        }else {
            [mixer->_unitReceiveBox addObject:sourceN];
            for (int i = 0; i<audio->mNumberBuffers; i++) {
                memcpy(mixer->_inputSourcBufferCache[bus]->mBuffers[i].mData, audio->mBuffers[i].mData, audio->mBuffers[i].mDataByteSize);
                mixer->_inputSourcBufferCache[bus]->mBuffers[i].mDataByteSize = audio->mBuffers[i].mDataByteSize;
            }
            if (mixer->_unitReceiveBox.count == mixer->_listenIntputCount) {
                [mixer unitRenderWithCount:frames time:(int64_t)([[NSDate date]timeIntervalSince1970]*1000)];
            }else if(mixer->_unitReceiveBox.count > mixer->_listenIntputCount){
                NSLog(@"不可能出现的错误 source:%p  time:%f",source,time->mSampleTime);
                assert(0);
            }
        }
    }
    
//    NSLog(@"source:%p  time:%f",source,time->mSampleTime);

}

static OSStatus sourceInputCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    GJAudioMixer* audioMix = (__bridge GJAudioMixer *)(inRefCon);
    for ( int i=0; i<ioData->mNumberBuffers; i++ ) {
        memcpy(ioData->mBuffers[i].mData,audioMix->_inputSourcBufferCache[inBusNumber]->mBuffers[i].mData,audioMix->_inputSourcBufferCache[inBusNumber]->mBuffers[i].mDataByteSize);
        ioData->mBuffers[i].mNumberChannels = audioMix->_inputSourcBufferCache[inBusNumber]->mBuffers[i].mNumberChannels;
        ioData->mBuffers[i].mDataByteSize = audioMix->_inputSourcBufferCache[inBusNumber]->mBuffers[i].mDataByteSize;
    }
//    NSLog(@"inBusNumber:%d  time:%f frames:%d",inBusNumber,inTimeStamp->mSampleTime,inNumberFrames);
    return noErr;
}



-(void)unitRenderWithCount:(UInt32)frames time:(int64_t)time{
    if (_needUpdateSource) {
        [self refreshSourceFource:NO];
    }
    _mixCount+=frames;
//    NSLog(@"request frames:%d",frames);
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp renderTimestamp = {0};
    renderTimestamp.mFlags = kAudioTimeStampSampleTimeValid;
    renderTimestamp.mSampleTime = (Float64)_mixCount;
    OSStatus result = noErr;
    for (int i = 0; i<_reanderBufferList->mNumberBuffers; i++) {
        _reanderBufferList->mBuffers[i].mNumberChannels = _clientFormat.mChannelsPerFrame;
        _reanderBufferList->mBuffers[i].mDataByteSize = _clientFormat.mBytesPerFrame * MAX_FRAME_COUNT;
    }

        
    result = AudioUnitRender(_mixerUnit, &flags, &renderTimestamp, 0, frames, _reanderBufferList);
  
    if (result != noErr) {
        NSLog(@"AudioUnitRender error:%d",result);
    }else{
        [self.delegate audioMixerProduceFrameWith:_reanderBufferList time:time];
    }
    [_unitReceiveBox removeAllObjects];
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        _receiveSource = [NSMutableDictionary dictionaryWithCapacity:2];
#ifdef ENABLE_IGNORE
        _ignoreSource = [NSMutableArray arrayWithCapacity:2];
#endif
        _unitReceiveBox = [NSMutableArray arrayWithCapacity:2];
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
                AEAudioBufferListFree(_inputSourcBufferCache[i]);
            }
        }
        
        _reanderBufferList = AEAudioBufferListCreate(_clientFormat, MAX_FRAME_COUNT);
        for (int i = 0; i<MAX_MIX_COUNT; i++) {
            _inputSourcBufferCache[i] = AEAudioBufferListCreate(_clientFormat, MAX_FRAME_COUNT);
        }
        _bytePerFrame = audioController.audioDescription.mBytesPerFrame;
    }
    if (_listenIntputCount < MAX_MIX_COUNT) {
        _listenIntputCount++;
        _needUpdateSource = YES;
    }
}
-(void)teardown{
    if (_listenIntputCount > 0) {
        _listenIntputCount--;
        _needUpdateSource = YES;
    }
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
    UInt32 maxFPS = MAX_FRAME_COUNT;
    AECheckOSStatus(AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, sizeof(maxFPS)),
                    "AudioUnitSetProperty(kAudioUnitProperty_MaximumFramesPerSlice)");
    
    // Try to set mixer's output stream format to our client format
    if(!AECheckOSStatus(AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &_clientFormat, sizeof(_clientFormat)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)")){
        return false;
    } ;
    
    return YES;
}

-(BOOL)refreshSourceFource:(BOOL)fource{
    // Set bus count
    if(_listenIntputCount != _receiveSource.allKeys.count)return NO;
    int counts = _listenIntputCount;

    
        
#ifdef ENABLE_IGNORE
        for (NSNumber* v in _ignoreSource) {
            if ([_receiveSource.allKeys containsObject:v]) {
                counts--;
            }
        }
#endif
    if (!fource) {

        if (_elementCount == counts) {
            return YES;
        }
    }


    _needUpdateSource = NO;
    _elementCount = counts;
    if ( !AECheckOSStatus(AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &_elementCount, sizeof(_elementCount)),
                          "AudioUnitSetProperty(kAudioUnitProperty_ElementCount)") ) return NO;
    
    // The default volume for the MultiChannelMixer is 0 on OSX and 1 on iOS. ¯\_(ツ)_/¯
    AudioUnitParameterValue defaultOutputVolume = 1.0;
    if ( !AECheckOSStatus(AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, defaultOutputVolume, 0),
                          "AudioUnitSetParameter(kMultiChannelMixerParam_Volume)") ) return NO;

    // Configure each bus
    for ( int busNumber=0; busNumber<_elementCount; busNumber++ ) {
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
-(void)restart{
    if (_graph) {
        AUGraphClose(_graph);
        DisposeAUGraph(_graph);
        _graph = nil;
    }
    [self createMixingGraph];
    [self refreshSourceFource:YES];
}
-(void)dealloc{
    if (_reanderBufferList != NULL) {
        AEAudioBufferListFree(_reanderBufferList);
        for (int i = 0; i<MAX_MIX_COUNT; i++) {
            AEAudioBufferListFree(_inputSourcBufferCache[i]);
        }
    }
    if (_graph) {
        AUGraphClose(_graph);
        DisposeAUGraph(_graph);
    }
}
@end
