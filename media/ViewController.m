//
//  ViewController.m
//  media
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
@interface ViewController ()<GJCaptureToolDelegate,GJH264DecoderDelegate,GJH264EncoderDelegate,AACEncoderFromPCMDelegate,PCMDecodeFromAACDelegate,AudioStreamPraseDelegate>
{
    GJAudioQueuePlayer* _audioPlayer;
    AudioPraseStream* _praseStream;
    NSTimer* _timer;
    int _totalCount;
    float _totalByte;
    MPMoviePlayerViewController* _player;
}
@property(nonatomic,strong)GJH264Decoder* decoder;
@property(nonatomic,strong)GJH264Encoder* encoder;

@property(nonatomic,strong)PCMDecodeFromAAC* audioDecoder;
@property(nonatomic,strong)AACEncoderFromPCM* audioEncoder;

@property(nonatomic,strong)AudioUnitCapture* audioUnitCapture;
@property(nonatomic,strong)GJCaptureTool* captureTool;


@property (weak, nonatomic) IBOutlet UIView *viewContainer;
@property (weak, nonatomic) IBOutlet UIButton *takeButton;//拍照按钮
@property (weak, nonatomic) IBOutlet OpenGLView20 *playView;    ///播放view
@property (weak, nonatomic) IBOutlet UILabel *fpsLab;
@property (weak, nonatomic) IBOutlet UILabel *ptsLab;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _praseStream = [[AudioPraseStream alloc]initWithFileType:kAudioFileAAC_ADTSType fileSize:0 error:nil];
    _praseStream.delegate = self;
    _captureTool = [[GJCaptureTool alloc]initWithType:GJCaptureTypeAudioStream layer:_viewContainer.layer];
    _captureTool.delegate = self;
    _captureTool.fps = 15;
    _encoder = [[GJH264Encoder alloc]init];
    _decoder = [[GJH264Decoder alloc]init];
    _audioEncoder = [[AACEncoderFromPCM alloc]init];
    _audioEncoder.delegate = self;
    _audioDecoder = [[PCMDecodeFromAAC alloc]init];
    _audioDecoder.delegate = self;
    _decoder.delegate = self;
    _encoder.deleagte = self;
    [self addGenstureRecognizer];
    // Do any additional setup after loading the view, typically from a nib.
}
-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
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
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateSpeed) userInfo:nil repeats:YES];
        [_captureTool startRecodeing];
    }else{
        [_timer invalidate];
        [_captureTool stopRecode];
    }
}
-(void)updateSpeed{
    _fpsLab.text = [NSString stringWithFormat:@"FPS:%d",_totalCount];;
    _totalCount = 0;
    _ptsLab.text = [NSString stringWithFormat:@"PTS:%.0fkb/s",_totalByte/1024.0];
    _totalByte = 0;
}

////屏幕旋转时调整视频预览图层的方向

-(void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection{
    [super traitCollectionDidChange:previousTraitCollection];
//    [self adjustOrientation];
}

-(void)adjustOrientation{
//    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
//    AVCaptureConnection *captureConnection=[_captureTool.captureVideoPreviewLayer connection];
//    captureConnection.videoOrientation = (AVCaptureVideoOrientation)orientation;
//    [_captureTool adjustOrientation];
    
}
//旋转后重新设置大小
-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation{
//    _viewContainer.captureVideoPreviewLayer.frame=self.viewContainer.bounds;
}
/**
 *  添加点按手势，点按时聚焦
 */
-(void)addGenstureRecognizer{
    UITapGestureRecognizer *tapGesture=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapScreen:)];
    [self.viewContainer addGestureRecognizer:tapGesture];
}
-(void)tapScreen:(UITapGestureRecognizer *)tapGesture{
    CGPoint point= [tapGesture locationInView:self.viewContainer];
    //将UI坐标转化为摄像头坐标
    CGPoint cameraPoint= [_captureTool.captureVideoPreviewLayer captureDevicePointOfInterestForPoint:point];
    [_captureTool setFocusCursorWithPoint:point];
    [_captureTool focusWithMode:AVCaptureFocusModeAutoFocus exposureMode:AVCaptureExposureModeAutoExpose atPoint:cameraPoint];
}

