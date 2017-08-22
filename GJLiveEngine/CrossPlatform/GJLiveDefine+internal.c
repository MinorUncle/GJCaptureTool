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
//GJRetainBuffer* R_GJAACPacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJAACPacket));
//}
//
//GJRetainBuffer* R_GJH264PacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJH264Packet));
//}
GJRetainBuffer* R_GJPacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
    
    GJRetainBuffer * buffer;
#if MENORY_CHECK
    GLong* data = (GLong*)calloc(1,sizeof(R_GJPacket)+sizeof(GJRetainBufferPool));
    data[0] = (GLong)pool;
    buffer =  (GJRetainBuffer*)(data+1);
#else
    buffer = (GJRetainBuffer*)calloc(1,sizeof(R_GJPacket));
#endif
    return buffer;
}

GJRetainBuffer* R_GJPCMFrameMalloc(GJRetainBufferPool* pool,GHandle userdata){
    
    GJRetainBuffer * buffer;
#if MENORY_CHECK
    GLong* data = (GLong*)calloc(1,sizeof(R_GJPCMFrame)+sizeof(GJRetainBufferPool));
    data[0] = (GLong)pool;
    buffer =  (GJRetainBuffer*)(data+1);
#else
    buffer = (GJRetainBuffer*)calloc(1,sizeof(R_GJPCMFrame));
#endif
    return buffer;
    
}
GJRetainBuffer* R_GJPixelFrameMalloc(GJRetainBufferPool* pool,GHandle userdata){
    
    GJRetainBuffer * buffer;
#if MENORY_CHECK
    GLong* data = (GLong*)calloc(1,sizeof(R_GJPixelFrame)+sizeof(GJRetainBufferPool));
    data[0] = (GLong)pool;
    buffer =  (GJRetainBuffer*)(data+1);
#else
    buffer = (GJRetainBuffer*)calloc(1,sizeof(R_GJPixelFrame));
#endif
    return buffer;
    
}

//GJRetainBuffer* R_GJStreamPacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJStreamPacket));
//}
//GJRetainBuffer* R_GJStreamFrameMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJStreamFrame));
//}
