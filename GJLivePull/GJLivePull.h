//
//  GJLivePull.h
//  GJLivePull
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GJLiveDefine.h"
@class UIView;
@class GJLivePull;

@protocol GJLivePullDelegate <NSObject>
@required

-(void)livePull:(GJLivePull*)livePull updatePullStatus:(GJPullStatus*)status;
-(void)livePull:(GJLivePull*)livePull fristFrameDecode:(GJPullFristFrameInfo*)info;
-(void)livePull:(GJLivePull*)livePull closeConnent:(GJPullSessionInfo*)info resion:(GJConnentCloceReason)reason;
-(void)livePull:(GJLivePull*)livePull connentSuccessWithElapsed:(int)elapsed;

-(void)livePull:(GJLivePull*)livePull errorType:(GJLiveErrorType)type infoDesc:(NSString*)infoDesc;


@optional
@end

@interface GJLivePull : NSObject
@property(nonatomic,strong,readonly,getter=getPreviewView)UIView* previewView;


/**
 是否显示，默认yes，离开页面时但是不销毁时，设置false节省消耗
 */
@property(nonatomic,assign)BOOL enablePreview;

@property(nonatomic,weak)id<GJLivePullDelegate> delegate;


- (bool)startStreamPullWithUrl:(char*)url;

- (void)stopStreamPull;

@end
