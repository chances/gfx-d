/// Vulkan command module
module gfx.vulkan.cmd;

package:

import gfx.bindings.vulkan;

import gfx.core.rc;
import gfx.core.typecons;
import gfx.graal.cmd;
import gfx.graal.renderpass;
import gfx.vulkan.buffer;
import gfx.vulkan.conv;
import gfx.vulkan.device;
import gfx.vulkan.error;
import gfx.vulkan.image;
import gfx.vulkan.renderpass;

import std.typecons : Flag;

class VulkanCommandPool : VulkanDevObj!(VkCommandPool, "DestroyCommandPool"), CommandPool
{
    mixin(atomicRcCode);

    this (VkCommandPool pool, VulkanDevice dev) {
        super(pool, dev);
    }

    override void reset() {
        vulkanEnforce(vk.ResetCommandPool(vkDev, vkObj, 0), "Could not reset command buffer");
    }

    override CommandBuffer[] allocate(size_t count) {
        VkCommandBufferAllocateInfo cbai;
        cbai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cbai.commandPool = vkObj;
        cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cbai.commandBufferCount = cast(uint)count;

        auto vkBufs = new VkCommandBuffer[count];
        vulkanEnforce(
            vk.AllocateCommandBuffers(vkDev, &cbai, &vkBufs[0]),
            "Could not allocate command buffers"
        );

        import std.algorithm : map;
        import std.array : array;

        return vkBufs
                .map!(vkBuf => cast(CommandBuffer)new VulkanCommandBuffer(vkBuf, this))
                .array;
    }

    override void free(CommandBuffer[] bufs) {
        import std.algorithm : map;
        import std.array : array;

        auto vkBufs = bufs.map!(
            b => enforce(cast(VulkanCommandBuffer)b, "Did not pass a Vulkan command buffer").vkObj
        ).array;
        vk.FreeCommandBuffers(vkDev, vkObj, cast(uint)bufs.length, &vkBufs[0]);
    }
}

final class VulkanCommandBuffer : CommandBuffer
{
    this (VkCommandBuffer vkObj, VulkanCommandPool pool) {
        _vkObj = vkObj;
        _pool = pool;
        _vk = pool.vk;
    }

    @property VkCommandBuffer vkObj() {
        return _vkObj;
    }

    override @property CommandPool pool() {
        return _pool;
    }

    @property VkDeviceCmds vk() {
        return _vk;
    }

    override void reset() {
        vulkanEnforce(
            vk.ResetCommandBuffer(vkObj, 0), "Could not reset vulkan command buffer"
        );
    }

    override void begin(Flag!"persistent" persistent) {
        VkCommandBufferBeginInfo cbbi;
        cbbi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        cbbi.flags = persistent ?
            VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT :
            VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        vulkanEnforce(
            vk.BeginCommandBuffer(vkObj, &cbbi), "Could not begin vulkan command buffer"
        );
    }

    override void end() {
        vulkanEnforce(
            vk.EndCommandBuffer(vkObj), "Could not end vulkan command buffer"
        );
    }

    override void pipelineBarrier(Trans!PipelineStage stageTrans,
                                  BufferMemoryBarrier[] bufMbs,
                                  ImageMemoryBarrier[] imgMbs)
    {
        import std.algorithm : map;
        import std.array : array;

        auto vkBufMbs = bufMbs.map!((BufferMemoryBarrier bufMb) {
            VkBufferMemoryBarrier vkBufMb;
            vkBufMb.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
            vkBufMb.srcAccessMask = accessToVk(bufMb.accessMaskTrans.from);
            vkBufMb.dstAccessMask = accessToVk(bufMb.accessMaskTrans.to);
            vkBufMb.srcQueueFamilyIndex = bufMb.queueFamIndexTrans.from;
            vkBufMb.dstQueueFamilyIndex = bufMb.queueFamIndexTrans.to;
            vkBufMb.buffer = enforce(cast(VulkanBuffer)bufMb.buffer, "Did not pass a Vulkan buffer").vkObj;
            vkBufMb.offset = bufMb.offset;
            vkBufMb.size = bufMb.size;
            return vkBufMb;
        }).array;

        auto vkImgMbs = imgMbs.map!((ImageMemoryBarrier imgMb) {
            VkImageMemoryBarrier vkImgMb;
            vkImgMb.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            vkImgMb.srcAccessMask = accessToVk(imgMb.accessMaskTrans.from);
            vkImgMb.dstAccessMask = accessToVk(imgMb.accessMaskTrans.to);
            vkImgMb.oldLayout = imgMb.layoutTrans.from.toVk();
            vkImgMb.newLayout = imgMb.layoutTrans.to.toVk();
            vkImgMb.srcQueueFamilyIndex = imgMb.queueFamIndexTrans.from;
            vkImgMb.dstQueueFamilyIndex = imgMb.queueFamIndexTrans.to;
            vkImgMb.image = enforce(cast(VulkanImageBase)imgMb.image, "Did not pass a Vulkan image").vkObj;
            vkImgMb.subresourceRange = imgMb.range.toVk();
            return vkImgMb;
        }).array;

        vk.CmdPipelineBarrier( vkObj,
            pipelineStageToVk(stageTrans.from), pipelineStageToVk(stageTrans.to),
            0, 0, null,
            cast(uint)vkBufMbs.length, vkBufMbs.ptr,
            cast(uint)vkImgMbs.length, vkImgMbs.ptr
        );
    }

