//
//  GJLiveDefine+internal.c
//  GJCaptureTool
//
//  Created by melot on 2017/4/5.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJLiveDefine+internal.h"
#include <stdlib.h>
#include "GJBufferPool.h"
long kcpOnceToken;

//GBool R_RetainBufferRelease(GJRetainBuffer* buffer){
//    if (buffer->data) {
//        free(buffer->data);
//    }
//    free(buffer);
//    return GTrue;
//}
//GJRetainBuffer* R_GJAACPacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJAACPacket));
//}
//
//GJRetainBuffer* R_GJH264PacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJH264Packet));
//}
GInt32 R_GJPacketMalloc(GJRetainBufferPool *pool) {

    return sizeof(R_GJPacket);
}

GInt32 R_GJPCMFrameMalloc(GJRetainBufferPool *pool) {

    return sizeof(R_GJPCMFrame);
}
GInt32 R_GJPixelFrameMalloc(GJRetainBufferPool *pool) {

    return sizeof(R_GJPixelFrame);
}

GVoid cleanMemory(GBool async){
    GJBufferPoolClean(defauleBufferPool(),async);
}



//GJRetainBuffer* R_GJStreamPacketMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJStreamPacket));
//}
//GJRetainBuffer* R_GJStreamFrameMalloc(GJRetainBufferPool* pool,GHandle userdata){
//    return (GJRetainBuffer*)calloc(1,sizeof(R_GJStreamFrame));
//}
