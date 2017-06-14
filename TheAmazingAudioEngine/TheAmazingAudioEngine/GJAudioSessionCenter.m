//
//  GJAudioSessionCenter.m
//  TheAmazingAudioEngine
//
//  Created by melot on 2017/6/14.
//  Copyright © 2017年 A Tasty Pixel. All rights reserved.
//

#import "GJAudioSessionCenter.h"
#import <AVFoundation/AVFoundation.h>
@interface GJAudioSessionCenter(){
    NSInteger _playeRequest;
    NSInteger _recodeRequest;
    NSInteger _mixingRequest;
    NSInteger _bluetoothRequest;
    NSInteger _voiceProcessingRequest;
    
    AVAudioSessionCategoryOptions _categoryOptions;
    NSString * _category;
}
@end
@implementation GJAudioSessionCenter
-(void)activeConfigWithError:(NSError**)error{
    [[AVAudioSession sharedInstance]setActive:YES withOptions:_categoryOptions error:error];
}
-(void)updateCategory{
    
    if (_recodeRequest > 0) {
        if (_recodeRequest > 0) {
            _category = AVAudioSessionCategoryPlayAndRecord;
        }else{
            _category = AVAudioSessionCategoryPlayback;
        }
    }else{
        _category = AVAudioSessionCategoryPlayback;
    }
}
-(void)updateCategoryOptions{
    _categoryOptions = 0;
    if (_mixingRequest > 0) {
        _categoryOptions |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    if (_bluetoothRequest>0) {
        _bluetoothRequest |= AVAudioSessionCategoryOptionAllowBluetooth;
    }
}
-(void)requestPlay:(BOOL)play error:(NSError**)error{
    if (play) {
        _playeRequest ++;
        if (_playeRequest ==1) {
            [self updateCategory];
            [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
        }
    }else if (_playeRequest > 0) {
        _playeRequest --;
        if (_playeRequest == 0) {
            [self updateCategory];
            [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
        }
    }
}
-(void)requestRecode:(BOOL)recode error:(NSError**)error{
    if (recode) {
        _recodeRequest ++;
        if (_recodeRequest ==1) {
            [self updateCategory];
            [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
        }
    }else if (_recodeRequest > 0) {
        _recodeRequest --;
        if (_recodeRequest == 0) {
            [self updateCategory];
            [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
        }
    }
}
-(void)requestMix:(BOOL)mix absolute:(BOOL)absolute error:(NSError**)error{
    if (absolute) {
        if (mix) {
            _mixingRequest = 1;
            _categoryOptions |= AVAudioSessionCategoryOptionMixWithOthers;
            [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
            
        }else{
            _mixingRequest = 0;
            _categoryOptions |= !AVAudioSessionCategoryOptionMixWithOthers;
            [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];

        }
    }else{
        if (mix) {
            _mixingRequest ++;
            if (_recodeRequest ==1) {
                _categoryOptions |= AVAudioSessionCategoryOptionMixWithOthers;
                [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
            }
        }else if (_recodeRequest > 0) {
            _recodeRequest --;
            if (_recodeRequest == 0) {
                _categoryOptions |= !AVAudioSessionCategoryOptionMixWithOthers;
                [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
            }
        }
    }
}
-(void)requestBluetooth:(BOOL)bluetooth absolute:(BOOL)absolute error:(NSError**)error{
    if (absolute) {
        if (bluetooth) {
            _bluetoothRequest = 1;
            [self updateCategoryOptions];
            [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
            
        }else{
            _bluetoothRequest = 0;
            [self updateCategoryOptions];
            [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
            
        }
    }else{
        if (bluetooth) {
            _bluetoothRequest ++;
            if (_bluetoothRequest ==1) {
                [self updateCategoryOptions];
                [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
            }
        }else if (_bluetoothRequest > 0) {
            _bluetoothRequest --;
            if (_bluetoothRequest == 0) {
                [self updateCategoryOptions];
                [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
            }
        }
    }
}
@end
