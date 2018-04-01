module gfx.gl3.queue;

package:

import gfx.bindings.opengl.gl;
import gfx.core.rc : Disposable;
import gfx.graal.cmd;
import gfx.graal.queue;

final class GlQueue : Queue, Disposable
{
    import gfx.gl3 : GlShare;
    import gfx.graal.device : Device;
    import gfx.graal.sync : Fence, Semaphore;

    private GlShare share;
    private Device _device;
    private GLuint readFbo;
    private GLuint vao;

    this(GlShare share, Device device) {
        this.share = share;
        _device = device;
        auto gl = share.gl;
        gl.GenFramebuffers(1, &readFbo);
        gl.GenVertexArrays(1, &vao);
        gl.BindVertexArray(vao);
    }

    override void dispose() {
        auto gl = share.gl;
        gl.DeleteFramebuffers(1, &readFbo);
        gl.DeleteVertexArrays(1, &vao);
    }

    override @property Device device() {
        return _device;
    }

    override void waitIdle() {}

    override void submit(Submission[] submissions, Fence fence) {
        auto gl = share.gl;
        foreach (ref s; submissions) {
            foreach (cmdBuf; s.cmdBufs) {
                auto glCmdBuf = cast(GlCommandBuffer)cmdBuf;
                foreach (cmd; glCmdBuf._cmds) {
                    cmd.execute(this, gl);
                }
                if (!glCmdBuf._persistent) {
                    glCmdBuf._cmds.length = 0;
                }
            }
        }
    }

    override void present(Semaphore[] waitSems, PresentRequest[] prs) {
        import gfx.gl3.resource : GlImage, GlImgType;
        import gfx.gl3.swapchain : GlSurface, GlSwapchain;
        auto gl = share.gl;

        foreach (i, pr; prs) {
            auto sc = cast(GlSwapchain)pr.swapChain;
            auto surf = sc.surface;
            auto img = cast(GlImage)sc.images[pr.imageIndex];
            auto size = sc.size;

            share.ctx.makeCurrent(surf.handle);

            if (i == prs.length-1) share.ctx.swapInterval = 1;
            else share.ctx.swapInterval = 0;

            import gfx.gl3.error : glCheck;

            gl.BindFramebuffer(GL_READ_FRAMEBUFFER, readFbo);
            final switch (img.glType) {
            case GlImgType.renderBuf:
                gl.FramebufferRenderbuffer(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, img.name);
                break;
            case GlImgType.tex:
                gl.FramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, img.name, 0);
                break;
            }

            gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
            gl.BlitFramebuffer(0, 0, size[0], size[1], 0, 0, size[0], size[1],
                               GL_COLOR_BUFFER_BIT, GL_NEAREST);
            glCheck(gl, "blit framebuffer");

            share.ctx.swapBuffers(surf.handle);
        }
    }
}

final class GlCommandPool : CommandPool
{
    import gfx.core.rc : atomicRcCode;
    import gfx.gl3 : GlShare;
    import gfx.graal.cmd : CommandBuffer;

    mixin(atomicRcCode);

    private GlQueue queue;
    private GlShare share;
    private GLuint fbo;

    this(GlQueue queue) {
        this.queue = queue;
        this.share = queue.share;
        auto gl = share.gl;
        gl.GenFramebuffers(1, &fbo);
    }
    override void dispose() {
        auto gl = share.gl;
        gl.DeleteFramebuffers(1, &fbo);
    }

    override void reset() {}

    override CommandBuffer[] allocate(size_t count) {
        auto bufs = new CommandBuffer[count];
        foreach (i; 0 .. count) {
            bufs[i] = new GlCommandBuffer(this, fbo);
        }
        return bufs;
    }

    override void free(CommandBuffer[] buffers) {}
}

