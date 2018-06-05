//
//  GJAudioAlignment.h
//  GJLiveEngine
//
//  Created by melot on 2018/6/4.
//  Copyright © 2018年 MinorUncle. All rights reserved.
//

#ifndef GJAudioAlignment_h
#define GJAudioAlignment_h

#include <stdio.h>
#include "GJLiveDefine.h"

typedef struct _GJAudioAlignmentContext GJAudioAlignmentContext;

void audioAlignmentAlloc(GJAudioAlignmentContext **pContext, const GJAudioFormat *format) ;
void audioAlignmentDelloc(GJAudioAlignmentContext **pContext) ;

/**
 对音频的pts和大小进行校正,校正后数据每次以sizePerPacket大小输出，所以无论何时outData的 size无论何时都不能小于sizePerPacket.
 输入和输出数据采用不同参数（外面可以传递相同地址，前提是inData的实际size不小于sizePerPacket），
 
 @param context context description
 @param inData 音频数据，当pts为INVALID时不会使用该数据，所以此时该内存是指用来读数据
 @param size 音频数据内存大小,size必须sizePerFrame字节对齐
 @param inoutPts pts为INVALID时表示data无效，只是用来读取缓冲数据，否则表示校正数据。
 @param outData 用于接受校正后的数据，所以内存至少是sizePerPacket。当为null时则不输出数据到outData，可以用来判断是否有新数据，避免了外面申请一块内存用于接受时又没有数据接收后又需要释放，导致的效率问题
 @return 0表示此次正常读取sizePerPacket大小数据，大于0表示至少sizePerPacket缓存可以继续读取。否则表示没有读取到数据。
 */
GInt32 audioAlignmentUpdate(GJAudioAlignmentContext *context, GUInt8 *inData, GInt size, GTime *inoutPts,GUInt8* outData);

#endif /* GJAudioAlignment_h */
