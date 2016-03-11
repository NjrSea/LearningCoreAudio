//
//  main.m
//  AUGraphBasedPlayThrough
//
//  Created by paul on 16/3/10.
//  Copyright © 2016年 小普. All rights reserved.
//

#import <Foundation/Foundation.h>
//#import <AudioToolbox/AudioToolbox.h>
#include <AudioToolbox/AudioToolbox.h>
#import "TPCircularBuffer/TPCircularBuffer.h"
#import "TPCircularBuffer/TPCircularBuffer+AudioBufferList.h"

//#define PART_II

#pragma mark user-data struct

typedef struct MyAUGraphPlayer
{
    AudioStreamBasicDescription streamFormat;
    
    AUGraph graph;
    AudioUnit inputUnit;
    AudioUnit outputUnit;
#ifdef PART_II
    
#else
    
#endif
    
    AudioBufferList *inputBuffer;
    TPCircularBuffer *ringBuffer;
    
    Float64 firstInputSampleTime;
    Float64 firstOutSampleTime;
    Float64 inToOutSampleTimeOffset;
    
} MyAUGraphPlayer;

#pragma mark render procs

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

void CreateInputUnit(MyAUGraphPlayer *player)
{
    // Generates a description that matches audio HAL
    AudioComponentDescription inputCD = { 0 };
    inputCD.componentType = kAudioUnitType_Output;
    inputCD.componentSubType = kAudioUnitSubType_HALOutput;
    inputCD.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent comp = AudioComponentFindNext(NULL, &inputCD);
    if (comp == NULL) {
        printf("Can't get output unit");
        exit(-1);
    }
    
    CheckError(AudioComponentInstanceNew(comp,
                                         &player->inputUnit),
               "Couldn't open component for inputUnit");

    // Enabling I/O on Input AUHAL
    UInt32 disableFlag = 0;
    UInt32 enableFlag = 1;
    AudioUnitScope outputBus = 0;
    AudioUnitScope inputBus = 1;
    CheckError(AudioUnitSetProperty(player->inputUnit,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Input,
                                    inputBus,
                                    &enableFlag,
                                    sizeof(enableFlag)),
               "Couldn't disable output on I/O unit");
    
    CheckError(AudioUnitSetProperty(player->inputUnit,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Output,
                                    outputBus,
                                    &disableFlag,
                                    sizeof(enableFlag)),
               "Couldn't disable output on I/O unit");

    // Getting the Default Audio Input Dvice
    AudioDeviceID defaultDevice = kAudioObjectUnknown;
    UInt32 propertySize = sizeof(defaultDevice);
    AudioObjectPropertyAddress defaultDeviceProperty;
    defaultDeviceProperty.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    defaultDeviceProperty.mScope = kAudioObjectPropertyScopeGlobal;
    defaultDeviceProperty.mElement = kAudioObjectPropertyElementMaster;
    
    CheckError(AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                          &defaultDeviceProperty,
                                          0,
                                          NULL,
                                          &propertySize,
                                          &defaultDevice),
               "Couldn't get default input device");
    
    // Setting the Current Device Property of the AUHAL
    CheckError(AudioUnitSetProperty(player->inputUnit,
                                    kAudioOutputUnitProperty_CurrentDevice,
                                    kAudioUnitScope_Global,
                                    outputBus,
                                    &defaultDevice,
                                    sizeof(defaultDevice)),
               "Couldn't set default device on I/O unit");
    
    // Getting AudioStreamBasicDescription from Input AUHAL
    propertySize = sizeof(AudioStreamBasicDescription);
    CheckError(AudioUnitGetProperty(player->inputUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    inputBus,
                                    &player->streamFormat,
                                    &propertySize),
               "Couldn't get ASBD from input unit");
    
    // Adopting Hardware Input Sample Rate
    AudioStreamBasicDescription deviceFormat;
    CheckError(AudioUnitGetProperty(player->inputUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input,
                                    inputBus,
                                    &deviceFormat,
                                    &propertySize),
               "Couldn't get ASBD from input unit");
    
    player->streamFormat.mSampleRate = deviceFormat.mSampleRate;
    propertySize = sizeof(AudioStreamBasicDescription);
    CheckError(AudioUnitSetProperty(player->inputUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    inputBus,
                                    &player->streamFormat,
                                    propertySize),
               "Couldn't set ASBD on input unit");
    
    // Calculating Capture Buffer Size for an I/O Unit
    UInt32 bufferSizeFrames = 0;
    propertySize = sizeof(UInt32);
    CheckError(AudioUnitGetProperty(player->inputUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &bufferSizeFrames, &propertySize), "Couldn't get buffer frame size from input unit");
    UInt32 bufferSizeBytes = bufferSizeFrames * sizeof(Float32);
    
    // Allocate an AudioBufferList plus enough space for array of AudioBuffers
    UInt32 propsize = offsetof(AudioBufferList, mBuffers[0]) + (sizeof(AudioBuffer) * player->streamFormat.mChannelsPerFrame);
    
    // malloc buffer lists
    player->inputBuffer = (AudioBufferList *)malloc(propsize);
    player->inputBuffer->mNumberBuffers = player->streamFormat.mChannelsPerFrame;

    // Pre-malloc buffers for AduioBufferLists
    for (UInt32 i = 0; i < player->inputBuffer->mNumberBuffers; i++) {
        player->inputBuffer->mBuffers[i].mNumberChannels = 1;
        player->inputBuffer->mBuffers[i].mDataByteSize = bufferSizeBytes;
        player->inputBuffer->mBuffers[i].mData = malloc(bufferSizeBytes);
    }
    
    // Alloc ring buffer that will hold data between the two audio devices
    
    
}

void CreateMyAUGraph(MyAUGraphPlayer *player)
{
#ifdef PART_II
#else
#endif
}

#pragma mark main function

int main(int argc, const char * argv[])
{
    MyAUGraphPlayer player = { 0 };
    
    // Create the input unit
    CreateInputUnit(&player);
    
    // Build a graph with output unit
    CreateMyAUGraph(&player);
    
#ifdef PART_II
#else
#endif
    // Start playing
    CheckError(AudioOutputUnitStart(player.inputUnit), "AudioOutputUnitStart failed");
    CheckError(AUGraphStart(player.graph), "AUGraphStart failed");
    // And wait
    printf("Capturing, press <return> to stop:\n");
    getchar();
    
cleanup:
    AUGraphStop(player.graph);
    AUGraphUninitialize(player.graph);
    AUGraphClose(player.graph);
    
    return 0;
}
