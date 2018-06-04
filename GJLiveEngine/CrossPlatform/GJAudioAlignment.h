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
 对音频的pts和大小进行校正
 
 @param context context description
 @param data 音频数据
 @param size 音频数据内存大小,此时data真正的大小不能小于sizePerPacket，size必须sizePerFrame字节对齐
 @param pts pts为INVALID时表示data无效，只是用来读取缓冲数据，否则表示校正数据。
 @return 非负数表示有多余的缓存数据可以读取，否则表示读取错误。。
 */
GInt32 audioAlignmentUpdate(GJAudioAlignmentContext *context, GVoid *data, GInt size, GTime *pts);
#endif /* GJAudioAlignment_h */
