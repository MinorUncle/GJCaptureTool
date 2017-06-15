//
//  GJAudioSessionCenter.h
//  TheAmazingAudioEngine
//
//  Created by melot on 2017/6/14.
//  Copyright © 2017年 A Tasty Pixel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GJAudioSessionCenter : NSObject

+(instancetype)shareSession;


-(BOOL)requestPlay:(BOOL)play key:(id)key error:(NSError**)error;

-(BOOL)requestRecode:(BOOL)recode key:(id)key error:(NSError**)error;
-(BOOL)requestMix:(BOOL)mix absolute:(BOOL)absolute key:(NSString*)key error:(NSError**)error;
-(BOOL)requestBluetooth:(BOOL)bluetooth absolute:(BOOL)absolute key:(id)key error:(NSError**)error;
-(BOOL)activeConfigWithError:(NSError**)error;
@end
