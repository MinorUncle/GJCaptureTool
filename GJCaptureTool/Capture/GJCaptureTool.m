//
//  GJCapture.m
//  GJCaptureTool
//
//  Created by tongguan on 16/6/27.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//
#import "GJCaptureTool.h"
#import "GJDebug.h"
//#ifndef DEBUG
//#import <AVFoundation/AVAudioSettings.h>
#import <CoreAudio/CoreAudioTypes.h>

typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);

@interface GJCaptureTool()<AVCaptureFileOutputRecordingDelegate,AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate>
{
//    AACEncoderFromPCM* _audioEncoder;
//    PCMDecodeFromAAC* _audioDecoder;
//    AudioEncoder* _RWAudioEncoder;
//    AACDecoder* _RWAudioDecoder;
}
@property (strong,nonatomic) AVCaptureSession *captureSession;//负责输入和输出设备之间的数据传递
@property(strong,nonatomic)AVCaptureDevice *audioCaptureDevice;   //音频输入设备
@property (strong,nonatomic)AVCaptureDeviceInput *audioCaptureDeviceInput; //音频输入
@property (strong,nonatomic) AVCaptureDeviceInput *videoCaptureDeviceInput;//负责从AVCaptureDevice获得输入数据


@property (strong,nonatomic) AVCaptureConnection *videoConnect;//视频链接
@property (strong,nonatomic) AVCaptureConnection *audioConnect;//音频链接

@property (strong,nonatomic) dispatch_queue_t audioStreamQueue;//音频线程
@property (strong,nonatomic) dispatch_queue_t videoStreamQueue;//视频线程
@property (strong,nonatomic) dispatch_queue_t fileQueue;//音频线程
@property (strong,nonatomic) dispatch_queue_t imageQueue;//视频线程




@property (strong,nonatomic)AVCaptureDevice *captureDevice;//相机拍摄预览图层

//@property (assign,nonatomic) BOOL enableRotation;//是否允许旋转（注意在视频录制过程中禁止屏幕旋转）
@property (assign,nonatomic) CGRect *lastBounds;//旋转的前大小
@property (assign,nonatomic) UIBackgroundTaskIdentifier backgroundTaskIdentifier;//后台任务标识

@property (strong, nonatomic) CALayer *focusCursor; //聚焦光标



@end
@implementation GJCaptureTool
@synthesize captureVideoPreviewLayer = _captureVideoPreviewLayer;
#pragma mark -- initFunction

- (instancetype)initWithType:(GJCaptureType)type fps:(int)fps layer:(CALayer*)layer
{
    self = [super init];
    if (self) {
        _fps = fps;
        _sessionPreset = AVCaptureSessionPreset640x480;
        
        [layer addObserver:self forKeyPath:@"bounds" options:NSKeyValueObservingOptionNew context:nil];
        _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc]init];
        _focusCursor = [[CALayer alloc]init];
        _focusCursor.borderColor = [UIColor orangeColor].CGColor;
        _focusCursor.borderWidth = 1;
        
        [layer addSublayer:_captureVideoPreviewLayer];
        [layer addSublayer:_focusCursor];
        _captureType = type;
        
        [self _initSession];
        [self _initVideoInpute];
        
        if ((_captureType & GJCaptureTypeFile) == GJCaptureTypeFile) {
            [self _initFileVideo];
        }
        if ((_captureType & GJCaptureTypeImage) == GJCaptureTypeImage) {
            [self _initImage];
        }
        if ((_captureType & GJCaptureTypeVideoStream) == GJCaptureTypeVideoStream) {
            [self _initVideo];
        }
        if ((_captureType & GJCaptureTypeAudioStream) == GJCaptureTypeAudioStream) {
            [self _initAudio];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientAtionChange:) name:UIDeviceOrientationDidChangeNotification object:nil];

    }
    return self;
}
-(void)orientAtionChange:(NSNotification*)note{
    NSLog(@"note:%@",note.userInfo);
    [self adjustOrientation];

}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context{
    if ([keyPath isEqualToString:@"bounds"]) {
        CGRect rect = [change[NSKeyValueChangeNewKey] CGRectValue];
        _captureVideoPreviewLayer.frame = rect;
    }
}