final class GlCommandBuffer : CommandBuffer
{
    import gfx.core.typecons : Trans;
    import gfx.core.types : Rect;
    import gfx.gl3 : GlShare, GlInfo;
    import gfx.gl3.conv : toGl;
    import gfx.gl3.pipeline : GlPipeline;
    import gfx.graal.buffer : Buffer, IndexType;
    import gfx.graal.image : ImageBase, ImageLayout, ImageSubresourceRange;
    import gfx.graal.pipeline : ColorBlendInfo, DescriptorSet, Pipeline,
                                PipelineLayout, ShaderStage, VertexInputBinding,
                                VertexInputAttrib, ViewportConfig;
    import gfx.graal.renderpass : Framebuffer, RenderPass;
    import std.experimental.logger;
    import std.typecons : Flag;

    private enum Dirty {
        none                = 0x00,
        vertexBindings      = 0x01,
        pipeline            = 0x02,

        all                 = 0xff,
    }

    private CommandPool _pool;
    private GLuint _fbo;
    private bool _persistent;

    private GlCommand[] _cmds;
    private Dirty _dirty;
    private size_t _indexOffset;
    private GLenum _indexType;
    private VertexBinding[] _vertexBindings;

    // pipeline cache
    private GLenum _primitive;
    private VertexInputBinding[] _inputBindings;
    private VertexInputAttrib[] _inputAttribs;
    private GLuint _prog;
    private ViewportConfig[] _viewports;


    this (CommandPool pool, GLuint fbo) {
        _pool = pool;
        _fbo = fbo;
    }

    override @property CommandPool pool() {
        return _pool;
    }

    override void reset() {
        _cmds.length = 0;
        _dirty = Dirty.none;
        _vertexBindings.length = 0;
    }

    override void begin(Flag!"persistent" persistent) {
        _persistent = persistent;
    }
    override void end() {}

    override void pipelineBarrier(Trans!PipelineStage stageTrans,
                                  BufferMemoryBarrier[] bufMbs,
                                  ImageMemoryBarrier[] imgMbs)
    {
        warningf("unimplemented GL command");
    }

    override void clearColorImage(ImageBase image, ImageLayout layout,
                                  in ClearColorValues clearValues,
                                  ImageSubresourceRange[] ranges)
    {
        import gfx.gl3.resource : GlImage;
        _cmds ~= new SetupFramebufferCmd(_fbo, cast(GlImage)image);
        _cmds ~= new ClearColorCmd(clearValues);
    }

    override void clearDepthStencilImage(ImageBase image, ImageLayout layout,
                                         in ClearDepthStencilValues clearValues,
                                         ImageSubresourceRange[] ranges)
    {
        warningf("unimplemented GL command");
    }

    override void copyBuffer(Trans!Buffer buffers, CopyRegion[] regions)
    {
        warningf("unimplemented GL command");
    }

    override void copyBufferToImage(Buffer srcBuffer, ImageBase dstImage,
                                    in ImageLayout dstLayout,
                                    in BufferImageCopy[] regions)
    {
        warningf("unimplemented GL command");
    }

    override void beginRenderPass(RenderPass rp, Framebuffer fb,
                                  Rect area, ClearValues[] clearValues)
    {
        import gfx.gl3.pipeline : GlFramebuffer;
        const glFb = cast(GlFramebuffer)fb;
        _cmds ~= new BindFramebufferCmd(glFb.name);
        foreach (cv; clearValues) {
            if (cv.type == ClearValues.Type.color) {
                _cmds ~= new ClearColorCmd(cv.values.color);
            }
        }
    }

    override void nextSubpass()
    {
        warningf("unimplemented GL command");
    }

    override void endRenderPass()
    {
        //warningf("unimplemented GL command");
    }

    override void bindPipeline(Pipeline pipeline)
    {
        auto glPipeline = cast(GlPipeline)pipeline;
        if (_prog != glPipeline.prog) {
            _prog = glPipeline.prog;
            _cmds ~= new BindProgramCmd(_prog);
        }
        bindOutputs(glPipeline.info.blendInfo);
        if (_viewports != glPipeline.info.viewports) {
            _viewports = glPipeline.info.viewports;
            _cmds ~= new SetViewportsCmd(_viewports);
        }
        _primitive = toGl(glPipeline.info.assembly.primitive);
        _inputBindings = glPipeline.info.inputBindings;
        _inputAttribs = glPipeline.info.inputAttribs;
        dirty(Dirty.pipeline);
    }

