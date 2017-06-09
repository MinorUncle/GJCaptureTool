//
//  AudioUnitCapture.m
//  TVBAINIAN
//
//  Created by 米花 mihuasama on 16/1/14.
//  Copyright © 2016年 tongguantech. All rights reserved.
//

#import "AudioUnitCapture.h"
#import <AVFoundation/AVFoundation.h>
#import "sys/utsname.h"

static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData);

static OSStatus playbackCallback(void *inRefCon,
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp *inTimeStamp,
                                 UInt32 inBusNumber,
                                 UInt32 inNumberFrames,
                                 AudioBufferList *ioData);

#define kOutputBus  0
#define kInputBus   1

@interface AudioUnitCapture ()
{
    GJRetainBufferPool* _bufferPool;
}
@property (copy,nonatomic)  void(^recDataBlock)(R_GJPCMFrame* pcmData);
@property (copy,nonatomic)  void(^playDataBlock)(uint8_t* playBuffer, int size);
@property (assign,nonatomic) AudioComponentInstance audioUnit;
@property (assign,nonatomic) float samplerate;
@end

@implementation AudioUnitCapture

@synthesize audioUnit       = _audioUnit;
@synthesize format      = _format;

AudioUnitCapture * globalUnit = NULL;


static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    
    
    
    AudioBuffer buffer;
    
    buffer.mNumberChannels = 1;
    buffer.mDataByteSize = inNumberFrames * 2;
    buffer.mData = malloc( inNumberFrames * 2 );
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = buffer;
    
    OSStatus status;

    status = AudioUnitRender([globalUnit audioUnit],
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &bufferList);
    [globalUnit checkError:status key:@"AudioUnitRender"];
    [globalUnit processAudio:&bufferList];
    
    free(bufferList.mBuffers[0].mData);
    
    return noErr;
}

static OSStatus playbackCallback(void *inRefCon,
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp *inTimeStamp,
                                 UInt32 inBusNumber,
                                 UInt32 inNumberFrames,
                                 AudioBufferList *ioData) {
    memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
    if (globalUnit.playDataBlock) {
        globalUnit.playDataBlock(ioData->mBuffers[0].mData, ioData->mBuffers[0].mDataByteSize);
    }
    return noErr;
}

- (id)initWithSamplerate:(float)samplerate channel:(UInt32)channel{
    self = [super init];
    if (self) {
        globalUnit = self;
        _format.mSampleRate       = samplerate;               // 3
        _format.mChannelsPerFrame = channel;                     // 4
        _format.mFramesPerPacket  = 1;                     // 7
        _format.mBitsPerChannel   = 16;                    // 5
        _format.mBytesPerFrame   = _format.mChannelsPerFrame * _format.mBitsPerChannel/8;
        _format.mFramesPerPacket = _format.mBytesPerFrame * _format.mFramesPerPacket ;
        _format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
        [self initAudio];
        GJRetainBufferPoolCreate(&_bufferPool, _format.mFramesPerPacket*1024, GTrue, R_GJPCMFrameMalloc, nil);
    }
    return self;
}


- (void)checkError:(int)ret key:(NSString *)key
{
    if (ret) {
        NSLog(@"Error : %@(%d)", key, ret);
    }
}

- (void)processAudio: (AudioBufferList*) bufferList
{
    if (_recDataBlock) {
        _recDataBlock(bufferList->mBuffers[0].mData, bufferList->mBuffers[0].mDataByteSize);
    }
}

