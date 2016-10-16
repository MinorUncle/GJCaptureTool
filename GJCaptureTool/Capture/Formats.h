//
//  Formats.h
//  GJCaptureTool
//
//  Created by 未成年大叔 on 16/10/16.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#ifndef Formats_h
#define Formats_h

typedef struct GJVideoFormat{
    uint32_t width,height;
    void* extends;
    uint32_t extendSize;
    uint8_t fps;
    
}GJVideoFormat;

typedef struct GJAudioFormat{
    uint32_t width,height;

    
}GJAudioFormat;


#endif /* Formats_h */
