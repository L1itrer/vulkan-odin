package platform

import win32 "core:sys/windows"
import "core:fmt"
import "core:dynlib"
import "core:strings"
import vk "vendor:vulkan"
import "vendor:glfw"

gRunning: bool = true


main :: proc()
{
  vulkanLoader := win32.LoadLibraryW(win32.utf8_to_wstring_alloc("vulkan-1.dll"))
  if vulkanLoader == nil
  {
    err := win32.GetLastError()
    fmt.println("Could not locate vulkan dll: ", err)
    return
  }
  defer win32.FreeLibrary(vulkanLoader)
  getProcAddrName := cstring("vkGetInstanceProcAddr")
  vkGetInstanceProcAddr := win32.GetProcAddress(vulkanLoader, getProcAddrName)
  if vkGetInstanceProcAddr == nil
  {
    err := win32.GetLastError()
    fmt.printfln("Could not locate %v: %v", getProcAddrName,err)
    return
  }
  vk, ok := init_vulkan(vkGetInstanceProcAddr)
  defer vulkan_release(vk) 
  if !ok
  {
    return
  }
  window, ok_wnd := win32_init_window(800, 600)
  if !ok_wnd do return
  free_all(context.temp_allocator)
  for gRunning
  {
    message: win32.MSG
    for win32.PeekMessageW(&message, nil, 0, 0, win32.PM_REMOVE)
    {
      if message.message == win32.WM_QUIT do gRunning = false
      win32.TranslateMessage(&message)
      win32.DispatchMessageW(&message)
    }
    free_all(context.temp_allocator)
  }
}

win32_init_window :: proc(width, height: i32) -> (window: win32.HWND, ok: bool)
{
  instance := cast(win32.HINSTANCE)win32.GetModuleHandleW(nil)
  windowClass: win32.WNDCLASSW = {
    style = win32.CS_HREDRAW | win32.CS_VREDRAW,
    lpfnWndProc = win32_window_proc,
    hInstance = instance,
    lpszClassName = win32.utf8_to_wstring("VulkanTriangleClass")
  }
  if !bool(win32.RegisterClassW(&windowClass))
  {
    fmt.eprintfln("Registering the class failed!")
    return nil, false
  }
  result_window := win32.CreateWindowExW(
    dwExStyle = 0,
    lpClassName = windowClass.lpszClassName,
    lpWindowName = win32.utf8_to_wstring("Vulkan triangle"),
    dwStyle = win32.WS_OVERLAPPED | win32.WS_VISIBLE | win32.WS_SYSMENU |
      win32.WS_MINIMIZEBOX | win32.WS_MINIMIZEBOX | win32.WS_CAPTION,
    X = win32.CW_USEDEFAULT, Y = win32.CW_USEDEFAULT,
    nWidth = width, nHeight = height,
    hWndParent = nil, hMenu = nil, hInstance = instance, lpParam = nil
  )
  if result_window == nil
  {
    return nil, false
  }
  return result_window, true
}

win32_window_proc :: proc "stdcall" (windowHandle: win32.HWND, message: u32, wParam: uintptr, lParam: int) -> win32.LRESULT
{
  result : win32.LRESULT
  switch message
  {
    case win32.WM_DESTROY, win32.WM_CLOSE:
    {
      gRunning = false
    }
    case win32.WM_SIZE:
    {
    }
    case win32.WM_ACTIVATEAPP:
    {
    }

    case: 
    {
       result = win32.DefWindowProcW(windowHandle, message, wParam, lParam)
    }
  }
  return result
}

when ODIN_DEBUG 
{
  USE_VALIDATION_LAYERS :: true
}
else
{
  USE_VALIDATION_LAYERS :: false
}

VulkanHandles :: struct{
  instance: vk.Instance,
  device: vk.Device,
  graphicsQueue: vk.Queue,
}

