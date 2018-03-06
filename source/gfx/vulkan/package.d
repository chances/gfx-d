/// Vulkan implementation of GrAAL
module gfx.vulkan;

import gfx.bindings.vulkan;
import gfx.graal;


// some standard layers

enum lunarGValidationLayers = [
    "VK_LAYER_LUNARG_core_validation",
    "VK_LAYER_LUNARG_standard_validation",
    "VK_LAYER_LUNARG_parameter_validation",
];

@property ApiProps vulkanApiProps() {
    return ApiProps(
        "vulkan", CoordSystem.rightHanded
    );
}

/// Load global level vulkan functions, and instance level layers and extensions
/// This function must be called before any other in this module
void vulkanInit()
{
    synchronized {
        _globCmds = loadVulkanGlobalCmds();
        _instanceLayers = loadInstanceLayers();
        _instanceExtensions = loadInstanceExtensions();
    }
}

struct VulkanVersion
{
    import std.bitmanip : bitfields;
    mixin(bitfields!(
        uint, "patch", 12,
        uint, "minor", 10,
        uint, "major", 10,
    ));

    this (in uint major, in uint minor, in uint patch) {
        this.major = major; this.minor = minor; this.patch = patch;
    }

    this (in uint vkVer) {
        this(VK_VERSION_MAJOR(vkVer), VK_VERSION_MINOR(vkVer), VK_VERSION_PATCH(vkVer));
    }

    static VulkanVersion fromUint(in uint vkVer) {
        return *cast(VulkanVersion*)(cast(void*)&vkVer);
    }

    uint toUint() const {
        return *cast(uint*)(cast(void*)&this);
    }

    string toString() {
        import std.format : format;
        return format("VulkanVersion(%s, %s, %s)", this.major, this.minor, this.patch);
    }
}

unittest {
    const vkVer = VK_MAKE_VERSION(12, 7, 38);
    auto vv = VulkanVersion.fromUint(vkVer);
    assert(vv.major == 12);
    assert(vv.minor == 7);
    assert(vv.patch == 38);
    assert(vv.toUint() == vkVer);
}

struct VulkanLayerProperties
{
    string layerName;
    VulkanVersion specVer;
    VulkanVersion implVer;
    string description;

    @property VulkanExtensionProperties[] instanceExtensions()
    {
        return loadInstanceExtensions(layerName);
    }
}

struct VulkanExtensionProperties
{
    string extensionName;
    VulkanVersion specVer;
}

/// Retrieve available instance level layer properties
@property VulkanLayerProperties[] vulkanInstanceLayers() {
    return _instanceLayers;
}
/// Retrieve available instance level extensions properties
@property VulkanExtensionProperties[] vulkanInstanceExtensions()
{
    return _instanceExtensions;
}

/// Creates a vulkan instance with default layers and extensions
VulkanInstance createVulkanInstance(in string appName=null,
                                    in VulkanVersion appVersion=VulkanVersion(0, 0, 0))
{
    debug {
        const wantedLayers = lunarGValidationLayers;
        const wantedExts = [ "VK_KHR_debug_report", "VK_EXT_debug_report" ];
    }
    else {
        const string[] wantedLayers = [];
        const string[] wantedExts = [];
    }

    import gfx.vulkan.wsi : surfaceInstanceExtensions;

    import std.algorithm : canFind, filter, map;
    import std.array : array;
    import std.range : chain;

    const layers = wantedLayers
            .filter!(l => _instanceLayers.map!(il => il.layerName).canFind(l))
            .array;
    const exts = wantedExts
            .filter!(e => _instanceExtensions.map!(ie => ie.extensionName).canFind(e))
            .array
        ~ surfaceInstanceExtensions;

    return createVulkanInstance(layers, exts, appName, appVersion);
}

