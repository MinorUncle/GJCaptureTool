//
//  GJAudioQueueRecode.h
//  Decoder
//
//  Created by tongguan on 16/2/22.
//  Copyright © 2016年 未成年大叔. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioFile.h>
static const int kNumberBuffers = 8;                            // 1
typedef struct _AQRecorderState {
    AudioQueueRef                mQueue;                        // 3
    AudioQueueBufferRef          mBuffers[kNumberBuffers];      // 4
    AudioFileID                  mAudioFile;                    // 5
    UInt32                       bufferByteSize;                // 6
    SInt64                       mCurrentPacket;                // 7
    bool                         mIsRunning;                    // 8
} AQRecorderState;
@class GJAudioQueueRecoderFile;

@protocol GJAudioQueueRecoderFileDelegate <NSObject>
@optional
//回调不带头信息
-(void)GJAudioQueueRecoderFile:(GJAudioQueueRecoderFile*) recoder streamData:(void*)data lenth:(int)lenth packetCount:(int)packetCount packetDescriptions:(const AudioStreamPacketDescription *)packetDescriptions;

@end
@interface GJAudioQueueRecoderFile : NSObject
@property(nonatomic,assign,readonly)AQRecorderState *pAqData;
@property(nonatomic,assign)int destMaxOutSize;
@property(nonatomic,assign,readonly)AudioStreamBasicDescription destFormat;
@property(nonatomic,weak)id<GJAudioQueueRecoderFileDelegate> delegate;


//AudioStreamBasicDescription desc;
//memset(&desc, 0, sizeof(AudioStreamBasicDescription));

//pcm
//desc.mFormatID = kAudioFormatLinearPCM;
//desc.mBitsPerChannel = 16;
//desc.mChannelsPerFrame = 1;
//desc.mSampleRate = 44100;
//desc.mFramesPerPacket = 1;
//desc.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;

//aac
//    desc.mFormatID         = kAudioFormatMPEG4AAC; // 2
//    desc.mSampleRate       = 44100;               // 3
//    desc.mChannelsPerFrame = 2;                     // 4
//    desc.mFramesPerPacket  = 1024;                     // 7

//defalut pcm
- (instancetype)initWithStreamDestFormat:(AudioStreamBasicDescription*)formatID;

-(BOOL)startRecodeAudio;
-(void)stop;

@end
