
module gfx.vulkan.memory;

package:

import gfx.bindings.vulkan;

import gfx.core.rc;
import gfx.graal.memory;
import gfx.vulkan.device;

class VulkanDeviceMemory : VulkanDevObj!(VkDeviceMemory, "freeMemory"), DeviceMemory
{
    mixin(atomicRcCode);

    this(VkDeviceMemory vk, VulkanDevice dev, in MemProps props, in size_t size, in uint typeIndex)
    {
        super(vk, dev);
        _props = props;
        _size = size;
        _typeIndex = typeIndex;
    }

    override @property MemProps props() {
        return _props;
    }

    override @property size_t size() {
        return _size;
    }

    override @property uint typeIndex() {
        return _typeIndex;
    }

    void* map(in size_t offset, in size_t size) {
        void *data;
        vulkanEnforce(
            cmds.mapMemory(vkDev, vk, offset, size, 0, &data),
            "Could not map device memory"
        );
        return data;
    }

    void unmap() {
        cmds.unmapMemory(vkDev, vk);
    }

    private MemProps _props;
    private size_t _size;
    private uint _typeIndex;
}
