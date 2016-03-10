//
//  main.m
//  ExtendConverter
//
//  Created by paul on 16/2/25.
//  Copyright © 2016年 小普. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kInputFileLocation CFSTR("/Users/paul/Desktop/AlmostLover.mp3")

#pragma mark user data struct

typedef struct MyAudioConverterSettings {
    AudioStreamBasicDescription outputFormat;
    ExtAudioFileRef inputFile;
    AudioFileID outputFile;
} MyAudioConverterSettings;

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

// Insert Listing 6.28-6.34 here
void Convert(MyAudioConverterSettings *mySettings)
{
    // 32KB is a good starting point
    UInt32 outputBufferSize = 32 * 1024;
    UInt32 sizePerPacket = mySettings->outputFormat.mBytesPerPacket;
    UInt32 packetsPerBuffer = outputBufferSize / sizePerPacket;
    
    UInt8 *outputBuffer = (UInt8 *)malloc(sizeof(UInt8) * outputBufferSize);
    uint32 outputFilePacketPosition = 0; // In bytes
    
    while (1) {
        AudioBufferList convertedData;
        convertedData.mNumberBuffers = 1;
        convertedData.mBuffers[0].mNumberChannels = mySettings->outputFormat.mChannelsPerFrame;
        convertedData.mBuffers[0].mDataByteSize = outputBufferSize;
        convertedData.mBuffers[0].mData = outputBuffer;
        
        // Reading and converting with ExtAudioFileRead
        UInt32 frameCount = packetsPerBuffer;
        CheckError(ExtAudioFileRead(mySettings->inputFile,
                                    &frameCount,
                                    &convertedData),
                   "Couldn't read from input file");
        // Terminating if no frames are read
        if (frameCount == 0) {
            printf("Done reading from file\n");
            return;
        }
        
        CheckError(AudioFileWritePackets(mySettings->outputFile,
                                         false,
                                         frameCount,
                                         NULL,
                                         outputFilePacketPosition / mySettings->outputFormat.mBytesPerPacket,
                                         &frameCount,
                                         convertedData.mBuffers[0].mData),
                   "Couldn't write packets to file");
        outputFilePacketPosition += (frameCount * mySettings->outputFormat.mBytesPerPacket);
    }
}

#pragma mark main function

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Open input file
        MyAudioConverterSettings audioConverterSettings = { 0 };
        
        // Open the input with ExtAudioFile
        CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kInputFileLocation, kCFURLPOSIXPathStyle, false);
        CheckError(ExtAudioFileOpenURL(inputFileURL, &audioConverterSettings.inputFile), "ExtAudioFileOpenURL failed");
        
        // Set up output file
        audioConverterSettings.outputFormat.mSampleRate = 44100.0;
        audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM;
        audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        audioConverterSettings.outputFormat.mBytesPerPacket = 4;
        audioConverterSettings.outputFormat.mFramesPerPacket = 1;
        audioConverterSettings.outputFormat.mBytesPerFrame = 4;
        audioConverterSettings.outputFormat.mChannelsPerFrame = 2;
        audioConverterSettings.outputFormat.mBitsPerChannel = 16;
        
        CFURLRef outputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                               CFSTR("output.aif"),
                                                               kCFURLPOSIXPathStyle,
                                                               false);
        CheckError(AudioFileCreateWithURL(outputFileURL,
                                          kAudioFileAIFFType,
                                          &audioConverterSettings.outputFormat,
                                          kAudioFileFlags_EraseFile,
                                          &audioConverterSettings.outputFile),
                   "AudioFileCreateWithURL failed");
        
        // Setting the client data format property on an extended audio file
        CheckError(ExtAudioFileSetProperty(audioConverterSettings.inputFile,
                                           kExtAudioFileProperty_ClientDataFormat,
                                           sizeof(AudioStreamBasicDescription), &
                                           audioConverterSettings.outputFile),
                   "Couldn't set client data format on input ext file");
        
        // Perform conversion
        fprintf(stdout, "Converting...\n");
        Convert(&audioConverterSettings);
        
    cleanup:
        ExtAudioFileDispose(audioConverterSettings.inputFile);
        AudioFileClose(audioConverterSettings.outputFile);
    }
    return 0;
}
