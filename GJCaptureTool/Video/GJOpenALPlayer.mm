//
//  GJOpenALPlayer.m
//  BTDemo
//
//  Created by crte on 13-8-16.
//  Copyright (c) 2013年 Shadow. All rights reserved.
//

#import "GJOpenALPlayer.h"
#import <AVFoundation/AVFoundation.h>
//#import "GJQueue+cplus.h"
#import "GJDebug.h"
#import "GJQueue.h"


@interface GJOpenALPlayer()
{
    int _samplerate;
    int _bitPerFrame;
    int _channels;
}
//声音环境
@property(nonatomic,assign) ALCcontext *mContext;
//声音设备
@property(nonatomic,assign) ALCdevice *mDevice;
//声源
@property(nonatomic,assign) ALuint outSourceID;
@end
@implementation GJOpenALPlayer
{
    GJQueue* _queue;
}
//@synthesize outSourceID;

- (instancetype)initWithSamplerate:(int)samplerate bitPerFrame:(int)bitPerFrame channels:(int)channels
{
    self = [super init];
    if (self) {
        _samplerate = samplerate;
        _bitPerFrame = bitPerFrame;
        _channels = channels;
    }
    return self;
}

-(bool)initOpenAl{
    if (!self.mDevice) {
        self.mDevice = alcOpenDevice(NULL);
        if (!self.mDevice) {
            self.mContext = alcGetCurrentContext();
            if (self.mContext!=nil) {
                self.mDevice = alcGetContextsDevice(_mContext);
                if (self.mDevice == nil) {
                    GJQueuePrintf("alcGetContextsDevice失败\n");
                    return false;
                }
                GJQueuePrintf("alcGetContextsDevice 成功\n");
                
            }else{
                GJQueuePrintf("alcOpenDevice失败\n");
                return false;
            }
            
        }
    }
    
    if (!self.mContext) {
        self.mContext = alcCreateContext(self.mDevice, NULL);
        if (!self.mContext || !alcMakeContextCurrent(self.mContext)) {
            GJQueuePrintf("alcCreateContext || alcMakeContextCurrent失败\n");
            return false;
        }
    }
    //创建音源
    alGenSources(1, &_outSourceID);
    ALenum error = alGetError();
    if (error != AL_NO_ERROR) {
        GJQueuePrintf("alGenSources失败：%d",error);
    }
    //设为不循环
    alSourcei(_outSourceID, AL_LOOPING, AL_FALSE);
    error = alGetError();
    if (error != AL_NO_ERROR) {
        GJQueuePrintf("alSourcei AL_LOOPING errorCode:%d\n",error);
    }
    //播放模式设为流式播放
    alSourcef(_outSourceID, AL_SOURCE_TYPE, AL_STREAMING);
    //清除错误
    error = alGetError();
    if (error != AL_NO_ERROR) {
        GJQueuePrintf("alSourcei AL_SOURCE_TYPE errorCode:%d\n",error);
    }
    [self initBuffers];
    return YES;
}
-(void)initBuffers{

    ALenum error;
    queueCreate(&_queue, 10);
    for (int i = 0; i<10 ; i++) {
        ALuint bufferID = 1;
        alGenBuffers(1, &bufferID);
        error = alGetError();
        if (error != AL_NO_ERROR) {
            GJQueuePrintf("alGenBuffers errorCode:%d\n",error);
            break;
        }
        queuePush(_queue, (void*)bufferID);
    }
}
-(void)stop{
    _state = OpenalStateStop;
    ALint state;
    ALenum error;
    alGetSourcei(self.outSourceID, AL_SOURCE_STATE, &state);
    if (state != AL_STOPPED) {
        alSourceStop(self.outSourceID);
        error = alGetError();
        if (error != AL_NO_ERROR) {
            GJQueuePrintf("alSourceStop outSourceID:%d, error Code: %d\n",_outSourceID, error);
        }
        alSourcei(_outSourceID, AL_BUFFER, NULL);
        error = alGetError();
        if (error != AL_NO_ERROR) {
            GJQueuePrintf("alSourcei AL_BUFFER ERROR: %d\n",error);
        }
        [self clean];
    }
}
-(void)pause{
    _state = OpenalStatePause;
    ALint state;
    ALenum error;
    alGetSourcei(self.outSourceID, AL_SOURCE_STATE, &state);
    if (state != AL_STOPPED) {
        alSourcePause(self.outSourceID);
        error = alGetError();
        if (error != AL_NO_ERROR) {
            GJQueuePrintf("alSourcePause outSourceID:%d,error code: %d\n",_outSourceID, error);
        }
    }
}

-(void)play
{
    _state = OpenalStatePlay;
    if (_outSourceID == 0) {
        [self initOpenAl];
    }
    ALint  state;
    ALenum error;
    alGetSourcei(self.outSourceID, AL_SOURCE_STATE, &state);
    if (state != AL_PLAYING)
    {
        alSourcePlay(_outSourceID);
        error = alGetError();
        if (error != AL_NO_ERROR) {
            GJQueuePrintf("alSourcePlay outSourceID:%d,error code: %d\n",_outSourceID, error);
        }
    }
}
//重启。
- (void)reStart
{
    [self clean];
    [self initOpenAl];
    [self play];
}



-(void)setVolume:(float)volume{
    volume = MAX(volume, 0);
    volume = MIN(volume, 1);
    _volume = volume;
    //设置播放音量
    alSourcef(_outSourceID, AL_GAIN, _volume);
    ALenum error = alGetError();
    if (error != noErr) {
        GJQueuePrintf("音量设置失败 outSourceID:%d,error code: %d\n",_outSourceID, error);
    }
}

