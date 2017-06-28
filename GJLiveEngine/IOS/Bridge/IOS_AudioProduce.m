//
//  IOS_AudioProduce.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_AudioProduce.h"

#import "GJLog.h"


#define AMAZING_AUDIO_ENGINE
//#define AUDIO_QUEUE_RECODE

#import <CoreAudio/CoreAudioTypes.h>
#ifdef AUDIO_QUEUE_RECODE
#import "GJAudioQueueRecoder.h"
#endif

#ifdef AMAZING_AUDIO_ENGINE
#import "GJAudioSessionCenter.h"
#import "AudioUnitCapture.h"
#import "AEAudioController.h"
#import "AEPlaythroughChannel.h"
#import "AEAudioSender.h"
#import "GJAudioMixer.h"


@interface GJAudioManager : NSObject<GJAudioMixerDelegate>
{
    GJRetainBufferPool* _bufferPool;
}
@property (nonatomic, assign)BOOL mixToSream;
@property (nonatomic, retain)AEPlaythroughChannel* playthrough;
@property (nonatomic, retain)AEAudioFilePlayer* mixfilePlay;
@property (nonatomic, retain)AEAudioController *audioController;
@property (nonatomic, retain)GJAudioMixer* audioMixer;

@property (nonatomic, readonly) AEAudioReceiverCallback receiverCallback;

@property (nonatomic, copy)void(^audioCallback)(R_GJPCMFrame* frame);
@end
@implementation GJAudioManager

-(instancetype)initWithFormat:(AudioStreamBasicDescription )audioFormat{
    self = [super init];
    if (self) {
        NSError* error;
        _mixToSream = YES;
        [[GJAudioSessionCenter shareSession] setPrefferSampleRate:audioFormat.mSampleRate error:&error];
        if (error != nil) {
            GJLOG(GJ_LOGERROR, "setPrefferSampleRate error:%s",error.localizedDescription.UTF8String);
        }
        _audioController = [[AEAudioController alloc]initWithAudioDescription:audioFormat inputEnabled:YES];
        _audioController.useMeasurementMode = YES;
//        _audioController.preferredBufferDuration = 0.015;
        _audioMixer = [[GJAudioMixer alloc]init];
        _audioMixer.delegate = self;
        [_audioController addInputReceiver:_audioMixer];
        GJRetainBufferPoolCreate(&_bufferPool, 0, GTrue, R_GJPCMFrameMalloc, GNULL);
    }
    return self;
}

-(void)audioMixerProduceFrameWith:(AudioBufferList *)frame time:(int64_t)time{
    R_GJPCMFrame* pcmFrame = (R_GJPCMFrame*)GJRetainBufferPoolGetSizeData(_bufferPool, frame->mBuffers[0].mDataByteSize);
    memcpy(pcmFrame->retain.data, frame->mBuffers[0].mData, frame->mBuffers[0].mDataByteSize);
    pcmFrame->channel = frame->mBuffers[0].mNumberChannels;
    pcmFrame->pts = (GInt64)time;
    pcmFrame->retain.size = frame->mBuffers[0].mDataByteSize;
    self.audioCallback(pcmFrame);
    retainBufferUnRetain(&pcmFrame->retain);
}

-(BOOL)startRecode:(NSError**)error{
    if (![_audioController start:error]) {
        GJLOG(GJ_LOGERROR, "AEAudioController start error:%@",(*error).description.UTF8String);
    }
    return *error == nil;
}
-(void)stopRecode{
    [_audioController stop];
}
-(AEPlaythroughChannel *)playthrough{
    if (_playthrough == nil) {
        _playthrough = [[AEPlaythroughChannel alloc]init];
    }
    return _playthrough;
}

