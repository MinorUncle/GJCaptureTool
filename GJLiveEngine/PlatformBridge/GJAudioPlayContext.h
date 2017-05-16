//
//  GJAudioPlayContext.h
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/5/16.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJAudioPlayContext_h
#define GJAudioPlayContext_h

#include <stdio.h>
#include "GJLiveDefine.h"
#include "GJFormats.h"
typedef struct _GJAudioPlayContext{
    GHandle obaque;
    GBool (*audioPlayInit) (struct _GJAudioPlayContext* context,GJPCMFormat format);
    GVoid (*audioPlayCallback) (struct _GJAudioPlayContext* context,GHandle audioData,GInt32 size);
}GJAudioPlayContext;
#endif /* GJAudioPlayContext_h */
