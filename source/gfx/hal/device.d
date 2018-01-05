module gfx.hal.device;

import gfx.core.rc;
import gfx.hal.memory;
import gfx.hal.queue;

struct DeviceFeatures {}

struct DeviceLimits {}

enum DeviceType {
    other,
    integratedGpu,
    discreteGpu,
    virtualGpu,
    cpu
}

/// A request for a specific queue and its priority level when opening a device.
struct QueueRequest
{
    uint familyIndex;
    float priority;
}

/// Represent a physical device. This interface is meant to describe the device
/// and open it.
interface PhysicalDevice : AtomicRefCounted
{
    @property uint apiVersion();
    @property uint driverVersion();
    @property uint vendorId();
    @property uint deviceId();
    @property string name();
    @property DeviceType type();
    @property DeviceFeatures features();
    @property DeviceLimits limits();
    @property MemoryProperties memoryProperties();
    @property QueueFamily[] queueFamilies();

    /// Open a device with the specified queues.
    /// Returns: null if it can't meet all requested queues, the opened device otherwise.
    Device open(in QueueRequest[] queues)
    in {
        assert(queues.isConsistentWith(queueFamilies));
    }
}

/// Checks that the requests are consistent with families
private bool isConsistentWith(in QueueRequest[] requests, in QueueFamily[] families)
{
    // TODO
    return true;
}

/// Handle to a physical device
interface Device : AtomicRefCounted
{
    DeviceMemory allocateMemory(uint memPropIndex, size_t size);
}
