//
//  OpusDecoder.h
//  OpusIPhoneTest
//
//  Created by Sam Leitch on 2012-12-07.
//  Copyright (c) 2012 Calgary Scientific Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface CSIOpusDecoder : NSObject

+ (CSIOpusDecoder*)decoderWithSampleRate:(double)sampleRate channels:(int)channels frameDuration:(double)frameDuration;

- (id)initWithSampleRate:(double)sampleRate channels:(int)channels frameDuration:(double)frameDuration;

- (void)decode:(NSData *)packet;

- (int)tryFillBuffer:(AudioBufferList *)audioBufferList;

@end
