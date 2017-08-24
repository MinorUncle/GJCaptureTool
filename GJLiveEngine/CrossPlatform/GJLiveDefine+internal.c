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
GInt32 R_GJPacketMalloc(GJRetainBufferPool* pool,GJRetainBuffer** buffer,GHandle userdata){
    
    *buffer = (GJRetainBuffer*)calloc(1,sizeof(R_GJPacket));
    return sizeof(R_GJPacket);
}

GInt32 R_GJPCMFrameMalloc(GJRetainBufferPool* pool,GJRetainBuffer** buffer,GHandle userdata){
    
    *buffer = (GJRetainBuffer*)calloc(1,sizeof(R_GJPCMFrame));
    return sizeof(R_GJPCMFrame);
    
}
GInt32 R_GJPixelFrameMalloc(GJRetainBufferPool* pool,GJRetainBuffer** buffer,GHandle userdata){
    
    *buffer = (GJRetainBuffer*)calloc(1,sizeof(R_GJPixelFrame));
    return sizeof(R_GJPixelFrame);
    
}

//GJRetainBuffer* R_GJStreamPacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJStreamPacket));
//}
//GJRetainBuffer* R_GJStreamFrameMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJStreamFrame));
//}