- (void)initAudio
{
    
    OSStatus status;
    
    // Describe audio component
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    
    if
    ([[self deviceVersion]isEqualToString:@"iPhone 6s"] ||[[self deviceVersion]isEqualToString:@"iPhone 6s Plus"])
    {
        desc.componentSubType =  kAudioUnitSubType_RemoteIO;
    }
    else
    {
        desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    }
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Get component
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    
    // Get audio units
    status = AudioComponentInstanceNew(inputComponent, &_audioUnit);
    [self checkError:status key:@"AudioComponentInstanceNew"];
    
    // Enable IO for recording
    UInt32 flag = 1;
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  kInputBus,
                                  &flag,
                                  sizeof(flag));
    [self checkError:status key:@"kAudioOutputUnitProperty_EnableIO"];
    
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output,
                                  kOutputBus,
                                  &flag,
                                  sizeof(flag));
    [self checkError:status key:@"kAudioOutputUnitProperty_EnableIO"];
    
    // Describe format
    
 

    
    // Apply format
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  kInputBus,
                                  &_format,
                                  sizeof(_format));
    [self checkError:status key:@"kAudioUnitProperty_StreamFormat"];
    
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  kOutputBus,
                                  &_format,
                                  sizeof(_format));
    [self checkError:status key:@"kAudioUnitProperty_StreamFormat"];
    
    
    // Set input callback
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = recordingCallback;
    callbackStruct.inputProcRefCon = (__bridge AURenderCallbackStruct*)self;
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  kInputBus,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    [self checkError:status key:@"kAudioOutputUnitProperty_SetInputCallback"];
    
    // Set output callback
    callbackStruct.inputProc = playbackCallback;
    callbackStruct.inputProcRefCon = (__bridge AURenderCallbackStruct*)self;
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Global,
                                  kOutputBus,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    [self checkError:status key:@"kAudioUnitProperty_SetRenderCallback"];
    
    // Disable buffer allocation for the recorder (optional - do this if we want to pass in our own)
    flag = 0;
    status = AudioUnitSetProperty(_audioUnit,
                                  kAudioUnitProperty_ShouldAllocateBuffer,
                                  kAudioUnitScope_Output,
                                  kInputBus,
                                  &flag,
                                  sizeof(flag));
	   
    Float32 preferredBufferSize = 0.01; // in seconds
    AVAudioSession* session = [AVAudioSession sharedInstance];
    [session setPreferredIOBufferDuration:preferredBufferSize error:nil];
    [session setActive:YES error:nil];
    
    // Initialise
    status = AudioUnitInitialize(_audioUnit);
    [self checkError:status key:@"AudioUnitInitialize"];
}