init_vulkan :: proc(vkGetInstanceProcAddr: rawptr) -> (handles: VulkanHandles, ok: bool)
{
  vk.load_proc_addresses_global(vkGetInstanceProcAddr)
  extensionCount : u32
  vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, nil)
  properties := make_slice([]vk.ExtensionProperties, cast(int)extensionCount, context.temp_allocator)
  vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, raw_data(properties))
  // TODO: save information about what extensions are available
  extensionNames := make_slice([]cstring, cast(int)extensionCount, context.temp_allocator)

  for i : u32 = 0; i < extensionCount; i += 1 
  {
    extensionNames[i] = cstring(raw_data(properties[i].extensionName[:]))
  }

  fmt.printfln("Available extensions (count: %v)", extensionCount)
  for ext, i in extensionNames
  {
    fmt.printfln("%v: %v", i, ext)
  }

  contains :: proc(cstr_array: []cstring, looked_for: string) -> bool
  {
    str := looked_for
    for cstr in cstr_array
    {
      curr_str := string(cstr)
      if strings.compare(str, curr_str) == 0 do return true
    }
    return false
  }

  requiredExtensions :: []cstring{
    "VK_KHR_surface", 
    "VK_KHR_win32_surface",
  }
  valid := true
  for requiredExtension in requiredExtensions
  {
    if !contains(extensionNames, string(requiredExtension))
    {
      fmt.eprintfln("Device does support required extension: %v", requiredExtension)
      valid = false
    }
  }
  if !valid do return {}, false

  valLayerCount: u32
  vk.EnumerateInstanceLayerProperties(&valLayerCount, nil)
  validationLayerProperties := make_slice([]vk.LayerProperties, cast(int)valLayerCount, context.temp_allocator)
  vk.EnumerateInstanceLayerProperties(&valLayerCount, raw_data(validationLayerProperties))
  valLayerNames := make_slice([]cstring, cast(int)valLayerCount, context.temp_allocator)
  for i : u32 = 0; i < valLayerCount; i += 1 
  {
    valLayerNames[i] = cstring(raw_data(validationLayerProperties[i].layerName[:]))
  }
  fmt.printfln("Available validation layers (count: %v)", valLayerCount)
  for ext, i in valLayerNames
  {
    fmt.printfln("%v: %v", i, ext)
  }

  when USE_VALIDATION_LAYERS
  {
    requiredValLayers :: [?]string{
      "VK_LAYER_KHRONOS_validation"
    }
    for requiredValLayer in requiredValLayers
    {
      if !contains(valLayerNames, requiredValLayer)
      {
        valid = false
        fmt.eprintfln("Device does support required validation layer: %v", requiredValLayer)
      }
    }
    if !valid do return {}, false
  }

  appInfo: vk.ApplicationInfo = {
    sType = vk.StructureType.APPLICATION_INFO,
    pApplicationName = "Hello triangle",
    applicationVersion = vk.MAKE_VERSION(1, 0, 0),
    pEngineName = "No engine",
    engineVersion = vk.MAKE_VERSION(1, 0, 0),
    apiVersion = vk.API_VERSION_1_0
  }
  createInfo: vk.InstanceCreateInfo = {
    sType = vk.StructureType.INSTANCE_CREATE_INFO,
    pApplicationInfo = &appInfo,
    enabledExtensionCount = cast(u32)len(extensionNames),
    ppEnabledExtensionNames = raw_data(extensionNames)
  }
  when USE_VALIDATION_LAYERS
  {
    createInfo.enabledLayerCount = valLayerCount
    createInfo.ppEnabledLayerNames = raw_data(valLayerNames)
  }
  // TODO: setup non-default debug message printing

  vulkanInstance: vk.Instance
  result := vk.CreateInstance(&createInfo, nil, &vulkanInstance)
  handles.instance = vulkanInstance
  if (result != vk.Result.SUCCESS)
  {
    fmt.eprintfln("could not create instance!")
    return {}, false
  }
  vk.load_proc_addresses_instance(vulkanInstance)
  fmt.println("Vulkan procedure loading succsessful")

  // device selection
  deviceCount: u32
  vulkanDevice: vk.PhysicalDevice
  vk.EnumeratePhysicalDevices(vulkanInstance, &deviceCount, nil)
  if deviceCount == 0
  {
    fmt.eprintfln("This mashine has no suitable vulkan devices")
    return handles, false
  }

  devices := make_slice([]vk.PhysicalDevice, cast(int)deviceCount, context.temp_allocator)
  vk.EnumeratePhysicalDevices(vulkanInstance, &deviceCount, raw_data(devices))
  for device, i in devices
  {
    if device_suitable(device)
    {
      fmt.println("Found a suitable vulkan device")
      vulkanDevice = device
      break
    }
  }
  if vulkanDevice == nil
  {
    fmt.eprintfln("This mashine has no suitable vulkan devices")
    return handles, false
  }
  indicies := queue_families_find(vulkanDevice)
  deviceFeatures := vk.PhysicalDeviceFeatures{}
  queuePriority : f32 = 1.0
  queueCreateInfo: vk.DeviceQueueCreateInfo = {
      sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
      queueFamilyIndex = indicies.graphicsFamily,
      queueCount = 1,
      pQueuePriorities = &queuePriority
  }
  deviceCreateInfo := vk.DeviceCreateInfo {
    sType = vk.StructureType.DEVICE_CREATE_INFO,
    pQueueCreateInfos = &queueCreateInfo,
    queueCreateInfoCount = 1,
    pEnabledFeatures = &deviceFeatures,
  }
  when USE_VALIDATION_LAYERS
  {
    deviceCreateInfo.enabledLayerCount = valLayerCount
    deviceCreateInfo.ppEnabledLayerNames = raw_data(valLayerNames)
  }

  logicalDevice: vk.Device
  result = vk.CreateDevice(vulkanDevice, &deviceCreateInfo, nil, &logicalDevice)
  if result != vk.Result.SUCCESS
  {
    fmt.eprintln("Could not instantiate logical device")
    return handles, false
  }
  handles.device = logicalDevice
  vk.GetDeviceQueue(handles.device, indicies.graphicsFamily, 0, &handles.graphicsQueue)

  return handles, true
}

vulkan_release :: proc(handles: VulkanHandles)
{
  vk.DestroyDevice(handles.device, nil)
  vk.DestroyInstance(handles.instance, nil)
  fmt.println("vulkan destroyed")
}

device_suitable :: proc(device: vk.PhysicalDevice) -> bool
{
  familyIndex, ok := queue_families_find(device)
  return ok
}

queue_families_find :: proc(device: vk.PhysicalDevice) -> (QueueFamilyIndecies, bool) #optional_ok
{
  queueFamilyCount: u32 = ---
  queueFamilyIndex: QueueFamilyIndecies
  vk.GetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nil)
  families := make_slice([]vk.QueueFamilyProperties, cast(int)queueFamilyCount, context.temp_allocator)
  vk.GetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, raw_data(families[:]))
  i: u32
  for family in families
  {
    if vk.QueueFlag.GRAPHICS in family.queueFlags
    {
      queueFamilyIndex.graphicsFamily = i
      return queueFamilyIndex, true
    }
    i += 1
  }
  return queueFamilyIndex, false
}

QueueFamilyIndecies :: struct
{
  graphicsFamily: u32
}
