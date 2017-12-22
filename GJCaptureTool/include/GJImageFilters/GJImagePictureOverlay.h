//
//  KKImagePictureOverlay.h
//  KKLiveEngine
//
//  Created by melot on 2017/8/15.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GPUImageFilter.h"
@interface GJOverlayAttribute : NSObject
//注意，frame的origin是中点
@property(assign,nonatomic)CGRect frame;
@property(assign,nonatomic)CGFloat rotate;
//注意image更新后，每次该index循环都是更新后的图片
@property(retain,nonatomic) UIImage* _Nonnull  image;


+(instancetype _Nonnull )overlayAttributeWithImage:(UIImage* _Nonnull)image frame:(CGRect)frame rotate:(CGFloat)rotate;
@end


typedef void(^OverlaysUpdate)(NSInteger index,GJOverlayAttribute* _Nonnull ioAttr,BOOL* _Nonnull ioFinish);
@interface GJImagePictureOverlay : GPUImageFilter


/**
 开始贴图
 
 @param images 图片
 @param fps 帧率,fps<=0,表示每次都更新
 @param update 更新回调
 @return 是否成功
 */
-(BOOL)startOverlaysWithImages:(NSArray<GJOverlayAttribute*>*_Nonnull)images fps:(NSInteger)fps updateBlock:(OverlaysUpdate _Nullable )update;
-(void)stop;
@end