-(BOOL)enableAudioInEarMonitoring:(BOOL)enable{
    if (enable) {
        [_audioController addInputReceiver:self.playthrough];
        [_audioController addChannels:@[self.playthrough]];
    }else{
        [_audioController removeChannels:@[self.playthrough]];
        [_audioController removeInputReceiver:self.playthrough];
    }
    return GTrue;
}
-(void)setMixToSream:(BOOL)mixToSream{
    _mixToSream = mixToSream;
    if (_mixToSream) {
        [_audioMixer removeIgnoreSource:AEAudioSourceMainOutput];
    }else{
        [_audioMixer addIgnoreSource:AEAudioSourceMainOutput];
    }
}
-(BOOL)setMixFile:(NSURL*)file{
    if (_mixfilePlay != nil) {
        GJLOG(GJ_LOGWARNING, "上一个文件没有关闭，自动关闭");
        [_audioController removeChannels:@[_mixfilePlay]];
        [_audioController removeOutputReceiver:_audioMixer fromChannel:_mixfilePlay];
        _mixfilePlay = nil;
    }
    NSError* error;
    _mixfilePlay = [[AEAudioFilePlayer alloc]initWithURL:file error:&error];
    if (_mixfilePlay == nil) {
        GJLOG(GJ_LOGERROR, "AEAudioFilePlayer alloc error:%s",error.localizedDescription.UTF8String);
        return GFalse;
    }else{
        [_audioController addChannels:@[_mixfilePlay]];
        [_audioController performAsynchronousMessageExchangeWithBlock:^{
//             [_audioController addOutputReceiver:_audioMixer forChannel:_mixfilePlay];
            [_audioController addOutputReceiver:_audioMixer];
        } responseBlock:nil];
       
        return GTrue;
    }
}
-(BOOL)mixFilePlayAtTime:(uint64_t)time{
    if (_mixfilePlay) {
        [_mixfilePlay playAtTime:time];
        return YES;
    }else{
        GJLOG(GJ_LOGERROR, "请先设置minx file");
        return NO;
    }
}
-(void)stopMix{
    if (_mixfilePlay == nil) {
        GJLOG(GJ_LOGWARNING, "重复stop mix");
    }else{
        [_audioController removeChannels:@[_mixfilePlay]];
        [_audioController removeOutputReceiver:_audioMixer];
//        [_audioController removeOutputReceiver:_audioMixer fromChannel:_mixfilePlay];
        _mixfilePlay = nil;
    }
}
-(void)dealloc{
    GJLOG(GJ_LOGDEBUG, "GJAudioManager dealloc");
    [_audioController removeInputReceiver:_audioMixer];
    NSMutableArray* play = [NSMutableArray arrayWithCapacity:2];
    
    if (_mixfilePlay) {
        [play addObject:_mixfilePlay];
        [_audioController removeOutputReceiver:_audioMixer];
//        [_audioController removeOutputReceiver:_audioMixer fromChannel:_mixfilePlay];
    }
    if (_playthrough) {
        [play addObject:_playthrough];
        [_audioController removeInputReceiver:_playthrough];
    }
    [_audioController removeChannels:play];
    
}
@end

#endif

inline static GBool audioProduceSetup(struct _GJAudioProduceContext* context,GJAudioFormat format,AudioFrameOutCallback callback,GHandle userData){
    GJAssert(context->obaque == GNULL, "上一个音频生产器没有释放");
    if (format.mType != GJAudioType_PCM) {
        GJLOG(GJ_LOGERROR, "解码音频源格式不支持");
        return GFalse;
    }
    UInt32 formatid = 0;
    switch (format.mType) {
        case GJAudioType_PCM:
            formatid = kAudioFormatLinearPCM;
            break;
        default:
        {
            GJLOG(GJ_LOGERROR, "解码音频源格式不支持");
            return GFalse;
            break;
        }
    }
    if (callback == GNULL) {
        GJLOG(GJ_LOGERROR, "回调函数不能为空");
        return GFalse;
    }
#ifdef AUDIO_QUEUE_RECODE
    GJAudioQueueRecoder* recoder = [[GJAudioQueueRecoder alloc]initWithStreamWithSampleRate:format.mSampleRate channel:format.mChannelsPerFrame formatID:formatid];
    recoder.callback = ^(R_GJPCMFrame *frame) {
        callback(userData,frame);
    };
    context->obaque = (__bridge_retained GHandle)(recoder);
#endif
    
#ifdef AMAZING_AUDIO_ENGINE
    AudioStreamBasicDescription audioFormat = {0};
    audioFormat.mSampleRate       = format.mSampleRate;               // 3
    audioFormat.mChannelsPerFrame = format.mChannelsPerFrame;                     // 4
    audioFormat.mFramesPerPacket  = 1;                     // 7
    audioFormat.mBitsPerChannel   = 16;                    // 5
    audioFormat.mBytesPerFrame   = audioFormat.mChannelsPerFrame * audioFormat.mBitsPerChannel/8;
    audioFormat.mBytesPerPacket =audioFormat.mBytesPerFrame*audioFormat.mFramesPerPacket;
    audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
    audioFormat.mFormatID = kAudioFormatLinearPCM;

    GJAudioManager* manager = [[GJAudioManager alloc]initWithFormat:audioFormat];
    manager.audioCallback = ^(R_GJPCMFrame *frame) {
        callback(userData,frame);
    };
    if (!manager) {
        GJLOG(GJ_LOGERROR, "GJAudioManager setup ERROR");
        return GFalse;
    }else{
        context->obaque = (__bridge_retained GHandle)manager;
        return GTrue;
    }
#endif
    return GTrue;
}
inline static GVoid audioProduceUnSetup(struct _GJAudioProduceContext* context){
    if(context->obaque){
#ifdef AUDIO_QUEUE_RECODE
        GJAudioQueueRecoder* recode = (__bridge_transfer GJAudioQueueRecoder *)(context->obaque);
        [recode stop];
        context->obaque = GNULL;
#endif
        
#ifdef AMAZING_AUDIO_ENGINE
        GJAudioManager* manager = (__bridge_transfer GJAudioManager *)(context->obaque);
        [manager stopRecode ];
        context->obaque = GNULL;
#endif
    }
}
inline static GBool audioProduceStart(struct _GJAudioProduceContext* context){
    __block GBool result = GTrue;
#ifdef AUDIO_QUEUE_RECODE
    GJAudioQueueRecoder* recode = (__bridge GJAudioQueueRecoder *)(context->obaque);
    result =  [recode startRecodeAudio];
#endif
#ifdef AMAZING_AUDIO_ENGINE
    if (/* DISABLES CODE */ (1)) {
        NSError* error;
        GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
        if(![manager startRecode:&error]){
            GJLOG(GJ_LOGERROR, "startRecode error:%s",error.localizedDescription.UTF8String);
            result = GFalse;
        }
    }else{
        dispatch_sync(dispatch_get_main_queue(), ^{
            NSError* error;
            GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
            if(![manager startRecode:&error]){
                GJLOG(GJ_LOGERROR, "startRecode error:%s",error.localizedDescription.UTF8String);
                result = GFalse;
            }
        });
    }

#endif
    return result;
}
inline static GVoid audioProduceStop(struct _GJAudioProduceContext* context){
#ifdef AUDIO_QUEUE_RECODE
    GJAudioQueueRecoder* recode = (__bridge GJAudioQueueRecoder *)(context->obaque);
    [recode stop];
#endif
#ifdef AMAZING_AUDIO_ENGINE
    if (/* DISABLES CODE */ (1)) {
        GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
        [manager stopRecode];
    }else{
        dispatch_sync(dispatch_get_main_queue(), ^{
            GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
            [manager stopRecode];
        });
    }
#endif
}