-(BOOL)_initSession{
    _captureSession=[[AVCaptureSession alloc]init];

    return YES;
}
-(BOOL)_initFileVideo{
    _captureMovieFileOutput = [[AVCaptureMovieFileOutput alloc]init];
    if ([_captureSession canAddOutput:_captureMovieFileOutput]) {
        [_captureSession addOutput:_captureMovieFileOutput];
        GJQueueLOG(@"添加视频文件输出成功");
    }else{
        return NO;
    }
    _fileQueue = dispatch_queue_create("_fileQueue", DISPATCH_QUEUE_CONCURRENT);
    return YES;

}
-(BOOL)_initImage{
    _captureImageOutput = [[AVCaptureStillImageOutput alloc]init];
    if ([_captureSession canAddOutput:_captureImageOutput]) {
        [_captureSession addOutput:_captureImageOutput];
        GJQueueLOG(@"添加图片输出成功");
    }else{
        GJQueueLOG(@"添加图片输出失败");
        return NO;
    }
    NSDictionary * imageOutputSettings = @{AVVideoCodecKey:AVVideoCodecJPEG};
    _captureImageOutput.outputSettings = imageOutputSettings;
    _imageQueue = dispatch_queue_create("_imageQueue", DISPATCH_QUEUE_CONCURRENT);
    return YES;

}
-(void)setSessionPreset:(NSString *)sessionPreset{
    if ([_captureSession canSetSessionPreset:sessionPreset]) {//设置分辨率
        _captureSession.sessionPreset=sessionPreset;
    }
}
-(BOOL)_initVideoInpute{
    if ([_captureSession canSetSessionPreset:_sessionPreset]) {//设置分辨率
        _captureSession.sessionPreset=_sessionPreset;
    }
    //获得输入设备
    self.captureDevice=[self getCameraDeviceWithPosition:AVCaptureDevicePositionBack];//取得后置摄像头
    if (!self.captureDevice){
        GJQueueLOG(@"获取后置摄像头失败");
        return NO;
    }
    NSError* error;
    //根据输入设备初始化设备输入对象，用于获得输入数据
    _videoCaptureDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:self.captureDevice error:&error];
    if (error) {
        [self echoError:error appendStr:@"取得设备输入对象"];
        return NO;
    }
    //将设备输入添加到会话中
    if ([_captureSession canAddInput:_videoCaptureDeviceInput]) {
        [_captureSession addInput:_videoCaptureDeviceInput];
        GJQueueLOG(@"添加视频输入成功");
    }
    [self.captureVideoPreviewLayer setSession:self.captureSession];
    self.captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect;//填充模式
    [self addNotificationToCaptureDevice:self.captureDevice];

    [self adjustOrientation];
    return YES;
}
-(BOOL)_initVideo{
    
    //初始化设备输出对象，用于获得输出数据

    _captureDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    if ([_captureSession canAddOutput:_captureDataOutput]) {
        [_captureSession addOutput:_captureDataOutput];
        GJQueueLOG(@"添加视频数据输出成功");
    }
    _videoConnect = [_captureDataOutput connectionWithMediaType:AVMediaTypeVideo];
    self.captureDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};

       //链接创建后
    NSError * error;
    if([self.captureDevice lockForConfiguration:&error]){
        self.captureDevice.activeVideoMinFrameDuration = CMTimeMake(1, _fps);
        self.captureDevice.activeVideoMaxFrameDuration = CMTimeMake(1, _fps);
        [self.captureDevice unlockForConfiguration];
    }else{
        GJQueueLOG(@"error:%s", error.localizedDescription.UTF8String);
        return NO;
    }
    _videoStreamQueue = dispatch_queue_create("_videoStreamQueue", DISPATCH_QUEUE_CONCURRENT);
    
    
    return YES;
