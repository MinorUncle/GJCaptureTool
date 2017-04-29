//
//  GJLiveDefine+internal.c
//  GJCaptureTool
//
//  Created by melot on 2017/4/5.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLiveDefine+internal.h"
#include <stdlib.h>
GBool R_RetainBufferRelease(GJRetainBuffer* buffer){
    if (buffer->data) {
        free(buffer->data);
    }
    free(buffer);
    return GTrue;
}
GJRetainBuffer* R_GJAACPacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
    return (GJRetainBuffer*)malloc(sizeof(R_GJAACPacket));
}
GJRetainBuffer* R_GJPCMPacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
    return (GJRetainBuffer*)malloc(sizeof(R_GJPCMPacket));
}
