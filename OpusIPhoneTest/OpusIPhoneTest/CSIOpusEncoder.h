//
//  CSIOpusAdapter.h
//  OpusIPhoneTest
//
//  Created by Sam Leitch on 2012-12-04.
//  Copyright (c) 2012 Calgary Scientific Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface CSIOpusEncoder : NSObject

+ (CSIOpusEncoder*)encoderWithSampleRate:(double)sampleRate channels:(int)channels frameDuration:(double)frameDuration;

- (id)initWithSampleRate:(double)sampleRate channels:(int)channels frameDuration:(double)frameDuration;

- (NSArray *)encodeSample:(CMSampleBufferRef)sampleBuffer;

- (NSArray *)encodeBufferList:(AudioBufferList *)audioBufferList;

@end
