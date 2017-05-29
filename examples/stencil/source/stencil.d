module stencil;

import gfx.foundation.rc;
import gfx.foundation.typecons;
import gfx.pipeline;

import gfx.window.glfw;

import std.typecons : Tuple, tuple;
import std.stdio : writeln;

struct PTVertex {
    @GfxName("a_Pos")       float[2] pos;
    @GfxName("a_TexCoord")  float[2] uv;
}
struct PCVertex {
    @GfxName("a_Pos")   float[2] pos;
    @GfxName("a_Color") float[3] color;
}

struct StencilWriteMeta {
    VertexInput!PTVertex        input;

    @GfxName("u_Sampler")
    ResourceView!STF            tex;

    @GfxName("o_Color")
    @GfxColorMask(ColorMask(ColorFlags.none))  // disable rendering in color buffer (default is 'All')
    ColorOutput!Rgba8           color;

    // 0x01 mask: we only care on the first bitplane
    @GfxStencil(StencilTest(
        Comparison.always, 0x01, [
            StencilOp.replace, StencilOp.replace, StencilOp.replace
        ]
    ))
    StencilOutput!DepthStencil  stencil;
}

struct TriangleMeta {
    VertexInput!PCVertex        input;

    @GfxName("o_Color")
    ColorOutput!Rgba8           color;

    // 0x01 mask: we only care on the first bitplane
    @GfxStencil(StencilTest(Comparison.equal, 0x01, [StencilOp.keep, StencilOp.keep, StencilOp.keep]))
    StencilOutput!DepthStencil  stencil;
}

alias StencilWritePS = PipelineState!StencilWriteMeta;
alias TrianglePS = PipelineState!TriangleMeta;


immutable triangle = [
    PCVertex([-1.0, -1.0], [1.0, 0.0, 0.0]),
    PCVertex([ 1.0, -1.0], [0.0, 1.0, 0.0]),
    PCVertex([ 0.0,  1.0], [0.0, 0.0, 1.0]),
];

immutable square = [
    PTVertex([-1.0,  1.0], [0.0, 1.0]),
    PTVertex([-1.0, -1.0], [0.0, 0.0]),
    PTVertex([ 1.0, -1.0], [1.0, 0.0]),
    PTVertex([ 1.0,  1.0], [1.0, 1.0]),
];

immutable ushort[] squareIndices = [
    0, 1, 2,    0, 2, 3
];

immutable float[4] clearColor = [0.1, 0.2, 0.3, 1.0];


alias STF = Tuple!(R8, Unorm); // stencil texture format

Texture!STF makeChessboard() {
    auto data = new ubyte[32*32];
    foreach (r; 0 .. 32) {
        foreach (c; 0 .. 32) {
            immutable oddR = (r/4)%2 != 0;
            immutable oddC = (c/4)%2 != 0;
            data[r*32 + c] = oddR == oddC ? 0xff : 0x00;
        }
    }
    TexUsageFlags usage = TextureUsage.shaderResource;
    return new Texture2D!STF(usage, 1, 32, 32, [data]);
}



struct FPSProbe {
    import std.datetime : StopWatch;

    size_t frameCount;
    StopWatch sw;

    void start() { sw.start(); }
    void tick() { frameCount += 1; }
    @property float fps() const {
        auto msecs = sw.peek().msecs();
        return 1000f * frameCount / msecs;
    }
}

void main() {
    auto window = rc(gfxGlfwWindow!(Rgba8, DepthStencil)("gfx-d - Stencil", 640, 480));
    auto rtv = rc(window.colorSurface.viewAsRenderTarget());
    auto dsv = rc(window.depthStencilSurface.viewAsDepthStencil());
    auto cbv = rc(makeChessboard().viewAsShaderResource(0, 0, newSwizzle()));

    auto swp = makeRc!Program(ShaderSet.vertexPixel(
        import("330-stencil.v.glsl"),
        import("330-stencil.f.glsl"),
    ));
    auto swvb = makeRc!(VertexBuffer!PTVertex)(square);
    auto sws = VertexBufferSlice(new IndexBuffer!ushort(squareIndices));
    auto swpso = makeRc!(StencilWritePS)(swp.obj, Primitive.triangles, Rasterizer.fill);
    auto swdata = StencilWritePS.Data(
        swvb, cbv, rtv, StencilOutput!DepthStencil.Data(dsv, [1, 1])
    );

    auto trp = makeRc!Program(ShaderSet.vertexPixel(
        import("330-triangle.v.glsl"),
        import("330-triangle.f.glsl"),
    ));
    auto trvb = makeRc!(VertexBuffer!PCVertex)(triangle);
    auto trs = VertexBufferSlice(trvb.count);
    auto trpso = makeRc!(TrianglePS)(trp.obj, Primitive.triangles, Rasterizer.fill);
    auto trdata = TrianglePS.Data(
        trvb, rtv, StencilOutput!DepthStencil.Data(dsv, [1, 1])
    );

    auto encoder = Encoder(window.device.makeCommandBuffer());

    window.onKey = (int, int, int, int) { window.shouldClose = true; };
    window.onFbResize = (ushort w, ushort h) { encoder.setViewport(0, 0, w, h); };

    FPSProbe fps;
    fps.start();

    while (!window.shouldClose) {

        encoder.clearStencil(dsv, 0x00);
        encoder.draw!StencilWriteMeta(sws, swpso, swdata);

        encoder.clear!Rgba8(rtv, clearColor);
        encoder.draw!TriangleMeta(trs, trpso, trdata);

        encoder.flush(window.device);

        window.swapBuffers();
        window.pollEvents();
        fps.tick();
    }

    writeln("FPS: ", fps.fps);
}