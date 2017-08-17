//
//  KKImagePictureOverlay.h
//  KKLiveEngine
//
//  Created by melot on 2017/8/15.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GPUImageFilter.h"
@interface GJOverlayAttribute : NSObject
@property(assign,nonatomic)CGRect frame;
@property(assign,nonatomic)CGFloat rotate;

+(instancetype)overlayAttributeWithFrame:(CGRect)frame rotate:(CGFloat)rotate;
@end


typedef GJOverlayAttribute*(^OverlaysUpdate)(NSInteger index,BOOL* ioFinish);
@interface GJImagePictureOverlay : GPUImageFilter


/**
 开始贴图

 @param images 图片
 @param frame 位置，采用相对采集图片大小的相对关系，所有都在0-1之间
 @param fps 帧率
 @param update 更新回调
 @return 是否成功
 */
-(BOOL)startOverlaysWithImages:(NSArray<UIImage*>*)images frame:(CGRect)frame fps:(NSInteger)fps updateBlock:(OverlaysUpdate)update;
-(void)stop;
@end