/// Creates an Instance object with Vulkan backend with user specified layers and extensions
VulkanInstance createVulkanInstance(in string[] layers, in string[] extensions,
                                    in string appName=null,
                                    in VulkanVersion appVersion=VulkanVersion(0, 0, 0))
{
    import gfx : gfxVersionMaj, gfxVersionMin, gfxVersionMic;
    import std.algorithm : all, canFind, map;
    import std.array : array;
    import std.exception : enforce;
    import std.string : toStringz;

    // throw if some requested layers or extensions are not available
    // TODO: specific exception
    foreach (l; layers) {
        enforce(
            _instanceLayers.map!(il => il.layerName).canFind(l),
            "Could not find layer " ~ l ~ " when creating Vulkan instance"
        );
    }
    foreach (e; extensions) {
        enforce(
            _instanceExtensions.map!(ie => ie.extensionName).canFind(e),
            "Could not find extension " ~ e ~ " when creating Vulkan instance"
        );
    }

    VkApplicationInfo ai;
    ai.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    if (appName.length) {
        ai.pApplicationName = toStringz(appName);
    }
    ai.applicationVersion = appVersion.toUint();
    ai.pEngineName = "gfx-d\n".ptr;
    ai.engineVersion = VK_MAKE_VERSION(gfxVersionMaj, gfxVersionMin, gfxVersionMic);

    auto vkLayers = layers.map!toStringz.array;
    auto vkExts = extensions.map!toStringz.array;

    VkInstanceCreateInfo ici;
    ici.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ici.pApplicationInfo = &ai;
    ici.enabledLayerCount = cast(uint)vkLayers.length;
    ici.ppEnabledLayerNames = &vkLayers[0];
    ici.enabledExtensionCount = cast(uint)vkExts.length;
    ici.ppEnabledExtensionNames = &vkExts[0];

    VkInstance vkInst;
    vulkanEnforce(_globCmds.createInstance(&ici, null, &vkInst), "Could not create Vulkan instance");

    return new VulkanInstance(vkInst);
}

/// Retrieve available device level layers
@property VulkanLayerProperties[] vulkanDeviceLayers(PhysicalDevice device) {
    auto pd = cast(VulkanPhysicalDevice)device;
    if (!pd) return [];

    return pd._availableLayers;
}
/// Retrieve available instance level extensions properties
VulkanExtensionProperties[] vulkanDeviceExtensions(PhysicalDevice device, in string layerName=null)
{
    auto pd = cast(VulkanPhysicalDevice)device;
    if (!pd) return [];

    if (!layerName) {
        return pd._availableExtensions;
    }
    else {
        return pd.loadDeviceExtensions(layerName);
    }
}

void overrideDeviceOpenVulkanLayers(PhysicalDevice device, string[] layers)
{
    auto pd = cast(VulkanPhysicalDevice)device;
    if (!pd) return;

    pd._openLayers = layers;
}

void overrideDeviceOpenVulkanExtensions(PhysicalDevice device, string[] extensions)
{
    auto pd = cast(VulkanPhysicalDevice)device;
    if (!pd) return;

    pd._openExtensions = extensions;
}


package:

import gfx.core.rc;
import gfx.graal.device;
import gfx.graal.format;
import gfx.graal.memory;
import gfx.graal.presentation;
import gfx.graal.queue;
import gfx.vulkan.conv;
import gfx.vulkan.device;
import gfx.vulkan.error;
import gfx.vulkan.wsi : VulkanSurface;

import std.exception : enforce;

__gshared VkGlobalCmds _globCmds;
__gshared VulkanLayerProperties[] _instanceLayers;
__gshared VulkanExtensionProperties[] _instanceExtensions;

VulkanLayerProperties[] loadInstanceLayers()
{
    uint count;
    vulkanEnforce(
        _globCmds.enumerateInstanceLayerProperties(&count, null),
        "Could not retrieve Vulkan instance layers"
    );
    if (!count) return[];

    auto vkLayers = new VkLayerProperties[count];
    vulkanEnforce(
        _globCmds.enumerateInstanceLayerProperties(&count, &vkLayers[0]),
        "Could not retrieve Vulkan instance layers"
    );

    import std.algorithm : map;
    import std.array : array;
    import std.string : fromStringz;

    return vkLayers
            .map!((ref VkLayerProperties vkLp) {
                return VulkanLayerProperties(
                    fromStringz(&vkLp.layerName[0]).idup,
                    VulkanVersion.fromUint(vkLp.specVersion),
                    VulkanVersion.fromUint(vkLp.implementationVersion),
                    fromStringz(&vkLp.description[0]).idup,
                );
            })
            .array;
}

VulkanExtensionProperties[] loadInstanceExtensions(in string layerName=null)
{
    import std.string : toStringz;

    const(char)* layer;
    if (layerName.length) {
        layer = toStringz(layerName);
    }
    uint count;
    vulkanEnforce(
        _globCmds.enumerateInstanceExtensionProperties(layer, &count, null),
        "Could not retrieve Vulkan instance extensions"
    );
    if (!count) return[];

    auto vkExts = new VkExtensionProperties[count];
    vulkanEnforce(
        _globCmds.enumerateInstanceExtensionProperties(layer, &count, &vkExts[0]),
        "Could not retrieve Vulkan instance extensions"
    );

    import std.algorithm : map;
    import std.array : array;
    import std.string : fromStringz;

    return vkExts
            .map!((ref VkExtensionProperties vkExt) {
                return VulkanExtensionProperties(
                    fromStringz(&vkExt.extensionName[0]).idup,
                    VulkanVersion.fromUint(vkExt.specVersion)
                );
            })
            .array;
}

