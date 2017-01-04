//
//  ViewController.m
//  GJCaptureTool
//
//  Created by tongguan on 16/6/27.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import "ViewController.h"
#import "GJCaptureTool.h"
#import "OpenGLView20.h"
#import "Audio/GJAudioQueuePlayer.h"
#import "GJH264Decoder.h"
#import "GJH264Encoder.h"
#import <MediaPlayer/MPMoviePlayerViewController.h>
#import "PCMDecodeFromAAC.h"
#import "AACEncoderFromPCM.h"
#import "AudioPraseStream.h"
#import "AudioUnitCapture.h"
#import "H264Decoder.h"
#import "H264Encoder.h"
#import "H264StreamToTS.h"
//#import "rtmp.h"
#import "RtmpSendH264.h"
#import "GJFormats.h"
#import "LibRtmpSession.hpp"
#import "rtmp/log.h"
#import "GJAudioQueueRecoder.h"
extern "C"{
#import "avformat.h"
#import "swscale.h"
#import "avcodec.h"
#import "GJQueue.h"
#import "GJBufferPool.h"

}
GJQueue* _mp4VideoQueue;
GJQueue* _mp4AudioQueue;
BOOL _recodeState;

@interface ViewController ()<GJCaptureToolDelegate,GJH264DecoderDelegate,GJH264EncoderDelegate,AACEncoderFromPCMDelegate,PCMDecodeFromAACDelegate,AudioStreamPraseDelegate,H264DecoderDelegate,H264EncoderDelegate,GJAudioQueueRecoderDelegate>
{
    GJAudioQueuePlayer* _audioPlayer;
    AudioPraseStream* _praseStream;
    LibRtmpSession* _rtmpSend;
    BOOL _stop;
    H264StreamToTS* _toTS;
    H264Decoder* _decode;
    H264Encoder* _encoder;
    GJBufferPool _videoYUVPool;
    GJBufferPool _videoH264Pool;
    NSTimer* _timer;
    int _totalCount;
    float _totalByte;
    NSDate* _beginDate;
    MPMoviePlayerViewController* _player;
    GJAudioQueueRecoder* _audioRecoder;
    AVFormatContext* pMp4VFormat;
    AVFormatContext* pMp4AFormat;

}
@property(nonatomic,strong)UIImageView* imageView;

@property(nonatomic,strong)GJH264Decoder* gjDecoder;
@property(nonatomic,strong)GJH264Encoder* gjEncoder;

@property(nonatomic,strong)PCMDecodeFromAAC* audioDecoder;
@property(nonatomic,strong)AACEncoderFromPCM* audioEncoder;

@property(nonatomic,strong)AudioUnitCapture* audioUnitCapture;
@property(nonatomic,strong)GJCaptureTool* captureTool;

@property (weak, nonatomic) IBOutlet UIView *viewContainer;
@property (weak, nonatomic) IBOutlet UIButton *takeButton;//拍照按钮
@property (weak, nonatomic) IBOutlet OpenGLView20 *playView;    ///播放view
@property (weak, nonatomic) IBOutlet UILabel *fpsLab;
@property (weak, nonatomic) IBOutlet UILabel *ptsLab;
@property (weak, nonatomic) IBOutlet UILabel *stateLab;

@end

@implementation ViewController
-(UIImageView *)imageView{
    if (_imageView == nil) {
        _imageView = [[UIImageView alloc]initWithFrame:_playView.bounds];
        [_playView addSubview:_imageView];
    }
    return _imageView;
}
#define FPS 15

- (void)viewDidLoad {
    [super viewDidLoad];
    queueCreate(&_mp4AudioQueue, 10);
    queueCreate(&_mp4VideoQueue, 10);
//    _praseStream = [[AudioPraseStream alloc]initWithFileType:kAudioFileAAC_ADTSType fileSize:0 error:nil];
//    _praseStream.delegate = self;
    int fps = FPS;
    _captureTool = [[GJCaptureTool alloc]initWithType:GJCaptureType(GJCaptureTypeVideoStream | GJCaptureTypeAudioStream) fps:fps layer:_viewContainer.layer];
    _captureTool.delegate = self;
    _gjEncoder = [[GJH264Encoder alloc]initWithFps:fps];
    _gjDecoder = [[GJH264Decoder alloc]init];
    _audioEncoder = [[AACEncoderFromPCM alloc]init];
    _audioEncoder.delegate = self;
    _audioDecoder = [[PCMDecodeFromAAC alloc]init];
    _audioDecoder.delegate = self;
    _gjDecoder.delegate = self;
    _gjEncoder.deleagte = self;
//    char* url="rtmp://192.168.1.102:1935/myapp/room";
//    _rtmpSend = new LibRtmpSession(url);
    // Do any additional setup after loading the view, typically from a nib.
//    AudioStreamBasicDescription format;
//    memset( &format, 0x00, sizeof(format) );
//    
//    UInt32 size = sizeof(format.mChannelsPerFrame);
//    OSStatus err = AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareInputNumberChannels,
//                                           &size,
//                                           &format.mChannelsPerFrame);
//    
//    format.mSampleRate			= 44100;
//    format.mFormatID			= kAudioFormatLinearPCM;
//    format.mFormatFlags         = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
//    format.mChannelsPerFrame	= 2;
//    format.mFramesPerPacket     = 1;
//    format.mBitsPerChannel		= 16;
//    format.mBytesPerPacket		= format.mBytesPerFrame = (format.mBitsPerChannel / 8) * format.mChannelsPerFrame;
//
//    _audioRecoder = [[GJAudioQueueRecoder alloc]initWithStreamDestFormat:&format];
//    _audioRecoder.delegate = self;
//    [_audioRecoder startRecodeAudio];
}
-(void)GJAudioQueueRecoder:(GJAudioQueueRecoder*) recoder streamData:(void*)data lenth:(int)lenth packetCount:(int)packetCount packetDescriptions:(const AudioStreamPacketDescription *)packetDescriptions{

    NSLog(@"GJAudioQueueRecoder");
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
//    [self connect];
    [_captureTool startRunning];
}
-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    [_captureTool stopRunning];
}
- (IBAction)changeCap:(UIButton*)sender {
    [_captureTool changeCapturePosition];
}
- (IBAction)Recode:(UIButton*)sender {
    sender.selected = !sender.selected;
    if (sender.selected) {
        

        _beginDate = [NSDate date];
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateSpeed) userInfo:nil repeats:YES];
        [_captureTool startRecodeing];
