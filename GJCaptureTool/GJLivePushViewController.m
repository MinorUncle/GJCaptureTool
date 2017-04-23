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
        [self.view addSubview:_pullStateLab];
        
        _pullRateLab = [[UILabel alloc]init];
        _pullRateLab.textColor = [UIColor redColor];
        _pullRateLab.text = @"Bitrate:0.0 KB/s";
        _pullRateLab.numberOfLines = 0;
        [self.view addSubview:_pullRateLab];
        
        _videoCacheLab = [[UILabel alloc]init];
        _videoCacheLab.textColor = [UIColor redColor];
        _videoCacheLab.text = @"cache V:0.0 ms f:0";
        _videoCacheLab.numberOfLines = 0;
        [self.view addSubview:_videoCacheLab];
        
        _audioCacheLab = [[UILabel alloc]init];
        _audioCacheLab.numberOfLines = 0;
        _audioCacheLab.textColor = [UIColor redColor];
        _audioCacheLab.text = @"cache A:0.0 ms f:0";
        [self.view addSubview:_audioCacheLab];
        
        _netDelay = [[UILabel alloc]init];
        _netDelay.numberOfLines = 0;
        _netDelay.textColor = [UIColor redColor];
        _netDelay.text = @"NetDelay:0ms";
        [self.view addSubview:_netDelay];

        
        _playerBufferLab = [[UILabel alloc]init];
        _playerBufferLab.numberOfLines = 0;
        _playerBufferLab.textColor = [UIColor redColor];
        _playerBufferLab.text = @"buffer：未缓冲";
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

@property (strong, nonatomic) UILabel *fpsLab;
@property (strong, nonatomic) UILabel *sendRateLab;

@property (strong, nonatomic) UILabel *pushStateLab;

@property (strong, nonatomic) UILabel *delayVLab;
@property (strong, nonatomic) UILabel *delayALab;


@property(strong,nonatomic)NSMutableArray<PullShow*>* pulls;

@end

