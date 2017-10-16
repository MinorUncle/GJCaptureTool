//
//  AudioPraseStream.m
//  GJCaptureTool
//
//  Created by tongguan on 16/7/8.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import "AudioPraseStream.h"
#import "GJDebug.h"
#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 100

@interface AudioPraseStream () {
  @private
    BOOL _discontinuous;

    AudioFileStreamID _audioFileStreamID;

    SInt64         _dataOffset;
    NSTimeInterval _packetDuration;

    UInt64 _processedPacketsCount;
    UInt64 _processedPacketsSizeTotal;
}
- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID;
- (void)handleAudioFileStreamPackets:(const void *)packets
                       numberOfBytes:(UInt32)numberOfBytes
                     numberOfPackets:(UInt32)numberOfPackets
                  packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins;
@end

#pragma mark - static callbacks
static void MCSAudioFileStreamPropertyListener(void *                    inClientData,
                                               AudioFileStreamID         inAudioFileStream,
                                               AudioFileStreamPropertyID inPropertyID,
                                               UInt32 *                  ioFlags) {
    AudioPraseStream *audioFileStream = (__bridge AudioPraseStream *) inClientData;
    [audioFileStream handleAudioFileStreamProperty:inPropertyID];
}

static void MCAudioFileStreamPacketsCallBack(void *                        inClientData,
                                             UInt32                        inNumberBytes,
                                             UInt32                        inNumberPackets,
                                             const void *                  inInputData,
                                             AudioStreamPacketDescription *inPacketDescriptions) {
    AudioPraseStream *audioFileStream = (__bridge AudioPraseStream *) inClientData;
    [audioFileStream handleAudioFileStreamPackets:inInputData
                                    numberOfBytes:inNumberBytes
                                  numberOfPackets:inNumberPackets
                               packetDescriptions:inPacketDescriptions];
}

#pragma mark -
@implementation AudioPraseStream
@synthesize     fileType              = _fileType;
@synthesize     readyToProducePackets = _readyToProducePackets;
@dynamic        available;
@synthesize     delegate           = _delegate;
@synthesize     duration           = _duration;
@synthesize     bitRate            = _bitRate;
@synthesize     format             = _format;
@synthesize     maxPacketSize      = _maxPacketSize;
@synthesize     audioDataByteCount = _audioDataByteCount;

#pragma init &dealloc
- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error {
    self = [super init];
    if (self) {
        _discontinuous = NO;
        _fileType      = fileType;
        _fileSize      = fileSize;
        [self _openAudioFileStreamWithFileTypeHint:_fileType error:error];
    }
    return self;
}

- (void)dealloc {
    [self _closeAudioFileStream];
}

- (void)_errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError {
    if (status != noErr) {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        GJLOG(DEFAULT_LOG, @"error:%@", error.localizedDescription);
        if (outError != NULL) {
            *outError = error;
        }
    }
}

#pragma mark - open & close
- (BOOL)_openAudioFileStreamWithFileTypeHint:(AudioFileTypeID)fileTypeHint error:(NSError *__autoreleasing *)error {
    OSStatus status = AudioFileStreamOpen((__bridge void *) self,
                                          MCSAudioFileStreamPropertyListener,
                                          MCAudioFileStreamPacketsCallBack,
                                          fileTypeHint,
                                          &_audioFileStreamID);

    if (status != noErr) {
        _audioFileStreamID = NULL;
        [self _errorForOSStatus:status error:error];
    }

    return status == noErr;
}

- (void)_closeAudioFileStream {
    if (self.available) {
        AudioFileStreamClose(_audioFileStreamID);
        _audioFileStreamID = NULL;
    }
}

- (void)close {
    [self _closeAudioFileStream];
}

- (BOOL)available {
    return _audioFileStreamID != NULL;
}

#pragma mark - actions
- (NSData *)fetchMagicCookie {
    UInt32   cookieSize;
    Boolean  writable;
    OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (status != noErr) {
        return nil;
    }

    void *cookieData = malloc(cookieSize);
    status           = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (status != noErr) {
        return nil;
    }

    NSData *cookie = [NSData dataWithBytes:cookieData length:cookieSize];
    free(cookieData);

    return cookie;
}