    override void bindVertexBuffers(uint firstBinding, VertexBinding[] bindings)
    {
        const minLen = firstBinding + bindings.length;
        if (_vertexBindings.length < minLen) _vertexBindings.length = minLen;
        _vertexBindings[firstBinding .. firstBinding+bindings.length] = bindings;
        dirty(Dirty.vertexBindings);
    }

    override void bindIndexBuffer(Buffer indexBuf, size_t offset,
                                  IndexType type)
    {
        import gfx.gl3.resource : GlBuffer;
        auto glBuf = cast(GlBuffer)indexBuf;
        _cmds ~= new BindIndexBufCmd(glBuf.name);
        _indexOffset = offset;
        _indexType = toGl(type);
    }

    override void bindDescriptorSets(PipelineBindPoint bindPoint,
                                     PipelineLayout layout, uint firstSet,
                                     DescriptorSet[] sets,
                                     in size_t[] dynamicOffsets)
    {
        import gfx.gl3.pipeline : GlDescriptorSet;
        import gfx.graal.pipeline : DescriptorType;

        size_t dynInd = 0;

        foreach (si, ds; sets) {
            auto glSet = cast(GlDescriptorSet)ds;

            foreach(bi, b; glSet.bindings) {

                foreach (di, d; b.descriptors) {

                    switch (b.layout.descriptorType) {
                    case DescriptorType.uniformBuffer:
                        _cmds ~= new BindUniformBufferCmd(
                            b.layout.binding, d.bufferRange, 0
                        );
                        break;
                    case DescriptorType.uniformBufferDynamic:
                        _cmds ~= new BindUniformBufferCmd(
                            b.layout.binding, d.bufferRange, dynamicOffsets[dynInd++]
                        );
                        break;
                    default:
                        warningf("unhandled descriptor set");
                        break;
                    }
                }
            }
        }
    }

    override void pushConstants(PipelineLayout layout, ShaderStage stages,
                                size_t offset, size_t size, const(void)* data)
    {
        warningf("unimplemented GL command");
    }

    override void draw(uint vertexCount, uint instanceCount, uint firstVertex,
                       uint firstInstance)
    {
        ensureBindings();
        _cmds ~= new DrawCmd(
            _primitive, cast(GLint)firstVertex, cast(GLsizei)vertexCount,
            cast(GLsizei)instanceCount, cast(GLuint)firstInstance
        );
    }

    override void drawIndexed(uint indexCount, uint instanceCount,
                              uint firstVertex, int vertexOffset,
                              uint firstInstance)
    {
        ensureBindings();

        const factor = _indexType == GL_UNSIGNED_SHORT ? 2 : 4;
        const offset = factor * firstVertex + _indexOffset;

        _cmds ~= new DrawIndexedCmd(
            _primitive, cast(GLsizei)indexCount, _indexType, offset, cast(GLint)vertexOffset,
            cast(GLsizei)instanceCount, cast(GLuint)firstInstance
        );
    }

    private void dirty(Dirty flag) {
        _dirty |= flag;
    }

    private void clean(Dirty flag) {
        _dirty &= ~flag;
    }

    private bool allDirty(Dirty flags) {
        return (_dirty & flags) == flags;
    }

    private bool someDirty(Dirty flags) {
        return (_dirty & flags) != Dirty.none;
    }

    private void ensureBindings() {
        if (someDirty(Dirty.vertexBindings)) {
            bindAttribs();
            clean(Dirty.vertexBindings);
        }
    }

