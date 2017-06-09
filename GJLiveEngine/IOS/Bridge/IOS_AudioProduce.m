//
//  IOS_AudioProduce.m
//  GJCaptureTool
//
//  Created by melot on 2017/5/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "IOS_AudioProduce.h"

#import "GJLog.h"


#define AUDIO_UNIT_RECODE
//#define AUDIO_QUEUE_RECODE


#ifdef AUDIO_QUEUE_RECODE
#import "GJAudioQueueRecoder.h"
#endif

#import "AudioUnitCapture.h"
#import "AEAudioController.h"
#import "AEPlaythroughChannel.h"

@interface GJPlaythroughChannel : AEPlaythroughChannel
{
    GJRetainBufferPool* _bufferPool;
    GJQueue* _qeue;
}
@end
@implementation GJPlaythroughChannel


static void inputCallback(__unsafe_unretained GJPlaythroughChannel *THIS,
                          __unsafe_unretained AEAudioController *audioController,
                          void                     *source,
                          const AudioTimeStamp     *time,
                          UInt32                    frames,
                          AudioBufferList          *audio) {
    
    GJPlaythroughChannel* playChannel = THIS;
    if (playChannel.audiobusConnectedToSelf ) return;
    if (audio &&  audio->mNumberBuffers>0) {
        GUInt32 size = (GUInt32)audio->mBuffers[0].mDataByteSize;
        if (playChannel->_bufferPool == GNULL) {
            
                GBool result = GJRetainBufferPoolCreate(&(playChannel->_bufferPool), size, GTrue, R_GJPCMFrameMalloc, GNULL);
                if (result != GTrue) {
                    return ;
                }
        }
        R_GJPCMFrame* frmae = (R_GJPCMFrame*)GJRetainBufferPoolGetData(playChannel->_bufferPool);
        memcpy(frmae->retain.data, audio->mBuffers[0].mData, audio->mBuffers[0].mDataByteSize);
        frmae->channel = audio->mBuffers[0].mNumberChannels;
        
        
        retainBufferUnRetain(&frmae->retain);
    };
}

-(AEAudioReceiverCallback)receiverCallback {
    return inputCallback;
}

static OSStatus renderCallback(__unsafe_unretained AEPlaythroughChannel *THIS,
                               __unsafe_unretained AEAudioController *audioController,
                               const AudioTimeStamp     *time,
                               UInt32                    frames,
                               AudioBufferList          *audio) {
    while ( 1 ) {
        // Discard any buffers with an incompatible format, in the event of a format change
        AudioBufferList *nextBuffer = TPCircularBufferNextBufferList(&THIS->_buffer, NULL);
        if ( !nextBuffer ) break;
        if ( nextBuffer->mNumberBuffers == audio->mNumberBuffers ) break;
        TPCircularBufferConsumeNextBufferList(&THIS->_buffer);
    }
    
    UInt32 fillCount = TPCircularBufferPeek(&THIS->_buffer, NULL, AEAudioControllerAudioDescription(audioController));
    if ( fillCount > frames+kSkipThreshold ) {
        UInt32 skip = fillCount - frames;
        TPCircularBufferDequeueBufferListFrames(&THIS->_buffer,
                                                &skip,
                                                NULL,
                                                NULL,
                                                AEAudioControllerAudioDescription(audioController));
    }
    
    TPCircularBufferDequeueBufferListFrames(&THIS->_buffer,
                                            &frames,
                                            audio,
                                            NULL,
                                            AEAudioControllerAudioDescription(audioController));
    
    return noErr;
}

-(AEAudioRenderCallback)renderCallback {
    return renderCallback;
}

@end


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
    AudioStreamBasicDescription audioFormat = {0};
    audioFormat.mSampleRate       = format.mSampleRate;               // 3
    audioFormat.mChannelsPerFrame = format.mChannelsPerFrame;                     // 4
    audioFormat.mFramesPerPacket  = 1;                     // 7
    audioFormat.mBitsPerChannel   = 16;                    // 5
    audioFormat.mBytesPerFrame   = audioFormat.mChannelsPerFrame * audioFormat.mBitsPerChannel/8;
    audioFormat.mBytesPerPacket =audioFormat.mBytesPerFrame*audioFormat.mFramesPerPacket;
    audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
    audioFormat.mFormatID = kAudioFormatLinearPCM;

    
    AEAudioController* audioController = [[AEAudioController alloc]initWithAudioDescription:audioFormat options:AEAudioControllerOptionEnableInput];
    return [audioController start:nil];
}
inline static GVoid audioProduceUnSetup(struct _GJAudioProduceContext* context){
    if(context->obaque){
#ifdef AUDIO_QUEUE_RECODE

        GJAudioQueueRecoder* recode = (__bridge_transfer GJAudioQueueRecoder *)(context->obaque);
        [recode stop];
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
    
    return result;
}
inline static GVoid audioProduceStop(struct _GJAudioProduceContext* context){
#ifdef AUDIO_QUEUE_RECODE
    GJAudioQueueRecoder* recode = (__bridge GJAudioQueueRecoder *)(context->obaque);
    [recode stop];
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
