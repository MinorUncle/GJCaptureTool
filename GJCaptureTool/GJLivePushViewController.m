//
//  GJLivePushViewController.m
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePushViewController.h"
#import "GJLivePush.h"
#import <AVFoundation/AVFoundation.h>
#import "GJLivePull.h"
#import "GJLog.h"
#import "log.h"
#import "GJBufferPool.h"

static char* url = "rtmp://192.168.199.187/live/room";
//static char* url = "rtmp://192.168.199.187/live/room";

@interface PullShow : NSObject
{
    
}
@property (strong, nonatomic) UILabel *pullRateLab;
@property (strong, nonatomic) UILabel *pullStateLab;
@property (strong, nonatomic) UILabel *videoCacheLab;
@property (strong, nonatomic) UILabel *audioCacheLab;
@property (strong, nonatomic) UILabel *playerBufferLab;
@property (strong, nonatomic) UILabel *netDelay;


@property (strong, nonatomic) UIView* view;;
@property (assign, nonatomic) CGRect frame;
@property (strong, nonatomic) GJLivePull* pull;
@property (weak, nonatomic) UIButton* pullBtn;;

@end

@implementation PullShow
- (instancetype)initWithView:(UIView*)view
{
    self = [super init];
    if (self) {
        _view = view;
        _pullStateLab = [[UILabel alloc]init];
        _pullStateLab.numberOfLines = 0;
        _pullStateLab.text = @"未连接";
        _pullStateLab.textColor = [UIColor redColor];
        _pullStateLab.font = [UIFont systemFontOfSize:10];
        [self.view addSubview:_pullStateLab];
        
        _pullRateLab = [[UILabel alloc]init];
        _pullRateLab.textColor = [UIColor redColor];
        _pullRateLab.text = @"Bitrate:0.0 KB/s";
        _pullRateLab.numberOfLines = 0;
        _pullRateLab.font = [UIFont systemFontOfSize:10];
        [self.view addSubview:_pullRateLab];
        
        _videoCacheLab = [[UILabel alloc]init];
        _videoCacheLab.textColor = [UIColor redColor];
        _videoCacheLab.text = @"cache V:0.0 ms f:0";
        _videoCacheLab.numberOfLines = 0;
        _videoCacheLab.font = [UIFont systemFontOfSize:10];
        [self.view addSubview:_videoCacheLab];
        
        _audioCacheLab = [[UILabel alloc]init];
        _audioCacheLab.numberOfLines = 0;
        _audioCacheLab.textColor = [UIColor redColor];
        _audioCacheLab.text = @"cache A:0.0 ms f:0";
        _audioCacheLab.font = [UIFont systemFontOfSize:10];
        [self.view addSubview:_audioCacheLab];
        
        _netDelay = [[UILabel alloc]init];
        _netDelay.numberOfLines = 0;
        _netDelay.textColor = [UIColor redColor];
        _netDelay.text = @"NetDelay:0ms";
        _netDelay.font = [UIFont systemFontOfSize:10];
        [self.view addSubview:_netDelay];

        
        _playerBufferLab = [[UILabel alloc]init];
        _playerBufferLab.numberOfLines = 0;
        _playerBufferLab.textColor = [UIColor redColor];
        _playerBufferLab.text = @"buffer：未缓冲";
        _playerBufferLab.font = [UIFont systemFontOfSize:10];
        [self.view addSubview:_playerBufferLab];
    }
    return self;
}
-(void)setFrame:(CGRect)frame{
    _frame = frame;
    self.view.frame = frame;
    CGRect rect = frame;
    int count = 6;
    rect.origin.x = 0;
    rect.origin.y = 0;
    rect.size.height *= 1.0/count;
    _pullStateLab.frame = rect;
    
    rect.origin.y = CGRectGetMaxY(rect);
    _pullRateLab.frame = rect;
    
    rect.origin.y = CGRectGetMaxY(rect);
    _videoCacheLab.frame = rect;
    
    rect.origin.y = CGRectGetMaxY(rect);
    _audioCacheLab.frame = rect;
    
    rect.origin.y = CGRectGetMaxY(rect);
    _netDelay.frame = rect;
    
    rect.origin.y = CGRectGetMaxY(rect);
    _playerBufferLab.frame = rect;
}
@end
@interface GJLivePushViewController ()<GJLivePushDelegate,GJLivePullDelegate>
{
    GJLivePush* _livePush;

}
@property (strong, nonatomic) UIView *topView;
@property (strong, nonatomic) UIView *bottomView;
@property (strong, nonatomic) UIButton *pushButton;
@property (strong, nonatomic) UIButton *pullButton;
@property (strong, nonatomic) UIButton *pull2Button;
@property (strong, nonatomic) UIButton *audioMixBtn;
@property (strong, nonatomic) UIButton *earPlay;
@property (strong, nonatomic) UIButton *mixStream;
@property (strong, nonatomic) UIButton *changeCamera;

