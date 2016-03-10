//
//  main.m
//  Converter
//
//  Created by paul on 16/2/24.
//  Copyright © 2016年 小普. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kInputFileLocation CFSTR("/Users/paul/Desktop/AlmostLover.mp3")

#pragma mark user data struct

typedef struct MyAudioConverterSettings
{
    AudioStreamBasicDescription inputFormat;
    AudioStreamBasicDescription outputFormat;
    
    AudioFileID inputFile;
    AudioFileID outputFile;
    
    UInt64 inputFilePacketIndex;
    UInt64 inputFilePacketCount;
    UInt32 inputFilePacketMaxSize;
    AudioStreamPacketDescription *inputFilePacketDescriptions;
    
    void *sourceBuffer;
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

#pragma mark converter callback function

OSStatus MyAudioConverterCallback(AudioConverterRef inAudioConverter,
                                  UInt32 *ioDataPacketCount,
                                  AudioBufferList *ioData,
                                  AudioStreamPacketDescription **outDataPacketDescription,
                                  void *inUserData)
{
    MyAudioConverterSettings *audioConverterSettings = (MyAudioConverterSettings *)inUserData;
    
    ioData->mBuffers[0].mData = NULL;
    ioData->mBuffers[0].mDataByteSize = 0;
    
    // if there are not enough packets to satisfy request,
    // then read what's left
    if (audioConverterSettings->inputFilePacketIndex + *ioDataPacketCount > audioConverterSettings->inputFilePacketCount) {
        *ioDataPacketCount = audioConverterSettings->inputFilePacketCount - audioConverterSettings->inputFilePacketIndex;
    }
    if (*ioDataPacketCount == 0) {
        return noErr;
    }
    if (audioConverterSettings->sourceBuffer != NULL) {
        free(audioConverterSettings->sourceBuffer);
        audioConverterSettings->sourceBuffer = NULL;
    }
    
    audioConverterSettings->sourceBuffer = (void *)calloc(1, *ioDataPacketCount * audioConverterSettings->inputFilePacketMaxSize);
    
    UInt32 outByteCount = 0;
    OSStatus result = AudioFileReadPackets(audioConverterSettings->inputFile,
                                           true,
                                           &outByteCount,
                                           audioConverterSettings->inputFilePacketDescriptions,
                                           audioConverterSettings->inputFilePacketIndex,
                                           ioDataPacketCount,
                                           audioConverterSettings->sourceBuffer);
#ifdef MAC_OS_X_VERSION_10_7
    if (result == kAudioFileEndOfFileError && *ioDataPacketCount) {
        result = noErr;
    }
#else
    if (result == eofErr && *ioDataPacketCount) {
        result = noErr;
    }
#endif
    else if (result != noErr) {
        return result;
    }
    
    // updating the source file position and AudioBuffer members with the results of read
    audioConverterSettings->inputFilePacketIndex += *ioDataPacketCount;
    ioData->mBuffers[0].mData = audioConverterSettings->sourceBuffer;
    ioData->mBuffers[0].mDataByteSize = outByteCount;
    if (outDataPacketDescription) {
        *outDataPacketDescription = audioConverterSettings->inputFilePacketDescriptions;
    }
    return result;
}

void Convert(MyAudioConverterSettings *mySettings)
{
    // create the audioConverter object
    AudioConverterRef audioConverter;
    CheckError(AudioConverterNew(&mySettings->inputFormat, &mySettings->outputFormat, &audioConverter), "AudioConverterNew failed");

    UInt32 packetsPerBuffer = 0;
    UInt32 outputBufferSize = 32 * 1024; // 32KB is a good starting point
    UInt32 sizePerPacket = mySettings->inputFormat.mBytesPerPacket;
    if (sizePerPacket == 0) {
        UInt32 size = sizeof(sizePerPacket);
        CheckError(AudioConverterGetProperty(audioConverter,
                                             kAudioConverterPropertyMaximumOutputPacketSize,
                                             &size,
                                             &sizePerPacket),
                   "Could't get kAudioConverterPropertyMaximumOutputPacketSize");
        
        if (sizePerPacket > outputBufferSize) {
            outputBufferSize = sizePerPacket;
        }
        
        packetsPerBuffer = outputBufferSize / sizePerPacket;
        mySettings->inputFilePacketDescriptions = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * packetsPerBuffer);
    } else {
        // determining packets per buffer for constant bit rate data
        packetsPerBuffer = outputBufferSize / sizePerPacket;
    }
    
    UInt8 *outputBuffer = (UInt8 *)malloc(sizeof(UInt8) * outputBufferSize);
    // loop to convert and write data
    UInt32 outputFilePacketPosition = 0;
    while (1) {
        // preparing an AudioBufferList to receive converted data
        AudioBufferList convertedData;
        convertedData.mNumberBuffers = 1;
        convertedData.mBuffers[0].mNumberChannels = mySettings->inputFormat.mChannelsPerFrame;
        convertedData.mBuffers[0].mDataByteSize = outputBufferSize;
        convertedData.mBuffers[0].mData = outputBuffer;
        
        UInt32 ioOutputDatapackets = packetsPerBuffer;
        OSStatus error = AudioConverterFillComplexBuffer(audioConverter,
                                                         MyAudioConverterCallback,
                                                         mySettings,
                                                         &ioOutputDatapackets,
                                                         &convertedData,
                                                         (mySettings->inputFilePacketDescriptions ?
                                                          mySettings->inputFilePacketDescriptions : nil));
        if (error || !ioOutputDatapackets) {
            break; // This is the termination condition
        }
        // writing converted data to the output file
        CheckResult(AudioFileWritePackets(mySettings->outputFile,
                                          false,
                                          ioOutputDatapackets,
                                          NULL,
                                          outputFilePacketPosition /
                                          mySettings->outputFormat.mBytesPerPacket,
                                          &ioOutputDatapackets,
                                          convertedData.mBuffers[0].mData),
                    "Couldn't write packets to file");
        outputFilePacketPosition += (ioOutputDatapackets * mySettings->outputFormat.mBytesPerPacket);
    }
    // cleaning up the audio converter
    AudioConverterDispose(audioConverter);
}