VulkanLayerProperties[] loadDeviceLayers(VulkanPhysicalDevice pd)
{
    uint count;
    vulkanEnforce(
        pd.cmds.enumerateDeviceLayerProperties(pd.vk, &count, null),
        "Could not retrieve Vulkan device layers"
    );
    if (!count) return[];

    auto vkLayers = new VkLayerProperties[count];
    vulkanEnforce(
        pd.cmds.enumerateDeviceLayerProperties(pd.vk, &count, &vkLayers[0]),
        "Could not retrieve Vulkan device layers"
    );

    import std.algorithm : map;
    import std.array : array;
    import std.string : fromStringz;

    return vkLayers
            .map!((ref VkLayerProperties vkLp) {
                return VulkanLayerProperties(
                    fromStringz(&vkLp.layerName[0]).idup,
                    VulkanVersion.fromUint(vkLp.specVersion),
                    VulkanVersion.fromUint(vkLp.implementationVersion),
                    fromStringz(&vkLp.description[0]).idup,
                );
            })
            .array;
}

VulkanExtensionProperties[] loadDeviceExtensions(VulkanPhysicalDevice pd, in string layerName=null)
{
    import std.string : toStringz;

    const(char)* layer;
    if (layerName.length) {
        layer = toStringz(layerName);
    }

    uint count;
    vulkanEnforce(
        pd.cmds.enumerateDeviceExtensionProperties(pd.vk, layer, &count, null),
        "Could not retrieve Vulkan device extensions"
    );
    if (!count) return[];

    auto vkExts = new VkExtensionProperties[count];
    vulkanEnforce(
        pd.cmds.enumerateDeviceExtensionProperties(pd.vk, layer, &count, &vkExts[0]),
        "Could not retrieve Vulkan device extensions"
    );

    import std.algorithm : map;
    import std.array : array;
    import std.string : fromStringz;

    return vkExts
            .map!((ref VkExtensionProperties vkExt) {
                return VulkanExtensionProperties(
                    fromStringz(&vkExt.extensionName[0]).idup,
                    VulkanVersion.fromUint(vkExt.specVersion)
                );
            })
            .array;
}

class VulkanObj(VkType)
{
    this (VkType vk) {
        _vk = vk;
    }

    final @property VkType vk() {
        return _vk;
    }

    private VkType _vk;
}

class VulkanInstObj(VkType) : Disposable
{
    this (VkType vk, VulkanInstance inst)
    {
        _vk = vk;
        _inst = inst;
        _inst.retain();
    }

    override void dispose() {
        _inst.release();
        _inst = null;
    }

    final @property VkType vk() {
        return _vk;
    }

    final @property VulkanInstance inst() {
        return _inst;
    }

    final @property VkInstance vkInst() {
        return _inst.vk;
    }

    private VkType _vk;
    private VulkanInstance _inst;
}

final class VulkanInstance : VulkanObj!(VkInstance), Instance
{
    mixin(atomicRcCode);

    this(VkInstance vk) {
        super(vk);
        _cmds = new VkInstanceCmds(vk, _globCmds);
    }

    override void dispose() {
        cmds.destroyInstance(vk, null);
    }

    override @property ApiProps apiProps() {
        return vulkanApiProps;
    }

    @property VkInstanceCmds cmds() {
        return _cmds;
    }

    override PhysicalDevice[] devices()
    {
        import std.array : array, uninitializedArray;
        uint count;
        vulkanEnforce(cmds.enumeratePhysicalDevices(vk, &count, null),
                "Could not enumerate Vulkan devices");
        auto devices = uninitializedArray!(VkPhysicalDevice[])(count);
        vulkanEnforce(cmds.enumeratePhysicalDevices(vk, &count, devices.ptr),
                "Could not enumerate Vulkan devices");

        import std.algorithm : map;
        return devices
            .map!(d => cast(PhysicalDevice)(new VulkanPhysicalDevice(d, this)))
            .array;
    }

    VkInstanceCmds _cmds;
}

final class VulkanPhysicalDevice : PhysicalDevice
{
    mixin(atomicRcCode);