- (NSString*)deviceVersion
{
    // 需要#import "sys/utsname.h"
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceString = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    
    //iPhone
    if ([deviceString isEqualToString:@"iPhone1,1"])    return @"iPhone 1G";
    if ([deviceString isEqualToString:@"iPhone1,2"])    return @"iPhone 3G";
    if ([deviceString isEqualToString:@"iPhone2,1"])    return @"iPhone 3GS";
    if ([deviceString isEqualToString:@"iPhone3,1"])    return @"iPhone 4";
    if ([deviceString isEqualToString:@"iPhone3,2"])    return @"Verizon iPhone 4";
    if ([deviceString isEqualToString:@"iPhone4,1"])    return @"iPhone 4S";
    if ([deviceString isEqualToString:@"iPhone5,1"])    return @"iPhone 5";
    if ([deviceString isEqualToString:@"iPhone5,2"])    return @"iPhone 5";
    if ([deviceString isEqualToString:@"iPhone5,3"])    return @"iPhone 5C";
    if ([deviceString isEqualToString:@"iPhone5,4"])    return @"iPhone 5C";
    if ([deviceString isEqualToString:@"iPhone6,1"])    return @"iPhone 5S";
    if ([deviceString isEqualToString:@"iPhone6,2"])    return @"iPhone 5S";
    if ([deviceString isEqualToString:@"iPhone7,1"])    return @"iPhone 6 Plus";
    if ([deviceString isEqualToString:@"iPhone7,2"])    return @"iPhone 6";
    if ([deviceString isEqualToString:@"iPhone8,1"])    return @"iPhone 6s";
    if ([deviceString isEqualToString:@"iPhone8,2"])    return @"iPhone 6s Plus";
    
    //iPod
    if ([deviceString isEqualToString:@"iPod1,1"])      return @"iPod Touch 1G";
    if ([deviceString isEqualToString:@"iPod2,1"])      return @"iPod Touch 2G";
    if ([deviceString isEqualToString:@"iPod3,1"])      return @"iPod Touch 3G";
    if ([deviceString isEqualToString:@"iPod4,1"])      return @"iPod Touch 4G";
    if ([deviceString isEqualToString:@"iPod5,1"])      return @"iPod Touch 5G";
    
    //iPad
    if ([deviceString isEqualToString:@"iPad1,1"])      return @"iPad";
    if ([deviceString isEqualToString:@"iPad2,1"])      return @"iPad 2 (WiFi)";
    if ([deviceString isEqualToString:@"iPad2,2"])      return @"iPad 2 (GSM)";
    if ([deviceString isEqualToString:@"iPad2,3"])      return @"iPad 2 (CDMA)";
    if ([deviceString isEqualToString:@"iPad2,4"])      return @"iPad 2 (32nm)";
    if ([deviceString isEqualToString:@"iPad2,5"])      return @"iPad mini (WiFi)";
    if ([deviceString isEqualToString:@"iPad2,6"])      return @"iPad mini (GSM)";
    if ([deviceString isEqualToString:@"iPad2,7"])      return @"iPad mini (CDMA)";
    
    if ([deviceString isEqualToString:@"iPad3,1"])      return @"iPad 3(WiFi)";
    if ([deviceString isEqualToString:@"iPad3,2"])      return @"iPad 3(CDMA)";
    if ([deviceString isEqualToString:@"iPad3,3"])      return @"iPad 3(4G)";
    if ([deviceString isEqualToString:@"iPad3,4"])      return @"iPad 4 (WiFi)";
    if ([deviceString isEqualToString:@"iPad3,5"])      return @"iPad 4 (4G)";
    if ([deviceString isEqualToString:@"iPad3,6"])      return @"iPad 4 (CDMA)";
    
    if ([deviceString isEqualToString:@"iPad4,1"])      return @"iPad Air";
    if ([deviceString isEqualToString:@"iPad4,2"])      return @"iPad Air";
    if ([deviceString isEqualToString:@"iPad4,3"])      return @"iPad Air";
    if ([deviceString isEqualToString:@"iPad5,3"])      return @"iPad Air 2";
    if ([deviceString isEqualToString:@"iPad5,4"])      return @"iPad Air 2";
    if ([deviceString isEqualToString:@"i386"])         return @"Simulator";
    if ([deviceString isEqualToString:@"x86_64"])       return @"Simulator";
    
    if ([deviceString isEqualToString:@"iPad4,4"]
        ||[deviceString isEqualToString:@"iPad4,5"]
        ||[deviceString isEqualToString:@"iPad4,6"])      return @"iPad mini 2";
    
    if ([deviceString isEqualToString:@"iPad4,7"]
        ||[deviceString isEqualToString:@"iPad4,8"]
        ||[deviceString isEqualToString:@"iPad4,9"])      return @"iPad mini 3";
    
    return deviceString;
}

- (void)startRecording:(void(^)(R_GJPCMFrame* frame))dataBlock
{
    _recDataBlock = dataBlock;
    NSError *audioSessionError = nil;
    
    AVAudioSession *mySession = [AVAudioSession sharedInstance];     // 1
    [mySession setPreferredInputNumberOfChannels:_format.mChannelsPerFrame error:&audioSessionError];
    [mySession setPreferredIOBufferDuration:1024.0/_format.mSampleRate error:&audioSessionError];
    [mySession setCategory: AVAudioSessionCategoryPlayAndRecord      // 3
                     error: &audioSessionError];
    [mySession setActive: YES                                        // 4
                   error: &audioSessionError];
    OSStatus status = AudioOutputUnitStart(_audioUnit);
    [self checkError:status key:@"AudioOutputUnitStart"];
}

- (void)setPlayBlock:(void(^)(uint8_t* playBuffer, int size))playBlock
{
    _playDataBlock = playBlock;
}

- (void)stopRecording
{
    OSStatus status = AudioOutputUnitStop(_audioUnit);
    [self checkError:status key:@"AudioOutputUnitStop"];
    status = AudioUnitUninitialize(_audioUnit);
    [self checkError:status key:@"AudioUnitUninitialize"];
    status = AudioComponentInstanceDispose(_audioUnit);
    [self checkError:status key:@"AudioUnitUninitialize"];
    [self destoryBlcock];
}

- (void)destoryBlcock
{
    _playDataBlock = nil;
    _recDataBlock = nil;
    globalUnit = nil;

}

- (void)dealloc
{
}

@end
