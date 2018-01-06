/// Vulkan device module
module gfx.backend.vulkan.device;

package:

import erupted;

import gfx.backend.vulkan;
import gfx.backend.vulkan.error;
import gfx.backend.vulkan.memory;
import gfx.core.rc;
import gfx.hal.device;
import gfx.hal.memory;

final class VulkanDevice : Device
{
    mixin(atomicRcCode);

    this (VkDevice vk, VulkanPhysicalDevice pd)
    {
        _vk = vk;
        _pd = pd;
        _pd.retain();
    }

    override void dispose() {
        vkDestroyDevice(_vk, null);
        _vk = null;
        _pd.release();
        _pd = null;
    }

    @property VkDevice vk() {
        return _vk;
    }

    override DeviceMemory allocateMemory(uint memTypeIndex, size_t size)
    {
        VkMemoryAllocateInfo mai;
        mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize = size;
        mai.memoryTypeIndex = memTypeIndex;

        VkDeviceMemory vkMem;
        vulkanEnforce(vkAllocateMemory(_vk, &mai, null, &vkMem), "Could not allocate device memory");

        return new VulkanDeviceMemory(vkMem, this, memTypeIndex, size);
    }

    VkDevice _vk;
    VulkanPhysicalDevice _pd;
}