    this(VkPhysicalDevice vk, VulkanInstance inst) {
        _vk = vk;
        _inst = inst;
        _inst.retain();
        _cmds = _inst.cmds;

        cmds.getPhysicalDeviceProperties(_vk, &_vkProps);

        _availableLayers = loadDeviceLayers(this);
        _availableExtensions = loadDeviceExtensions(this);

        import std.algorithm : canFind, map;
        import std.exception : enforce;
        debug {
            foreach (l; lunarGValidationLayers) {
                if (_availableLayers.map!"a.layerName".canFind(l)) {
                    _openLayers ~= l;
                }
            }
        }
        version(GfxOffscreen) {}
        else {
            import gfx.vulkan.wsi : swapChainExtension;
            enforce(_availableExtensions.map!"a.extensionName".canFind(swapChainExtension));
            _openExtensions ~= swapChainExtension;
        }
    }

    override void dispose() {
        _inst.release();
        _inst = null;
    }


    @property VkPhysicalDevice vk() {
        return _vk;
    }

    @property VkInstanceCmds cmds() {
        return _cmds;
    }

    override @property string name() {
        import std.string : fromStringz;
        return fromStringz(_vkProps.deviceName.ptr).idup;
    }
    override @property DeviceType type() {
        return devTypeToGfx(_vkProps.deviceType);
    }
    override @property DeviceFeatures features() {
        import std.algorithm : canFind, map;
        import gfx.vulkan.wsi : swapChainExtension;

        VkPhysicalDeviceFeatures vkFeats;
        cmds.getPhysicalDeviceFeatures(vk, &vkFeats);

        DeviceFeatures features;
        features.anisotropy = vkFeats.samplerAnisotropy == VK_TRUE;
        features.presentation = vulkanDeviceExtensions(this)
                .map!(e => e.extensionName)
                .canFind(swapChainExtension);
        return features;
    }
    override @property DeviceLimits limits() {
        import gfx.graal.pipeline : ShaderLanguage;
        return DeviceLimits(ShaderLanguage.spirV);
    }

    override @property MemoryProperties memoryProperties()
    {
        VkPhysicalDeviceMemoryProperties vkProps=void;
        cmds.getPhysicalDeviceMemoryProperties(_vk, &vkProps);

        MemoryProperties props;

        foreach(i; 0 .. vkProps.memoryHeapCount) {
            const vkHeap = vkProps.memoryHeaps[i];
            props.heaps ~= MemoryHeap(
                cast(size_t)vkHeap.size, cast(MemProps)0, (vkHeap.flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) != 0
            );
        }
        foreach(i; 0 .. vkProps.memoryTypeCount) {
            const vkMemType = vkProps.memoryTypes[i];
            const type = MemoryType(
                i, vkMemType.heapIndex, props.heaps[vkMemType.heapIndex].size,
                memPropsToGfx(vkMemType.propertyFlags)
            );
            props.types ~= type;
            props.heaps[i].props |= type.props;
        }

        return props;
    }

    override @property QueueFamily[] queueFamilies()
    {
        import std.array : array, uninitializedArray;
        uint count;
        cmds.getPhysicalDeviceQueueFamilyProperties(_vk, &count, null);

        auto vkQueueFams = uninitializedArray!(VkQueueFamilyProperties[])(count);
        cmds.getPhysicalDeviceQueueFamilyProperties(_vk, &count, vkQueueFams.ptr);

        import std.algorithm : map;
        return vkQueueFams.map!(vk => QueueFamily(
            queueCapToGfx(vk.queueFlags), vk.queueCount
        )).array;
    }

    override FormatProperties formatProperties(in Format format)
    {
        VkFormatProperties vkFp;
        cmds.getPhysicalDeviceFormatProperties(_vk, format.toVk(), &vkFp);

        return FormatProperties(
            vkFp.linearTilingFeatures.toGfx(),
            vkFp.optimalTilingFeatures.toGfx(),
            vkFp.bufferFeatures.toGfx(),
        );
    }

    override bool supportsSurface(uint queueFamilyIndex, Surface graalSurface) {
        auto surf = enforce(
            cast(VulkanSurface)graalSurface,
            "Did not pass a Vulkan surface"
        );
        VkBool32 supported;
        vulkanEnforce(
            cmds.getPhysicalDeviceSurfaceSupportKHR(vk, queueFamilyIndex, surf.vk, &supported),
            "Could not query vulkan surface support"
        );
        return supported != VK_FALSE;
    }

    override SurfaceCaps surfaceCaps(Surface graalSurface) {
        auto surf = enforce(
            cast(VulkanSurface)graalSurface,
            "Did not pass a Vulkan surface"
        );
        VkSurfaceCapabilitiesKHR vkSc;
        vulkanEnforce(
            cmds.getPhysicalDeviceSurfaceCapabilitiesKHR(vk, surf.vk, &vkSc),
            "Could not query vulkan surface capabilities"
        );
        return vkSc.toGfx();
    }