//        [_audioPlayer start];
        _recodeState = YES;
        [self mp4RecodeInit];

    }else{
        [_timer invalidate];
//        [_audioPlayer stop:YES];
        [_captureTool stopRecode];
        _recodeState = NO;
    
    }
}
-(void)connect{
    RTMP_LogSetLevel(RTMP_LOGDEBUG);
    
//    if(!RTMP_SetupURL(_rtmpSend, "rtmp://192.168.1.2:5920/rtmplive/room")){
//        NSLog(@"RTMP_SetupURL error");
//        _stateLab.text = @"url设置失败";
//        
//        RTMP_Free(_rtmpSend);
//        _rtmpSend=NULL;
//        
//        return;
//    };
//    _stateLab.text = @"连接中";
//    RTMP_EnableWrite(_rtmpSend);
//    if(!RTMP_Connect(_rtmpSend, nil)){
//        NSLog(@"RTMP_Connect error");
//        _stateLab.text = @"连接失败";
//        
//        RTMP_Free(_rtmpSend);
//        _rtmpSend=NULL;
//        
//        return;
//    };
//    _stateLab.text = @"连接流中";
//    
//    if (RTMP_ConnectStream(_rtmpSend,0) == FALSE) {
//        _stateLab.text = @"连接流失败";
//        
//        NSLog(@"RTMP_ConnectStream error");
//        RTMP_Close(_rtmpSend);
//        RTMP_Free(_rtmpSend);
//        _rtmpSend=NULL;
//        return ;
//    }
    
    if (_rtmpSend->Connect(RTMP_TYPE_PUSH)>=0) {
        _stateLab.text = @"连接成功";
    }else{
        _stateLab.text = @"连接失败";
    }
};
-(void)disConnect{
    _rtmpSend->DisConnect();
    _stateLab.text = @"未连接";

}
-(void)updateSpeed{
    _fpsLab.text = [NSString stringWithFormat:@"FPS:%d",_totalCount];;
    _totalCount = 0;
    _ptsLab.text = [NSString stringWithFormat:@"PTS:%.0fkb/s",_totalByte/1024.0];
    _totalByte = 0;
}


-(UIImage *) imageFromPixelBuffer:(CVImageBufferRef) imageBuffer{
    
    @autoreleasepool {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        
        uint8_t* baseAdd = (uint8_t*)CVPixelBufferGetBaseAddress(imageBuffer);
        
        OSType p =CVPixelBufferGetPixelFormatType(imageBuffer);
        char* ty = (char*)&p;
        NSLog(@"ty:%c%c%c%c",ty[3],ty[2],ty[1],ty[0]);
        size_t size = CVPixelBufferGetDataSize(imageBuffer);
        size_t count = CVPixelBufferGetPlaneCount(imageBuffer);
        
        size_t sd = CVPixelBufferGetBytesPerRow(imageBuffer);
        
        size_t pw1 = CVPixelBufferGetWidthOfPlane(imageBuffer, 1);
        size_t ph1 = CVPixelBufferGetHeightOfPlane(imageBuffer, 1);
        
        
        size_t pw = CVPixelBufferGetWidthOfPlane(imageBuffer, 0);
        size_t ph = CVPixelBufferGetHeightOfPlane(imageBuffer, 0);
        
        size_t bytesPerRow0 = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
        size_t bytesPerRow1 = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1);
        
        size_t top,left,right,bottom;
        CVPixelBufferGetExtendedPixels(imageBuffer, &left, &right, &top, &bottom);
        
        uint8_t* planeAdd1 = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
        
        
        uint8_t* planeAdd0 = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
        
        NSLog(@"sd:%ld,add:%ld",planeAdd1-planeAdd0,planeAdd0 - baseAdd);
        
        
        
        
        // Get the number of bytes per row for the plane pixel buffer
        void *baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
        // void* planeAdd0 = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
        
        // Get the number of bytes per row for the plane pixel buffer
        //        size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,0);
        // Get the pixel buffer width and height
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        UIImage *image = [self getImageWithBuffer:planeAdd0 bytesPerRow:bytesPerRow0 width:width height:height];
        
        CVPixelBufferUnlockBaseAddress(imageBuffer,0);
        return (image);
    }
}

