/*
 HIDShim.c
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

#include "HIDShim.h"
#include <mach/mach_time.h>

// IOHIDDeviceGetValue returns an *unowned* (not retained) IOHIDValueRef.
// Swift imports it with a non-optional Unmanaged out-parameter, which makes it
// impossible to express that ownership rule correctly — releasing the value
// crashes inside IOHIDValueGetIntegerValue. Do the read here instead.

static unsigned long long kb_now_ticks(void) {
    return (unsigned long long)mach_absolute_time();
}

static double kb_ticks_to_seconds(unsigned long long ticks) {
    static mach_timebase_info_data_t info;
    static int ready = 0;
    if (!ready) { mach_timebase_info(&info); ready = 1; }
    if (info.denom == 0) return 0;
    return (double)ticks * (double)info.numer / (double)info.denom / 1e9;
}

static IOReturn kb_extract(IOHIDValueRef value, int *outValue, unsigned long long *outAgeSeconds) {
    unsigned long long stamp = (unsigned long long)IOHIDValueGetTimeStamp(value);
    if (stamp == 0) {
        // Never received: the element's 0 is a placeholder, not a reading.
        *outValue = -1;
        *outAgeSeconds = 0;
        return kIOReturnSuccess;
    }
    *outValue = (int)IOHIDValueGetIntegerValue(value);
    unsigned long long now = kb_now_ticks();
    *outAgeSeconds = (stamp > now) ? 0 : (unsigned long long)kb_ticks_to_seconds(now - stamp);
    return kIOReturnSuccess;
}

IOReturn KBHIDReadCachedValueEx(IOHIDDeviceRef device, IOHIDElementRef element,
                                int *outValue, unsigned long long *outAgeSeconds) {
    IOHIDValueRef value = NULL;
    IOReturn rc = IOHIDDeviceGetValue(device, element, &value);
    if (rc != kIOReturnSuccess || value == NULL) {
        *outValue = -1;
        *outAgeSeconds = 0;
        return rc == kIOReturnSuccess ? kIOReturnNoDevice : rc;
    }
    return kb_extract(value, outValue, outAgeSeconds);
}

// A live answer has an age of 0, which is what lets it beat a stale cached value.
IOReturn KBHIDReadFreshValueEx(IOHIDDeviceRef device, IOHIDElementRef element,
                               int *outValue, unsigned long long *outAgeSeconds) {
    IOHIDValueRef value = NULL;
    IOReturn rc = IOHIDDeviceGetValueWithOptions(device, element, &value,
                                                 kIOHIDDeviceGetValueWithUpdate);
    if (rc != kIOReturnSuccess || value == NULL) {
        *outValue = -1;
        *outAgeSeconds = 0;
        return rc == kIOReturnSuccess ? kIOReturnNoDevice : rc;
    }
    return kb_extract(value, outValue, outAgeSeconds);
}
