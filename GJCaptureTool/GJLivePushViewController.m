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
@interface GJLivePushViewController ()<GJLivePushDelegate,GJLivePullDelegate>
{
    GJLivePush* _livePush;
    GJLivePull* _livePull;
    GJLivePull* _livePull2;
}
@property (strong, nonatomic) UIView *topView;
@property (strong, nonatomic) UIView *bottomView;
@property (strong, nonatomic) UIButton *pushButton;
@property (strong, nonatomic) UIButton *pullButton;
@property (strong, nonatomic) UIButton *pull2Button;

@property (strong, nonatomic) UILabel *fpsLab;
@property (strong, nonatomic) UILabel *sendRateLab;
@property (strong, nonatomic) UILabel *pullRateLab;

@property (strong, nonatomic) UILabel *pushStateLab;
@property (strong, nonatomic) UILabel *pullStateLab;
@property (strong, nonatomic) UILabel *delayLab;
@property (strong, nonatomic) UILabel *videoCacheLab;
@property (strong, nonatomic) UILabel *audioCacheLab;



@end

@implementation GJLivePushViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    GJ_LogSetLevel(GJ_LOGALL);
    _livePush = [[GJLivePush alloc]init];
    _livePush.delegate = self;
    _livePull = [[GJLivePull alloc]init];
    _livePull.delegate = self;
    
    CGRect rect = self.view.bounds;
    rect.size.height *= 0.45;
    self.topView = _livePush.previewView;//[[UIView alloc]initWithFrame:rect];
    self.topView.contentMode = UIViewContentModeScaleAspectFill;
    self.topView.frame = rect;
    self.topView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.topView];
    
    
    
    rect.origin = CGPointMake(10, 20);
    rect.size = CGSizeMake(self.view.bounds.size.width-10, 30);
    _pushStateLab = [[UILabel alloc]initWithFrame:rect];
    _pushStateLab.text = @"推流未连接";
    _pushStateLab.textColor = [UIColor redColor];
    [self.view addSubview:_pushStateLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _pullStateLab = [[UILabel alloc]initWithFrame:rect];
    _pullStateLab.text = @"拉流未连接";
    _pullStateLab.textColor = [UIColor redColor];
    [self.view addSubview:_pullStateLab];

    
    rect.origin.y = CGRectGetMaxY(rect);
    _fpsLab = [[UILabel alloc]initWithFrame:rect];
    _fpsLab.textColor = [UIColor redColor];
    _fpsLab.text = @"发送帧率0";
    [self.view addSubview:_fpsLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _sendRateLab = [[UILabel alloc]initWithFrame:rect];
    _sendRateLab.textColor = [UIColor redColor];
    _sendRateLab.text = @"发送码率:0.0 KB/s";
    [self.view addSubview:_sendRateLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _pullRateLab = [[UILabel alloc]initWithFrame:rect];
    _pullRateLab.textColor = [UIColor redColor];
    _pullRateLab.text = @"接收码率:0.0 KB/s";
    [self.view addSubview:_pullRateLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _delayLab = [[UILabel alloc]initWithFrame:rect];
    _delayLab.textColor = [UIColor redColor];
    _delayLab.text = @"发送阻塞延时0.0 ms 帧数：0";
    [self.view addSubview:_delayLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _videoCacheLab = [[UILabel alloc]initWithFrame:rect];
    _videoCacheLab.textColor = [UIColor redColor];
    _videoCacheLab.text = @"视频播放缓存时长0.0 ms 帧数：0";
    [self.view addSubview:_videoCacheLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _audioCacheLab = [[UILabel alloc]initWithFrame:rect];
    _audioCacheLab.textColor = [UIColor redColor];
    _audioCacheLab.text = @"音频播放缓存时长0.0 ms 帧数：0";
    [self.view addSubview:_audioCacheLab];
    
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
    
    rect.origin.x = CGRectGetMaxX(rect);
    _pullButton = [[UIButton alloc]initWithFrame:rect];
    [_pullButton setTitle:@"拉流1开始" forState:UIControlStateNormal];
    [_pullButton setTitle:@"拉流1结束" forState:UIControlStateSelected];
    [_pullButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_pullButton setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [_pullButton setShowsTouchWhenHighlighted:YES];
    [_pullButton addTarget:self action:@selector(takeSelect:) forControlEvents:UIControlEventTouchUpInside];
    _pullButton.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_pullButton];
    rect.origin.x = CGRectGetMaxX(rect);
    _pull2Button = [[UIButton alloc]initWithFrame:rect];
    [_pull2Button setTitle:@"拉流2开始" forState:UIControlStateNormal];
    [_pull2Button setTitle:@"拉流2结束" forState:UIControlStateSelected];
    [_pull2Button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_pull2Button setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [_pull2Button setShowsTouchWhenHighlighted:YES];
    [_pull2Button addTarget:self action:@selector(takeSelect:) forControlEvents:UIControlEventTouchUpInside];
    _pull2Button.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_pull2Button];
    
    rect.origin.x = 0;
    rect.origin.y = CGRectGetMaxY(rect);
    rect.size.height = self.view.bounds.size.height * 0.45;
    rect.size.width = self.view.bounds.size.width*0.5;
    self.bottomView = [_livePull getPreviewView];
    _bottomView.frame = rect;
    _bottomView.backgroundColor = [UIColor redColor];
    [self.view addSubview:_bottomView];
    
    _livePull2 = [[GJLivePull alloc]init];
    UIView* show2 = [_livePull2 getPreviewView];
    show2.backgroundColor = [UIColor yellowColor];
    rect.origin.x = CGRectGetMaxX(rect);
    show2.frame = rect;
    [self.view addSubview:show2];

    
    [_livePush startCaptureWithSizeType:kCaptureSize352_288 fps:15 position:AVCaptureDevicePositionBack];
    
    [_livePush startPreview];
    
       // Do any additional setup after loading the view.
}
-(void)takeSelect:(UIButton*)btn{
    btn.selected = !btn.selected;
    char* url = "rtmp://10.0.1.243/live/room";
    if (btn == _pushButton) {
        if (btn.selected) {
            GJPushConfig config;
            config.channel = 1;
            config.audioSampleRate = 44100;
            config.pushSize = CGSizeMake(288, 352);
            config.videoBitRate = 8*80*1024;
            config.pushUrl = url;
            [_livePush startStreamPushWithConfig:config];
        }else{
             [_livePush stopStreamPush];
        }
      
    }else if(btn == _pullButton){
        if (btn.selected) {
            [_livePull startStreamPullWithUrl:url];
        }else{
            [_livePull stopStreamPull];
        }

    }else if(btn == _pull2Button){
        if (btn.selected) {
            [_livePull2 startStreamPullWithUrl:url];
        }else{
            [_livePull2 stopStreamPull];
        }
    }

}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void)livePush:(GJLivePush *)livePush connentSuccessWithElapsed:(int)elapsed{
    dispatch_async(dispatch_get_main_queue(), ^{
        _pushStateLab.text = [NSString stringWithFormat:@"推流连接成功 耗时：%d ms",elapsed];
    });
}
-(void)livePush:(GJLivePush *)livePush closeConnent:(GJPushSessionInfo *)info resion:(GJConnentCloceReason)reason{
    dispatch_async(dispatch_get_main_queue(), ^{
        _pushStateLab.text = [NSString stringWithFormat:@"推流关闭 总推流时长：%ld ms",info->sessionDuring];
    });
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
                _pullStateLab.text =@"网络错误";
            });
            break;
        }
        default:
            break;
    }
}
-(void)livePush:(GJLivePush *)livePush updatePushStatus:(GJPushStatus *)status{
        _sendRateLab.text = [NSString stringWithFormat:@"发送码率:%0.2f KB/s",status->bitrate/1024.0];
        _fpsLab.text = [NSString stringWithFormat:@"发送帧率%d",status->frameRate];
        _delayLab.text = [NSString stringWithFormat:@"发送阻塞延时%d ms 帧数：%d",status->cacheTime,status->cacheCount];
}
-(void)livePull:(GJLivePull *)livePull connentSuccessWithElapsed:(int)elapsed{
    _pullStateLab.text = [NSString stringWithFormat:@"推流连接成功 耗时：%d ms",elapsed];
}
-(void)livePull:(GJLivePull *)livePull closeConnent:(GJPullSessionInfo *)info resion:(GJConnentCloceReason)reason{
    _pullStateLab.text = [NSString stringWithFormat:@"推流关闭 总推流时长：%ld ms",info->sessionDuring];
}
-(void)livePull:(GJLivePull *)livePull updatePullStatus:(GJPullStatus *)status{
    if (_livePull == livePull) {
        _pullRateLab.text = [NSString stringWithFormat:@"接收码率:%0.2f KB/s",status->bitrate/1024.0];
        _videoCacheLab.text = [NSString stringWithFormat:@"视频播放缓存时长%d ms 帧数：%d",status->videoCacheTime,status->videoCacheCount];
        _audioCacheLab.text = [NSString stringWithFormat:@"音频播放缓存时长%d ms 帧数：%d",status->audioCacheTime,status->audioCacheCount];
    }

}

-(void)livePull:(GJLivePull *)livePull fristFrameDecode:(GJPullFristFrameInfo *)info{
    NSLog(@"pull size:%@",[NSValue valueWithCGSize:info->size]);
}
-(void)livePull:(GJLivePull *)livePull errorType:(GJLiveErrorType)type infoDesc:(NSString *)infoDesc{

    switch (type) {
        case kLivePullReadPacketError:
        case kLivePullConnectError:{
            dispatch_async(dispatch_get_main_queue(), ^{
                _pullStateLab.text =@"拉流失败";
                [livePull stopStreamPull];
                if (livePull == _livePull) {
                    _pullButton.selected = false;
                }else{
                    _pull2Button.selected = false;
                }
            });
            break;
        }
        default:
            break;
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
