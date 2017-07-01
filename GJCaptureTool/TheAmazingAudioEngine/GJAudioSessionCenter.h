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


-(BOOL)requestPlay:(BOOL)play key:(NSString*)key error:(NSError**)error;
-(BOOL)requestSpeaker:(BOOL)speaker key:(NSString*)key error:(NSError**)error;
-(BOOL)requestRecode:(BOOL)recode key:(NSString*)key error:(NSError**)error;
-(BOOL)requestMix:(BOOL)mix key:(NSString*)key error:(NSError**)error;
-(BOOL)requestBluetooth:(BOOL)bluetooth key:(NSString*)key error:(NSError**)error;
-(BOOL)requestAllowAirPlay:(BOOL)bluetooth key:(NSString*)key error:(NSError**)error;
-(BOOL)requestDefaultToSpeaker:(BOOL)bluetooth key:(NSString*)key error:(NSError**)error;

-(BOOL)activeSession:(BOOL)active key:(NSString*)key error:(NSError**)error;
-(BOOL)setPrefferSampleRate:(double)sampleRate error:(NSError**)error;
-(void)lockConfig;
-(void)unLockConfig;
@end
