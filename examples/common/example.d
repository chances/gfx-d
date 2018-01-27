module example;

import gfx.core.rc;
import gfx.graal;
import gfx.graal.cmd;
import gfx.graal.device;
import gfx.graal.queue;
import gfx.graal.sync;
import gfx.vulkan;
import gfx.window;

import std.algorithm;
import std.exception;
import std.typecons;

class Example : Disposable
{
    string title;
    Rc!Instance instance;
    Window window;
    uint graphicsQueueIndex;
    uint presentQueueIndex;
    Rc!PhysicalDevice physicalDevice;
    Rc!Device device;
    Queue graphicsQueue;
    Queue presentQueue;
    uint[2] surfaceSize;
    bool hasAlpha;
    Rc!Swapchain swapchain;
    Image[] scImages;
    Rc!Semaphore imageAvailableSem;
    Rc!Semaphore renderingFinishSem;
    Rc!CommandPool cmdPool;
    CommandBuffer[] cmdBufs;
    Fence[] fences;

    enum numCmdBufs=2;
    size_t cmdBufInd;

    this (string title)
    {
        this.title = title;
    }

    override void dispose() {
        if (device) {
            device.waitIdle();
        }
        releaseArray(fences);
        if (cmdPool && cmdBufs.length) {
            cmdPool.free(cmdBufs);
            cmdPool.unload();
        }
        // the rest is checked with Rc, so it is safe to call unload even
        // if object is invalid
        imageAvailableSem.unload();
        renderingFinishSem.unload();
        swapchain.unload();
        device.unload();
        physicalDevice.unload();
        if (window) {
            window.close();
        }
        instance.unload();
    }

    void prepare()
    {
        import std.format : format;
        // initialize vulkan library
        vulkanInit();
        // create a vulkan instance
        instance = createVulkanInstance(
            format("Gfx-d %s Example", title),
            VulkanVersion(0, 0, 1)
        ).rc;
        // create a window for the running platform
        // the window surface is created during this process
        window = createWindow(instance);

        // the rest of the preparation
        prepareDevice();
        prepareSwapchain(null);
        prepareSync();
        prepareCmds();
        prepareRenderPasses();
        preparePipelines();
    }

    void prepareDevice()
    {
        bool checkDevice(PhysicalDevice dev) {
            graphicsQueueIndex = uint.max;
            presentQueueIndex = uint.max;
            if (dev.softwareRendering) return false;
            foreach (uint i, qf; dev.queueFamilies) {
                const graphics = qf.cap & QueueCap.graphics;
                const present = dev.supportsSurface(i, window.surface);
                if (graphics && present) {
                    graphicsQueueIndex = i;
                    presentQueueIndex = i;
                    return true;
                }
                if (graphics) graphicsQueueIndex = i;
                if (present) presentQueueIndex = i;
            }
            return graphicsQueueIndex != uint.max && presentQueueIndex != uint.max;
        }
        foreach (pd; instance.devices) {
            if (checkDevice(pd)) {
                auto qrs = [ QueueRequest(graphicsQueueIndex, [ 0.5f ]) ];
                if (graphicsQueueIndex != presentQueueIndex) {
                    qrs ~= QueueRequest(presentQueueIndex, [ 0.5f ]);
                }
                physicalDevice = pd;
                device = pd.open(qrs);
                graphicsQueue = device.getQueue(graphicsQueueIndex, 0);
                presentQueue = device.getQueue(presentQueueIndex, 0);
                break;
            }
        }
    }

    void prepareSwapchain(Swapchain former=null) {
        const surfCaps = physicalDevice.surfaceCaps(window.surface);
        enforce(surfCaps.usage & ImageUsage.transferDst, "TransferDst not supported by surface");
        const usage = ImageUsage.transferDst | ImageUsage.colorAttachment;
        const numImages = max(2, surfCaps.minImages);
        enforce(surfCaps.maxImages == 0 || surfCaps.maxImages >= numImages);
        const f = chooseFormat(physicalDevice, window.surface);
        hasAlpha = (surfCaps.supportedAlpha & CompositeAlpha.preMultiplied) == CompositeAlpha.preMultiplied;
        const ca = hasAlpha ? CompositeAlpha.preMultiplied : CompositeAlpha.opaque;
        surfaceSize = [ 640, 480 ];
        foreach (i; 0..2) {
            surfaceSize[i] = clamp(surfaceSize[i], surfCaps.minSize[i], surfCaps.maxSize[i]);
        }
        const pm = choosePresentMode(physicalDevice, window.surface);

        swapchain = device.createSwapchain(window.surface, pm, numImages, f, surfaceSize, usage, ca, former);
        scImages = swapchain.images;
    }

    void prepareSync() {
        imageAvailableSem = device.createSemaphore();
        renderingFinishSem = device.createSemaphore();
        fences = new Fence[numCmdBufs];
        foreach (i; 0 .. numCmdBufs) {
            fences[i] = device.createFence(Yes.signaled);
        }
        retainArray(fences);
    }

    void prepareCmds() {
        cmdPool = device.createCommandPool(graphicsQueueIndex);
        cmdBufs = cmdPool.allocate(numCmdBufs);
    }

    abstract void prepareRenderPasses();
    abstract void preparePipelines();
    abstract void recordCmds(size_t bufInd, size_t imgInd);

    size_t nextCmdBuf() {
        const ind = cmdBufInd++;
        if (cmdBufInd == numCmdBufs) {
            cmdBufInd = 0;
        }
        return ind;
    }

    void render()
    {
        import core.time : dur;

        bool needReconstruction;
        const imgInd = swapchain.acquireNextImage(dur!"seconds"(-1), imageAvailableSem, needReconstruction);
        const bufInd = nextCmdBuf();

        fences[bufInd].wait();
        fences[bufInd].reset();

        recordCmds(bufInd, imgInd);

        presentQueue.submit([
            Submission (
                [ StageWait(imageAvailableSem, PipelineStage.transfer) ],
                [ renderingFinishSem ], [ cmdBufs[bufInd] ]
            )
        ], fences[bufInd] );

        presentQueue.present(
            [ renderingFinishSem ],
            [ PresentRequest(swapchain, imgInd) ]
        );

        // if (needReconstruction) {
        //     prepareSwapchain(swapchain);
        //     presentPool.reset();
        // }
    }
}

/// Return a format suitable for the surface.
///  - if supported by the surface Format.rgba8_uNorm
///  - otherwise the first format with uNorm numeric format
///  - otherwise the first format
Format chooseFormat(PhysicalDevice pd, Surface surface)
{
    const formats = pd.surfaceFormats(surface);
    enforce(formats.length, "Could not get surface formats");
    if (formats.length == 1 && formats[0] == Format.undefined) {
        return Format.rgba8_uNorm;
    }
    foreach(f; formats) {
        if (f == Format.rgba8_uNorm) {
            return f;
        }
    }
    foreach(f; formats) {
        if (f.formatDesc.numFormat == NumFormat.uNorm) {
            return f;
        }
    }
    return formats[0];
}

PresentMode choosePresentMode(PhysicalDevice pd, Surface surface)
{
    // auto modes = pd.surfacePresentModes(surface);
    // if (modes.canFind(PresentMode.mailbox)) {
    //     return PresentMode.mailbox;
    // }
    assert(pd.surfacePresentModes(surface).canFind(PresentMode.fifo));
    return PresentMode.fifo;
}
