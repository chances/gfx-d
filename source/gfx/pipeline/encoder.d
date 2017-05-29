module gfx.pipeline.encoder;

import gfx.device : Device;
import gfx.foundation.rc : Rc;
import gfx.foundation.typecons : Option, some, none;
import gfx.pipeline.draw : CommandBuffer, clearColor, Instance;
import gfx.pipeline.format : Formatted, isFormatted;
import gfx.pipeline.buffer : Buffer, ConstBuffer, VertexBufferSlice, IndexType;
import gfx.pipeline.texture : Texture, ImageSliceInfo;
import gfx.pipeline.view : RenderTargetView, DepthStencilView;
import gfx.pipeline.pso : PipelineState;
import gfx.pipeline.pso.meta : PipelineData;

struct Encoder {

    Rc!CommandBuffer _cmdBuf;

    this(CommandBuffer cmdBuf) {
        _cmdBuf = cmdBuf;
    }

    void clear(T)(RenderTargetView!T view, Formatted!T.View value) if (isFormatted!T) {
        _cmdBuf.clearColor(view, clearColor(value));
    }

    void clearDepth(T)(DepthStencilView!T view, float depth) if (isFormatted!T) {
        _cmdBuf.clearDepthStencil(view, some(depth), none!ubyte);
    }

    void clearStencil(T)(DepthStencilView!T view, ubyte stencil) if (isFormatted!T) {
        _cmdBuf.clearDepthStencil(view, none!float, some(stencil));
    }

    void clearDepthStencil(T)(DepthStencilView!T view, float depth, ubyte stencil) if (isFormatted!T) {
        _cmdBuf.clearDepthStencil(view, some(depth), some(stencil));
    }

    void setViewport(ushort x, ushort y, ushort w, ushort h) {
        _cmdBuf.setViewport(x, y, w, h);
    }

    void updateBuffer(T)(Buffer!T buf, in T[] data, in size_t offset) {
        auto byteOffset = offset*T.sizeof;
        auto bytes = cast(const(ubyte)*)data.ptr;
        _cmdBuf.updateBuffer(buf, bytes[0 .. data.length*T.sizeof], byteOffset);
    }

    void updateTexture(T)(Texture!T tex, ImageSliceInfo info, const(Texture!T.Texel)[] texels) {
        import gfx.foundation.util : untypeSlice;
        // TODO bounds check
        _cmdBuf.updateTexture(tex, info, untypeSlice(texels));
    }

    void updateConstBuffer(T)(ConstBuffer!T buf, in T value) {
        auto bytes = cast(const(ubyte)*)&value;
        _cmdBuf.updateBuffer(buf, bytes[0 .. T.sizeof].dup, 0);
    }
    void updateConstBuffer(T)(ConstBuffer!T buf, in T[] slice) {
        auto bytes = cast(const(ubyte)*)slice.ptr;
        _cmdBuf.updateBuffer(buf, bytes[0 .. slice.length*T.sizeof], 0);
    }

    void draw(MS)(VertexBufferSlice slice, PipelineState!MS pso, PipelineData!MS data) {
        auto dataSet = pso.makeDataSet(data); // TODO make data set cached member of pso;
        _cmdBuf.bindPipelineState(pso);
        _cmdBuf.bindVertexBuffers(dataSet.vertexBuffers);
        _cmdBuf.bindPixelTargets(dataSet.pixelTargets);
        _cmdBuf.setRefValues(dataSet.blendRef, dataSet.stencilRef);
        _cmdBuf.bindConstantBuffers(dataSet.constantBlocks);
        _cmdBuf.bindResourceViews(dataSet.resourceViews);
        _cmdBuf.bindSamplers(dataSet.samplers);

        if(slice.type == IndexType.none) {
            _cmdBuf.draw(cast(uint)(slice.start+slice.baseVertex), cast(uint)slice.end, none!Instance);
        }
        else {
            _cmdBuf.bindIndex(slice.buffer, slice.type);
            _cmdBuf.drawIndexed(cast(uint)slice.start, cast(uint)slice.end, cast(uint)slice.baseVertex, none!Instance);
        }
    }

    void flush(Device device) {
        device.submit(_cmdBuf);
    }
}