- (BOOL)parseData:(void *)data lenth:(int)lenth error:(NSError **)error {
    if (self.readyToProducePackets && _packetDuration == 0) {
        [self _errorForOSStatus:-1 error:error];
        return NO;
    }

    GJLOG(DEFAULT_LOG, @"_discontinuous:%d", _discontinuous);
    OSStatus status = AudioFileStreamParseBytes(_audioFileStreamID, (UInt32) lenth, data, _discontinuous ? kAudioFileStreamParseFlag_Discontinuity : 0);
    [self _errorForOSStatus:status error:error];
    return status == noErr;
}

- (SInt64)seekToTime:(NSTimeInterval *)time {
    SInt64   approximateSeekOffset = _dataOffset + (*time / _duration) * _audioDataByteCount;
    SInt64   seekToPacket          = floor(*time / _packetDuration);
    SInt64   seekByteOffset;
    UInt32   ioFlags = 0;
    SInt64   outDataByteOffset;
    OSStatus status = AudioFileStreamSeek(_audioFileStreamID, seekToPacket, &outDataByteOffset, &ioFlags);
    if (status == noErr && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated)) {
        *time -= ((approximateSeekOffset - _dataOffset) - outDataByteOffset) * 8.0 / _bitRate;
        seekByteOffset = outDataByteOffset + _dataOffset;
    } else {
        _discontinuous = YES;
        seekByteOffset = approximateSeekOffset;
    }
    return seekByteOffset;
}

#pragma mark - callbacks
- (void)calculateBitRate {
    if (_packetDuration && _processedPacketsCount > BitRateEstimationMinPackets && _processedPacketsCount <= BitRateEstimationMaxPackets) {
        double averagePacketByteSize = _processedPacketsSizeTotal / _processedPacketsCount;
        _bitRate                     = 8.0 * averagePacketByteSize / _packetDuration;
    }
}

- (void)calculateDuration {
    if (_fileSize > 0 && _bitRate > 0) {
        _duration = ((_fileSize - _dataOffset) * 8.0) / _bitRate;
    }
}

- (void)calculatepPacketDuration {
    if (_format.mSampleRate > 0) {
        _packetDuration = _format.mFramesPerPacket / _format.mSampleRate;
    }
}

- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID {
    char *property = (char *) &propertyID;
    GJLOG(DEFAULT_LOG, @"propertyID:%c%c%c%c", property[3], property[2], property[1], property[0]);
    switch (propertyID) {
        case kAudioFileStreamProperty_ReadyToProducePackets: {
            _readyToProducePackets = YES;
            _discontinuous         = YES;

            UInt32   sizeOfUInt32 = sizeof(_maxPacketSize);
            OSStatus status       = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &_maxPacketSize);
            if (status != noErr || _maxPacketSize == 0) {
                status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &_maxPacketSize);
            }

            if (_delegate && [_delegate respondsToSelector:@selector(audioFileStreamReadyToProducePackets:)]) {
                [_delegate audioFileStreamReadyToProducePackets:self];
            }
            break;
        }
        case kAudioFileStreamProperty_DataOffset: {
            UInt32 offsetSize = sizeof(_dataOffset);
            AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataOffset, &offsetSize, &_dataOffset);
            _audioDataByteCount = _fileSize - _dataOffset;
            [self calculateDuration];
            break;
        }
        case kAudioFileStreamProperty_DataFormat: {
            UInt32 asbdSize = sizeof(_format);
            AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataFormat, &asbdSize, &_format);
            [self calculatepPacketDuration];
            break;
        }
        case kAudioFileStreamProperty_FormatList: {
            Boolean  outWriteable;
            UInt32   formatListSize;
            OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
            if (status == noErr) {
                AudioFormatListItem *formatList = malloc(formatListSize);
                OSStatus             status     = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, formatList);
                if (status == noErr) {
                    UInt32 supportedFormatsSize;
                    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize);
                    if (status != noErr) {
                        free(formatList);
                        return;
                    }

                    UInt32  supportedFormatCount = supportedFormatsSize / sizeof(OSType);
                    OSType *supportedFormats     = (OSType *) malloc(supportedFormatsSize);
                    status                       = AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize, supportedFormats);
                    if (status != noErr) {
                        free(formatList);
                        free(supportedFormats);
                        return;
                    }

                    for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i++) {
                        AudioStreamBasicDescription format = formatList[i].mASBD;
                        for (UInt32 j = 0; j < supportedFormatCount; ++j) {
                            NSLog(@"format:%d  support:%d", (unsigned int) format.mFormatID, (unsigned int) supportedFormats[j]);
                            if (format.mFormatID == supportedFormats[j]) {
                                char *formatC = (char *) &(format.mFormatID);
                                GJLOG(DEFAULT_LOG, @"formatC:%c%c%c%c", formatC[3], formatC[2], formatC[1], formatC[0]);
                                _format = format;
                                [self calculatepPacketDuration];
                            }
                        }
                    }
                    free(supportedFormats);
                }
                free(formatList);
            }
            break;
        }
        default:
            break;
    }
}

