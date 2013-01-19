//
//  CSIOpusAdapter.m
//  OpusIPhoneTest
//
//  Created by Sam Leitch on 2012-12-04.
//  Copyright (c) 2012 Calgary Scientific Inc. All rights reserved.
//

#import "CSIOpusEncoder.h"
#include "CSIDataQueue.h"
#include "opus.h"
#define BUFFER_LENGTH 4096

@interface CSIOpusEncoder ()
@property (assign) OpusEncoder *encoder;
@property (assign) double frameDuration;
@property (assign) int bytesPerFrame;
@property (assign) int samplesPerFrame;
@property (assign) CSIDataQueueRef inputBuffer;
@property (assign) opus_int16 *frameBuffer;
@property (assign) void *encodeBuffer;
@end

@implementation CSIOpusEncoder

- (id)initWithSampleRate:(double)sampleRate channels:(int)channels frameDuration:(double)frameDuration
{
    self = [super init];
    
    if(self)
    {
        
        NSLog(@"Creating an encoder using Opus version %s", opus_get_version_string());
        
        int error;
        self.encoder = opus_encoder_create(sampleRate, channels, OPUS_APPLICATION_VOIP, &error);
        
        if(error != OPUS_OK)
        {
            NSLog(@"Opus encoder encountered an error %s", opus_strerror(error));
        }

        self.frameDuration = frameDuration;
        self.samplesPerFrame = (int)(sampleRate * frameDuration);
        int bytesPerSample = sizeof(opus_int16);
        self.bytesPerFrame = self.samplesPerFrame * bytesPerSample;
        
        self.inputBuffer = CSIDataQueueCreate();
        self.encodeBuffer = malloc(BUFFER_LENGTH);
        self.frameBuffer = malloc(self.bytesPerFrame);
    }

    return self;
}

+ (CSIOpusEncoder *)encoderWithSampleRate:(double)sampleRate channels:(int)channels frameDuration:(double)frameDuration
{
    CSIOpusEncoder *encoder = [[CSIOpusEncoder alloc] initWithSampleRate:sampleRate channels:channels frameDuration:frameDuration];
    return encoder;
}

- (NSArray *)encodeSample:(CMSampleBufferRef)sampleBuffer
{
//    CMItemCount numSamplesInBuffer = CMSampleBufferGetNumSamples(sampleBuffer);
//    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
//    Float64 durationInSeconds = CMTimeGetSeconds(duration);
//    NSLog(@"The sample rate is %f", numSamplesInBuffer / durationInSeconds);

    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    AudioBufferList audioBufferList;
     
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer,
                                                            NULL,
                                                            &audioBufferList,
                                                            sizeof(audioBufferList),
                                                            NULL,
                                                            NULL,
                                                            kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                                                            &blockBuffer);
    
    
    return [self encodeBufferList:&audioBufferList];
}

- (NSArray *)encodeBufferList:(AudioBufferList *)audioBufferList
{
    NSMutableArray *output = [NSMutableArray array];
    
    for (int i=0; i < audioBufferList->mNumberBuffers; ++i) {
        AudioBuffer audioBuffer = audioBufferList->mBuffers[i];
        CSIDataQueueEnqueue(self.inputBuffer, audioBuffer.mData, audioBuffer.mDataByteSize);
    }
    
    while (CSIDataQueueGetLength(self.inputBuffer) > self.bytesPerFrame) {
        CSIDataQueueDequeue(self.inputBuffer, self.frameBuffer, self.bytesPerFrame);
        opus_int32 result = opus_encode(self.encoder, self.frameBuffer, self.samplesPerFrame, self.encodeBuffer, BUFFER_LENGTH);
        
        if(result < 0) {
            NSLog(@"Opus encoder encountered an error %s", opus_strerror(result));
            return nil;
        }
        
        NSData *encodedData = [NSData dataWithBytes:self.encodeBuffer length:result];
        [output addObject:encodedData];
    }
    
    return output;
}

- (void)dealloc
{
    free(self.encodeBuffer);
    free(self.frameBuffer);
    CSIDataQueueDestroy(self.inputBuffer);
    opus_encoder_destroy(self.encoder);
}

@end
