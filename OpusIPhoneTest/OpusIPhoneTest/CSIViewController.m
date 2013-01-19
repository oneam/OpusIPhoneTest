//
//  CSIViewController.m
//  OpusIPhoneTest
//
//  Created by Sam Leitch on 2012-12-04.
//  Copyright (c) 2012 Calgary Scientific Inc. All rights reserved.
//

#import "CSIViewController.h"
#import "CSIOpusEncoder.h"
#import "CSIOpusDecoder.h"
#include "CSIDataQueue.h"
#import <AVFoundation/AVFoundation.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

const AudioUnitElement kInputBusNumber = 1;
const AudioUnitElement kOutputBusNumber = 0;
#define RECV_BUFFER_SIZE 1024

@interface CSIViewController ()

@property (strong) AVCaptureSession *captureSession;
@property (strong) AVCaptureDevice *camera;
@property (strong) AVCaptureVideoDataOutput *video;
@property (strong) AVCaptureVideoPreviewLayer *preview;

@property (strong) AVCaptureDevice *microphone;
@property (strong) AVCaptureAudioDataOutput *audio;

@property (assign) double sampleRate;
@property (assign) double frameDuration;
@property (assign) int samplesPerFrame;
@property (assign) int bytesPerSample;
@property (assign) int bytesPerFrame;

@property (assign) AUGraph audioGraph;
@property (assign) AudioComponentDescription ioUnitDesc;
@property (assign) AUNode ioNode;
@property (assign) AudioUnit ioUnit;
@property (assign) AudioBufferList *ioData;

@property (strong) CSIOpusEncoder *encoder;
@property (strong) CSIOpusDecoder *decoder;
@property (strong) dispatch_queue_t decodeQueue;

@property (assign) int socketFd;
@property (strong) dispatch_queue_t sendQueue;
@property (strong) dispatch_queue_t receiveQueue;
@property (strong) dispatch_source_t receiveSource;
@property (assign) void* receiveBuffer;

@end

OSStatus inputCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    CSIViewController *viewController = (__bridge CSIViewController *)inRefCon;
    AudioUnit ioUnit = viewController.ioUnit;
    ioData = viewController.ioData;
    OSStatus status = AudioUnitRender(ioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData);
    if(status != noErr) { NSLog(@"Failed to retrieve data from mic"); return noErr; }
    
    if(viewController.modeControl.selectedSegmentIndex != 0)
    {
        [viewController encodeAudio:ioData timestamp:inTimeStamp];
    }
    
    return noErr;
}

OSStatus renderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    CSIViewController *viewController = (__bridge CSIViewController *)inRefCon;

    int modeIndex = viewController.modeControl.selectedSegmentIndex;
    if(modeIndex == 0)
    {
        AudioBufferList *outputData = viewController.ioData;
        memcpy(ioData->mBuffers[0].mData, outputData->mBuffers[0].mData, ioData->mBuffers[0].mDataByteSize);
    }
    else
    {
        int bytesFilled = [viewController.decoder tryFillBuffer:ioData];
        if(bytesFilled <= 0)
        {
            memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
        }
    }

    return noErr;
}

@implementation CSIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.sampleRate = 48000;
    
    [self setupAudioSession];
    [self setupCaptureSession];
    [self setupVideoCapture];
    [self setupVideoPreview];
//    [self setupAudioCapture];
    [self setupAudioIOGraph];
    [self setupEncoder];
    [self setupDecoder];
    [self setupSocket];
    [self start];
    
    self.statusLabel.text = @"Running";
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setupAudioSession
{
    NSError *error;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setPreferredSampleRate:48000 error:&error];
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    [audioSession setPreferredIOBufferDuration:0.02 error:&error];
    [audioSession setActive:YES error:&error];
    
    double sampleRate = audioSession.sampleRate;
    double ioBufferDuration = audioSession.IOBufferDuration;
    int samplesPerFrame = (int)(ioBufferDuration * sampleRate) + 1;
    int bytesPerSample = sizeof(AudioSampleType);
    int bytesPerFrame = samplesPerFrame * bytesPerSample;

    self.sampleRate = sampleRate;
    self.frameDuration = ioBufferDuration;
    self.samplesPerFrame = samplesPerFrame;
    self.bytesPerSample = bytesPerSample;
    self.bytesPerFrame = bytesPerFrame;
}

- (void)setupCaptureSession
{
    self.captureSession = [AVCaptureSession new];
    self.captureSession.sessionPreset = AVCaptureSessionPreset352x288;
}

- (void)setupVideoCapture
{
    NSError *error;
    
    self.camera = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    
    if(!self.camera)
    {
        // TODO: Add error condition
    }
    
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:self.camera error:&error];
    
    if(!videoInput)
    {
        // TODO: Add error condition
    }
    
    [self.captureSession addInput:videoInput];
    
    self.video = [AVCaptureVideoDataOutput new];
    
    dispatch_queue_t videoQueue = dispatch_queue_create("VideoQueue", NULL);
    
    [self.video setSampleBufferDelegate:self queue:videoQueue];
    
    [self.captureSession addOutput:self.video];
}

