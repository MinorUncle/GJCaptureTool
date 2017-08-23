//
//  LIveStartViewController.m
//  GJCaptureTool
//
//  Created by melot on 2017/8/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "LIveStartViewController.h"
#import "GJLivePushViewController.h"
@interface LIveStartViewController ()
{
    UIButton* _startBtn;
}
@end

@implementation LIveStartViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    _startBtn = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, 100, 80)];
    _startBtn.center = self.view.center;
    [_startBtn addTarget:self action:@selector(startBtn:) forControlEvents:UIControlEventTouchUpInside];
    [_startBtn setTitle:@"点击进入" forState:UIControlStateNormal];
    [_startBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.view addSubview:_startBtn];
    // Do any additional setup after loading the view.
}
-(void)startBtn:(UIButton*)btn{
    GJLivePushViewController* c = [[GJLivePushViewController alloc]init];
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