-(UIImage*)getImageWithBuffer:(void*)buffer bytesPerRow:(int)bytesPerRow width:(int)width height:(int)height{
    
    // Create a device-dependent gray color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    
    // Create a bitmap graphics context with the sample buffer data
    
    CGContextRef context = CGBitmapContextCreate(buffer, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGImageAlphaNone);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return image;
}
#pragma mark ---delegate
-(void)GJCaptureTool:(GJCaptureTool*)captureView recodeVideoYUVData:(CMSampleBufferRef)sampleBuffer{

//        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//        CVPixelBufferLockBaseAddress(imageBuffer, 0);
//        uint8_t* baseAdd = (uint8_t*)CVPixelBufferGetBaseAddress(imageBuffer);
//        size_t w = CVPixelBufferGetWidth(imageBuffer);
//        size_t h = CVPixelBufferGetHeight(imageBuffer);
//        OSType p =CVPixelBufferGetPixelFormatType(imageBuffer);
//        char* ty = (char*)&p;
//        NSLog(@"ty:%c%c%c%c",ty[3],ty[2],ty[1],ty[0]);
//        size_t q = CVPixelBufferGetDataSize(imageBuffer);
//        size_t s = CVPixelBufferGetPlaneCount(imageBuffer);
//        size_t sd = CVPixelBufferGetBytesPerRow(imageBuffer);
//        size_t sds1 = CVPixelBufferGetWidthOfPlane(imageBuffer, 1);
//        size_t ds1 = CVPixelBufferGetHeightOfPlane(imageBuffer, 1);
//        void* planeAdd1 = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
//        
//        size_t sds0 = CVPixelBufferGetWidthOfPlane(imageBuffer, 0);
//        size_t ds0 = CVPixelBufferGetHeightOfPlane(imageBuffer, 0);
//        uint8_t* planeAdd0 = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
////        NSLog(@"sd:%ld,add:%ld",planeAdd1-planeAdd0,planeAdd0 - baseAdd);
//        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
//        long d = planeAdd0 - baseAdd;
//
//        
//        
////         convert the image
//
//        
//
//        
//    [_playView displayYUV420pData:(void*)(baseAdd + d) width:(uint32_t)w height:(uint32_t)h];

  
//    [_gjEncoder encodeSampleBuffer:sampleBuffer fourceKey:NO];
    
    
            if (_encoder == nil) {
                CVImageBufferRef imgRef = CMSampleBufferGetImageBuffer(sampleBuffer);
                int w = (int)CVPixelBufferGetWidth(imgRef);
                int h = (int)CVPixelBufferGetHeight(imgRef);
                _encoder = [[H264Encoder alloc]initWithWidth:w height:h];
                _encoder.delegate = self;
            }
            [_encoder encoderData:sampleBuffer];
    
}
-(void)GJCaptureTool:(GJCaptureTool*)captureView recodeAudioPCMData:(CMSampleBufferRef)sampleBuffer{
    
    [_audioEncoder encodeWithBuffer:sampleBuffer];

//    
//    if (_audioPlayer == nil) {
//        
//        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
//        const AudioStreamBasicDescription* base = CMAudioFormatDescriptionGetStreamBasicDescription(format);
//        AudioFormatID formtID = base->mFormatID;
//        char* codeChar = (char*)&(formtID);
//        NSLog(@"GJAudioQueueRecoder format：%c%c%c%c ",codeChar[3],codeChar[2],codeChar[1],codeChar[0]);
//        _audioPlayer = [[GJAudioQueuePlayer alloc]initWithFormat:*base bufferSize:4000 macgicCookie:nil];
//        [_audioPlayer start];
//    }
//    
//    AudioBufferList bufferOut;
//    CMBlockBufferRef bufferRetain;
//    size_t size;
//    AudioStreamPacketDescription packet;
//    memset(&packet, 0, sizeof(AudioStreamPacketDescription));
//    OSStatus status = CMSampleBufferGetAudioStreamPacketDescriptions(sampleBuffer, sizeof(AudioStreamPacketDescription), &packet, &size);
//    assert(!status);
//    status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, &size, &bufferOut, sizeof(AudioBufferList), NULL, NULL, 0, &bufferRetain);
//    assert(!status);
//    [_audioPlayer playData:bufferOut.mBuffers[0].mData lenth:bufferOut.mBuffers[0].mDataByteSize packetCount:1 packetDescriptions:NULL isEof:NO];
//    CFRelease(bufferRetain);
}
#define RTMP_HEAD_SIZE   (sizeof(RTMPPacket)+RTMP_MAX_HEADER_SIZE)
-(void) sendH264Packet:(unsigned char *)data size:(unsigned int) size key:(int) bIsKeyFrame time:(unsigned int )nTimeStamp
{
//    if(data == NULL && size<11)
//    {
//        return ;
//    }
//    
//    unsigned char *body = (unsigned char*)malloc(size+9);
//    memset(body,0,size+9);
//    
//    int i = 0;
//    if(bIsKeyFrame)
//    {
//        body[i++] = 0x17;// 1:Iframe  7:AVC
//
//    }
//    else
//    {
//        body[i++] = 0x27;// 2:Pframe  7:AVC
//
//    }
//    
//    body[i++] = 0x01;// AVC NALU
//    body[i++] = 0x00;
//    body[i++] = 0x00;
//    body[i++] = 0x00;
//    
//    body[i++] = size>>24;
//    body[i++] = size>>16;
//    body[i++] = size>>8;
//    body[i++] = size&0xff;;
//    memcpy(&body[i],data,size);
//    
//    [self SendPacket:RTMP_PACKET_TYPE_VIDEO body:body size:i+size-12 time:nTimeStamp];
//    
//    free(body);
    
}
-(void) SendPacket:(int) type body:(char*)body size:(int) size time:(int) time{
//    RTMPPacket * packet = (RTMPPacket*)malloc(sizeof(RTMPPacket));
//    RTMPPacket_Alloc(packet,size);
//    RTMPPacket_Reset(packet);
//    /*分配包内存和初始化,len为包体长度*/
//    
//    /*包体内存*/
//    memcpy(packet->m_body,body,size);
//    packet->m_nBodySize = size;
//    
//    /*
//     * 此处省略包体填充
//     */
//    packet->m_hasAbsTimestamp = 0;
//    packet->m_packetType = RTMP_PACKET_TYPE_VIDEO; /*此处为类型有两种一种是音频,一种是视频*/
//    packet->m_nInfoField2 = _rtmpSend->m_stream_id;
//    packet->m_nChannel = 0x04;
//    packet->m_headerType = RTMP_PACKET_SIZE_LARGE;
//    NSDate * current  = [NSDate date];
//    packet->m_nTimeStamp = [current timeIntervalSinceDate:_beginDate]*1000;
//    
//    /*发送*/
//    if (RTMP_IsConnected(_rtmpSend)) {
//        int ret = RTMP_SendPacket(_rtmpSend,packet,false); /*TRUE为放进发送队列,FALSE是不放进发送队列,直接发送*/
//        NSLog(@"RTMP_SendPacket :%d",ret);
//    }
//    
//    /*释放内存*/
//    free(packet);

}
-(void)GJH264Encoder:(GJH264Encoder *)encoder encodeCompleteBuffer:(uint8_t *)buffer withLenth:(long)totalLenth keyFrame:(BOOL)keyFrame dts:(int64_t)dts{
    GJData* bufData = (GJData*)malloc(sizeof(GJData));
    bufData->data = malloc(totalLenth);
    bufData->size = totalLenth;
    memcpy(bufData->data, buffer, totalLenth);
    queuePush(_mp4VideoQueue, bufData, 2000);
    //    if (_decode == nil) {
    //        _decode = [[H264Decoder alloc]initWithWidth:encoder.width height:encoder.height];
    //        _decode.decoderDelegate = self;
    //    }
    //    [_decode decodeData:data lenth:size];
    

    
    _totalCount ++;
    _totalByte += totalLenth;
//    if (!_rtmpSend->GetConnectedFlag()) {
//        dispatch_async(dispatch_get_main_queue(), ^{
//            _stateLab.text = @"连接中。。。";
//            
//            if (_rtmpSend->Connect(RTMP_TYPE_PUSH)>=0) {
//                _stateLab.text = @"连接成功";
//            }else{
//                _stateLab.text = @"连接失败";
//            }
//        });
//      
//        return;
//    }
//    if (keyFrame) {
//        unsigned char * spsppsData = (unsigned char *)encoder.parameterSet.bytes;
//        size_t spsSize = (size_t)spsppsData[0];
//        size_t ppsSize = (size_t)spsppsData[4+ spsSize];
//
//        _rtmpSend->SendVideoSpsPps(spsppsData+8+spsSize, ppsSize, spsppsData+4, spsSize,dts);
//    }
//        NSData* data = [NSData dataWithBytes:buffer length:30];
//    
//        NSLog(@"SendVideoRawData:%@,\nlenth:%lu  dts:%lld",data,totalLenth,dts);
//    _rtmpSend->SendH264Packet(buffer, totalLenth, keyFrame,dts);
    
//    if (keyFrame) {
//        unsigned char * spsppsData = (unsigned char *)encoder.parameterSet.bytes;
//        size_t spsSize = (size_t)spsppsData[0];
//        size_t ppsSize = (size_t)spsppsData[4+ spsSize];
//        _rtmpSend->SendVideoSpsPps(&spsppsData[8+ spsSize], ppsSize,&spsppsData[4], spsSize);
//        NSLog(@"SendH264Packet   spspps:%ld",spsSize+ ppsSize);
//    }
//    _rtmpSend->SendH264Packet(buffer, (unsigned int)totalLenth, keyFrame, [[NSDate date]timeIntervalSinceDate:_beginDate]);
//    NSLog(@"SendH264Packet   packetsize:%ld",totalLenth);
    
//[self sendH264Packet:(unsigned char *)encoder.parameterSet.bytes size:(unsigned  int)encoder.parameterSet.length key:keyFrame time:[[NSDate date]timeIntervalSinceDate:_beginDate]];
//
    
    //
//    if (_decode == nil) {
//        _decode = [[H264Decoder alloc]initWithWidth:encoder.currentWidth height:encoder.currentHeight];
//        _decode.decoderDelegate = self;
//    }
//    [_decode decodeData:buffer lenth:(int)totalLenth];
    NSData* buff = [NSData dataWithBytes:buffer length:100];
    NSLog(@"buffer:%@",buff);
    if (keyFrame) {
        unsigned char * spsppsData = (unsigned char*)malloc(encoder.parameterSet.length);
        memcpy(spsppsData, (unsigned char *)encoder.parameterSet.bytes, encoder.parameterSet.length);
        size_t spsSize = (size_t)spsppsData[0];
        size_t ppsSize = (size_t)spsppsData[4+ spsSize];
        memcpy(spsppsData, "\x00\x00\x00\x01", 4);
        memcpy(spsppsData+4+spsSize, "\x00\x00\x00\x01", 4);
        NSData* spspps = [NSData dataWithBytes:spsppsData length:encoder.parameterSet.length];
        NSLog(@"spspps:%@",spspps);
        [_gjDecoder decodeBuffer:(uint8_t*)spsppsData withLenth:(uint32_t)encoder.parameterSet.length];

        free(spsppsData);
    }

//    printf("fram type:%x,",buffer[4]);
    [_gjDecoder decodeBuffer:buffer withLenth:(uint32_t)totalLenth];
}

