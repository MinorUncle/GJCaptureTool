//
//  GJDebug.h
//  media
//
//  Created by tongguan on 16/7/8.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#ifndef GJDebug_h
#define GJDebug_h

#include <stdio.h>
#ifndef DEBUG
//#ifdef DEBUG
#define _GJ_DEBUG(name, format, ...) printf("%s:%s,[line:%d]:" format "\n",name,__FUNCTION__, __LINE__,##__VA_ARGS__)
#else
#define _GJ_DEBUG(...)
#endif

#include <stdio.h>
#ifndef DEBUG
//#ifdef DEBUG
#define _GJ_LOG(name, format, ...) NSLog( name format ,##__VA_ARGS__)
#else
#define _GJ_LOG(...)
#endif


#define CAPTURE_DEBUG(format, ...) _GJ_DEBUG("CAPTURE_DEBUG: ", format,##__VA_ARGS__)
#define CAPTURE_LOG(format, ...) _GJ_LOG(@"CAPTURE_LOG: ", format,##__VA_ARGS__)


#define GJDecoder_DEBUG(format, ...) _GJ_DEBUG( "GJDecoder_DEBUG: ", format,##__VA_ARGS__)
#define GJDecoder_LOG(format, ...) _GJ_LOG( @"GJDecoder_LOG: ", format,##__VA_ARGS__)

#define GJH264Encoder_DEBUG(format, ...) _GJ_DEBUG( "GJH264Encoder_DEBUG: ", format,##__VA_ARGS__)
#define GJH264Encoder_LOG(format, ...) _GJ_LOG( @"GJH264Encoder_LOG: ", format,##__VA_ARGS__)

#define GJOpenAL_DEBUG(format, ...) _GJ_DEBUG( "GJOpenAL_DEBUG: ", format,##__VA_ARGS__)
#define GJOpenAL_LOG(format, ...) _GJ_LOG( @"GJOpenAL_LOG: ", format,##__VA_ARGS__)

#define AACEncoderFromPCM_DEBUG(format, ...) _GJ_DEBUG( "AACEncoderFromPCM_DEBUG: ", format,##__VA_ARGS__)
#define AACEncoderFromPCM_LOG(format, ...) _GJ_LOG( @"AACEncoderFromPCM_LOG: ", format,##__VA_ARGS__)

#define PCMDecodeFromAAC_DEBUG(format, ...) _GJ_DEBUG( "PCMDecodeFromAAC_DEBUG: ", format,##__VA_ARGS__)
#define PCMDecodeFromAAC_LOG(format, ...) _GJ_LOG( @"PCMDecodeFromAAC_LOG: ", format,##__VA_ARGS__)

#define AudioPraseStream_DEBUG(format, ...) _GJ_DEBUG( "AudioPraseStream_DEBUG: ", format,##__VA_ARGS__)
#define AudioPraseStream_LOG(format, ...) _GJ_LOG( @"AudioPraseStream_LOG: ", format,##__VA_ARGS__)

//#ifndef DEBUG
#ifdef DEBUG
#define GJQueueLOG(format, ...) printf(format,##__VA_ARGS__)
#else
#define GJQueueLOG(format, ...)
#endif
#endif /* GJDebug_h */