#pragma mark ---delegate
-(void)GJCaptureTool:(GJCaptureTool*)captureView recodeVideoYUVData:(CMSampleBufferRef)sampleBuffer{
//    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//    CVPixelBufferLockBaseAddress(imageBuffer, 0);
//    void* baseAdd = CVPixelBufferGetBaseAddress(imageBuffer);
//    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
//    size_t w = CVPixelBufferGetWidth(imageBuffer);
//    size_t h = CVPixelBufferGetHeight(imageBuffer);
//    [_playView displayYUV420pData:baseAdd width:(uint32_t)w height:(uint32_t)h];

    [_encoder encodeSampleBuffer:sampleBuffer];
    
   
}

-(void)GJCaptureTool:(GJCaptureTool*)captureView recodeAudioPCMData:(CMSampleBufferRef)sampleBuffer{
    
    [_audioEncoder encodeWithBuffer:sampleBuffer];

//    
//    if (_audioPlayer == nil) {
//        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
//        const AudioStreamBasicDescription* base = CMAudioFormatDescriptionGetStreamBasicDescription(format);
//        AudioFormatID formtID = base->mFormatID;
//        char* codeChar = (char*)&(formtID);
//        NSLog(@"GJAudioQueueRecoder format：%c%c%c%c ",codeChar[3],codeChar[2],codeChar[1],codeChar[0]);
//        _audioPlayer = [[GJAudioQueuePlayer alloc]initWithFormat:*base bufferSize:4000 macgicCookie:nil];
//    }
//    AudioBufferList bufferOut;
//    CMBlockBufferRef bufferRetain;
//    size_t size;
//    AudioStreamPacketDescription packet;
//    memset(&packet, 0, sizeof(AudioStreamPacketDescription));
//    OSStatus status = CMSampleBufferGetAudioStreamPacketDescriptions(sampleBuffer, sizeof(AudioStreamPacketDescription), &packet, &size);
//    assert(!status);
//    status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, &size, &bufferOut, sizeof(AudioBufferList), NULL, NULL, 0, &bufferRetain);
//    assert(!status);
//    [_audioPlayer playData:bufferOut.mBuffers[0].mData lenth:bufferOut.mBuffers[0].mDataByteSize packetCount:0 packetDescriptions:NULL isEof:NO];
//    CFRelease(bufferRetain);
}
-(void)GJH264Encoder:(GJH264Encoder *)encoder encodeCompleteBuffer:(uint8_t *)buffer withLenth:(long)totalLenth{
    _totalCount ++;
    _totalByte += totalLenth;
    [_decoder decodeBuffer:buffer withLenth:(uint32_t)totalLenth];
}
-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer{
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    void* baseAdd = CVPixelBufferGetBaseAddress(imageBuffer);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    size_t w = CVPixelBufferGetWidth(imageBuffer);
    size_t h = CVPixelBufferGetHeight(imageBuffer);
    
    
    
//    _totalCount ++;
//    _totalByte += w*h*1.5;
    [_playView displayYUV420pData:baseAdd width:(uint32_t)w height:(uint32_t)h];
}
-(void)pcmDecode:(PCMDecodeFromAAC *)decoder completeBuffer:(void *)buffer lenth:(int)lenth{
    if (_audioPlayer == nil) {
        _audioPlayer = [[GJAudioQueuePlayer alloc]initWithFormat:decoder.destFormatDescription bufferSize:decoder.destMaxOutSize macgicCookie:nil];
    }
    NSLog(@"PCMDecodeFromAAC:%d",lenth);
    [_audioPlayer playData:buffer lenth:lenth packetCount:0 packetDescriptions:NULL isEof:NO];
}
-(void)AACEncoderFromPCM:(AACEncoderFromPCM *)encoder encodeCompleteBuffer:(uint8_t *)buffer Lenth:(long)totalLenth packetCount:(int)count packets:(AudioStreamPacketDescription *)packets{
    [_praseStream parseData:buffer lenth:(int)totalLenth error:nil];
    NSLog(@"AACEncoderFromPCM:count:%d  lenth:%ld",count,totalLenth);
//    [_audioDecoder decodeBuffer:buffer withLenth:(uint32_t)totalLenth];

}
- (void)audioFileStream:(AudioPraseStream *)audioFileStream audioData:(const void *)audioData numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins{
    for (int i = 0; i<numberOfPackets; i++) {
        [_audioDecoder decodeBuffer:(uint8_t*)audioData numberOfBytes:numberOfBytes numberOfPackets:numberOfPackets packetDescriptions:packetDescriptioins];
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