    private void bindAttribs() {
        assert(_vertexBindings.length == _inputBindings.length);
        assert(someDirty(Dirty.vertexBindings));

        import gfx.gl3.conv : glVertexFormat, vertexFormatSupported;
        import gfx.gl3.resource : GlBuffer;
        import gfx.graal.format : formatDesc;
        import std.algorithm : filter;

        foreach (bi, vb; _vertexBindings) {
            const bindingInfo = _inputBindings[bi];

            GlVertexAttrib[] attribs;

            foreach (ai; _inputAttribs.filter!(ia => ia.binding == bi)) {
                const f = ai.format;
                assert(vertexFormatSupported(f));

                attribs ~= GlVertexAttrib(
                    ai.location, glVertexFormat(f), vb.offset+ai.offset
                );
            }

            auto buf = cast(GlBuffer)vb.buffer;
            _cmds ~= new BindVertexBufCmd(buf.name, cast(GLsizei)bindingInfo.stride, attribs);
        }
    }

    void bindOutputs(ColorBlendInfo blendInfo) {
        if (blendInfo.logicOp.isSome) {
            // enable logicOp
            // TODO
            warning("Gl logicOp not implemented");
        }
        else {
            // disable logicOp
        }
        foreach (slot, attachment; blendInfo.attachments) {
            _cmds ~= new BindBlendSlotCmd(cast(GLuint)slot, attachment);
        }
    }
}

private:

abstract class GlCommand {
    abstract void execute(GlQueue queue, Gl gl);
}

final class BindFramebufferCmd : GlCommand
{
    GLuint fbo;
    this(GLuint fbo) { this.fbo = fbo; }
    override void execute(GlQueue queue, Gl gl) {
        gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo);
    }
}

final class SetupFramebufferCmd : GlCommand
{
    import gfx.gl3.resource : GlImage, GlImgType;

    GLuint fbo;
    GlImage img;

    this(GLuint fbo, GlImage img) {
        this.fbo = fbo;
        this.img = img;
    }

    override void execute(GlQueue queue, Gl gl) {
        gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo);
        final switch (img.glType) {
        case GlImgType.renderBuf:
            gl.FramebufferRenderbuffer(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, img.name);
            break;
        case GlImgType.tex:
            gl.FramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, img.name, 0);
            break;
        }
        const GLenum drawBuf = GL_COLOR_ATTACHMENT0;
        gl.DrawBuffers(1, &drawBuf);
    }
}

final class SetViewportsCmd : GlCommand {
    import gfx.graal.pipeline : ViewportConfig;
    ViewportConfig[] viewports;
    this (ViewportConfig[] viewports) {
        this.viewports = viewports;
    }

    override void execute(GlQueue queue, Gl gl) {
        if (viewports.length > 1 && !queue.share.info.viewportArray) {
            import std.experimental.logger : error;
            error("ARB_viewport_array not supported");
            viewports = viewports[0..1];
        }

        if (viewports.length > 1) {
            foreach (i, vc; viewports) {
                const vp = vc.viewport;
                gl.ViewportIndexedf(cast(GLuint)i, vp.x, vp.y, vp.width, vp.height);
                gl.DepthRangeIndexed(cast(GLuint)i, vp.minDepth, vp.maxDepth);

                const sc = vc.scissors;
                gl.ScissorIndexed(
                    cast(GLuint)i,
                    cast(GLint)sc.x, cast(GLint)sc.y,
                    cast(GLsizei)sc.width, cast(GLsizei)sc.height
                );
            }
        }
        else if (viewports.length == 1) {
            const vp = viewports[0].viewport;
            gl.Viewport(
                cast(GLint)vp.x, cast(GLint)vp.y,
                cast(GLsizei)vp.width, cast(GLsizei)vp.height
            );
            gl.DepthRangef(vp.minDepth, vp.maxDepth);

            const sc = viewports[0].scissors;
            gl.Scissor(
                cast(GLint)sc.x, cast(GLint)sc.y,
                cast(GLsizei)sc.width, cast(GLsizei)sc.height
            );
        }
    }

}

final class ClearColorCmd : GlCommand {

    ClearColorValues values;

    this (ClearColorValues values) {
        this.values = values;
    }

