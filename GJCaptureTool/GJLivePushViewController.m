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
@interface GJLivePushViewController ()<GJLivePushDelegate,GJLivePullDelegate>
{
    GJLivePush* _livePush;
    GJLivePull* _livePull;
}
@property (strong, nonatomic) UIView *topView;
@property (strong, nonatomic) UIView *bottomView;
@property (strong, nonatomic) UIButton *takeButton;//拍照按钮
@property (strong, nonatomic) UILabel *fpsLab;
@property (strong, nonatomic) UILabel *sendRateLab;
@property (strong, nonatomic) UILabel *pullRateLab;

@property (strong, nonatomic) UILabel *pushStateLab;
@property (strong, nonatomic) UILabel *pullStateLab;
@property (strong, nonatomic) UILabel *delayLab;


@end

@implementation GJLivePushViewController

- (void)viewDidLoad {
    [super viewDidLoad];
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
    rect.size = CGSizeMake(200, 30);
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
    _delayLab.text = @"发送阻塞延时0.0 ms";
    [self.view addSubview:_delayLab];
    
    int count = 1;
    rect.origin.y = CGRectGetMaxY(self.topView.frame);
    rect.origin.x = 0;
    rect.size.width = self.topView.frame.size.width * 1.0/count;
    rect.size.height = self.view.bounds.size.height* 0.1;
    _takeButton = [[UIButton alloc]initWithFrame:rect];
    [_takeButton setTitle:@"开始" forState:UIControlStateNormal];
    [_takeButton setTitle:@"结束" forState:UIControlStateSelected];
    [_takeButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_takeButton setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [_takeButton setShowsTouchWhenHighlighted:YES];
    [_takeButton addTarget:self action:@selector(takeSelect:) forControlEvents:UIControlEventTouchUpInside];
    _takeButton.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_takeButton];

    
    rect.origin.x = 0;
    rect.origin.y = CGRectGetMaxY(rect);
    rect.size.height = self.view.bounds.size.height * 0.45;
    rect.size.width = self.view.bounds.size.width;
    self.bottomView = [_livePull getPreviewView];
    _bottomView.frame = rect;
    _bottomView.backgroundColor = [UIColor redColor];
    [self.view addSubview:_bottomView];
    
    
    [_livePush startCaptureWithSizeType:kCaptureSize352_288 fps:15 position:AVCaptureDevicePositionBack];
    
    [_livePush startPreview];
    

    // Do any additional setup after loading the view.
}
-(void)takeSelect:(UIButton*)btn{
    btn.selected = !btn.selected;
    if (btn.selected) {
        GJPushConfig config;
        config.channel = 1;
        config.audioSampleRate = 44100;
        config.pushSize = CGSizeMake(288, 352);
        config.videoBitRate = 8*200*1024;
        config.pushUrl = "rtmp://10.0.1.243:1935/live/room";
        [_livePush startStreamPushWithConfig:config];
        
        [_livePull startStreamPullWithUrl:config.pushUrl];
    }else{
        [_livePush stopStreamPush];
        [_livePull stopStreamPull];
    }
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)livePush:(GJLivePush *)livePush messageType:(LivePushMessageType)type infoDesc:(id)infoDesc{
    switch (type) {
        case kLivePushConnectSuccess:
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                _pushStateLab.text =@"推流连接成功";
            });
        }
            break;
        case kLivePushConnentError:{
            dispatch_async(dispatch_get_main_queue(), ^{
                _pushStateLab.text =@"推流连接失败";
                [_livePush stopStreamPush];
                _takeButton.selected = false;
            });
            break;
        }
        case kLivePushCloseSuccess:{
            dispatch_async(dispatch_get_main_queue(), ^{
                _pullStateLab.text =@"推流结束";
            });
            break;
        }
        default:
            break;
    }
}

-(void)livePull:(GJLivePull *)livePull messageType:(LivePullMessageType)type infoDesc:(NSString *)infoDesc{

    switch (type) {
        case kLivePullConnectSuccess:
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                _pullStateLab.text =@"拉流连接成功";
            });
        }
            break;
        case kLivePullConnectError:{
            dispatch_async(dispatch_get_main_queue(), ^{
                _pullStateLab.text =@"拉流连接失败";
                [_livePull stopStreamPull];
                _takeButton.selected = false;
            });
            break;
        }
        case kLivePullCloseSuccess:{
            dispatch_async(dispatch_get_main_queue(), ^{
                _pullStateLab.text =@"拉流结束";
            });
            break;
        }
        default:
            break;
    }
}

-(void)livePull:(GJLivePull *)livePull bitrate:(long)bitrate{
    _pullRateLab.text = [NSString stringWithFormat:@"接收码率:%0.2f KB/s",bitrate/1024.0];
}
-(void)livePush:(GJLivePush *)livePush frameRate:(long)frameRate bitrate:(long)bitrate quality:(long)quality delay:(long)delay{
    _sendRateLab.text = [NSString stringWithFormat:@"发送码率:%0.2f KB/s",bitrate/1024.0];
    _fpsLab.text = [NSString stringWithFormat:@"发送帧率%ld",frameRate];
    _delayLab.text = [NSString stringWithFormat:@"发送阻塞延时%ld ms",delay];
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