FAILURE:
    return NO;
}
-(BOOL)_initAudio{
    NSError* error;
    //添加一个音频输入设备
    _audioCaptureDevice=[[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
    if (!_audioCaptureDevice) {
        GJQueueLOG(@"取得设备音频对象时出错");
        return NO;
    }
    _audioCaptureDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:_audioCaptureDevice error:&error];
    if (error) {
        GJQueueLOG(@"取得设备输入对象时出错，错误原因：%s",error.localizedDescription.UTF8String);
        return NO;
    }
    //添加一个音频输出设备
    _captureAudioOutput = [[AVCaptureAudioDataOutput alloc]init];
    if ([_captureSession canAddOutput:_captureAudioOutput]) {
        [_captureSession addOutput:_captureAudioOutput];
        GJQueueLOG(@"添加音频输出成功");
    }
    if ([_captureSession canAddInput:_audioCaptureDeviceInput]) {
        [_captureSession addInput:_audioCaptureDeviceInput];
        GJQueueLOG(@"添加音频输入成功");
    }else{
        GJQueueLOG(@"无法添加音频输入");
    }
    _audioConnect = [_captureAudioOutput connectionWithMediaType:AVMediaTypeAudio];
    return YES;
faile:
    return NO;
}

#pragma mark - 提示

/**
 *  设备连接成功
 *
 *  @param notification 通知对象
 */
-(void)deviceConnected:(NSNotification *)notification{
    GJQueueLOG(@"设备已连接...");
}
/**
 *  设备连接断开
 *
 *  @param notification 通知对象
 */
-(void)deviceDisconnected:(NSNotification *)notification{
    NSLog(@"设备已断开.");
}
/**
 *  捕获区域改变
 *
 *  @param notification 通知对象
 */
-(void)areaChange:(NSNotification *)notification{
    NSLog(@"捕获区域改变...");
}

/**
 *  会话出错
 *
 *  @param notification 通知对象
 */
-(void)sessionRuntimeError:(NSNotification *)notification{
    NSLog(@"会话发生错误.");
}

#pragma mark - 私有方法

/**
 *  取得指定位置的摄像头
 *
 *  @param position 摄像头位置
 *
 *  @return 摄像头设备
 */
-(AVCaptureDevice *)getCameraDeviceWithPosition:(AVCaptureDevicePosition )position{
    NSArray *cameras= [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *camera in cameras) {
        if ([camera position]==position) {
            return camera;
        }
    }
    return nil;
}
-(NSString*)getNameWithTime:(NSDate*)date
{
    NSDateFormatter * formate = [[NSDateFormatter alloc]init];
    [formate setDateFormat:@"yyyy_MM_dd__HH_mm_ss"];
    NSString * dateString = [formate stringFromDate:date];
    dateString = [NSString stringWithFormat:@"%@.mp4",dateString];
    return dateString;
}


#pragma mark 属性
-(void)setFps:(int)fps{
    _fps = fps;
    NSError* error;
    
//    NSArray * a = self.captureDevice.activeFormat.videoSupportedFrameRateRanges;
    if([self.captureDevice lockForConfiguration:&error]){
        self.captureDevice.activeVideoMinFrameDuration = CMTimeMake(1, _fps);
        self.captureDevice.activeVideoMaxFrameDuration = CMTimeMake(1, _fps);
        [self.captureDevice unlockForConfiguration];
    }
}
#pragma mark 接口函数
-(void)startRunning{
    [_captureSession startRunning];
}
-(void)stopRunning{
    [_captureSession stopRunning];
}

-(void)startRecodeing{

    if ((_captureType & GJCaptureTypeFile) == GJCaptureTypeFile) {
        NSString *outputFielPath=[NSTemporaryDirectory() stringByAppendingString:[self getNameWithTime:[NSDate date]]];
        NSLog(@"save path is :%@",outputFielPath);
        AVCaptureConnection *captureConnection=[self.captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        captureConnection.videoOrientation=[self.captureVideoPreviewLayer connection].videoOrientation;
        //根据连接取得设备输出的数据
        if (![self.captureMovieFileOutput isRecording]) {
            //预览图层和视频方向保持一致
            [self.captureMovieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFielPath] recordingDelegate:self];
        }
    }
    if ((_captureType & GJCaptureTypeVideoStream) == GJCaptureTypeVideoStream){
//        AVCaptureConnection *captureConnection=[self.captureDataOutput connectionWithMediaType:AVMediaTypeVideo];
//        captureConnection.videoOrientation=[self.captureVideoPreviewLayer connection].videoOrientation;
        [self.captureDataOutput setSampleBufferDelegate:self queue:_videoStreamQueue];
    }
    if ((_captureType & GJCaptureTypeAudioStream) == GJCaptureTypeAudioStream){
        if (_audioStreamQueue == nil) {
            _audioStreamQueue = dispatch_queue_create("_audioStreamQueue", DISPATCH_QUEUE_CONCURRENT);
        }
        [self.captureAudioOutput setSampleBufferDelegate:self queue:_audioStreamQueue];
    }
   
    return;
}
-(void)captureImageWithBlock:(void (^)(UIImage *))resultBlock{
    if ((_captureType & GJCaptureTypeImage) == GJCaptureTypeImage){
        AVCaptureConnection *captureConnection=[self.captureImageOutput connectionWithMediaType:AVMediaTypeVideo];
        [self.captureImageOutput captureStillImageAsynchronouslyFromConnection:captureConnection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
            NSData * data = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
            UIImage* image = [UIImage imageWithData:data];
            if (resultBlock != nil) {
                resultBlock(image);
            }
        }];
    }else{
        if (resultBlock != nil) {
            resultBlock(nil);
        }
    }
}
-(void)stopRecode{
    if((_captureType & GJCaptureTypeFile) == GJCaptureTypeFile){
        if ([self.captureMovieFileOutput isRecording]){
            [self.captureMovieFileOutput stopRecording];//停止录制
        }
    }
    if ((_captureType & GJCaptureTypeVideoStream) == GJCaptureTypeVideoStream){
        [self.captureDataOutput setSampleBufferDelegate:nil queue:NULL];
    }
    if ((_captureType & GJCaptureTypeAudioStream) == GJCaptureTypeAudioStream){
        [self.captureAudioOutput setSampleBufferDelegate:nil queue:nil];
    }
}

