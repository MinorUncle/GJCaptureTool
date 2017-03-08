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
#import "GJImageView.h"
#import "GJImageYUVDataInput.h"
#import "GPUImageContext.h"
#import <CoreImage/CoreImage.h>
typedef struct _GJImageBuffer{
    CVImageBufferRef image;
    CMTime           pts;
}GJImageBuffer;

@interface GJLivePull()<GJH264DecoderDelegate>
{
    GJRtmpPull* _videoPull;
    pthread_t  _playThread;
    

}
@property(strong,nonatomic)GJImageYUVDataInput* YUVInput;
@property(strong,nonatomic)GPUImageView* displayView;
@property(strong,nonatomic)GJH264Decoder* decoder;
@property(assign,nonatomic)GJQueue* imageQueue;
@property(assign,nonatomic)GJQueue* audioQueue;
@property(assign,nonatomic)BOOL stopRequest;

@end
@implementation GJLivePull
- (instancetype)init
{
    self = [super init];
    if (self) {
        _decoder = [[GJH264Decoder alloc]init];
        _decoder.delegate = self;
        _enablePreview = YES;
        queueCreate(&_imageQueue, 30, true, false);
        queueCreate(&_audioQueue, 80, true, false);
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
        case GJRTMPPullMessageType_closeComplete:
            message = kLivePullCloseSuccess;
            break;
        default:
            break;
    }
    [livePull.delegate livePull:livePull messageType:message infoDesc:nil];
}
static void pullDataCallback(GJRtmpPull* pull,GJRTMPDataType dataType,GJRetainBuffer* buffer,void* parm,uint32_t pts){
    GJLivePull* livePull = (__bridge GJLivePull *)(parm);
    if (dataType == GJRTMPVideoData) {
        [livePull.decoder decodeBuffer:buffer pts:CMTimeMake(pts, 1000)];
    }
}

static void* playLoop(void* parm);

- (BOOL)startStreamPullWithUrl:(char*)url{
    

    GJRtmpPull_Create(&_videoPull, pullMessageCallback, (__bridge void *)(self));
    GJRtmpPull_StartConnect(_videoPull, pullDataCallback, (__bridge void *)(self),(const char*) url);
//    pthread_create(&_playThread, NULL, playLoop, (__bridge void *)(self));
    return YES;
}

- (void)stopStreamPull{
    GJRtmpPull_CloseAndRelease(_videoPull);
}

-(UIView *)getPreviewView{
    if (_displayView == nil) {
        _displayView = [[GJImageView alloc]init];
    }
    return _displayView;
}

-(void)setEnablePreview:(BOOL)enablePreview{
    _enablePreview = enablePreview;
    
}
GPUImageFramebuffer* fram;
-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(CMTime)pts{
    if (_YUVInput == nil) {
        OSType type = CVPixelBufferGetPixelFormatType(imageBuffer);
        if (type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            _YUVInput = [[GJImageYUVDataInput alloc]initPixelFormat:GJPixelFormatNV12];
            [_YUVInput addTarget:_displayView];
        }
    }
    
    [_YUVInput updateDataWithImageBuffer:imageBuffer timestamp:pts];
    return;
//    GJImageBuffer* buffer = malloc(sizeof(buffer));
//    buffer->image = imageBuffer;
//    buffer->pts = pts;
//    if (queuePush(_imageQueue, buffer, 0)) {
//        CVPixelBufferRetain(imageBuffer);
////        CVBufferRetain(imageBuffer);
//    }
    
    OSType re = CVPixelBufferGetPixelFormatType(imageBuffer);
    char* code = (char*)&re;
    NSLog(@"code:%c %c %c %c \n",code[3],code[2],code[1],code[0]);
    CGSize size = CVImageBufferGetEncodedSize(imageBuffer);
//    CVPixelBufferLockBaseAddress(imageBuffer, 0);
//    uint8_t* base = CVPixelBufferGetBaseAddress(imageBuffer);
//    uint8_t* Y = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
//    uint8_t* u = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
//    int c = CVPixelBufferGetPlaneCount(imageBuffer);
//    
//    CVPlanarPixelBufferInfo_YCbCrBiPlanar* bufferInfo = (CVPlanarPixelBufferInfo_YCbCrBiPlanar*)base;
//    NSUInteger yOffset = ntohl(bufferInfo->componentInfoY.offset);
//    NSUInteger yPitch = ntohl(bufferInfo->componentInfoY.rowBytes);
//    
//    NSUInteger cbCrOffset = ntohl(bufferInfo->componentInfoCbCr.offset);
//    NSUInteger cbCrPitch = ntohl(bufferInfo->componentInfoCbCr.rowBytes);
//    memset(base+cbCrOffset, 0, cbCrPitch*size.height*0.5);
//    
//    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    CVOpenGLESTextureCacheRef coreVideoTextureCache = [[GPUImageContext sharedImageProcessingContext] coreVideoTextureCache];

    CVOpenGLESTextureRef texture;
    CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage (kCFAllocatorDefault, coreVideoTextureCache, imageBuffer,
                                                        NULL, // texture attributes
                                                        GL_TEXTURE_2D,
                                                        GL_RED_EXT, // opengl format
                                                        (int)size.width,
                                                        (int)size.height,
                                                        GL_RED_EXT, // native iOS format
                                                        GL_UNSIGNED_BYTE,
                                                        0,
                                                        &texture);
    GPUImageFramebuffer* frameBuffer = [[GPUImageFramebuffer alloc]initWithSize:size overriddenTexture:CVOpenGLESTextureGetName(texture)];
    fram = frameBuffer;
    NSInteger textureIndex = [self.displayView nextAvailableTextureIndex];
    [self.displayView setInputFramebuffer:frameBuffer atIndex: textureIndex];
    [self.displayView setInputSize:size atIndex:textureIndex];
    [self.displayView newFrameReadyAtTime:pts atIndex:textureIndex];

//    [self.YUVInput updateDataWithY:Y U:u V:u+(long)(size.width*size.height/4) Timestamp:pts];

    return;
    
}

