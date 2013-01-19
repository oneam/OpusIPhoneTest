//
//  OpusDecoder.m
//  OpusIPhoneTest
//
//  Created by Sam Leitch on 2012-12-07.
//  Copyright (c) 2012 Calgary Scientific Inc. All rights reserved.
//

#import "CSIOpusDecoder.h"
#include "CSIDataQueue.h"
#include "opus.h"

@interface CSIOpusDecoder ()
@property (assign) OpusDecoder *decoder;
@property (assign) double sampleRate;
@property (assign) double frameDuration;
@property (assign) int samplesPerFrame;
@property (assign) size_t bytesPerSample;
@property (assign) CSIDataQueueRef outputBuffer;
@property (assign) opus_int16 *decodeBuffer;
@end


@implementation CSIOpusDecoder

+ (CSIOpusDecoder*)decoderWithSampleRate:(double)sampleRate channels:(int)channels frameDuration:(double)frameDuration
{
    return [[CSIOpusDecoder alloc] initWithSampleRate:sampleRate channels:channels frameDuration:frameDuration];
}

- (id)initWithSampleRate:(double)sampleRate channels:(int)channels frameDuration:(double)frameDuration
{
    self = [super init];
    
    if(self)
    {
        
        NSLog(@"Creating an encoder using Opus version %s", opus_get_version_string());
        
        int error;
        _decoder = opus_decoder_create(sampleRate, channels, &error);
        
        if(error != OPUS_OK)
        {
            NSLog(@"Opus encoder encountered an error %s", opus_strerror(error));
            return nil;
        }
        
        _sampleRate = sampleRate;
        _frameDuration = frameDuration;
        _bytesPerSample = sizeof(opus_int16);
        _samplesPerFrame = (int)(sampleRate * frameDuration);
        
        _outputBuffer = CSIDataQueueCreate();
        _decodeBuffer = malloc(_bytesPerSample * _samplesPerFrame);
    }
    
    return self;
}

- (void)dealloc
{
    free(_decodeBuffer);
    CSIDataQueueDestroy(_outputBuffer);
}

- (void)decode:(NSData *)packet
{
    int result = opus_decode(self.decoder, packet.bytes, packet.length, self.decodeBuffer, self.samplesPerFrame, 0);
    if(result < 0)
    {
        NSLog(@"Opus decoder encountered an error %s", opus_strerror(result));
        return;
    }
    
    @synchronized(self)
    {
        size_t bytesAvailable = result * self.bytesPerSample;
        CSIDataQueueEnqueue(self.outputBuffer, self.decodeBuffer, bytesAvailable);
        
        double bufferDuration = CSIDataQueueGetLength(self.outputBuffer) / self.sampleRate;
        if(bufferDuration > 0.5)
        {
            NSLog(@"Output queue at %fs. Clearing.", bufferDuration);
            CSIDataQueueClear(self.outputBuffer);
        }
    }
}

- (int)tryFillBuffer:(AudioBufferList *)audioBufferList
{
    uint totalBytesRequested = 0;
    for (int i=0; i < audioBufferList->mNumberBuffers; ++i)
    {
        AudioBuffer audioBuffer = audioBufferList->mBuffers[i];
        if(audioBuffer.mNumberChannels > 1) return NO;
        totalBytesRequested += audioBuffer.mDataByteSize;
    }
    
    if(totalBytesRequested == 0) return 0;
    
    @synchronized(self)
    {
        int bytesAvailable = CSIDataQueueGetLength(self.outputBuffer);
        if(bytesAvailable < totalBytesRequested)
        {
//            NSLog(@"Couldnt fill buffer. Needed %d bytes but only have %d", totalBytesRequested, bytesAvailable);
            return 0;
        }
        
        for (int i=0; i < audioBufferList->mNumberBuffers; ++i)
        {
            AudioBuffer audioBuffer = audioBufferList->mBuffers[i];
            CSIDataQueueDequeue(self.outputBuffer, audioBuffer.mData, audioBuffer.mDataByteSize);
        }
        
        return totalBytesRequested;
    }
}


@end
