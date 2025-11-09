package platform

import win32 "core:sys/windows"
import "core:fmt"
import "core:log"
import "core:dynlib"
import vk "vendor:vulkan"

gRunning: bool = true

main :: proc()
{
  init_vulkan()
//  window, ok := init_window(800, 600)
//  if !ok do return
//  for gRunning
//  {
//    message: win32.MSG
//    for win32.PeekMessageW(&message, nil, 0, 0, win32.PM_REMOVE)
//    {
//      if message.message == win32.WM_QUIT do gRunning = false
//      win32.TranslateMessage(&message)
//      win32.DispatchMessageW(&message)
//    }
//  }
}

init_window :: proc(width, height: i32) -> (window: win32.HWND, ok: bool)
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
    log.log(log.Level.Error, "Registering the class failed!")
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

init_vulkan :: proc() -> (instance: vk.Instance, ok: bool)
{
  // NOTE: loading dlls on windows is fucked up apparently
  // TODO: unhardcode this string
  vulkanLoader, loaded := dynlib.load_library("C:/Windows/System32/vulkan-1.dll")
  defer dynlib.unload_library(vulkanLoader)
  if !loaded
  {
    log.log(log.Level.Error, dynlib.last_error())
    return
  }
  ptr, found := dynlib.symbol_address(vulkanLoader, "vkGetInstanceProcAddr")
  if !found
  {
    log.log(log.Level.Error, dynlib.last_error())
    return
  }
  vkGetInstanceProcAddr := ptr
  vk.load_proc_addresses_global(vkGetInstanceProcAddr)
  extensionCount : u32
  vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, nil)
  properties := make_slice([]vk.ExtensionProperties, cast(int)extensionCount, context.temp_allocator)
  vk.EnumerateInstanceExtensionProperties(nil, &extensionCount, raw_data(properties))
  // just enable all of them baby!
  // TODO: figure out how to add only necessery extensions
  extension_names := make_slice([]cstring, cast(int)extensionCount, context.temp_allocator)
  for i : u32 = 0; i < extensionCount; i += 1 
  {
    extension_names[i] = cstring(raw_data(properties[i].extensionName[:]))
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
    enabledExtensionCount = extensionCount,
    ppEnabledExtensionNames = raw_data(extension_names)
  }
  vulkan_instance: vk.Instance
  result := vk.CreateInstance(&createInfo, nil, &vulkan_instance)
  if (result != vk.Result.SUCCESS)
  {
    log.log(log.Level.Error, "could not create instance!")
    return nil, false
  }
  return instance, true
}