-(void)adjustOrientation{
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    AVCaptureConnection *captureConnection=[self.captureVideoPreviewLayer connection];
    captureConnection.videoOrientation = (AVCaptureVideoOrientation)orientation;
    captureConnection=[self.captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    if (captureConnection == nil) {
        captureConnection=[self.captureDataOutput connectionWithMediaType:AVMediaTypeVideo];
    }
    captureConnection.videoOrientation = (AVCaptureVideoOrientation)orientation;
}

- (void)changeCapturePosition {
    [self removeNotificationFromCaptureDevice:self.captureDevice];
    AVCaptureDevicePosition currentPosition=[self.captureDevice position];
    
    self.captureDevice =[self.videoCaptureDeviceInput device];
    AVCaptureDevicePosition toChangePosition=AVCaptureDevicePositionFront;
    if (currentPosition==AVCaptureDevicePositionUnspecified||currentPosition==AVCaptureDevicePositionFront) {
        toChangePosition=AVCaptureDevicePositionBack;
    }
    
    self.captureDevice =[self getCameraDeviceWithPosition:toChangePosition];
    [self addNotificationToCaptureDevice:self.captureDevice ];
    //获得要调整的设备输入对象
    AVCaptureDeviceInput *toChangeDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:self.captureDevice  error:nil];
    
    //改变会话的配置前一定要先开启配置，配置完成后提交配置改变
    [self.captureSession beginConfiguration];
    //移除原有输入对象
    [self.captureSession removeInput:self.videoCaptureDeviceInput];
    //添加新的输入对象
    if ([self.captureSession canAddInput:toChangeDeviceInput]) {
        [self.captureSession addInput:toChangeDeviceInput];
        self.videoCaptureDeviceInput=toChangeDeviceInput;
    }
    //提交会话配置
    [self.captureSession commitConfiguration];
    
    self.videoCaptureDeviceInput = toChangeDeviceInput;
    
    NSError* error;
    //链接创建后
    if([self.captureDevice lockForConfiguration:&error]){
        self.captureDevice.activeVideoMinFrameDuration = CMTimeMake(1, _fps);
        self.captureDevice.activeVideoMaxFrameDuration = CMTimeMake(1, _fps);
        [self.captureDevice unlockForConfiguration];
    }else{
        GJQueueLOG(@"error:%s",error.localizedDescription.UTF8String);
        return;
    }
    
}


/**
 *  改变设备属性的统一操作方法
 *
 *  @param propertyChange 属性改变操作
 */
-(void)changeDeviceProperty:(PropertyChangeBlock)propertyChange{
    AVCaptureDevice *captureDevice= [self.videoCaptureDeviceInput device];
    NSError *error;
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }else{
        GJQueueLOG(@"设置设备属性过程发生错误，错误信息：%s",error.localizedDescription.UTF8String);
    }
}

/**
 *  设置闪光灯模式
 *
 *  @param flashMode 闪光灯模式
 */
-(void)setFlashMode:(AVCaptureFlashMode )flashMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFlashModeSupported:flashMode]) {
            [captureDevice setFlashMode:flashMode];
        }
    }];
}
/**
 *  设置聚焦模式
 *
 *  @param focusMode 聚焦模式
 */
-(void)setFocusMode:(AVCaptureFocusMode )focusMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:focusMode];
        }
    }];
}
/**
 *  设置曝光模式
 *
 *  @param exposureMode 曝光模式
 */
-(void)setExposureMode:(AVCaptureExposureMode)exposureMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:exposureMode];
        }
    }];
}
/**
 *  设置聚焦点
 *
 *  @param point 聚焦点
 */