-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(uint)pts{
//    CVPixelBufferLockBaseAddress(imageBuffer, 0);
//    uint8_t* baseAdd = (uint8_t*)CVPixelBufferGetBaseAddress(imageBuffer);
//    size_t w = CVPixelBufferGetWidth(imageBuffer);
//    size_t h = CVPixelBufferGetHeight(imageBuffer);
//    OSType p =CVPixelBufferGetPixelFormatType(imageBuffer);
//    char* ty = (char*)&p;
//    NSLog(@"ty:%c%c%c%c",ty[3],ty[2],ty[1],ty[0]);
//    size_t q = CVPixelBufferGetDataSize(imageBuffer);
//    size_t s = CVPixelBufferGetPlaneCount(imageBuffer);
//    size_t sd = CVPixelBufferGetBytesPerRow(imageBuffer);
//    size_t sds1 = CVPixelBufferGetWidthOfPlane(imageBuffer, 1);
//    size_t ds1 = CVPixelBufferGetHeightOfPlane(imageBuffer, 1);
//    uint8_t* planeAdd1 = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
//    size_t sds12 = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1);
//    size_t sds120 = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
//
//    size_t sds0 = CVPixelBufferGetWidthOfPlane(imageBuffer, 0);
//    size_t ds0 = CVPixelBufferGetHeightOfPlane(imageBuffer, 0);
//    uint8_t* planeAdd0 = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
//    NSLog(@"sd:%ld,add:%ld",planeAdd1-planeAdd0,planeAdd0 - baseAdd);
//    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
//    long d = planeAdd0 - baseAdd;
//
//    static uint8_t* cacheData;
//    if (cacheData == NULL) {
//        cacheData = (uint8_t*)malloc(sds1*ds1 + sds0*ds0);
//    }
//    memcpy(cacheData, planeAdd0, sds0*ds0);
//    memcpy(cacheData+sds0*ds0, planeAdd1, sds1*ds1);
//
    UIImage* image = [self imageFromPixelBuffer:imageBuffer];
    // Update the display with the captured image for DEBUG purposes
    dispatch_async(dispatch_get_main_queue(), ^{
        
        self.imageView.image = image;
    });
    
    
//    _totalCount ++;
//    _totalByte += w*h*1.5;
//    [_playView displayYUV420pData:cacheData width:(uint32_t)w height:(uint32_t)h];
    
}

