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
    }
@property(strong,nonatomic)GJH264Decoder* decoder;

@end
@implementation GJLivePull
@synthesize previewView = _previewView;
- (instancetype)init
{
    self = [super init];
    if (self) {
        _decoder = [[GJH264Decoder alloc]init];
        _decoder.delegate = self;
        _enablePreview = YES;
    }
    return self;
}

static void pullMessageCallback(GJRtmpPull* pull, GJRTMPPullMessageType messageType,void* rtmpPullParm,void* messageParm){
    GJLivePull* livePull = (__bridge GJLivePull *)(rtmpPullParm);
    LivePullMessageType message = kLivePullUnknownError;
    switch (messageType) {
        case GJRTMPPullMessageType_connectError:
        case GJRTMPPullMessageType_urlPraseError:
            message = kLivePullConnectError;
            GJRtmpPull_CloseAndRelease(pull);
            break;
        case GJRTMPPullMessageType_sendPacketError:
            GJRtmpPull_CloseAndRelease(pull);
            break;
            
        case GJRTMPPullMessageType_connectSuccess:
            message = kLivePullConnectSuccess;
            break;
        default:
            break;
    }
    [livePull.delegate livePull:livePull messageType:message infoDesc:nil];
}
static void pullDataCallback(GJRtmpPull* pull,GJRTMPDataType dataType,GJRetainBuffer* buffer,void* parm,uint32_t dts){
    GJLivePull* livePull = (__bridge GJLivePull *)(parm);
    if (dataType == GJRTMPVideoData) {
        [livePull.decoder decodeBuffer:buffer];
    }
}



- (BOOL)startStreamPullWithUrl:(char*)url{
    
    GJRtmpPull_Create(&_videoPull, pullMessageCallback, (__bridge void *)(self));
    GJRtmpPull_StartConnect(_videoPull, pullDataCallback, (__bridge void *)(self),(const char*) url);
    return YES;
}

- (void)stopStreamPull{
    GJRtmpPull_CloseAndRelease(_videoPull);
}

-(UIView *)getPreviewView{
    if (_previewView == nil) {
        _previewView = [[UIImageView alloc]init];
    }
    return _previewView;
}
-(void)setEnablePreview:(BOOL)enablePreview{
    _enablePreview = enablePreview;
    
}

-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(uint)pts{
    CIImage* cimage = [CIImage imageWithCVPixelBuffer:imageBuffer];
    UIImage* image = [UIImage imageWithCIImage:cimage];
    // Update the display with the captured image for DEBUG purposes
    dispatch_async(dispatch_get_main_queue(), ^{
        ((UIImageView*)_previewView).image = image;
    });

}


@end