static void* playLoop(void* parm){
    GJLivePull* pull = (__bridge GJLivePull *)(parm);
    GJImageBuffer* preImage;
    if (!queuePop(pull.imageQueue, (void**)&preImage, INT_MAX)) {
        return NULL;
    }
    
    clock_t begin = 0;
    
    //play
    
//     Update the display with the captured image for DEBUG purposes
//        CIImage* cimage = [CIImage imageWithCVPixelBuffer:preImage->image];
//        UIImage* image = [UIImage imageWithCIImage:cimage];
//    ((UIImageView*)pull.displayView).image = image;

//    CGSize size = CVImageBufferGetEncodedSize(preImage->image);
//    CVPixelBufferLockBaseAddress(preImage->image, 0);
//    uint8_t* Y = CVPixelBufferGetBaseAddressOfPlane(preImage->image, 0);
//    uint8_t* u = CVPixelBufferGetBaseAddressOfPlane(preImage->image, 1);
//    int c = CVPixelBufferGetPlaneCount(preImage->image);
//    CVPixelBufferUnlockBaseAddress(preImage->image, 0);
//    pull.YUVInput = [[GJImageYUVDataInput alloc]initWithImageSize:size pixelFormat:GJYUVixelFormat420P type:GJPixelTypeUByte];
//    [pull.YUVInput updateDataWithY:Y U:u V:u+(long)(size.width*size.height/4) Timestamp:preImage->pts];
//    CVPixelBufferRelease(preImage->image);
//    GJImageBuffer* currentImage;
//
//    while (!pull.stopRequest) {
//        
//     
//        if( queuePop(pull.imageQueue, (void**)&currentImage, INT_MAX)){
//            float pastTime = currentImage->pts.value*1000.0/currentImage->pts.timescale- preImage->pts.value*1000.0/currentImage->pts.timescale;
//            clock_t end = clock();
//            float needWait = (end - begin)*1000.0/CLOCKS_PER_SEC - pastTime;
//            if (needWait > 1) {
//                usleep(needWait*1000);
//            }
//            //play
//            free(preImage);
//            preImage = currentImage;
//          
//            CVPixelBufferLockBaseAddress(preImage->image, 0);
//            uint8_t* Y = CVPixelBufferGetBaseAddressOfPlane(preImage->image, 0);
//            uint8_t* u = CVPixelBufferGetBaseAddressOfPlane(preImage->image, 1);
//            int c = CVPixelBufferGetPlaneCount(preImage->image);
//            CVPixelBufferUnlockBaseAddress(preImage->image, 0);
//            [pull.YUVInput updateDataWithY:Y U:u V:u+(long)(size.width*size.height/4) Timestamp:preImage->pts];
//            CVPixelBufferRelease(preImage->image);
//
//            begin = clock();
//            
//        };
//    }
//    
//    if (preImage) {
//        free(preImage);
//    }
    
    
    
    return NULL;
ERROR:
    return NULL;
}


@end
