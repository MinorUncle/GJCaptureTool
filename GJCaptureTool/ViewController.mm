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
#import "GJBufferPool.h"
#import "GJFormats.h"
#import "LibRtmpSession.hpp"
#import "rtmp/log.h"
#import "GJAudioQueueRecoder.h"
extern "C"{
#import "avformat.h"
#import "swscale.h"
}

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
    int fps = 28;
    _captureTool = [[GJCaptureTool alloc]initWithType:GJCaptureType(GJCaptureTypeVideoStream|GJCaptureTypeAudioStream) fps:fps layer:_viewContainer.layer];
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
        [_audioPlayer start];

    }else{
        [_timer invalidate];
        [_audioPlayer stop:YES];
        [_captureTool stopRecode];
    
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
    return;
    
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
//    if (_decode == nil) {
//        _decode = [[H264Decoder alloc]initWithWidth:encoder.width height:encoder.height];
//        _decode.decoderDelegate = self;
//    }
//    [_decode decodeData:data lenth:size];
    
    uint8_t* datab = (uint8_t*)data;
    NSData* d = [NSData dataWithBytes:datab length:100];
    NSLog(@"data:%@",d );
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
    
        [_gjDecoder decodeBuffer:data withLenth:size];

    
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


//-(void)initWriteMp4{
//    av_register_all();
//
//}
//-(void)writeMp4:(uint8_t*)data size:(int)size{
//    
//    
//    
//    AVFormatContext* pFormat = NULL;
//    if (avformat_open_input(&pFormat, SRC_FILE, NULL, NULL) < 0)
//    {
//        return 0;
//    }
//    AVCodecContext* video_dec_ctx = NULL;
//    AVCodec* video_dec = NULL;
//    if (avformat_find_stream_info(pFormat, NULL) < 0)
//    {
//        return 0;
//    }
//    av_dump_format(pFormat, 0, SRC_FILE, 0);
//    video_dec_ctx = pFormat->streams[0]->codec;
//    video_dec = avcodec_find_decoder(video_dec_ctx->codec_id);
//    if (avcodec_open2(video_dec_ctx, video_dec, NULL) < 0)
//    {
//        return 0;
//    }
//    
//    AVFormatContext* pOFormat = NULL;
//    AVOutputFormat* ofmt = NULL;
//    if (avformat_alloc_output_context2(&pOFormat, NULL, NULL, OUT_FILE) < 0)
//    {
//        return 0;
//    }
//    ofmt = pOFormat->oformat;
//    if (avio_open(&(pOFormat->pb), OUT_FILE, AVIO_FLAG_READ_WRITE) < 0)
//    {
//        return 0;
//    }
//    AVCodecContext *video_enc_ctx = NULL;
//    AVCodec *video_enc = NULL;
//    video_enc = avcodec_find_encoder(AV_CODEC_ID_H264);
//    AVStream *video_st = avformat_new_stream(pOFormat, video_enc);
//    if (!video_st)
//        return 0;
//    video_enc_ctx = video_st->codec;
//    video_enc_ctx->width = video_dec_ctx->width;
//    video_enc_ctx->height = video_dec_ctx->height;
//    video_enc_ctx->pix_fmt = PIX_FMT_YUV420P;
//    video_enc_ctx->time_base.num = 1;
//    video_enc_ctx->time_base.den = 25;
//    video_enc_ctx->bit_rate = video_dec_ctx->bit_rate;
//    video_enc_ctx->gop_size = 250;
//    video_enc_ctx->max_b_frames = 10;
//    //H264
//    //pCodecCtx->me_range = 16;
//    //pCodecCtx->max_qdiff = 4;
//    video_enc_ctx->qmin = 10;
//    video_enc_ctx->qmax = 51;
//    if (avcodec_open2(video_enc_ctx, video_enc, NULL) < 0)
//    {
//        printf("编码器打开失败！\n");
//        return 0;
//    }
//    printf("Output264video Information====================\n");
//    av_dump_format(pOFormat, 0, OUT_FILE, 1);
//    printf("Output264video Information====================\n");
//    
//    //mp4 file
//    AVFormatContext* pMp4Format = NULL;
//    AVOutputFormat* pMp4OFormat = NULL;
//    if (avformat_alloc_output_context2(&pMp4Format, NULL, NULL, OUT_FMT_FILE) < 0)
//    {
//        return 0;
//    }
//    pMp4OFormat = pMp4Format->oformat;
//    if (avio_open(&(pMp4Format->pb), OUT_FMT_FILE, AVIO_FLAG_READ_WRITE) < 0)
//    {
//        return 0;
//    }
//    
//    for (int i = 0; i < pFormat->nb_streams; i++) {
//        AVStream *in_stream = pFormat->streams[i];
//        AVStream *out_stream = avformat_new_stream(pMp4Format, in_stream->codec->codec);
//        if (!out_stream) {
//            return 0;
//        }
//        int ret = 0;
//        ret = avcodec_copy_context(out_stream->codec, in_stream->codec);
//        if (ret < 0) {
//            fprintf(stderr, "Failed to copy context from input to output stream codec context\n");
//            return 0;
//        }
//        out_stream->codec->codec_tag = 0;
//        if (pMp4Format->oformat->flags & AVFMT_GLOBALHEADER)
//            out_stream->codec->flags |= CODEC_FLAG_GLOBAL_HEADER;
//    }
//    
//    
//    av_dump_format(pMp4Format, 0, OUT_FMT_FILE, 1);
//    
//    if (avformat_write_header(pMp4Format, NULL) < 0)
//    {
//        return 0;
//    }
//    
//    
//    ////
//    
//    
//    
//    av_opt_set(video_enc_ctx->priv_data, "preset", "superfast", 0);
//    av_opt_set(video_enc_ctx->priv_data, "tune", "zerolatency", 0);
//    avformat_write_header(pOFormat, NULL);
//    AVPacket *pkt = new AVPacket();
//    av_init_packet(pkt);
//    AVFrame *pFrame = avcodec_alloc_frame();
//    int ts = 0;
//    while (1)
//    {
//        if (av_read_frame(pFormat, pkt) < 0)
//        {
//            avio_close(pOFormat->pb);
//            av_write_trailer(pMp4Format);
//            avio_close(pMp4Format->pb);
//            delete pkt;
//            return 0;
//        }
//        if (pkt->stream_index == 0)
//        {
//            
//            int got_picture = 0, ret = 0;
//            ret = avcodec_decode_video2(video_dec_ctx, pFrame, &got_picture, pkt);
//            if (ret < 0)
//            {
//                delete pkt;
//                return 0;
//            }
//            pFrame->pts = pFrame->pkt_pts;//ts++;
//            if (got_picture)
//            {
//                AVPacket *tmppkt = new AVPacket;
//                av_init_packet(tmppkt);
//                int size = video_enc_ctx->width*video_enc_ctx->height * 3 / 2;
//                char* buf = new char[size];
//                memset(buf, 0, size);
//                tmppkt->data = (uint8_t*)buf;
//                tmppkt->size = size;
//                ret = avcodec_encode_video2(video_enc_ctx, tmppkt, pFrame, &got_picture);
//                if (ret < 0)
//                {
//                    avio_close(pOFormat->pb);
//                    delete buf;
//                    return 0;
//                }
//                if (got_picture)
//                {
//                    //ret = av_interleaved_write_frame(pOFormat, tmppkt);
//                    AVStream *in_stream = pFormat->streams[pkt->stream_index];
//                    AVStream *out_stream = pMp4Format->streams[pkt->stream_index];
//                    
//                    tmppkt->pts = av_rescale_q_rnd(tmppkt->pts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF);
//                    tmppkt->dts = av_rescale_q_rnd(tmppkt->dts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF);
//                    tmppkt->duration = av_rescale_q(tmppkt->duration, in_stream->time_base, out_stream->time_base);
//                    tmppkt->pos = -1;
//                    ret = av_interleaved_write_frame(pMp4Format, tmppkt);
//                    if (ret < 0)
//                        return 0;
//                    delete tmppkt;
//                    delete buf;
//                }
//            }
//            //avcodec_free_frame(&pFrame);
//        }
//        else if (pkt->stream_index == 1)
//        {
//            AVStream *in_stream = pFormat->streams[pkt->stream_index];
//            AVStream *out_stream = pMp4Format->streams[pkt->stream_index];
//            
//            pkt->pts = av_rescale_q_rnd(pkt->pts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF);
//            pkt->dts = av_rescale_q_rnd(pkt->dts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF);
//            pkt->duration = av_rescale_q(pkt->duration, in_stream->time_base, out_stream->time_base);
//            pkt->pos = -1;
//            if (av_interleaved_write_frame(pMp4Format, pkt) < 0)
//                return 0;
//        }
//    }
//    avcodec_free_frame(&pFrame);
//    return 0;
//}


@end
