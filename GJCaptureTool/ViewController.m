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
#import <MediaPlayer/MediaPlayer.h>
#import "PCMDecodeFromAAC.h"
#import "AACEncoderFromPCM.h"
#import "AudioPraseStream.h"
#import "AudioUnitCapture.h"
#import "H264Decoder.h"
#import "H264Encoder.h"
#import "H264StreamToTS.h"
#import "rtmp.h"
#import "RtmpSendH264.h"
#import "GJFormats.h"
@interface ViewController ()<GJCaptureToolDelegate,GJH264DecoderDelegate,GJH264EncoderDelegate,AACEncoderFromPCMDelegate,PCMDecodeFromAACDelegate,AudioStreamPraseDelegate,H264DecoderDelegate,H264EncoderDelegate>
{
    GJAudioQueuePlayer* _audioPlayer;
    AudioPraseStream* _praseStream;
    RTMP* _rtmpSend;
    BOOL _stop;
    H264StreamToTS* _toTS;
    H264Decoder* _decode;
    H264Encoder* _encoder;
    
    NSTimer* _timer;
    int _totalCount;
    float _totalByte;
    NSDate* _beginDate;
    MPMoviePlayerViewController* _player;
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

- (void)viewDidLoad {
    [super viewDidLoad];
//    _praseStream = [[AudioPraseStream alloc]initWithFileType:kAudioFileAAC_ADTSType fileSize:0 error:nil];
//    _praseStream.delegate = self;
    _captureTool = [[GJCaptureTool alloc]initWithType:GJCaptureTypeVideoStream|GJCaptureTypeAudioStream fps:15 layer:_viewContainer.layer];
    _captureTool.delegate = self;
    _gjEncoder = [[GJH264Encoder alloc]init];
    _gjDecoder = [[GJH264Decoder alloc]init];
    _audioEncoder = [[AACEncoderFromPCM alloc]init];
    _audioEncoder.delegate = self;
    _audioDecoder = [[PCMDecodeFromAAC alloc]init];
    _audioDecoder.delegate = self;
    _gjDecoder.delegate = self;
    _gjEncoder.deleagte = self;
    
    _rtmpSend = RTMP_Alloc();
    RTMP_Init(_rtmpSend);
    // Do any additional setup after loading the view, typically from a nib.
}
-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [self connect];
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
        [_audioPlayer start];

    }else{
        [_timer invalidate];
        [_audioPlayer stop:YES];
        [_captureTool stopRecode];
    
    }
}
-(void)connect{
    
    if(!RTMP_SetupURL(_rtmpSend, "rtmp://192.168.1.102:1935/myapp/room")){
        NSLog(@"RTMP_SetupURL error");
        _stateLab.text = @"连接失败";
        
        RTMP_Free(_rtmpSend);
        _rtmpSend=NULL;
        
        return;
    };
    _stateLab.text = @"连接中";
    RTMP_EnableWrite(_rtmpSend);
    if(!RTMP_Connect(_rtmpSend, nil)){
        NSLog(@"RTMP_Connect error");
        _stateLab.text = @"连接失败";
        
        RTMP_Free(_rtmpSend);
        _rtmpSend=NULL;
        
        return;
    };
    _stateLab.text = @"连接流中";
    
    if (RTMP_ConnectStream(_rtmpSend,0) == FALSE) {
        _stateLab.text = @"连接失败";
        
        NSLog(@"RTMP_ConnectStream error");
        RTMP_Close(_rtmpSend);
        RTMP_Free(_rtmpSend);
        _rtmpSend=NULL;
        return ;
    }
    _stateLab.text = @"连接成功";
};
-(void)disConnect{
    RTMP_Close(_rtmpSend);
    RTMP_Free(_rtmpSend);
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
//        void* baseAdd = CVPixelBufferGetBaseAddress(imageBuffer);
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
//        void* planeAdd0 = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
//        NSLog(@"sd:%ld,add:%ld",planeAdd1-planeAdd0,planeAdd0 - baseAdd);
//        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
//        long d = planeAdd0 - baseAdd;

        
        
//         convert the image

        

        
//    [_playView displayYUV420pData:(void*)(baseAdd + d) width:(uint32_t)w height:(uint32_t)h];

    [_gjEncoder encodeSampleBuffer:sampleBuffer fourceKey:NO];
    
        
//            if (_encoder == nil) {
//                CVImageBufferRef imgRef = CMSampleBufferGetImageBuffer(sampleBuffer);
//                int w = (int)CVPixelBufferGetWidth(imgRef);
//                int h = (int)CVPixelBufferGetHeight(imgRef);
//                _encoder = [[H264Encoder alloc]initWithWidth:w height:h];
//                _encoder.delegate = self;
//            }
//            [_encoder encoderData:sampleBuffer];
    
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
    if(data == NULL && size<11)
    {
        return ;
    }
    
    unsigned char *body = (unsigned char*)malloc(size+9);
    memset(body,0,size+9);
    
    int i = 0;
    if(bIsKeyFrame)
    {
        body[i++] = 0x17;// 1:Iframe  7:AVC
        body[i++] = 0x01;// AVC NALU
        body[i++] = 0x00;
        body[i++] = 0x00;
        body[i++] = 0x00;
        
        memcpy(&body[i],data,size);
    }
    else
    {
        body[i++] = 0x27;// 2:Pframe  7:AVC
        body[i++] = 0x01;// AVC NALU
        body[i++] = 0x00;
        body[i++] = 0x00;
        body[i++] = 0x00;
        memcpy(&body[i],data,size);
    }
    
    [self SendPacket:RTMP_PACKET_TYPE_VIDEO body:body size:i+size time:nTimeStamp];
    
    free(body);
    
}
-(void) SendPacket:(int) type body:(char*)body size:(int) size time:(int) time{
    RTMPPacket * packet;
    
    /*分配包内存和初始化,len为包体长度*/
    packet = (RTMPPacket *)malloc(sizeof(RTMPPacket));
    memset(packet,0,sizeof(RTMPPacket));
    
    /*包体内存*/
    packet->m_body = body;
    packet->m_nBodySize = size;
    
    /*
     * 此处省略包体填充
     */
    packet->m_hasAbsTimestamp = 0;
    packet->m_packetType = RTMP_PACKET_TYPE_VIDEO; /*此处为类型有两种一种是音频,一种是视频*/
    packet->m_nInfoField2 = _rtmpSend->m_stream_id;
    packet->m_nChannel = 0x04;
    packet->m_headerType = RTMP_PACKET_SIZE_LARGE;
    NSDate * current  = [NSDate date];
    packet->m_nTimeStamp = [current timeIntervalSinceDate:_beginDate]*1000;
    
    /*发送*/
    if (RTMP_IsConnected(_rtmpSend)) {
        int ret = RTMP_SendPacket(_rtmpSend,packet,false); /*TRUE为放进发送队列,FALSE是不放进发送队列,直接发送*/
        NSLog(@"RTMP_SendPacket :%d",ret);
    }
    
    /*释放内存*/
    free(packet);

}
-(void)GJH264Encoder:(GJH264Encoder *)encoder encodeCompleteBuffer:(uint8_t *)buffer withLenth:(long)totalLenth keyFrame:(BOOL)keyFrame{
    
    
    _totalCount ++;
    _totalByte += totalLenth;
    
//    if (keyFrame) {
//        [self sendH264Packet:(unsigned char *)encoder.parameterSet.bytes size:(unsigned  int)encoder.parameterSet.length key:keyFrame time:[[NSDate date]timeIntervalSinceDate:_beginDate]];
////    }
//
    
    //
//    if (_decode == nil) {
//        _decode = [[H264Decoder alloc]initWithWidth:encoder.currentWidth height:encoder.currentHeight];
//        _decode.decoderDelegate = self;
//    }
//    [_decode decodeData:buffer lenth:(int)totalLenth];
    if (keyFrame) {
        [_gjDecoder decodeBuffer:(uint8_t*)encoder.parameterSet.bytes withLenth:(uint32_t)encoder.parameterSet.length];
    }
    [_gjDecoder decodeBuffer:buffer withLenth:(uint32_t)totalLenth];
}
-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer{
//    CVPixelBufferLockBaseAddress(imageBuffer, 0);
//    void* baseAdd = CVPixelBufferGetBaseAddress(imageBuffer);
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
//    void* planeAdd1 = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
//    
//    size_t sds0 = CVPixelBufferGetWidthOfPlane(imageBuffer, 0);
//    size_t ds0 = CVPixelBufferGetHeightOfPlane(imageBuffer, 0);
//    void* planeAdd0 = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
//    NSLog(@"sd:%ld,add:%ld",planeAdd1-planeAdd0,planeAdd0 - baseAdd);
//    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
//    long d = planeAdd0 - baseAdd;

    
//
    UIImage* image = [self imageFromPixelBuffer:imageBuffer];
    // Update the display with the captured image for DEBUG purposes
    dispatch_async(dispatch_get_main_queue(), ^{
        
        self.imageView.image = image;
    });
    
    
//    _totalCount ++;
//    _totalByte += w*h*1.5;
//    [_playView displayYUV420pData:baseAdd+d width:(uint32_t)w height:(uint32_t)h];
    
}

-(void)H264Encoder:(H264Encoder *)encoder h264:(uint8_t *)data size:(int)size pts:(int64_t)pts dts:(int64_t)dts{
//    if (_decode == nil) {
//        _decode = [[H264Decoder alloc]initWithWidth:encoder.width height:encoder.height];
//        _decode.decoderDelegate = self;
//    }
//    [_decode decodeData:data lenth:size];
    
//        [_gjDecoder decodeBuffer:data withLenth:size];

    
//    ///rtmpsendh264
//    if (_rtmpSend == nil) {
//        _rtmpSend = [[RtmpSendH264 alloc]initWithOutUrl:@"rtmp://192.168.1.103:1935/myapp/room"];
//        _rtmpSend.width = encoder.width;
//        _rtmpSend.height = encoder.height;
//        _rtmpSend.videoExtradata = encoder.extendata;
//    }
//    [_rtmpSend sendH264Buffer:data lengh:size pts:pts dts:dts eof:NO];
    
    if (_rtmpSend == nil) {
     
        }
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


@end
