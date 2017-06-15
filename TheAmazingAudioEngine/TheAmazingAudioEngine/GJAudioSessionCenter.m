//
//  GJAudioSessionCenter.m
//  TheAmazingAudioEngine
//
//  Created by melot on 2017/6/14.
//  Copyright © 2017年 A Tasty Pixel. All rights reserved.
//

#import "GJAudioSessionCenter.h"
#import <AVFoundation/AVFoundation.h>
static  GJAudioSessionCenter* _gjAudioSession;
@interface GJAudioSessionCenter(){
    NSMutableArray* _playeRequest;
    NSMutableArray* _recodeRequest;
    NSMutableArray* _mixingRequest;
    NSMutableArray* _bluetoothRequest;
    NSMutableArray* _voiceProcessingRequest;
    
    AVAudioSessionCategoryOptions _categoryOptions;
    NSString * _category;
}
@end
@implementation GJAudioSessionCenter

+(instancetype)shareSession{
    if (_gjAudioSession) {
        _gjAudioSession = [[GJAudioSessionCenter alloc]init];
    }
    return _gjAudioSession;
}
+(instancetype)allocWithZone:(struct _NSZone *)zone{
    if (_gjAudioSession) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            _gjAudioSession = [super allocWithZone:zone];
        });
    }
    return _gjAudioSession;
}
-(void)activeConfigWithError:(NSError**)error{
    [[AVAudioSession sharedInstance]setActive:YES withOptions:_categoryOptions error:error];
}
-(BOOL)updateCategoryWithError:(NSError**)error{
    
    if (_recodeRequest > 0) {
        if (_recodeRequest > 0) {
            _category = AVAudioSessionCategoryPlayAndRecord;
        }else{
            _category = AVAudioSessionCategoryPlayback;
        }
    }else{
        _category = AVAudioSessionCategoryPlayback;
    }
    if (![_category isEqualToString:[AVAudioSession sharedInstance].category]) {
        return [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
    }
    return YES;
}
-(BOOL)updateCategoryOptionsWithError:(NSError**)error{
    _categoryOptions = 0;
    if (_mixingRequest.count > 0) {
        _categoryOptions |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    if (_bluetoothRequest.count>0) {
        _categoryOptions |= AVAudioSessionCategoryOptionAllowBluetooth;
    }
    if ([AVAudioSession sharedInstance].categoryOptions != _categoryOptions) {
        return [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
    }
    return YES;
}
-(BOOL)requestPlay:(BOOL)play key:(id)key error:(NSError**)error{
    BOOL result = YES;
    if (play){
        if(![_playeRequest containsObject:key]){
            [_playeRequest addObject:key];
            if (_playeRequest.count ==1) {
                result = [self updateCategoryWithError:error];
            }
        }
    }else if([_playeRequest containsObject:key]){
        [_playeRequest removeObject:key];
        if (_playeRequest.count == 0) {
            result = [self updateCategoryWithError:error];
        }
    }
    return result;
}
-(BOOL)requestRecode:(BOOL)recode key:(id)key error:(NSError**)error{
    BOOL result = YES;
    if (recode) {
        if(![_recodeRequest containsObject:key]){
            [_recodeRequest addObject:key];
            if (_recodeRequest.count ==1) {
                result = [self updateCategoryWithError:error];
            }
        }
    }else if([_recodeRequest containsObject:key]){
        [_playeRequest removeObject:key];
        if (_playeRequest.count == 0) {
            result = [self updateCategoryWithError:error];
        }
    }
    return result;
}
-(BOOL)requestMix:(BOOL)mix absolute:(BOOL)absolute key:(NSString*)key error:(NSError**)error{
    BOOL result = YES;
    if (absolute) {
        if (mix) {
            [_mixingRequest removeAllObjects];
            [_mixingRequest addObject:key];
            result = [self updateCategoryOptionsWithError:error];
        }else{
            [_mixingRequest removeAllObjects];
            result = [self updateCategoryOptionsWithError:error];

        }
    }else{
        if (mix) {
            if (![_mixingRequest containsObject:key]) {
                [_mixingRequest addObject:key];
                if (_mixingRequest.count ==1) {
                    result = [self updateCategoryOptionsWithError:error];
                }
            }
           
        }else if ([_mixingRequest containsObject:key]) {
            [_mixingRequest removeObject:key];
            if (_mixingRequest.count == 0) {
                result = [self updateCategoryOptionsWithError:error];
            }
        }
    }
    return result;
}
-(BOOL)requestBluetooth:(BOOL)bluetooth absolute:(BOOL)absolute key:(id)key error:(NSError**)error{
    BOOL result = YES;
    if (absolute) {
        if (bluetooth) {
            [_bluetoothRequest removeAllObjects];
            [_bluetoothRequest addObject:key];
            result = [self updateCategoryOptionsWithError:error];
            
        }else{
            [_bluetoothRequest removeAllObjects];
            result = [self updateCategoryOptionsWithError:error];
            
        }
    }else{
        if (bluetooth) {
            if (![_bluetoothRequest containsObject:key]) {
                [_bluetoothRequest addObject:key];
                if (_bluetoothRequest.count ==1) {
                    result = [self updateCategoryOptionsWithError:error];
                }
            }
        }else if ([_bluetoothRequest containsObject:key]) {
            [_bluetoothRequest removeObject:key];
            if (_bluetoothRequest.count == 0) {
                result = [self updateCategoryOptionsWithError:error];
            }
        }
    }
    return result;
}
@end
