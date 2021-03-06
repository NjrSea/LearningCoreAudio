//
//  main.m
//  FirstAudioUnit
//
//  Created by paul on 16/2/29.
//  Copyright © 2016年 小普. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kInputFileLocation CFSTR("/Users/paul/Desktop/AlmostLover.mp3")

#pragma mark user-data struct

typedef struct MyAUGraphPlayer
{
    AudioStreamBasicDescription inputFormat;
    AudioFileID inputFile;
    AUGraph graph;
    AudioUnit fileAU;
} MyAUGraphPlayer;

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

void CreateMyAUGraph(MyAUGraphPlayer *player)
{
    // Create a new AUGraph
    CheckError(NewAUGraph(&player->graph), "NewAUGraph failed");
    
    // Generate desciption that matches output devece (speakers)
    AudioComponentDescription outputCD = { 0 };
    outputCD.componentType = kAudioUnitType_Output;
    outputCD.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputCD.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Adds a node with above desciption to the graph
    AUNode outputNode;
    CheckError(AUGraphAddNode(player->graph,
                              &outputCD,
                              &outputNode),
               "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed");
    
    // Generate description that matches a generator AU of type:
    // audio file player
    AudioComponentDescription fileplayerCD = { 0 };
    fileplayerCD.componentType = kAudioUnitType_Generator;
    fileplayerCD.componentSubType = kAudioUnitSubType_AudioFilePlayer;
    fileplayerCD.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Adds a node with above description to the graph
    AUNode fileNode;
    CheckError(AUGraphAddNode(player->graph, 
                              &fileplayerCD, 
                              &fileNode), 
               "AUGraphAddNode[kAudioUnitSubType_AudioFilePlayer] failed");

    // Opening the graph opens all contained audio units but does
    // not allocate any resources yet
    CheckError(AUGraphOpen(player->graph), "AUGraphOpen failed");
    
    // Get the refrence to the AudioUnit object for the
    // file player graph node
    CheckError(AUGraphNodeInfo(player->graph, 
                               fileNode, 
                               NULL, 
                               &player->fileAU),
               "AUGraphNodeInfo failed");
    
    // Connect the output source of the file player AU to
    // the input source of the output code
    CheckError(AUGraphConnectNodeInput(player->graph,
                                       fileNode,
                                       0,
                                       outputNode,
                                       0),
               "AUGraphConnectNodeInput");
    
    // Now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(player->graph),
               "AUGraphInitialize failed");
    
    
}

Float64 PrepareFileAU(MyAUGraphPlayer *player)
{
    // Tell the file player unit to load the file we want to play
    CheckError(AudioUnitSetProperty(player->fileAU,
                                    kAudioUnitProperty_ScheduledFileIDs,
                                    kAudioUnitScope_Global,
                                    0,
                                    &player->inputFile,
                                    sizeof(player->inputFile)),
               "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileIDs] failed");
    
    UInt64 nPackets;
    UInt32 propsize = sizeof(nPackets);
    CheckError(AudioFileGetProperty(player->inputFile,
                                    kAudioFilePropertyAudioDataPacketCount,
                                    &propsize,
                                    &nPackets),
               "AudioFileGetProperty[kAudioFilePropertyAudioDataPacketCount] failed");
    // Tell the file player AU to play the entire file
    ScheduledAudioFileRegion rgn;
    memset(&rgn.mTimeStamp, 0, sizeof(rgn.mTimeStamp));
    rgn.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
    rgn.mTimeStamp.mSampleTime = 0;
    rgn.mCompletionProc = NULL;
    rgn.mCompletionProcUserData = NULL;
    rgn.mAudioFile = player->inputFile;
    rgn.mLoopCount = 1;
    rgn.mStartFrame = 0;
    rgn.mFramesToPlay = nPackets * player->inputFormat.mFramesPerPacket;
    
    
    CheckError(AudioUnitSetProperty(player->fileAU,
                                    kAudioUnitProperty_ScheduledFileRegion,
                                    kAudioUnitScope_Global,
                                    0,
                                    &rgn,
                                    sizeof(rgn)),
               "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileRegion] failed");
    
    // Tell the file player AU when to start playing (-1 sample time means next render cycle
    AudioTimeStamp startTime;
    memset(&startTime, 0, sizeof(startTime));
    startTime.mFlags = kAudioTimeStampSampleTimeValid;
    startTime.mSampleTime = -1;
    
    CheckError(AudioUnitSetProperty(player->fileAU,
                                    kAudioUnitProperty_ScheduleStartTimeStamp,
                                    kAudioUnitScope_Global,
                                    0,
                                    &startTime,
                                    sizeof(startTime)),
               "AudioUnitSetProperty[kAudioUnitProperty_ScheduleStartTimeStamp] failed");

    // File duration
    return (nPackets * player->inputFormat.mFramesPerPacket) / player->inputFormat.mSampleRate;
}

#pragma mark main function

int main(int argc, const char * argv[])
{
    CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                          kInputFileLocation,
                                                          kCFURLPOSIXPathStyle,
                                                          FALSE);
    MyAUGraphPlayer player = { 0 };
    
    // Open the input audio file
    CheckError(AudioFileOpenURL(inputFileURL,
                                kAudioFileReadPermission,
                                0,
                                &player.inputFile),
               "AudioFileOpenURL failed");
    CFRelease(inputFileURL);
    
    // Get the audio data format from the file
    UInt32 propSize = sizeof(player.inputFormat);
    CheckError(AudioFileGetProperty(player.inputFile,
                                    kAudioFilePropertyDataFormat,
                                    &propSize,
                                    &player.inputFormat),
               "Couldn't get file's data format");
    
    // Build a basic fileplayer->speakers graph
    CreateMyAUGraph(&player);
    // Configure the file player
    Float64 fileDuration = PrepareFileAU(&player);

    // Start playing
    CheckError(AUGraphStart(player.graph), "AUGraphStart failed");
    // Sleep until the file is finished
    usleep((int)(fileDuration * 1000.0 * 1000.0));
    
cleanup:
    AUGraphStop(player.graph);
    AUGraphUninitialize(player.graph);
    AUGraphClose(player.graph);
    AudioFileClose(player.inputFile);
    
    return 0;
}
