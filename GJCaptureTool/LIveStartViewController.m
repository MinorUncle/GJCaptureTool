//
//  LIveStartViewController.m
//  GJCaptureTool
//
//  Created by melot on 2017/8/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "LIveStartViewController.h"
#import "GJLivePushViewController.h"
//static NSString* pullUlr = @"rtmp://10.0.1.65/live/room";
static NSString* pullUlr = @"http://pull.kktv8.com/livekktv/73257119.flv";
//static NSString* url = @"rtmp://192.168.199.187/live/room";
//static NSString* url = @"rtmp://192.168.199.187/live/room";
//static NSString* url = @"rtmp://live.hkstv.hk.lxdns.com/live/hks";
//static NSString* url = @"rtsp://10.0.23.65/sample_100kbit.mp4";
static NSString* pushUrl = @"rtmp://push.kktv8.com/livekktv/73257119";//kk服务器地址

//static NSString* pushUrl = @"rtmp://10.0.1.65/live/room";

@interface LIveStartViewController ()
{
    UIButton* _startBtn;
    UIButton* _arStartBtn;

    UITextField* _pushAddr;
    UITextField* _pullAddr;
    
}
@end

@implementation LIveStartViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    CGRect rect = CGRectMake(0, 200, 80, 40);

    UILabel* leftLab = [[UILabel alloc]initWithFrame:rect];
    leftLab.text = @"拉流地址";
    [self.view addSubview:leftLab];
    
    rect.origin.y += 100;
    leftLab = [[UILabel alloc]initWithFrame:rect];
    leftLab.text = @"推流地址";
    [self.view addSubview:leftLab];
    
    rect.origin.y = 200;
    rect.origin.x = leftLab.frame.size.width;
    rect.size.width = self.view.bounds.size.width - rect.size.width;

    _pullAddr = [[UITextField alloc]initWithFrame:rect];
    _pullAddr.borderStyle =  UITextBorderStyleRoundedRect;
    _pullAddr.text = pullUlr;
    [self.view addSubview:_pullAddr];

    rect.origin.y += 100;
    _pushAddr = [[UITextField alloc]initWithFrame:rect];
    _pushAddr.text = pushUrl;
    _pushAddr.borderStyle =  UITextBorderStyleRoundedRect;
    [self.view addSubview:_pushAddr];
    
    rect.origin.x = 0;
    rect.size.width = self.view.bounds.size.width;
    rect.origin.y += 100;
    _startBtn = [[UIButton alloc]initWithFrame:rect];
    [_startBtn addTarget:self action:@selector(startBtn:) forControlEvents:UIControlEventTouchUpInside];
    [_startBtn setTitle:@"普通直播" forState:UIControlStateNormal];
    [_startBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.view addSubview:_startBtn];
    
    rect.origin.x = 0;
    rect.size.width = self.view.bounds.size.width;
    rect.origin.y += 100;
    _arStartBtn = [[UIButton alloc]initWithFrame:rect];
    [_arStartBtn addTarget:self action:@selector(startBtn:) forControlEvents:UIControlEventTouchUpInside];
    [_arStartBtn setTitle:@"AR直播" forState:UIControlStateNormal];
    [_arStartBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.view addSubview:_arStartBtn];
    // Do any additional setup after loading the view.
}
-(void)startBtn:(UIButton*)btn{
    NSString* pull = _pullAddr.text;
    NSString* push = _pushAddr.text;
    if (!pull || !pull) {
        return;
    }
    

    GJLivePushViewController* c = [[GJLivePushViewController alloc]init];
    c.pullAddr = pull;
    c.pushAddr = push;
    if (btn == _arStartBtn) {
        c.isAr = YES;
    }
    [self presentViewController:c animated:YES completion:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