    override void execute(GlQueue queue, Gl gl) {
        final switch (values.type) {
        case ClearColorValues.Type.f32:
            gl.ClearBufferfv(GL_COLOR, 0, &values.values.f32[0]);
            break;
        case ClearColorValues.Type.i32:
            gl.ClearBufferiv(GL_COLOR, 0, &values.values.i32[0]);
            break;
        case ClearColorValues.Type.u32:
            gl.ClearBufferuiv(GL_COLOR, 0, &values.values.u32[0]);
            break;
        }
    }
}

final class BindProgramCmd : GlCommand
{
    GLuint prog;
    this(GLuint prog) { this.prog = prog; }
    override void execute(GlQueue queue, Gl gl) {
        gl.UseProgram(prog);
        gl.Disable(GL_CULL_FACE);
    }
}

struct GlVertexAttrib {
    import gfx.gl3.conv : GlVertexFormat;

    GLuint index;
    GlVertexFormat format;
    size_t offset;
}

final class BindVertexBufCmd : GlCommand
{
    GLuint buffer;
    GLsizei stride;
    GlVertexAttrib[] attribs;

    this(GLuint buffer, GLsizei stride, GlVertexAttrib[] attribs) {
        this.buffer = buffer;
        this.stride = stride;
        this.attribs = attribs;
    }

    override void execute(GlQueue queue, Gl gl)
    {
        import gfx.gl3.conv : VAOAttribFun;

        gl.BindBuffer(GL_ARRAY_BUFFER, buffer);
        foreach(at; attribs) {
            final switch (at.format.fun) {
            case VAOAttribFun.f:
                gl.VertexAttribPointer(
                    at.index, at.format.size, at.format.type,
                    at.format.normalized, stride, cast(const(void*))at.offset
                );
                break;
            case VAOAttribFun.i:
                gl.VertexAttribIPointer(
                    at.index, at.format.size, at.format.type, stride,
                    cast(const(void*))at.offset
                );
                break;
            case VAOAttribFun.d:
                gl.VertexAttribLPointer(
                    at.index, at.format.size, at.format.type, stride,
                    cast(const(void*))at.offset
                );
                break;
            }
        }
        gl.BindBuffer(GL_ARRAY_BUFFER, 0);
    }
}

final class BindIndexBufCmd : GlCommand
{
    GLuint buf;

    this(GLuint buf) {
        this.buf = buf;
    }

    override void execute(GlQueue queue, Gl gl)
    {
        gl.BindBuffer(GL_ELEMENT_ARRAY_BUFFER, buf);
    }
}

final class BindUniformBufferCmd : GlCommand
{
    import gfx.gl3.resource : GlBuffer;
    import gfx.graal.pipeline : BufferRange;

    GLuint binding;
    BufferRange bufferRange;
    size_t dynamicOffset;

    this (GLuint binding, BufferRange br, in size_t dynOffset) {
        this.binding = binding;
        this.bufferRange = br;
        this.dynamicOffset = dynOffset;
    }

    override void execute(GlQueue queue, Gl gl) {
        auto glBuf = cast(GlBuffer)bufferRange.buffer;

        gl.BindBufferRange(
            GL_UNIFORM_BUFFER, binding, glBuf.name,
            cast(GLintptr)(bufferRange.offset+dynamicOffset),
            cast(GLintptr)bufferRange.range
        );
    }
}

final class BindBlendSlotCmd : GlCommand
{
    import gfx.graal.pipeline : ColorBlendAttachment, ColorMask;

    GLuint slot;
    ColorBlendAttachment blendInfo;

    this(GLuint slot, ColorBlendAttachment blendInfo) {
        this.slot = slot;
        this.blendInfo = blendInfo;
    }