#pragma mark main function

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Open input file
        
        MyAudioConverterSettings audioConverterSettings = { 0 };
        CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                              kInputFileLocation,
                                                              kCFURLPOSIXPathStyle,
                                                              false);
        CheckError(AudioFileOpenURL(inputFileURL,
                                    kAudioFileReadPermission,
                                    0,
                                    &audioConverterSettings.inputFile),
                   "AudioFileOpenURL failed");
        CFRelease(inputFileURL);
        
        // Get input format
        UInt32 propSize = sizeof(audioConverterSettings.inputFormat);
        CheckError(AudioFileGetProperty(audioConverterSettings.inputFile,
                                        kAudioFilePropertyDataFormat,
                                        &propSize,
                                        &audioConverterSettings.inputFormat),
                   "Couldn't get file's data format");
        
        // Set up output file
        // get the total number of packets in the file
        propSize = sizeof(audioConverterSettings.inputFilePacketCount);
        CheckError(AudioFileGetProperty(audioConverterSettings.inputFile,
                                        kAudioFilePropertyAudioDataPacketCount,
                                        &propSize,
                                        &audioConverterSettings.inputFilePacketCount),
                   "couldn't get file's packet count");
        
        // get size of the largest possible packet
        propSize = sizeof(audioConverterSettings.inputFilePacketMaxSize);
        CheckError(AudioFileGetProperty(audioConverterSettings.inputFile,
                                        kAudioFilePropertyMaximumPacketSize,
                                        &propSize,
                                        &audioConverterSettings.inputFilePacketMaxSize),
                   "couldn't get file's max packet size");
        // defining output ASBD and creating an output audio file
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
        CFRelease(outputFileURL);
        
        // calling a convenience Convert() function and closing file
        fprintf(stdout, "Converting...\n");
        Convert(&audioConverterSettings);
        
    cleanup:
        AudioFileClose(audioConverterSettings.inputFile);
        AudioFileClose(audioConverterSettings.outputFile);
        return 0;
    }
    return 0;
}