@property (strong, nonatomic) UISlider *inputGain;
@property (strong, nonatomic) UILabel *inputGainLab;

@property (strong, nonatomic) UISlider *mixGain;
@property (strong, nonatomic) UILabel *mixGainLab;

@property (strong, nonatomic) UISlider *outputGain;
@property (strong, nonatomic) UILabel *outputGainLab;

@property (strong, nonatomic) UILabel *fpsLab;
@property (strong, nonatomic) UILabel *sendRateLab;

@property (strong, nonatomic) UILabel *pushStateLab;

@property (strong, nonatomic) UILabel *delayVLab;
@property (strong, nonatomic) UILabel *delayALab;
@property (strong, nonatomic) UILabel *currentV;


@property(strong,nonatomic)NSMutableArray<PullShow*>* pulls;

@end

@implementation GJLivePushViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _pulls = [[NSMutableArray alloc]initWithCapacity:2];
    GJ_LogSetLevel(GJ_LOGINFO);
    RTMP_LogSetLevel(RTMP_LOGERROR);
    
    _livePush = [[GJLivePush alloc]init];
//    _livePush.videoMute = YES;
//    _livePush.audioMute = YES;
    
    GJPushConfig config = {0};
    config.mAudioChannel = 2;
    config.mAudioSampleRate = 44100;
    config.mPushSize = (GSize){360, 640};
    config.mVideoBitrate = 8*80*1024;
    config.mFps = 15;
    config.mAudioBitrate = 40*1000;
    [_livePush setPushConfig:config];
    _livePush.delegate = self;
 
    
    CGRect rect = self.view.bounds;
    rect.size.height *= 0.45;
    self.topView = _livePush.previewView;//[[UIView alloc]initWithFrame:rect];
    self.topView.contentMode = UIViewContentModeScaleAspectFit;
    self.topView.frame = rect;
    self.topView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.topView];
    
    
    
    rect.origin = CGPointMake(0, 20);
    rect.size = CGSizeMake(self.view.bounds.size.width*0.5, 30);
    _pushStateLab = [[UILabel alloc]initWithFrame:rect];
    _pushStateLab.text = @"推流未连接";
    _pushStateLab.textColor = [UIColor redColor];
    _pushStateLab.font = [UIFont systemFontOfSize:10];
    [self.view addSubview:_pushStateLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _fpsLab = [[UILabel alloc]initWithFrame:rect];
    _fpsLab.textColor = [UIColor redColor];
    _fpsLab.font = [UIFont systemFontOfSize:10];
    _fpsLab.text = @"FPS V:0,A:0";
    [self.view addSubview:_fpsLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _sendRateLab = [[UILabel alloc]initWithFrame:rect];
    _sendRateLab.textColor = [UIColor redColor];
    _sendRateLab.text = @"bitrate V:0 KB/s A:0 KB/s";
    _sendRateLab.font = [UIFont systemFontOfSize:10];
    [self.view addSubview:_sendRateLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _delayVLab = [[UILabel alloc]initWithFrame:rect];
    _delayVLab.textColor = [UIColor redColor];
    _delayVLab.font = [UIFont systemFontOfSize:10];
    _delayVLab.text = @"cache V t:0 ms f:0";
    [self.view addSubview:_delayVLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _delayALab = [[UILabel alloc]initWithFrame:rect];
    _delayALab.textColor = [UIColor redColor];
    _delayALab.font = [UIFont systemFontOfSize:10];
    _delayALab.text = @"cache A t:0 ms f:0";
    [self.view addSubview:_delayALab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _currentV = [[UILabel alloc]initWithFrame:rect];
    _currentV.textColor = [UIColor redColor];
    _currentV.font = [UIFont systemFontOfSize:10];
    _currentV.text = @"CV rate:0 kB/s f:0";
    [self.view addSubview:_currentV];
    
    rect.origin = CGPointMake(self.view.bounds.size.width*0.5, 20);
    rect.size = CGSizeMake(self.view.bounds.size.width*0.5, 30);
    _audioMixBtn = [[UIButton alloc]initWithFrame:rect];
    _audioMixBtn.backgroundColor = [UIColor clearColor];
    [_audioMixBtn setTitle:@"开始混音" forState:UIControlStateNormal];
    [_audioMixBtn setTitle:@"结束混音" forState:UIControlStateSelected];
    [_audioMixBtn setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [_audioMixBtn addTarget:self action:@selector(takeSelect:) forControlEvents:UIControlEventTouchUpInside];
    _audioMixBtn.backgroundColor = [UIColor grayColor];
    [self.view addSubview:_audioMixBtn];

    rect.origin.y = CGRectGetMaxY(rect);
    _earPlay = [[UIButton alloc]initWithFrame:rect];
    _earPlay.backgroundColor = [UIColor clearColor];
    [_earPlay setTitle:@"开始耳返" forState:UIControlStateNormal];
    [_earPlay setTitle:@"结束耳返" forState:UIControlStateSelected];
    [_earPlay setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [_earPlay addTarget:self action:@selector(takeSelect:) forControlEvents:UIControlEventTouchUpInside];
    _earPlay.backgroundColor = [UIColor grayColor];
    [self.view addSubview:_earPlay];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _mixStream = [[UIButton alloc]initWithFrame:rect];
    _mixStream.backgroundColor = [UIColor clearColor];
    [_mixStream setTitle:@"禁止混流" forState:UIControlStateNormal];
    [_mixStream setTitle:@"允许混流" forState:UIControlStateSelected];
    [_mixStream setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [_mixStream addTarget:self action:@selector(takeSelect:) forControlEvents:UIControlEventTouchUpInside];
    _mixStream.backgroundColor = [UIColor grayColor];
    [self.view addSubview:_mixStream];

    rect.origin.y = CGRectGetMaxY(rect);
    _changeCamera = [[UIButton alloc]initWithFrame:rect];
    _changeCamera.backgroundColor = [UIColor clearColor];
    [_changeCamera setTitle:@"切换相机" forState:UIControlStateNormal];
    [_changeCamera setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [_changeCamera addTarget:self action:@selector(takeSelect:) forControlEvents:UIControlEventTouchUpInside];
    _changeCamera.backgroundColor = [UIColor grayColor];
    [self.view addSubview:_changeCamera];
    
    rect.origin.y = CGRectGetMaxY(rect);
    rect.size.width *= 0.4;
    _inputGainLab = [[UILabel alloc]initWithFrame:rect];
    _inputGainLab.text = @"采集音量";
    _inputGainLab.font = [UIFont systemFontOfSize:10];
    [self.view addSubview:_inputGainLab];
    rect.origin.x = CGRectGetMaxX(rect);
    rect.size.width = self.view.bounds.size.width - rect.origin.x;
    _inputGain = [[UISlider alloc]initWithFrame:rect];
    _inputGain.maximumValue = 1.0;
    _inputGain.minimumValue = 0.0;
    _inputGain.continuous = NO;
    _inputGain.value = 1.0;
    [_inputGain addTarget:self action:@selector(valueChange:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_inputGain];
    
    rect.origin.y = CGRectGetMaxY(rect);
    rect.size.width = _inputGainLab.bounds.size.width;
    rect.origin.x = _inputGainLab.frame.origin.x;
    
    _mixGainLab = [[UILabel alloc]initWithFrame:rect];
    _mixGainLab.text = @"混音音量";
    _mixGainLab.font = [UIFont systemFontOfSize:10];
    [self.view addSubview:_mixGainLab];
    rect.origin.x = CGRectGetMaxX(rect);
    rect.size.width = self.view.bounds.size.width - rect.origin.x;
    _mixGain = [[UISlider alloc]initWithFrame:rect];
    _mixGain.maximumValue = 1.0;
    _mixGain.minimumValue = 0.0;
    _mixGain.value = 1.0;
    _mixGain.continuous = NO;
    [_mixGain addTarget:self action:@selector(valueChange:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_mixGain];
    
    
    rect.origin.y = CGRectGetMaxY(rect);
    rect.size.width = _mixGainLab.bounds.size.width;
    rect.origin.x = _mixGainLab.frame.origin.x;
    
    _outputGainLab = [[UILabel alloc]initWithFrame:rect];
    _outputGainLab.text = @"混音音量";
    _outputGainLab.font = [UIFont systemFontOfSize:10];
    [self.view addSubview:_outputGainLab];
    rect.origin.x = CGRectGetMaxX(rect);
    rect.size.width = self.view.bounds.size.width - rect.origin.x;
    _outputGain = [[UISlider alloc]initWithFrame:rect];
    _outputGain.maximumValue = 1.0;
    _outputGain.minimumValue = 0.0;
    _outputGain.continuous = NO;
    _outputGain.value = 1.0;
    [_outputGain addTarget:self action:@selector(valueChange:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_outputGain];
    
    
    int count = 3;
    rect.origin.y = CGRectGetMaxY(self.topView.frame);
    rect.origin.x = 0;
    rect.size.width = self.topView.frame.size.width * 1.0/count;
    rect.size.height = self.view.bounds.size.height* 0.1;
    _pushButton = [[UIButton alloc]initWithFrame:rect];
    [_pushButton setTitle:@"推流开始" forState:UIControlStateNormal];
    [_pushButton setTitle:@"推流结束" forState:UIControlStateSelected];
    [_pushButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_pushButton setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [_pushButton setShowsTouchWhenHighlighted:YES];
    [_pushButton addTarget:self action:@selector(takeSelect:) forControlEvents:UIControlEventTouchUpInside];
    _pushButton.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_pushButton];
    
    CGRect sRect;
    sRect.origin.x = 0;
    sRect.origin.y = CGRectGetMaxY(rect);
    sRect.size.height = self.view.bounds.size.height - sRect.origin.y;
    sRect.size.width = self.view.bounds.size.width/(count-1);
    for (int i = 0; i<count -1; i++) {
        rect.origin.x = CGRectGetMaxX(rect);
        UIButton* pullButton = [[UIButton alloc]initWithFrame:rect];
        [pullButton setTitle:@"拉流1开始" forState:UIControlStateNormal];
        [pullButton setTitle:@"拉流1结束" forState:UIControlStateSelected];
        [pullButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [pullButton setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
        [pullButton setShowsTouchWhenHighlighted:YES];
        [pullButton addTarget:self action:@selector(takeSelect:) forControlEvents:UIControlEventTouchUpInside];
        pullButton.backgroundColor = [UIColor whiteColor];
        [self.view addSubview:pullButton];
        
        GJLivePull* livePull = [[GJLivePull alloc]init];
        livePull.delegate = self;
        
        PullShow* show = [[PullShow alloc]initWithView:[livePull getPreviewView]];
        show.pullBtn = pullButton;
        show.frame = sRect;
        show.view.backgroundColor = [UIColor yellowColor];
        show.view.contentMode = UIViewContentModeScaleAspectFit;
        sRect.origin.x = CGRectGetMaxX(sRect);
        show.pull = livePull;
        [_pulls addObject:show];
        [self.view addSubview:show.view];
    }
    
    _livePush.cameraPosition = GJInterfaceOrientationPortrait;
    [_livePush startPreview];
    
       // Do any additional setup after loading the view.
}
-(void)valueChange:(UISlider*)slider{
    if (slider == _inputGain) {
        _inputGainLab.text = [NSString stringWithFormat:@"采集音量：%0.2f",slider.value];
        [_livePush setInputVolume:slider.value];
    }else if (slider == _mixGain){
        _mixGainLab.text = [NSString stringWithFormat:@"混音音量：%0.2f",slider.value];
        [_livePush setMixVolume:slider.value];

    }else if (slider == _outputGain){
        _outputGainLab.text = [NSString stringWithFormat:@"输出音量：%0.2f",slider.value];
        [_livePush setMasterOutVolume:slider.value];
    }
}
-(void)takeSelect:(UIButton*)btn{
    btn.selected = !btn.selected;//rtmp://10.0.1.126/live/room
    if (btn == _pushButton) {
        if (btn.selected) {
            
            NSString* path = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
            path = [path stringByAppendingPathComponent:@"test.mp4"];
//            [_livePush videoRecodeWithPath:path];
            [_livePush startStreamPushWithUrl:[NSString stringWithUTF8String:url]];
        }else{
             [_livePush stopStreamPush];
        }
    }else if(btn == _audioMixBtn){
        if (btn.selected) {
            NSURL* path = [[NSBundle mainBundle]URLForResource:@"MixTest" withExtension:@"mp3"];
            [_livePush startAudioMixWithFile:path];

        }else{
            [_livePush stopAudioMix];
        }
    }else if(btn == _earPlay){
        [_livePush enableAudioInEarMonitoring:btn.selected];
    }else if(btn == _mixStream){
        _livePush.mixFileNeedToStream = !btn.selected;
    }else  if(btn == _changeCamera){
        if (_livePush.cameraPosition == GJCameraPositionBack) {
            _livePush.cameraPosition = GJCameraPositionFront;
        }else{
            _livePush.cameraPosition = GJCameraPositionBack;
        }
        
    }else{
        GJLivePull* pull = NULL;
        for (PullShow* show in _pulls) {
            if (show.pullBtn == btn) {
                pull = show.pull;
                break;
            }
        }
//        if (pull == NULL) {
//            assert(0);
//        }
        
        if (btn.selected) {
            [pull startStreamPullWithUrl:url];
        }else{
            [pull stopStreamPull];
        }
        
    }

}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void)livePush:(GJLivePush *)livePush connentSuccessWithElapsed:(GLong)elapsed{
    _pushStateLab.text = [NSString stringWithFormat:@"推流连接耗时：%ld ms",elapsed];
}
-(void)livePush:(GJLivePush *)livePush closeConnent:(GJPushSessionInfo *)info resion:(GJConnentCloceReason)reason{
    GJPushSessionInfo pushInfo = *info;
    dispatch_async(dispatch_get_main_queue(), ^{
        _pushStateLab.text = [NSString stringWithFormat:@"推流关闭,推流时长：%ld ms",pushInfo.sessionDuring];
    });
}
-(PullShow*)getShowWithPush:(GJLivePull*)pull{
    for (PullShow* show in _pulls) {
        if (show.pull == pull) {
            return show;
        }
    }
    return 0;
}
-(void)livePush:(GJLivePush *)livePush dynamicVideoUpdate:(VideoDynamicInfo *)elapsed{
    _currentV.text = [NSString stringWithFormat:@"CV rate:%fkB/s f:%f",elapsed->currentBitrate,elapsed->sourceFPS];
}
-(void)livePush:(GJLivePush *)livePush errorType:(GJLiveErrorType)type infoDesc:(id)infoDesc{
    switch (type) {
        case kLivePushConnectError:{
            dispatch_async(dispatch_get_main_queue(), ^{
                _pushStateLab.text =@"推流连接失败";
                [_livePush stopStreamPush];
                _pushButton.selected = false;
            });
            break;
        }
        case kLivePushWritePacketError:{
            dispatch_async(dispatch_get_main_queue(), ^{
                _pushStateLab.text =@"网络错误";
            });
            break;
        }
        default:
            break;
    }
}
//-(void)livePush:(GJLivePush *)livePush pushPacket:(R_GJH264Packet *)packet{
//    if (_pulls.count>0) {
//        GJStreamPacket ppush;
//        ppush.type = GJMediaType_Video;
//        ppush.packet.h264Packet = packet;
//        [_pulls[0].pull pullDataCallback:ppush];
//    }
//}
//-(void)livePush:(GJLivePush *)livePush pushImagebuffer:(CVImageBufferRef)packet pts:(CMTime)pts{
//    if (_pulls.count>0) {
//        [_pulls[0].pull pullimage:packet time:pts];
//        
//    }
//
//}

-(void)livePush:(GJLivePush *)livePush updatePushStatus:(GJPushSessionStatus *)status{
    
    _sendRateLab.text = [NSString stringWithFormat:@"bitrate V:%0.2f KB/s A:%0.2f KB/s",status->videoStatus.bitrate/1024.0,status->audioStatus.bitrate/1024.0];
    _fpsLab.text = [NSString stringWithFormat:@"FPS V:%0.2f,A:%0.2f",status->videoStatus.frameRate,status->audioStatus.frameRate];
    _delayVLab.text = [NSString stringWithFormat:@"cache V t:%ld ms f:%ld",status->videoStatus.cacheTime,status->videoStatus.cacheCount];
    _delayALab.text = [NSString stringWithFormat:@"cache A t:%ld ms f:%ld",status->audioStatus.cacheTime,status->audioStatus.cacheCount];
}
-(void)livePull:(GJLivePull *)livePull connentSuccessWithElapsed:(int)elapsed{
    dispatch_async(dispatch_get_main_queue(), ^{
        PullShow* show = [self getShowWithPush:livePull];
        show.pullStateLab.text = [NSString stringWithFormat:@"connent during：%d ms",elapsed];
    });
  
}
-(void)livePull:(GJLivePull *)livePull closeConnent:(GJPullSessionInfo *)info resion:(GJConnentCloceReason)reason{
    GJPullSessionInfo sInfo= *info;
    dispatch_async(dispatch_get_main_queue(), ^{

        PullShow* show = [self getShowWithPush:livePull];
        show.pullStateLab.text = [NSString stringWithFormat:@"connent total：%lld ms",sInfo.sessionDuring];
    });
}
-(void)livePull:(GJLivePull *)livePull updatePullStatus:(GJPullSessionStatus *)status{
    GJPullSessionStatus pullStatus = *status;
    dispatch_async(dispatch_get_main_queue(), ^{
        PullShow* show = [self getShowWithPush:livePull];
        show.pullRateLab.text = [NSString stringWithFormat:@"bitrate V:%0.2f KB/s A:%0.2f KB/s",pullStatus.videoStatus.bitrate/1024.0,pullStatus.audioStatus.bitrate/1024.0];
        show.videoCacheLab.text = [NSString stringWithFormat:@"cache V t:%ld ms f:%ld",pullStatus.videoStatus.cacheTime,pullStatus.videoStatus.cacheCount];
        show.audioCacheLab.text = [NSString stringWithFormat:@"cache A t:%ld ms f:%ld",pullStatus.audioStatus.cacheTime,pullStatus.audioStatus.cacheCount];
    });
}

-(void)livePull:(GJLivePull *)livePull fristFrameDecode:(GJPullFristFrameInfo *)info{
    NSLog(@"pull w:%f,h:%f",info->size.width,info->size.height);
}
-(void)livePull:(GJLivePull *)livePull errorType:(GJLiveErrorType)type infoDesc:(NSString *)infoDesc{

    switch (type) {
        case kLivePullReadPacketError:
        case kLivePullConnectError:{
                PullShow* show = [self getShowWithPush:livePull];
                show.pullStateLab.text =@"connect error";
                [show.pull stopStreamPull];
                show.pullBtn.selected = false;
            break;
        }
        default:
            break;
    }
}

-(void)livePull:(GJLivePull *)livePull bufferUpdatePercent:(float)percent duration:(long)duration{
    PullShow* show = [self getShowWithPush:livePull];
    dispatch_async(dispatch_get_main_queue(), ^{
        show.playerBufferLab.text = [NSString stringWithFormat:@"buffer：%0.2f  %ld ms",percent,duration];
    });
}

-(void)livePull:(GJLivePull *)livePull networkDelay:(long)delay{
    PullShow* show = [self getShowWithPush:livePull];
    dispatch_async(dispatch_get_main_queue(), ^{
        show.netDelay.text = [NSString stringWithFormat:@"NetDelay:%ld ms",delay];
    });
}
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    UIAlertView* alert = [[UIAlertView alloc]initWithTitle:@"提示" message:@"是否测试释放推拉流对象" delegate:self cancelButtonTitle:@"确定" otherButtonTitles:@"取消", nil];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
    if (buttonIndex == 0) {
        _livePush = nil;
        [_pulls removeAllObjects];
        NSLog(@"释放完成");
        GJBufferPoolClean(defauleBufferPool(),false);
    }
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/



@end
