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
        GJRetainBufferPoolClean(_bufferPool, YES);
        GJRetainBufferPoolFree(&(_bufferPool));
    }
    self.audioController = nil;
}
- (void)teardown {
    self.audioController = nil;
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
    NSError* error;
    [[GJAudioSessionCenter shareSession] setPrefferSampleRate:format.mSampleRate error:&error];
    if (error != nil) {
        GJLOG(GJ_LOGERROR, "setPrefferSampleRate error:%s",error.localizedDescription.UTF8String);
    }
    AEAudioController* audioController = [[AEAudioController alloc]initWithAudioDescription:audioFormat options:AEAudioControllerOptionEnableInput];
    
    GJAudioOutput* audioOut = [[GJAudioOutput alloc]initWithAudioController:audioController];
    [audioController addInputReceiver:audioOut];
    audioOut.audioCallback = ^(R_GJPCMFrame* frame){
        callback(userData,frame);
    };
    context->obaque = (__bridge_retained GHandle)audioController;
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
        AEAudioController* audioController = (__bridge_transfer AEAudioController *)(context->obaque);
        [audioController stop];
        context->obaque = GNULL;
#endif
    }
}
inline static GBool audioProduceStart(struct _GJAudioProduceContext* context){
    GBool result = GTrue;
#ifdef AUDIO_QUEUE_RECODE
    GJAudioQueueRecoder* recode = (__bridge GJAudioQueueRecoder *)(context->obaque);
    result =  [recode startRecodeAudio];
#endif
#ifdef AMAZING_AUDIO_ENGINE
    NSError* error;
    AEAudioController* audioController = (__bridge AEAudioController *)(context->obaque);
    [audioController start:&error];
    result = (error != nil);
#endif
    return result;
}
inline static GVoid audioProduceStop(struct _GJAudioProduceContext* context){
#ifdef AUDIO_QUEUE_RECODE
    GJAudioQueueRecoder* recode = (__bridge GJAudioQueueRecoder *)(context->obaque);
    [recode stop];
#endif
#ifdef AMAZING_AUDIO_ENGINE
    AEAudioController* audioController = (__bridge AEAudioController *)(context->obaque);
    [audioController stop];
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
}
GVoid GJ_AudioProduceContextDealloc(GJAudioProduceContext** context){
    if ((*context)->obaque) {
        GJLOG(GJ_LOGWARNING, "encodeUnSetup 没有调用，自动调用");
        (*context)->audioProduceUnSetup(*context);
    }
    free(*context);
    *context = GNULL;
}
