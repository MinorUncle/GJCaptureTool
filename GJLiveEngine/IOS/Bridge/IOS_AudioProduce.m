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



@interface GJAudioOutput : NSObject <AEAudioReceiver>
{
    GJRetainBufferPool* _bufferPool;
}
- (instancetype)init;

- (id)initWithAudioController:(AEAudioController*)audioController;

@property (nonatomic, assign) float volume;
@property (nonatomic, assign) float pan;
@property (nonatomic, assign) BOOL channelIsMuted;
@property (nonatomic, readonly) AudioStreamBasicDescription audioDescription;
@property (nonatomic, weak) AEAudioController *audioController;


@property (nonatomic, copy)void(^audioCallback)(R_GJPCMFrame* frame);

@end
@implementation GJAudioOutput


static void inputCallback(__unsafe_unretained GJAudioOutput *THIS,
                          __unsafe_unretained AEAudioController *audioController,
                          void                     *source,
                          const AudioTimeStamp     *time,
                          UInt32                    frames,
                          AudioBufferList          *audio) {
    
    GJAudioOutput* playChannel = THIS;
    if (playChannel.channelIsMuted || !playChannel.audioCallback) return;
    if (audio &&  audio->mNumberBuffers>0) {
        GUInt32 size = (GUInt32)audio->mBuffers[0].mDataByteSize;
        if (playChannel->_bufferPool == GNULL) {
            
            GBool result = GJRetainBufferPoolCreate(&(playChannel->_bufferPool), size, GTrue, R_GJPCMFrameMalloc, GNULL);
            if (result != GTrue) {
                return ;
            }
        }
        R_GJPCMFrame* rFrame = (R_GJPCMFrame*)GJRetainBufferPoolGetData(playChannel->_bufferPool);
        memcpy(rFrame->retain.data, audio->mBuffers[0].mData, audio->mBuffers[0].mDataByteSize);
        rFrame->channel = audio->mBuffers[0].mNumberChannels;
        playChannel.audioCallback(rFrame);
        retainBufferUnRetain(&rFrame->retain);
    };
}


-(AEAudioReceiverCallback)receiverCallback {
    return inputCallback;
}
- (id)initWithAudioController:(AEAudioController*)audioController {
    return [self init];
}

- (id)init {
    if ( !(self = [super init]) ) return nil;
    _volume = 1.0;
    return self;
}
-(AudioStreamBasicDescription)audioDescription {
    return _audioController.inputAudioDescription;
}


- (void)dealloc {
    if (_bufferPool) {
        GJRetainBufferPool* pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, YES);
            GJRetainBufferPoolFree(pool);
        });
    }
    self.audioController = nil;
}
- (void)teardown {
    self.audioController = nil;
}
@end

@interface GJAudioManager : NSObject
{
}
@property (nonatomic, retain)AEPlaythroughChannel* playthrough;
@property (nonatomic, retain)AEAudioFilePlayer* mixfilePlay;
@property (nonatomic, retain) AEAudioController *audioController;
@property (nonatomic, retain) GJAudioOutput *audioOut;

@property (nonatomic, copy)void(^audioCallback)(R_GJPCMFrame* frame);
@end
@implementation GJAudioManager
-(instancetype)initWithFormat:(AudioStreamBasicDescription )audioFormat{
    self = [super init];
    if (self) {
        NSError* error;
        [[GJAudioSessionCenter shareSession] setPrefferSampleRate:audioFormat.mSampleRate error:&error];
        
        if (error != nil) {
            GJLOG(GJ_LOGERROR, "setPrefferSampleRate error:%s",error.localizedDescription.UTF8String);
        }
        _audioController = [[AEAudioController alloc]initWithAudioDescription:audioFormat options:AEAudioControllerOptionEnableInput];
        _audioController.useMeasurementMode = NO;
//        _audioController.voiceProcessingOnlyForSpeakerAndMicrophone = NO;
        _audioController.voiceProcessingEnabled = YES;
        if (![_audioController start:&error]) {
            GJLOG(GJ_LOGERROR, "AEAudioController start error:%@",error.description.UTF8String);
            self = nil;
        }

    }
    return self;
}
-(GJAudioOutput *)audioOut{
    if (_audioOut == nil) {
        _audioOut = [[GJAudioOutput alloc]initWithAudioController:_audioController];
    }
    return _audioOut;
}

-(void)setAudioCallback:(void (^)(R_GJPCMFrame *))audioCallback{
    self.audioOut.audioCallback = audioCallback;
}
-(BOOL)startRecode:(NSError**)error{

    [_audioController addInputReceiver:self.audioOut];
    return  _audioOut != nil;
}
-(void)stopRecode{
    [_audioController removeInputReceiver:_audioOut];
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

-(BOOL)setMixFile:(NSURL*)file{
    if (_mixfilePlay != nil) {
        GJLOG(GJ_LOGWARNING, "上一个文件没有关闭，自动关闭");
        [_audioController removeChannels:@[_mixfilePlay]];
        _mixfilePlay = nil;
    }
    NSError* error;
    _mixfilePlay = [[AEAudioFilePlayer alloc]initWithURL:file error:&error];
    if (_mixfilePlay == nil) {
        GJLOG(GJ_LOGERROR, "AEAudioFilePlayer alloc error:%s",error.localizedDescription.UTF8String);
        return GFalse;
    }else{
        [_audioController addChannels:@[_mixfilePlay]];
        return GTrue;
    }
}
-(BOOL)mixFilePlayAtTime:(uint64_t)time{
    if (_mixfilePlay) {
//        [_mixfilePlay playAtTime:time];
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
        _mixfilePlay = nil;
    }
}
-(void)dealloc{
    GJLOG(GJ_LOGDEBUG, "GJAudioManager dealloc");
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
    if (1) {
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
    if (1) {
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
}
GVoid GJ_AudioProduceContextDealloc(GJAudioProduceContext** context){
    if ((*context)->obaque) {
        GJLOG(GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->audioProduceUnSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
