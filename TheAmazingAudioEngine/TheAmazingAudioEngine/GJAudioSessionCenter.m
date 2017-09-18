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
    NSMutableArray* _airplayRequest;
    NSMutableArray* _speakerRequest;
    NSMutableArray* _mixingRequest;
    NSMutableArray* _bluetoothRequest;
    NSMutableArray* _voiceProcessingRequest;
    NSMutableArray* _activeRequest;

    AVAudioSessionCategoryOptions _categoryOptions;
    NSString * _category;
    BOOL            _lock;
}
@end
@implementation GJAudioSessionCenter

+(instancetype)shareSession{
    if (_gjAudioSession == nil) {
        _gjAudioSession = [[GJAudioSessionCenter alloc]init];
        [[NSNotificationCenter defaultCenter]addObserver:_gjAudioSession selector:@selector(receiveNotification:) name:AVAudioSessionRouteChangeNotification object:nil];
    }
    return _gjAudioSession;
}
-(void)receiveNotification:(NSNotification*)notic{
   AVAudioSessionRouteChangeReason reason = [notic.userInfo[AVAudioSessionRouteChangeReasonKey] longValue];
    NSError* error;
    if (reason == AVAudioSessionRouteChangeReasonNewDeviceAvailable) {
        [[AVAudioSession sharedInstance]overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error];
        NSLog(@"override out to none result:%@",error);
        
    }else if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable){
        
        [[AVAudioSession sharedInstance]overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
        NSLog(@"override out to speaker result:%@",error);
    }


}
+(instancetype)allocWithZone:(struct _NSZone *)zone{
    if (_gjAudioSession == nil) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            _gjAudioSession = [super allocWithZone:zone];
            _gjAudioSession->_airplayRequest = [NSMutableArray arrayWithCapacity:2];
            _gjAudioSession->_speakerRequest = [NSMutableArray arrayWithCapacity:2];
            _gjAudioSession->_playeRequest = [NSMutableArray arrayWithCapacity:2];
            _gjAudioSession->_recodeRequest = [NSMutableArray arrayWithCapacity:2];
            _gjAudioSession->_mixingRequest = [NSMutableArray arrayWithCapacity:2];
            _gjAudioSession->_bluetoothRequest = [NSMutableArray arrayWithCapacity:2];
            _gjAudioSession->_voiceProcessingRequest = [NSMutableArray arrayWithCapacity:2];
            
            _gjAudioSession->_activeRequest = [NSMutableArray arrayWithCapacity:2];
        });
    }
    return _gjAudioSession;
}

-(BOOL)activeSession:(BOOL)active key:(NSString*)key error:(NSError**)error{
    
    BOOL result = YES;
    @synchronized (self) {

        if (active){
            if(![_activeRequest containsObject:key]){
                [_activeRequest addObject:key];
                if (_activeRequest.count ==1) {
                    NSLog(@"AVAudioSession setActive:%d",active);
                    result = [[AVAudioSession sharedInstance] setActive:active error:error];
                }
            }
        }else if([_activeRequest containsObject:key]){
            [_activeRequest removeObject:key];
            if (_activeRequest.count == 0) {
                NSLog(@"AVAudioSession setActive:%d",active);
                result = [[AVAudioSession sharedInstance] setActive:active error:error];
            }
        }
    }
    return result;
}

