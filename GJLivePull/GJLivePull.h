//
//  GJLivePull.h
//  GJLivePull
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "GJLivePullDefine.h"
@class UIView;
@class GJLivePull;

@protocol GJLivePullDelegate <NSObject>
@required
/**
 直播信息回调，当直播类型为KKPull_PROTOCOL_ZEGO时，直播地址从这里回调(重要).
 
 @param livePull livePull description
 @param type 信息type，
 @param infoDesc 信息值，具体类型见LivePullInfoType
 */
-(void)livePull:(GJLivePull*)livePull messageType:(LivePullMessageType)type infoDesc:(NSString*)infoDesc;

-(void)livePull:(GJLivePull*)livePull bitrate:(long)bitrate;

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
