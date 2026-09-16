#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7
};
typedef uint32_t MTTouchState;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    MTTouchState state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector;
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

typedef void *MTDeviceRef;

CFArrayRef MTDeviceCreateList(void);
MTDeviceRef MTDeviceCreateDefault(void);
void MTDeviceRelease(MTDeviceRef device);

OSStatus MTDeviceStart(MTDeviceRef device, int options);
OSStatus MTDeviceStop(MTDeviceRef device);
bool MTDeviceIsRunning(MTDeviceRef device);
bool MTDeviceIsBuiltIn(MTDeviceRef device);
bool MTDeviceIsOpaqueSurface(MTDeviceRef device);

OSStatus MTDeviceGetSensorSurfaceDimensions(MTDeviceRef device, int *width, int *height);
OSStatus MTDeviceGetFamilyID(MTDeviceRef device, int *familyID);
OSStatus MTDeviceGetDeviceID(MTDeviceRef device, uint64_t *deviceID);
OSStatus MTDeviceGetDriverType(MTDeviceRef device, int *driverType);

typedef void (*MTFrameCallbackFunction)(
    MTDeviceRef device,
    MTTouch *touches,
    size_t numTouches,
    double timestamp,
    size_t frame
);

void MTRegisterContactFrameCallback(MTDeviceRef device, MTFrameCallbackFunction callback);
void MTUnregisterContactFrameCallback(MTDeviceRef device, MTFrameCallbackFunction callback);