-(BOOL)updateCategoryOptionsWithError:(NSError**)error{
    
    if (_lock) {
        return YES;
    }
    _categoryOptions = 0;
    AVAudioSessionCategoryOptions options = 0;
    NSString* category = nil;
    if (_mixingRequest.count > 0) {
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    if (_bluetoothRequest.count>0) {
        options |= AVAudioSessionCategoryOptionAllowBluetooth;
    }
    if (_airplayRequest.count>0) {
        options |= AVAudioSessionCategoryOptionAllowAirPlay;
    }
    if (_speakerRequest.count>0) {
        options |= AVAudioSessionCategoryOptionDefaultToSpeaker;
    }
    if (_playeRequest > 0) {
        
        if (_recodeRequest > 0) {
            category = AVAudioSessionCategoryPlayAndRecord;
        }else{
            category = AVAudioSessionCategoryPlayback;
        }
        
    }else{
        
        category = AVAudioSessionCategoryRecord;
        
    }
    
    if (![_category isEqualToString:[AVAudioSession sharedInstance].category] || options != [AVAudioSession sharedInstance].categoryOptions) {
        
        _category = category;
        _categoryOptions = options;
        NSLog(@"set audiosession category:%@ optations:%d",_category,_categoryOptions);
        return [[AVAudioSession sharedInstance] setCategory:_category withOptions:_categoryOptions error:error];
        
    }
    
    return YES;
    
}
-(BOOL)requestPlay:(BOOL)play key:(NSString*)key error:(NSError**)error{
    BOOL result = YES;

    @synchronized (self) {
        
        if (play){
            if(![_playeRequest containsObject:key]){
                [_playeRequest addObject:key];
                if (_playeRequest.count ==1) {
                    result = [self updateCategoryOptionsWithError:error];
                }
            }
        }else if([_playeRequest containsObject:key]){
            [_playeRequest removeObject:key];
            if (_playeRequest.count == 0) {
                result = [self updateCategoryOptionsWithError:error];
            }
        }
    }

    return result;
    
}

-(BOOL)requestRecode:(BOOL)recode key:(NSString*)key error:(NSError**)error{
    
    BOOL result = YES;
    @synchronized (self) {

        if (recode) {
            if(![_recodeRequest containsObject:key]){
                [_recodeRequest addObject:key];
                if (_recodeRequest.count ==1) {
                    result = [self updateCategoryOptionsWithError:error];
                }
            }
        }else if([_recodeRequest containsObject:key]){
            [_playeRequest removeObject:key];
            if (_playeRequest.count == 0) {
                result = [self updateCategoryOptionsWithError:error];
            }
        }
    }
    return result;
    
}
-(BOOL)requestMix:(BOOL)mix key:(NSString*)key error:(NSError**)error{
    
    BOOL result = YES;
    @synchronized (self) {

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
-(BOOL)requestAllowAirPlay:(BOOL)allowAirPlay key:(NSString*)key error:(NSError**)error
{
    
    BOOL result = YES;
    @synchronized (self) {

        if (allowAirPlay) {
            if (![_airplayRequest containsObject:key]) {
                [_airplayRequest addObject:key];
                if (_airplayRequest.count ==1) {
                    result = [self updateCategoryOptionsWithError:error];
                }
            }
        }else if ([_airplayRequest containsObject:key]) {
            [_airplayRequest removeObject:key];
            if (_airplayRequest.count == 0) {
                result = [self updateCategoryOptionsWithError:error];
            }
        }
    }
    
    return result;
    
}
-(BOOL)requestDefaultToSpeaker:(BOOL)speaker key:(NSString*)key error:(NSError**)error{
    
    BOOL result = YES;
    
    @synchronized (self) {

        if (speaker) {
            if (![_speakerRequest containsObject:key]) {
                [_speakerRequest addObject:key];
                if (_speakerRequest.count ==1) {
                    result = [self updateCategoryOptionsWithError:error];
                }
            }
        }else if ([_speakerRequest containsObject:key]) {
            [_speakerRequest removeObject:key];
            if (_speakerRequest.count == 0) {
                result = [self updateCategoryOptionsWithError:error];
            }
        }
    }
    return result;
    
}
-(BOOL)requestBluetooth:(BOOL)bluetooth key:(NSString*)key error:(NSError**)error{
    
    BOOL result = YES;
    @synchronized (self) {

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

-(BOOL)setPrefferSampleRate:(double)sampleRate error:(NSError**)error{
    
    return [[AVAudioSession sharedInstance]setPreferredSampleRate:sampleRate error:error];

}
-(void)lockBeginConfig{
    
    _lock = YES;
    
}

-(void)unLockApplyConfig:(NSError**)error{
    
    _lock = NO;
    [self updateCategoryOptionsWithError:error];
    
}
@end