@implementation GJLivePushViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _pulls = [[NSMutableArray alloc]initWithCapacity:2];
    GJ_LogSetLevel(GJ_LOGINFO);
    RTMP_LogSetLevel(RTMP_LOGDEBUG);
    
    _livePush = [[GJLivePush alloc]init];
    _livePush.delegate = self;
 
    
    CGRect rect = self.view.bounds;
    rect.size.height *= 0.45;
    self.topView = _livePush.previewView;//[[UIView alloc]initWithFrame:rect];
    self.topView.contentMode = UIViewContentModeScaleAspectFit;
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
    _fpsLab = [[UILabel alloc]initWithFrame:rect];
    _fpsLab.textColor = [UIColor redColor];
    _fpsLab.text = @"FPS V:0,A:0";
    [self.view addSubview:_fpsLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _sendRateLab = [[UILabel alloc]initWithFrame:rect];
    _sendRateLab.textColor = [UIColor redColor];
    _sendRateLab.text = @"bitrate V:0 KB/s A:0 KB/s";
    [self.view addSubview:_sendRateLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _delayVLab = [[UILabel alloc]initWithFrame:rect];
    _delayVLab.textColor = [UIColor redColor];
    _delayVLab.text = @"cache V t:0 ms f:0";
    [self.view addSubview:_delayVLab];
    
    rect.origin.y = CGRectGetMaxY(rect);
    _delayALab = [[UILabel alloc]initWithFrame:rect];
    _delayALab.textColor = [UIColor redColor];
    _delayALab.text = @"cache A t:0 ms f:0";
    [self.view addSubview:_delayALab];
    
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
    
    [_livePush startCaptureWithSizeType:kCaptureSize1280_720 fps:15 position:AVCaptureDevicePositionBack];
    
    [_livePush startPreview];
    
       // Do any additional setup after loading the view.
}
static char* url = "rtmp://192.168.18.21/live/room";

-(void)takeSelect:(UIButton*)btn{
    btn.selected = !btn.selected;rtmp://10.0.1.126/live/room
    if (btn == _pushButton) {
        if (btn.selected) {
            GJPushConfig config;
            config.channel = 1;
            config.audioSampleRate = 44100;
            config.pushSize = CGSizeMake(360, 640);
            config.videoBitRate = 8*80*1024;
            config.pushUrl = url;
            
            NSString* path = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
            path = [path stringByAppendingPathComponent:@"test.mp4"];
//            [_livePush videoRecodeWithPath:path];
            [_livePush startStreamPushWithConfig:config];
            
        }else{
             [_livePush stopStreamPush];
        }
      
    }else{
        GJLivePull* pull = NULL;
        for (PullShow* show in _pulls) {
            if (show.pullBtn == btn) {
                pull = show.pull;
                break;
            }
        }
        if (pull == NULL) {
            assert(0);
        }
        
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


-(void)livePush:(GJLivePush *)livePush connentSuccessWithElapsed:(int)elapsed{
    _pushStateLab.text = [NSString stringWithFormat:@"推流连接成功 耗时：%d ms",elapsed];
}
-(void)livePush:(GJLivePush *)livePush closeConnent:(GJPushSessionInfo *)info resion:(GJConnentCloceReason)reason{
    GJPushSessionInfo pushInfo = *info;
    dispatch_async(dispatch_get_main_queue(), ^{
        _pushStateLab.text = [NSString stringWithFormat:@"推流关闭 总推流时长：%ld ms",pushInfo.sessionDuring];
    });
}
-(PullShow*)getShowWithPush:(GJLivePull*)pull{
    for (PullShow* show in _pulls) {
        if (show.pull == pull) {
            return show;
        }
    }
    assert(0);
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
-(void)livePush:(GJLivePush *)livePush pushPacket:(R_GJH264Packet *)packet{
    if (_pulls.count>0) {
        GJStreamPacket ppush;
        ppush.type = GJVideoType;
        ppush.packet.h264Packet = packet;
        [_pulls[0].pull pullDataCallback:ppush];
    }
}
-(void)livePush:(GJLivePush *)livePush pushImagebuffer:(CVImageBufferRef)packet pts:(CMTime)pts{
    if (_pulls.count>0) {
        [_pulls[0].pull pullimage:packet time:pts];
        
    }

}

-(void)livePush:(GJLivePush *)livePush updatePushStatus:(GJPushSessionStatus *)status{
    _sendRateLab.text = [NSString stringWithFormat:@"bitrate V:%0.2f KB/s A:%0.2f KB/s",status->videoStatus.bitrate/1024.0,status->audioStatus.bitrate/1024.0];
    _fpsLab.text = [NSString stringWithFormat:@"FPS V:%0.2f,A:%0.2f",status->videoStatus.frameRate,status->audioStatus.frameRate];
    _delayVLab.text = [NSString stringWithFormat:@"cache V t:%ld ms f:%ld",status->videoStatus.cacheTime,status->videoStatus.cacheCount];
    _delayALab.text = [NSString stringWithFormat:@"cache A t:%ld ms f:%ld",status->audioStatus.cacheTime,status->audioStatus.cacheCount];
}
-(void)livePull:(GJLivePull *)livePull connentSuccessWithElapsed:(int)elapsed{
    PullShow* show = [self getShowWithPush:livePull];
    show.pullStateLab.text = [NSString stringWithFormat:@"connent during：%d ms",elapsed];
}
-(void)livePull:(GJLivePull *)livePull closeConnent:(GJPullSessionInfo *)info resion:(GJConnentCloceReason)reason{
    PullShow* show = [self getShowWithPush:livePull];
    show.pullStateLab.text = [NSString stringWithFormat:@"connent total：%ld ms",info->sessionDuring];
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
    NSLog(@"pull size:%@",[NSValue valueWithCGSize:info->size]);
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
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/



@end
