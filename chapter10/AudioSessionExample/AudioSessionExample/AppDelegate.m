//
//  AppDelegate.m
//  AudioSessionExample
//
//  Created by paul on 16/3/15.
//  Copyright © 2016年 小普. All rights reserved.
//

#import "AppDelegate.h"

#define FOREGROUND_FREQUENCY 880.0
#define BACKGROUND_FREQUENCY 523.25
#define BUFFER_COUNT 3
#define BUFFER_DURATION 0.5

@interface AppDelegate ()

@end

@implementation AppDelegate



- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Establishing an Audio Seesion with AudioSessionInitialize()
    CheckError(AudioSessionInitialize(NULL,
                                      kCFRunLoopDefaultMode,
                                      MyInterruptionListener,
                                      (__bridge void *)(self)),
               "Couldn't initialize the audio session");
    
    // Setting the Audio Category for an iOS Application
    UInt32 category = kAudioSessionCategory_MediaPlayback;
    CheckError(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                                       sizeof(category),
                                       &category),
               "Couldn't set category on audio session");
    
    // Creating AudioStreamBasicDescription for a Programmatically Generated Sine Wave
    self.currentFrequency = FOREGROUND_FREQUENCY;
    _streamFormat.mSampleRate = 44100.0;
    _streamFormat.mFormatID = kAudioFormatLinearPCM;
    _streamFormat.mFormatFlags = kAudioFormatFlagsCanonical;
    _streamFormat.mChannelsPerFrame = 1;
    _streamFormat.mFramesPerPacket = 1;
    _streamFormat.mBitsPerChannel = 16;
    _streamFormat.mBytesPerFrame = 2;
    _streamFormat.mBytesPerPacket = 2;
    
    // Creating an Audio Queue on iOS
    CheckError(AudioQueueNewOutput(&_streamFormat,
                                   MyAQOutputCallback,
                                   (__bridge void * _Nullable)(self),
                                   NULL,
                                   kCFRunLoopCommonModes,
                                   0,
                                   &_audioQueue),
               "Couldn't create the output AudioQueue");
    
    // Create and enqueue buffers
    AudioQueueBufferRef buffers [BUFFER_COUNT];
    UInt32 bufferSize = BUFFER_DURATION * self.streamFormat.mSampleRate * self.streamFormat.mBytesPerFrame;
    for (int i = 0; i < BUFFER_COUNT; i++) {
        CheckError(AudioQueueAllocateBuffer(self.audioQueue,
                                            bufferSize,
                                            &buffers[i]),
                                            "Couldn't allocate the Audio Queue buffer");
        CheckError([self fillBuffer:buffers[i]], "Couldn't fill buffer (priming)");
        
        CheckError(AudioQueueEnqueueBuffer(self.audioQueue,
                                           buffers[i],
                                           0,
                                           NULL),
                   "Couldn't enqueue buffer (priming)");
    }
    
    CheckError(AudioQueueStart(self.audioQueue, NULL), "Couldn't start the AudioQueue");
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    
}

#pragma mark utility functions

static void CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) {
        return;
    }
    
    char errorString[20];
    // See if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else {
        // No, format is as an integer
        sprintf(errorString, "%d", (int)error);
    }
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    // Termate program
    exit(1);
}


@end