-(void)H264Encoder:(H264Encoder *)encoder h264:(uint8_t *)data size:(int)size pts:(int64_t)pts dts:(int64_t)dts{
    GJData* bufData = (GJData*)malloc(sizeof(GJData));
    bufData->data = malloc(size);
    bufData->size = size;
    memcpy(bufData->data, data, size);
    queuePush(_mp4VideoQueue, bufData, 2000);
    static int64_t preDts,prePts;
    printf("dts:%lld pts:%lld\n",preDts - dts,prePts - pts);
    prePts = pts; preDts = dts;

//    if (_decode == nil) {
//        _decode = [[H264Decoder alloc]initWithWidth:encoder.width height:encoder.height];
//        _decode.decoderDelegate = self;
//    }
//    [_decode decodeData:data lenth:size];

//    uint8_t* datab = (uint8_t*)data;
//    NSData* d = [NSData dataWithBytes:datab length:100];
//    NSLog(@"data:%@",d );
//    while (datab<_videoPacket->data+_videoPacket->size) {
//        if (datab[0] == 0 && datab[1] == 0 && datab[2] == 1 && datab[3] == 0x65) {
//            datab--;
//            datab[0]=0;
//            break;
//        }
//        printf("%02x",*datab++);
//    }
//    sour = (uint8_t*)data;
//    while (sour+4 < data+size && !(sour[0]!=0 && sour[1]==0 && sour[2]==0 && sour[3]==1)) {
//        sour++;
//    }
//    if (sour+4 < data+size) {
//        sour[5] += sour[4]<<4;
//        sour[4] = 1;
//        sour[3] = 0;
//    }

//    d = [NSData dataWithBytes:sour length:100];
//    NSLog(@"data2:%@",d );
    
//        [_gjDecoder decodeBuffer:data withLenth:size];

    
//    ///rtmpsendh264
//    if (_rtmpSend == nil) {
//        _rtmpSend = [[RtmpSendH264 alloc]initWithOutUrl:@"rtmp://192.168.1.103:1935/myapp/room"];
//        _rtmpSend.width = encoder.width;
//        _rtmpSend.height = encoder.height;
//        _rtmpSend.videoExtradata = encoder.extendata;
//    }
//    [_rtmpSend sendH264Buffer:data lengh:size pts:pts dts:dts eof:NO];
    
//    if (keyFrame) {
//                unsigned char * spsppsData = (unsigned char*)malloc(encoder.parameterSet.length);
//                memcpy(spsppsData, (unsigned char *)encoder.parameterSet.bytes, encoder.parameterSet.length);
//                size_t spsSize = (size_t)spsppsData[0];
//                size_t ppsSize = (size_t)spsppsData[4+ spsSize];
//                memcpy(spsppsData, "\x00\x00\x00\x01", 4);
//                memcpy(spsppsData+4+spsSize, "\x00\x00\x00\x01", 4);
//                [_gjDecoder decodeBuffer:(uint8_t*)spsppsData withLenth:(uint32_t)encoder.parameterSet.length];
//                free(spsppsData);
//            }
//            printf("fram type:%x,",buffer[4]);
//            [_gjDecoder decodeBuffer:buffer withLenth:(uint32_t)totalLenth];
    
}
-(void)H264Decoder:(H264Decoder *)decoder GetYUV:(char *)data size:(int)size width:(float)width height:(float)height{
    //    [_openglView displayYUV420pData:(void*)(data) width:(uint32_t)width height:(uint32_t)height];
    @autoreleasepool {
        UIImage* image = [self getImageWithBuffer:data bytesPerRow:width width:width height:height];
        //     Update the display with the captured image for DEBUG purposes
        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageView.image = image;
        });

    }
}
-(void)pcmDecode:(PCMDecodeFromAAC *)decoder completeBuffer:(void *)buffer lenth:(int)lenth{
    if (_audioPlayer == nil) {
        _audioPlayer = [[GJAudioQueuePlayer alloc]initWithFormat:decoder.destFormatDescription bufferSize:decoder.destMaxOutSize macgicCookie:nil];
    }
    NSLog(@"PCMDecodeFromAAC:%d",lenth);
    [_audioPlayer playData:buffer lenth:lenth packetCount:0 packetDescriptions:NULL isEof:NO];
}
static int aacFramePerS;
static int aacIndex;