- (void)setupVideoPreview
{    
    self.preview = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    // TODO: Add preview to display
}

- (void)setupAudioCapture
{
    NSError *error;
    
    self.microphone = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
    
    if(!self.microphone)
    {
        // TODO: Add error condition
    }
    
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:self.microphone error:&error];
    
    if(!audioInput)
    {
        // TODO: Add error condition
    }
    
    [self.captureSession addInput:audioInput];
    
    self.audio = [AVCaptureAudioDataOutput new];
    
    dispatch_queue_t audioQueue = dispatch_queue_create("AudioQueue", NULL);
    
    [self.audio setSampleBufferDelegate:self queue:audioQueue];
    
    [self.captureSession addOutput:self.audio];
}

- (void)setupAudioIOGraph
{
    OSStatus status = noErr;

    AUGraph audioGraph;
    status = NewAUGraph(&audioGraph);
    if(status != noErr) { NSLog(@"Failed to create audio graph"); return; }
    self.audioGraph = audioGraph;
    
    AudioComponentDescription ioUnitDesc;
    ioUnitDesc.componentType = kAudioUnitType_Output;
    ioUnitDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    ioUnitDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioUnitDesc.componentFlags = 0;
    ioUnitDesc.componentFlagsMask = 0;
    self.ioUnitDesc = ioUnitDesc;

    AUNode ioNode;
    status = AUGraphAddNode(audioGraph, &ioUnitDesc, &ioNode);
    if(status != noErr) { NSLog(@"Failed to add mic to audio graph"); return; }
    status = AUGraphOpen(audioGraph);
    if(status != noErr) { NSLog(@"Failed to open audio graph"); return; }
    self.ioNode = ioNode;
    
    AudioUnit ioUnit;
    status = AUGraphNodeInfo(audioGraph, ioNode, &ioUnitDesc, &ioUnit);
    if(status != noErr) { NSLog(@"Failed to get mic handle from audio graph"); return; }
    self.ioUnit = ioUnit;
    
    UInt32 ioEnabled = 1;
    status = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kInputBusNumber, &ioEnabled, sizeof(ioEnabled));
    if(status != noErr) { NSLog(@"Failed to set IO enabled on mic"); return; }
    
    size_t bytesPerSample = self.bytesPerSample;
    
    AudioStreamBasicDescription monoStreamFormat = {0};
    monoStreamFormat.mFormatID          = kAudioFormatLinearPCM;
    monoStreamFormat.mFormatFlags       = kAudioFormatFlagsCanonical;
    monoStreamFormat.mBytesPerPacket    = bytesPerSample;
    monoStreamFormat.mFramesPerPacket   = 1;
    monoStreamFormat.mBytesPerFrame     = bytesPerSample;
    monoStreamFormat.mChannelsPerFrame  = 1;
    monoStreamFormat.mBitsPerChannel    = 8 * bytesPerSample;
    monoStreamFormat.mSampleRate        = self.sampleRate;
    
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, kInputBusNumber, &monoStreamFormat, sizeof(monoStreamFormat));
    if(status != noErr) { NSLog(@"Failed to set stream format on mic"); return; }
    
    AURenderCallbackStruct inputCallbackStruct;
    inputCallbackStruct.inputProc        = &inputCallback;
    inputCallbackStruct.inputProcRefCon  = (__bridge void *)(self);
    status = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, kInputBusNumber, &inputCallbackStruct, sizeof(inputCallbackStruct));
    if(status != noErr) { NSLog(@"Failed to set input callback on mic"); return; }
    
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBusNumber, &monoStreamFormat, sizeof(monoStreamFormat));
    if(status != noErr) { NSLog(@"Failed to set stream format on speaker"); return; }
    
    AURenderCallbackStruct outputCallbackStruct;
    outputCallbackStruct.inputProc        = &renderCallback;
    outputCallbackStruct.inputProcRefCon  = (__bridge void *)(self);
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Output, kOutputBusNumber, &outputCallbackStruct, sizeof(outputCallbackStruct));
    if(status != noErr) { NSLog(@"Failed to set render callback on speaker"); return; }
    
    AudioBufferList *ioData = (AudioBufferList *)malloc(offsetof(AudioBufferList, mBuffers) + sizeof(AudioBuffer *));
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mNumberChannels = 1;
    ioData->mBuffers[0].mDataByteSize = self.bytesPerFrame;
    ioData->mBuffers[0].mData = malloc(self.bytesPerFrame);
    self.ioData = ioData;
    
    status = AUGraphInitialize(audioGraph);
    if(status != noErr) { NSLog(@"Failed to initialize audio graph"); return; }
}

