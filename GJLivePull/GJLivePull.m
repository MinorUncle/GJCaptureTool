//
//  GJLivePull.m
//  GJLivePull
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePull.h"
#import "GJRtmpPull.h"
#import "GJH264Decoder.h"
@interface GJLivePull()<GJH264DecoderDelegate>
{
    GJRtmpPull* _videoPull;
    GJH264Decoder* _decoder;
}
@end
@implementation GJLivePull
- (instancetype)init
{
    self = [super init];
    if (self) {
        _decoder = [[GJH264Decoder alloc]init];
        _decoder.delegate = self;
    }
    return self;
}

static void pullMessageCallback(GJRtmpPull* pull, GJRTMPPullMessageType messageType,void* rtmpPullParm,void* messageParm){
    switch (messageType) {
        case GJRTMPPullMessageType_connectError:
        case GJRTMPPullMessageType_urlPraseError:
        case GJRTMPPullMessageType_sendPacketError:
            GJRtmpPull_CloseAndRelease(pull);
            break;
            
        default:
            break;
    }
}
static void pullDataCallback(GJRtmpPull* pull,GJRTMPDataType dataType,GJRetainBuffer* buffer,uint32_t dts){
    if (dataType == GJRTMPVideoData) {
        
    }
}



- (BOOL)startStreamPullWithUrl:(char*)url{
    
    GJRtmpPull_Create(&_videoPull, pullMessageCallback, (__bridge void *)(self));
    GJRtmpPull_StartConnect(_videoPull, pullDataCallback, url);
    return YES;
}

- (void)stopStreamPull{
    GJRtmpPull_CloseAndRelease(_videoPull);
}

-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(uint)pts{

}


@end