    override void execute(GlQueue queue, Gl gl) {
        if (blendInfo.enabled) {
            // TODO
            import std.experimental.logger : warning;
            warning("Gl blending not implemented");
        }
        else {
            gl.Disablei(GL_BLEND, slot);
        }
        import std.typecons : BitFlags, Yes;
        BitFlags!(ColorMask, Yes.unsafe) cm = blendInfo.colorMask;
        gl.ColorMaski(
            slot,
            (cm & ColorMask.r) ? GL_TRUE : GL_FALSE,
            (cm & ColorMask.g) ? GL_TRUE : GL_FALSE,
            (cm & ColorMask.b) ? GL_TRUE : GL_FALSE,
            (cm & ColorMask.a) ? GL_TRUE : GL_FALSE
        );
    }
}

final class DrawCmd : GlCommand
{
    GLenum primitive;
    GLint first;
    GLsizei count;
    GLsizei instanceCount;
    GLuint baseInstance;

    this (GLenum primitive, GLint first, GLsizei count, GLsizei instanceCount,
            GLuint baseInstance)
    {
        this.primitive = primitive;
        this.first = first;
        this.count = count;
        this.instanceCount = instanceCount;
        this.baseInstance = baseInstance;
    }

    override void execute(GlQueue queue, Gl gl) {
        if (baseInstance != 0 && !queue.share.info.baseInstance) {
            import std.experimental.logger : errorf;
            errorf("No support for ARB_base_instance");
            return;
        }
        if (instanceCount <= 1) {
            gl.DrawArrays(primitive, first, count);
        }
        else if (instanceCount > 1 && baseInstance == 0) {
            gl.DrawArraysInstanced(primitive, first, count, instanceCount);
        }
        else if (instanceCount > 1 && baseInstance != 0) {
            gl.DrawArraysInstancedBaseInstance(
                primitive, first, count, instanceCount, baseInstance
            );
        }
        import gfx.gl3.error : glCheck;
        glCheck(gl, "draw");
    }
}

final class DrawIndexedCmd : GlCommand
{
    GLenum primitive;
    GLsizei count;
    GLenum type;
    size_t indexBufOffset;
    GLint baseVertex;
    GLsizei instanceCount;
    GLuint baseInstance;

    this(GLenum primitive, GLsizei count, GLenum type, size_t indexBufOffset,
            GLint baseVertex, GLsizei instanceCount, GLuint baseInstance)
    {
        this.primitive = primitive;
        this.count = count;
        this.type = type;
        this.indexBufOffset = indexBufOffset;
        this.baseVertex = baseVertex;
        this.instanceCount = instanceCount;
        this.baseInstance = baseInstance;
    }

    override void execute(GlQueue queue, Gl gl) {
        import std.experimental.logger : errorf;

        const offset = cast(const(void*))indexBufOffset;

        if (baseVertex != 0 && !queue.share.info.drawElementsBaseVertex) {
            errorf("No support for ARB_draw_elements_base_vertex");
            return;
        }
        if (baseInstance != 0 && !queue.share.info.baseInstance) {
            errorf("No support for ARB_base_instance");
            return;
        }

        if (instanceCount <= 1 && baseVertex == 0) {
            gl.DrawElements(primitive, count, type, offset);
        }
        else if (instanceCount <= 1 && baseVertex != 0) {
            gl.DrawElementsBaseVertex(primitive, count, type, offset, baseVertex);
        }
        else if (instanceCount > 1 && baseInstance == 0 && baseVertex == 0) {
            gl.DrawElementsInstanced(primitive, count, type, offset, instanceCount);
        }
        else if (instanceCount > 1 && baseInstance == 0 && baseVertex != 0) {
            gl.DrawElementsInstancedBaseVertex(
                primitive, count, type, offset, instanceCount, baseVertex
            );
        }
        else if (instanceCount > 1 && baseInstance != 0 && baseVertex == 0) {
            gl.DrawElementsInstancedBaseInstance(
                primitive, count, type, offset, instanceCount, baseInstance
            );
        }
        else {
            gl.DrawElementsInstancedBaseVertexBaseInstance(
                primitive, count, type, offset, instanceCount, baseVertex, baseInstance
            );
        }
        import gfx.gl3.error : glCheck;
        glCheck(gl, "draw indexed");
    }
}