- (void)handleAudioFileStreamPackets:(const void *)packets
                       numberOfBytes:(UInt32)numberOfBytes
                     numberOfPackets:(UInt32)numberOfPackets
                  packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins {
    if (_discontinuous) {
        _discontinuous = NO;
    }

    if (numberOfBytes == 0 || numberOfPackets == 0) {
        return;
    }

    BOOL deletePackDesc = NO;
    if (packetDescriptioins == NULL) {
        deletePackDesc                             = YES;
        UInt32                        packetSize   = numberOfBytes / numberOfPackets;
        AudioStreamPacketDescription *descriptions = (AudioStreamPacketDescription *) malloc(sizeof(AudioStreamPacketDescription) * numberOfPackets);

        for (int i = 0; i < numberOfPackets; i++) {
            UInt32 packetOffset                     = packetSize * i;
            descriptions[i].mStartOffset            = packetOffset;
            descriptions[i].mVariableFramesInPacket = 0;
            if (i == numberOfPackets - 1) {
                descriptions[i].mDataByteSize = numberOfBytes - packetOffset;
            } else {
                descriptions[i].mDataByteSize = packetSize;
            }
        }
        packetDescriptioins = descriptions;
    }

    if ([self.delegate respondsToSelector:@selector(audioFileStream:ParseDataResultWithPacketDescription:numberOfPacket:)]) {
        [self.delegate audioFileStream:self ParseDataResultWithPacketDescription:packetDescriptioins numberOfPacket:numberOfPackets];
    }

    [_delegate audioFileStream:self audioData:packets numberOfBytes:numberOfBytes numberOfPackets:numberOfPackets packetDescriptions:packetDescriptioins];

    if (_processedPacketsCount < BitRateEstimationMaxPackets) {
        _processedPacketsCount += numberOfPackets;
        _processedPacketsSizeTotal += numberOfBytes;
        [self calculateBitRate];
        [self calculateDuration];
    }

    //    NSMutableArray *parsedDataArray = [[NSMutableArray alloc] init];
    //    for (int i = 0; i < numberOfPackets; ++i)
    //    {
    //        AudioStreamPacketDescription
    //        SInt64 packetOffset = packetDescriptioins[i].mStartOffset;
    //        MCParsedAudioData *parsedData = [MCParsedAudioData parsedAudioDataWithBytes:packets + packetOffset
    //                                                                  packetDescription:packetDescriptioins[i]];
    //
    //        [parsedDataArray addObject:parsedData];
    //        NSLog(@"dataLenth:%ld",(unsigned long)parsedData.data.length);
    //
    //        if (_processedPacketsCount < BitRateEstimationMaxPackets)
    //        {
    //            _processedPacketsSizeTotal += parsedData.packetDescription.mDataByteSize;
    //            _processedPacketsCount += 1;
    //            [self calculateBitRate];
    //            [self calculateDuration];
    //        }
    //    }
    //
    //    [_delegate audioFileStream:self audioDataParsed:parsedDataArray];

    if (deletePackDesc) {
        free(packetDescriptioins);
    }
}

@end
