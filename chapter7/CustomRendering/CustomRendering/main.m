//
//  main.m
//  CustomRendering
//
//  Created by paul on 16/3/9.
//  Copyright © 2016年 小普. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define sineFrequency 880.0

#pragma mark user-data struct

typedef struct MySineWavePlayer {
    AudioUnit outputUnit;
    double startingFrameCount;
} MySineWavePlayer;

#pragma mark callback function
// Insert Listing 7.34 here

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

OSStatus SineWaveRenderProc(void *inRefCon,
                            AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp,
                            UInt32 inBusNumber,
                            UInt32 inNumberFrames,
                            AudioBufferList *ioData)
{
    MySineWavePlayer *player = (MySineWavePlayer *)inRefCon;
    
    double j = player->startingFrameCount;
    double cycleLength = 44100. / sineFrequency;
    int frame = 0;
    for (frame = 0; frame < inNumberFrames; ++frame) {
        Float32 *data = (Float32 *)ioData->mBuffers[0].mData;
        (data)[frame] = (Float32)sin(2 * M_PI * (j / cycleLength));
        // copy to right  channel too
        data = (Float32 *)ioData->mBuffers[1].mData;
        (data)[frame] = (Float32)sin(2 * M_PI * (j / cycleLength));
        
        j += 1.0;
        if (j > cycleLength) {
            j -= cycleLength;
        }
    }
    
    player->startingFrameCount = j;
    return noErr;
}

void CreateAndConnectOutputUnit(MySineWavePlayer *player)
{
    // Generates a description that matches the output device (speakers)
    AudioComponentDescription outputCD = { 0 };
    outputCD.componentType = kAudioUnitType_Output;
    outputCD.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputCD.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Getting an Audio Unit with AudioComponentFindNext
    AudioComponent comp = AudioComponentFindNext(NULL, &outputCD);
    if (comp == NULL) {
        printf("can't get output unit");
        exit(-1);
    }
    CheckError(AudioComponentInstanceNew(comp,
                                         &player->outputUnit),
               "AudioComponentInstanceNew failed");
    
    // Register the render callback
    AURenderCallbackStruct input;
    input.inputProc = SineWaveRenderProc;
    input.inputProcRefCon = &player;
    CheckError(AudioUnitSetProperty(player->outputUnit,
                                    kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Input,
                                    0,
                                    &input, sizeof(input)),
               "AudioUnitSetProperty failed");
    
    // Initialize the unit
    CheckError(AudioUnitInitialize(player->outputUnit),
               "Couldn't initialize output unit");
    
}

#pragma mark main function

int main(int argc, const char * argv[])
{
    MySineWavePlayer player = { 0 };
    
    // Set up ouput unit and call back
    CreateAndConnectOutputUnit(&player);
    
    // Start playing
    CheckError(AudioOutputUnitStart(player.outputUnit), "Couldn't start output unit");
    
    // Play for 5 seconds
    sleep(5);
    // Clean up
cleanup:
    
    AudioOutputUnitStop(player.outputUnit);
    AudioUnitInitialize(player.outputUnit);
    AudioComponentInstanceDispose(player.outputUnit);
    
    return 0;
}