    override void clearColorImage(ImageBase image, ImageLayout layout,
                         in ClearColorValues clearValues, ImageSubresourceRange[] ranges)
    {
        import std.algorithm : map;
        import std.array : array;

        auto vkImg = enforce(cast(VulkanImageBase)image, "Did not pass a vulkan image").vkObj;
        auto vkLayout = layout.toVk();
        auto vkClear = cast(const(VkClearColorValue)*) cast(const(void)*) &clearValues.values;
        auto vkRanges = ranges.map!(r => r.toVk()).array;

        vk.CmdClearColorImage(vkObj, vkImg, vkLayout, vkClear, cast(uint)vkRanges.length, &vkRanges[0]);
    }

    override void clearDepthStencilImage(ImageBase image, ImageLayout layout,
                                         in ClearDepthStencilValues clearValues,
                                         ImageSubresourceRange[] ranges)
    {
        import std.algorithm : map;
        import std.array : array;

        auto vkImg = enforce(cast(VulkanImageBase)image, "Did not pass a vulkan image").vkObj;
        auto vkLayout = layout.toVk();
        auto vkClear = VkClearDepthStencilValue(clearValues.depth, clearValues.stencil);
        auto vkRanges = ranges.map!(r => r.toVk()).array;

        vk.CmdClearDepthStencilImage(vkObj, vkImg, vkLayout, &vkClear, cast(uint)vkRanges.length, &vkRanges[0]);
    }

    override void copyBuffer(Trans!Buffer buffers, CopyRegion[] regions)
    {
        import std.algorithm : map;
        import std.array : array;

        auto vkRegions = regions.map!(
            r => VkBufferCopy(r.offset.from, r.offset.to, r.size)
        ).array;

        vk.CmdCopyBuffer(vkObj,
            enforce(cast(VulkanBuffer)buffers.from).vkObj,
            enforce(cast(VulkanBuffer)buffers.to).vkObj,
            cast(uint)vkRegions.length, vkRegions.ptr
        );
    }

    void copyBufferToImage(Buffer srcBuffer, ImageBase dstImage,
                           in ImageLayout dstLayout, in BufferImageCopy[] regions)
    {
        import gfx.core.util : transmute;
        import std.algorithm : map;
        import std.array : array;

        auto vkRegions = regions.map!(
            bic => transmute!VkBufferImageCopy(bic)
        ).array;

        vk.CmdCopyBufferToImage(
            vkObj,
            enforce(cast(VulkanBuffer)srcBuffer).vkObj,
            enforce(cast(VulkanImageBase)dstImage).vkObj,
            dstLayout.toVk(),
            cast(uint)vkRegions.length, vkRegions.ptr
        );
    }