-(void)AACEncoderFromPCM:(AACEncoderFromPCM *)encoder encodeCompleteBuffer:(uint8_t *)buffer Lenth:(long)totalLenth packetCount:(int)count packets:(AudioStreamPacketDescription *)packets{
    aacIndex++;
//    if (aacFramePerS == 0) {
//        aacFramePerS = encoder.destFormatDescription.mSampleRate;
//        _rtmpSend.audioStreamFormat = encoder.destFormatDescription;
//    }
//
//    [_rtmpSend sendAACBuffer:buffer lenth:(int)totalLenth pts:aacIndex/aacFramePerS dts:aacIndex eof:NO];
    
//    if (_audioPlayer == nil) {
//        _audioPlayer = [[GJAudioQueuePlayer alloc]initWithFormat:encoder.destFormatDescription bufferSize:encoder.destMaxOutSize macgicCookie:[encoder fetchMagicCookie]];
//    }
////    NSLog(@"PCMDecodeFromAAC:%d",lenth);
//        [_audioPlayer playData:buffer lenth:(UInt32)totalLenth packetCount:count packetDescriptions:packets isEof:NO];

//    [_praseStream parseData:buffer lenth:(int)totalLenth error:nil];
    NSLog(@"AACEncoderFromPCM:count:%d  lenth:%ld",count,totalLenth);
    GJData* bufData = (GJData*)malloc(sizeof(GJData));
    bufData->data = malloc(totalLenth);
    bufData->size = totalLenth;
    memcpy(bufData->data, buffer, totalLenth);
    queuePush(_mp4AudioQueue, bufData, 2000);
    

    
//    [_audioDecoder decodeBuffer:buffer numberOfBytes:(UInt32)totalLenth numberOfPackets:count packetDescriptions:packets];

}
- (void)audioFileStream:(AudioPraseStream *)audioFileStream audioData:(const void *)audioData numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins{
    for (int i = 0; i<numberOfPackets; i++) {
//        [_audioDecoder decodeBuffer:(uint8_t*)audioData numberOfBytes:numberOfBytes numberOfPackets:numberOfPackets packetDescriptions:packetDescriptioins];
    }
//    NSLog(@"audioFileStream:%d",numberOfPackets);
    NSLog(@"audioFileStream count:%d  lenth:%d",numberOfPackets,numberOfBytes);
}
-(void)GJCaptureTool:(GJCaptureTool*)captureTool didRecodeFile:(NSURL*)fileUrl{
    NSFileManager* manager = [NSFileManager defaultManager];
    NSDictionary * dic = [manager attributesOfItemAtPath:[fileUrl path] error:nil];
    NSLog(@"url:%@    ..%@",[fileUrl path],dic);
    
    _player = [[MPMoviePlayerViewController alloc]initWithContentURL:fileUrl];
    [self presentMoviePlayerViewControllerAnimated:_player];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
static int read_packet(void *opaque, uint8_t *buf, int buf_size){
    GJQueue* q = (GJQueue*)opaque;
    GJData* popValue=NULL;
    int readSize = 0;
    static int readIndex = 0;
    while (readSize == 0 && _recodeState) {
        if( queuePeekTopOutValue(q, (void**)&popValue,1000) >= 0){
            if (popValue->size<= readIndex) {
                readIndex = 0;
                queuePop(q, (void**)&popValue, 1000);
                free(popValue->data);
                free(popValue);
            }else{
                if(buf_size - readSize <= popValue->size - readIndex){
                    int size = buf_size - readSize;
                    memcpy(buf+readSize, (uint8_t*)popValue->data+readIndex, size);
                    readSize += size;
                    readIndex += size;
                }else{
                    int size = (int)popValue->size - readIndex;
                    memcpy(buf+readSize, (uint8_t*)popValue->data+readIndex, size);
                    readSize += size;
                    readIndex += size;
                }
            }
        };
    }

    return readSize;
}
AVFormatContext* pMp4OFormat = NULL;

int vdts,adts;


-(BOOL)mp4RecodeInit{
    av_register_all();
    NSString* path = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
    path = [path stringByAppendingPathComponent:@"outfmtfile.mp4"];
    avformat_alloc_output_context2(&pMp4OFormat, NULL, NULL, path.UTF8String);
    if (!pMp4OFormat) {
        printf( "Could not create output context\n");
        return -4;
    }
    if( [self initWriteMp4Video]<0){
        return -1;
    };
    if( [self initWriteMp4Audio]<0){
        return -1;
    };
    
    //Output information------------------
    av_dump_format(pMp4OFormat, 0, path.UTF8String, 1);

    //Open output file
    
    if (!(pMp4OFormat->flags & AVFMT_NOFILE)) {
        int ret = avio_open(&pMp4OFormat->pb, path.UTF8String, AVIO_FLAG_WRITE);
        if (ret < 0) {
            printf( "Could not open output file '%s'", path.UTF8String);
            return -7;
        }
    }
    
    //Write file header
    if (avformat_write_header(pMp4OFormat, NULL) < 0) {
        printf( "Error occurred when opening output file\n");
        return -8;
    }
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (_recodeState) {
            if (queueGetLength(_mp4VideoQueue)*2 > queueGetLength(_mp4AudioQueue)) {
                [self writeVideo];
            }else{
                [self writeAudio];
            }
        }
        int ret = av_write_trailer(pMp4OFormat);
        NSLog(@"av_write_trailer:%d",ret);
    });
    return YES;
}
-(BOOL)initWriteMp4Audio{
   
    int ret;
    AVIOContext* pb = NULL;
    AVInputFormat* piFmt = NULL;
    pMp4AFormat = avformat_alloc_context();
    pMp4AFormat->max_analyze_duration = 1000;
    pMp4AFormat->flags = AVFMT_NOFILE;
    unsigned char* m_bufAvalloc;

    m_bufAvalloc = (unsigned char*)av_malloc(32768);
    pb = avio_alloc_context(m_bufAvalloc, 32768, 0, _mp4AudioQueue,read_packet, NULL, NULL);
    
    if (av_probe_input_buffer(pb, &piFmt, "", NULL, 0, 0) < 0)
        return -1;
    else{
        printf("format:%s[%s]\n", piFmt->name, piFmt->long_name);
    }
    
    pMp4AFormat->pb = pb;
    
    //Input
    if (avformat_open_input(&pMp4AFormat, "", piFmt, NULL) != 0){//iformat，priv_data赋值，pb, nbstreams,streams为null
        printf("Couldn't open input stream.（无法打开输入流）\n");
        return -2;
    }
    pMp4AFormat->streams[0]->time_base =  av_make_q(1,1000);
//    av_format_set_video_codec(pMp4IFormat, avcodec_find_decoder(AV_CODEC_ID_H264));
//    av_format_set_audio_codec(pMp4IFormat, avcodec_find_decoder(AV_CODEC_ID_AAC));
    if ((ret = avformat_find_stream_info(pMp4AFormat, 0)) < 0) {
        printf( "Failed to retrieve input stream information");
        return -3;
    }
    //    pMp4OFormat = pMp4Format->oformat;
    for(int i = 0;i<pMp4AFormat->nb_streams;i++) {
        if (pMp4AFormat->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            //Create output AVStream according to input AVStream
            AVStream *in_stream = pMp4AFormat->streams[0];
            AVStream *out_stream = avformat_new_stream(pMp4OFormat, in_stream->codec->codec);
            if (!out_stream) {
                printf( "Failed allocating output stream\n");
                return -5;
            }
            //Copy the settings of AVCodecContext
            if (avcodec_copy_context(out_stream->codec, in_stream->codec) < 0) {
                printf( "Failed to copy context from input to output stream codec context\n");
                return -6;
            }
            out_stream->codec->codec_tag = 0;
            if (pMp4OFormat->oformat->flags & AVFMT_GLOBALHEADER)
            {
                out_stream->codec->flags |= CODEC_FLAG_GLOBAL_HEADER;
            }
            out_stream->time_base = in_stream->time_base;
            break;
        }
    }
    
      return TRUE;
}
-(int)initWriteMp4Video{
  
    int ret;
    AVIOContext* pb = NULL;
    AVInputFormat* piFmt = NULL;
    
    pMp4VFormat = avformat_alloc_context();
    pMp4VFormat->max_analyze_duration = 1000;
    pMp4VFormat->flags = AVFMT_NOFILE;
    unsigned char* m_bufAvalloc;

    m_bufAvalloc = (unsigned char*)av_malloc(32768);
    pb = avio_alloc_context(m_bufAvalloc, 32768, 0, _mp4VideoQueue,read_packet, NULL, NULL);
    
    if (av_probe_input_buffer(pb, &piFmt, "", NULL, 0, 0) < 0)
        return -1;
    else{
        printf("format:%s[%s]\n", piFmt->name, piFmt->long_name);
    }
    pMp4VFormat->pb = pb;
    //Input
    if (avformat_open_input(&pMp4VFormat, "", piFmt, NULL) != 0){//iformat，priv_data赋值，pb, nbstreams,streams为null
        printf("Couldn't open input stream.（无法打开输入流）\n");
        return -2;
    }
    pMp4VFormat->streams[0]->time_base = av_make_q(1,1000);
    if ((ret = avformat_find_stream_info(pMp4VFormat, 0)) < 0) {
        printf( "Failed to retrieve input stream information");
        return -3;
    }
    
    //Output
//    pMp4OFormat = pMp4Format->oformat;
    for(int i = 0;i<pMp4VFormat->nb_streams;i++) {
        if (pMp4VFormat->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {        //Create output AVStream according to input AVStream
            AVStream *in_stream = pMp4VFormat->streams[0];
            AVStream *out_stream = avformat_new_stream(pMp4OFormat, in_stream->codec->codec);
            if (!out_stream) {
                printf( "Failed allocating output stream\n");
                return -5;
            }
            if (avcodec_copy_context(out_stream->codec, in_stream->codec) < 0) {
                printf( "Failed to copy context from input to output stream codec context\n");
                return -6;
            }
            out_stream->codec->codec_tag = 0;
            if (pMp4OFormat->oformat->flags & AVFMT_GLOBALHEADER)
            {
                out_stream->codec->flags |= CODEC_FLAG_GLOBAL_HEADER;
            }
            out_stream->time_base = in_stream->time_base;
            break;
        }
    }
    return TRUE;
}
static float audioDts;
-(int)writeAudio{
    AVPacket filter_pkt;
    av_init_packet(&filter_pkt);
    if (av_read_frame(pMp4AFormat, &filter_pkt) >= 0) {
        filter_pkt.dts = audioDts++ *1024 / 44100 * pMp4AFormat->streams[0]->time_base.den / pMp4AFormat->streams[0]->time_base.num;
        filter_pkt.dts = av_rescale_q(filter_pkt.dts, pMp4AFormat->streams[0]->time_base, pMp4OFormat->streams[0]->time_base);
        static AVBSFContext* bsfContext;
        filter_pkt.stream_index = 1;
        AVPacket filtered_packet;
        if (bsfContext == NULL) {
            const AVBitStreamFilter *bsf = av_bsf_get_by_name("aac_adtstoasc");
            av_bsf_alloc(bsf, &bsfContext);
        }
        int ret=0;
        av_init_packet(&filtered_packet);
        if (( ret = av_bsf_send_packet(bsfContext, &filter_pkt)) < 0) {
            av_packet_unref(&filter_pkt);
            return -1;
        }
        if ((ret = av_bsf_receive_packet(bsfContext, &filtered_packet)) < 0)return -1;
        int re = av_interleaved_write_frame(pMp4OFormat, &filtered_packet);
        NSLog(@"write audio:%d",re);
    }

    return 0;
}
static float videoDts;

-(void)writeVideo{
    AVPacket filter_pkt;
    av_init_packet(&filter_pkt);
    if (av_read_frame(pMp4VFormat, &filter_pkt) >= 0) {
        filter_pkt.dts = videoDts++ / FPS * pMp4VFormat->streams[0]->time_base.den / pMp4VFormat->streams[0]->time_base.num;
        filter_pkt.dts = av_rescale_q(filter_pkt.dts, pMp4VFormat->streams[0]->time_base, pMp4OFormat->streams[0]->time_base);
        filter_pkt.stream_index = 0;
        int re = av_interleaved_write_frame(pMp4OFormat, &filter_pkt);
        av_packet_unref(&filter_pkt);
        NSLog(@"write video:%d",re);
    }

}


-(void)dealloc{
    queueRelease(&_mp4VideoQueue);
    queueRelease(&_mp4AudioQueue);
}
@end
