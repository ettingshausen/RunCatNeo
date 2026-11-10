/*
 HIDShim.h
 HIDShim

 Created by ettingshausen on 2026/11/11.
 Copyright 2026 ettingshausen

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#ifndef HIDSHIM_H
#define HIDSHIM_H

#include <IOKit/hid/IOHIDLib.h>

/// Reads the driver's cached value of the element together with its age.
/// outValue is -1 when no report has ever been received, so the element's
/// placeholder 0 is never mistaken for a real reading.
/// outAgeSeconds is the report's age in seconds.
IOReturn KBHIDReadCachedValueEx(IOHIDDeviceRef device, IOHIDElementRef element,
                                int *outValue, unsigned long long *outAgeSeconds);

/// Same read but asks the device for a fresh report first. Blocks until the
/// device answers, so callers must stay off the main thread.
IOReturn KBHIDReadFreshValueEx(IOHIDDeviceRef device, IOHIDElementRef element,
                               int *outValue, unsigned long long *outAgeSeconds);

#endif