    override void beginRenderPass(RenderPass rp, Framebuffer fb,
                                  Rect area, ClearValues[] clearValues)
    {
        import std.algorithm : map;
        import std.array : array;
        auto vkCvs = clearValues.map!(
            (ClearValues cv) {
                VkClearValue vkCv;
                if (cv.type == ClearValues.Type.color) {
                    const ccv = cv.values.color;
                    VkClearColorValue vkCcv;
                    switch (ccv.type) {
                    case ClearColorValues.Type.f32:
                        vkCcv.float32 = ccv.values.f32;
                        break;
                    case ClearColorValues.Type.i32:
                        vkCcv.int32 = ccv.values.i32;
                        break;
                    case ClearColorValues.Type.u32:
                        vkCcv.uint32 = ccv.values.u32;
                        break;
                    default:
                        break;
                    }
                    vkCv.color = vkCcv;
                }
                else if (cv.type == ClearValues.Type.depthStencil) {
                    const dscv = cv.values.depthStencil;
                    vkCv.depthStencil = VkClearDepthStencilValue(
                        dscv.depth, dscv.stencil
                    );
                }
                return vkCv;
            }
        ).array;

        VkRenderPassBeginInfo bi;
        bi.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        bi.renderPass = enforce(cast(VulkanRenderPass)rp, "did not supply a valid Vulkan render pass").vkObj;
        bi.framebuffer = enforce(cast(VulkanFramebuffer)fb, "did not supply a valid Vulkan frame buffer").vkObj;
        bi.renderArea = area.toVk();
        bi.clearValueCount = cast(uint)vkCvs.length;
        bi.pClearValues = vkCvs.ptr;

        vk.CmdBeginRenderPass(vkObj, &bi, VK_SUBPASS_CONTENTS_INLINE);
    }

    override void nextSubpass() {
        vk.CmdNextSubpass(vkObj, VK_SUBPASS_CONTENTS_INLINE);
    }

    override void endRenderPass() {
        vk.CmdEndRenderPass(vkObj);
    }

    override void bindPipeline(Pipeline pipeline)
    {
        vk.CmdBindPipeline(vkObj, VK_PIPELINE_BIND_POINT_GRAPHICS, enforce(
            cast(VulkanPipeline)pipeline, "did not pass a valid Vulkan pipeline"
        ).vkObj);
    }

    override void bindVertexBuffers(uint firstBinding, VertexBinding[] bindings) {
        import std.algorithm : map;
        import std.array : array;
        auto vkBufs = bindings
                .map!(b => enforce(cast(VulkanBuffer)b.buffer).vkObj)
                .array;
        auto vkOffsets = bindings
                .map!(b => cast(VkDeviceSize)b.offset)
                .array;
        vk.CmdBindVertexBuffers(vkObj, firstBinding, cast(uint)bindings.length, vkBufs.ptr, vkOffsets.ptr);
    }

    override void bindIndexBuffer(Buffer indexBuf, size_t offset, IndexType type) {
        auto vkBuf = enforce(cast(VulkanBuffer)indexBuf).vkObj;
        vk.CmdBindIndexBuffer(vkObj, vkBuf, offset, type.toVk());
    }

    override void bindDescriptorSets(PipelineBindPoint bindPoint, PipelineLayout layout,
                                     uint firstSet, DescriptorSet[] sets,
                                     in size_t[] dynamicOffsets)
    {
        import std.algorithm : map;
        import std.array : array;

        auto vkSets = sets.map!(s => enforce(cast(VulkanDescriptorSet)s).vkObj).array;
        static if (size_t.sizeof == uint.sizeof) {
            const vkOffsets = dynamicOffsets;
        }
        else {
            const vkOffsets = dynamicOffsets.map!(o => cast(uint)o).array;
        }

        vk.CmdBindDescriptorSets( vkObj, bindPoint.toVk(),
            enforce(cast(VulkanPipelineLayout)layout).vkObj,
            firstSet, cast(uint)vkSets.length, vkSets.ptr,
            cast(uint)vkOffsets.length, vkOffsets.ptr);
    }

    override void pushConstants(PipelineLayout layout, ShaderStage stages,
                                size_t offset, size_t size, const(void)* data)
    {
        auto vkPl = enforce(cast(VulkanPipelineLayout)layout).vkObj;
        vk.CmdPushConstants(vkObj, vkPl, shaderStageToVk(stages), cast(uint)offset, cast(uint)size, data);
    }

    override void draw(uint vertexCount, uint instanceCount, uint firstVertex, uint firstInstance)
    {
        vk.CmdDraw(vkObj, vertexCount, instanceCount, firstVertex, firstInstance);
    }

    override void drawIndexed(uint indexCount, uint instanceCount, uint firstVertex, int vertexOffset, uint firstInstance)
    {
        vk.CmdDrawIndexed(vkObj, indexCount, instanceCount, firstVertex, vertexOffset, firstInstance);
    }

    private VkCommandBuffer _vkObj;
    private VulkanCommandPool _pool;
    private VkDeviceCmds _vk;
}
