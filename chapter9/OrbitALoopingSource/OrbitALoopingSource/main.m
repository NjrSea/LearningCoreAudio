//
//  main.m
//  OrbitALoopingSource
//
//  Created by paul on 16/3/15.
//  Copyright © 2016年 小普. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <OpenAL/OpenAL.h>

#define RUN_TIME 60.0
#define ORBIT_SPEED 10.0
#define LOOP_PATH CFSTR("/Users/paul/Desktop/AlmostLover.mp3")

#pragma mark user-data functions

typedef struct MyLoopPlayer {
    AudioStreamBasicDescription dataFormat;
    UInt16 *sampleBuffer;
    UInt32 bufferSizeBytes;
    ALuint sources[1];
} MyLoopPlayer;

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

static void CheckALError(const char *operation)
{
    ALenum alErr = alGetError();
    if (alErr == AL_NO_ERROR) {
        return;
    }
    char *errFormat = NULL;
    switch (alErr) {
        case AL_INVALID_NAME:
            errFormat = "OpenAL Error: %s (AL_INVALID_NAME)";
            break;
        case AL_INVALID_VALUE:
            errFormat = "OpenAL Error: %s (AL_INVALID_VALUE)";
            break;
        case AL_INVALID_ENUM:
            errFormat = "OpenAL Error: %s (AL_INVALID_ENUM)";
            break;
        case AL_INVALID_OPERATION:
            errFormat = "OpenAL Error: %s (AL_INVALID_OPERATION)";
            break;
        case AL_OUT_OF_MEMORY:
            errFormat = "OpenAL Error: %s (AL_OUT_OF_MEMORY)";
            break;
        default:
            break;
    }
    fprintf(stderr, errFormat, operation);
    exit(1);
}

void updateSourceLocation(MyLoopPlayer player)
{
    double theta = fmod(CFAbsoluteTimeGetCurrent() * ORBIT_SPEED, M_PI * 2);
    ALfloat x = 3 * cos(theta);
    ALfloat y = 0.5 * sin(theta);
    ALfloat z = 1.0 * sin(theta);
    alSource3f(player.sources[0], AL_POSITION, x, y, z);
}

OSStatus loadLoopIntoBuffer(MyLoopPlayer *player)
{
    CFURLRef loopFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, LOOP_PATH, kCFURLPOSIXPathStyle, false);
    ExtAudioFileRef extAudioFile;
    CheckError(ExtAudioFileOpenURL(loopFileURL, &extAudioFile), "Couldn't open ExtAudioFile for reading");
    
    // Describing the AL_FORMAT_MONO16 Format as an AudioStreamBasicDescription and Using it with an ExtAduioFile
    memset(&player->dataFormat, 0, sizeof(player->dataFormat));
    player->dataFormat.mFormatID = kAudioFormatLinearPCM;
    player->dataFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    player->dataFormat.mSampleRate = 44100.0;
    player->dataFormat.mChannelsPerFrame = 1;
    player->dataFormat.mFramesPerPacket = 1;
    player->dataFormat.mBitsPerChannel = 16;
    player->dataFormat.mBytesPerFrame = 2;
    player->dataFormat.mBytesPerPacket = 2;
    
    // Tell extAudioFile about our format
    CheckError(ExtAudioFileSetProperty(extAudioFile,
                                       kExtAudioFileProperty_ClientDataFormat,
                                       sizeof(AudioStreamBasicDescription),
                                       &player->dataFormat),
               "Couldn't set client format on ExtAudioFile");
    
    SInt64 fileLengthFrames;
    UInt32 propSize = sizeof(fileLengthFrames);
    ExtAudioFileGetProperty(extAudioFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &fileLengthFrames);
    
    AudioBufferList *buffers;
    UInt32 ablSize = offsetof(AudioBufferList, mBuffers[0]) + (sizeof(AudioBufferList) * 1);
    buffers = malloc(ablSize);
    
    player->sampleBuffer = malloc(sizeof(UInt16) *player->bufferSizeBytes);
    buffers->mNumberBuffers = 1;
    buffers->mBuffers[0].mNumberChannels = 1;
    buffers->mBuffers[0].mDataByteSize = player->bufferSizeBytes;
    buffers->mBuffers[0].mData = player->sampleBuffer;
    
    // Loop reading into the ABL until buffer is full
    UInt32 totalFramesRead = 0;
    do {
        UInt32 framesRead = fileLengthFrames - totalFramesRead;
        // While doing successive reads
        buffers->mBuffers[0].mData = player->sampleBuffer + (totalFramesRead * sizeof(UInt16));
        CheckError(ExtAudioFileRead(extAudioFile, &framesRead, buffers), "ExtAudioFileRead failed");
        totalFramesRead += framesRead;
        printf("read %d frames\n,", framesRead);
    } while (totalFramesRead < fileLengthFrames);
    free(buffers);
    return noErr;
}

#pragma mark main functions

int main(int argc, const char * argv[])
{
    MyLoopPlayer player;
    // Convert to an OpenAL-friendly format and read into memory
    CheckError(loadLoopIntoBuffer(&player),
               "Couldn't load loop into buffer");
    ALCdevice *alDevice = alcOpenDevice(NULL);
    CheckALError("Couldn't open AL device");
    ALCcontext *alContext = alcCreateContext(alDevice, 0);
    CheckALError("Couldn't open AL context");
    alcMakeContextCurrent(alContext);
    CheckALError("Couldn't make AL context current");
    
    // Set up OpenAL buffer
    ALuint buffers[1];
    alGenBuffers(1, buffers);
    CheckALError("Couldn't generate buffers");
    alBufferData(*buffers, AL_FORMAT_MONO16, player.sampleBuffer, player.bufferSizeBytes, player.dataFormat.mSampleRate);
    CheckALError("Couldn't buffer data");
    free(player.sampleBuffer);
    
    // Set up OpenAL source
    alGenSources(1, player.sources);
    CheckALError("Couldn't generate sources");
    alSourcei(player.sources[0], AL_LOOPING, AL_TRUE);
    CheckALError("Couldn't set source looping property");
    alSourcef(player.sources[0], AL_GAIN, AL_MAX_GAIN);
    CheckALError("Couldn't set source gain");
    
    updateSourceLocation(player);
    CheckALError("Couldn't set initial source position");
    
    // Connect buffer to source
    alSourcei(player.sources[0], AL_BUFFER, buffers[0]);
    CheckALError("Couldn't connect buffer to source");
    
    // Set up listener
    alListener3f(AL_POSITION, 0.0, 0.0, 0.0);
    CheckALError("Couldn't set listener position");
    
    // Start playing
    alSourcePlay(player.sources[0]);
    CheckALError("Couldn't play");
    
    // Loop and wait
    printf("Playing...\n");
    time_t startTime = time(NULL);
    
    do {
        // Get next theta
        updateSourceLocation(player);
        CheckALError("Couldn't set looping source position");
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
    } while (difftime(time(NULL), startTime) < RUN_TIME);
    
    // Clean up
    alSourceStop(player.sources[0]);
    alDeleteSources(1, player.sources);
    alDeleteBuffers(1, buffers);
    alcDestroyContext(alContext);
    alcCloseDevice(alDevice);
    return 0;
}
