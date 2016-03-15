//
//  AppDelegate.h
//  AudioSessionExample
//
//  Created by paul on 16/3/15.
//  Copyright © 2016年 小普. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (nonatomic, assign) AudioQueueRef audioQueue;
@property (nonatomic, assign) AudioStreamBasicDescription streamFormat;
@property (nonatomic, assign) UInt32 bufferSize;
@property (nonatomic, assign) double currentFrequency;
@property (nonatomic, assign) double startingFrameCount;

- (OSStatus)fillBuffer:(AudioQueueRef)buffer;

@end

