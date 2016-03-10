//
//  main.m
//  Recording
//
//  Created by paul on 16/2/20.
//  Copyright © 2016年 小普. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kNumberRecordBuffers 3

#pragma mark user data struct

typedef struct MyRecorder {
    AudioFileID recordFile;
    SInt64 recordPacket;
    Boolean running;
} MyRecorder;

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

static OSStatus MyGetDefaultInputDeviceSampleRate(Float64 *outSampleRate)
{
    OSStatus error;
    AudioDeviceID deviceID = 0;
    
    AudioObjectPropertyAddress propertyAddress;
    UInt32 propertySize;
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    propertyAddress.mSelector = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    propertySize = sizeof(AudioDeviceID);
    error = AudioHardwareServiceGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &propertySize, &deviceID);
    if (error) {
        return error;
    }
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    propertySize = sizeof(Float64);
    error = AudioHardwareServiceGetPropertyData(deviceID, &propertyAddress, 0, NULL, &propertySize, outSampleRate);
    return error;
}

static void MyCopyEncoderCookieToFile(AudioQueueRef queue, AudioFileID fileID)
{
    OSStatus error;
    UInt32 propertySize;
    
    error = AudioQueueGetPropertySize(queue, kAudioConverterCompressionMagicCookie, &propertySize);
    
    if (error == noErr && propertySize > 0) {
        Byte *magicCookie = (Byte *)malloc(propertySize);
        CheckError(AudioQueueGetProperty(queue,
                                         kAudioQueueProperty_MagicCookie,
                                         magicCookie, &propertySize),
                   "Couldn't get audio queue's magic cookie");
        
        CheckError(AudioFileSetProperty(fileID,
                                        kAudioFilePropertyMagicCookieData,
                                        propertySize,
                                        magicCookie),
                   "Couldn't set audio file's magic cookie");
        free(magicCookie);
    }
}

static int MyComputeRecordBufferSize(AudioStreamBasicDescription *asbd, AudioQueueRef queue, float seconds)
{
    int packets, frames, bytes;
    
    frames = (int)ceil(seconds * asbd->mSampleRate);
    
    if (asbd->mBytesPerFrame > 0) {
        bytes = frames * asbd->mBytesPerFrame;
    } else {
        UInt32 maxPacketSize;
        if (asbd->mBytesPerPacket > 0) {
            // Constant packet size
            maxPacketSize = asbd->mBytesPerPacket;
        } else {
            // Get the largest single packet size possible
            UInt32 propertySize = sizeof(maxPacketSize);
            CheckError(AudioQueueGetProperty(queue,
                                             kAudioConverterPropertyMaximumOutputPacketSize,
                                             &maxPacketSize,
                                             &propertySize),
                       "Couldn't get queue's maximun output packet size");
        }
        if (asbd->mFramesPerPacket > 0) {
            packets = frames / asbd->mFramesPerPacket;
        } else {
            // Worst-case scenario: 1 frame in a packet
            packets = frames;
        }
        // Sanity check
        if (packets == 0) {
            packets = 1;
        }
        bytes = packets * maxPacketSize;
    }
    return bytes;
}

#pragma mark record callback function

static void MyAQInputCallback(void *inUserData,
                              AudioQueueRef inQueue,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumPackets,
                              const AudioStreamPacketDescription *inPacketDesc)
{
    MyRecorder *recorder = (MyRecorder *)inUserData;
    
    if (inNumPackets > 0) {
        // Write packets to a file
        CheckError(AudioFileWritePackets(recorder->recordFile,
                                         FALSE,
                                         inBuffer->mAudioDataByteSize,
                                         inPacketDesc,
                                         recorder->recordPacket,
                                         &inNumPackets,
                                         inBuffer->mAudioData),
                   "AudioFileWritePackets failed");
        
        // Increment the packet index
        recorder->recordPacket += inNumPackets;
    }
    if (recorder->running) {
        CheckError(AudioQueueEnqueueBuffer(inQueue, inBuffer, 0, NULL), "AudioQueueEnqueueBuffer failed");
    }
}

#pragma mark main function

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        // Set up format
        MyRecorder recorder = { 0 };
        AudioStreamBasicDescription recordFormat;
        memset(&recordFormat, 0, sizeof(recordFormat));
        
        // Indicate that we want to record as stereo AAC
        recordFormat.mFormatID = kAudioFormatMPEG4AAC;
        recordFormat.mChannelsPerFrame = 2;
        
        // Avoid hardcoding for sample rate
//        MyGetDefaultInputDeviceSampleRate(&recordFormat.mSampleRate);
        recordFormat.mSampleRate = 44100;
        
        UInt32 propSize = sizeof(recordFormat);
        CheckError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                          0,
                                          NULL,
                                          &propSize,
                                          &recordFormat),
                   "AudioFormatGetProperty failed");
        
        // Set up queue
        AudioQueueRef queue = { 0 };
        CheckError(AudioQueueNewInput(&recordFormat,
                                      MyAQInputCallback,
                                      &recorder,
                                      NULL,
                                      NULL,
                                      0,
                                      &queue),
                   "AudioQueueNewInput failed");
        
        UInt32 size = sizeof(recordFormat);
        CheckError(AudioQueueGetProperty(queue,
                                         kAudioConverterCurrentOutputStreamDescription,
                                         &recordFormat,
                                         &size),
                   "Couldn't get queue's format");
        
        // Set up file
        CFURLRef myFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                           CFSTR("output.caf"),
                                                           kCFURLPOSIXPathStyle, false);
        CheckError(AudioFileCreateWithURL(myFileURL,
                                          kAudioFileCAFType,
                                          &recordFormat,
                                          kAudioFileFlags_EraseFile,
                                          &recorder.recordFile),
                   "AudioFileCreateWithURL failed");
        
        // Handle magic cookie
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        
        // Other setup as needed
        int bufferByteSize = MyComputeRecordBufferSize(&recordFormat, queue, 0.5);
        
        // Enqueuing
        int bufferIndex;
        for (bufferIndex = 0; bufferIndex < kNumberRecordBuffers; bufferIndex++) {
            AudioQueueBufferRef buffer;
            CheckError(AudioQueueAllocateBuffer(queue, bufferByteSize, &buffer), "AudioQueueAllocateBuffer failed");
            CheckError(AudioQueueEnqueueBuffer(queue, buffer, 0, NULL), "AudioQueueEnqueueBuffer failed");
        }
        // Start queue

        // Starting the audio queue, pass NULL start immediately
        recorder.running = TRUE;
        CheckError(AudioQueueStart(queue, NULL), "AudioQueueStart failed");
        
        // Blocking on stdin to continue recording
        printf("Recording, press <return> to stop:\n");
        getchar();
        
        // Stop queue
        printf("* recording done *\n");
        recorder.running = FALSE;
        CheckError(AudioQueueStop(queue, TRUE), "AudioQueueStop failed");
        
        // Recalling the magic cookie convenience function
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        
        // Cleaning up the audio queue and audio file
        AudioQueueDispose(queue, TRUE);
        AudioFileClose(recorder.recordFile);
    }
    return 0;
}
