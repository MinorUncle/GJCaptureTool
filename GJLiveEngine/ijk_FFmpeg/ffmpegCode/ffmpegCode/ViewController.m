//
//  ViewController.m
//  ffmpegCode
//
//  Created by tongguan on 16/5/26.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import "ViewController.h"
#import "avformat.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    av_register_all();
    printf("sdfw");
    printf("hihi%s",avformat_configuration());
    
  
    // Do any additional setup after loading the view, typically from a nib.
}
-(void)loadFile{
    NSString* input = [[NSBundle mainBundle]pathForResource:@"test" ofType:@"mp4"];
    
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