-(void)focusWithMode:(AVCaptureFocusMode)focusMode exposureMode:(AVCaptureExposureMode)exposureMode atPoint:(CGPoint)point{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        if ([captureDevice isFocusPointOfInterestSupported]) {
            [captureDevice setFocusPointOfInterest:point];
        }
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
        }
        if ([captureDevice isExposurePointOfInterestSupported]) {
            [captureDevice setExposurePointOfInterest:point];
        }
    }];
}



/**
 *  设置聚焦光标位置
 *
 *  @param point 光标位置
 */
-(void)setFocusCursorWithPoint:(CGPoint)point{
    
    CGRect rect = self.focusCursor.frame;
    rect.origin.x = point.x - 0.5 * rect.size.width;
    rect.origin.y = point.y - 0.5 * rect.size.height;
    self.focusCursor.frame = rect;
    self.focusCursor.transform = CATransform3DMakeScale(1.5, 1.5, 0);
    self.focusCursor.opacity=1.0;
    [UIView animateWithDuration:1.0 animations:^{
        self.focusCursor.transform=CATransform3DIdentity;
    } completion:^(BOOL finished) {
        self.focusCursor.opacity=0;
    }];
}

#pragma mark Notification
/**
 *  给输入设备添加通知
 */
-(void)addNotificationToCaptureDevice:(AVCaptureDevice *)captureDevice{
    //注意添加区域改变捕获通知必须首先设置设备允许捕获
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        captureDevice.subjectAreaChangeMonitoringEnabled=YES;
    }];
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //捕获区域发生改变
    [notificationCenter addObserver:self selector:@selector(areaChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}

-(void)removeNotificationFromCaptureDevice:(AVCaptureDevice *)captureDevice{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
/**
 *  移除所有通知
 */
-(void)removeNotification{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self];
}

-(void)addNotificationToCaptureSession:(AVCaptureSession *)captureSession{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //会话出错
    [notificationCenter addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:captureSession];
}


#pragma mark delegate

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    if (connection == self.videoConnect) {
        if([self.delegate respondsToSelector:@selector(GJCaptureTool:recodeVideoYUVData:)]){
            [self.delegate GJCaptureTool:self recodeVideoYUVData:sampleBuffer];
        }
    }else if(connection == self.audioConnect){
        if([self.delegate respondsToSelector:@selector(GJCaptureTool:recodeAudioPCMData:)]){
            [self.delegate GJCaptureTool:self recodeAudioPCMData:sampleBuffer];
        }
//        if (_audioPlayer == nil) {
//            CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
//            const AudioStreamBasicDescription* base = CMAudioFormatDescriptionGetStreamBasicDescription(format);
//            AudioFormatID formtID = base->mFormatID;
//            char* codeChar = (char*)&(formtID);
//            NSLog(@"GJAudioQueueRecoder format：%c%c%c%c ",codeChar[3],codeChar[2],codeChar[1],codeChar[0]);
//            
//            _audioPlayer = [[GJAudioQueuePlayer alloc]initWithFormat:*base bufferSize:4000 macgicCookie:nil];
//        }
//        AudioBufferList bufferOut;
//        CMBlockBufferRef bufferRetain;
//        size_t size;
//        
//        AudioStreamPacketDescription packet;
//        memset(&packet, 0, sizeof(AudioStreamPacketDescription));
//        OSStatus status = CMSampleBufferGetAudioStreamPacketDescriptions(sampleBuffer, sizeof(AudioStreamPacketDescription), &packet, &size);
//        assert(!status);
//        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, &size, &bufferOut, sizeof(AudioBufferList), NULL, NULL, 0, &bufferRetain);
//        assert(!status);
//        [_audioPlayer playData:bufferOut.mBuffers[0].mData lenth:bufferOut.mBuffers[0].mDataByteSize packetCount:0 packetDescriptions:NULL isEof:NO];
//        CFRelease(bufferRetain);
    }

}
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error{
    if ([self.delegate respondsToSelector:@selector(GJCaptureTool:didRecodeFile:)]) {
        [self.delegate GJCaptureTool:self didRecodeFile:outputFileURL];
    }
}

-(void)echoError:(NSError*)error appendStr:(NSString*)str{
    if (error) {
        GJQueueLOG(@"%s失败，error:%s",str.UTF8String,error.localizedDescription.UTF8String);
    }
}


-(void)start{

}
-(void)dealloc{
    [_captureVideoPreviewLayer.superlayer removeObserver:self forKeyPath:@"bounds"];
    [[NSNotificationCenter defaultCenter]removeObserver:self];
}


@end