    override Format[] surfaceFormats(Surface graalSurface) {
        auto surf = enforce(
            cast(VulkanSurface)graalSurface,
            "Did not pass a Vulkan surface"
        );

        uint count;
        vulkanEnforce(
            cmds.getPhysicalDeviceSurfaceFormatsKHR(vk, surf.vk, &count, null),
            "Could not query vulkan surface formats"
        );
        auto vkSf = new VkSurfaceFormatKHR[count];
        vulkanEnforce(
            cmds.getPhysicalDeviceSurfaceFormatsKHR(vk, surf.vk, &count, &vkSf[0]),
            "Could not query vulkan surface formats"
        );

        import std.algorithm : filter, map;
        import std.array : array;
        return vkSf
                .filter!(sf => sf.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
                .map!(sf => sf.format.toGfx())
                .array;
    }

    override PresentMode[] surfacePresentModes(Surface graalSurface) {
        auto surf = enforce(
            cast(VulkanSurface)graalSurface,
            "Did not pass a Vulkan surface"
        );

        uint count;
        vulkanEnforce(
            cmds.getPhysicalDeviceSurfacePresentModesKHR(vk, surf.vk, &count, null),
            "Could not query vulkan surface present modes"
        );
        auto vkPms = new VkPresentModeKHR[count];
        vulkanEnforce(
            cmds.getPhysicalDeviceSurfacePresentModesKHR(vk, surf.vk, &count, &vkPms[0]),
            "Could not query vulkan surface present modes"
        );

        import std.algorithm : filter, map;
        import std.array : array;
        return vkPms
                .filter!(pm => pm.hasGfxSupport)
                .map!(pm => pm.toGfx())
                .array;
    }

    override Device open(in QueueRequest[] queues, in DeviceFeatures features=DeviceFeatures.all)
    {
        import std.algorithm : filter, map, sort;
        import std.array : array;
        import std.exception : enforce;
        import std.string : toStringz;
        import gfx.vulkan.wsi : swapChainExtension;

        if (!queues.length) {
            return null;
        }

        const qcis = queues.map!((const(QueueRequest) r) {
            VkDeviceQueueCreateInfo qci;
            qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
            qci.queueFamilyIndex = r.familyIndex;
            qci.queueCount = cast(uint)r.priorities.length;
            qci.pQueuePriorities = r.priorities.ptr;
            return qci;
        }).array;

        const layers = _openLayers.map!toStringz.array;
        const extensions = _openExtensions
                .filter!(e => e != swapChainExtension || features.presentation)
                .map!toStringz.array;
        VkPhysicalDeviceFeatures vkFeats;
        vkFeats.samplerAnisotropy = features.anisotropy ? VK_TRUE : VK_FALSE;

        VkDeviceCreateInfo ci;
        ci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        ci.queueCreateInfoCount = cast(uint)qcis.length;
        ci.pQueueCreateInfos = qcis.ptr;
        ci.enabledLayerCount = cast(uint)layers.length;
        ci.ppEnabledLayerNames = &layers[0];
        ci.enabledExtensionCount = cast(uint)extensions.length;
        ci.ppEnabledExtensionNames = &extensions[0];
        ci.pEnabledFeatures = &vkFeats;

        VkDevice vkDev;
        vulkanEnforce(cmds.createDevice(_vk, &ci, null, &vkDev),
                "Vulkan device creation failed");

        return new VulkanDevice(vkDev, this);
    }

    private VkPhysicalDevice _vk;
    private VkPhysicalDeviceProperties _vkProps;
    private VulkanInstance _inst;

    private VkInstanceCmds _cmds;

    private VulkanLayerProperties[] _availableLayers;
    private VulkanExtensionProperties[] _availableExtensions;

    private string[] _openLayers;
    private string[] _openExtensions;
}

DeviceType devTypeToGfx(in VkPhysicalDeviceType vkType)
{
    switch (vkType) {
    case VK_PHYSICAL_DEVICE_TYPE_OTHER:
        return DeviceType.other;
    case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:
        return DeviceType.integratedGpu;
    case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:
        return DeviceType.discreteGpu;
    case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:
        return DeviceType.virtualGpu;
    case VK_PHYSICAL_DEVICE_TYPE_CPU:
        return DeviceType.cpu;
    default:
        assert(false, "unexpected vulkan device type constant");
    }
}