- (void)setupEncoder
{
    
    self.encoder = [CSIOpusEncoder encoderWithSampleRate:self.sampleRate channels:1 frameDuration:0.01];
}

- (void)setupDecoder
{
    self.decoder = [CSIOpusDecoder decoderWithSampleRate:self.sampleRate channels:1 frameDuration:0.01];
    self.decodeQueue = dispatch_queue_create("Decode Queue", nil);
}

- (void)setupSocket
{
    int socketFd;
    
    socketFd = socket(AF_INET, SOCK_DGRAM, 0);
    if(socketFd < 0)
    {
        NSLog(@"Unable to create socket");
        return;
    }
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(31337);
    
    int bindResult = bind(socketFd,(struct sockaddr *) &addr,sizeof(addr));
    if(bindResult < 0)
    {
        NSLog(@"Unable to bind socket to port 31337");
        close(socketFd);
        return;
    }
    
    self.socketFd = socketFd;
    
    self.sendQueue = dispatch_queue_create("Send Queue", nil);
    
    self.receiveBuffer = malloc(RECV_BUFFER_SIZE);
    self.receiveQueue = dispatch_queue_create("Socket Queue", nil);
    self.receiveSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self.socketFd, 0, self.receiveQueue);
    dispatch_source_set_event_handler(self.receiveSource, ^{[self receivePacket];});
}

- (void)start
{
    [self.captureSession startRunning];
    
    OSStatus status;
    status = AUGraphStart(self.audioGraph);
    if(status != noErr) { NSLog(@"Failed to start audio graph"); return; }
    
    struct ip_mreq mreq;
    mreq.imr_multiaddr.s_addr = inet_addr("239.255.1.42");
    mreq.imr_interface.s_addr = htonl(INADDR_ANY);
    
    int addMembershipResult = setsockopt(self.socketFd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, sizeof(mreq));
    if (addMembershipResult < 0)
    {
        NSLog(@"Unable to listen on multicast port");
        return;
    }
    
    u_char loopback = 0;
    int loopbackResult = setsockopt(self.socketFd, IPPROTO_IP, IP_MULTICAST_LOOP, &loopback, sizeof(loopback));
    if(loopbackResult < 0)
    {
        NSLog(@"Error setting loopback on port");
        return;
    }
    
    socklen_t loopbackSize;
    loopbackResult = getsockopt(self.socketFd, IPPROTO_IP, IP_MULTICAST_LOOP, &loopback, &loopbackSize);
    if(loopback != 0 || loopbackResult < 0)
    {
        NSLog(@"Loopback is on when it shouldn't be");
    }
    
    dispatch_resume(self.receiveSource);
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDescription);
    
    if(mediaType == kCMMediaType_Video)
    {
        // TODO: process video
        // NSLog(@"Video sample");
    }
    else if(mediaType == kCMMediaType_Audio)
    {
        // This is not used as it does not provide different sample rates and the Audio graph is required for playback anyway.
        NSArray *encodedSamples = [self.encoder encodeSample:sampleBuffer];
        for (NSData *encodedSample in encodedSamples) {
            NSLog(@"Encoded %d bytes", encodedSample.length);
        }
    }
    
}

- (void)encodeAudio:(AudioBufferList *)data timestamp:(const AudioTimeStamp *)timestamp
{
    NSArray *encodedSamples = [self.encoder encodeBufferList:data];
    for (NSData *encodedSample in encodedSamples) {
//        NSLog(@"Encoded %d bytes", encodedSample.length);

        if(self.modeControl.selectedSegmentIndex == 1)
        {
            dispatch_async(self.decodeQueue, ^{[self.decoder decode:encodedSample];});
        }
        else
        {
            dispatch_async(self.sendQueue, ^{[self sendPacket:encodedSample];});
        }
    }
}

- (void)receivePacket
{
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(31337);

    socklen_t addrLength = sizeof(addr);
    ssize_t bytesReceived = recvfrom(self.socketFd, self.receiveBuffer, RECV_BUFFER_SIZE, 0, (struct sockaddr*)&addr, &addrLength);
    if(bytesReceived < 0)
    {
        NSLog(@"There was a problem receiving data");
        return;
    }
    
    if(self.modeControl.selectedSegmentIndex != 2) return;
    
//    NSLog(@"Received %zd bytes", bytesReceived);
    NSData* packet = [NSData dataWithBytesNoCopy:self.receiveBuffer length:bytesReceived freeWhenDone:NO];
    [self.decoder decode:packet];
}

- (void)sendPacket:(NSData*)packet
{
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr("239.255.1.42");
    addr.sin_port = htons(31337);
    
    ssize_t bytesSent = sendto(self.socketFd, packet.bytes, packet.length, 0, (struct sockaddr*)&addr, sizeof(addr));
    if(bytesSent < packet.length)
    {
        NSLog(@"There was a problem sending data");
    }
}

@end
