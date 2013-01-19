//
//  CSIDataQueue.h
//  OpusIPhoneTest
//
//  Created by Sam Leitch on 2012-12-13.
//  Copyright (c) 2012 Calgary Scientific Inc. All rights reserved.
//

#ifndef OpusIPhoneTest_CSIDataQueue_h
#define OpusIPhoneTest_CSIDataQueue_h
#include <stdlib.h>

typedef struct CSIDataQueueOpaque *CSIDataQueueRef;

CSIDataQueueRef CSIDataQueueCreate();
void CSIDataQueueClear(CSIDataQueueRef queue);
size_t CSIDataQueueEnqueue(CSIDataQueueRef queue, const void* data, size_t dataLength);
size_t CSIDataQueueDequeue(CSIDataQueueRef queue, void* data, size_t dataLength);
size_t CSIDataQueuePeek(CSIDataQueueRef queue, void* data, size_t dataLength);
size_t CSIDataQueueGetLength(CSIDataQueueRef queue);
void CSIDataQueueDestroy(CSIDataQueueRef queue);

int CSIDataQueueRunTests();

#endif