GBool enableAudioInEarMonitoring(struct _GJAudioProduceContext* context,GBool enable){
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
    return [manager enableAudioInEarMonitoring:enable];
#endif
    return  GTrue;
}
GBool setupMixAudioFile(struct _GJAudioProduceContext* context,const GChar* file,GBool loop){
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
    NSURL * url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:file]];
    return [manager setMixFile:url];
#endif
    return  GTrue;
}
GBool startMixAudioFileAtTime(struct _GJAudioProduceContext* context,GUInt64 time){
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
    return [manager mixFilePlayAtTime:time];
#endif
    return  GTrue;
}
GVoid stopMixAudioFile(struct _GJAudioProduceContext* context){
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
    return [manager stopMix];
#endif
}
GBool setInputGain(struct _GJAudioProduceContext* context,GFloat32 inputGain){
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
    manager.audioController.inputGain = inputGain;
    GFloat32 gain = manager.audioController.inputGain;
    return GFloatEqual(gain, inputGain);
#endif
    return GFalse;
}
GBool setMixVolume(struct _GJAudioProduceContext* context,GFloat32 volume){
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
    manager.mixfilePlay.volume = volume;
    
    return GFloatEqual(manager.mixfilePlay.volume, volume);
#endif
    return GFalse;
    
}
GBool setOutVolume(struct _GJAudioProduceContext* context,GFloat32 volume){
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
    manager.audioController.masterOutputVolume = volume;
    return GFloatEqual(manager.audioController.masterOutputVolume, volume);
#endif
    return GFalse;
}
GBool setMixToStream(struct _GJAudioProduceContext* context,GBool should){
#ifdef AMAZING_AUDIO_ENGINE
    GJAudioManager* manager = (__bridge GJAudioManager *)(context->obaque);
    manager.mixToSream = should;
#endif
    return GTrue;
}
GVoid GJ_AudioProduceContextCreate(GJAudioProduceContext** recodeContext){
    if (*recodeContext == NULL) {
        *recodeContext = (GJAudioProduceContext*)malloc(sizeof(GJAudioProduceContext));
    }
    GJAudioProduceContext* context = *recodeContext;
    context->audioProduceSetup = audioProduceSetup;
    context->audioProduceUnSetup = audioProduceUnSetup;
    context->audioProduceStart = audioProduceStart;
    context->audioProduceStop = audioProduceStop;
    
    context->enableAudioInEarMonitoring = enableAudioInEarMonitoring;
    context->setupMixAudioFile = setupMixAudioFile;
    context->startMixAudioFileAtTime = startMixAudioFileAtTime;
    context->stopMixAudioFile = stopMixAudioFile;
    
    context->setInputGain = setInputGain;
    context->setMixVolume = setMixVolume;
    context->setOutVolume = setOutVolume;
    context->setMixToStream = setMixToStream;

}
GVoid GJ_AudioProduceContextDealloc(GJAudioProduceContext** context){
    if ((*context)->obaque) {
        GJLOG(GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->audioProduceUnSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
