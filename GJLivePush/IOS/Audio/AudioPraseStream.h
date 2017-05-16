//
//  AudioPraseStream.h
//  GJCaptureTool
//
//  Created by tongguan on 16/7/8.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

/// 将任意不连续的aac packet流转换成连续的packet
@class AudioPraseStream;
@protocol AudioStreamPraseDelegate <NSObject>
@required
- (void)audioFileStream:(AudioPraseStream *)audioFileStream audioData:(const void *)audioData numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins;
@optional
- (void)audioFileStreamReadyToProducePackets:(AudioPraseStream *)audioFileStream;
- (AudioStreamPacketDescription)audioFileStream:(AudioPraseStream *)audioFileStream ParseDataResultWithPacketDescription:(AudioStreamPacketDescription*)packetDescription numberOfPacket:(int)number;;

@end

@interface AudioPraseStream : NSObject

@property (nonatomic,assign,readonly) AudioFileTypeID fileType;
@property (nonatomic,assign,readonly) BOOL available;
@property (nonatomic,assign,readonly) BOOL readyToProducePackets;
@property (nonatomic,weak) id<AudioStreamPraseDelegate> delegate;

@property (nonatomic,assign,readonly) AudioStreamBasicDescription format;
@property (nonatomic,assign,readonly) unsigned long long fileSize;
@property (nonatomic,assign,readonly) NSTimeInterval duration;
@property (nonatomic,assign,readonly) UInt32 bitRate;
@property (nonatomic,assign,readonly) UInt32 maxPacketSize;
@property (nonatomic,assign,readonly) UInt64 audioDataByteCount;


- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error;

- (BOOL)parseData:(void *)data  lenth:(int)lenth error:(NSError **)error;

/**
 *  seek to timeinterval
 *
 *  @param time On input, timeinterval to seek.
 On output, fixed timeinterval.
 *
 *  @return seek byte offset
 */
- (SInt64)seekToTime:(NSTimeInterval *)time;

- (NSData *)fetchMagicCookie;

- (void)close;
@end
