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
@interface GJLivePushViewController ()<GJLivePushDelegate>
{
    GJLivePush* _livePush;
}
@property (strong, nonatomic) UIView *topView;
@property (strong, nonatomic) UIView *bottomView;
@property (strong, nonatomic) UIButton *takeButton;//拍照按钮
@property (strong, nonatomic) UILabel *fpsLab;
@property (strong, nonatomic) UILabel *btsLab;
@property (strong, nonatomic) UILabel *stateLab;
@end

@implementation GJLivePushViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _livePush = [[GJLivePush alloc]init];
    _livePush.delegate = self;
    CGRect rect = self.view.bounds;
    rect.size.height *= 0.45;
    self.topView = _livePush.previewView;//[[UIView alloc]initWithFrame:rect];
    self.topView.contentMode = UIViewContentModeScaleAspectFill;
    self.topView.frame = rect;
    self.topView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.topView];
    rect.origin.y = CGRectGetMaxY(rect);
    rect.size.width *= 0.333;
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
    
    rect.origin.x = CGRectGetMaxX(rect);
    _fpsLab = [[UILabel alloc]initWithFrame:rect];
    _fpsLab.backgroundColor = [UIColor whiteColor];
    _fpsLab.text = @"0.0 fps";
    [self.view addSubview:_fpsLab];
    
    rect.origin.x = CGRectGetMaxX(rect);
    _btsLab = [[UILabel alloc]initWithFrame:rect];
    _btsLab.backgroundColor = [UIColor whiteColor];
    _btsLab.text = @"0.0 KB/s";
    [self.view addSubview:_btsLab];
    
    rect.origin.x = 0;
    rect.origin.y = CGRectGetMaxY(rect);
    rect.size.height = self.view.bounds.size.height * 0.45;
    rect.size.width = self.view.bounds.size.width;
    self.bottomView = [[UIView alloc]initWithFrame:rect];
    _bottomView.backgroundColor = [UIColor redColor];
    [self.view addSubview:_bottomView];
    
    rect.origin = CGPointMake(10, 20);
    rect.size = CGSizeMake(200, 50);
    _stateLab = [[UILabel alloc]initWithFrame:rect];
    _stateLab.text = @"未连接";
    [self.view addSubview:_stateLab];
    _stateLab.textColor = [UIColor redColor];
    
    [_livePush startCaptureWithSizeType:kCaptureSize352_288 fps:10 position:AVCaptureDevicePositionBack];
    
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
        config.pushUrl = "rtmp://192.168.18.21:1935/live/room";
        [_livePush startStreamPushWithConfig:config];
    }else{
        [_livePush stopStreamPush];
    }
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void)livePush:(GJLivePush *)livePush infoType:(LivePushInfoType)type infoDesc:(id)infoDesc{
    switch (type) {
        case kLivePushInfoConnectSuccess:
        {
            dispatch_async(dispatch_get_main_queue(), ^{
               _stateLab.text =@"连接成功";
            });
        }
            break;
            
        default:
            break;
    }
}
-(void)livePush:(GJLivePush *)livePush errorType:(LivePushErrorType)type errorDesc:(NSString *)errorDesc{
    switch (type) {
        case kLivePushConnentError:{
            dispatch_async(dispatch_get_main_queue(), ^{
                _stateLab.text =@"连接失败";
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
