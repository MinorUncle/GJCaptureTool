//
//  H264StreamToTS.h
//  Mp4ToTS
//
//  Created by tongguan on 16/7/14.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface H264StreamToTS : NSObject

//完整的存储路径文件名
@property(copy,nonatomic)NSString* destFilePath;
@property(copy,nonatomic)NSString* preFileName;

//最大分片数，超过则删除前面的。<=0不设置
@property(assign,nonatomic)int numberOfMaxCountFiles;


@property(assign,nonatomic)int durationPerTs;

- (instancetype)initWithDestFilePath:(NSString*)filePath;

-(void)sendH264Stream:(uint8_t*)buffer lenth:(int)lengh pts:(int)pts dts:(int)dts;
-(void)sendAACStream:(uint8_t*)buffer lenth:(int)lengh pts:(int)pts dts:(int)dts;

-(void)start;
-(void)stop;
@end
