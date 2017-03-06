//
//  GJLivePull.h
//  GJLivePull
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GJLivePullDefine.h"
@class UIView;
@class GJLivePull;

@protocol GJLivePullDelegate <NSObject>
@required
/**
 推流停止错误回调
 
 @param type 错误类型
 @param errorDesc 描述
 */
-(void)livePull:(GJLivePull*)livePull errorType:(LivePullErrorType)type errorDesc:(NSString*)errorDesc;



/**
 直播信息回调，当直播类型为KKPull_PROTOCOL_ZEGO时，直播地址从这里回调(重要).
 
 @param livePull livePull description
 @param type 信息type，
 @param infoDesc 信息值，具体类型见LivePullInfoType
 */
-(void)livePull:(GJLivePull*)livePull infoType:(LivePullInfoType)type infoDesc:(id)infoDesc;

@optional
@end

@interface GJLivePull : NSObject
@property(nonatomic,strong,readonly,getter=getPreviewView)UIView* previewView;

- (bool)startStreamPullWithUrl:(char*)url;

- (void)stopStreamPull;

@end