-(void)playData:(unsigned char *)data size:(UInt32)size{
    [self insertPCMDataToQueue:data size:size samplerate:_samplerate bitPerFrame:_bitPerFrame channels:_channels];
}

- (void)insertPCMDataToQueue:(unsigned char *)data size:(UInt32)size samplerate:(long)samplerate bitPerFrame:(long)bitPerFrame channels:(long)channels
{
    ALint state;
    ALenum error;
    if (_state != OpenalStatePlay) {
        return;
    }
    
    //读取错误信息
    error = alGetError();
    if (error != AL_NO_ERROR) {
        GJQueuePrintf("插入数据之前 outSourceID:%d,error code: %d\n",_outSourceID, error);
        [self reStart];
        return;
    }
    //常规安全性判断
    if (data == NULL) {
        GJQueuePrintf("GJOpenALPlayer:插入PCM数据为空, 返回\n");
        return;
    }
    
    if(queueGetLength(_queue) < 10*0.3){
        [self updataQueueBuffer];
    }
    error = alGetError();
    if (error != AL_NO_ERROR) {
        GJQueuePrintf("updataQueueBuffer outSourceID:%d,error code: %d\n",_outSourceID, error);
    }
    
    ALuint bufferID = 0;
    if (!queuePop(_queue, (void**)&bufferID)) {
        if (queueGetLength(_queue)>10) {
            NSLog(@"audio cache over flat ");
            return;
        }
        ALenum error;
            alGenBuffers(1, &bufferID);
            error = alGetError();
            if (error != AL_NO_ERROR) {
                GJQueuePrintf("alGenBuffers errorCode:%d\n",error);
                return;
            }
        
    };
    //将数据存入缓存区
    if (bitPerFrame ==0) {
        bitPerFrame = _bitPerFrame;
    }
    if (channels == 0) {
        channels = _channels;
    }
    if (samplerate == 0) {
        samplerate = _samplerate;
    }
    
    if (bitPerFrame == 8&&channels == 1) {
        alBufferData(bufferID, AL_FORMAT_MONO8, (char *)data, (ALsizei)size, (int)samplerate);
    }
    else if (bitPerFrame == 16&&channels == 1)
    {
        alBufferData(bufferID, AL_FORMAT_MONO16, (char *)data, (ALsizei)size,  (int)samplerate);
    }
    else if (bitPerFrame == 8&&channels == 2)
    {
        alBufferData(bufferID, AL_FORMAT_STEREO8, (char *)data, (ALsizei)size,  (int)samplerate);
    }
    else if (bitPerFrame == 16&&channels == 2)
    {
        alBufferData(bufferID, AL_FORMAT_STEREO16, (char *)data, (ALsizei)size,  (int)samplerate);
    }
    error = alGetError();
    if (error != AL_NO_ERROR) {
        GJQueuePrintf("alBufferData outSourceID:%d,error code: %d\n",_outSourceID, error);
    }
    //        添加到队列
    alSourceQueueBuffers(self.outSourceID, 1, &bufferID);
    
    error = alGetError();
    if (error != AL_NO_ERROR) {
        GJQueuePrintf("alSourceQueueBuffers outSourceID:%d,error code: %d\n",_outSourceID, error);
    }
    alGetSourcei(self.outSourceID, AL_SOURCE_STATE, &state);
    if(state != AL_PLAYING){
        [self play];
    }
}




+ (void)setPlayBackToSpeaker
{
    
    NSError * error;
    //    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    //    [audioSession overrideOutputAudioPort:kAudioSessionOverrideAudioRoute_Speaker error:&error];
    //    [audioSession setActive:YES error:&error];
}

- (void)clean
{
    ALenum error;
    alSourcei(_outSourceID, AL_BUFFER, NULL);
    error = alGetError();
    if (error != AL_NO_ERROR) {
        GJQueuePrintf("alSourcei AL_BUFFER ERROR: %d\n",error);
    }
    //删除声源
    alDeleteSources(1, &_outSourceID);
    if (self.mContext !=nil) {
        //删除环境
        alcDestroyContext(self.mContext);
    }
    if (self.mDevice != nil) {
        //关闭设备
        alcCloseDevice(self.mDevice);
    }
    self.mContext = nil;
    self.mDevice = nil;
    _outSourceID = 0;
    
    [self deleteQueueBuffers];
}



- (void)getInfo
{
    
    ALint queued;
    ALint processed;
    alGetSourcei(_outSourceID, AL_BUFFERS_PROCESSED, &processed);
    alGetSourcei(_outSourceID, AL_BUFFERS_QUEUED, &queued);
    NSLog(@"process = %d, queued = %d\n", processed, queued);
}

-(BOOL)updataQueueBuffer
{
    int processed ;
    alGetSourcei(_outSourceID, AL_BUFFERS_PROCESSED, &processed);
    // alGetSourcei(_outSourceID, AL_BUFFERS_QUEUED, &queued);
    
    // NSLog(@"Processed = %d\n", processed);
    // NSLog(@"Queued = %d\n", queued);
    while (processed-->0)
    {
        ALuint  buffer;
        alSourceUnqueueBuffers(_outSourceID, 1, &buffer);
        queuePush(_queue, (void*)buffer);
//        _queue.queuePush(buffer);
    }
    return YES;
}

-(void)deleteQueueBuffers{
    ALenum error;
    ALuint bufferID = 0;

    while (queuePop(_queue, (void**)&bufferID)) {
        alDeleteBuffers(1, &bufferID);
        error = alGetError();
        if (error != AL_NO_ERROR) {
            GJQueuePrintf("deleteBuffers:%d 错误, 错误信息: %d\n",bufferID,error);
        }
    }
}

- (void)dealloc
{
    [self deleteQueueBuffers];
    GJQueuePrintf("openal 销毁\n");
}

@end
